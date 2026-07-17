import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlannerServiceTests: XCTestCase {
    
    var service: MealPlannerService!
    var mockRepo: MockNutritionRepository!
    var mockAI: MockAIService!
    var mockAnalytics: MockAnalyticsManager!
    var mockAuth: MockAuthService!
    var userDefaults: UserDefaults!
    var userDefaultsSuiteName: String!
    
    override func setUp() {
        super.setUp()
        
        mockRepo = MockNutritionRepository()
        mockAI = MockAIService()
        mockAnalytics = MockAnalyticsManager()
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "user1"
        userDefaultsSuiteName = "MealPlannerServiceTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.aiService = mockAI
        DIContainer.shared.analyticsManager = mockAnalytics
        DIContainer.shared.authService = mockAuth
        
        let recipeService = RecipeService()
        service = MealPlannerService(recipeService: recipeService, userDefaults: userDefaults)
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        service = nil
        mockRepo = nil
        mockAI = nil
        mockAnalytics = nil
        mockAuth = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
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
        
        service.invalidateCache(for: "user1")
        
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

    func testDiskCacheIsSeparatedByAccountAndDoesNotPersistRawUserIDs() async throws {
        let date = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 7, day: 16, hour: 12).date
        )
        let userOnePlan = MealPlanDay(id: "plan-a", date: date, meals: [])
        let userTwoPlan = MealPlanDay(id: "plan-b", date: date, meals: [])

        let savedUserOne = await service.savePlan(userOnePlan, for: "user-one")
        let savedUserTwo = await service.savePlan(userTwoPlan, for: "user-two")
        XCTAssertTrue(savedUserOne)
        XCTAssertTrue(savedUserTwo)

        let reloadedService = MealPlannerService(
            recipeService: RecipeService(),
            userDefaults: userDefaults
        )
        XCTAssertEqual(
            reloadedService.cachedPlan(for: date, userID: "user-one")?.id,
            userOnePlan.id
        )
        XCTAssertEqual(
            reloadedService.cachedPlan(for: date, userID: "user-two")?.id,
            userTwoPlan.id
        )
        XCTAssertNil(userDefaults.data(forKey: "mealPlanCache"))

        let userOneKey = try XCTUnwrap(
            AccountScopedStorageKey.make(prefix: "mealPlanCache", userID: "user-one")
        )
        let persistedData = try XCTUnwrap(userDefaults.data(forKey: userOneKey))
        let persistedText = try XCTUnwrap(String(bytes: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedText.contains("user-one"))
        XCTAssertFalse(persistedText.contains("user-two"))
    }

    func testInvalidateCacheOnlyRemovesRequestedAccount() async throws {
        let date = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 7, day: 16, hour: 12).date
        )
        let savedUserOne = await service.savePlan(
            MealPlanDay(id: "one", date: date, meals: []),
            for: "user-one"
        )
        let savedUserTwo = await service.savePlan(
            MealPlanDay(id: "two", date: date, meals: []),
            for: "user-two"
        )
        XCTAssertTrue(savedUserOne)
        XCTAssertTrue(savedUserTwo)

        service.invalidateCache(for: "user-one")

        XCTAssertNil(service.cachedPlan(for: date, userID: "user-one"))
        XCTAssertEqual(service.cachedPlan(for: date, userID: "user-two")?.id, "two")
        let reloadedService = MealPlannerService(
            recipeService: RecipeService(),
            userDefaults: userDefaults
        )
        XCTAssertNil(reloadedService.cachedPlan(for: date, userID: "user-one"))
        XCTAssertEqual(reloadedService.cachedPlan(for: date, userID: "user-two")?.id, "two")
    }

    func testLegacyCombinedCacheMigratesEveryAccountBeforeRemoval() async throws {
        let date = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 7, day: 16, hour: 12).date
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        let legacyPlans = [
            "user-one::\(dateKey)": MealPlanDay(id: "legacy-one", date: date, meals: []),
            "user-two::\(dateKey)": MealPlanDay(id: "legacy-two", date: date, meals: [])
        ]
        userDefaults.set(try JSONEncoder().encode(legacyPlans), forKey: "mealPlanCache")
        let migratedService = MealPlannerService(
            recipeService: RecipeService(),
            userDefaults: userDefaults
        )

        XCTAssertEqual(migratedService.cachedPlan(for: date, userID: "user-one")?.id, "legacy-one")
        XCTAssertEqual(migratedService.cachedPlan(for: date, userID: "user-two")?.id, "legacy-two")
        XCTAssertNil(userDefaults.data(forKey: "mealPlanCache"))
        let userOneKey = try XCTUnwrap(
            AccountScopedStorageKey.make(prefix: "mealPlanCache", userID: "user-one")
        )
        let userTwoKey = try XCTUnwrap(
            AccountScopedStorageKey.make(prefix: "mealPlanCache", userID: "user-two")
        )
        XCTAssertNotNil(userDefaults.data(forKey: userOneKey))
        XCTAssertNotNil(userDefaults.data(forKey: userTwoKey))
    }
    
    // MARK: - Saving
    func testSaveFullMealPlan() async {
        let days = [
            MealPlanDay(id: "d1", date: Date(), meals: []),
            MealPlanDay(id: "d2", date: Date(), meals: [])
        ]
        
        let saved = await service.saveFullMealPlan(days: days, for: "user1")
        
        XCTAssertTrue(saved)
        XCTAssertEqual(mockRepo.batchSavedMealPlans.count, 2)
        XCTAssertEqual(mockRepo.batchSavedMealPlans.first?.id, "d1")
    }

    func testSaveFullMealPlanFailureReturnsFalseAndDoesNotCache() async {
        let date = Date()
        let plan = MealPlanDay(id: "failed-day", date: date, meals: [])
        mockRepo.mealPlanError = APIError.apiError("save failed")

        let saved = await service.saveFullMealPlan(days: [plan], for: "user1")

        XCTAssertFalse(saved)
        XCTAssertTrue(mockRepo.batchSavedMealPlans.isEmpty)
        XCTAssertNil(service.cachedPlan(for: date, userID: "user1"))
    }

    func testDiscardMealPlanRemovesSevenDaysAndPreservesNonPlanGroceryItems() async throws {
        let calendar = Calendar.current
        let startDate = try XCTUnwrap(
            DateComponents(calendar: calendar, year: 2026, month: 7, day: 16, hour: 12).date
        )
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: startDate))
        }

        for date in dates {
            let dateString = formatter.string(from: date)
            let plan = MealPlanDay(
                id: dateString,
                date: date,
                meals: [PlannedMeal(mealType: "Dinner", ingredients: ["Chicken"])]
            )
            mockRepo.mockMealPlansByDateString[dateString] = plan
            _ = await service.fetchPlan(for: date, userID: "user1")
        }

        let manualItem = GroceryListItem(
            name: "Coffee filters",
            quantity: 1,
            unit: "item",
            source: "manual"
        )
        let barcodeItem = GroceryListItem(
            name: "Sparkling water",
            quantity: 2,
            unit: "item",
            source: "barcode"
        )
        mockRepo.mockFetchGroceryListResult = [
            GroceryListItem(
                name: "Chicken",
                quantity: 2,
                unit: "lb",
                source: "mealPlan",
                sourcePlanStart: startDate
            ),
            manualItem,
            barcodeItem
        ]

        let discarded = await service.discardMealPlan(starting: startDate, for: "user1")

        XCTAssertTrue(discarded)
        XCTAssertEqual(mockRepo.discardedMealPlanUserIDs, ["user1"])
        XCTAssertEqual(mockRepo.discardedMealPlanDateStrings, dates.map(formatter.string(from:)))
        XCTAssertEqual(mockRepo.savedGroceryLists, [manualItem, barcodeItem])
        XCTAssertTrue(mockRepo.mockMealPlansByDateString.isEmpty)
        XCTAssertTrue(dates.allSatisfy { service.cachedPlan(for: $0, userID: "user1") == nil })
        XCTAssertEqual(mockAnalytics.loggedEvents.last?.name, "meal_plan_discarded")
    }

    func testDiscardMealPlanFailureKeepsCachedPlanAndGroceryItems() async throws {
        let date = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 7, day: 16, hour: 12).date
        )
        let plan = MealPlanDay(
            id: "2026-07-16",
            date: date,
            meals: [PlannedMeal(mealType: "Dinner", ingredients: ["Chicken"])]
        )
        let groceryItems = [
            GroceryListItem(
                name: "Chicken",
                quantity: 2,
                unit: "lb",
                source: "mealPlan"
            )
        ]
        mockRepo.mockFetchGroceryListResult = groceryItems
        _ = await service.savePlan(plan, for: "user1")
        mockRepo.mealPlanError = APIError.apiError("discard failed")

        let discarded = await service.discardMealPlan(starting: date, for: "user1")

        XCTAssertFalse(discarded)
        XCTAssertEqual(service.cachedPlan(for: date, userID: "user1")?.id, plan.id)
        XCTAssertTrue(mockRepo.discardedMealPlanDateStrings.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
        XCTAssertEqual(mockRepo.mockFetchGroceryListResult, groceryItems)
        XCTAssertFalse(mockAnalytics.loggedEvents.contains { $0.name == "meal_plan_discarded" })
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

    func testGenerateAndSaveFullWeekPlanReportsPersistenceFailure() async {
        mockAI.mockResult = .failure(.apiError("use local fallback"))
        mockRepo.mealPlanError = APIError.apiError("save failed")
        let goalSettings = GoalSettings()
        goalSettings.calories = 2000
        goalSettings.protein = 150
        goalSettings.carbs = 200
        goalSettings.fats = 70

        let result = await service.generateAndSaveFullWeekPlan(
            goals: goalSettings,
            preferredFoods: ["Chicken", "Rice", "Broccoli"],
            preferredCuisines: ["Italian"],
            preferredSnacks: ["Yogurt"],
            userID: "user1"
        )

        XCTAssertFalse(result)
        XCTAssertTrue(mockRepo.batchSavedMealPlans.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
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

    func testCancelledWeekGenerationDoesNotPersistAPlan() async {
        mockAI.mockResult = .failure(.apiError("use local fallback"))
        mockAI.responseDelayNanoseconds = 100_000_000
        let goalSettings = GoalSettings()
        goalSettings.calories = 2_000
        goalSettings.protein = 150
        goalSettings.carbs = 200
        goalSettings.fats = 70

        let task = Task {
            await service.generateAndSaveFullWeekPlan(
                goals: goalSettings,
                preferredFoods: ["Chicken", "Rice", "Broccoli"],
                preferredCuisines: ["Italian"],
                preferredSnacks: ["Yogurt"],
                userID: "user1"
            )
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(mockRepo.batchSavedMealPlans.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
    }

    func testAccountSwitchDuringWeekGenerationDoesNotPersistAPlan() async {
        mockAI.mockResult = .failure(.apiError("use local fallback"))
        mockAI.responseDelayNanoseconds = 100_000_000
        let goalSettings = GoalSettings()
        goalSettings.calories = 2_000
        goalSettings.protein = 150
        goalSettings.carbs = 200
        goalSettings.fats = 70

        let task = Task {
            await service.generateAndSaveFullWeekPlan(
                goals: goalSettings,
                preferredFoods: ["Chicken", "Rice", "Broccoli"],
                preferredCuisines: ["Italian"],
                preferredSnacks: ["Yogurt"],
                userID: "user1"
            )
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        mockAuth.currentUserID = "user2"

        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(mockRepo.batchSavedMealPlans.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
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

    func testRapidGrocerySavesRemainOrderedAndLatestStateWins() async {
        mockRepo.grocerySaveDelayNanoseconds = 20_000_000
        let first = [GroceryListItem(name: "Apple", quantity: 1, unit: "item")]
        let second = [GroceryListItem(name: "Banana", quantity: 2, unit: "item")]

        service.saveGroceryList(first, for: "user1")
        service.saveGroceryList(second, for: "user1")

        let didSave = await service.waitForPendingGrocerySave(for: "user1")
        XCTAssertTrue(didSave)
        XCTAssertEqual(mockRepo.grocerySaveSnapshots.count, 2)
        XCTAssertEqual(mockRepo.grocerySaveSnapshots[0].first?.name, "Apple")
        XCTAssertEqual(mockRepo.grocerySaveSnapshots[1].first?.name, "Banana")
        XCTAssertEqual(mockRepo.savedGroceryLists.first?.name, "Banana")
    }

    func testSynchronizedGroceryListReportsReadFailureWithoutSavingAnEmptyList() async {
        mockRepo.groceryListError = APIError.apiError("offline")

        let result = await service.fetchSynchronizedGroceryListResult(for: "user1")

        guard case .failure = result else {
            return XCTFail("Expected the grocery read failure to reach the caller")
        }
        XCTAssertTrue(mockRepo.grocerySaveSnapshots.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
    }

    func testStaleGroceryRefreshAbortsWhenMealPlanReadFails() async {
        mockRepo.mockFetchGroceryListResult = [
            GroceryListItem(
                name: "Chicken",
                quantity: 1,
                unit: "lb",
                category: "Meat & Seafood",
                source: "mealPlan",
                sourcePlanStart: Date().addingTimeInterval(-8 * 86_400)
            )
        ]
        mockRepo.mealPlanError = APIError.apiError("offline")

        let result = await service.fetchSynchronizedGroceryListResult(for: "user1")

        guard case .failure = result else {
            return XCTFail("Expected the failed plan refresh to reach the caller")
        }
        XCTAssertTrue(mockRepo.grocerySaveSnapshots.isEmpty)
        XCTAssertTrue(mockRepo.savedGroceryLists.isEmpty)
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

    func testSynchronizedGroceryListReplacesStalePlanItemsAndPreservesManualItems() async throws {
        let calendar = Calendar.current
        let currentStart = try XCTUnwrap(
            DateComponents(calendar: calendar, year: 2026, month: 7, day: 13, hour: 12).date
        )
        let staleStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: currentStart))
        let currentPlan = MealPlanDay(
            id: "current-plan",
            date: currentStart,
            meals: [
                PlannedMeal(
                    mealType: "Dinner",
                    ingredients: ["2 bananas", "1 lb chicken breast"]
                )
            ]
        )
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        mockRepo.mockMealPlansByDateString[formatter.string(from: currentStart)] = currentPlan
        mockRepo.mockFetchGroceryListResult = [
            GroceryListItem(
                name: "Apples",
                quantity: 8,
                unit: "item",
                category: "Produce",
                source: "mealPlan",
                sourcePlanStart: staleStart
            ),
            GroceryListItem(
                name: "Coffee filters",
                quantity: 1,
                unit: "item",
                category: "Misc",
                source: "manual"
            )
        ]

        let synchronized = await service.fetchSynchronizedGroceryList(
            for: "user1",
            starting: currentStart
        )

        XCTAssertEqual(Set(synchronized.map(\.name)), ["Bananas", "Chicken Breast", "Coffee filters"])
        XCTAssertFalse(synchronized.contains { $0.name == "Apples" })
        XCTAssertEqual(synchronized.first(where: { $0.name == "Coffee filters" })?.source, "manual")
        XCTAssertTrue(
            synchronized
                .filter { $0.source == "mealPlan" }
                .allSatisfy { calendar.isDate($0.sourcePlanStart ?? .distantPast, inSameDayAs: currentStart) }
        )
        XCTAssertEqual(mockRepo.savedGroceryLists, synchronized)
    }
}
