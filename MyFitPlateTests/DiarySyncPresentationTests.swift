import XCTest
import FirebaseCore
import FirebaseFirestore
import MyFitPlateCore
@testable import MyFitPlate

/// Local queue/status regressions. Named Firebase apps use a synthetic project, localhost,
/// and disabled networking; these tests never contact a backend or use an owner's outbox.
final class DiarySyncPresentationTests: XCTestCase {
    private var apps: [FirebaseApp] = []
    private var directories: [URL] = []

    override func tearDown() {
        for app in apps { app.delete { _ in } }
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        apps = []
        directories = []
    }

    func testEmptyRetryPublishesSyncedWithoutCreatingAnOutbox() async throws {
        let fixture = try await makeFixture(owner: "empty-owner")
        let observed = observe(.synced, repository: fixture.repository, owner: "empty-owner")
        defer { NotificationCenter.default.removeObserver(observed.token) }

        fixture.repository.retryPendingDailyLogs(userID: "empty-owner")
        await fulfillment(of: [observed.expectation], timeout: 3)

        XCTAssertEqual(fixture.repository.dailyLogSyncState(userID: "empty-owner"), .synced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outbox.path),
                       "Refreshing status must not create or rewrite a diary queue.")
    }

    func testEmptyOwnerRetryLeavesAnotherAccountsPendingMutationByteIdentical() async throws {
        let fixture = try await makeFixture(owner: "current-owner")
        let store = DailyLogMutationStore(fileURL: fixture.outbox)
        let log = DailyLog(id: "2026-11-03", date: Date(timeIntervalSince1970: 1_793_664_000), meals: [])
        try store.append(DailyLogMutation(userID: "other-owner", log: log))
        let originalBytes = try Data(contentsOf: fixture.outbox)
        let observed = observe(.synced, repository: fixture.repository, owner: "current-owner")
        defer { NotificationCenter.default.removeObserver(observed.token) }

        fixture.repository.retryPendingDailyLogs(userID: "current-owner")
        await fulfillment(of: [observed.expectation], timeout: 3)

        XCTAssertEqual(try Data(contentsOf: fixture.outbox), originalBytes)
        XCTAssertEqual(try store.pending(userID: "other-owner").count, 1)
        XCTAssertEqual(fixture.repository.dailyLogSyncState(userID: "other-owner"), .pending(1))
    }

    func testEmptyRetryClearsStaleReadFailureAfterDurableQueueIsRestored() async throws {
        let fixture = try await makeFixture(owner: "recovered-owner")
        try Data("unreadable fixture".utf8).write(to: fixture.outbox)
        let failed = observe(.failed, repository: fixture.repository, owner: "recovered-owner")
        fixture.repository.retryPendingDailyLogs(userID: "recovered-owner")
        await fulfillment(of: [failed.expectation], timeout: 3)
        NotificationCenter.default.removeObserver(failed.token)
        XCTAssertEqual(fixture.repository.dailyLogSyncState(userID: "recovered-owner"), .failed)
        XCTAssertEqual(try Data(contentsOf: fixture.outbox), Data("unreadable fixture".utf8),
                       "A failed read must preserve the original queue bytes.")

        // Simulate a separately completed recovery; the repository itself never erases a queue.
        let restoredBytes = Data("[]".utf8)
        let recovered = observe(.synced, repository: fixture.repository, owner: "recovered-owner")
        defer { NotificationCenter.default.removeObserver(recovered.token) }
        try restoredBytes.write(to: fixture.outbox, options: .atomic)
        fixture.repository.retryPendingDailyLogs(userID: "recovered-owner")
        await fulfillment(of: [recovered.expectation], timeout: 3)

        XCTAssertEqual(fixture.repository.dailyLogSyncState(userID: "recovered-owner"), .synced)
        XCTAssertEqual(try Data(contentsOf: fixture.outbox), restoredBytes)
    }

    func testRetryForInactiveAccountDoesNotPublishItsStatus() async throws {
        let fixture = try await makeFixture(owner: "signed-in-owner")
        let unexpected = expectation(description: "No notification for an inactive owner")
        unexpected.isInverted = true
        let token = NotificationCenter.default.addObserver(forName: .dailyLogSyncStateChanged, object: nil, queue: nil) { note in
            if note.object as? String == "signed-out-owner" { unexpected.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        fixture.repository.retryPendingDailyLogs(userID: "signed-out-owner")
        // The state read synchronizes with the repository queue before the notification check.
        XCTAssertEqual(fixture.repository.dailyLogSyncState(userID: "signed-out-owner"), .synced)
        await fulfillment(of: [unexpected], timeout: 0.3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outbox.path))
    }

    private func observe(_ state: DailyLogSyncState, repository: FirestoreNutritionRepository,
                         owner: String) -> (expectation: XCTestExpectation, token: NSObjectProtocol) {
        let updated = expectation(description: "Owner-scoped status reconciliation")
        // Network restoration and an explicit retry may independently reconcile the same queue.
        updated.assertForOverFulfill = false
        let token = NotificationCenter.default.addObserver(forName: .dailyLogSyncStateChanged, object: nil, queue: nil) { note in
            guard note.object as? String == owner, repository.dailyLogSyncState(userID: owner) == state else { return }
            XCTAssertEqual(note.userInfo?["hasNewMutation"] as? Bool, false,
                           "An empty retry is a status refresh, not a new diary mutation.")
            updated.fulfill()
        }
        return (updated, token)
    }

    private func makeFixture(owner: String) async throws -> (repository: FirestoreNutritionRepository, outbox: URL) {
        let name = "diary-status-test-\(UUID().uuidString)"
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        FirebaseApp.configure(name: name, options: options)
        let app = try XCTUnwrap(FirebaseApp.app(name: name))
        apps.append(app)
        let database = Firestore.firestore(app: app)
        database.useEmulator(withHost: "127.0.0.1", port: 1)
        try await database.disableNetwork()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        let outbox = directory.appendingPathComponent("outbox.json")
        return (FirestoreNutritionRepository(db: database, outboxURL: outbox, currentUserID: { owner }), outbox)
    }
}
