import XCTest
@testable import MyFitPlateCore

final class WorkoutPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func routine() -> WorkoutRoutine {
        WorkoutRoutine(id: "routine", userID: "a", name: "Strength", dateCreated: Date(),
                       exercises: [RoutineExercise(name: "Squat", sets: [
                        ExerciseSet(isCompleted: true, reps: 8, weight: 100),
                        ExerciseSet(isCompleted: false, reps: 10, weight: 110)
                       ])])
    }

    func testOfflineWritesSurviveRelaunchAndOverlayInOrder() throws {
        let url = directory.appendingPathComponent("queue.json")
        let store = WorkoutOutbox(fileURL: url)
        var plan = WorkoutProgram(id: "plan", userID: "a", name: "Original", routines: [routine()])
        let first = try WorkoutPendingWrite(userID: "a", collection: .programs, documentID: "plan", value: plan)
        try store.append(first)
        try store.append(first)
        plan.name = "Edited offline"
        let second = try WorkoutPendingWrite(userID: "a", collection: .programs, documentID: "plan", value: plan)
        try store.append(second)
        let reopened = WorkoutOutbox(fileURL: url)
        XCTAssertEqual(try reopened.pending(userID: "a").count, 2)
        XCTAssertTrue(try reopened.pending(userID: "b").isEmpty)
        var visible: [WorkoutProgram] = try reopened.overlay([], userID: "a", collection: .programs, id: { $0.id })
        XCTAssertEqual(visible.map(\.name), ["Edited offline"])
        try reopened.acknowledge(first)
        XCTAssertEqual(try reopened.pending(userID: "a").map(\.id), [second.id])
        try reopened.append(WorkoutPendingWrite(userID: "a", deleting: .programs, documentID: "plan"))
        visible = try reopened.overlay([plan], userID: "a", collection: .programs, id: { $0.id })
        XCTAssertTrue(visible.isEmpty)
    }

    func testQueueCorruptionRejectsNewSaveWithoutDiscardingExistingData() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("queue.json")
        try Data("unreadable".utf8).write(to: url)
        let store = WorkoutOutbox(fileURL: url)
        XCTAssertThrowsError(try store.append(WorkoutPendingWrite(userID: "a", deleting: .routines, documentID: "r")))
        XCTAssertEqual(try String(contentsOf: url), "unreadable")
    }

    func testDeletingOneAccountsPendingWritesKeepsOtherAccount() throws {
        let store = WorkoutOutbox(fileURL: directory.appendingPathComponent("queue.json"))
        try store.append(WorkoutPendingWrite(userID: "a", deleting: .routines, documentID: "r"))
        try store.append(WorkoutPendingWrite(userID: "b", deleting: .routines, documentID: "r"))
        try store.removeAll(userID: "a")
        XCTAssertTrue(try store.pending(userID: "a").isEmpty)
        XCTAssertEqual(try store.pending(userID: "b").count, 1)
    }

    func testDraftRestoresSetsAndFrozenCompletionWithoutDuplicatingSession() throws {
        let store = WorkoutDraftStore(directory: directory)
        var draft = WorkoutSessionDraft(routine: routine())
        draft.elapsed = 600
        let completedAt = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(draft.prepareCompletion(weightPounds: 180, now: completedAt))
        try store.save(draft, userID: "a")
        XCTAssertNil(try store.load(userID: "b"))
        let reopened = WorkoutDraftStore(directory: directory)
        var restored = try XCTUnwrap(reopened.load(userID: "a"))
        XCTAssertEqual(restored.routine.exercises[0].sets[0].weight, 100)
        XCTAssertEqual(restored.elapsed, 600)
        XCTAssertTrue(restored.prepareCompletion(weightPounds: 200, now: completedAt.addingTimeInterval(86400)))
        XCTAssertEqual(restored.completion?.id, draft.sessionID)
        XCTAssertEqual(restored.completion?.date, completedAt)
        XCTAssertEqual(restored.completion?.completedExercises[0].sets.count, 1)
        XCTAssertEqual(restored.diaryExercise?.id, draft.sessionID)
        XCTAssertEqual(restored.diaryExercise?.durationMinutes, 10)
        XCTAssertEqual(restored.diaryExercise?.caloriesBurned, draft.diaryExercise?.caloriesBurned)
        try reopened.remove(userID: "b")
        XCTAssertNotNil(try reopened.load(userID: "a"))
        try reopened.remove(userID: "a")
        XCTAssertNil(try reopened.load(userID: "a"))
    }

    func testNoCompletedSetsCannotCreateAWorkout() {
        let template = routine()
        template.exercises[0].sets[0].isCompleted = false
        var draft = WorkoutSessionDraft(routine: template)
        XCTAssertFalse(draft.prepareCompletion(weightPounds: 180))
        XCTAssertNil(draft.completion)
        XCTAssertNil(draft.diaryExercise)
    }

    func testEditingRoutineDoesNotMutateItsSourceUntilAccepted() {
        let original = routine()
        let editor = RoutineEditorViewModel(routine: original) { _ in }
        XCTAssertFalse(editor.hasChanges)
        editor.exercises[0].sets[0].weight = 200
        XCTAssertTrue(editor.hasChanges)
        XCTAssertEqual(original.exercises[0].sets[0].weight, 100)
        XCTAssertEqual(editor.draft.exercises[0].sets[0].weight, 200)
    }
}
