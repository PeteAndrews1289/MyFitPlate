import XCTest
@testable import MyFitPlateCore

final class WorkoutProgramEditingTests: XCTestCase {
    private func legacyProgram() -> WorkoutProgram {
        WorkoutProgram(id: "phul-instance", userID: "editor-user", name: "PHUL",
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000), routines: [
                WorkoutRoutine(id: "upper", userID: "editor-user", name: "Upper", dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
                    exercises: [RoutineExercise(id: "bench", name: "Bench press", sets: [ExerciseSet(id: "bench-set", target: "8-12")])]),
                WorkoutRoutine(id: "lower", userID: "editor-user", name: "Lower", dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
                    exercises: [RoutineExercise(id: "squat", name: "Squat", sets: [ExerciseSet(id: "squat-set", target: "5")])])
            ], startDate: Date(timeIntervalSince1970: 1_700_000_000), daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39,
            skippedIndices: [2, 9, 20])
    }

    func testRestoredPreBlockRoutineDraftCannotRewriteAuthoredRotationAndRemainsRecoverable() throws {
        let legacy = legacyProgram()
        var canonical = legacy
        canonical.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: legacy)
        var changed = legacy
        changed.routines[0] = try XCTUnwrap(legacy.routines[0].deepCopy())
        changed.routines[0].exercises[0].sets[0].target = "1 rep"
        let draft = ProgramEditorDraft(program: changed, baseline: legacy)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        try store.save(draft, userID: "editor-user", scope: "program-phul-instance")
        let restored = try XCTUnwrap(store.load(ProgramEditorDraft.self, userID: "editor-user", scope: "program-phul-instance")).value
        XCTAssertThrowsError(try restored.preparedForSave(latest: canonical)) { error in
            XCTAssertEqual(error.localizedDescription, WorkoutBlockError.authoredRotationChanged.localizedDescription)
        }
        let retained = try XCTUnwrap(store.load(ProgramEditorDraft.self, userID: "editor-user", scope: "program-phul-instance")).value
        XCTAssertEqual(retained.program.routines[0].exercises[0].sets[0].target, "1 rep")
        XCTAssertNil(retained.program.trainingBlock)
        XCTAssertEqual(canonical.routines[0].exercises[0].sets[0].target, "8-12")
        XCTAssertEqual(canonical.currentProgressIndex, 39)
        XCTAssertEqual(canonical.skippedIndices, [2, 9, 20])
    }

    func testMetadataOnlyLegacyDraftKeepsCanonicalBlockAndNewestProgress() throws {
        let legacy = legacyProgram()
        var canonical = legacy
        canonical.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: legacy)
        canonical.currentProgressIndex = 40
        canonical.skippedIndices = [2, 9, 20, 39]
        var draft = legacy
        draft.name = "PHUL gym plan"
        draft.startDate = Date(timeIntervalSince1970: 1_700_086_400)
        let result = try ProgramEditorDraft(program: draft, baseline: legacy).preparedForSave(latest: canonical)
        XCTAssertEqual(result.name, "PHUL gym plan")
        XCTAssertEqual(result.startDate, draft.startDate)
        XCTAssertEqual(result.trainingBlock?.revisionID, canonical.trainingBlock?.revisionID)
        XCTAssertEqual(result.currentProgressIndex, 40)
        XCTAssertEqual(result.skippedIndices, [2, 9, 20, 39])
    }

    func testOrdinaryEditorCannotReorderOrRemoveAuthoredBaseRoutines() throws {
        let legacy = legacyProgram()
        var canonical = legacy
        canonical.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: legacy)
        var reordered = legacy
        reordered.routines.reverse()
        XCTAssertThrowsError(try ProgramEditorDraft(program: reordered, baseline: legacy).preparedForSave(latest: canonical))
        var removed = legacy
        removed.routines.removeLast()
        XCTAssertThrowsError(try ProgramEditorDraft(program: removed, baseline: legacy).preparedForSave(latest: canonical))
    }

    func testLegacyProgramsWithoutAuthoredBlockRetainOrdinaryRotationEditing() throws {
        let legacy = legacyProgram()
        var edited = legacy
        edited.routines.reverse()
        let result = try ProgramEditorDraft(program: edited, baseline: legacy).preparedForSave(latest: legacy)
        XCTAssertEqual(result.routines.map(\.id), ["lower", "upper"])
        XCTAssertEqual(result.currentProgressIndex, 39)
        XCTAssertNil(result.trainingBlock)
    }
}
