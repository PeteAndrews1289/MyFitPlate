import XCTest
@testable import MyFitPlateCore

@MainActor
final class DeletedAccountCleanupTests: XCTestCase {
    private var directory: URL!
    private var store: DeletedAccountCleanupStore!
    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("deleted-cleanup-\(UUID().uuidString)")
        store = DeletedAccountCleanupStore(directory: directory)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testFailedDomainRemainsDurableWhileOtherDomainsCompleteAndRelaunchRetriesOnlyOriginalOwner() throws {
        let coordinator = DeletedAccountCleanupCoordinator(store: store)
        var completed: [String] = []
        let result = coordinator.attempt(for: "deleted-owner", domains: ["drafts", "speech", "preferences"]) { user, domain in
            XCTAssertEqual(user, "deleted-owner")
            if domain == "speech" { throw CocoaError(.fileWriteNoPermission) }
            completed.append(domain)
        }
        XCTAssertFalse(result)
        XCTAssertEqual(completed, ["drafts", "preferences"])
        let receipt = try XCTUnwrap(store.pending().first)
        XCTAssertEqual(receipt.remainingDomains, ["speech"])
        XCTAssertNotNil(coordinator.errorMessage)
        let reopened = DeletedAccountCleanupCoordinator(store: store)
        var retried: [String] = []
        XCTAssertTrue(reopened.retryPending { user, domain in
            XCTAssertEqual(user, "deleted-owner", "A different active login must not change cleanup ownership")
            retried.append(domain)
        })
        XCTAssertEqual(retried, ["speech"])
        XCTAssertTrue(try store.pending().isEmpty)
    }

    func testActualReceiptIOFailureDoesNotEraseDataAndRepairRetriesVolatileIntent() throws {
        try Data("not a directory".utf8).write(to: directory)
        let coordinator = DeletedAccountCleanupCoordinator(store: store)
        var calls = 0
        XCTAssertFalse(coordinator.attempt(for: "deleted-owner", domains: ["drafts"]) { _, _ in calls += 1 })
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(coordinator.errorMessage)
        try FileManager.default.removeItem(at: directory)
        XCTAssertTrue(coordinator.retryPending { user, domain in
            XCTAssertEqual(user, "deleted-owner"); XCTAssertEqual(domain, "drafts"); calls += 1
        })
        XCTAssertEqual(calls, 1)
    }

    func testLostAcknowledgementAfterDeletionReplaysIdempotentlyAndPreservesOtherAccountFiles() throws {
        let dataRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-data-\(UUID().uuidString)")
        let backup = directory.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: dataRoot); try? FileManager.default.removeItem(at: backup) }
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let owned = dataRoot.appendingPathComponent("deleted-owner")
        let other = dataRoot.appendingPathComponent("other-owner")
        try Data("first".utf8).write(to: owned); try Data("second".utf8).write(to: other)
        let coordinator = DeletedAccountCleanupCoordinator(store: store)
        XCTAssertFalse(coordinator.attempt(for: "deleted-owner", domains: ["files"]) { _, _ in
            try FileManager.default.removeItem(at: owned)
            try FileManager.default.moveItem(at: self.directory, to: backup)
            try Data("blocked acknowledgement".utf8).write(to: self.directory)
        })
        XCTAssertEqual(try String(contentsOf: other), "second")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        let reopened = DeletedAccountCleanupCoordinator(store: store)
        XCTAssertTrue(reopened.retryPending { user, _ in
            XCTAssertEqual(user, "deleted-owner")
            if FileManager.default.fileExists(atPath: owned.path) { try FileManager.default.removeItem(at: owned) }
        })
        XCTAssertEqual(try String(contentsOf: other), "second")
        XCTAssertTrue(try store.pending().isEmpty)
    }

    func testUnreadableOrMismatchedOwnerReceiptIsKeptWithoutExecutingCleanup() throws {
        let receipt = DeletedAccountCleanupReceipt(version: 1, id: UUID(), userID: "owner-a", remainingDomains: ["files"])
        try store.save(receipt)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let mismatched = DeletedAccountCleanupReceipt(version: 1, id: receipt.id, userID: "owner-b", remainingDomains: ["files"])
        try JSONEncoder().encode(mismatched).write(to: file)
        var calls = 0
        let coordinator = DeletedAccountCleanupCoordinator(store: store)
        XCTAssertFalse(coordinator.retryPending { _, _ in calls += 1 })
        XCTAssertEqual(calls, 0)
        try Data("unreadable".utf8).write(to: file)
        XCTAssertFalse(coordinator.retryPending { _, _ in calls += 1 })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(try String(contentsOf: file), "unreadable")
    }

    func testSuccessfulDifferentOwnerRetryCannotHideAnotherOwnersPendingFailure() throws {
        try store.save(DeletedAccountCleanupReceipt(version: 1, id: UUID(), userID: "failed-owner", remainingDomains: ["files"]))
        try store.save(DeletedAccountCleanupReceipt(version: 1, id: UUID(), userID: "successful-owner", remainingDomains: ["files"]))
        let coordinator = DeletedAccountCleanupCoordinator(store: store)
        XCTAssertFalse(coordinator.retryPending { user, _ in
            if user == "failed-owner" { throw CocoaError(.fileWriteNoPermission) }
        })
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertEqual(try store.pending().map(\.userID), ["failed-owner"])
    }
}
