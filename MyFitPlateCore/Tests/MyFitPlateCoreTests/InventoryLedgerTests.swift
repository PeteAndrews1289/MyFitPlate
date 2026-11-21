import XCTest
@testable import MyFitPlateCore

@MainActor
final class InventoryLedgerTests: XCTestCase {
    private let user = "inventory-owner"
    private func lot(_ name: String = "Rice", amount: Double = 1_000, unit: String = "g") -> PantryItem {
        var item = PantryItem(name: name, quantity: amount, unit: unit, category: "Pantry")
        item.dateAdded = Date(timeIntervalSince1970: 1_790_000_000)
        item.quantityVerified = true; item.preparation = "Raw"; return item
    }
    private func batch() throws -> PlannedMeal {
        let meal = PlannedMeal(id: "rice-plan", mealType: "Dinner", foodItem: FoodItem(id: "rice-food", name: "Rice bowl",
            calories: 400, protein: 25, carbs: 50, fats: 10, servingSize: "one bowl", servingWeight: 300), ingredients: ["100 g Rice"])
        return try MealPlanCookingRules.configuring(meal, date: Date(), cookingPortions: 4)
    }
    private func repository(items: [PantryItem] = []) -> MockNutritionRepository {
        let auth = MockAuthService(); auth.currentUserID = user
        DIContainer.shared.authService = auth
        let repo = MockNutritionRepository(); repo.inventoryAccountID = user
        repo.mockPantryItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        DIContainer.shared.nutritionRepository = repo; return repo
    }
    func testCompatibleConversionsNeverCrossMassVolumeOrPackage() {
        XCTAssertEqual(InventoryQuantityRules.convert(1, from: "kg", to: "g"), 1_000)
        XCTAssertEqual(InventoryQuantityRules.convert(1, from: "lb", to: "g")!, 453.59237, accuracy: 0.000001)
        XCTAssertEqual(InventoryQuantityRules.convert(1, from: "cup", to: "ml")!, 236.5882365, accuracy: 0.000001)
        XCTAssertNil(InventoryQuantityRules.convert(1, from: "cup", to: "g"))
        XCTAssertNil(InventoryQuantityRules.convert(1, from: "package", to: "g"))
        XCTAssertNil(InventoryQuantityRules.convert(.nan, from: "g", to: "g"))
    }
    func testLegacyUnknownExpiredAndCookedStockDoNotSatisfyRawShopping() {
        var legacy = lot(amount: 500); legacy.quantityVerified = nil
        var unknown = lot(amount: 500); unknown.quantityUnknown = true
        var expired = lot(amount: 500); expired.bestBefore = .distantPast
        var cooked = lot(amount: 500); cooked.preparation = "Cooked"
        let needs = [GroceryListItem(name: "Rice", quantity: 200, unit: "g", source: "mealPlan")]
        for item in [legacy, unknown, expired, cooked] {
            let coverage = InventoryPlanningRules.coverage(items: needs, stock: [item])
            XCTAssertEqual(coverage[0].available, 0); XCTAssertEqual(coverage[0].needToBuy, 200)
            XCTAssertEqual(item.quantity, 500) // Coverage never changes legacy or actual records.
        }
    }
    func testCoverageReservesCompatibleStockOnlyOnceAndKeepsManualNeeds() {
        let rice = lot(amount: 500)
        let first = GroceryListItem(name: "Rice", quantity: 0.4, unit: "kg", source: "mealPlan")
        let second = GroceryListItem(name: "Rice", quantity: 300, unit: "g", source: "mealPlan")
        let manual = GroceryListItem(name: "Rice", quantity: 200, unit: "g", source: "manual")
        let rows = InventoryPlanningRules.coverage(items: [first, second, manual], stock: [rice])
        XCTAssertEqual(rows[0].available, 0.4, accuracy: 0.000001)
        XCTAssertEqual(rows[1].available, 100, accuracy: 0.000001)
        XCTAssertEqual(rows[1].needToBuy, 200, accuracy: 0.000001)
        XCTAssertEqual(rows[2].needToBuy, 200)
    }
    func testCookConsumeDiaryAndUndoAreAtomicAndRawIngredientsDeductOnlyOnce() async throws {
        let rice = lot(); let repo = repository(items: [rice]); let planned = try batch()
        let cook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: [rice], selectedLots: [0: rice.id], userID: user, bestBefore: nil)
        try await repo.applyInventoryMutation(userID: user, mutation: cook)
        try await repo.applyInventoryMutation(userID: user, mutation: cook)
        var stock = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(stock.first { $0.id == rice.id }?.quantity, 600)
        let cooked = try XCTUnwrap(stock.first { $0.isCookedBatch })
        XCTAssertEqual(cooked.quantity, 4)
        let consume = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: user,
            plannedMeal: planned, date: Date(), mealName: "Dinner", alsoLog: true)
        try await repo.applyInventoryMutation(userID: user, mutation: consume)
        try await repo.applyInventoryMutation(userID: user, mutation: consume)
        stock = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(stock.first { $0.id == rice.id }?.quantity, 600)
        XCTAssertEqual(stock.first { $0.id == cooked.id }?.quantity, 3)
        let day = consume.diary!.day.dayKey
        XCTAssertEqual(repo.inventoryDiaryLogs["\(user)|\(day)"]?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(repo.inventoryDiaryLogs["\(user)|\(day)"]?.meals.flatMap(\.foodItems).first?.calories, 400)
        let undo = try InventoryPlanningRules.undoing(consume, current: stock)
        try await repo.applyInventoryMutation(userID: user, mutation: undo)
        XCTAssertTrue(repo.inventoryDiaryLogs["\(user)|\(day)"]?.meals.isEmpty == true)
        let readback1 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback1.first { $0.id == cooked.id }?.quantity, 4)
        // A deliberate re-consume after Undo is allowed; old consume receipt still cannot reapply.
        let current = try await repo.fetchInventory(userID: user)
        let again = try InventoryPlanningRules.reducing(item: current.first { $0.id == cooked.id }!, amount: 1, reason: .consume,
            userID: user, plannedMeal: planned, date: consume.diary!.day.originalDate, mealName: "Dinner", alsoLog: true)
        try await repo.applyInventoryMutation(userID: user, mutation: again)
        try await repo.applyInventoryMutation(userID: user, mutation: consume)
        let readback2 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback2.first { $0.id == cooked.id }?.quantity, 3)
    }
    func testFreshIDsCannotCookOrConsumeSamePlannedOccurrenceTwice() async throws {
        let repo = repository(); let planned = try batch()
        let cook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: [], selectedLots: [:], userID: user, bestBefore: nil)
        try await repo.applyInventoryMutation(userID: user, mutation: cook)
        var duplicate = cook; duplicate.id = UUID()
        do { try await repo.applyInventoryMutation(userID: user, mutation: duplicate); XCTFail("Duplicate cooking") } catch {}
        let cooked = try await repo.fetchInventory(userID: user).first!
        let consume = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: user, plannedMeal: planned)
        try await repo.applyInventoryMutation(userID: user, mutation: consume)
        let remaining = try await repo.fetchInventory(userID: user).first!
        XCTAssertThrowsError(try InventoryPlanningRules.reducing(item: remaining, amount: 1, reason: .consume, userID: user, plannedMeal: planned))
        var second = consume; second.id = UUID(); second.before = [remaining]
        var again = remaining; again.quantity -= 1; second.after = [again]
        do { try await repo.applyInventoryMutation(userID: user, mutation: second); XCTFail("Duplicate planned portion") } catch {}
        let readback3 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback3.first?.quantity, 3)
    }
    func testDiaryConflictCannotDeductStockAndChangedFoodBlocksUndo() async throws {
        let repo = repository(); let planned = try batch()
        let cook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: [], selectedLots: [:], userID: user, bestBefore: nil)
        try await repo.applyInventoryMutation(userID: user, mutation: cook)
        let cooked = try await repo.fetchInventory(userID: user).first!
        let consume = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: user, plannedMeal: planned, alsoLog: true)
        var existing = consume.diary!.desired!; existing.calories = 999
        repo.mockLogsByDay = [DailyLog(id: consume.diary!.day.dayKey, date: Date(), meals: [Meal(name: "Dinner", foodItems: [existing])])]
        do { try await repo.applyInventoryMutation(userID: user, mutation: consume); XCTFail("Existing log must not consume") } catch {}
        let readback4 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback4.first?.quantity, 4)
        XCTAssertTrue(repo.appliedInventoryIDs.count == 1)
    }
    func testUndoConsumptionPreservesLaterPurchasesAndRejectsNegativeBalance() async throws {
        let original = lot(amount: 500); let repo = repository(items: [original])
        let used = try InventoryPlanningRules.reducing(item: original, amount: 200, reason: .consume, userID: user)
        try await repo.applyInventoryMutation(userID: user, mutation: used)
        var restocked = try await repo.fetchInventory(userID: user).first!; restocked.quantity += 100
        let restock = InventoryMutation(userID: user, title: "Restock", reason: .purchase, before: used.after, after: [restocked])
        try await repo.applyInventoryMutation(userID: user, mutation: restock)
        let undo = try InventoryPlanningRules.undoing(used, current: try await repo.fetchInventory(userID: user))
        try await repo.applyInventoryMutation(userID: user, mutation: undo)
        let readback5 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback5.first?.quantity, 600)
        XCTAssertThrowsError(try InventoryPlanningRules.undoing(restock, current: [lot(amount: 0)]))
    }
    func testPurchaseTransferAndUndoRetainShoppingAndOtherRows() async throws {
        let repo = repository()
        let need = GroceryListItem(name: "Rice", quantity: 500, unit: "g", source: "mealPlan")
        let manual = GroceryListItem(name: "Coffee", quantity: 1, unit: "package", source: "manual")
        repo.mockFetchGroceryListResult = [need, manual]
        let buy = try InventoryPlanningRules.purchasing(item: need, totalBought: 1_000, transferAmount: 1_000, userID: user)
        try await repo.applyInventoryMutation(userID: user, mutation: buy)
        XCTAssertEqual(repo.mockFetchGroceryListResult.first?.transferredToPantryQuantity, 1_000)
        XCTAssertEqual(repo.mockFetchGroceryListResult.last, manual)
        XCTAssertThrowsError(try InventoryPlanningRules.purchasing(item: repo.mockFetchGroceryListResult[0], totalBought: 1_000, transferAmount: 1, userID: user))
        let undo = try InventoryPlanningRules.undoing(buy, current: try await repo.fetchInventory(userID: user), groceries: repo.mockFetchGroceryListResult)
        try await repo.applyInventoryMutation(userID: user, mutation: undo)
        XCTAssertEqual(repo.mockFetchGroceryListResult[0].transferredToPantryQuantity, 0)
        XCTAssertEqual(repo.mockFetchGroceryListResult[0].purchasedQuantity, 1_000)
        XCTAssertEqual(repo.mockFetchGroceryListResult.last, manual)
    }
    func testLostAcknowledgementRecoveryCancellationAndAccountIsolation() async throws {
        let repo = repository()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let item = lot()
        let operation = InventoryMutation(userID: user, title: "Purchase", reason: .purchase, before: [], after: [item])
        let session = InventorySaveSession(userID: user, store: store, enqueueHealth: { _ in true })
        XCTAssertTrue(session.prepare(operation))
        repo.inventoryFailureAfterCommit = URLError(.timedOut)
        await session.save(using: repo)
        XCTAssertFalse(session.checkpoint?.accepted == true)
        let reopened = InventorySaveSession(userID: user, store: store, enqueueHealth: { _ in true })
        await reopened.resolve(using: repo, cancelPending: true)
        XCTAssertTrue(reopened.checkpoint?.accepted == true)
        XCTAssertEqual(repo.appliedInventoryIDs, [operation.id])
        XCTAssertTrue(reopened.finish())
        var cancelled = operation; cancelled.id = UUID(); cancelled.after[0].id = UUID()
        let next = InventorySaveSession(userID: user, store: store, enqueueHealth: { _ in true }); XCTAssertTrue(next.prepare(cancelled))
        await next.resolve(using: repo, cancelPending: true)
        do { try await repo.applyInventoryMutation(userID: user, mutation: cancelled); XCTFail("Cancelled operation") } catch {}
        repo.inventoryAccountID = nil
        let readback6 = try await repo.fetchInventory(userID: "other-account")
        XCTAssertTrue(readback6.isEmpty)
        let auth = DIContainer.shared.authService as! MockAuthService; auth.currentUserID = "other-account"
        await reopened.resolve(using: repo, cancelPending: true)
        XCTAssertTrue(InventorySaveSession(userID: "other-account", store: store, enqueueHealth: { _ in true }).checkpoint == nil)
    }
    func testReceiptPayloadReuseAndStaleStockAreRejected() async throws {
        let item = lot(); let repo = repository(items: [item])
        let use = try InventoryPlanningRules.reducing(item: item, amount: 100, reason: .waste, userID: user)
        try await repo.applyInventoryMutation(userID: user, mutation: use)
        var altered = use; altered.after[0].quantity = 1
        do { try await repo.applyInventoryMutation(userID: user, mutation: altered); XCTFail("Reused identity") } catch {}
        var stale = use; stale.id = UUID()
        do { try await repo.applyInventoryMutation(userID: user, mutation: stale); XCTFail("Stale balance") } catch {}
        let readback7 = try await repo.fetchInventory(userID: user)
        XCTAssertEqual(readback7.first?.quantity, 900)
    }
    func testNamedTimersPersistIndependentlyAndDoNotPauseEachOther() throws {
        _ = repository()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let session = MealCookingCheckpointSession(userID: user, contextID: "multiple-cooking-timers", store: store)
        XCTAssertTrue(session.startTimer(minutes: 10, now: now))
        XCTAssertTrue(session.addNamedTimer(name: "Rice", minutes: 5, now: now))
        XCTAssertTrue(session.addNamedTimer(name: "Oven", minutes: 20, now: now))
        let rice = session.checkpoint.additionalTimers![0]
        let oven = session.checkpoint.additionalTimers![1]
        XCTAssertTrue(session.changeNamedTimer(id: rice.id, now: now.addingTimeInterval(30)))
        let reopened = MealCookingCheckpointSession(userID: user, contextID: "multiple-cooking-timers", store: store)
        XCTAssertEqual(reopened.checkpoint.additionalTimers?.count, 2)
        XCTAssertEqual(reopened.checkpoint.additionalTimers?[0].remaining(now: now.addingTimeInterval(600)), 270)
        XCTAssertEqual(reopened.checkpoint.additionalTimers?[1].remaining(now: now.addingTimeInterval(600)), 600)
        XCTAssertEqual(reopened.remaining(now: now.addingTimeInterval(30)), 570)
        XCTAssertTrue(reopened.changeNamedTimer(id: rice.id, now: now.addingTimeInterval(600)))
        XCTAssertTrue(reopened.finishExpiredNamedTimers(now: now.addingTimeInterval(900)))
        XCTAssertTrue(reopened.checkpoint.additionalTimers?[0].finished == true)
        XCTAssertFalse(reopened.checkpoint.additionalTimers?[1].finished == true)
        XCTAssertTrue(reopened.changeNamedTimer(id: oven.id, remove: true))
        XCTAssertEqual(reopened.checkpoint.additionalTimers?.count, 1)
    }

    func testMetadataAndTimestampRoundTripUndoPreservesPreciseNutrition() throws {
        _ = repository()
        let planned = try batch()
        var cooked = lot(amount: 4, unit: "portion")
        cooked.cookedBatch = planned.cookingBatch; cooked.portionFood = planned.foodItem
        cooked.preparation = "Cooked"
        let operation = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: user, plannedMeal: planned, alsoLog: true)
        let patch = operation.diary!
        var storedFood = patch.desired!
        storedFood.timestamp = storedFood.timestamp.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970 + 0.0000001) }
        let stored = DailyLog(id: patch.day.dayKey, date: patch.day.startOfDay, meals: [Meal(name: patch.mealName, foodItems: [storedFood])])
        let inverse = try InventoryPlanningRules.undoing(operation, current: operation.after)
        XCTAssertTrue(try inverse.diary!.applying(to: stored).meals.isEmpty)
        var changed = stored
        changed.meals[0].foodItems[0].calories += 0.0001
        XCTAssertThrowsError(try inverse.diary!.applying(to: changed))
        var moved = stored; moved.meals[0].name = "Breakfast"
        XCTAssertThrowsError(try inverse.diary!.applying(to: moved))
    }

    func testCookedBatchNoLongerRequestsRawIngredientsAndUndoRestoresNeed() throws {
        let planned = try batch()
        let day = MealPlanDay(id: MealPlanEditingRules.dayID(Date()), date: Calendar.current.startOfDay(for: Date()), meals: [planned])
        let before = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric)
        XCTAssertEqual(before.first?.quantity, 400)
        let cooked = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric, cookedBatchIDs: [planned.cookingBatch!.id])
        XCTAssertTrue(cooked.isEmpty)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric, cookedBatchIDs: []).first?.quantity, 400)
    }

    func testUndoEarlierPlannedConsumptionPreservesLaterPortionEvidence() async throws {
        let repo = repository(); let first = try batch()
        let cook = try InventoryPlanningRules.cooked(batch: first.cookingBatch!, originalMeal: first, stock: [], selectedLots: [:], userID: user, bestBefore: nil)
        try await repo.applyInventoryMutation(userID: user, mutation: cook)
        let cooked = try await repo.fetchInventory(userID: user).first!
        let consumeFirst = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: user, plannedMeal: first)
        try await repo.applyInventoryMutation(userID: user, mutation: consumeFirst)
        var second = first; second.id = "second-planned-portion"
        let remaining = try await repo.fetchInventory(userID: user).first!
        let consumeSecond = try InventoryPlanningRules.reducing(item: remaining, amount: 1, reason: .consume, userID: user, plannedMeal: second)
        try await repo.applyInventoryMutation(userID: user, mutation: consumeSecond)
        let inverse = try InventoryPlanningRules.undoing(consumeFirst, current: try await repo.fetchInventory(userID: user))
        try await repo.applyInventoryMutation(userID: user, mutation: inverse)
        let restored = try await repo.fetchInventory(userID: user).first!
        XCTAssertEqual(restored.quantity, 3)
        XCTAssertEqual(restored.recordedPlannedPortions, consumeSecond.after[0].recordedPlannedPortions?.filter { $0 != consumeFirst.uniqueSourceKey })
    }

    func testBoughtAmountWithoutPantryTransferDoesNotInventStockAndUndoRestoresShopping() async throws {
        let repo = repository()
        let row = GroceryListItem(name: "Rice", quantity: 500, unit: "g", source: "mealPlan")
        repo.mockFetchGroceryListResult = [row]
        let bought = try InventoryPlanningRules.purchasing(item: row, totalBought: 500, transferAmount: 0, userID: user)
        XCTAssertTrue(bought.after.isEmpty)
        try await repo.applyInventoryMutation(userID: user, mutation: bought)
        let stock = try await repo.fetchInventory(userID: user)
        XCTAssertTrue(stock.isEmpty)
        XCTAssertEqual(repo.mockFetchGroceryListResult[0].purchasedQuantity, 500)
        let undo = try InventoryPlanningRules.undoing(bought, current: stock, groceries: repo.mockFetchGroceryListResult)
        try await repo.applyInventoryMutation(userID: user, mutation: undo)
        XCTAssertEqual(repo.mockFetchGroceryListResult[0].purchasedQuantity, 0)
        XCTAssertFalse(repo.mockFetchGroceryListResult[0].isCompleted)
    }

    func testPartiallyBoughtWithoutStockTransferReducesShoppingNeedWithoutInventingInventory() {
        var row = GroceryListItem(name: "Rice", quantity: 500, unit: "g", source: "mealPlan")
        row.purchasedQuantity = 200; row.transferredToPantryQuantity = 0
        let partial = InventoryPlanningRules.coverage(items: [row], stock: [])[0]
        XCTAssertEqual(partial.available, 0)
        XCTAssertEqual(partial.needToBuy, 300)
        row.isCompleted = true
        XCTAssertEqual(InventoryPlanningRules.coverage(items: [row], stock: [])[0].needToBuy, 0)
    }

}
