import Foundation

protocol DailyLogServicing: AnyObject {
    var currentDailyLog: DailyLog? { get set }
    var activelyViewedDate: Date { get set }
    var smartSuggestions: [FoodItem] { get set }
    
    func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService)
    func updateWidgetData()
    func publishCurrentDailyLog(_ log: DailyLog)
    func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String)
    func logFoodItem(_ foodItem: FoodItem, mealType: String) async
    func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)?)
    func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
    func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String)
    func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String)
    func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem)
    func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem])
    func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String)
    func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String)
    func deleteFoodFromCurrentLog(for userID: String, foodItemID: String)
    func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double)
    func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double)
    func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double)
    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
    func loadSmartSuggestions(for userID: String)
    func fetchDailyHistory(for userID: String, startDate: Date?, endDate: Date?) async -> Result<[DailyLog], Error>
}
