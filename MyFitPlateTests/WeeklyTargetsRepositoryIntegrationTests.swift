import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
@testable import MyFitPlate

private final class WeeklyTargetsEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}

private final class WeeklyTargetsEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("weekly-targets-test-") ? WeeklyTargetsEmulatorCheck() : nil
    }
}

/// Synthetic named Firebase apps, localhost Auth/Firestore only. Opt in using
/// MYFITPLATE_EMULATOR_TESTS=YES; these tests never use the production Firebase app.
final class WeeklyTargetsRepositoryTests: XCTestCase {
    private var apps: [FirebaseApp] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(WeeklyTargetsEmulatorCheckFactory())
    }

    override func tearDown() {
        for app in apps { try? Auth.auth(app: app).signOut(); app.delete { _ in } }
        apps = []
        super.tearDown()
    }

    private func client() -> (auth: Auth, db: Firestore) {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "weekly-targets-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!
        apps.append(app)
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        return (auth, db)
    }

    @MainActor
    private func proposal(userID: String) throws -> WeeklyTargetProposal {
        let goals = GoalSettings(isEditingPreview: true)
        goals.calorieGoalMethod = .dynamicTDEE; goals.calories = 2_100
        let evidence = AdaptiveGoalService.ExpenditureSnapshot(recentWeighInCount: 21, recentLogCount: 21,
            last21DaysCalorieAverage: 2_200, weightChangeRatePerDay: -0.1, calculatedTDEE: 2_550,
            dataConfidence: .high, validLogCount: 21, isActionable: true)
        return try WeeklyTargetProposal(userID: userID, before: goals.makeGoalEditorDraft(), evidence: evidence,
                                        evidenceFingerprint: "local-emulator-reviewed-inputs")
    }

    @MainActor
    func testDecisionAndTargetsCommitTogetherAndExactRetryDoesNotTouchDiaryOrLaterTargets() async throws {
        let client = client()
        let uid = try await client.auth.signInAnonymously().user.uid
        let repository = FirestoreSettingsRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        let frozen = try proposal(userID: uid)
        let decision = WeeklyTargetDecision(proposal: frozen, choice: .accept)
        let profile = client.db.collection("users").document(uid)
        var data = frozen.before.payload(updatedAt: Date())
        var goals = data["goals"] as? [String: Any] ?? [:]
        goals["waterGoal"] = 93; goals["lastCheckInDate"] = Date().addingTimeInterval(-14 * 86_400)
        data["goals"] = goals; data["unrelated"] = "preserve"
        try await profile.setData(data)
        let log = profile.collection("dailyLogs").document("2026-10-01")
        try await log.setData(["goalCalories": 1_987, "meals": []])
        let first = try await repository.saveWeeklyTargetDecision(decision)
        XCTAssertEqual(first, decision)
        try await profile.updateData(["goals.calories": 2_900, "calories": 2_900])
        let replay = try await repository.saveWeeklyTargetDecision(decision)
        XCTAssertEqual(replay, decision)
        let profileAfter = try await profile.getDocument(source: .server).data()
        XCTAssertEqual((profileAfter?["goals"] as? [String: Any])?["calories"] as? Int, 2_900)
        XCTAssertEqual((profileAfter?["goals"] as? [String: Any])?["waterGoal"] as? Int, 93)
        XCTAssertEqual(profileAfter?["unrelated"] as? String, "preserve")
        let oldLog = try await log.getDocument(source: .server).data()
        XCTAssertEqual(oldLog?["goalCalories"] as? Int, 1_987)
        let history = try await repository.fetchWeeklyTargetDecisions(userID: uid)
        XCTAssertEqual(history, [decision])
        let legacy = try await profile.collection("weeklyTargetDecisions").document("legacy-completion").getDocument(source: .server)
        XCTAssertTrue(legacy.exists)
        XCTAssertNil(legacy.data()?["payload"], "Legacy completion must not invent a proposal")
    }

    @MainActor
    func testChangedTargetOrChangedChoiceCannotCreateAnotherReceipt() async throws {
        let client = client()
        let uid = try await client.auth.signInAnonymously().user.uid
        let repository = FirestoreSettingsRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        let frozen = try proposal(userID: uid)
        let profile = client.db.collection("users").document(uid)
        var current = frozen.before; current.calories += 25
        try await profile.setData(current.payload(updatedAt: Date()))
        do {
            _ = try await repository.saveWeeklyTargetDecision(WeeklyTargetDecision(proposal: frozen, choice: .accept))
            XCTFail("Changed adaptive target must reject the old proposal")
        } catch { }
        let rejectedReceipt = try await profile.collection("weeklyTargetDecisions").document(frozen.id.uuidString).getDocument(source: .server)
        XCTAssertFalse(rejectedReceipt.exists)
        try await profile.setData(frozen.before.payload(updatedAt: Date()), merge: true)
        let keep = WeeklyTargetDecision(proposal: frozen, choice: .keep)
        _ = try await repository.saveWeeklyTargetDecision(keep)
        do {
            _ = try await repository.saveWeeklyTargetDecision(WeeklyTargetDecision(proposal: frozen, choice: .accept, now: keep.decidedAt))
            XCTFail("A stable decision ID cannot change intent on retry")
        } catch { }
        let history = try await repository.fetchWeeklyTargetDecisions(userID: uid)
        XCTAssertEqual(history, [keep])
        let saved = try await profile.getDocument(source: .server).data()
        XCTAssertTrue(frozen.matchesPersistedTargets(try XCTUnwrap(saved)))
    }
}
