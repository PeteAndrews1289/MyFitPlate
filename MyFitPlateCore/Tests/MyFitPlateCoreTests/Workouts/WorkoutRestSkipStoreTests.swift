import MyFitPlateShared
import XCTest

final class WorkoutRestSkipStoreTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testDelayedActionCannotSkipANewRestOrAnotherAccountsSession() {
        let original = UUID(), next = UUID(), otherAccount = UUID()
        let store = WorkoutRestSkipStore(directory: directory)
        XCTAssertTrue(store.request(restID: original, now: now))
        XCTAssertFalse(store.wasRequested(restID: next, now: now))
        XCTAssertFalse(store.wasRequested(restID: otherAccount, now: now))
        XCTAssertTrue(store.wasRequested(restID: original, now: now))
        XCTAssertTrue(store.wasRequested(restID: original, now: now), "Repeated recovery must not revive the skipped rest")
    }

    func testActionSurvivesProcessRecreationAndDoesNotLoseAnotherRest() {
        let first = UUID(), second = UUID()
        XCTAssertTrue(WorkoutRestSkipStore(directory: directory).request(restID: first, now: now))
        XCTAssertTrue(WorkoutRestSkipStore(directory: directory).request(restID: second, now: now))
        let reopened = WorkoutRestSkipStore(directory: directory)
        XCTAssertTrue(reopened.wasRequested(restID: first, now: now.addingTimeInterval(30)))
        XCTAssertTrue(reopened.wasRequested(restID: second, now: now.addingTimeInterval(30)))
        let reopenedAgain = WorkoutRestSkipStore(directory: directory)
        XCTAssertTrue(reopenedAgain.wasRequested(restID: first, now: now.addingTimeInterval(31)))
        XCTAssertTrue(reopenedAgain.wasRequested(restID: second, now: now.addingTimeInterval(31)))
    }

    func testExpiredActionsAreRemovedWithoutAffectingCurrentAction() throws {
        let old = UUID(), current = UUID()
        let store = WorkoutRestSkipStore(directory: directory)
        XCTAssertTrue(store.request(restID: old, now: now))
        XCTAssertTrue(store.request(restID: current, now: now.addingTimeInterval(2 * 86_400)))
        XCTAssertFalse(store.wasRequested(restID: old, now: now.addingTimeInterval(2 * 86_400)))
        XCTAssertTrue(store.wasRequested(restID: current, now: now.addingTimeInterval(2 * 86_400)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count, 1)
        XCTAssertFalse(store.wasRequested(restID: current, now: now.addingTimeInterval(4 * 86_400)))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testUnavailableSharedStorageCannotClaimActionWasSaved() throws {
        let store = WorkoutRestSkipStore(directory: nil)
        let restID = UUID()
        XCTAssertFalse(store.request(restID: restID, now: now))
        XCTAssertFalse(store.wasRequested(restID: restID, now: now))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("regular-file")
        try Data("kept".utf8).write(to: blocked)
        let failedWrite = WorkoutRestSkipStore(directory: blocked)
        XCTAssertFalse(failedWrite.request(restID: restID, now: now))
        XCTAssertFalse(failedWrite.wasRequested(restID: restID, now: now))
        XCTAssertEqual(try Data(contentsOf: blocked), Data("kept".utf8))
    }
}
