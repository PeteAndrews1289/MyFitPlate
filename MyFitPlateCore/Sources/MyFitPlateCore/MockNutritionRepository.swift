import Foundation
import Combine

public final class MockNutritionRepository: NutritionRepositoryProtocol {
    public init() {}
    public func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void) {}
    public func saveDailyLog(userID: String, log: DailyLog) async throws {}
    public func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {}
    public func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any { return UUID() }
    public func removeLogSnapshotListener(_ handle: Any) {}
    public func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog] { return [] }
    public func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {}
    public func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay? { return nil }
    public func saveMealPlan(userID: String, plan: MealPlanDay) async throws {}
    public func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws {}
    public func fetchGroceryList(userID: String) async throws -> [GroceryListItem] { return [] }
    public func saveGroceryList(userID: String, items: [GroceryListItem]) async throws {}
    public func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any { return UUID() }
    public func removePantrySnapshotListener(_ handle: Any) {}
    public func savePantryItem(userID: String, item: PantryItem) async throws {}
    public func deletePantryItem(userID: String, itemID: String) async throws {}
    public func fetchRecipes(userID: String) async throws -> [Recipe] { return [] }
    public func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe { return recipe }
    public func deleteRecipe(userID: String, recipeID: String) async throws {}
    public func saveCustomFood(userID: String, foodItem: FoodItem) async throws {}
    public func deleteCustomFood(userID: String, foodItemID: String) async throws {}
    public func fetchCustomFoods(userID: String) async throws -> [FoodItem] { return [] }
    public func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws {}
    public func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem] { return [] }
}
