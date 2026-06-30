import XCTest
@testable import MyFitPlateCore

@MainActor
final class PantryServiceTests: XCTestCase {
    private var service: PantryService!
    private var mockRepo: MockNutritionRepository!

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        service = PantryService()
    }

    override func tearDown() {
        service.stopListening()
        service = nil
        mockRepo = nil
        super.tearDown()
    }

    private func waitForPantryTasks() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func item(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unit: String,
        category: String = "Misc"
    ) -> PantryItem {
        PantryItem(id: id, name: name, quantity: quantity, unit: unit, category: category, dateAdded: Date(timeIntervalSince1970: 100))
    }

    func testStartListeningSortsSnapshotItemsAndStopsLoading() async {
        mockRepo.mockPantrySnapshotResult = .success([
            item(name: "Zucchini", quantity: 2, unit: "item"),
            item(name: "Apple", quantity: 3, unit: "item")
        ])

        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        XCTAssertEqual(mockRepo.pantryListenerUserIDs, ["user-1"])
        XCTAssertFalse(service.isLoading)
        XCTAssertEqual(service.pantryItems.map(\.name), ["Apple", "Zucchini"])
    }

    func testStartListeningIgnoresEmptyUserID() async {
        service.startListening(userID: "")
        await waitForPantryTasks()

        XCTAssertTrue(mockRepo.pantryListenerUserIDs.isEmpty)
        XCTAssertFalse(service.isLoading)
        XCTAssertTrue(service.pantryItems.isEmpty)
    }

    func testStartListeningSameUserDoesNotRegisterDuplicateListener() async {
        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        XCTAssertEqual(mockRepo.pantryListenerUserIDs, ["user-1"])
        XCTAssertTrue(mockRepo.removedPantryListenerHandles.isEmpty)
    }

    func testStartListeningDifferentUserRemovesPreviousListener() async {
        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        service.startListening(userID: "user-2")
        await waitForPantryTasks()

        XCTAssertEqual(mockRepo.pantryListenerUserIDs, ["user-1", "user-2"])
        XCTAssertEqual(mockRepo.removedPantryListenerHandles.count, 1)
    }

    func testStartListeningFailureStopsLoadingAndKeepsExistingItems() async {
        service.pantryItems = [item(name: "Oats", quantity: 1, unit: "lb")]
        mockRepo.mockPantrySnapshotResult = .failure(URLError(.cannotLoadFromNetwork))

        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        XCTAssertFalse(service.isLoading)
        XCTAssertEqual(service.pantryItems.map(\.name), ["Oats"])
    }

    func testStopListeningClearsItemsByDefault() async {
        service.pantryItems = [item(name: "Oats", quantity: 1, unit: "lb")]
        service.startListening(userID: "user-1")
        await waitForPantryTasks()

        service.stopListening()

        XCTAssertFalse(service.isLoading)
        XCTAssertTrue(service.pantryItems.isEmpty)
        XCTAssertEqual(mockRepo.removedPantryListenerHandles.count, 1)
    }

    func testStopListeningCanKeepItems() async {
        service.pantryItems = [item(name: "Oats", quantity: 1, unit: "lb")]
        service.startListening(userID: "user-1")
        await waitForPantryTasks()
        service.pantryItems = [item(name: "Oats", quantity: 1, unit: "lb")]

        service.stopListening(clearItems: false)

        XCTAssertEqual(service.pantryItems.map(\.name), ["Oats"])
    }

    func testAddOrUpdateItemSavesNewItem() async throws {
        let oats = item(name: "Oats", quantity: 2, unit: "lb")

        service.addOrUpdateItem(oats, userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, oats.id)
        XCTAssertEqual(saved.quantity, 2)
        XCTAssertEqual(mockRepo.savedPantryUserIDs, ["user-1"])
    }

    func testAddOrUpdateItemMergesMatchingNameAndNormalizedUnit() async throws {
        let existingID = UUID()
        service.pantryItems = [
            item(id: existingID, name: "fresh chopped tomatoes", quantity: 2, unit: "cups")
        ]

        service.addOrUpdateItem(item(name: "tomato", quantity: 1.5, unit: "cup"), userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(saved.quantity, 3.5, accuracy: 0.001)
        XCTAssertEqual(saved.unit, "cups")
    }

    func testAddOrUpdateItemUpdatesExistingItemByID() async throws {
        let existingID = UUID()
        service.pantryItems = [item(id: existingID, name: "Rice", quantity: 1, unit: "cup")]

        service.addOrUpdateItem(item(id: existingID, name: "Brown Rice", quantity: 3, unit: "cup"), userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(saved.name, "Brown Rice")
        XCTAssertEqual(saved.quantity, 3)
    }

    func testDeleteItemRecordsRepositoryDelete() async {
        let pantryItem = item(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, name: "Rice", quantity: 1, unit: "cup")

        service.deleteItem(pantryItem, userID: "user-1")
        await waitForPantryTasks()

        XCTAssertEqual(mockRepo.deletedPantryUserIDs, ["user-1"])
        XCTAssertEqual(mockRepo.deletedPantryItemIDs, ["00000000-0000-0000-0000-000000000111"])
    }

    func testClearPantryDeletesEachCurrentItem() async {
        service.pantryItems = [
            item(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, name: "Rice", quantity: 1, unit: "cup"),
            item(id: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!, name: "Beans", quantity: 1, unit: "can")
        ]

        await service.clearPantry(userID: "user-1")
        await waitForPantryTasks()

        XCTAssertEqual(Set(mockRepo.deletedPantryItemIDs), Set([
            "00000000-0000-0000-0000-000000000111",
            "00000000-0000-0000-0000-000000000222"
        ]))
    }

    func testRemoveIngredientsDecrementsMatchingPantryItem() async throws {
        let existingID = UUID()
        service.pantryItems = [item(id: existingID, name: "Chicken Breast", quantity: 2, unit: "lb")]

        service.removeIngredients(["1 lb chicken breast"], userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(saved.quantity, 1, accuracy: 0.001)
        XCTAssertTrue(mockRepo.deletedPantryItemIDs.isEmpty)
    }

    func testRemoveIngredientsDeletesWhenQuantityIsConsumed() async {
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000333")!
        service.pantryItems = [item(id: existingID, name: "Rice", quantity: 1, unit: "cup")]

        service.removeIngredients(["2 cups rice"], userID: "user-1")
        await waitForPantryTasks()

        XCTAssertTrue(mockRepo.savedPantryItems.isEmpty)
        XCTAssertEqual(mockRepo.deletedPantryItemIDs, ["00000000-0000-0000-0000-000000000333"])
    }

    func testRemoveFoodItemsUsesFoodName() async throws {
        let existingID = UUID()
        service.pantryItems = [item(id: existingID, name: "Tomato", quantity: 3, unit: "item")]
        let loggedFood = FoodItem(id: "food-1", name: "1 tomato", calories: 25)

        service.removeIngredients([loggedFood], userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(saved.quantity, 2, accuracy: 0.001)
    }

    func testFoodLoggedNotificationRemovesMatchingIngredient() async throws {
        let existingID = UUID()
        service.pantryItems = [item(id: existingID, name: "Tomato", quantity: 2, unit: "item")]

        DailyLogNotifications.postFoodLogged(FoodItem(id: "food-1", name: "1 tomato", calories: 25), userID: "user-1")
        await waitForPantryTasks()

        let saved = try XCTUnwrap(mockRepo.savedPantryItems.first)
        XCTAssertEqual(saved.id, existingID)
        XCTAssertEqual(saved.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(mockRepo.savedPantryUserIDs, ["user-1"])
    }

    func testSaveAndDeleteFailuresDoNotMutateMockRecords() async {
        mockRepo.pantryItemError = URLError(.timedOut)
        let pantryItem = item(name: "Rice", quantity: 1, unit: "cup")

        service.addOrUpdateItem(pantryItem, userID: "user-1")
        service.deleteItem(pantryItem, userID: "user-1")
        await waitForPantryTasks()

        XCTAssertTrue(mockRepo.savedPantryItems.isEmpty)
        XCTAssertTrue(mockRepo.deletedPantryItemIDs.isEmpty)
    }
}
