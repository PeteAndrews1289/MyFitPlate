import XCTest
import HealthKit
@testable import MyFitPlateCore

@MainActor
final class InventoryHealthSyncQueueTests: XCTestCase {
    private let owner = "inventory-health-owner"
    private var currentOwner: String?
    private var directory: URL!
    private var health: MockHealthKitManager!
    private var latest: DailyLog!
    override func setUp() {
        super.setUp(); currentOwner = owner
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        health = MockHealthKitManager()
    }
    override func tearDown() {
        for callback in health.inventorySaveCallbacks { callback(false) }
        health.inventorySaveCallbacks = []
        try? FileManager.default.removeItem(at: directory); super.tearDown()
    }
    private func mutation() throws -> InventoryMutation {
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: Date(timeIntervalSince1970: 1_700_000_000)))
        let food = FoodItem(id: "planned-stock-food", name: "Rice bowl", calories: 400, protein: 25, carbs: 50, fats: 10, timestamp: day.originalDate)
        let patch = InventoryDiaryPatch(day: day, mealName: "Dinner", desired: food)
        var lot = PantryItem(name: "Cooked rice", quantity: 4, unit: "portion"); lot.quantityVerified = true
        var after = lot; after.quantity = 3
        latest = DailyLog(id: day.dayKey, date: day.startOfDay, meals: [Meal(name: "Dinner", foodItems: [food])])
        return InventoryMutation(userID: owner, title: "Use rice", reason: .consume, before: [lot], after: [after], diary: patch)
    }
    private func queue() -> InventoryHealthSyncQueue {
        InventoryHealthSyncQueue(store: EditorDraftStore(directory: directory), healthKit: health,
            currentUserID: { self.currentOwner }, reader: { _, completion in completion(.success(self.latest)) })
    }
    private func settle(_ queue: InventoryHealthSyncQueue, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if !queue.isWorking { return }
            await Task.yield()
        }
        XCTFail("Queue didn't settle", file: file, line: line)
    }
    private func waitSave() async {
        for _ in 0..<500 { if !health.inventorySaveCallbacks.isEmpty { return }; await Task.yield() }
        XCTFail("Expected held save")
    }
    func testStableOperationReplayExportsOnceAndUndoDeletesOnlyItsExport() async throws {
        let operation = try mutation(), value = queue()
        XCTAssertTrue(value.enqueue(operation)); await settle(value)
        XCTAssertEqual(health.inventoryEvents, ["save:\(operation.id.uuidString):planned-stock-food"])
        XCTAssertTrue(value.enqueue(operation)); await settle(value)
        XCTAssertEqual(health.inventoryEvents.count, 1)
        let undo = try InventoryPlanningRules.undoing(operation, current: operation.after)
        latest.meals = []
        XCTAssertTrue(value.enqueue(undo)); await settle(value)
        XCTAssertEqual(health.inventoryEvents.last, "delete:\(operation.id.uuidString):planned-stock-food")
        XCTAssertEqual(value.pendingCount, 0)
        XCTAssertTrue(value.enqueue(operation)); await settle(value)
        XCTAssertEqual(health.inventoryEvents.count, 2, "Old accepted replay cannot resurrect an undone export")
    }
    func testUndoOrdersAfterHeldSaveIncludingPartiallyFailedCallback() async throws {
        let operation = try mutation(), value = queue()
        health.holdInventorySaves = true
        XCTAssertTrue(value.enqueue(operation)); await waitSave()
        let undo = try InventoryPlanningRules.undoing(operation, current: operation.after)
        latest.meals = []
        XCTAssertTrue(value.enqueue(undo))
        XCTAssertEqual(health.inventoryEvents.count, 1)
        health.inventorySaveCallbacks.removeFirst()(false)
        await settle(value)
        XCTAssertEqual(health.inventoryEvents.last, "delete:\(operation.id.uuidString):planned-stock-food")
        XCTAssertEqual(value.pendingCount, 0)
    }
    func testPermissionPendingSurvivesRestartAndExportsWhenAvailable() async throws {
        let operation = try mutation()
        health.inventoryNutritionAuthorized = false
        var value: InventoryHealthSyncQueue? = queue()
        XCTAssertTrue(value!.enqueue(operation)); await settle(value!)
        XCTAssertEqual(value!.pendingCount, 1); XCTAssertTrue(health.inventoryEvents.isEmpty)
        value = nil
        health.inventoryNutritionAuthorized = true
        let reopened = queue(); reopened.activateAccount(owner); await settle(reopened)
        XCTAssertEqual(reopened.pendingCount, 0)
        XCTAssertEqual(health.inventoryEvents.count, 1)
    }
    func testNormalDiaryEditWhileHealthSavePendingCleansOnlyOldOperation() async throws {
        let operation = try mutation(), value = queue()
        health.holdInventorySaves = true
        XCTAssertTrue(value.enqueue(operation)); await waitSave()
        latest.meals[0].foodItems[0].calories = 999
        health.inventorySaveCallbacks.removeFirst()(true)
        await settle(value)
        XCTAssertEqual(health.inventoryEvents, ["save:\(operation.id.uuidString):planned-stock-food", "delete:\(operation.id.uuidString):planned-stock-food"])
        XCTAssertEqual(latest.meals[0].foodItems[0].calories, 999)
    }
    func testMissingDiaryBeforeExportAndAccountSwitchCannotExportStaleFood() async throws {
        let operation = try mutation(), value = queue()
        latest.meals = []
        XCTAssertTrue(value.enqueue(operation)); await settle(value)
        XCTAssertTrue(health.inventoryEvents.isEmpty)
        currentOwner = "different-owner"
        XCTAssertFalse(value.enqueue(operation)); value.activateAccount(currentOwner)
        XCTAssertEqual(value.pendingCount, 0)
    }
    func testInventoryHealthSamplesHaveDistinctOperationIDsAndNoCopyReceiptMarker() async throws {
        let store = MockHealthStore()
        let actual = HealthKitManager(store: store)
        let operation = try mutation(), food = operation.diary!.desired!
        let success = await withCheckedContinuation { continuation in
            actual.saveInventoryNutrition(for: food, userID: owner, operationID: operation.id) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(success)
        let samples = store.savedObjects.compactMap { $0 as? HKQuantitySample }
        XCTAssertEqual(samples.count, 4)
        for sample in samples {
            XCTAssertEqual(sample.metadata?["inventoryOperationID"] as? String, operation.id.uuidString)
            XCTAssertNil(sample.metadata?["MyFitPlateTransferCopy"])
            XCTAssertTrue((sample.metadata?[HKMetadataKeySyncIdentifier] as? String)?.hasPrefix("MyFitPlate.inventory.") == true)
        }
        let otherID = UUID()
        XCTAssertNotEqual(HealthKitManager.inventoryNutritionSyncIdentifier(foodID: food.id, userID: owner, operationID: operation.id, nutrientIdentifier: "calories"),
            HealthKitManager.inventoryNutritionSyncIdentifier(foodID: food.id, userID: owner, operationID: otherID, nutrientIdentifier: "calories"))
        let deleted = await withCheckedContinuation { continuation in
            actual.deleteInventoryNutrition(for: food, userID: owner, operationID: operation.id) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.deletedPredicates.count, 4)
        for predicate in store.deletedPredicates {
            XCTAssertEqual((predicate as? NSCompoundPredicate)?.subpredicates.count, 2)
        }
    }
}
