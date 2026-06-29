import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlannerServiceTests: XCTestCase {
    
    var service: MealPlannerService!
    var mockRepo: MockNutritionRepository!
    var mockAI: MockAIService!
    var mockAnalytics: MockAnalyticsManager!
    
    override func setUp() {
        super.setUp()
        
        mockRepo = MockNutritionRepository()
        mockAI = MockAIService()
        mockAnalytics = MockAnalyticsManager()
        
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.aiService = mockAI
        DIContainer.shared.analyticsManager = mockAnalytics
        
        // Clear User Defaults Cache
        UserDefaults.standard.removeObject(forKey: "mealPlanCache")
        
        let recipeService = RecipeService()
        service = MealPlannerService(recipeService: recipeService)
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "mealPlanCache")
        service = nil
        mockRepo = nil
        mockAI = nil
        mockAnalytics = nil
        super.tearDown()
    }
    
    // MARK: - Caching and Fetching
    func testFetchPlanHitsCacheFirst() async {
        let date = Date()
        let plan = MealPlanDay(id: "test", date: date, meals: [])
        await service.savePlan(plan, for: "user1")
        
        // Mock repo should not be called again because it's cached
        mockRepo.mockFetchMealPlanResult = nil
        
        let fetched = await service.fetchPlan(for: date, userID: "user1")
        XCTAssertEqual(fetched?.id, "test")
    }
    
    func testFetchPlanFromRepoIfCacheMiss() async {
        let date = Date()
        let plan = MealPlanDay(id: "test2", date: date, meals: [])
        mockRepo.mockFetchMealPlanResult = plan
        
        let fetched = await service.fetchPlan(for: date, userID: "user1")
        XCTAssertEqual(fetched?.id, "test2")
        
        // Next fetch should be cached
        mockRepo.mockFetchMealPlanResult = nil
        let cached = await service.fetchPlan(for: date, userID: "user1")
        XCTAssertEqual(cached?.id, "test2")
    }
    
    func testInvalidateCache() async {
        let date = Date()
        let plan = MealPlanDay(id: "test", date: date, meals: [])
        await service.savePlan(plan, for: "user1")
        
        service.invalidateCache()
        
        mockRepo.mockFetchMealPlanResult = nil
        let fetched = await service.fetchPlan(for: date, userID: "user1")
        XCTAssertNil(fetched)
    }
    
    func testCachedPlan() async {
        let date = Date()
        let plan = MealPlanDay(id: "testCached", date: date, meals: [])
        await service.savePlan(plan, for: "user1")
        
        let cached = service.cachedPlan(for: date, userID: "user1")
        XCTAssertEqual(cached?.id, "testCached")
    }
    
    func testPrefetchPlans() async {
        let date = Date()
        let plan = MealPlanDay(id: "prefetchDay", date: date, meals: [])
        mockRepo.mockFetchMealPlanResult = plan
        
        await service.prefetchPlans(starting: date, userID: "user1")
        
        // They should be in cache now
        let cached = service.cachedPlan(for: date, userID: "user1")
        XCTAssertEqual(cached?.id, "prefetchDay")
    }
    
    // MARK: - Saving
    func testSaveFullMealPlan() async {
        let days = [
            MealPlanDay(id: "d1", date: Date(), meals: []),
            MealPlanDay(id: "d2", date: Date(), meals: [])
        ]
        
        await service.saveFullMealPlan(days: days, for: "user1")
        
        XCTAssertEqual(mockRepo.batchSavedMealPlans.count, 2)
        XCTAssertEqual(mockRepo.batchSavedMealPlans.first?.id, "d1")
    }
    
    // MARK: - AI Meal Generation
    func testGenerateAndSaveFullWeekPlanSuccess() async {
        // mockAI needs to return 7 days worth of plans.
        let json = """
        [
            {"date": "2023-10-01", "meals": []},
            {"date": "2023-10-02", "meals": []},
            {"date": "2023-10-03", "meals": []},
            {"date": "2023-10-04", "meals": []},
            {"date": "2023-10-05", "meals": []},
            {"date": "2023-10-06", "meals": []},
            {"date": "2023-10-07", "meals": []}
        ]
        """
        mockAI.mockResult = .success(json)
        
        let goalSettings = GoalSettings()
        goalSettings.calories = 2000
        goalSettings.protein = 150
        goalSettings.carbs = 200
        goalSettings.fats = 70
        
        let result = await service.generateAndSaveFullWeekPlan(
            goals: goalSettings,
            preferredFoods: [],
            preferredCuisines: ["Italian"],
            preferredSnacks: [],
            userID: "user1"
        )
        
        XCTAssertTrue(result)
        XCTAssertEqual(mockRepo.batchSavedMealPlans.count, 7)
    }
    
    func testGenerateAndSaveFullWeekPlanFallback() async {
        mockAI.mockResult = .failure(.apiError("test"))
        let goalSettings = GoalSettings()
        goalSettings.calories = 2000
        goalSettings.protein = 150
        goalSettings.carbs = 200
        goalSettings.fats = 70
        
        let result = await service.generateAndSaveFullWeekPlan(
            goals: goalSettings,
            preferredFoods: [],
            preferredCuisines: [],
            preferredSnacks: [],
            userID: "user1"
        )
        
        XCTAssertTrue(result)
        XCTAssertEqual(mockRepo.batchSavedMealPlans.count, 7)
    }
    
    func testRegenerateSingleMealSuccess() async {
        let json = """
        {
            "mealType": "Lunch",
            "mealName": "Chicken Rice Bowl",
            "calories": 500,
            "protein": 40,
            "carbs": 50,
            "fats": 15,
            "ingredients": ["Chicken", "Rice"],
            "instructions": ["Cook chicken", "Cook rice"]
        }
        """
        mockAI.mockResult = .success(json)
        
        let day = MealPlanDay(id: "day1", date: Date(), meals: [])
        let mealToReplace = PlannedMeal(mealType: "Lunch")
        let goals = GoalSettings()
        
        let regenerated = await service.regenerateSingleMeal(
            for: day,
            mealToReplace: mealToReplace,
            goals: goals,
            preferredFoods: [],
            preferredCuisines: [],
            preferredSnacks: [],
            userID: "user1"
        )
        
        XCTAssertNotNil(regenerated)
        XCTAssertEqual(regenerated?.mealType, "Lunch")
        XCTAssertEqual(regenerated?.ingredients?.count, 2)
    }
    
    // MARK: - Grocery List
    func testSaveAndFetchGroceryList() async {
        let items = [GroceryListItem(name: "Apple", quantity: 2, unit: "pieces")]
        mockRepo.mockFetchGroceryListResult = items
        
        service.saveGroceryList(items, for: "user1")
        
        // Let the async Task inside saveGroceryList finish
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        XCTAssertEqual(mockRepo.savedGroceryLists.count, 1)
        XCTAssertEqual(mockRepo.savedGroceryLists.first?.name, "Apple")
        
        let fetched = await service.fetchGroceryList(for: "user1")
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Apple")
    }
    
    func testRefreshGroceryList() async {
        let date = Date()
        let meal = PlannedMeal(mealType: "Breakfast", ingredients: ["100g Oats", "1 cup Milk"])
        let plan = MealPlanDay(id: "day1", date: date, meals: [meal])
        
        await service.savePlan(plan, for: "user1")
        
        await service.refreshGroceryList(for: "user1", starting: date)
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        // refresh fetches existing items (0 here) and adds generated
        XCTAssertFalse(mockRepo.savedGroceryLists.isEmpty)
    }
}
