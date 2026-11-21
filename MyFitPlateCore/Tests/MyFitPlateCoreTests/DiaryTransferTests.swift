import XCTest
@testable import MyFitPlateCore

@MainActor
final class DiaryTransferTests: XCTestCase {
    private let owner = "diary-transfer-owner"
    private var source: DiaryDayContext!
    private var destination: DiaryDayContext!
    private var sourceMeal: Meal!
    private var sourceLog: DailyLog!
    private var destinationLog: DailyLog!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        let zone = TimeZone(identifier: "America/New_York")!
        source = DiaryDayContext(userID: owner, date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: zone)
        destination = source.adding(days: 1)
        sourceMeal = Meal(name: "Breakfast", foodItems: [food("oats", calories: 200), food("milk", calories: 100)])
        sourceLog = DailyLog(id: source.dayKey, date: source.originalDate, meals: [sourceMeal],
                            totalCaloriesOverride: 700, waterTracker: WaterTracker(totalOunces: 16, date: source.originalDate))
        destinationLog = DailyLog(id: destination.dayKey, date: destination.originalDate,
                                 meals: [Meal(name: "Dinner", foodItems: [food("existing", calories: 500)])],
                                 totalCaloriesOverride: 900, waterTracker: WaterTracker(totalOunces: 8, date: destination.originalDate))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func food(_ id: String, calories: Double) -> FoodItem {
        FoodItem(id: id, name: id.capitalized, calories: calories, protein: 10, carbs: 20, fats: 4, fiber: 3,
                 servingSize: "2 x cup", servingWeight: 200, timestamp: Date(timeIntervalSince1970: 1_699_990_000),
                 sourceMetadata: .userEntered(sourceName: "Historical label"), calcium: 140, vitaminC: 12,
                 quantityValue: 2, servingUnit: "cup")
    }

    private func draft(_ mode: DiaryTransferMode = .copy, ids: [String]? = ["oats"], sameDay: Bool = false) throws -> DiaryTransferDraft {
        try DiaryTransferDraft(source: source, destination: sameDay ? source : destination,
                               sourceLog: sourceLog, mode: mode, foodIDs: ids)
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    func testCopyCreatesFreshConsumptionAndPreservesSourceNutritionAndDayMetadata() throws {
        var proposal = try draft()
        proposal.entries[0].destinationMealName = "Dinner"
        let command = try proposal.freeze(now: Date(timeIntervalSince1970: 1_700_100_000))
        let result = try DiaryTransferRules.apply(command, source: sourceLog, destination: destinationLog)
        XCTAssertEqual(try encoded(result.sourceLog), try encoded(sourceLog))
        let original = sourceMeal.foodItems[0]
        let copied = try XCTUnwrap(result.destinationLog.meals.first?.foodItems.last)
        XCTAssertNotEqual(copied.id, original.id)
        XCTAssertEqual(copied.calories, original.calories)
        XCTAssertEqual(copied.calcium, original.calcium)
        XCTAssertEqual(copied.vitaminC, original.vitaminC)
        XCTAssertEqual(copied.quantityValue, original.quantityValue)
        XCTAssertEqual(try encoded(copied.sourceMetadata), try encoded(original.sourceMetadata))
        XCTAssertEqual(result.destinationLog.waterTracker, destinationLog.waterTracker)
        XCTAssertEqual(result.destinationLog.totalCaloriesOverride, 900)
        XCTAssertEqual(sourceLog.totalCalories(), 300)
        try result.receipt.validate()
    }

    func testSameDayMoveRetainsIdentityAndExactNutrition() throws {
        var proposal = try draft(.move, sameDay: true)
        proposal.entries[0].destinationMealName = "Lunch"
        let result = try DiaryTransferRules.apply(proposal.freeze(), source: sourceLog, destination: sourceLog)
        XCTAssertEqual(result.sourceLog.meals.first?.foodItems.map(\.id), ["milk"])
        let moved = try XCTUnwrap(result.destinationLog.meals.last?.foodItems.first)
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(moved, sourceMeal.foodItems[0]))
        XCTAssertEqual(try encoded(result.sourceLog), try encoded(result.destinationLog))
        XCTAssertEqual(result.sourceLog.waterTracker, sourceLog.waterTracker)
        XCTAssertEqual(result.sourceLog.totalCaloriesOverride, 700)
    }

