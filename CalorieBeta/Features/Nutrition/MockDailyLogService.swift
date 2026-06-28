import Foundation

@MainActor
class MockDailyLogService: DailyLogServicing {
    var currentDailyLog: DailyLog? = nil
    var activelyViewedDate: Date = Date()
    var smartSuggestions: [FoodItem] = []
    
    func fetchLog(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: date, meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    func fetchLogInternal(for userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: date, meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    func fetchOrCreateTodayLog(for userID: String, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        let mockLog = DailyLog(id: "mock_log_id", date: Date(), meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: nil, journalEntries: nil)
        completion(.success(mockLog))
    }
    
    func fetchDailyHistory(for userID: String, startDate: Date?, endDate: Date?) async -> Result<[DailyLog], Error> {
        return .success([])
    }
    
    func logFoodItem(_ foodItem: FoodItem, mealType: String) async {
        // Mock implementation
    }
    
    func addFoodToCurrentLog(for userID: String, foodItem: FoodItem, source: String) {
        // Mock implementation
    }
    
    func addFoodToLog(for userID: String, date: Date, mealName: String, foodItem: FoodItem, source: String) {
        // Mock implementation
    }
    
    func updateFoodInCurrentLog(for userID: String, updatedFoodItem: FoodItem) {
        // Mock implementation
    }
    
    func deleteFoodFromCurrentLog(for userID: String, foodItemID: String) {
        // Mock implementation
    }
    
    func addMealToCurrentLog(for userID: String, mealName: String, foodItems: [FoodItem]) {
        // Mock implementation
    }
    
    func addMealToLog(for userID: String, date: Date, mealName: String, foodItems: [FoodItem], source: String) {
        // Mock implementation
    }
    
    func addMealGroupsToLog(for userID: String, date: Date, mealGroups: [(mealName: String, foodItems: [FoodItem])], source: String) {
        // Mock implementation
    }
    
    func repeatFoods(from sourceDate: Date, to targetDate: Date, for userID: String) {
        // Mock implementation
    }
    
    func fetchRecentFoodItems(for userID: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        completion(.success([]))
    }
    
    func addWaterToCurrentLog(for userID: String, amount: Double, goalOunces: Double) {
        // Mock implementation
    }
    
    func addWorkoutToCurrentLog(for userID: String, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        // Mock implementation
    }
    
    func addWorkoutToLog(for userID: String, date: Date, exerciseName: String, durationMinutes: Int?, caloriesBurned: Double) {
        // Mock implementation
    }
    
    func fetchRecommendedFoods(for userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        completion(.success([]))
    }
    
    func loadSmartSuggestions(for userID: String) {
        // Mock implementation
    }
    
    func setupDependencies(goalSettings: GoalSettings, bannerService: BannerService, achievementService: AchievementService) {
        // Mock implementation
    }
    
    func updateWidgetData() {
        // Mock implementation
    }
    
    func publishCurrentDailyLog(_ log: DailyLog) {
        // Mock implementation
    }
    
    func updateDailyLog(for userID: String, updatedLog: DailyLog, completion: ((Bool) -> Void)?) {
        completion?(true)
    }
}
