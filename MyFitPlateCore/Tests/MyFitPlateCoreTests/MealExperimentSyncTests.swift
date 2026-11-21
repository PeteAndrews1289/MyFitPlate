import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealExperimentSyncTests: XCTestCase {
    private func experiment(now: Date = Date()) throws -> MealExperiment {
        let routine = WorkoutRoutine(id: "routine", userID: "a", name: "Upper", dateCreated: now,
            exercises: [RoutineExercise(name: "Press", sets: [ExerciseSet(target: "8", reps: 8, weight: 100)], targetSets: 1)])
        let program = WorkoutProgram(id: "program", userID: "a", name: "Plan", routines: [routine], startDate: now,
                                     daysOfWeek: [1, 3, 5], currentProgressIndex: 0)
        return try MealExperimentRules.create(program: program, routineID: "routine",
            mealA: FoodItem(name: "Oats", calories: 300), mealB: FoodItem(name: "Toast", calories: 300),
            minutesBefore: 90, startsWithA: true, now: now)
    }
    private func observation(_ id: String) -> MealExperimentObservation {
        MealExperimentObservation(sessionID: id, sessionDate: Date(), energy: 4, comfort: 4, minutesBefore: 90,
                                  confounders: [], workingSets: 1, volume: 800, meanRPE: 8, note: "")
    }
    func testIndependentOfflineCheckInsMergeWithoutDroppingEither() throws {
        let base = try experiment()
        var one = base; one.trials[0].observation = observation("one")
        var two = base; two.trials[1].observation = observation("two")
        var a = MealExperimentCloudState(); a.update(one)
        var b = MealExperimentCloudState(); b.update(base); b.update(two)
        let merged = a.merging(b)
        XCTAssertEqual(merged.experiments[0].trials.compactMap { $0.observation?.sessionID }, ["one", "two"])
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(b.merging(a)))
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(merged.merging(a)))
    }
    func testConcurrentCheckInsForOneTrialAreBothRecoverableAndNotDoubleCounted() throws {
        let base = try experiment()
        var first = base; first.trials[0].observation = observation("one")
        var second = base; second.trials[0].observation = observation("two")
        var a = MealExperimentCloudState(); a.update(first)
        var b = MealExperimentCloudState(); b.update(second)
        let merged = a.merging(b)
        XCTAssertEqual(Set(merged.experiments[0].trials.compactMap { $0.observation?.sessionID }), ["one", "two"])
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(b.merging(a)))
        XCTAssertEqual(try PlanFingerprint.make(merged), try PlanFingerprint.make(merged.merging(a)))
        XCTAssertEqual(MealExperimentRules.summary(merged.experiments[0]).a.count, 2)
    }

    func testDeletionTombstonePreventsOldOfflineCopyResurrection() throws {
        let time = Date()
        let base = try experiment(now: time.addingTimeInterval(-60))
        var old = MealExperimentCloudState(); old.update(base)
        var deleted = old; deleted.deleteAll(now: time)
        var laterEdit = base; laterEdit.trials[0].observation = observation("old-device")
        old.update(laterEdit, now: time.addingTimeInterval(60))
        XCTAssertTrue(deleted.merging(old).experiments.isEmpty)
        XCTAssertTrue(old.merging(deleted).experiments.isEmpty)
        var fresh = MealExperimentCloudState(); fresh.update(try experiment(now: time.addingTimeInterval(1)))
        XCTAssertEqual(deleted.merging(fresh).experiments.count, 1)
    }
    func testOfflineSaveSurvivesRestartAndRecoversOnAnotherDevice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ComparisonRepositoryMock()
        repository.offline = true
        let local = EditorDraftStore(directory: root.appendingPathComponent("one"))
        let first = MealExperimentStore(storage: local, repository: repository)
        first.activateAccount("a")
        let value = try experiment()
        try first.save(value, for: "a")
        await first.synchronize()
        XCTAssertTrue(first.syncMessage?.contains("Could not sync") == true)
        let restarted = MealExperimentStore(storage: local, repository: repository)
        restarted.activateAccount("a")
        XCTAssertEqual(restarted.active?.id, value.id)
        repository.offline = false
        await restarted.synchronize()
        let second = MealExperimentStore(storage: EditorDraftStore(directory: root.appendingPathComponent("two")), repository: repository)
        second.activateAccount("a")
        await second.synchronize()
        XCTAssertEqual(second.active?.id, value.id)
        second.activateAccount("b")
        await second.synchronize()
        XCTAssertTrue(second.experiments.isEmpty)
        XCTAssertThrowsError(try second.save(value, for: "a"))
    }
    func testLegacyLocalComparisonsMigrateWithoutChangingTrialIDs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = EditorDraftStore(directory: root)
        let original = try experiment()
        try storage.save([original], userID: "a", scope: "familiar-meal-comparisons-v1")
        let store = MealExperimentStore(storage: storage)
        store.activateAccount("a")
        XCTAssertEqual(store.active?.trials.map(\.id), original.trials.map(\.id))
        let checkpoint = try XCTUnwrap(storage.load(MealExperimentCheckpoint.self, userID: "a", scope: "familiar-meal-comparisons-v2"))
        XCTAssertTrue(checkpoint.value.pending)
    }
}

@MainActor
private final class ComparisonRepositoryMock: MealExperimentRepository {
    var states: [String: MealExperimentCloudState] = [:]
    var offline = false
    func merge(_ state: MealExperimentCloudState, userID: String) async throws -> MealExperimentCloudState {
        if offline { throw URLError(.notConnectedToInternet) }
        let merged = (states[userID] ?? MealExperimentCloudState()).merging(state)
        states[userID] = merged
        return merged
    }
}