    func testMoveRefusesEditedMissingOrRehomedSourceAndDestinationCollision() throws {
        let command = try draft(.move).freeze()
        var changed = sourceLog!
        changed.meals[0].foodItems[0].calories = 210
        XCTAssertThrowsError(try DiaryTransferRules.apply(command, source: changed, destination: destinationLog))
        changed.meals[0].foodItems.removeFirst()
        XCTAssertThrowsError(try DiaryTransferRules.apply(command, source: changed, destination: destinationLog))
        changed = sourceLog; changed.meals[0].id = UUID()
        XCTAssertThrowsError(try DiaryTransferRules.apply(command, source: changed, destination: destinationLog))
        var collision = destinationLog!; collision.meals[0].foodItems.append(sourceMeal.foodItems[0])
        XCTAssertThrowsError(try DiaryTransferRules.apply(command, source: sourceLog, destination: collision))
        XCTAssertEqual(sourceLog.meals[0].foodItems.count, 2)
    }

    func testCrossDayMoveUndoTargetsOnlyTransferredFoodsAndPreservesNewEntries() throws {
        let result = try DiaryTransferRules.apply(draft(.move).freeze(), source: sourceLog, destination: destinationLog)
        var newerSource = result.sourceLog
        newerSource.meals[0].name = "Morning meal"
        newerSource.meals[0].foodItems.append(food("new-source", calories: 50))
        var newerDestination = result.destinationLog
        newerDestination.meals[0].foodItems.append(food("new-destination", calories: 70))
        let undo = try DiaryTransferRules.undo(result.receipt, source: newerSource, destination: newerDestination)
        XCTAssertEqual(undo.sourceLog.meals[0].name, "Morning meal")
        XCTAssertEqual(Set(undo.sourceLog.meals.flatMap(\.foodItems).map(\.id)), ["oats", "milk", "new-source"])
        XCTAssertEqual(Set(undo.destinationLog.meals.flatMap(\.foodItems).map(\.id)), ["existing", "new-destination"])
        XCTAssertEqual(undo.sourceLog.waterTracker, sourceLog.waterTracker)
        XCTAssertEqual(undo.destinationLog.totalCaloriesOverride, 900)
        XCTAssertNotNil(undo.receipt.undoneAt)
        XCTAssertFalse(try DiaryTransferRules.undo(undo.receipt, source: undo.sourceLog, destination: undo.destinationLog).newlyApplied)
    }

    func testUndoRefusesToOverwriteAnEditedOrRemovedTransferredFood() throws {
        let result = try DiaryTransferRules.apply(draft().freeze(), source: sourceLog, destination: destinationLog)
        let placement = try XCTUnwrap(result.receipt.placements.first)
        var changed = result.destinationLog
        let index = try XCTUnwrap(changed.meals.firstIndex { $0.id == placement.destinationMealID })
        changed.meals[index].foodItems[0].protein = 99
        XCTAssertThrowsError(try DiaryTransferRules.undo(result.receipt, source: result.sourceLog, destination: changed))
        changed.meals[index].foodItems.removeAll()
        XCTAssertThrowsError(try DiaryTransferRules.undo(result.receipt, source: result.sourceLog, destination: changed))
    }

    func testWholeDayCopySupportsExclusionPortionsAndMealMappingWithStableIDs() throws {
        var proposal = try draft(ids: nil)
        proposal.entries[0].multiplier = 1.5
        proposal.entries[0].destinationMealName = "Dinner"
        proposal.entries[1].isIncluded = false
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let first = try proposal.freeze(now: now)
        let roundTrip = try JSONDecoder().decode(DiaryTransferDraft.self, from: encoded(proposal))
        let second = try roundTrip.freeze(now: now)
        XCTAssertEqual(try first.fingerprint(), try second.fingerprint())
        let result = try DiaryTransferRules.apply(second, source: sourceLog, destination: destinationLog)
        let copied = try XCTUnwrap(result.destinationLog.meals[0].foodItems.last)
        XCTAssertEqual(copied.calories, 300)
        XCTAssertEqual(copied.calcium, 210)
        XCTAssertEqual(copied.quantityValue, 3)
        XCTAssertEqual(result.receipt.placements.count, 1)
        XCTAssertEqual(sourceLog.totalCalories(), 300)
        var invalidMove = try draft(.move); invalidMove.entries[0].multiplier = 0.5
        XCTAssertThrowsError(try invalidMove.freeze())
    }

