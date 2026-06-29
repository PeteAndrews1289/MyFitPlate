import Foundation

@MainActor
public protocol DailyLogReading: AnyObject {
    var currentDailyLog: DailyLog? { get set }
    var activelyViewedDate: Date { get set }

    func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchDailyHistory(for userID: String, startDate: Date?, endDate: Date?) async -> Result<[DailyLog], Error>
}

@MainActor
public protocol FoodLogging: AnyObject {
    func logFoodItem(_ foodItem: FoodItem, mealType: String) async
    func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String)
    func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String)
    func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem)
    func deleteFoodFromCurrentLog(for userID: String, foodItemID: String)

    func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem])
    func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String)
    func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String)
    func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String)

    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
}

@MainActor
public protocol WaterLogging: AnyObject {
    func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double)
}

@MainActor
public protocol WorkoutLogging: AnyObject {
    func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double)
    func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double)
}

@MainActor
public protocol SmartSuggestionProviding: AnyObject {
    var smartSuggestions: [FoodItem] { get set }

    func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
    func loadSmartSuggestions(for userID: String)
}

@MainActor
public protocol DailyLogStateManaging: AnyObject {
    func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService)
    func updateWidgetData()
    func publishCurrentDailyLog(_ log: DailyLog)
    func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)?)
}

/// The umbrella protocol that encompasses all Daily Log capabilities.
/// Over time, objects should depend on the smaller segregated protocols above.
@MainActor
public protocol DailyLogServicing: DailyLogReading, FoodLogging, WaterLogging, WorkoutLogging, SmartSuggestionProviding, DailyLogStateManaging {}
