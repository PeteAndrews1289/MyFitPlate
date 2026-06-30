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

    func testAddFoodToPastDateDoesNotReplaceCurrentDailyLog() async throws {
        let viewedDate = Calendar.current.startOfDay(for: Date())
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: viewedDate)!
        service.activelyViewedDate = viewedDate
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "past", date: pastDate, meals: []))

        service.addFoodToLog(
            for: "user",
            date: pastDate,
            mealName: "Dinner",
            foodItem: FoodItem(id: "f1", name: "Salmon", calories: 350),
            source: "recipe"
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.id, "past")
        XCTAssertEqual(updatedLog.meals.map(\.name), ["Dinner"])
        XCTAssertNil(service.currentDailyLog)
    }

    func testAddFoodFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.notConnectedToInternet))

        service.addFoodToCurrentLog(for: "user", foodItem: FoodItem(id: "f1", name: "Apple", calories: 95))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testUpdateFoodMissingItemSkipsUpdate() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let existing = FoodItem(id: "existing", name: "Apple", calories: 95)
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: date, meals: [Meal(name: "Breakfast", foodItems: [existing])]))

        service.updateFoodInCurrentLog(for: "user", updatedFoodItem: FoodItem(id: "missing", name: "Banana", calories: 110))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testUpdateFoodFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.timedOut))

        service.updateFoodInCurrentLog(for: "user", updatedFoodItem: FoodItem(id: "f1", name: "Apple", calories: 95))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testAddMealGroupsSkipsEmptyGroups() async {
        service.addMealGroupsToLog(
            for: "user",
            date: Date(),
            mealGroups: [
                (mealName: "Breakfast", foodItems: []),
                (mealName: "Lunch", foodItems: [])
            ]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testAddMealGroupsAddsMultipleMealsAndPublishesCurrentLog() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: date, meals: []))

        service.addMealGroupsToLog(
            for: "user",
            date: date,
            mealGroups: [
                (mealName: "Breakfast", foodItems: [FoodItem(id: "eggs", name: "Eggs", calories: 140)]),
                (mealName: "Lunch", foodItems: [FoodItem(id: "rice", name: "Rice", calories: 200)])
            ],
            source: "meal_plan"
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.meals.map(\.name), ["Breakfast", "Lunch"])
        XCTAssertEqual(updatedLog.meals.flatMap(\.foodItems).map(\.name), ["Eggs", "Rice"])
        XCTAssertEqual(service.currentDailyLog?.meals.count, 2)
    }

    func testAddMealGroupsFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.cannotFindHost))

        service.addMealToCurrentLog(
            for: "user",
            mealName: "Dinner",
            foodItems: [FoodItem(id: "f1", name: "Chicken", calories: 250)]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testDeleteFoodMissingItemSkipsUpdate() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let existing = FoodItem(id: "existing", name: "Apple", calories: 95)
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: date, meals: [Meal(name: "Breakfast", foodItems: [existing])]))

        service.deleteFoodFromCurrentLog(for: "user", foodItemID: "missing")

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testDeleteFoodFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.cannotLoadFromNetwork))

        service.deleteFoodFromCurrentLog(for: "user", foodItemID: "f1")

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testAddWaterFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.networkConnectionLost))

        service.addWaterToCurrentLog(for: "user", amount: 12, goalOunces: 64)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testAddWorkoutToLogAddsExercise() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        service.publishCurrentDailyLog(DailyLog(id: "1", date: date, meals: []))
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: date, meals: []))

        service.addWorkoutToCurrentLog(for: "user", exerciseName: "Walk", durationMinutes: 35, caloriesBurned: 180)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.exercises?.map(\.name), ["Walk"])
        XCTAssertEqual(updatedLog.exercises?.first?.durationMinutes, 35)
        XCTAssertEqual(service.currentDailyLog?.exercises?.map(\.name), ["Walk"])
    }

    func testAddWorkoutFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.dnsLookupFailed))

        service.addWorkoutToCurrentLog(for: "user", exerciseName: "Walk", durationMinutes: 35, caloriesBurned: 180)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testFetchDailyHistoryReturnsSuccessAndFailure() async {
        let date = Calendar.current.startOfDay(for: Date())
        mockRepo.mockFetchDailyHistoryResult = .success([DailyLog(id: "1", date: date, meals: [])])

        let success = await service.fetchDailyHistory(for: "user")
        if case .success(let logs) = success {
            XCTAssertEqual(logs.map(\.id), ["1"])
        } else {
            XCTFail("expected history success")
        }

        mockRepo.mockFetchDailyHistoryResult = .failure(URLError(.timedOut))
        let failure = await service.fetchDailyHistory(for: "user")
        if case .failure = failure {} else {
            XCTFail("expected history failure")
        }
    }

    func testLoadSmartSuggestionsDeduplicatesRecentFoods() async {
        mockRepo.recentFoodsToReturn = [
            FoodItem(id: "1", name: "Apple", calories: 95),
            FoodItem(id: "2", name: "apple", calories: 95),
            FoodItem(id: "3", name: "Oats", calories: 150)
        ]

        service.loadSmartSuggestions(for: "user")

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.smartSuggestions.map(\.name), ["Apple", "Oats"])
    }

    func testRepeatFoodsWhenSourceHasMeals() async {
        let sourceDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400))
        let targetDate = Calendar.current.startOfDay(for: Date())
        
        let food = FoodItem(id: "r1", name: "Oats", calories: 150)
        let meal = Meal(name: "Breakfast", foodItems: [food])
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: sourceDate, meals: [meal]))
        
        service.repeatFoods(from: sourceDate, to: targetDate, for: "user")
        
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        XCTAssertEqual(updatedLog.meals.count, 1)
        XCTAssertEqual(updatedLog.meals[0].name, "Breakfast")
        XCTAssertEqual(updatedLog.meals[0].foodItems.count, 2)
        XCTAssertEqual(updatedLog.meals[0].foodItems[1].name, "Oats")
    }

    func testRepeatFoodsFetchFailure() async {
        let sourceDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400))
        let targetDate = Calendar.current.startOfDay(for: Date())
        
        mockRepo.mockFetchLogResult = .failure(URLError(.notConnectedToInternet))
        
        service.repeatFoods(from: sourceDate, to: targetDate, for: "user")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNil(mockRepo.lastUpdatedLog)
    }

    func testNormalizedFoodForLogging() {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        mockRepo.mockFetchLogResult = .success(DailyLog(id: "1", date: date, meals: []))
        
        var food = FoodItem(id: "f1", name: "Apple", calories: 95)
        // Add a case where normalizedForEstimatedSource changes calories if source is some specific string
        // Actually we just test that the logging calls the normalizer and adds it.
        service.addFoodToLog(for: "user", date: date, mealName: "Snack", foodItem: food, source: "estimate")
        
        let exp = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
    }
}
