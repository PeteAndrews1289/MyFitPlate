import XCTest
@testable import MyFitPlateCore

final class RunWorkoutLibraryRevisionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var auth: MockAuthService!

    override func setUp() {
        super.setUp()
        suite = "RunWorkoutLibraryRevisionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        auth = MockAuthService()
        auth.currentUserID = "a"
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func plan(_ name: String = "Track") -> RunWorkoutPlan {
        RunWorkoutPlan(id: "track", name: name, subtitle: "One step", steps: [RunWorkoutStep(id: "work", kind: .hard, title: "Work", goal: .distance(meters: 400))])
    }

    func testLostAcknowledgementReplayKeepsOneRevisionAndCannotOverwriteLaterEdit() throws {
        let first = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        let original = plan()
        let receipt = try first.saveReviewed(original, replacing: nil, operationID: "first", userID: "a")
        let later = plan("Revised")
        _ = try first.saveReviewed(later, replacing: original, operationID: "edit", userID: "a")
        let restarted = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        XCTAssertEqual(try restarted.saveReviewed(original, replacing: nil, operationID: "first", userID: "a"), receipt)
        XCTAssertEqual(restarted.customPlans, [later])
        XCTAssertEqual(restarted.revisions(forPlanID: original.id).map(\.plan), [original, later])
        XCTAssertThrowsError(try restarted.saveReviewed(plan("Stale"), replacing: original, operationID: "stale", userID: "a"))
        XCTAssertThrowsError(try restarted.saveReviewed(later, replacing: original, operationID: "first", userID: "a"))
        XCTAssertEqual(restarted.customPlans, [later])
    }

    func testLegacyMigrationAndArchivePreserveHistoricalRevisionWithoutRestoringDeletedTemplateOnReplay() throws {
        let original = plan()
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.run_workout_plans", userID: "a"))
        defaults.set(try JSONEncoder().encode([original]), forKey: key)
        let store = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        let later = plan("Updated")
        let receipt = try store.saveReviewed(later, replacing: original, operationID: "edit", userID: "a")
        store.deletePlan(id: original.id)
        XCTAssertTrue(store.customPlans.isEmpty)
        XCTAssertEqual(try store.saveReviewed(later, replacing: original, operationID: "edit", userID: "a"), receipt)
        XCTAssertTrue(store.customPlans.isEmpty)
        XCTAssertEqual(store.revisions(forPlanID: original.id).map(\.plan), [original, later])
    }

    func testAccountChangeAndUnreadableLibraryFailClosed() throws {
        let store = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        auth.currentUserID = "b"
        XCTAssertThrowsError(try store.saveReviewed(plan(), replacing: nil, operationID: "wrong", userID: "a"))
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.run_workout_plans", userID: "b"))
        let unsupported = Data("{\"schema\":99,\"plans\":[],\"revisions\":[],\"receipts\":[]}".utf8)
        defaults.set(unsupported, forKey: key)
        XCTAssertThrowsError(try store.saveReviewed(plan(), replacing: nil, operationID: "future", userID: "b"))
        store.addPlan(plan())
        XCTAssertEqual(defaults.data(forKey: key), unsupported)
    }

    func testRepeatGroupPreservesMemberIdentityAndExecutesDistanceFinalRecovery() throws {
        let group = RunWorkoutRepeatGroup(id: "pair", repetitions: 6, workGoal: .distance(meters: 400), recoveryGoal: .distance(meters: 100), includeFinalRecovery: true)
        let workout = RunWorkoutPlan.repeated(id: "six", name: "Six 400s", warmupSeconds: 600, group: group, cooldownSeconds: 300)
        XCTAssertEqual(workout.steps.count, 14)
        XCTAssertEqual(workout.totalDistanceMeters, 3000)
        XCTAssertEqual(workout.steps[12].id, "pair.recovery.6")
        try RunWorkoutPlanStore.validate(workout)
        var more = group
        more.repetitions = 7
        let expanded = more.expandedSteps
        XCTAssertEqual(Array(expanded.prefix(group.expandedSteps.count)), group.expandedSteps)
        let tracker = RunWorkoutTracker(plan: workout)
        _ = tracker.progress(elapsedSeconds: 600, distanceMeters: 1000)
        XCTAssertEqual(tracker.progress(elapsedSeconds: 720, distanceMeters: 1400).currentStep?.id, "pair.recovery.1")
        XCTAssertEqual(tracker.progress(elapsedSeconds: 780, distanceMeters: 1500).currentStep?.id, "pair.work.2")
        XCTAssertEqual(try JSONDecoder().decode(RunWorkoutPlan.self, from: JSONEncoder().encode(workout)), workout)
    }

    func testInvalidTargetAndMismatchedRepeatExpansionCannotBeCommitted() throws {
        let store = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        var invalid = plan()
        invalid.steps[0].target = RunWorkoutTarget(fastestSecondsPerKm: 400, slowestSecondsPerKm: 300)
        XCTAssertThrowsError(try store.saveReviewed(invalid, replacing: nil, operationID: "invalid", userID: "a"))
        invalid = plan()
        invalid.repeatGroup = RunWorkoutRepeatGroup(id: "wrong", repetitions: 2, workGoal: .distance(meters: 400), recoveryGoal: .duration(seconds: 90))
        XCTAssertThrowsError(try RunWorkoutPlanStore.validate(invalid))
        XCTAssertTrue(store.customPlans.isEmpty)
    }
    func testCompletedStepReceiptsRejectCorruptionConflictsAndAccountChanges() throws {
        let results = RunWorkoutResultStore(userDefaults: defaults, authService: auth)
        let receipt = RunWorkoutResult(runID: "completed", planID: "plan", planName: "Original",
            completedAt: Date(timeIntervalSince1970: 100), steps: [])
        try results.saveChecked(receipt, userID: "a")
        try results.saveChecked(receipt, userID: "a")
        var changed = receipt; changed.planName = "Changed"
        XCTAssertThrowsError(try results.saveChecked(changed, userID: "a"))
        XCTAssertEqual(results.result(forRunID: "completed"), receipt)
        auth.currentUserID = "b"
        XCTAssertThrowsError(try results.saveChecked(receipt, userID: "a"))
        XCTAssertNil(results.result(forRunID: "completed"))
        auth.currentUserID = "a"
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.run_workout_results", userID: "a"))
        let unreadable = Data("original unreadable receipt library".utf8)
        defaults.set(unreadable, forKey: key)
        XCTAssertFalse(results.save(receipt))
        XCTAssertFalse(results.deleteResult(forRunID: receipt.runID))
        XCTAssertEqual(defaults.data(forKey: key), unreadable)
    }

}
