import XCTest
@testable import MyFitPlateCore

@MainActor
final class PersonalReportPreferencesTests: XCTestCase {
    func testDisplayChoicesPersistPerAccountWithoutChangingOtherPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        var value = try PersonalReportPreferenceStore.load(userID: "a", store: store)
        XCTAssertFalse(value.showsWellnessComposite); XCTAssertTrue(value.showsGamification); XCTAssertFalse(value.showsBMI)
        value.showsGamification = false
        try PersonalReportPreferenceStore.save(value, userID: "a", currentUserID: "a", store: store)
        XCTAssertEqual(try PersonalReportPreferenceStore.load(userID: "a", store: store), value)
        XCTAssertTrue(try PersonalReportPreferenceStore.load(userID: "b", store: store).showsGamification)
        XCTAssertThrowsError(try PersonalReportPreferenceStore.save(value, userID: "a", currentUserID: "b", store: store))
    }
    func testRoutineNotesStaySeparateAndInvalidSavePreservesEarlierReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        var value = SleepRoutineNotes(); value.usesPreferredWindow = true
        value.nightNotes["captured-night"] = "Late flight; source times retained."
        try SleepRoutineNoteStore.save(value, userID: "a", currentUserID: "a", store: store)
        var invalid = value; invalid.preferredBedtimeMinutes = 1440
        XCTAssertThrowsError(try SleepRoutineNoteStore.save(invalid, userID: "a", currentUserID: "a", store: store))
        XCTAssertEqual(try SleepRoutineNoteStore.load(userID: "a", store: store), value)
        XCTAssertTrue(try SleepRoutineNoteStore.load(userID: "b", store: store).nightNotes.isEmpty)
        XCTAssertThrowsError(try SleepRoutineNoteStore.save(value, userID: "a", currentUserID: "b", store: store))
    }
}
