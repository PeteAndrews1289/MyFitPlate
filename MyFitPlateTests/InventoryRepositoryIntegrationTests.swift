import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class InventoryEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class InventoryEmulatorFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("inventory-test-") ? InventoryEmulatorCheck() : nil
    }
}

/// Synthetic named apps with explicit localhost endpoints; never touches a production app.
@MainActor
final class InventoryRepositoryIntegrationTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
        let directory: URL
        let repository: FirestoreNutritionRepository
    }
    private var clients: [Client] = []
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(InventoryEmulatorFactory())
    }
    override func tearDown() {
        for client in clients {
            try? client.auth.signOut(); client.app.delete { _ in }
            try? FileManager.default.removeItem(at: client.directory)
        }
        clients = []; super.tearDown()
    }
    private func client() -> Client {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"; options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "inventory-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!, auth = Auth.auth(app: FirebaseApp.app(name: name)!)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app); db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let repository = FirestoreNutritionRepository(db: db, outboxURL: directory.appendingPathComponent("outbox.json"), currentUserID: { auth.currentUser?.uid })
        let value = Client(app: app, auth: auth, db: db, directory: directory, repository: repository)
        clients.append(value); return value
    }
    private func lot(amount: Double = 1_000) -> PantryItem {
        var item = PantryItem(name: "Rice", quantity: amount, unit: "g", category: "Pantry", dateAdded: Date(timeIntervalSince1970: 1_700_000_000.1234567))
        item.quantityVerified = true; item.preparation = "Raw"; return item
    }
    private func meal() throws -> PlannedMeal {
        let meal = PlannedMeal(id: "inventory-planned", mealType: "Dinner", foodItem: FoodItem(id: "bowl", name: "Rice bowl", calories: 400, protein: 25, carbs: 50, fats: 10, servingSize: "bowl", servingWeight: 300), ingredients: ["100 g Rice"])
        return try MealPlanCookingRules.configuring(meal, date: Date(), cookingPortions: 4)
    }
    func testCookingThenConsumeAndUndoAtomicallyPreserveRawDiaryAndPHUL() async throws {
        let client = client(); let uid = try await client.auth.signInAnonymously().user.uid
        let owner = client.db.collection("users").document(uid)
        let rice = lot(); let riceRef = owner.collection("pantryItems").document(rice.id.uuidString)
        var rawRice = try Firestore.Encoder().encode(rice); rawRice["futureStockField"] = "keep"
        try await riceRef.setData(rawRice)
        let actualRice = try await riceRef.getDocument(source: .server).data(as: PantryItem.self)
        let planned = try meal()
        let cook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: [actualRice], selectedLots: [0: actualRice.id], userID: uid, bestBefore: nil)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: cook)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: cook)
        let stock = try await client.repository.fetchInventory(userID: uid)
        let cooked = try XCTUnwrap(stock.first { $0.isCookedBatch })
        let use = try InventoryPlanningRules.reducing(item: cooked, amount: 1, reason: .consume, userID: uid, plannedMeal: planned, date: Date().addingTimeInterval(-1), mealName: "Dinner", alsoLog: true)
        let dayRef = owner.collection("dailyLogs").document(use.diary!.day.dayKey)
        let other = FoodItem(id: "untouched-food", name: "Unrelated food", calories: 123, protein: 1, carbs: 20, fats: 3)
        let day = DailyLog(id: use.diary!.day.dayKey, date: use.diary!.day.startOfDay, meals: [Meal(name: "Lunch", foodItems: [other])])
        var rawDay = try Firestore.Encoder().encode(day); rawDay["futureDay"] = "keep"
        var rawMeals = try XCTUnwrap(rawDay["meals"] as? [[String: Any]])
        var rawFoods = try XCTUnwrap(rawMeals[0]["foodItems"] as? [[String: Any]]); rawFoods[0]["futureFood"] = "keep"
        rawMeals[0]["foodItems"] = rawFoods; rawDay["meals"] = rawMeals
        try await dayRef.setData(rawDay)
        let phul = owner.collection("workoutPrograms").document("phul")
        try await phul.setData(["currentProgressIndex": 38, "skippedIndices": [2, 7]])
        try await client.repository.applyInventoryMutation(userID: uid, mutation: use)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: use)
        let used = try await client.repository.fetchInventory(userID: uid)
        XCTAssertEqual(used.first { $0.id == rice.id }?.quantity, 600)
        XCTAssertEqual(used.first { $0.id == cooked.id }?.quantity, 3)
        let savedLog = try await dayRef.getDocument(source: .server).data(as: DailyLog.self)
        XCTAssertEqual(savedLog.meals.flatMap(\.foodItems).count, 2)
        let undo = try InventoryPlanningRules.undoing(use, current: used)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: undo)
        let final = try await dayRef.getDocument(source: .server).data()!
        XCTAssertEqual(final["futureDay"] as? String, "keep")
        let finalMeals = try XCTUnwrap(final["meals"] as? [[String: Any]])
        let preservedFood = try XCTUnwrap(finalMeals[0]["foodItems"] as? [[String: Any]])
        XCTAssertEqual(preservedFood[0]["futureFood"] as? String, "keep")
        let finalRice = try await riceRef.getDocument(source: .server).data()!
        XCTAssertEqual(finalRice["quantity"] as? Double, 600)
        XCTAssertEqual(finalRice["futureStockField"] as? String, "keep")
        let finalProgram = try await phul.getDocument(source: .server).data()!
        XCTAssertEqual(finalProgram["currentProgressIndex"] as? Int, 38)
        XCTAssertEqual(finalProgram["skippedIndices"] as? [Int], [2, 7])
    }
    func testStaleIngredientCannotPartiallyCreateBatchAndNewIDCannotCookAgain() async throws {
        let client = client(); let uid = try await client.auth.signInAnonymously().user.uid
        let owner = client.db.collection("users").document(uid)
        let rice = lot(); let ref = owner.collection("pantryItems").document(rice.id.uuidString)
        try await ref.setData(Firestore.Encoder().encode(rice))
        let baseline = try await ref.getDocument(source: .server).data(as: PantryItem.self)
        let planned = try meal()
        let cook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: [baseline], selectedLots: [0: baseline.id], userID: uid, bestBefore: nil)
        try await ref.updateData(["quantity": 300])
        do { try await client.repository.applyInventoryMutation(userID: uid, mutation: cook); XCTFail("Stale raw stock") } catch {}
        let afterFailure = try await client.repository.fetchInventory(userID: uid)
        XCTAssertEqual(afterFailure.count, 1); XCTAssertEqual(afterFailure[0].quantity, 300)
        let untrackedCook = try InventoryPlanningRules.cooked(batch: planned.cookingBatch!, originalMeal: planned, stock: afterFailure, selectedLots: [:], userID: uid, bestBefore: nil)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: untrackedCook)
        var duplicate = untrackedCook; duplicate.id = UUID()
        do { try await client.repository.applyInventoryMutation(userID: uid, mutation: duplicate); XCTFail("Fresh ID duplicate batch") } catch {}
        let result = try await client.repository.fetchInventory(userID: uid)
        XCTAssertEqual(result.filter(\.isCookedBatch).count, 1)
    }
    func testPurchasePreservesConcurrentManualGroceryFieldsAndUndoTransfer() async throws {
        let client = client(); let uid = try await client.auth.signInAnonymously().user.uid
        let owner = client.db.collection("users").document(uid)
        let need = GroceryListItem(name: "Rice", quantity: 500, unit: "g", source: "mealPlan")
        let manual = GroceryListItem(name: "Coffee", quantity: 1, unit: "package", source: "manual")
        let ref = owner.collection("userSettings").document("groceryList")
        var other = try Firestore.Encoder().encode(manual); other["futureGrocery"] = "preserve"
        try await ref.setData(["items": [try Firestore.Encoder().encode(need), other], "futureList": "keep"])
        let purchase = try InventoryPlanningRules.purchasing(item: need, totalBought: 1_000, transferAmount: 1_000, userID: uid)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: purchase)
        let raw = try await ref.getDocument(source: .server).data()!
        XCTAssertEqual(raw["futureList"] as? String, "keep")
        let rawItems = try XCTUnwrap(raw["items"] as? [[String: Any]])
        XCTAssertEqual(rawItems[1]["futureGrocery"] as? String, "preserve")
        let currentStock = try await client.repository.fetchInventory(userID: uid)
        let currentGrocery = try await client.repository.fetchGroceryList(userID: uid)
        let undo = try InventoryPlanningRules.undoing(purchase, current: currentStock, groceries: currentGrocery)
        try await client.repository.applyInventoryMutation(userID: uid, mutation: undo)
        let finalGrocery = try await client.repository.fetchGroceryList(userID: uid)
        XCTAssertEqual(finalGrocery[0].transferredToPantryQuantity, 0)
        XCTAssertEqual(finalGrocery[0].purchasedQuantity, 1_000)
        XCTAssertEqual(finalGrocery[1].id, manual.id)
    }
    func testStatusReplayAfterLaterEditCancelFenceAndWrongAccount() async throws {
        let client = client(); let uid = try await client.auth.signInAnonymously().user.uid
        let item = lot()
        let add = InventoryMutation(userID: uid, title: "Add rice", reason: .purchase, before: [], after: [item])
        try await client.repository.applyInventoryMutation(userID: uid, mutation: add)
        let ref = client.db.collection("users").document(uid).collection("pantryItems").document(item.id.uuidString)
        try await ref.updateData(["quantity": 777])
        try await client.repository.applyInventoryMutation(userID: uid, mutation: add)
        let replayed = try await ref.getDocument(source: .server).data(as: PantryItem.self)
        XCTAssertEqual(replayed.quantity, 777)
        let resolution = try await client.repository.resolveInventoryMutation(userID: uid, mutation: add, cancelPending: true)
        XCTAssertEqual(resolution, .accepted)
        var altered = add; altered.after[0].quantity = 123
        do { try await client.repository.applyInventoryMutation(userID: uid, mutation: altered); XCTFail("Payload identity reuse") } catch {}
        var cancelled = add; cancelled.id = UUID(); cancelled.after[0].id = UUID()
        let fence = try await client.repository.resolveInventoryMutation(userID: uid, mutation: cancelled, cancelPending: true)
        XCTAssertEqual(fence, .cancelled)
        do { try await client.repository.applyInventoryMutation(userID: uid, mutation: cancelled); XCTFail("Cancelled apply") } catch {}
        do { _ = try await client.repository.fetchInventory(userID: "another-account"); XCTFail("Wrong account") } catch {}
    }
}
