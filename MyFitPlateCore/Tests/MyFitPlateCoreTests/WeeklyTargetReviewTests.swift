import XCTest
@testable import MyFitPlateCore

@MainActor
final class WeeklyTargetReviewTests: XCTestCase {
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: SettingsRepositoryProtocol?
    private var auth: MockAuthService!
    private var repository: MockSettingsRepository!
    private var owner = ""
    private var directory: URL!
    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.settingsRepository
        owner = "weekly-review-\(UUID().uuidString)"
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockSettingsRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.settingsRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        if let key = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner) { UserDefaults.standard.removeObject(forKey: key) }
        DIContainer.shared.authService = previousAuth; DIContainer.shared.settingsRepository = previousRepository
        super.tearDown()
    }
    private func model() -> GoalSettings {
        let goals = GoalSettings(isEditingPreview: true); goals.activateAccount(owner)
        goals.calorieGoalMethod = .dynamicTDEE; goals.calories = 2_100; goals.waterGoal = 91
        goals.weightHistory = [("protected", Date(), 180)]
        return goals
    }
    private func proposal(_ goals: GoalSettings, now: Date = Date(), estimated: Double = 2_500) throws -> WeeklyTargetProposal {
        let evidence = AdaptiveGoalService.ExpenditureSnapshot(recentWeighInCount: 21, recentLogCount: 21,
            last21DaysCalorieAverage: 2_200, weightChangeRatePerDay: -0.08, calculatedTDEE: estimated,
            dataConfidence: .high, validLogCount: 21, recentWorkoutCount: 0, isActionable: true)
        return try WeeklyTargetProposal(userID: owner, before: goals.makeGoalEditorDraft(), evidence: evidence,
                                        evidenceFingerprint: "intake-and-weight-revision", now: now)
    }

    func testChangedEvidenceAccountAndExactAdaptiveTargetRequireNewReview() throws {
        let goals = model(); let frozen = try proposal(goals); let now = frozen.createdAt
        XCTAssertNoThrow(try frozen.validate(userID: owner, current: goals.makeGoalEditorDraft(), evidenceFingerprint: frozen.evidenceFingerprint, now: now))
        XCTAssertThrowsError(try frozen.validate(userID: "another", current: frozen.before, evidenceFingerprint: frozen.evidenceFingerprint, now: now))
        XCTAssertThrowsError(try frozen.validate(userID: owner, current: frozen.before, evidenceFingerprint: "corrected-input", now: now))
        var changed = frozen.before; changed.calories += 50
        XCTAssertThrowsError(try frozen.validate(userID: owner, current: changed, evidenceFingerprint: frozen.evidenceFingerprint, now: now))
        XCTAssertThrowsError(try frozen.validate(userID: owner, current: frozen.before, evidenceFingerprint: frozen.evidenceFingerprint, now: now.addingTimeInterval(1_801)))
        XCTAssertEqual(goals.calories, 2_100)
    }

    func testFailureRetainsTargetAndCheckpointThenExactDecisionRetries() async throws {
        let goals = model(); let frozen = try proposal(goals)
        repository.mockFetchUserGoalsResult = frozen.before.payload(updatedAt: Date())
        let store = WeeklyTargetReviewStore(store: EditorDraftStore(directory: directory))
        var checkpoint = WeeklyTargetCheckpoint(proposal: frozen)
        let decision = try checkpoint.submit(.accept)
        try store.save(checkpoint, currentUserID: owner)
        repository.saveUserGoalsError = URLError(.notConnectedToInternet)
        do { _ = try await goals.saveWeeklyTargetDecision(decision); XCTFail("Expected offline failure") } catch {}
        XCTAssertEqual(goals.calories, 2_100); XCTAssertNil(goals.lastCheckInDate)
        XCTAssertEqual(try store.load(userID: owner)?.submittedDecision, decision)
        XCTAssertTrue(try store.history(userID: owner).isEmpty)
        repository.saveUserGoalsError = nil
        let accepted = try await goals.saveWeeklyTargetDecision(decision)
        try store.finish(accepted, currentUserID: owner)
        XCTAssertEqual(goals.calories, frozen.after.calories)
        XCTAssertEqual(goals.protein, frozen.after.macros.protein)
        XCTAssertEqual(goals.lastCheckInDate, decision.decidedAt)
        XCTAssertEqual(goals.waterGoal, 91); XCTAssertEqual(goals.weightHistory.map(\.id), ["protected"])
        XCTAssertNil(try store.load(userID: owner))
        XCTAssertEqual(try store.history(userID: owner), [decision])
        XCTAssertEqual(repository.weeklyTargetCommitCount, 1)
    }

    func testLostCommitResponseRecoversReceiptWithoutApplyingTargetsTwiceOrRollingBackLaterEdit() async throws {
        let goals = model(); let frozen = try proposal(goals)
        repository.mockFetchUserGoalsResult = frozen.before.payload(updatedAt: Date())
        let decision = WeeklyTargetDecision(proposal: frozen, choice: .accept)
        repository.weeklyDecisionErrorAfterCommit = URLError(.timedOut)
        do { _ = try await goals.saveWeeklyTargetDecision(decision); XCTFail("Expected lost response") } catch {}
        XCTAssertEqual(repository.weeklyTargetCommitCount, 1)
        XCTAssertEqual(goals.calories, frozen.before.calories)
        repository.weeklyDecisionErrorAfterCommit = nil
        _ = try await goals.saveWeeklyTargetDecision(decision)
        XCTAssertEqual(goals.calories, frozen.after.calories)
        goals.calories = 2_900
        _ = try await goals.saveWeeklyTargetDecision(decision)
        XCTAssertEqual(goals.calories, 2_900, "An old receipt cannot replace a later target")
        XCTAssertEqual(repository.weeklyTargetCommitCount, 1)
    }

    func testKeepAndDeferRecordDifferentOutcomesWithoutChangingTargets() async throws {
        for choice in [WeeklyTargetDecision.Choice.keep, .deferReview] {
            let goals = model(); let frozen = try proposal(goals)
            let decision = WeeklyTargetDecision(proposal: frozen, choice: choice)
            _ = try await goals.saveWeeklyTargetDecision(decision)
            XCTAssertEqual(goals.makeGoalEditorDraft(), frozen.before)
            XCTAssertEqual(goals.lastCheckInDate, choice == .keep ? decision.decidedAt : nil)
            XCTAssertEqual(decision.profilePatch.isEmpty, choice == .deferReview)
            XCTAssertEqual(decision.nextEligibleDate == nil, choice == .deferReview)
        }
    }

    func testPendingDecisionSurvivesRelaunchAndCannotSwitchChoiceOrAccount() throws {
        let frozen = try proposal(model())
        var checkpoint = WeeklyTargetCheckpoint(proposal: frozen)
        let decision = try checkpoint.submit(.keep)
        let store = WeeklyTargetReviewStore(store: EditorDraftStore(directory: directory))
        try store.save(checkpoint, currentUserID: owner)
        let reopened = WeeklyTargetReviewStore(store: EditorDraftStore(directory: directory))
        var recovered = try XCTUnwrap(reopened.load(userID: owner))
        XCTAssertEqual(try recovered.submit(.keep, now: Date().addingTimeInterval(90)), decision)
        XCTAssertThrowsError(try recovered.submit(.accept))
        XCTAssertThrowsError(try reopened.save(recovered, currentUserID: "another"))
        XCTAssertNil(try reopened.load(userID: "another"))
        XCTAssertThrowsError(try reopened.save(WeeklyTargetCheckpoint(proposal: proposal(model())), currentUserID: owner))
    }

    func testLateAccountSwitchCannotPublishOrCommitDecision() async throws {
        let goals = model(); let frozen = try proposal(goals)
        repository.beforeNextGoalEditorCommit = { [auth] in auth?.currentUserID = "another" }
        do {
            _ = try await goals.saveWeeklyTargetDecision(WeeklyTargetDecision(proposal: frozen, choice: .accept))
            XCTFail("Expected account guard")
        } catch { XCTAssertEqual(error as? WeeklyTargetReviewError, .accountChanged) }
        XCTAssertEqual(goals.calories, frozen.before.calories)
        XCTAssertEqual(repository.weeklyTargetCommitCount, 0)
    }

    func testSixWeekDecisionHistoryPreservesExactIntentAndPriorTargets() async throws {
        let goals = model(); let store = WeeklyTargetReviewStore(store: EditorDraftStore(directory: directory))
        let start = Date().addingTimeInterval(-35 * 86_400)
        let choices: [WeeklyTargetDecision.Choice] = [.accept, .keep, .deferReview, .accept, .keep, .accept]
        var expected: [WeeklyTargetDecision] = []
        for (week, choice) in choices.enumerated() {
            let time = Calendar.current.date(byAdding: .day, value: week * 7, to: start)!
            repository.weeklyDecisionNow = { time }
            let frozen = try proposal(goals, now: time, estimated: 2_500 + Double(week) * 30)
            repository.mockFetchUserGoalsResult = frozen.before.payload(updatedAt: time)
            var checkpoint = WeeklyTargetCheckpoint(proposal: frozen)
            let decision = try checkpoint.submit(choice, now: time)
            try store.save(checkpoint, currentUserID: owner)
            let accepted = try await goals.saveWeeklyTargetDecision(decision)
            try store.finish(accepted, currentUserID: owner)
            expected.insert(decision, at: 0)
            XCTAssertEqual(goals.makeGoalEditorDraft(), decision.effectiveTargets)
        }
        XCTAssertEqual(try store.history(userID: owner), expected)
        XCTAssertEqual(repository.weeklyTargetCommitCount, 6)
        XCTAssertEqual(expected.map(\.choice), Array(choices.reversed()))
        XCTAssertEqual(goals.weightHistory.map(\.id), ["protected"])
    }
}
