import XCTest
@testable import MyFitPlateCore

@MainActor
final class DailyLogServiceTests: XCTestCase {
    
    var service: DailyLogService!
    var mockRepo: MockNutritionRepository!
    var goalSettings: GoalSettings!
    var bannerService: BannerService!
    
    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = MockAuthService() // Assumes there's a MockAuthService
        
        service = DailyLogService()
        goalSettings = GoalSettings()
        bannerService = BannerService()
        
        // Pass a dummy AchievementService
        let achievementService = AchievementService()
        service.setupDependencies(goalSettings: goalSettings, bannerService: bannerService, achievementService: achievementService)
    }

    func testFetchLogInternalAsyncReturnsEmptyLogWhenNoCurrent() async throws {
        let date = Date()
        service.activelyViewedDate = date.addingTimeInterval(86400) // Different day
        
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "123", date: date, meals: []))
        
        let expectation = XCTestExpectation(description: "Fetch complete")
        service.fetchLog(for: "user", date: date) { result in
            switch result {
            case .success(let log):
                XCTAssertEqual(log.id, "123")
                expectation.fulfill()
            case .failure:
                XCTFail()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testAddFoodToCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let initialLog = DailyLog(id: "1", date: date, meals: [])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
        service.addFoodToCurrentLog(for: "user", foodItem: food)
        
        // Let background tasks complete
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        XCTAssertEqual(updatedLog.meals.count, 1)
        XCTAssertEqual(updatedLog.meals[0].foodItems.count, 1)
        XCTAssertEqual(updatedLog.meals[0].foodItems[0].name, "Apple")
    }

    func testUpdateFoodInCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
        let meal = Meal(id: UUID(), name: "Breakfast", foodItems: [food])
        let initialLog = DailyLog(id: "1", date: date, meals: [meal])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        var updatedFood = food
        updatedFood.calories = 100
        service.updateFoodInCurrentLog(for: "user", updatedFoodItem: updatedFood)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        XCTAssertEqual(updatedLog.meals[0].foodItems[0].calories, 100)
    }

    func testDeleteFoodFromCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
        let meal = Meal(id: UUID(), name: "Breakfast", foodItems: [food])
        let initialLog = DailyLog(id: "1", date: date, meals: [meal])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        service.deleteFoodFromCurrentLog(for: "user", foodItemID: "f1")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        let allFoods = updatedLog.meals.flatMap { $0.foodItems }
        XCTAssertTrue(allFoods.isEmpty)
    }

    func testAddWaterToCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let initialLog = DailyLog(id: "1", date: date, meals: [])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        service.addWaterToCurrentLog(for: "user", amount: 16.0, goalOunces: 64.0)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        XCTAssertEqual(updatedLog.waterTracker?.totalOunces, 16.0)
    }

    func testRepeatFoodsWhenSourceIsEmpty() async {
        let sourceDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400))
        let targetDate = Calendar.current.startOfDay(for: Date())
        
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: sourceDate, meals: []))
        
        service.repeatFoods(from: sourceDate, to: targetDate, for: "user")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Since source is empty, banner might show but log shouldn't be updated
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testFetchRecommendedFoods() async {
        let food = FoodItem(id: "r1", name: "Oats", calories: 150)
        mockRepo.mockRecommendedFoods = [food]
        
        let expectation = XCTestExpectation(description: "Fetch Recommended")
        service.fetchRecommendedFoods(for: "user", mealName: "Breakfast") { result in
            switch result {
            case .success(let items):
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items[0].name, "Oats")
                expectation.fulfill()
            case .failure:
                XCTFail()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
