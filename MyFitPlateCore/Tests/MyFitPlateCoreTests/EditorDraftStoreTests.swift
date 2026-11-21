import XCTest
@testable import MyFitPlateCore

final class EditorDraftStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testEditorRestoresNestedUnfinishedRoutineAfterStoreRecreation() throws {
        let store = EditorDraftStore(directory: directory)
        let routine = WorkoutRoutine(id: "new-routine", userID: "a", name: "", dateCreated: Date(timeIntervalSince1970: 123))
        let program = WorkoutProgram(id: "original", userID: "a", name: "Plan", currentProgressIndex: 35)
        let pending = ProgramEditorDraft(program: program, baseline: program, pendingRoutine: routine)
        try store.save(pending, userID: "a", scope: "program-original")
        let reopened = EditorDraftStore(directory: directory)
        let restored = try XCTUnwrap(reopened.load(ProgramEditorDraft.self, userID: "a", scope: "program-original"))
        XCTAssertEqual(restored.value.program.id, "original")
        XCTAssertEqual(restored.value.program.currentProgressIndex, 35)
        XCTAssertEqual(restored.value.pendingRoutine?.id, "new-routine")
        XCTAssertTrue(restored.value.program.routines.isEmpty, "An unfinished child is not a saved routine")
    }

    func testDraftsAreIsolatedByAccountAndEditorAndDeletionIsScoped() throws {
        let store = EditorDraftStore(directory: directory)
        try store.save("a's program", userID: "a", scope: "program")
        try store.save("a's routine", userID: "a", scope: "routine")
        try store.save("b's program", userID: "b", scope: "program")
        XCTAssertEqual(try store.load(String.self, userID: "a", scope: "program")?.value, "a's program")
        XCTAssertNil(try store.load(String.self, userID: "b", scope: "routine"))
        try store.remove(userID: "a", scope: "program")
        XCTAssertNotNil(try store.load(String.self, userID: "a", scope: "routine"))
        try store.removeAll(userID: "a")
        XCTAssertNil(try store.load(String.self, userID: "a", scope: "routine"))
        XCTAssertEqual(try store.load(String.self, userID: "b", scope: "program")?.value, "b's program")
    }

    func testRestoredEditorKeepsItsIdentityAndDoesNotMutateSavedRoutine() throws {
        let original = WorkoutRoutine(id: "saved", userID: "a", name: "Original", dateCreated: Date(), exercises: [])
        let editor = RoutineEditorViewModel(routine: original, onSave: { _ in })
        editor.routineName = "Unfinished edits"
        try EditorDraftStore(directory: directory).save(editor.checkpoint, userID: "a", scope: "routine")
        let recovered = try XCTUnwrap(EditorDraftStore(directory: directory).load(RoutineEditorDraft.self, userID: "a", scope: "routine"))
        let reopened = RoutineEditorViewModel(routine: original, onSave: { _ in })
        reopened.restore(recovered.value)
        XCTAssertEqual(reopened.draft.id, "saved")
        XCTAssertEqual(reopened.routineName, "Unfinished edits")
        XCTAssertTrue(reopened.hasChanges)
        XCTAssertEqual(original.name, "Original")
    }

    func testRecoveredPlanEditsNeverRewindCurrentWorkoutProgress() {
        let original = WorkoutProgram(id: "plan", userID: "a", name: "Plan", currentProgressIndex: 8)
        var edited = original
        edited.name = "Edited name"
        var current = original
        current.currentProgressIndex = 12
        current.skippedIndices = [9, 10]
        let draft = ProgramEditorDraft(program: edited, baseline: original)
        let result = draft.preservingProgress(from: current)
        XCTAssertEqual(result.name, "Edited name")
        XCTAssertEqual(result.currentProgressIndex, 12)
        XCTAssertEqual(result.skippedIndices, [9, 10])
        current.userID = "b"
        XCTAssertEqual(draft.preservingProgress(from: current).currentProgressIndex, 8)
    }

    func testUnreadableDraftIsPreservedWhenAutosaveRetries() throws {
        let store = EditorDraftStore(directory: directory)
        try store.save("valuable edits", userID: "a", scope: "program")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let file = try XCTUnwrap(files.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
        let damaged = Data("unreadable previous draft".utf8)
        try damaged.write(to: file)
        XCTAssertThrowsError(try store.load(String.self, userID: "a", scope: "program"))
        XCTAssertThrowsError(try store.save("replacement", userID: "a", scope: "program"))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testNewerSchemaIsNotSilentlyReplacedAndSignedOutWritesFail() throws {
        let store = EditorDraftStore(directory: directory)
        try store.save("future edits", userID: "a", scope: "../program")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let file = try XCTUnwrap(files.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        payload["version"] = 99
        try JSONSerialization.data(withJSONObject: payload).write(to: file)
        XCTAssertThrowsError(try store.save("old format", userID: "a", scope: "../program"))
        XCTAssertThrowsError(try store.save("signed out", userID: "", scope: "program"))
    }
}
