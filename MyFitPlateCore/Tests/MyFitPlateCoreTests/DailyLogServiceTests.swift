import XCTest
@testable import MyFitPlateCore

private func diaryServiceDayKey(_ date: Date) -> String { DiaryDayContext.dayKey(for: date)! }

@MainActor
final class DailyLogServiceTests: XCTestCase {
    func testDayReviewRejectsFailedSaveThenRetriesAndUndoesWithoutTouchingFood() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        service.currentDailyLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "meal", name: "Meal", calories: 500)])])
        mockRepo.persistsDailyLogUpdates = true
        try await mockRepo.saveDailyLog(userID: "user", log: XCTUnwrap(service.currentDailyLog))
        mockRepo.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in
            service.setNutritionDayStatus(.complete, for: "user", date: date) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(rejected)
        XCTAssertNil(service.currentDailyLog?.nutritionDayStatus)
        mockRepo.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in
            service.setNutritionDayStatus(.complete, for: "user", date: date) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.currentDailyLog?.nutritionDayStatus, .complete)
        service.undoLastDiaryChange(for: "user")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(service.currentDailyLog?.nutritionDayStatus)
        XCTAssertEqual(service.currentDailyLog?.meals[0].foodItems.first?.id, "meal")
        let future = await withCheckedContinuation { continuation in
            service.setNutritionDayStatus(.complete, for: "user", date: date.addingTimeInterval(86_400)) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(future)
    }

    func testDayReviewCanonicalRaceKeepsNewFoodWithoutOfferingItsUndo() async throws {
        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400))
        let original = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "first", name: "Rice", calories: 200)])])
        mockRepo.persistsDailyLogUpdates = true
        try await mockRepo.saveDailyLog(userID: "user", log: original)
        let loaded: DailyLog = try await withCheckedThrowingContinuation { continuation in
            service.fetchLog(for: "user", date: date) { continuation.resume(with: $0) }
        }
        XCTAssertEqual(loaded.id, original.id)
        mockRepo.shouldDeferDailyLogUpdateCompletions = true
        let task = Task { @MainActor in
            await withCheckedContinuation { continuation in
                service.setNutritionDayStatus(.complete, for: "user", date: date, reviewedLog: original) { continuation.resume(returning: $0) }
            }
        }
        for _ in 0..<100 where mockRepo.deferredDailyLogUpdateCompletions.isEmpty { await Task.yield() }
        XCTAssertEqual(mockRepo.deferredDailyLogUpdateCompletions.count, 1)
        var concurrent = try XCTUnwrap(mockRepo.lastUpdatedLog)
        concurrent.meals[0].foodItems.append(FoodItem(id: "another-device", name: "Fruit", calories: 100))
        mockRepo.mockFetchLogResult = .success(concurrent)
        mockRepo.deferredDailyLogUpdateCompletions.removeFirst()(true)
        let confirmed = await task.value
        XCTAssertFalse(confirmed)
        XCTAssertFalse(service.canUndoDiaryChange, "Review Undo must never include another writer's food")
        XCTAssertEqual(service.currentDailyLog?.meals[0].foodItems.map(\.id), ["first", "another-device"])
        XCTAssertEqual(service.currentDailyLog.map(NutritionDayEvidence.status), .unknown)
    }

    func testMealDraftReplayAddsMissingEntriesOnlyAndDoesNotReplaceUndoOnNoOp() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        let original = FoodItem(id: "existing", name: "Already logged", calories: 50)
        let first = FoodItem(id: "draft-one", name: "Oats", calories: 200)
        let second = FoodItem(id: "draft-two", name: "Milk", calories: 100)
        service.currentDailyLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Breakfast", foodItems: [original, first])])
        let save: () async -> Bool = {
            await withCheckedContinuation { continuation in
                self.service.addMealGroupsToLog(for: "user", date: date,
                                               mealGroups: [(mealName: "Breakfast", foodItems: [first, second])],
                                               source: "meal_draft", deduplicateFoodIDs: true) {
                    continuation.resume(returning: $0)
                }
            }
        }
        let firstAccepted = await save()
        XCTAssertTrue(firstAccepted)
        let undoID = try XCTUnwrap(service.undoChangeID)
        XCTAssertEqual(service.undoID(forAddedFoods: ["draft-two"], userID: "user"), undoID)
        XCTAssertNil(service.undoID(forAddedFoods: ["draft-one", "draft-two"], userID: "user"))
        XCTAssertNil(service.undoID(forAddedFoods: ["draft-two"], userID: "different-account"))
        let replayAccepted = await save()
        XCTAssertTrue(replayAccepted)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), ["existing", "draft-one", "draft-two"])
        XCTAssertEqual(service.undoChangeID, undoID)
        service.undoLastDiaryChange(for: "user")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), ["existing", "draft-one"])
    }

    func testWorkoutSaveUsesCaptureDateAndRetryKeepsOneDiaryEntry() async throws {
        let captured = Calendar.current.startOfDay(for: Date())
        let historical = captured.addingTimeInterval(-86400 * 3)
        service.activelyViewedDate = historical
        service.currentDailyLog = DailyLog(id: diaryServiceDayKey(historical), date: historical, meals: [])
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(captured), date: captured, meals: []))
        let exercise = LoggedExercise(id: "session", name: "Strength", durationMinutes: 20, caloriesBurned: 80,
                                      date: captured, source: "routine", workoutID: "r", sessionID: "session")
        let accepted = await service.saveWorkoutExercise(for: "user", exercise: exercise)
        XCTAssertTrue(accepted)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.date, captured)
        XCTAssertEqual(service.currentDailyLog?.id, diaryServiceDayKey(historical))
        mockRepo.mockFetchLogResult = .success(try XCTUnwrap(mockRepo.lastUpdatedLog))
        let retried = await service.saveWorkoutExercise(for: "user", exercise: exercise)
        XCTAssertTrue(retried)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.exercises?.map(\.id), ["session"])
    }

    func testMovingFoodPreservesNutritionAndProvidesUndo() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        let food = FoodItem(id: "food", name: "Oats", calories: 200, protein: 8, servingSize: "1 cup", calcium: 100)
        service.currentDailyLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Breakfast", foodItems: [food])])
        service.moveFood(for: "user", foodID: "food", date: date, to: "Lunch")
        try await Task.sleep(nanoseconds: 100_000_000)
        let moved = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertTrue(moved.meals.first { $0.name == "Breakfast" }?.foodItems.isEmpty == true)
        XCTAssertEqual(moved.meals.first { $0.name == "Lunch" }?.foodItems.first?.calcium, 100)
        XCTAssertEqual(moved.totalCalories(), 200)
        XCTAssertTrue(service.canUndoDiaryChange)
        service.undoLastDiaryChange(for: "user")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.meals.first { $0.name == "Breakfast" }?.foodItems.map(\.id), ["food"])
        XCTAssertEqual(mockRepo.lastUpdatedLog?.totalCalories(), 200)
    }
    
    var service: DailyLogService!
    var mockRepo: MockNutritionRepository!
    var mockAuth: MockAuthService!
    var goalSettings: GoalSettings!
    var bannerService: BannerService!
    var mockCrashManager: MockCrashManager!
    var mockAnalyticsManager: MockAnalyticsManager!
    private var undoDirectory: URL!
    private var undoStore: EditorDraftStore!
    
    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "user"
        DIContainer.shared.authService = mockAuth
        mockCrashManager = MockCrashManager()
        mockAnalyticsManager = MockAnalyticsManager()
        DIContainer.shared.crashManager = mockCrashManager
        DIContainer.shared.analyticsManager = mockAnalyticsManager
        
        undoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("daily-log-service-tests-\(UUID())")
        undoStore = EditorDraftStore(directory: undoDirectory)
        service = DailyLogService(undoStore: undoStore)
        service.activateAccount("user")
        goalSettings = GoalSettings()
        bannerService = BannerService()
        
        // Pass a dummy AchievementService
        let achievementService = AchievementService()
        service.setupDependencies(goalSettings: goalSettings, bannerService: bannerService, achievementService: achievementService)
    }

    override func tearDown() {
        service?.activateAccount(nil)
        service = nil
        undoStore = nil
        if let undoDirectory { try? FileManager.default.removeItem(at: undoDirectory) }
        undoDirectory = nil
        super.tearDown()
    }

    func testFetchLogInternalAsyncReturnsEmptyLogWhenNoCurrent() async throws {
        let date = Date()
        service.activelyViewedDate = date.addingTimeInterval(86400) // Different day
        
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        
        let expectation = XCTestExpectation(description: "Fetch complete")
        service.fetchLog(for: "user", date: date) { result in
            switch result {
            case .success(let log):
                XCTAssertEqual(log.id, diaryServiceDayKey(date))
                expectation.fulfill()
            case .failure:
                XCTFail("Expected the captured diary day to load successfully")
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testAddFoodToCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let initialLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])
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

    func testRapidFoodMutationsAreSerializedWithoutLosingItems() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))

        service.addFoodToLog(
            for: "user",
            date: date,
            mealName: "Breakfast",
            foodItem: FoodItem(id: "first", name: "Eggs", calories: 140)
        )
        service.addFoodToLog(
            for: "user",
            date: date,
            mealName: "Breakfast",
            foodItem: FoodItem(id: "second", name: "Toast", calories: 120)
        )

        try await Task.sleep(nanoseconds: 250_000_000)

        let foods = try XCTUnwrap(mockRepo.lastUpdatedLog).meals.flatMap(\.foodItems)
        XCTAssertEqual(foods.map(\.id), ["first", "second"])
    }

    func testUpdateFoodInCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
        let meal = Meal(id: UUID(), name: "Breakfast", foodItems: [food])
        let initialLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [meal])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        var updatedFood = food
        updatedFood.calories = 100
        service.updateFoodInCurrentLog(for: "user", updatedFoodItem: updatedFood)
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        XCTAssertEqual(updatedLog.meals[0].foodItems[0].calories, 100)
    }

    /// Regression: editing servings must apply to the in-memory log the UI is showing, not a
    /// fresh Firestore fetch that can lag a very recent write. Here the fetch is deliberately
    /// stale (missing the chicken); the edit must still land on the full displayed log.
    func testUpdateAppliesToInMemoryLogNotStaleFetch() async throws {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date

        let rice = FoodItem(id: "rice", name: "Rice", calories: 300, protein: 6, carbs: 70, fats: 1)
        let chicken = FoodItem(id: "chicken", name: "Chicken", calories: 325, protein: 63, carbs: 0, fats: 8)
        let displayedLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(id: UUID(), name: "Dinner", foodItems: [rice, chicken])])
        service.publishCurrentDailyLog(displayedLog)

        // A stale fetch that dropped the chicken (a write still in flight).
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(id: UUID(), name: "Dinner", foodItems: [rice])]))

        var rice3 = rice   // bump 2 → 3 servings
        rice3.calories = 450; rice3.carbs = 105; rice3.protein = 9
        service.updateFoodInCurrentLog(for: "user", updatedFoodItem: rice3)

        try? await Task.sleep(nanoseconds: 150_000_000)

        // 450 (rice) + 325 (chicken) — the edit landed and no item was lost to the stale fetch.
        let published = try XCTUnwrap(service.currentDailyLog)
        XCTAssertEqual(published.totalCalories(), 775, accuracy: 0.001)
        let persisted = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(persisted.totalCalories(), 775, accuracy: 0.001)
        XCTAssertTrue(published.meals.flatMap { $0.foodItems.map(\.name) }.contains("Chicken"))
    }

    func testDeleteFoodFromCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
        let meal = Meal(id: UUID(), name: "Breakfast", foodItems: [food])
        let initialLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [meal])
        mockRepo.mockFetchLogResult = .success(initialLog)
        
        service.deleteFoodFromCurrentLog(for: "user", foodItemID: "f1")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
        let updatedLog = mockRepo.lastUpdatedLog!
        let allFoods = updatedLog.meals.flatMap { $0.foodItems }
        XCTAssertTrue(allFoods.isEmpty)
        XCTAssertTrue(updatedLog.meals.isEmpty)
    }

    func testCapturedWaterUsesCaptureDayWhileHistoricalDiaryStaysOpen() async {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        service.activelyViewedDate = yesterday
        service.currentDailyLog = DailyLog(id: diaryServiceDayKey(yesterday), date: yesterday, meals: [])
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(today), date: today, meals: []))
        let accepted = expectation(description: "durable acceptance")
        service.addWaterToLog(for: "user", amount: 8, goalOunces: 64, capturedAt: today, entryID: "water-receipt") { success in
            XCTAssertTrue(success)
            accepted.fulfill()
        }
        await fulfillment(of: [accepted], timeout: 2)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.date, today)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.pendingMutationID, "water-receipt")
        XCTAssertEqual(service.activelyViewedDate, yesterday)
    }

    func testUndoRemovesJustTheRecentlyAddedFood() async {
        let today = Calendar.current.startOfDay(for: Date())
        let existing = FoodItem(id: "existing", name: "Existing", calories: 100, protein: 10, carbs: 10, fats: 2)
        let added = FoodItem(id: "added", name: "Added", calories: 100, protein: 10, carbs: 10, fats: 2)
        let original = DailyLog(id: diaryServiceDayKey(today), date: today, meals: [Meal(name: "Lunch", foodItems: [existing])])
        service.currentDailyLog = original
        service.activelyViewedDate = today
        mockRepo.mockFetchLogResult = .success(original)
        service.addFoodToLog(for: "user", date: today, mealName: "Lunch", foodItem: added)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(service.canUndoDiaryChange)
        service.undoLastDiaryChange(for: "user")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(mockRepo.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), ["existing"])
        XCTAssertFalse(service.canUndoDiaryChange)
    }

    func testAddWaterToCurrentLog() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let initialLog = DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])
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
        
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(sourceDate), date: sourceDate, meals: []))
        
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
                XCTFail("Expected recommended foods to load successfully")
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testRecommendedFoodsCompletingAfterAccountSwitchAreRejected() async {
        mockRepo.shouldDeferRecommendedFoodCallbacks = true
        let completion = expectation(description: "Stale recommendation is rejected")

        service.fetchRecommendedFoods(for: "user", mealName: "Breakfast") { result in
            if case .success = result {
                XCTFail("The previous account's recommendations must not be delivered.")
            }
            completion.fulfill()
        }

        mockAuth.currentUserID = "user-2"
        service.activateAccount("user-2")
        mockRepo.completeDeferredRecommendedFoodFetches(with: .success([
            FoodItem(id: "old", name: "Old account oats", calories: 150)
        ]))

        await fulfillment(of: [completion], timeout: 1.0)
    }

    func testAddFoodToPastDateDoesNotReplaceCurrentDailyLog() async throws {
        let viewedDate = Calendar.current.startOfDay(for: Date())
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: viewedDate)!
        service.activelyViewedDate = viewedDate
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(pastDate), date: pastDate, meals: []))

        service.addFoodToLog(
            for: "user",
            date: pastDate,
            mealName: "Dinner",
            foodItem: FoodItem(id: "f1", name: "Salmon", calories: 350),
            source: "recipe"
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let updatedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(updatedLog.id, diaryServiceDayKey(pastDate))
        XCTAssertEqual(updatedLog.meals.map(\.name), ["Dinner"])
        XCTAssertNil(service.currentDailyLog)
    }

    func testAddFoodFetchFailureDoesNotUpdateLog() async {
        mockRepo.mockFetchLogResult = .failure(URLError(.notConnectedToInternet))

        service.addFoodToCurrentLog(for: "user", foodItem: FoodItem(id: "f1", name: "Apple", calories: 95))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertEqual(
            mockCrashManager.recordedErrors.first?.userInfo["release_health_operation"] as? String,
            "daily_log_mutation"
        )
        XCTAssertEqual(mockCrashManager.recordedErrors.first?.userInfo["stage"] as? String, "prepare")
    }

    func testRejectedDailyLogWriteRecordsOperationTaggedNonFatal() async {
        let date = Calendar.current.startOfDay(for: Date())
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        mockRepo.updateLogSuccess = false

        service.addFoodToLog(
            for: "user",
            date: date,
            mealName: "Lunch",
            foodItem: FoodItem(id: "f1", name: "Apple", calories: 95),
            source: "quick_log"
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockCrashManager.recordedErrors.count, 1)
        XCTAssertEqual(
            mockCrashManager.recordedErrors.first?.userInfo["release_health_area"] as? String,
            "nutrition"
        )
        XCTAssertEqual(
            mockCrashManager.recordedErrors.first?.userInfo["release_health_operation"] as? String,
            "daily_log_mutation"
        )
        XCTAssertEqual(mockCrashManager.recordedErrors.first?.userInfo["stage"] as? String, "persist")
        XCTAssertEqual(
            mockAnalyticsManager.loggedEvents.first?.name,
            ProductAnalytics.Event.nonfatalErrorRecorded.rawValue
        )
    }

    func testUpdateFoodMissingItemSkipsUpdate() async {
        let date = Calendar.current.startOfDay(for: Date())
        service.activelyViewedDate = date
        let existing = FoodItem(id: "existing", name: "Apple", calories: 95)
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Breakfast", foodItems: [existing])]))

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
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))

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
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [Meal(name: "Breakfast", foodItems: [existing])]))

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
        service.publishCurrentDailyLog(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))

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
        mockRepo.mockFetchDailyHistoryResult = .success([DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])])

        let success = await service.fetchDailyHistory(for: "user")
        if case .success(let logs) = success {
            XCTAssertEqual(logs.map(\.id), [diaryServiceDayKey(date)])
        } else {
            XCTFail("expected history success")
        }

        mockRepo.mockFetchDailyHistoryResult = .failure(URLError(.timedOut))
        let failure = await service.fetchDailyHistory(for: "user")
        if case .failure = failure {} else {
            XCTFail("expected history failure")
        }
    }

    func testDailyHistoryCompletingAfterAccountSwitchIsRejected() async {
        let date = Date()
        mockRepo.fetchDailyHistoryDelayNanoseconds = 75_000_000
        mockRepo.mockFetchDailyHistoryResult = .success([
            DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])
        ])

        let resultTask = Task {
            await service.fetchDailyHistory(for: "user", startDate: nil, endDate: nil)
        }
        await Task.yield()
        mockAuth.currentUserID = "user-2"
        service.activateAccount("user-2")

        let result = await resultTask.value
        if case .success = result {
            XCTFail("History from the previous account must not be delivered.")
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
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(sourceDate), date: sourceDate, meals: [meal]))
        
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
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        
        let food = FoodItem(id: "f1", name: "Apple", calories: 95)
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

    func testRepeatYesterdayMealSuccess() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86400)
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)
        let food1 = FoodItem(id: "1", name: "Eggs", calories: 150)
        let sourceLog = DailyLog(id: diaryServiceDayKey(yesterdayStart), date: yesterdayStart, meals: [Meal(name: "Breakfast", foodItems: [food1])])
        mockRepo.mockFetchLogResult = .success(sourceLog)

        let exp = XCTestExpectation(description: "Repeat meal")
        service.repeatYesterdayMeal(for: "user", mealName: "Breakfast", targetDate: Date()) { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertNotNil(mockRepo.lastUpdatedLog)
    }

    func testRepeatYesterdayMealEmpty() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date().addingTimeInterval(-86400)
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)
        let sourceLog = DailyLog(id: diaryServiceDayKey(yesterdayStart), date: yesterdayStart, meals: [Meal(name: "Lunch", foodItems: [])])
        mockRepo.mockFetchLogResult = .success(sourceLog)

        let exp = XCTestExpectation(description: "Repeat meal empty")
        service.repeatYesterdayMeal(for: "user", mealName: "Breakfast", targetDate: Date()) { success in
            XCTAssertFalse(success)
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testFoodLoggedNotificationExposesTypedPayload() throws {
        let food = FoodItem(id: "persisted-food", name: "Greek yogurt", calories: 140)
        let notification = Notification(
            name: .foodItemLogged,
            userInfo: [
                DailyLogNotificationUserInfoKey.foodItem: food,
                DailyLogNotificationUserInfoKey.userID: "user-1"
            ]
        )
        let payload = try XCTUnwrap(DailyLogNotifications.foodLoggedPayload(from: notification))
        XCTAssertEqual(payload.foodItem, food)
        XCTAssertEqual(payload.userID, "user-1")
    }

    func testFoodLoggedPayloadRejectsWrongNotificationAndEmptyAccount() {
        XCTAssertNil(DailyLogNotifications.foodLoggedPayload(from: Notification(name: .didUpdateExerciseLog)))
        XCTAssertNil(DailyLogNotifications.foodLoggedPayload(from: Notification(
            name: .foodItemLogged,
            userInfo: [
                "foodItem": FoodItem(id: "food", name: "Oats", calories: 150),
                "userID": ""
            ]
        )))
    }

    func testTwoFetchesWhileInitialListenerIsPendingBothComplete() async {
        let date = Calendar.current.startOfDay(for: Date())
        mockRepo.shouldDeferLogSnapshotCallbacks = true

        let first = expectation(description: "First fetch completes")
        let second = expectation(description: "Second fetch completes")
        service.fetchLog(for: "user", date: date) { result in
            XCTAssertEqual(try? result.get().id, diaryServiceDayKey(date))
            first.fulfill()
        }
        service.fetchLog(for: "user", date: date) { result in
            XCTAssertEqual(try? result.get().id, diaryServiceDayKey(date))
            second.fulfill()
        }

        mockRepo.emitLogSnapshot(.success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])), for: "user")

        await fulfillment(of: [first, second], timeout: 1.0)
    }

    func testAccountSwitchClearsLogAndIgnoresLatePreviousAccountListener() async {
        let date = Calendar.current.startOfDay(for: Date())
        mockRepo.shouldDeferLogSnapshotCallbacks = true

        service.fetchLog(for: "user", date: date) { _ in }
        mockAuth.currentUserID = "user-2"
        service.activateAccount("user-2")
        service.fetchLog(for: "user-2", date: date) { _ in }

        mockRepo.emitLogSnapshot(.success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])), for: "user")
        await Task.yield()
        XCTAssertNil(service.currentDailyLog)

        mockRepo.emitLogSnapshot(.success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: [])), for: "user-2")
        await Task.yield()
        XCTAssertEqual(service.currentDailyLog?.id, diaryServiceDayKey(date))
    }

    func testMutationCompletingAfterAccountSwitchCannotPublishOldAccountState() async {
        let date = Calendar.current.startOfDay(for: Date())
        mockRepo.mockFetchLogResult = .success(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        mockRepo.shouldDeferDailyLogUpdateCompletions = true

        service.addFoodToLog(
            for: "user",
            date: date,
            mealName: "Breakfast",
            foodItem: FoodItem(id: "food", name: "Oats", calories: 150)
        )
        await Task.yield()
        XCTAssertEqual(mockRepo.deferredDailyLogUpdateCompletions.count, 1)

        mockAuth.currentUserID = "user-2"
        service.activateAccount("user-2")
        mockRepo.completeDeferredDailyLogUpdates(success: true)
        await Task.yield()

        XCTAssertNil(service.currentDailyLog)
        XCTAssertNil(bannerService.currentBanner)
    }

    func testSignOutClearsAccountScopedDailyLogAndSuggestions() {
        let date = Date()
        service.publishCurrentDailyLog(DailyLog(id: diaryServiceDayKey(date), date: date, meals: []))
        service.smartSuggestions = [FoodItem(id: "food", name: "Oats", calories: 150)]

        mockAuth.currentUserID = nil
        service.activateAccount(nil)

        XCTAssertNil(service.currentDailyLog)
        XCTAssertTrue(service.smartSuggestions.isEmpty)
    }
}
