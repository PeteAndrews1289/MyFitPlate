import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
@testable import MyFitPlate

private final class FoodPreferencesEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}

private final class FoodPreferencesEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("food-preferences-test-") ? FoodPreferencesEmulatorCheck() : nil
    }
}

/// Synthetic named Firebase apps, localhost Auth/Firestore only. Opt in using
/// MYFITPLATE_EMULATOR_TESTS=YES; these tests never use the production Firebase app.
final class FoodPreferencesRepositoryTests: XCTestCase {
    private var apps: [FirebaseApp] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(FoodPreferencesEmulatorCheckFactory())
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
        let name = "food-preferences-test-\(UUID())"
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

    func testCheckedPreferenceTransactionPreservesCalorieTargetsHistoryAndUnrelatedFields() async throws {
        let client = client()
        let uid = try await client.auth.signInAnonymously().user.uid
        let repository = FirestoreSettingsRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        let reference = client.db.collection("users").document(uid)
        let baseline = FoodPreferencesDraft.defaults
        var draft = baseline; draft.proteins = ["Tempeh", "Fish"]; draft.cuisines = ["Mexican"]
        var goals: [String: Any] = baseline.fields
        goals["calories"] = 2_137; goals["protein"] = 143; goals["waterGoal"] = 93
        try await reference.setData(["goals": goals, "calories": 2_137, "calorieGoalMethod": "custom", "unrelated": "keep"])
        let history = reference.collection("dailyLogs").document("2026-10-28")
        try await history.setData(["meals": [], "goalCalories": 1_987])
        try await repository.saveFoodPreferencesChange(userID: uid, baseline: baseline, draft: draft)
        // Same accepted proposal can be retried after an acknowledgement was lost.
        try await repository.saveFoodPreferencesChange(userID: uid, baseline: baseline, draft: draft)
        let saved = try await reference.getDocument(source: .server).data()
        let savedGoals = try XCTUnwrap(saved?["goals"] as? [String: Any])
        XCTAssertEqual(savedGoals["suggestionProteins"] as? [String], ["Tempeh", "Fish"])
        XCTAssertEqual(savedGoals["suggestionCuisines"] as? [String], ["Mexican"])
        XCTAssertEqual(savedGoals["calories"] as? Int, 2_137)
        XCTAssertEqual(savedGoals["protein"] as? Int, 143)
        XCTAssertEqual(savedGoals["waterGoal"] as? Int, 93)
        XCTAssertEqual(saved?["calories"] as? Int, 2_137)
        XCTAssertEqual(saved?["calorieGoalMethod"] as? String, "custom")
        XCTAssertEqual(saved?["unrelated"] as? String, "keep")
        XCTAssertNil(saved?["goals.suggestionProteins"], "The patch must address nested fields, not create dotted top-level keys")
        let oldLog = try await history.getDocument(source: .server).data()
        XCTAssertEqual(oldLog?["goalCalories"] as? Int, 1_987)
    }

    func testStalePreferenceRevisionAndWrongOwnerCannotOverwriteServerChoices() async throws {
        let client = client()
        let uid = try await client.auth.signInAnonymously().user.uid
        let reference = client.db.collection("users").document(uid)
        let baseline = FoodPreferencesDraft.defaults
        var current = baseline; current.proteins = ["Eggs"]
        try await reference.setData(["goals": current.fields])
        var proposal = baseline; proposal.cuisines = ["Italian"]
        let repository = FirestoreSettingsRepository(db: client.db, currentUserID: { client.auth.currentUser?.uid })
        do {
            try await repository.saveFoodPreferencesChange(userID: uid, baseline: baseline, draft: proposal)
            XCTFail("A stale revision must be rejected")
        } catch { }
        do {
            try await repository.saveFoodPreferencesChange(userID: "other-account", baseline: current, draft: proposal)
            XCTFail("The active account must match the captured owner")
        } catch { }
        let saved = try await reference.getDocument(source: .server).data()
        XCTAssertTrue(current.matchesPersistedPreferences(try XCTUnwrap(saved)))
    }
}
