import Foundation

public protocol NutritionRepositoryProtocol: Sendable {
    func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void)
    func saveDailyLog(userID: String, log: DailyLog) async throws
    func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any
    func removeLogSnapshotListener(_ handle: Any)
    func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog]
    func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
    
    // Meal Plans & Grocery List
    func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay?
    func saveMealPlan(userID: String, plan: MealPlanDay) async throws
    func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws
    func fetchGroceryList(userID: String) async throws -> [GroceryListItem]
    func saveGroceryList(userID: String, items: [GroceryListItem]) async throws
    
    // Pantry
    func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any
    func removePantrySnapshotListener(_ handle: Any)
    func savePantryItem(userID: String, item: PantryItem) async throws
    func deletePantryItem(userID: String, itemID: String) async throws
    
    // Recipes
    func fetchRecipes(userID: String) async throws -> [Recipe]
    func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe
    func deleteRecipe(userID: String, recipeID: String) async throws
    
    // Custom Foods
    func saveCustomFood(userID: String, foodItem: FoodItem) async throws
    func deleteCustomFood(userID: String, foodItemID: String) async throws
    func fetchCustomFoods(userID: String) async throws -> [FoodItem]
    
    // Recent Foods
    func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws
    func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem]
}
