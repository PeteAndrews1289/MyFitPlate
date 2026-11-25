import XCTest
@testable import MyFitPlateCore

final class FastingSessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: FastingSessionStore!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let owner = FastingSessionStore.ownerScope(userID: "fast-owner")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = FastingSessionStore(directory: directory)
        try store.activateAccount(userID: "fast-owner")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testStartAndEndSurviveStoreRecreationWithoutAnActivity() throws {
        let started = try store.start(ownerScope: owner, hours: 16, now: now)
        XCTAssertEqual(started.targetEndTime.timeIntervalSince(now), 16 * 3_600)
        let restarted = FastingSessionStore(directory: directory)
        XCTAssertEqual(try restarted.load(ownerScope: owner).activeSession, started)
        let ended = try restarted.end(ownerScope: owner, sessionID: started.id, expectedRevision: 1, now: now.addingTimeInterval(3_000))
        let saved = try store.load(ownerScope: owner)
        XCTAssertNil(saved.activeSession)
        XCTAssertEqual(saved.lastEndedSession, ended)
        XCTAssertEqual(saved.sessions.count, 1)
        XCTAssertEqual(ended.startTime, now)
    }

    func testDuplicateStartCannotReplaceCurrentSession() throws {
        let original = try store.start(ownerScope: owner, hours: 12, now: now)
        XCTAssertThrowsError(try store.start(ownerScope: owner, hours: 20, now: now.addingTimeInterval(60))) { XCTAssertEqual($0 as? FastingStoreError, .alreadyActive) }
        XCTAssertEqual(try store.load(ownerScope: owner).sessions, [original])
    }

    func testDuplicateOldEndDoesNotAlterNewFastOrFirstEndTime() throws {
        let first = try store.start(ownerScope: owner, hours: 16, now: now)
        let ended = try store.end(ownerScope: owner, sessionID: first.id, expectedRevision: 1, now: now.addingTimeInterval(60))
        let next = try store.start(ownerScope: owner, hours: 12, now: now.addingTimeInterval(120))
        XCTAssertEqual(try store.end(ownerScope: owner, sessionID: first.id, expectedRevision: 1, now: now.addingTimeInterval(180)), ended)
        XCTAssertEqual(try store.load(ownerScope: owner).activeSession, next)
        XCTAssertEqual(try store.load(ownerScope: owner).sessions.count, 2)
    }

    func testStaleAndUnknownEndCommandsPreserveActiveSession() throws {
        let fast = try store.start(ownerScope: owner, hours: 14, now: now)
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: 2, now: now.addingTimeInterval(60)))
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: Int.max, now: now.addingTimeInterval(60)))
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: UUID(), expectedRevision: 1, now: now.addingTimeInterval(60)))
        XCTAssertEqual(try store.load(ownerScope: owner).activeSession, fast)
    }

    func testAccountSwitchFencesOldControlsAndPreservesBothAccounts() throws {
        let fast = try store.start(ownerScope: owner, hours: 14, now: now)
        try store.activateAccount(userID: "other-owner")
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: 1, now: now.addingTimeInterval(60))) { XCTAssertEqual($0 as? FastingStoreError, .accountChanged) }
        let other = try XCTUnwrap(FastingSessionStore.ownerScope(userID: "other-owner"))
        let otherFast = try store.start(ownerScope: other, hours: 12, now: now)
        try store.activateAccount(userID: "fast-owner")
        XCTAssertEqual(try store.load(ownerScope: owner).activeSession, fast)
        XCTAssertEqual(try store.load(ownerScope: other).activeSession, otherFast)
    }

    func testSignOutDetachesWithoutEndingTheSavedFast() throws {
        let fast = try store.start(ownerScope: owner, hours: 14, now: now)
        try store.activateAccount(userID: nil)
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: 1, now: now.addingTimeInterval(60)))
        try store.activateAccount(userID: "fast-owner")
        XCTAssertEqual(try store.load(ownerScope: owner).activeSession, fast)
    }

    func testInvalidDurationAndNonfiniteClockNeverCreateARecord() throws {
        for hours in [-1, 0, 24, Int.max] { XCTAssertThrowsError(try store.start(ownerScope: owner, hours: hours, now: now)) }
        XCTAssertThrowsError(try store.start(ownerScope: owner, hours: 16, now: Date(timeIntervalSinceReferenceDate: .nan)))
        XCTAssertThrowsError(try store.start(ownerScope: owner, hours: 16, now: .distantFuture))
        XCTAssertTrue(try store.load(ownerScope: owner).sessions.isEmpty)
    }

    func testClockRollbackRejectsEndWithoutChangingTimes() throws {
        let fast = try store.start(ownerScope: owner, hours: 16, now: now)
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: 1, now: now.addingTimeInterval(-1)))
        XCTAssertEqual(try store.load(ownerScope: owner).activeSession, fast)
    }

    func testTargetReachedIsNotAnAutomaticCompletion() throws {
        let fast = try store.start(ownerScope: owner, hours: 12, now: now.addingTimeInterval(-24 * 3_600))
        XCTAssertTrue(try store.load(ownerScope: owner).activeSession?.isActive == true)
        let ended = try store.end(ownerScope: owner, sessionID: fast.id, expectedRevision: 1, now: now)
        XCTAssertEqual(ended.endedAt?.timeIntervalSince(ended.startTime), 24 * 3_600)
    }

    func testUnavailableStorageDoesNotAcknowledgeStart() {
        let missing = FastingSessionStore(directory: nil)
        XCTAssertThrowsError(try missing.activateAccount(userID: "fast-owner"))
        XCTAssertThrowsError(try missing.start(ownerScope: owner, hours: 16, now: now))
    }

    func testUnreadableSavedStateIsKeptByteForByte() throws {
        let url = directory.appendingPathComponent("fasts-\(owner).json")
        let original = Data("{future-unreadable-state".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try store.start(ownerScope: owner, hours: 16, now: now)) { XCTAssertEqual($0 as? FastingStoreError, .unreadable) }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testRejectedDiskWriteCannotStartAnInMemoryOnlyFast() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try store.start(ownerScope: owner, hours: 16, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("fasts-\(owner).json").path))
    }

    func testLegacyRecoveryKeepsTimesAndIsIdempotent() throws {
        let fast = try store.recoverLegacy(ownerScope: owner, activityID: "old-activity", startTime: now.addingTimeInterval(-120), targetEndTime: now.addingTimeInterval(14 * 3_600 - 120), now: now)
        XCTAssertEqual(fast.startTime, now.addingTimeInterval(-120))
        XCTAssertEqual(fast.source, "legacy-activity")
        let replay = try store.recoverLegacy(ownerScope: owner, activityID: "old-activity", startTime: now, targetEndTime: now.addingTimeInterval(12 * 3_600), now: now)
        XCTAssertEqual(replay, fast)
        XCTAssertEqual(try store.load(ownerScope: owner).sessions.count, 1)
    }

    func testLegacyActivityCannotBeClaimedByAnotherAccount() throws {
        _ = try store.recoverLegacy(ownerScope: owner, activityID: "old-activity", startTime: now, targetEndTime: now.addingTimeInterval(12 * 3_600), now: now)
        try store.activateAccount(userID: "other-owner")
        let other = try XCTUnwrap(FastingSessionStore.ownerScope(userID: "other-owner"))
        XCTAssertThrowsError(try store.recoverLegacy(ownerScope: other, activityID: "old-activity", startTime: now, targetEndTime: now.addingTimeInterval(12 * 3_600), now: now))
        XCTAssertTrue(try store.load(ownerScope: other).sessions.isEmpty)
    }

    func testInvalidOwnerCannotEscapeScopedStorage() {
        XCTAssertThrowsError(try store.load(ownerScope: "../elsewhere"))
        XCTAssertNil(FastingSessionStore.ownerScope(userID: ""))
        XCTAssertNotEqual(FastingSessionStore.ownerScope(userID: "one"), FastingSessionStore.ownerScope(userID: "two"))
    }

    func testDeletionPurgesOnlyCapturedOwnerAndKeepsOtherAccountsActiveFence() throws {
        let first = try store.start(ownerScope: owner, hours: 16, now: now)
        try store.activateAccount(userID: "other-owner")
        let other = try XCTUnwrap(FastingSessionStore.ownerScope(userID: "other-owner"))
        let second = try store.start(ownerScope: other, hours: 12, now: now)
        _ = try store.removeAccount(userID: "fast-owner")
        XCTAssertTrue(try store.load(ownerScope: owner).sessions.isEmpty)
        XCTAssertEqual(try store.load(ownerScope: other).activeSession, second)
        XCTAssertThrowsError(try store.end(ownerScope: owner, sessionID: first.id, expectedRevision: 1, now: now.addingTimeInterval(60)))
        XCTAssertNoThrow(try store.end(ownerScope: other, sessionID: second.id, expectedRevision: 1, now: now.addingTimeInterval(60)))
    }
}
