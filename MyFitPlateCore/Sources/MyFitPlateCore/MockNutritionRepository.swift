import Foundation
import Combine

public final class MockNutritionRepository: NutritionRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public init() {}
    
    // Properties for testing
    public var lastUpdatedLog: DailyLog?
    public var savedDailyLogs: [DailyLog] = []
    public var savedDailyLogUserIDs: [String] = []
    public var saveDailyLogError: Error?
    public var updateLogSuccess: Bool = true
    public var mockFetchLogResult: Result<DailyLog, Error>?
    public var mockFetchDailyHistoryResult: Result<[DailyLog], Error>?
    public var mockRecommendedFoods: [FoodItem] = []
    
    public func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {
        lastUpdatedLog = log
        completion(updateLogSuccess)
    }
    public func saveDailyLog(userID: String, log: DailyLog) async throws {
        if let saveDailyLogError { throw saveDailyLogError }
        lastUpdatedLog = log
        savedDailyLogs.append(log)
        savedDailyLogUserIDs.append(userID)
    }
    public func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        if let result = mockFetchLogResult {
            completion(result)
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            completion(.success(emptyLog))
        }
    }
    public func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any { 
        if let result = mockFetchLogResult {
            onChange(result)
        } else {
            let emptyLog = DailyLog(id: "test", date: date, meals: [])
            onChange(.success(emptyLog))
        }
        return UUID() 
    }
    public func removeLogSnapshotListener(_ handle: Any) {}
    public func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog] { 
        if let mock = mockFetchDailyHistoryResult {
            return try mock.get()
        }
        return [] 
    }
    public func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        completion(.success(mockRecommendedFoods))
    }
    public var mockFetchMealPlanResult: MealPlanDay?
    public var mockFetchGroceryListResult: [GroceryListItem] = []
    public var savedMealPlans: [MealPlanDay] = []
    public var savedGroceryLists: [GroceryListItem] = []
    public var batchSavedMealPlans: [MealPlanDay] = []
    
    public func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? { 
        return mockFetchMealPlanResult 
    }
    public func saveMealPlan(userID: String, plan: MealPlanDay) async throws {
        savedMealPlans.append(plan)
    }
    public func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {
        batchSavedMealPlans.append(contentsOf: plans)
    }
    public func fetchGroceryList(userID: String) async throws -> [GroceryListItem] { 
        return mockFetchGroceryListResult 
    }
    public func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {
        savedGroceryLists = items
    }
    public var mockPantrySnapshotResult: Result<[PantryItem], Error>?
    public var pantryListenerUserIDs: [String] = []
    public var removedPantryListenerHandles: [Any] = []
    public var savedPantryItems: [PantryItem] = []
    public var savedPantryUserIDs: [String] = []
    public var deletedPantryItemIDs: [String] = []
    public var deletedPantryUserIDs: [String] = []
    public var pantryItemError: Error?

    public func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any {
        pantryListenerUserIDs.append(userID)
        if let mockPantrySnapshotResult {
            onChange(mockPantrySnapshotResult)
        } else {
            onChange(.success([]))
        }
        return UUID()
    }

    public func removePantrySnapshotListener(_ handle: Any) {
        removedPantryListenerHandles.append(handle)
    }

    public func savePantryItem(userID: String, item: PantryItem) async throws {
        if let pantryItemError { throw pantryItemError }
        savedPantryUserIDs.append(userID)
        savedPantryItems.append(item)
    }

    public func deletePantryItem(userID: String, itemID: String) async throws {
        if let pantryItemError { throw pantryItemError }
        lock.lock()
        deletedPantryUserIDs.append(userID)
        deletedPantryItemIDs.append(itemID)
        lock.unlock()
    }
    public var mockRecipes: [Recipe] = []
    public var savedRecipes: [Recipe] = []
    public var deletedRecipeIDs: [String] = []
    
    public func fetchRecipes(userID: String) async throws -> [Recipe] { return mockRecipes }
    public func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe { 
        savedRecipes.append(recipe)
        return recipe 
    }
    public func deleteRecipe(userID: String, recipeID: String) async throws {
        deletedRecipeIDs.append(recipeID)
    }
    public var savedCustomFoods: [FoodItem] = []
    public var deletedCustomFoodIDs: [String] = []
    public var customFoodsToReturn: [FoodItem] = []
    public var customFoodError: Error?
    public func saveCustomFood(userID: String, foodItem: FoodItem) async throws {
        if let customFoodError { throw customFoodError }
        savedCustomFoods.append(foodItem)
    }
    public func deleteCustomFood(userID: String, foodItemID: String) async throws {
        if let customFoodError { throw customFoodError }
        deletedCustomFoodIDs.append(foodItemID)
    }
    public func fetchCustomFoods(userID: String) async throws -> [FoodItem] {
        if let customFoodError { throw customFoodError }
        return customFoodsToReturn
    }
    public var savedRecentFoods: [(userID: String, foodItem: FoodItem, source: String, stableID: String)] = []
    public var recentFoodsToReturn: [FoodItem] = []
    public var recentFoodError: Error?
    public var fetchRecentFoodLimits: [Int] = []

    public func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws {
        if let recentFoodError { throw recentFoodError }
        savedRecentFoods.append((userID, foodItem, source, stableID))
    }

    public func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem] {
        if let recentFoodError { throw recentFoodError }
        fetchRecentFoodLimits.append(limit)
        return Array(recentFoodsToReturn.prefix(limit))
    }
}
