import XCTest
@testable import MyFitPlateCore

@MainActor
final class InventoryCheckpointCASTests: XCTestCase {
    private var oldAuth: AuthServiceProtocol!
    private var auth: MockAuthService!
    private var store: EditorDraftStore!
    private var directory: URL!
    override func setUp() {
        oldAuth = DIContainer.shared.authService; auth = MockAuthService(); auth.currentUserID = "stock-owner"
        DIContainer.shared.authService = auth
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
    }
    override func tearDown() { DIContainer.shared.authService = oldAuth; try? FileManager.default.removeItem(at: directory) }
    private func purchase() -> InventoryMutation {
        InventoryMutation(userID: "stock-owner", title: "Purchase", reason: .purchase, before: [], after: [PantryItem(name: "Rice", quantity: 1, unit: "package")])
    }
    func testStaleUnsubmittedEditorCannotEraseAcceptedReceiptWithUncheckpointedHealthIntent() async throws {
        let repository = MockNutritionRepository()
        var attemptedHealth = 0
        let fresh = InventorySaveSession(userID: "stock-owner", store: store, enqueueHealth: { _ in attemptedHealth += 1; return false })
        XCTAssertTrue(fresh.prepare(purchase()))
        let stale = InventorySaveSession(userID: "stock-owner", store: store, enqueueHealth: { _ in XCTFail("Stale unsent editor cannot complete Health cleanup"); return true })
        await fresh.save(using: repository)
        XCTAssertEqual(fresh.checkpoint?.accepted, true); XCTAssertEqual(attemptedHealth, 1)
        XCTAssertFalse(stale.finish())
        XCTAssertEqual(try store.load(InventoryCheckpoint.self, userID: "stock-owner", scope: InventorySaveSession.scope)?.value.accepted, true)
        await stale.save(using: repository)
        XCTAssertEqual(try store.load(InventoryCheckpoint.self, userID: "stock-owner", scope: InventorySaveSession.scope)?.value.accepted, true)
        XCTAssertEqual(repository.appliedInventoryIDs.count, 1)
        let resumed = InventorySaveSession(userID: "stock-owner", store: store, enqueueHealth: { _ in attemptedHealth += 1; return true })
        XCTAssertTrue(resumed.finish()); XCTAssertEqual(attemptedHealth, 2)
    }
    func testStaleSameIDCheckpointCannotDowngradeCancelledStateOrDeleteIt() async throws {
        let repository = MockNutritionRepository(), fresh = InventorySaveSession(userID: "stock-owner", store: store, enqueueHealth: { _ in true })
        XCTAssertTrue(fresh.prepare(purchase()))
        let stale = InventorySaveSession(userID: "stock-owner", store: store, enqueueHealth: { _ in true })
        await fresh.resolve(using: repository, cancelPending: true)
        XCTAssertEqual(fresh.checkpoint?.cancelled, true)
        await stale.save(using: repository)
        XCTAssertFalse(stale.finish())
        let retained = try store.load(InventoryCheckpoint.self, userID: "stock-owner", scope: InventorySaveSession.scope)?.value
        XCTAssertEqual(retained?.cancelled, true); XCTAssertFalse(retained?.submitted ?? true)
        XCTAssertTrue(repository.appliedInventoryIDs.isEmpty)
    }
    func testReviewedGroceryProductEvidenceTransfersToStockWithoutInventingMass() throws {
        let food = FoodItem(id: "product", name: "Rice", calories: 350, servingSize: "100 g", servingWeight: 100)
        var product = GroceryProductSnapshot(food: food, barcode: "123456789012"); product.packageQuantity = 500; product.packageUnit = "g"
        var row = GroceryListItem(name: "Rice", quantity: 2, unit: "package"); row.productSnapshot = product
        let operation = try InventoryPlanningRules.purchasing(item: row, totalBought: 2, transferAmount: 1, userID: "stock-owner")
        XCTAssertEqual(operation.after.first?.productSnapshot, product)
        XCTAssertEqual(operation.after.first?.quantity, 1); XCTAssertEqual(operation.after.first?.unit, "package")
        XCTAssertNil(operation.after.first?.portionFood)
    }
}
