import XCTest
@testable import MyFitPlateCore

final class InventoryIntakeLifecycleTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func consumption() throws -> (PantryItem, InventoryMutation, InventoryIntakeLink, FoodItem) {
        var stock = PantryItem(name: "Identified chicken", quantity: 1_000, unit: "g", dateAdded: date)
        stock.quantityVerified = true; stock.preparation = "Cooked"
        stock.portionFood = FoodItem(name: "Identified chicken", calories: 2, protein: 0.25, servingSize: "1 g", servingWeight: 1, quantityValue: 1, servingUnit: "g")
        let event = try InventoryPlanningRules.reducing(item: stock, amount: 200, reason: .consume, userID: "owner", date: date, alsoLog: true)
        return (stock, event, try InventoryIntakeLink(source: InventoryReceipt(event, status: .accepted)), try XCTUnwrap(event.diary?.desired))
    }
    private func day() throws -> DiaryDayContext { try XCTUnwrap(DiaryDayContext(userID: "owner", date: date)) }
    func testEditDeleteAndUndoApplyOnlyOriginalDeltaWhilePreservingLaterPurchases() throws {
        let (_, event, link, food) = try consumption()
        var later = try XCTUnwrap(event.after.first); later.quantity += 400; later.location = "New shelf"; later.name = "Owner label"; later.revisionID = "purchase"
        let edited = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        let edit = try InventoryIntakeRules.projecting(link: link, before: food, after: edited, current: [later], day: day(), mealName: "Lunch", operationID: "edit")
        XCTAssertEqual(edit.after.first?.quantity, 1_100); XCTAssertEqual(edit.after.first?.location, "New shelf"); XCTAssertEqual(edit.after.first?.name, "Owner label")
        XCTAssertEqual(edit.link.currentScale, 1.5)
        let deletion = try InventoryIntakeRules.projecting(link: edit.link, before: edited, after: nil, current: edit.after, day: day(), mealName: "Lunch", operationID: "delete")
        XCTAssertEqual(deletion.after.first?.quantity, 1_400)
        let undo = try InventoryIntakeRules.projecting(link: deletion.link, before: nil, after: edited, current: deletion.after, day: day(), mealName: "Lunch", operationID: "undo")
        XCTAssertEqual(undo.after.first?.quantity, 1_100); XCTAssertEqual(undo.link.source.fingerprint, link.source.fingerprint)
        XCTAssertEqual(try link.source.mutation().after.first?.quantity, 800, "Immutable original receipt is never rewritten")
    }
    func testStaleIntakeOrUnavailableAdditionalStockCannotMutateAnything() throws {
        let (_, event, link, food) = try consumption()
        let edited = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        let first = try InventoryIntakeRules.projecting(link: link, before: food, after: edited, current: event.after, day: day(), mealName: "Lunch", operationID: "edit")
        XCTAssertThrowsError(try InventoryIntakeRules.projecting(link: first.link, before: food, after: nil, current: first.after, day: day(), mealName: "Lunch", operationID: "stale"))
        let tooMuch = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 10))
        XCTAssertThrowsError(try InventoryIntakeRules.projecting(link: link, before: food, after: tooMuch, current: event.after, day: day(), mealName: "Lunch", operationID: "unavailable"))
        XCTAssertEqual(event.after.first?.quantity, 800)
    }
    func testUnsupportedQuantityAndChangedUnitRequireReviewWithoutNameGuessing() throws {
        let (_, event, link, food) = try consumption()
        var incompatible = food; incompatible.quantityValue = nil; incompatible.servingUnit = "unknown bucket"; incompatible.servingSize = "unknown bucket"; incompatible.servingWeight = 0
        XCTAssertThrowsError(try InventoryIntakeRules.projecting(link: link, before: food, after: incompatible, current: event.after, day: day(), mealName: "Lunch", operationID: "unknown"))
        var changedLot = event.after[0]; changedLot.unit = "ml"
        XCTAssertThrowsError(try InventoryIntakeRules.projecting(link: link, before: food, after: nil, current: [changedLot], day: day(), mealName: "Lunch", operationID: "unit"))
        var other = food; other.id = "same-name-unlinked"
        XCTAssertThrowsError(try InventoryIntakeRules.scale(food: other, link: link))
    }
    func testCookedPortionCorrectionNeverRepeatsRawIngredientConsumption() throws {
        let batch = MealCookingBatch(id: "batch", sourceMealID: "meal", cookingDate: date, name: "Dinner", totalPortions: 4, ingredientsPerPortion: [], instructions: nil, allocations: [])
        var cooked = PantryItem(name: "Dinner batch", quantity: 4, unit: "portion", dateAdded: date)
        cooked.quantityVerified = true; cooked.cookedBatch = batch
        cooked.portionFood = FoodItem(name: "Dinner", calories: 400, servingSize: "1 serving", servingWeight: 300)
        let event = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: "owner", date: date, alsoLog: true)
        let link = try InventoryIntakeLink(source: InventoryReceipt(event, status: .accepted)); let food = try XCTUnwrap(event.diary?.desired)
        let raw = PantryItem(name: "Raw ingredient already cooked", quantity: 600, unit: "g", dateAdded: date)
        let desired = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 2))
        let edit = try InventoryIntakeRules.projecting(link: link, before: food, after: desired, current: event.after + [raw], day: day(), mealName: "Dinner", operationID: "portion-edit")
        XCTAssertEqual(edit.after.count, 1); XCTAssertEqual(edit.after.first?.id, cooked.id); XCTAssertEqual(edit.after.first?.quantity, 2)
        XCTAssertEqual(raw.quantity, 600); XCTAssertFalse(edit.event.itemIDs.contains(raw.id))
        let deleted = try InventoryIntakeRules.projecting(link: edit.link, before: desired, after: nil, current: edit.after, day: day(), mealName: "Dinner", operationID: "portion-delete")
        XCTAssertEqual(deleted.after.first?.quantity, 4)
    }
    func testFrozenCheckedIntentIsStableAcrossReadHintRefreshButRejectsChangedPayload() throws {
        let (_, _, _, food) = try consumption(); let updated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        let before = DailyLog(id: try day().dayKey, date: date, meals: [Meal(name: "Lunch", foodItems: [food])])
        var log = before.rememberingMutationBase(); log.meals[0].foodItems[0] = updated
        log.pendingMutationID = "stable-edit"; log.pendingFoodEdit = FoodEditPrecondition(original: food, desired: updated)
        let command = try DailyLogMutation(userID: "owner", log: log)
        var refreshed = log; refreshed.mutationBase = try JSONEncoder().encode(log)
        XCTAssertEqual(try InventoryIntakeRules.intentFingerprint(command), try InventoryIntakeRules.intentFingerprint(DailyLogMutation(userID: "owner", log: refreshed)))
        var changed = updated; changed.calories += 1
        refreshed.pendingFoodEdit = FoodEditPrecondition(original: food, desired: changed)
        XCTAssertNotEqual(try InventoryIntakeRules.intentFingerprint(command), try InventoryIntakeRules.intentFingerprint(DailyLogMutation(userID: "owner", log: refreshed)))
        XCTAssertEqual(InventoryIntakeRules.eventID(userID: "owner", operationID: "stable-edit", foodID: food.id), InventoryIntakeRules.eventID(userID: "owner", operationID: "stable-edit", foodID: food.id))
    }
    func testLinkRoundTripsAndRejectsWrongEventReason() throws {
        let (_, event, link, _) = try consumption()
        let reloaded = try JSONDecoder().decode(InventoryIntakeLink.self, from: JSONEncoder().encode(link))
        try reloaded.validate(); XCTAssertEqual(reloaded.foodID, link.foodID); XCTAssertEqual(reloaded.stockIDs, link.stockIDs)
        var wrong = event; wrong.reason = .cook
        XCTAssertThrowsError(try InventoryIntakeLink(source: InventoryReceipt(wrong, status: .accepted)))
    }
    func testMockLostAckThenLaterEditKeepsCanonicalStockAndRejectsChangedReplay() async throws {
        let (stock, event, _, food) = try consumption()
        let repo = MockNutritionRepository(); repo.inventoryAccountID = "owner"; repo.persistsDailyLogUpdates = true
        repo.mockPantryItemsByID = [stock.id: stock]
        try await repo.applyInventoryMutation(userID: "owner", mutation: event)
        let context = try day()
        let original = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey])
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        var proposal = original.rememberingMutationBase()
        _ = DailyLogRules.updateFoodInLog(log: &proposal, updatedFoodItem: updated)
        proposal.pendingMutationID = "lost-ack"; proposal.pendingFoodEdit = FoodEditPrecondition(original: food, desired: updated)
        repo.inventoryFailureAfterCommit = URLError(.timedOut)
        do { try await repo.saveDailyLog(userID: "owner", log: proposal); XCTFail("Expected lost acknowledgement") } catch {}
        let stockAfterLostAck = try await repo.fetchInventory(userID: "owner")
        XCTAssertEqual(stockAfterLostAck.first?.quantity, 700)
        let acceptedEventCount = repo.inventoryReceipts.count
        let newest = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 0.5))
        var later = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey]).rememberingMutationBase()
        _ = DailyLogRules.updateFoodInLog(log: &later, updatedFoodItem: newest)
        later.pendingMutationID = "later-edit"; later.pendingFoodEdit = FoodEditPrecondition(original: updated, desired: newest)
        try await repo.saveDailyLog(userID: "owner", log: later)
        try await repo.saveDailyLog(userID: "owner", log: proposal)
        let current = try await repo.fetchInventory(userID: "owner")
        XCTAssertEqual(current.first?.quantity, 900)
        XCTAssertEqual(repo.inventoryDiaryLogs["owner|" + context.dayKey]?.meals.flatMap(\.foodItems).first?.calories, newest.calories)
        XCTAssertEqual(repo.inventoryReceipts.count, acceptedEventCount + 1, "Read-only acceptance replay does not append another physical event")
        var altered = proposal; altered.pendingFoodEdit = FoodEditPrecondition(original: food, desired: newest)
        do { try await repo.saveDailyLog(userID: "owner", log: altered); XCTFail("Changed frozen intent must be rejected") } catch {}
    }
    func testMockDeleteAndDiaryUndoRestoreOnlyLinkedIntakeAndFenceOldStockUndo() async throws {
        let (stock, event, _, food) = try consumption()
        let repo = MockNutritionRepository(); repo.inventoryAccountID = "owner"; repo.persistsDailyLogUpdates = true
        repo.mockPantryItemsByID = [stock.id: stock]
        try await repo.applyInventoryMutation(userID: "owner", mutation: event)
        let context = try day(); let original = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey])
        var deleted = original.rememberingMutationBase(); _ = DailyLogRules.deleteFoodFromLog(log: &deleted, foodItemID: food.id)
        deleted.pendingMutationID = "delete-intake"
        try await repo.saveDailyLog(userID: "owner", log: deleted)
        let restoredStock = try await repo.fetchInventory(userID: "owner")
        XCTAssertEqual(restoredStock.first?.quantity, 1_000)
        let staleStockUndo = try InventoryPlanningRules.undoing(event, current: restoredStock)
        do { try await repo.applyInventoryMutation(userID: "owner", mutation: staleStockUndo); XCTFail("Already reversed intake must not credit stock again") } catch {}
        let stillRestored = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(stillRestored.first?.quantity, 1_000)
        var undo = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey]).rememberingMutationBase(); undo.meals = original.meals
        undo.pendingMutationID = "undo-delete"; undo.pendingFoodEdits = [FoodEditPrecondition(foodID: food.id, expected: nil, desired: food)]
        try await repo.saveDailyLog(userID: "owner", log: undo)
        let consumedAgain = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(consumedAgain.first?.quantity, 800)
        try await repo.saveDailyLog(userID: "owner", log: undo)
        let repeated = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(repeated.first?.quantity, 800)
    }
    func testMockLegacyReceiptBackfillIsExactAndSameNameDiaryCopyDoesNotConsumeStock() async throws {
        let (stock, event, _, food) = try consumption()
        let repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true; repo.mockPantryItemsByID = [stock.id: stock]
        try await repo.applyInventoryMutation(userID: "owner", mutation: event)
        repo.inventoryIntakeLinks = [:]
        let legacyLink = try await repo.fetchInventoryIntakeLink(userID: "owner", foodID: food.id)
        XCTAssertEqual(legacyLink?.source.id, event.id)
        let context = try day(); let original = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey])
        var copy = food; copy.id = "unrelated-copy"
        var proposal = original.rememberingMutationBase(); proposal.meals[0].foodItems.append(copy); proposal.pendingMutationID = "copy-food"
        try await repo.saveDailyLog(userID: "owner", log: proposal)
        let unchanged = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(unchanged.first?.quantity, 800)
        let unlinkedCopy = try await repo.fetchInventoryIntakeLink(userID: "owner", foodID: copy.id)
        XCTAssertNil(unlinkedCopy)
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 2))
        var edit = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey]).rememberingMutationBase()
        _ = DailyLogRules.updateFoodInLog(log: &edit, updatedFoodItem: updated); edit.pendingMutationID = "legacy-edit"
        edit.pendingFoodEdit = FoodEditPrecondition(original: food, desired: updated)
        try await repo.saveDailyLog(userID: "owner", log: edit)
        let consumed = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(consumed.first?.quantity, 600)
        XCTAssertEqual(repo.inventoryDiaryLogs["owner|" + context.dayKey]?.meals.flatMap(\.foodItems).count, 2)
    }
    func testMockIncompatibleAndOverdrawnEditKeepBothDiaryAndStockUntouched() async throws {
        let (stock, event, _, food) = try consumption()
        let repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true; repo.mockPantryItemsByID = [stock.id: stock]
        try await repo.applyInventoryMutation(userID: "owner", mutation: event)
        let context = try day(); let original = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey])
        let tooMuch = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 10))
        var edit = original.rememberingMutationBase(); _ = DailyLogRules.updateFoodInLog(log: &edit, updatedFoodItem: tooMuch)
        edit.pendingMutationID = "overdraw"; edit.pendingFoodEdit = FoodEditPrecondition(original: food, desired: tooMuch)
        do { try await repo.saveDailyLog(userID: "owner", log: edit); XCTFail("Negative stock must never be accepted") } catch {}
        let stockAfter = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(stockAfter.first?.quantity, 800)
        XCTAssertEqual(repo.inventoryDiaryLogs["owner|" + context.dayKey]?.meals.flatMap(\.foodItems).first?.calories, food.calories)
    }

    func testUnchangedLegacyDuplicateGroupsPermitWaterAndUnrelatedUniqueEdit() throws {
        let first = FoodItem(id: "duplicate", name: "First", calories: 100)
        let second = FoodItem(id: "duplicate", name: "Second", calories: 200)
        let unique = FoodItem(id: "unique", name: "Independent", calories: 50)
        let before = DailyLog(id: try day().dayKey, date: date, meals: [Meal(name: "Lunch", foodItems: [first, second, unique])])
        var water = before.rememberingMutationBase(); water.waterTracker = WaterTracker(totalOunces: 12, goalOunces: 64, date: date)
        XCTAssertTrue(try InventoryIntakeRules.changes(before: before, after: water).isEmpty)
        let mergedWater = try DailyLogMutation(userID: "owner", log: water).applying(to: before, checkingFoodEdits: true)
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(mergedWater.meals[0].foodItems[0], first))
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(mergedWater.meals[0].foodItems[1], second))
        var edited = before.rememberingMutationBase(); edited.meals[0].foodItems[2].calories = 75
        XCTAssertEqual(try InventoryIntakeRules.changes(before: before, after: edited).map(\.id), ["unique"])
        let merged = try DailyLogMutation(userID: "owner", log: edited).applying(to: before, checkingFoodEdits: true)
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(merged.meals[0].foodItems[0], first))
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(merged.meals[0].foodItems[1], second))
        XCTAssertEqual(merged.meals[0].foodItems[2].calories, 75)
    }
    func testAmbiguousChangedDuplicateGroupStillRequiresReview() throws {
        let first = FoodItem(id: "duplicate", name: "First", calories: 100)
        let second = FoodItem(id: "duplicate", name: "Second", calories: 200)
        let before = DailyLog(id: try day().dayKey, date: date, meals: [Meal(name: "Lunch", foodItems: [first, second])])
        var changed = before; changed.meals[0].foodItems[1].calories = 201
        XCTAssertThrowsError(try InventoryIntakeRules.changes(before: before, after: changed))
        var reordered = before; reordered.meals[0].foodItems.swapAt(0, 1)
        XCTAssertThrowsError(try InventoryIntakeRules.changes(before: before, after: reordered))
    }
    @MainActor
    func testServiceAcceptedReplayRefreshesCanonicalInsteadOfPublishingStaleLocalProposal() async throws {
        let (stock, event, _, food) = try consumption()
        let repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true; repo.mockPantryItemsByID = [stock.id: stock]
        try await repo.applyInventoryMutation(userID: "owner", mutation: event)
        let context = try day(); let original = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey])
        let updated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        var old = original.rememberingMutationBase(); _ = DailyLogRules.updateFoodInLog(log: &old, updatedFoodItem: updated)
        old.pendingMutationID = "old-accepted"; old.pendingFoodEdit = FoodEditPrecondition(original: food, desired: updated)
        try await repo.saveDailyLog(userID: "owner", log: old)
        let newest = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 0.5))
        var later = try XCTUnwrap(repo.inventoryDiaryLogs["owner|" + context.dayKey]).rememberingMutationBase()
        _ = DailyLogRules.updateFoodInLog(log: &later, updatedFoodItem: newest)
        later.pendingMutationID = "newest"; later.pendingFoodEdit = FoodEditPrecondition(original: updated, desired: newest)
        try await repo.saveDailyLog(userID: "owner", log: later)
        let oldRepo = DIContainer.shared.nutritionRepository, oldAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "owner"
        DIContainer.shared.nutritionRepository = repo; DIContainer.shared.authService = auth
        defer { DIContainer.shared.nutritionRepository = oldRepo; DIContainer.shared.authService = oldAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = DailyLogService(undoStore: EditorDraftStore(directory: directory))
        _ = await withCheckedContinuation { continuation in service.fetchLog(for: "owner", day: context) { continuation.resume(returning: $0) } }
        service.currentDailyLog = original.rememberingMutationBase()
        let accepted = await withCheckedContinuation { continuation in
            service.updateFood(for: "owner", date: date, original: food, updated: updated, operationID: "old-accepted", dayContext: context) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.currentDailyLog?.meals.flatMap(\.foodItems).first?.calories, newest.calories)
        XCTAssertFalse(service.canUndoDiaryChange, "A replay cannot install an Undo that would rewind later work")
        let current = try await repo.fetchInventory(userID: "owner"); XCTAssertEqual(current.first?.quantity, 900)
    }

}