    func testOnlyNewProposalChecksFutureDayAndHistoricalCopiesUseCapturedDestinationTimeZone() throws {
        let proposal = try draft()
        XCTAssertThrowsError(try proposal.freeze(now: source.originalDate)) { error in
            XCTAssertEqual(error as? DiaryTransferError, .futureDay)
        }
        let later = try XCTUnwrap(destination.adding(days: 2))
        let command = try proposal.freeze(now: later.displayDate)
        let copied = try XCTUnwrap(command.entries.first?.destinationFood)
        XCTAssertEqual(DiaryDayContext.dayKey(for: try XCTUnwrap(copied.timestamp), timeZone: destination.timeZone), destination.dayKey)
        let restored = try JSONDecoder().decode(DiaryTransferCommand.self, from: encoded(command))
        XCTAssertNoThrow(try restored.validate(), "Frozen retries validate their payload, without retargeting against a new clock")
        let today = try draft(sameDay: true).freeze(now: source.originalDate.addingTimeInterval(0.123456))
        XCTAssertEqual(today.entries.first?.destinationFood.timestamp?.timeIntervalSince1970,
                       floor(source.originalDate.timeIntervalSince1970), "New copies use stable whole seconds without changing original timestamps")
    }

    func testOversizeSelectionAndPayloadAreRejectedBeforeAnyRepositoryWrite() throws {
        let many = (0..<101).map { food("food-\($0)", calories: 10) }
        let largeLog = DailyLog(id: source.dayKey, date: source.originalDate, meals: [Meal(name: "Lunch", foodItems: many)])
        let proposal = try DiaryTransferDraft(source: source, destination: destination, sourceLog: largeLog, mode: .copy)
        XCTAssertThrowsError(try proposal.freeze()) { error in XCTAssertEqual(error as? DiaryTransferError, .tooLarge) }
        var largeFood = food("large-label", calories: 10); largeFood.name = String(repeating: "a", count: 110_000)
        let oversized = DailyLog(id: source.dayKey, date: source.originalDate, meals: [Meal(name: "Lunch", foodItems: [largeFood])])
        XCTAssertThrowsError(try DiaryTransferDraft(source: source, destination: destination, sourceLog: oversized, mode: .copy).freeze()) {
            XCTAssertEqual($0 as? DiaryTransferError, .tooLarge)
        }
    }

    func testCopyUndoKeepsSourceEditsAndUnrelatedDestinationAdditions() throws {
        var proposal = try draft(sameDay: true); proposal.entries[0].destinationMealName = "Breakfast"
        let result = try DiaryTransferRules.apply(proposal.freeze(), source: sourceLog, destination: sourceLog)
        var current = result.destinationLog
        current.meals[0].foodItems[0].calories = 333
        current.meals[0].foodItems.append(food("new", calories: 50))
        let undo = try DiaryTransferRules.undo(result.receipt, source: current, destination: current)
        XCTAssertEqual(undo.destinationLog.meals[0].foodItems.map(\.id), ["oats", "milk", "new"])
        XCTAssertEqual(undo.destinationLog.meals[0].foodItems[0].calories, 333)
    }

