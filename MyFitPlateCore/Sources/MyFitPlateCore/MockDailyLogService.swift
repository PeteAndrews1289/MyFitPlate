import Foundation

@MainActor
public class MockDailyLogService: DailyLogServicing {
    public var currentDailyLog: DailyLog? = nil
    public var activelyViewedDate: Date = Date()
    public var smartSuggestions: [FoodItem] = []
    
    public func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: date, meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    public func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: date, meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    public func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: Date(), meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    public func fetchDailyHistory(for userID: String, startDate: Date?, endDate: Date?) async -> Result<[DailyLog], Error> {
        return .success([])
    }
    
    public func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        // Mock implementation
    }
    
    public func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String) {
        // Mock implementation
    }
    
    public func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String) {
        // Mock implementation
    }
    
    public func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem) {
        // Mock implementation
    }
    
    public func deleteFoodFromCurrentLog(for userID: String, foodItemID: String) {
        // Mock implementation
    }
    
    public func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        // Mock implementation
    }
    
    public func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String) {
        // Mock implementation
    }
    
    public func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String) {
        // Mock implementation
    }
    
    public func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String) {
        // Mock implementation
    }
    
    public func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        completion(.success([]))
    }
    
    public func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
        // Mock implementation
    }
    
    public func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        // Mock implementation
    }
    
    public func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        // Mock implementation
    }
    
    public func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        completion(.success([]))
    }
    
    public func loadSmartSuggestions(for userID: String) {
        // Mock implementation
    }
    
    public func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService) {
        // Mock implementation
    }
    
    public func updateWidgetData() {
        // Mock implementation
    }
    
    public func publishCurrentDailyLog(_ log: DailyLog) {
        // Mock implementation
    }
    
    public func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)?) {
        completion?(true)
    }
}
