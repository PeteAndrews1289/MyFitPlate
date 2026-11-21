import XCTest
@testable import MyFitPlateCore

@MainActor
final class TransferHealthSyncQueueTests: XCTestCase {
    private let owner = "transfer-health-owner"
    private var currentOwner: String?
    private var directory: URL!
    private var health: MockHealthKitManager!
    private var latestLog: DailyLog!

    override func setUp() {
        super.setUp()
        currentOwner = owner
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        health = MockHealthKitManager()
    }

    override func tearDown() {
        for callback in health.copiedSaveCallbacks { callback(false) }
        health.copiedSaveCallbacks = []
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func result(_ mode: DiaryTransferMode = .copy) throws -> DiaryTransferResult {
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: Date(timeIntervalSince1970: 1_700_000_000)))
        let next = try XCTUnwrap(day.adding(days: 1))
        let food = FoodItem(id: "original", name: "Rice", calories: 200, protein: 5, carbs: 40, fats: 2,
                            timestamp: day.originalDate)
        let source = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [food])])
        let destination = DailyLog(id: next.dayKey, date: next.originalDate, meals: [])
        let proposal = try DiaryTransferDraft(source: day, destination: next, sourceLog: source, mode: mode, foodIDs: [food.id])
        let value = try DiaryTransferRules.apply(proposal.freeze(), source: source, destination: destination)
        latestLog = value.destinationLog
        return value
    }

    private func queue(store: EditorDraftStore? = nil, reader: TransferHealthSyncQueue.DestinationReader? = nil) -> TransferHealthSyncQueue {
        TransferHealthSyncQueue(store: store ?? EditorDraftStore(directory: directory), healthKit: health,
            currentUserID: { self.currentOwner }, readDestination: reader ?? { _, completion in completion(.success(self.latestLog)) })
    }

    private func move(_ copied: DiaryTransferResult, sameDay: Bool = false) throws -> DiaryTransferResult {
        let source = copied.receipt.command.destination
        let destination = sameDay ? source : try XCTUnwrap(source.adding(days: 1))
        var proposal = try DiaryTransferDraft(source: source, destination: destination, sourceLog: copied.destinationLog,
            mode: .move, foodIDs: copied.receipt.placements.map { $0.destinationFood.id })
        for index in proposal.entries.indices { proposal.entries[index].destinationMealName = "Dinner" }
        return try DiaryTransferRules.apply(proposal.freeze(), source: copied.destinationLog,
            destination: sameDay ? copied.destinationLog : DailyLog(id: destination.dayKey, date: destination.originalDate, meals: []))
    }

    private func settle(_ queue: TransferHealthSyncQueue, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if !queue.status.isWorking { return }
            await Task.yield()
        }
        XCTFail("Queue did not settle", file: file, line: line)
    }

    private func waitForSave(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if !health.copiedSaveCallbacks.isEmpty { return }
            await Task.yield()
        }
        XCTFail("Expected controlled save callback", file: file, line: line)
    }

    func testAcceptedCopyAndReceiptReplaySaveExactlyItsFreshIDOnce() async throws {
        let accepted = try result()
        let value = queue()
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await settle(value)
        XCTAssertEqual(health.copiedFoods.map(\.id), accepted.receipt.placements.map { $0.destinationFood.id })
        XCTAssertNotEqual(health.copiedFoods.first?.id, "original")
        XCTAssertEqual(value.status.pendingCount, 0)
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await settle(value)
        XCTAssertEqual(health.copiedFoods.count, 1)
    }

    func testUndoWaitsForSaveCallbackThenDeletesAndStaleAcceptedReplayCannotResurrectIt() async throws {
        let accepted = try result()
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await waitForSave()
        let undone = try DiaryTransferRules.undo(accepted.receipt, source: accepted.sourceLog, destination: accepted.destinationLog)
        latestLog = undone.destinationLog
        XCTAssertTrue(value.reconcile(result: undone, userID: owner))
        XCTAssertEqual(health.copiedEvents.count, 1, "Undo cannot race a still-pending Health save")
        health.copiedSaveCallbacks.removeFirst()(true)
        await settle(value)
        let id = try XCTUnwrap(accepted.receipt.placements.first?.destinationFood.id)
        XCTAssertEqual(health.copiedEvents, ["save:\(id)", "delete:\(id)"])
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await settle(value)
        XCTAssertEqual(health.copiedFoods.count, 1)
        XCTAssertEqual(value.status.pendingCount, 0)
    }

    func testUndoAlsoCleansUpAfterAFailedSaveCallbackWhichMayHavePartiallyWritten() async throws {
        let accepted = try result()
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await waitForSave()
        let undone = try DiaryTransferRules.undo(accepted.receipt, source: accepted.sourceLog, destination: accepted.destinationLog)
        latestLog = undone.destinationLog
        XCTAssertTrue(value.reconcile(result: undone, userID: owner))
        health.copiedSaveCallbacks.removeFirst()(false)
        await settle(value)
        XCTAssertEqual(health.copiedEvents.count, 2)
        XCTAssertTrue(health.copiedEvents.last?.hasPrefix("delete:") == true)
        XCTAssertEqual(value.status.pendingCount, 0)
    }

    func testPermissionPendingSurvivesRelaunchAndOnlyExportsWhenAuthorizedAndStillPresent() async throws {
        let accepted = try result()
        health.copiedNutritionAuthorized = false
        var value: TransferHealthSyncQueue? = queue()
        XCTAssertTrue(try XCTUnwrap(value).reconcile(result: accepted, userID: owner))
        await settle(try XCTUnwrap(value))
        XCTAssertEqual(value?.status.pendingCount, 1)
        XCTAssertTrue(health.copiedEvents.isEmpty)
        XCTAssertNotNil(value?.status.message)
        value = nil
        health.copiedNutritionAuthorized = true
        let relaunched = queue()
        relaunched.activateAccount(owner)
        await settle(relaunched)
        XCTAssertEqual(health.copiedFoods.count, 1)
        XCTAssertEqual(relaunched.status.pendingCount, 0)
    }

    func testNormalEditOrDeleteInvalidationWaitsForCopySaveAndCannotBeReopenedByReplay() async throws {
        let accepted = try result()
        let id = try XCTUnwrap(accepted.receipt.placements.first?.destinationFood.id)
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await waitForSave()
        XCTAssertTrue(value.invalidateCopiedFoods(ids: [id, "unrelated-legacy-food"], userID: owner))
        XCTAssertEqual(health.copiedEvents, ["save:\(id)"])
        health.copiedSaveCallbacks.removeFirst()(true)
        await settle(value)
        XCTAssertEqual(health.copiedEvents, ["save:\(id)", "delete:\(id)"])
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await settle(value)
        XCTAssertEqual(health.copiedFoods.count, 1)
    }

    func testUnacknowledgedAttemptRestoresAndReusesSameCopyIdentity() async throws {
        let accepted = try result()
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await waitForSave()
        let crashSnapshot = directory.appendingPathExtension("crash-snapshot")
        defer { try? FileManager.default.removeItem(at: crashSnapshot) }
        try FileManager.default.copyItem(at: directory, to: crashSnapshot)
        health.copiedSaveCallbacks.removeFirst()(true)
        await settle(value)
        health.holdCopiedSaves = false
        let restored = queue(store: EditorDraftStore(directory: crashSnapshot))
        restored.activateAccount(owner)
        await settle(restored)
        XCTAssertEqual(health.copiedFoods.count, 2)
        XCTAssertEqual(health.copiedFoods[0].id, health.copiedFoods[1].id,
                       "The unacknowledged retry must reuse the same HealthKit sync identity, never a new food ID")
        XCTAssertEqual(restored.status.pendingCount, 0)
    }

    func testMoveMissingPlacementAndEditedLatestPlacementCannotExport() async throws {
        let moved = try result(.move)
        let value = queue()
        XCTAssertTrue(value.reconcile(result: moved, userID: owner))
        XCTAssertTrue(health.copiedEvents.isEmpty)
        let accepted = try result()
        var removed = accepted.destinationLog; removed.meals = []
        let stale = DiaryTransferResult(receipt: accepted.receipt, sourceLog: accepted.sourceLog, destinationLog: removed, newlyApplied: false)
        XCTAssertTrue(value.reconcile(result: stale, userID: owner))
        await settle(value)
        XCTAssertTrue(health.copiedEvents.isEmpty)
        XCTAssertEqual(value.status.pendingCount, 1, "A first-seen accepted receipt with no placement must remain honest and pending")
        XCTAssertNotNil(value.status.message)
        latestLog = accepted.destinationLog
        latestLog.meals[0].foodItems[0].calories += 10
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        await settle(value)
        XCTAssertTrue(health.copiedFoods.isEmpty, "An edited or removed placement must never be exported from stale acceptance data")
        XCTAssertTrue(health.copiedEvents.isEmpty, "An unexplained changed placement cannot authorize Health cleanup")
        XCTAssertEqual(value.status.pendingCount, 1)
        XCTAssertNotNil(value.status.message)
    }

    func testAccountChangeDuringVerificationStopsExportAndOwnerCanRetryLater() async throws {
        let accepted = try result()
        var heldRead: ((Result<DailyLog, Error>) -> Void)?
        let value = queue(reader: { _, completion in heldRead = completion })
        XCTAssertTrue(value.reconcile(result: accepted, userID: owner))
        for _ in 0..<300 { if heldRead != nil { break }; await Task.yield() }
        currentOwner = "other"
        try XCTUnwrap(heldRead)(.success(accepted.destinationLog))
        heldRead = nil
        await settle(value)
        XCTAssertTrue(health.copiedEvents.isEmpty)
        value.activateAccount("other")
        XCTAssertEqual(value.status.pendingCount, 0)
        XCTAssertFalse(value.reconcile(result: accepted, userID: owner))
        currentOwner = owner
        value.retryPending(userID: owner)
        for _ in 0..<300 { if heldRead != nil { break }; await Task.yield() }
        try XCTUnwrap(heldRead)(.success(accepted.destinationLog))
        await settle(value)
        XCTAssertEqual(health.copiedFoods.count, 1)
    }

    func testUnreadableCheckpointFailsClosedAndNeverTouchesHealth() throws {
        let accepted = try result()
        let store = EditorDraftStore(directory: directory)
        try store.save(["unrelated": "preserve"], userID: owner, scope: "diary-transfer-health")
        let value = queue(store: store)
        XCTAssertFalse(value.reconcile(result: accepted, userID: owner))
        XCTAssertTrue(health.copiedEvents.isEmpty)
        XCTAssertNotNil(value.status.message)
        XCTAssertEqual(try store.load([String: String].self, userID: owner, scope: "diary-transfer-health")?.value, ["unrelated": "preserve"])
    }

    func testMalformedReceiptAndMismatchedDestinationCannotQueueHealthEffects() throws {
        let accepted = try result()
        let malformed = DiaryTransferReceipt(command: accepted.receipt.command, commandFingerprint: "incorrect-fingerprint",
            acceptedAt: accepted.receipt.acceptedAt, placements: accepted.receipt.placements)
        let invalid = DiaryTransferResult(receipt: malformed, sourceLog: accepted.sourceLog,
                                           destinationLog: accepted.destinationLog, newlyApplied: true)
        let value = queue()
        XCTAssertFalse(value.reconcile(result: invalid, userID: owner))
        XCTAssertFalse(value.status.isWorking)
        XCTAssertNotNil(value.status.message)
        var wrongDay = accepted.destinationLog; wrongDay.id = "2000-01-01"
        XCTAssertFalse(value.reconcile(result: DiaryTransferResult(receipt: accepted.receipt, sourceLog: accepted.sourceLog,
            destinationLog: wrongDay, newlyApplied: false), userID: owner))
        XCTAssertTrue(health.copiedEvents.isEmpty)
        XCTAssertEqual(value.status.pendingCount, 0)
    }

    func testDeniedCopyThenMoveAndCopyReplayRestoreOriginalExportFromNewPlacementOnce() async throws {
        let copied = try result()
        let moved = try move(copied)
        var logs = [copied.receipt.command.destination.dayKey: copied.destinationLog]
        var requested: [String] = []
        let reader: TransferHealthSyncQueue.DestinationReader = { day, completion in
            requested.append(day.dayKey)
            completion(.success(logs[day.dayKey]!))
        }
        health.copiedNutritionAuthorized = false
        var value: TransferHealthSyncQueue? = queue(reader: reader)
        XCTAssertTrue(try XCTUnwrap(value).reconcile(result: copied, userID: owner))
        await settle(try XCTUnwrap(value))
        logs[moved.receipt.command.source.dayKey] = moved.sourceLog
        logs[moved.receipt.command.destination.dayKey] = moved.destinationLog
        XCTAssertTrue(try XCTUnwrap(value).reconcile(result: moved, userID: owner))
        await settle(try XCTUnwrap(value))
        let copyReplay = DiaryTransferResult(receipt: copied.receipt, sourceLog: copied.sourceLog,
            destinationLog: moved.sourceLog, newlyApplied: false)
        XCTAssertTrue(try XCTUnwrap(value).reconcile(result: copyReplay, userID: owner))
        await settle(try XCTUnwrap(value))
        XCTAssertTrue(health.copiedEvents.isEmpty)
        value = nil
        health.copiedNutritionAuthorized = true
        let restored = queue(reader: reader)
        restored.activateAccount(owner)
        await settle(restored)
        XCTAssertEqual(requested, [moved.receipt.command.destination.dayKey])
        XCTAssertEqual(health.copiedFoods.map(\.id), copied.receipt.placements.map { $0.destinationFood.id })
        XCTAssertEqual(health.copiedFoods.first?.timestamp, copied.receipt.placements.first?.destinationFood.timestamp)
        XCTAssertEqual(health.copiedEvents.count, 1)
        XCTAssertEqual(restored.status.pendingCount, 0)
    }

    func testUndoMoveRestoresPendingCopyLocationAndStaleForwardMoveCannotRedirectRetry() async throws {
        let copied = try result()
        let moved = try move(copied, sameDay: true)
        let undone = try DiaryTransferRules.undo(moved.receipt, source: moved.sourceLog, destination: moved.destinationLog)
        var logs = [copied.receipt.command.destination.dayKey: copied.destinationLog]
        var requested: [String] = []
        let reader: TransferHealthSyncQueue.DestinationReader = { day, completion in
            requested.append(day.dayKey); completion(.success(logs[day.dayKey]!))
        }
        health.copiedNutritionAuthorized = false
        let value = queue(reader: reader)
        XCTAssertTrue(value.reconcile(result: copied, userID: owner)); await settle(value)
        logs[moved.receipt.command.destination.dayKey] = moved.destinationLog
        XCTAssertTrue(value.reconcile(result: moved, userID: owner)); await settle(value)
        logs[undone.receipt.command.source.dayKey] = undone.sourceLog
        XCTAssertTrue(value.reconcile(result: undone, userID: owner)); await settle(value)
        XCTAssertTrue(value.reconcile(result: moved, userID: owner)); await settle(value)
        health.copiedNutritionAuthorized = true
        value.retryPending(userID: owner); await settle(value)
        XCTAssertEqual(requested, [copied.receipt.command.destination.dayKey])
        XCTAssertEqual(health.copiedEvents.count, 1)
        XCTAssertEqual(health.copiedFoods.first?.id, copied.receipt.placements.first?.destinationFood.id)
        XCTAssertEqual(health.copiedFoods.first?.timestamp, copied.receipt.placements.first?.destinationFood.timestamp)
        XCTAssertEqual(value.status.pendingCount, 0)
    }

    func testMoveAndItsUndoRejectStaleInFlightVerificationAtBothFormerLocations() async throws {
        let copied = try result()
        let moved = try move(copied)
        let undone = try DiaryTransferRules.undo(moved.receipt, source: moved.sourceLog, destination: moved.destinationLog)
        var logs = [copied.receipt.command.destination.dayKey: copied.destinationLog]
        var requested: [String] = []
        var pending: [(Result<DailyLog, Error>) -> Void] = []
        let value = queue(reader: { day, completion in
            requested.append(day.dayKey)
            if requested.count <= 2 { pending.append(completion) } else { completion(.success(logs[day.dayKey]!)) }
        })
        XCTAssertTrue(value.reconcile(result: copied, userID: owner))
        for _ in 0..<300 { if pending.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(pending.count, 1)
        logs[moved.receipt.command.source.dayKey] = moved.sourceLog
        logs[moved.receipt.command.destination.dayKey] = moved.destinationLog
        XCTAssertTrue(value.reconcile(result: moved, userID: owner))
        try XCTUnwrap(pending.first)(.failure(URLError(.notConnectedToInternet))); pending.removeFirst()
        for _ in 0..<300 { if pending.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(requested, [copied.receipt.command.destination.dayKey, moved.receipt.command.destination.dayKey])
        logs[undone.receipt.command.source.dayKey] = undone.sourceLog
        logs[undone.receipt.command.destination.dayKey] = undone.destinationLog
        XCTAssertTrue(value.reconcile(result: undone, userID: owner))
        try XCTUnwrap(pending.first)(.success(undone.destinationLog)); pending.removeFirst()
        await settle(value)
        XCTAssertEqual(requested, [copied.receipt.command.destination.dayKey, moved.receipt.command.destination.dayKey,
                                   copied.receipt.command.destination.dayKey])
        XCTAssertEqual(health.copiedEvents.count, 1, "Old-location errors or empty logs cannot delete a relocated copy")
        XCTAssertTrue(health.copiedEvents.first?.hasPrefix("save:") == true)
        XCTAssertEqual(value.status.pendingCount, 0)
    }

    func testMoveDuringCopiedSavePreservesExportUntilAnOrdinaryRemovalInvalidatesIt() async throws {
        let copied = try result()
        let moved = try move(copied)
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: copied, userID: owner))
        await waitForSave()
        latestLog = moved.destinationLog
        XCTAssertTrue(value.reconcile(result: moved, userID: owner))
        XCTAssertEqual(health.copiedEvents.count, 1)
        health.copiedSaveCallbacks.removeFirst()(true)
        await settle(value)
        XCTAssertEqual(health.copiedEvents.count, 1, "MOVE cannot schedule nutrition cleanup after an in-flight copy save")
        let undone = try DiaryTransferRules.undo(moved.receipt, source: moved.sourceLog, destination: moved.destinationLog)
        latestLog = undone.sourceLog
        XCTAssertTrue(value.reconcile(result: undone, userID: owner)); await settle(value)
        XCTAssertEqual(health.copiedEvents.count, 1, "Undoing MOVE also retains the original consumption")
        let id = try XCTUnwrap(copied.receipt.placements.first?.destinationFood.id)
        XCTAssertTrue(value.invalidateCopiedFoods(ids: [id], userID: owner)); await settle(value)
        XCTAssertEqual(health.copiedEvents, ["save:\(id)", "delete:\(id)"])
        XCTAssertEqual(health.copiedFoods.first?.timestamp, copied.receipt.placements.first?.destinationFood.timestamp)
    }

    func testUnreportedMoveAfterUnacknowledgedCopyAttemptPausesOnRelaunchUntilExplicitRemoval() async throws {
        let copied = try result()
        health.holdCopiedSaves = true
        let value = queue()
        XCTAssertTrue(value.reconcile(result: copied, userID: owner))
        await waitForSave()
        let crashSnapshot = directory.appendingPathExtension("unreported-move")
        defer { try? FileManager.default.removeItem(at: crashSnapshot) }
        try FileManager.default.copyItem(at: directory, to: crashSnapshot)
        health.copiedSaveCallbacks.removeFirst()(true)
        await settle(value)
        let moved = try move(copied)
        latestLog = moved.sourceLog // MOVE committed, but its local acknowledgement was lost.
        health.holdCopiedSaves = false
        let restored = queue(store: EditorDraftStore(directory: crashSnapshot))
        restored.activateAccount(owner)
        await settle(restored)
        XCTAssertEqual(restored.status.pendingCount, 1)
        XCTAssertNotNil(restored.status.message)
        XCTAssertEqual(health.copiedEvents.count, 1, "Missing at the former location cannot trigger another save or cleanup")
        let replay = DiaryTransferResult(receipt: copied.receipt, sourceLog: copied.sourceLog,
            destinationLog: moved.sourceLog, newlyApplied: false)
        XCTAssertTrue(restored.reconcile(result: replay, userID: owner)); await settle(restored)
        XCTAssertEqual(restored.status.pendingCount, 1)
        XCTAssertEqual(health.copiedEvents.count, 1, "A COPY replay with a missing placement also cannot infer deletion")
        let id = try XCTUnwrap(copied.receipt.placements.first?.destinationFood.id)
        XCTAssertTrue(restored.invalidateCopiedFoods(ids: [id], userID: owner)); await settle(restored)
        XCTAssertEqual(health.copiedEvents, ["save:\(id)", "delete:\(id)"])
        XCTAssertEqual(restored.status.pendingCount, 0)
    }
}
