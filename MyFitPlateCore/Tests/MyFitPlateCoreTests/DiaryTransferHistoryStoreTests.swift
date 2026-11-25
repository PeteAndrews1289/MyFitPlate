import XCTest
@testable import MyFitPlateCore

@MainActor
final class DiaryTransferHistoryStoreTests: XCTestCase {
    private let owner = "transfer-history-owner"
    private let scope = "diary-transfer-history"
    private var directory: URL!
    private var store: EditorDraftStore!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("transfer-history-\(UUID())")
        store = EditorDraftStore(directory: directory)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testAcceptedReceiptsPersistNewestFirstAcrossRecreation() throws {
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let newer = try receipt(index: 2)
        let older = try receipt(index: 1)
        XCTAssertTrue(history.record(newer))
        XCTAssertTrue(history.record(older))
        let restored = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.receipts.map(\.id), [newer.id, older.id])
        XCTAssertEqual(restored.receipts.map(\.commandFingerprint), [newer.commandFingerprint, older.commandFingerprint])
    }

    func testOnlyTwentyNewestReceiptsRemainInMemoryAndOnDisk() throws {
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let receipts = try (0..<25).map { try receipt(index: $0) }
        for receipt in receipts.reversed() { XCTAssertTrue(history.record(receipt)) }
        let expected = receipts.suffix(20).reversed().map(\.id)
        XCTAssertEqual(history.receipts.map(\.id), expected)
        let saved = try XCTUnwrap(store.load([DiaryTransferReceipt].self, userID: owner, scope: scope))
        XCTAssertEqual(saved.value.map(\.id), expected)
        XCTAssertEqual(DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner }).receipts.count, 20)
    }

    func testUndoReplacesItsReceiptAndStaleAcceptanceCannotEraseIt() throws {
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let accepted = try receipt(index: 1)
        let other = try receipt(index: 2)
        XCTAssertTrue(history.record(accepted)); XCTAssertTrue(history.record(other))
        var undone = accepted
        undone.undoneAt = accepted.acceptedAt.addingTimeInterval(60)
        XCTAssertTrue(history.record(undone))
        XCTAssertEqual(history.receipts.count, 2)
        XCTAssertTrue(history.record(accepted), "Delayed accepted responses are safe to replay after Undo")
        let restored = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertEqual(restored.receipts.first { $0.id == accepted.id }?.undoneAt, undone.undoneAt)
        XCTAssertEqual(restored.receipts.map(\.id), [other.id, accepted.id])
    }

    func testSeparateHistoryInstancesMergeAgainstLatestDurableIndex() throws {
        let first = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let stale = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let one = try receipt(index: 1), two = try receipt(index: 2)
        XCTAssertTrue(first.record(one))
        XCTAssertTrue(stale.record(two))
        first.reload()
        XCTAssertEqual(first.receipts.map(\.id), [two.id, one.id])
        var undone = one; undone.undoneAt = one.acceptedAt.addingTimeInterval(60)
        XCTAssertTrue(first.record(undone))
        XCTAssertTrue(stale.record(one))
        XCTAssertEqual(stale.receipts.first { $0.id == one.id }?.undoneAt, undone.undoneAt)
    }

    func testSameOperationIDWithAnotherFingerprintCannotReplaceSavedReceipt() throws {
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        let original = try receipt(index: 1)
        XCTAssertTrue(history.record(original))
        let file = try savedFile(), before = try Data(contentsOf: file)
        let collision = try receipt(index: 2, operationID: original.id)
        XCTAssertNotEqual(collision.commandFingerprint, original.commandFingerprint)
        XCTAssertFalse(history.record(collision))
        XCTAssertNotNil(history.errorMessage)
        XCTAssertEqual(history.receipts.first?.commandFingerprint, original.commandFingerprint)
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testMalformedStorageFailsClosedAndIsNotOverwritten() throws {
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertTrue(history.record(try receipt(index: 1)))
        let file = try savedFile()
        let damaged = Data("{ interrupted receipt data".utf8)
        try damaged.write(to: file, options: .atomic)
        let restored = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertTrue(restored.receipts.isEmpty)
        XCTAssertNotNil(restored.errorMessage)
        XCTAssertFalse(restored.record(try receipt(index: 2)))
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    func testDecodedInvalidOrWrongOwnerReceiptsFailClosedWithoutChangingFiles() throws {
        let valid = try receipt(index: 1)
        let invalid = DiaryTransferReceipt(command: valid.command, commandFingerprint: "different-fingerprint",
            acceptedAt: valid.acceptedAt, placements: valid.placements)
        try store.save([invalid], userID: owner, scope: scope)
        let file = try savedFile(), before = try Data(contentsOf: file)
        let invalidHistory = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertNotNil(invalidHistory.errorMessage)
        XCTAssertFalse(invalidHistory.record(valid))
        XCTAssertEqual(try Data(contentsOf: file), before)

        let otherDirectory = directory.appendingPathComponent("wrong-owner")
        let otherStore = EditorDraftStore(directory: otherDirectory)
        try otherStore.save([receipt(index: 3, userID: "different-owner")], userID: owner, scope: scope)
        let wrongOwnerHistory = DiaryTransferHistoryStore(userID: owner, store: otherStore, currentUserID: { self.owner })
        XCTAssertTrue(wrongOwnerHistory.receipts.isEmpty)
        XCTAssertNotNil(wrongOwnerHistory.errorMessage)
        XCTAssertFalse(wrongOwnerHistory.record(valid))
        XCTAssertEqual(try otherStore.load([DiaryTransferReceipt].self, userID: owner, scope: scope)?.value.first?.command.userID,
                       "different-owner")
    }

    func testAccountChangeClearsPresentationRejectsWritesAndKeepsBothAccountsIsolated() throws {
        var current: String? = owner
        let history = DiaryTransferHistoryStore(userID: owner, store: store, currentUserID: { current })
        let original = try receipt(index: 1)
        XCTAssertTrue(history.record(original))
        let file = try savedFile(), before = try Data(contentsOf: file)
        current = "different-owner"
        history.reload()
        XCTAssertTrue(history.receipts.isEmpty)
        XCTAssertNotNil(history.errorMessage)
        XCTAssertFalse(history.record(try receipt(index: 2)))
        XCTAssertEqual(try Data(contentsOf: file), before)

        let other = DiaryTransferHistoryStore(userID: "different-owner", store: store, currentUserID: { current })
        XCTAssertTrue(other.receipts.isEmpty)
        XCTAssertTrue(other.record(try receipt(index: 3, userID: "different-owner")))
        current = owner
        XCTAssertTrue(history.record(try receipt(index: 4)), "Returning to the owner reloads its original durable index")
        XCTAssertEqual(history.receipts.count, 2)
        XCTAssertTrue(history.receipts.contains { $0.id == original.id })
        XCTAssertTrue(history.receipts.allSatisfy { $0.command.userID == owner })
        XCTAssertEqual(DiaryTransferHistoryStore(userID: "different-owner", store: store,
            currentUserID: { "different-owner" }).receipts.count, 1)
    }

    private func receipt(index: Int, userID: String? = nil, operationID: UUID? = nil) throws -> DiaryTransferReceipt {
        let user = userID ?? owner
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let anchor = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-02-28T12:00:00Z"))
        let source = try XCTUnwrap(DiaryDayContext(userID: user, date: anchor, timeZone: zone))
        let destination = try XCTUnwrap(source.adding(days: 1))
        let food = FoodItem(id: "source-\(index)", name: "Food \(index)", calories: 100, timestamp: anchor)
        let sourceLog = DailyLog(id: source.dayKey, date: source.originalDate, meals: [Meal(name: "Lunch", foodItems: [food])])
        let destinationLog = DailyLog(id: destination.dayKey, date: destination.originalDate, meals: [])
        let acceptedAt = anchor.addingTimeInterval(3 * 86_400 + Double(index))
        let frozen = try DiaryTransferDraft(source: source, destination: destination, sourceLog: sourceLog,
                                            mode: .copy).freeze(now: acceptedAt)
        let command = try DiaryTransferCommand(id: operationID ?? frozen.id, source: source, destination: destination,
                                               mode: .copy, entries: frozen.entries)
        return try DiaryTransferRules.apply(command, source: sourceLog, destination: destinationLog, now: acceptedAt).receipt
    }

    private func savedFile() throws -> URL {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return try XCTUnwrap(files.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
    }
}