    func testRepositoryReceiptMakesApplyAndUndoIdempotentAfterAmbiguousAcknowledgement() async throws {
        let repository = MockNutritionRepository()
        repository.mockLogsByDay = [sourceLog, destinationLog]
        let command = try draft(.move).freeze()
        repository.diaryTransferFailureAfterCommit = CocoaError(.fileReadUnknown)
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: command); XCTFail("Expected ambiguous ack") } catch {}
        repository.diaryTransferFailureAfterCommit = nil
        let replay = try await repository.applyDiaryTransfer(userID: owner, command: command)
        XCTAssertFalse(replay.newlyApplied)
        XCTAssertEqual(repository.appliedDiaryTransferIDs, [command.id])
        XCTAssertEqual(replay.sourceLog.meals.flatMap(\.foodItems).map(\.id), ["milk"])
        repository.diaryTransferFailureAfterCommit = CocoaError(.fileReadUnknown)
        do { _ = try await repository.undoDiaryTransfer(userID: owner, receipt: replay.receipt); XCTFail("Expected ambiguous Undo ack") } catch {}
        repository.diaryTransferFailureAfterCommit = nil
        let undone = try await repository.undoDiaryTransfer(userID: owner, receipt: replay.receipt)
        XCTAssertFalse(undone.newlyApplied)
        XCTAssertEqual(repository.undoneDiaryTransferIDs, [command.id])
        XCTAssertEqual(Set(undone.sourceLog.meals.flatMap(\.foodItems).map(\.id)), ["oats", "milk"])
    }

    func testStableOperationCannotBeReusedForAnotherPayload() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let command = try draft().freeze()
        _ = try await repository.applyDiaryTransfer(userID: owner, command: command)
        let changed = try DiaryTransferCommand(id: command.id, source: command.source, destination: command.destination,
            mode: command.mode, entries: command.entries.map { entry in
                DiaryTransferCommand.Entry(originalFood: entry.originalFood, originalMealID: entry.originalMealID,
                    originalMealName: entry.originalMealName, destinationFood: entry.destinationFood,
                    destinationMealName: "Snacks", proposedMealID: entry.proposedMealID)
            })
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: changed); XCTFail("Cannot retarget a receipt") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .receiptMismatch)
        }
        XCTAssertEqual(repository.appliedDiaryTransferIDs, [command.id])
    }

    func testReadOnlyReceiptFetchCannotCreateMissingTransferAndAllowsPendingLocalDays() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let command = try draft(.move).freeze()
        do { _ = try await repository.fetchDiaryTransfer(userID: owner, command: command); XCTFail("Read must not create a receipt") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .receiptMissing)
        }
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        let accepted = try await repository.applyDiaryTransfer(userID: owner, command: command)
        repository.diaryTransferPendingDayKeys = [source.dayKey, destination.dayKey]
        let read = try await repository.fetchDiaryTransfer(userID: owner, command: command)
        XCTAssertFalse(read.newlyApplied)
        XCTAssertEqual(read.receipt.commandFingerprint, accepted.receipt.commandFingerprint)
        XCTAssertEqual(read.sourceLog.meals.flatMap(\.foodItems).map(\.id), ["milk"])
        XCTAssertEqual(repository.appliedDiaryTransferIDs, [command.id])
    }

    func testSessionKeepsFrozenCommandAcrossOfflineFailureRelaunchAndRetry() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        repository.diaryTransferError = URLError(.notConnectedToInternet)
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(.move), store: store, currentUserID: { self.owner })
        let offlineResult = await session.submit(using: repository)
        XCTAssertNil(offlineResult)
        let command = try XCTUnwrap(session.command)
        XCTAssertTrue(session.isFrozen)
        XCTAssertFalse(session.discardProposal())
        XCTAssertFalse(session.updateDraft { $0.entries.removeAll() })
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        let restored = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertEqual(try restored.command?.fingerprint(), try command.fingerprint())
        repository.diaryTransferError = nil
        let accepted = await restored.submit(using: repository)
        XCTAssertNotNil(accepted)
        XCTAssertEqual(repository.appliedDiaryTransferIDs, [command.id])
        XCTAssertTrue(restored.finish())
        XCTAssertNil(DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner }).checkpoint)
    }

    func testSessionRejectsAccountSwitchAndKeepsOldOwnerCheckpoint() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let store = EditorDraftStore(directory: directory)
        var activeOwner = owner
        let session = DiaryTransferSession(userID: owner, draft: try draft(), store: store, currentUserID: { activeOwner })
        activeOwner = "other-owner"
        let switchedResult = await session.submit(using: repository)
        XCTAssertNil(switchedResult)
        XCTAssertFalse(session.updateDraft { $0.entries.removeAll() })
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        XCTAssertNil(DiaryTransferSession(userID: activeOwner, store: store, currentUserID: { activeOwner }).checkpoint)
        activeOwner = owner
        XCTAssertNotNil(DiaryTransferSession(userID: owner, store: store, currentUserID: { activeOwner }).draft)
    }

    func testSessionRecoversAnAlreadyCommittedTransferAndSubmittedUndoAfterRelaunch() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(.move), store: store, currentUserID: { self.owner })
        repository.diaryTransferFailureAfterCommit = URLError(.networkConnectionLost)
        let ambiguous = await session.submit(using: repository)
        XCTAssertNil(ambiguous)
        let operationID = try XCTUnwrap(session.command?.id)
        repository.diaryTransferFailureAfterCommit = nil
        let restored = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
        let accepted = await restored.submit(using: repository)
        XCTAssertEqual(accepted?.newlyApplied, false)
        repository.diaryTransferFailureAfterCommit = URLError(.networkConnectionLost)
        let uncertainUndo = await restored.undo(using: repository)
        XCTAssertNil(uncertainUndo)
        XCTAssertEqual(restored.checkpoint?.undoSubmitted, true)
        repository.diaryTransferFailureAfterCommit = nil
        let resumed = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
        let undone = await resumed.undo(using: repository)
        XCTAssertNotNil(undone?.receipt.undoneAt)
        XCTAssertEqual(undone?.newlyApplied, false)
        XCTAssertEqual(repository.appliedDiaryTransferIDs, [operationID])
        XCTAssertEqual(repository.undoneDiaryTransferIDs, [operationID])
        XCTAssertTrue(resumed.finish())
    }

    func testHistoryUndoReconstructsFrozenIdentityAndCannotReplaceAnotherPendingIntent() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let command = try draft(.move).freeze()
        let accepted = try await repository.applyDiaryTransfer(userID: owner, command: command)
        let store = EditorDraftStore(directory: directory)
        let history = DiaryTransferSession(userID: owner, store: store, scope: "history-undo", currentUserID: { self.owner })
        XCTAssertTrue(history.prepareUndo(of: accepted.receipt))
        XCTAssertEqual(history.draft?.id, command.id)
        XCTAssertEqual(history.draft?.entries.map(\.destinationFoodID), command.entries.map { $0.destinationFood.id })
        XCTAssertTrue(history.isFrozen)
        let reopened = DiaryTransferSession(userID: owner, store: store, scope: "history-undo", currentUserID: { self.owner })
        let undone = await reopened.undo(using: repository)
        XCTAssertNotNil(undone?.receipt.undoneAt)
        let pending = DiaryTransferSession(userID: owner, draft: try draft(ids: ["milk"]), store: store,
                                          scope: "separate-intent", currentUserID: { self.owner })
        let pendingID = pending.draft?.id
        XCTAssertFalse(pending.prepareUndo(of: accepted.receipt))
        XCTAssertEqual(pending.draft?.id, pendingID)
        XCTAssertNil(pending.command)
    }

    func testOpeningAcceptedAndUndoneHistoryCanFinishWithoutSubmittingUndo() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let accepted = try await repository.applyDiaryTransfer(userID: owner, command: draft(.move).freeze())
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
        XCTAssertTrue(session.prepareUndo(of: accepted.receipt))
        XCTAssertEqual(session.checkpoint?.undoSubmitted, false)
        XCTAssertTrue(session.finish(), "Opening accepted history is presentation, not an Undo submission")
        XCTAssertTrue(repository.undoneDiaryTransferIDs.isEmpty)
        let undone = try await repository.undoDiaryTransfer(userID: owner, receipt: accepted.receipt)
        XCTAssertTrue(session.prepareUndo(of: undone.receipt))
        XCTAssertEqual(session.checkpoint?.undoSubmitted, false)
        XCTAssertTrue(session.finish(), "An already-undone row must not trap the global transfer checkpoint")
        XCTAssertNil(DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner }).checkpoint)
    }

    func testRejectedFrozenTransferCanBeCancelledAndPermanentFenceRejectsALateApply() async throws {
        let repository = MockNutritionRepository()
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(.move), store: store, currentUserID: { self.owner })
        var changed = sourceLog!; changed.meals[0].foodItems[0].calories = 333
        repository.mockLogsByDay = [changed, destinationLog]
        let rejected = await session.submit(using: repository)
        XCTAssertNil(rejected)
        let frozen = try XCTUnwrap(session.command)
        XCTAssertFalse(session.discardProposal())
        let cancelled = await session.cancelUnaccepted(using: repository)
        XCTAssertTrue(cancelled)
        XCTAssertNil(session.checkpoint)
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: frozen); XCTFail("Late submission must see permanent fence") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .cancelled)
        }
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
    }

    func testCancellationCannotDiscardAnAcceptedTransferWhoseAcknowledgementWasLost() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let session = DiaryTransferSession(userID: owner, draft: try draft(.move), store: EditorDraftStore(directory: directory),
                                           currentUserID: { self.owner })
        repository.diaryTransferFailureAfterCommit = URLError(.networkConnectionLost)
        let ambiguous = await session.submit(using: repository)
        XCTAssertNil(ambiguous)
        repository.diaryTransferFailureAfterCommit = nil
        let cancelled = await session.cancelUnaccepted(using: repository)
        XCTAssertFalse(cancelled)
        XCTAssertNotNil(session.receipt)
        XCTAssertEqual(session.lastVerifiedResult?.newlyApplied, false)
        XCTAssertEqual(session.lastVerifiedResult?.sourceLog.meals.flatMap(\.foodItems).map(\.id), ["milk"])
        XCTAssertTrue(session.finish())
    }

    func testCancellationLostAcknowledgementRetainsFrozenIntentUntilFenceIsConfirmedAfterRelaunch() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(), store: store, currentUserID: { self.owner })
        repository.diaryTransferError = URLError(.notConnectedToInternet)
        let offline = await session.submit(using: repository)
        XCTAssertNil(offline)
        let command = try XCTUnwrap(session.command)
        repository.diaryTransferError = nil; repository.diaryTransferFailureAfterCommit = URLError(.networkConnectionLost)
        let uncertain = await session.cancelUnaccepted(using: repository)
        XCTAssertFalse(uncertain); XCTAssertNotNil(session.checkpoint)
        repository.diaryTransferFailureAfterCommit = nil
        let restored = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
        let confirmed = await restored.cancelUnaccepted(using: repository)
        XCTAssertTrue(confirmed)
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: command); XCTFail("Cancelled copy must not commit") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .cancelled)
        }
    }

    func testConflictedUndoCanVerifyCanonicalReceiptAndFinishButOfflineRefreshKeepsIntent() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        repository.persistsDailyLogUpdates = true
        let session = DiaryTransferSession(userID: owner, draft: try draft(.move), store: EditorDraftStore(directory: directory),
                                           currentUserID: { self.owner })
        let forward = await session.submit(using: repository)
        var changed = try XCTUnwrap(forward?.destinationLog)
        let index = try XCTUnwrap(changed.meals.firstIndex { $0.foodItems.contains { $0.id == "oats" } })
        let foodIndex = try XCTUnwrap(changed.meals[index].foodItems.firstIndex { $0.id == "oats" })
        changed.meals[index].foodItems[foodIndex].protein = 99
        try await repository.saveDailyLog(userID: owner, log: changed)
        let conflict = await session.undo(using: repository)
        XCTAssertNil(conflict); XCTAssertEqual(session.checkpoint?.undoSubmitted, true)
        XCTAssertFalse(session.finish())
        repository.diaryTransferError = URLError(.notConnectedToInternet)
        let offline = await session.refresh(using: repository)
        XCTAssertNil(offline); XCTAssertEqual(session.checkpoint?.undoSubmitted, true)
        repository.diaryTransferError = nil
        let refreshed = await session.refresh(using: repository)
        XCTAssertNotNil(refreshed); XCTAssertNil(refreshed?.receipt.undoneAt)
        XCTAssertEqual(session.checkpoint?.undoSubmitted, false)
        XCTAssertTrue(session.finish())
        XCTAssertTrue(repository.undoneDiaryTransferIDs.isEmpty)
    }

    func testRepositoryBarriersRejectPendingDaysAndDeletedOwnersWithoutPartialMove() async throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog, destinationLog]
        let command = try draft(.move).freeze()
        repository.diaryTransferPendingDayKeys = [source.dayKey]
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: command); XCTFail("Pending source must block") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .pendingWrites)
        }
        repository.diaryTransferPendingDayKeys = []
        repository.diaryTransferBlockedUserIDs = [owner]
        do { _ = try await repository.applyDiaryTransfer(userID: owner, command: command); XCTFail("Deleted account must block") } catch {
            XCTAssertEqual(error as? DiaryTransferError, .accountChanged)
        }
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
        let actual = await withCheckedContinuation { continuation in
            repository.fetchLogInternal(userID: owner, day: source) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(try actual.get().totalCalories(), 300)
    }

    func testExactDayPathSurvivesTimezoneTravelAndUnreadableCheckpointIsNotOverwritten() throws {
        let repository = MockNutritionRepository(); repository.mockLogsByDay = [sourceLog]
        let traveled = try XCTUnwrap(DiaryDayContext(userID: owner, date: source.originalDate,
            timeZone: TimeZone(identifier: "Pacific/Honolulu")!, dayKey: source.dayKey))
        var result: Result<DailyLog, Error>?
        repository.fetchLogInternal(userID: owner, day: traveled) { result = $0 }
        XCTAssertEqual(try result?.get().id, source.dayKey)
        XCTAssertEqual(repository.fetchedDiaryDayKeys, [source.dayKey])
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(), store: store, currentUserID: { self.owner })
        XCTAssertNotNil(session.draft)
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        let relativeFile = try XCTUnwrap(files.first)
        let file = directory.appendingPathComponent(relativeFile)
        let corrupt = Data("unreadable transfer - keep".utf8); try corrupt.write(to: file)
        let reopened = DiaryTransferSession(userID: owner, draft: try draft(), store: store, currentUserID: { self.owner })
        XCTAssertTrue(reopened.isUnreadable)
        XCTAssertFalse(reopened.discardProposal())
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testUnknownOrMissingCommandVersionFailsClosedAndPreservesCheckpointBytes() async throws {
        let repository = MockNutritionRepository(); repository.diaryTransferError = URLError(.notConnectedToInternet)
        let store = EditorDraftStore(directory: directory)
        let session = DiaryTransferSession(userID: owner, draft: try draft(), store: store, currentUserID: { self.owner })
        let result = await session.submit(using: repository)
        XCTAssertNil(result)
        let command = try XCTUnwrap(session.command)
        XCTAssertEqual(command.schemaVersion, 1)
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        let file = directory.appendingPathComponent(try XCTUnwrap(files.first))
        let original = try Data(contentsOf: file)
        for version in [2, nil] as [Int?] {
            var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            var checkpoint = try XCTUnwrap(envelope["value"] as? [String: Any])
            var wireCommand = try XCTUnwrap(checkpoint["command"] as? [String: Any])
            XCTAssertEqual(wireCommand["schemaVersion"] as? Int, 1)
            wireCommand["schemaVersion"] = version
            let encodedCommand = try JSONSerialization.data(withJSONObject: wireCommand, options: [.sortedKeys])
            if version != nil {
                let unsupported = try JSONDecoder().decode(DiaryTransferCommand.self, from: encodedCommand)
                XCTAssertThrowsError(try unsupported.validate())
            } else {
                XCTAssertThrowsError(try JSONDecoder().decode(DiaryTransferCommand.self, from: encodedCommand))
            }
            checkpoint["command"] = wireCommand; envelope["value"] = checkpoint
            let untouched = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            try untouched.write(to: file)
            let reopened = DiaryTransferSession(userID: owner, store: store, currentUserID: { self.owner })
            XCTAssertTrue(reopened.isUnreadable)
            XCTAssertFalse(reopened.discardProposal())
            let rejected = await reopened.submit(using: repository)
            XCTAssertNil(rejected)
            XCTAssertEqual(try Data(contentsOf: file), untouched)
        }
        XCTAssertTrue(repository.appliedDiaryTransferIDs.isEmpty)
    }
}
