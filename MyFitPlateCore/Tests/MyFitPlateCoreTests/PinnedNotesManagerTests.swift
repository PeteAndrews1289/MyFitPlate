import XCTest
@testable import MyFitPlateCore

@MainActor
final class PinnedNotesManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var authService: MockAuthService!
    private var manager: PinnedNotesManager!

    override func setUp() {
        super.setUp()
        suiteName = "PinnedNotesManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        authService = MockAuthService()
        authService.currentUserID = "account-a"
        manager = PinnedNotesManager(userDefaults: defaults, authService: authService)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        authService = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPinnedNotesAreIsolatedBetweenAccounts() {
        manager.setPinnedNote(for: "Bench Press", note: "Pause the first rep")

        authService.currentUserID = "account-b"
        XCTAssertNil(manager.getPinnedNote(for: "Bench Press"))
        manager.setPinnedNote(for: "Bench Press", note: "Use the narrow grip")

        authService.currentUserID = "account-a"
        XCTAssertEqual(manager.getPinnedNote(for: "Bench Press"), "Pause the first rep")

        authService.currentUserID = "account-b"
        XCTAssertEqual(manager.getPinnedNote(for: "Bench Press"), "Use the narrow grip")
    }

    func testSignedOutUserCannotReadOrWritePinnedNotes() {
        manager.setPinnedNote(for: "Squat", note: "Brace before descending")

        authService.currentUserID = nil
        XCTAssertNil(manager.getPinnedNote(for: "Squat"))
        manager.setPinnedNote(for: "Deadlift", note: "Keep the bar close")

        authService.currentUserID = "account-a"
        XCTAssertEqual(manager.getPinnedNote(for: "Squat"), "Brace before descending")
        XCTAssertNil(manager.getPinnedNote(for: "Deadlift"))
    }

    func testLegacyNotesMigrateOnceToTheCurrentAccount() {
        defaults.set(["Row": "Lead with the elbows"], forKey: "pinnedExerciseNotes")

        XCTAssertEqual(manager.getPinnedNote(for: "Row"), "Lead with the elbows")
        XCTAssertNil(defaults.object(forKey: "pinnedExerciseNotes"))

        authService.currentUserID = "account-b"
        XCTAssertNil(manager.getPinnedNote(for: "Row"))

        authService.currentUserID = "account-a"
        XCTAssertEqual(manager.getPinnedNote(for: "Row"), "Lead with the elbows")
    }
}
