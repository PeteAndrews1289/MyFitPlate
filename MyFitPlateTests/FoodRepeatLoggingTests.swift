import Combine
import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class FoodRepeatLoggingTests: XCTestCase {
    func testImportStopsOnRejectedSaveAndReportsSuccessOnlyAfterRetry() async throws {
        let importer = MFPImportViewModel()
        let goals = GoalSettings(healthKitManager: MockHealthKitManager())
        let file = try importFixture()
        let preview = expectation(description: "import preview")
        importer.$stage.filter { $0 == .preview }.prefix(1).sink { _ in preview.fulfill() }.store(in: &subscriptions)
        importer.handlePicked(urls: [file], dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [preview], timeout: 3)
        repository.updateLogSuccess = false
        let failed = expectation(description: "import save rejected")
        importer.$stage.filter { if case .failed = $0 { return true }; return false }.prefix(1)
            .sink { _ in failed.fulfill() }.store(in: &subscriptions)
        importer.runImport(dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [failed], timeout: 3)
        if case .failed(let message) = importer.stage { XCTAssertTrue(message.contains("0 saved records")) }
        repository.updateLogSuccess = true
        let finished = expectation(description: "import accepted")
        importer.$stage.filter { if case .finished = $0 { return true }; return false }.prefix(1)
            .sink { _ in finished.fulfill() }.store(in: &subscriptions)
        importer.runImport(dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(importer.stage, .finished(days: 1, entries: 1, weighIns: 0, conflicts: 0))
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
    }

    func testImportDoesNotAssumeEmptyDiaryWhenConflictCheckFails() async throws {
        let importer = MFPImportViewModel()
        let goals = GoalSettings(healthKitManager: MockHealthKitManager())
        repository.mockFetchDailyHistoryResult = .failure(NSError(domain: "HistoryTest", code: 1))
        let failed = expectation(description: "conflict check rejected")
        importer.$stage.filter { if case .failed = $0 { return true }; return false }.prefix(1)
            .sink { _ in failed.fulfill() }.store(in: &subscriptions)
        importer.handlePicked(urls: [try importFixture()], dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertTrue(repository.savedDailyLogs.isEmpty)
        if case .failed(let message) = importer.stage { XCTAssertTrue(message.contains("existing diary")) }
    }

    func testImportPreviewCannotBeConfirmedByAnotherAccountAndReselectionRechecksItsConflicts() async throws {
        let importer = MFPImportViewModel()
        let goals = GoalSettings(healthKitManager: MockHealthKitManager())
        let file = try importFixture()
        let csv = try String(contentsOf: file)
        try (csv + "\n2025-11-04,Lunch,Apple,90,0,24,0\n").write(to: file, atomically: true, encoding: .utf8)
        let existingDay = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2025, month: 11, day: 3)))
        repository.mockFetchDailyHistoryResultsByUserID = [
            "repeat-test-user": .success([DailyLog(date: existingDay, meals: [
                Meal(name: "Breakfast", foodItems: [FoodItem(id: "existing-a", name: "Existing", calories: 100)])
            ])]),
            "import-target-b": .success([])
        ]
        let firstPreview = expectation(description: "account A import preview")
        importer.$stage.filter { $0 == .preview }.prefix(1).sink { _ in firstPreview.fulfill() }.store(in: &subscriptions)
        importer.handlePicked(urls: [file], dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [firstPreview], timeout: 3)
        XCTAssertEqual(importer.conflictCount, 1)
        let reviewedFoodIDs = importer.diaryLogs.flatMap(\.meals).flatMap(\.foodItems).map(\.id)

        auth.currentUserID = "import-target-b"
        service.activateAccount("import-target-b")
        importer.runImport(dailyLogService: service, goalSettings: goals)
        guard case .failed(let message) = importer.stage else { return XCTFail("A switched account must not confirm the prior preview") }
        XCTAssertTrue(message.contains("account changed"))
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertEqual(importer.diaryLogs.flatMap(\.meals).flatMap(\.foodItems).map(\.id), reviewedFoodIDs,
                       "The rejected confirmation must keep the reviewed source intact")

        let secondPreview = expectation(description: "account B rechecked preview")
        importer.$stage.filter { $0 == .preview }.prefix(1).sink { _ in secondPreview.fulfill() }.store(in: &subscriptions)
        importer.handlePicked(urls: [file], dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [secondPreview], timeout: 3)
        XCTAssertEqual(importer.conflictCount, 0, "Account B must not inherit A's conflict decisions")
        let finished = expectation(description: "account B accepted import")
        importer.$stage.filter { if case .finished = $0 { return true }; return false }.prefix(1)
            .sink { _ in finished.fulfill() }.store(in: &subscriptions)
        importer.runImport(dailyLogService: service, goalSettings: goals)
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(importer.stage, .finished(days: 2, entries: 2, weighIns: 0, conflicts: 0))
        XCTAssertEqual(repository.dailyLogUpdateUserIDs, ["import-target-b", "import-target-b"])
    }

    private func importFixture() throws -> URL {
        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        let file = draftDirectory.appendingPathComponent("diary.csv")
        try """
        Date,Meal,Food,Calories,Protein (g),Carbohydrates (g),Fat (g)
        2025-11-03,Breakfast,Oatmeal,300,10,54,5
        """.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func testMaiaRecipeRetryWaitsForAcceptanceAndKeepsOriginalDate() async {
        let maia = AIChatbotViewModel(actionStore: EditorDraftStore(directory: draftDirectory))
        maia.dailyLogService = service
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        service.activelyViewedDate = date
        let recipe = """
        Yogurt bowl
        ---Nutritional Breakdown---
        Calories: 220
        Protein: 20g
        Carbs: 28g
        Fats: 3g
        Calcium: 200
        """
        repository.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in
            maia.logRecipe(recipeText: recipe) { continuation.resume(returning: $0) }
            XCTAssertTrue(maia.isSavingAction)
            XCTAssertFalse(maia.showAlert)
        }
        XCTAssertFalse(rejected)
        XCTAssertFalse(maia.isSavingAction)
        XCTAssertTrue(maia.alertMessage.contains("Couldn't save"))
        repository.updateLogSuccess = true
        service.activelyViewedDate = Date()
        maia.showAlert = false
        let accepted = await withCheckedContinuation { continuation in
            maia.logRecipe(recipeText: recipe) { continuation.resume(returning: $0) }
            maia.logRecipe(recipeText: recipe) { XCTAssertFalse($0, "Rapid taps must not enqueue another entry") }
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.date, date)
        let foods = repository.lastUpdatedLog?.meals.flatMap(\.foodItems) ?? []
        XCTAssertEqual(foods.count, 1)
        XCTAssertEqual(foods.first?.calcium, 200)
        XCTAssertEqual(foods.first?.sourceMetadata?.sourceType, .aiChat)
    }

    func testMaiaWaterAndWorkoutActionsReportRejectedWrites() async {
        let maia = AIChatbotViewModel(actionStore: EditorDraftStore(directory: draftDirectory))
        maia.dailyLogService = service
        for action in [MaiaAction.logWater(amountOunces: 16),
                       MaiaAction.logWorkout(exerciseName: "Walk", durationMinutes: 20, caloriesBurned: 100)] {
            repository.updateLogSuccess = false
            let rejected = await withCheckedContinuation { continuation in
                maia.handleMaiaAction(action) { continuation.resume(returning: $0) }
            }
            XCTAssertFalse(rejected)
            XCTAssertFalse(maia.isSavingAction)
            XCTAssertTrue(maia.alertMessage.contains("Couldn't save"))
            repository.updateLogSuccess = true
            let accepted = await withCheckedContinuation { continuation in
                maia.handleMaiaAction(action) { continuation.resume(returning: $0) }
            }
            XCTAssertTrue(accepted)
            XCTAssertFalse(maia.alertMessage.contains("Couldn't save"))
        }
    }

    func testMaiaActionWithUnavailableServiceCompletesAsFailure() async {
        let maia = AIChatbotViewModel(actionStore: EditorDraftStore(directory: draftDirectory))
        let accepted = await withCheckedContinuation { continuation in
            maia.handleMaiaAction(.logWater(amountOunces: 16)) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(accepted)
        XCTAssertFalse(maia.isSavingAction)
    }

    func testMaiaMealPlanActionOpensReviewFlowWithoutSaving() {
        let maia = AIChatbotViewModel(actionStore: EditorDraftStore(directory: draftDirectory))
        maia.mealPlannerService = MealPlannerService(recipeService: RecipeService())
        maia.goalSettings = GoalSettings(healthKitManager: MockHealthKitManager())
        var completionCalled = false
        maia.handleMaiaAction(.generateMealPlan) { saved in
            completionCalled = true
            XCTAssertFalse(saved, "Opening the builder must not claim a plan has been saved")
        }
        XCTAssertTrue(completionCalled)
        XCTAssertTrue(maia.showingMealPlanBuilder)
        XCTAssertFalse(maia.isSavingAction)
        XCTAssertFalse(maia.showAlert)
        XCTAssertTrue(repository.batchSavedMealPlans.isEmpty)
    }

    func testMealDraftRestoresAndRetriesOriginalDestinationWithoutDuplicates() async throws {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        service.activelyViewedDate = date
        model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "oats", name: "Oats", calories: 200, calcium: 100))
        model.quickLog(food: FoodItem(id: "milk", name: "Milk", calories: 100))
        XCTAssertEqual(model.mealDraft?.entries.count, 2)
        model.updateMealDraft { $0.entries[0].multiplier = 1.5 }
        repository.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in
            model.logMealDraft { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(rejected)
        let submitted = try XCTUnwrap(model.mealDraft)
        XCTAssertTrue(submitted.isSubmitted)
        service.activelyViewedDate = Date()
        model = FoodSearchViewModel(selectedMeal: "Dinner", draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData()
        XCTAssertEqual(model.mealDraft?.id, submitted.id)
        XCTAssertEqual(model.mealDraft?.calories, 400)
        XCTAssertEqual(model.selectedMeal, "Breakfast", "Search must display the restored draft's actual destination")
        model.quickLog(food: FoodItem(id: "extra", name: "Unexpected food", calories: 500))
        XCTAssertEqual(model.mealDraft?.entries.count, 2, "A submitted payload stays frozen until its save is resolved")
        repository.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in
            model.logMealDraft { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(accepted)
        XCTAssertNil(model.mealDraft)
        XCTAssertEqual(repository.lastUpdatedLog?.date, date)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Breakfast")
        XCTAssertEqual(repository.lastUpdatedLog?.totalCalories(), 400)
        // Simulate termination after diary acceptance but before draft cleanup.
        repository.mockFetchLogResult = .success(try XCTUnwrap(repository.lastUpdatedLog))
        try EditorDraftStore(directory: draftDirectory).save(submitted, userID: "repeat-test-user", scope: "food-logging-meal")
        model = FoodSearchViewModel(draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData()
        let replayed = await withCheckedContinuation { continuation in
            model.logMealDraft { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(replayed)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 2)
        XCTAssertFalse(model.canUndoQuickLog, "Replaying an accepted meal must not expose an unrelated undo")
    }

    func testCapturedPhotoBatchStaysWithOriginalDraftAndIsIdempotentAcrossRelaunch() throws {
        let owner = "repeat-test-user"
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())))
        service.activelyViewedDate = yesterday
        model.isBuildingMeal = true
        let draft = try XCTUnwrap(model.draftForCapture())
        let photo = [FoodItem(id: "review-one", name: "Rice", calories: 200),
                     FoodItem(id: "review-two", name: "Broccoli", calories: 30)]
        service.activelyViewedDate = Date()
        XCTAssertFalse(model.selectReviewedPhotoFoods(photo, owner: "other-user", draftID: draft.id))
        XCTAssertFalse(model.selectReviewedPhotoFoods(photo, owner: owner, draftID: UUID()))
        XCTAssertTrue(model.selectReviewedPhotoFoods(photo, owner: owner, draftID: draft.id))
        let entryIDs = try XCTUnwrap(model.mealDraft?.entries.map(\.id))
        model = FoodSearchViewModel(selectedMeal: "Dinner", draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData()
        XCTAssertTrue(model.selectReviewedPhotoFoods(photo, owner: owner, draftID: draft.id))
        XCTAssertEqual(model.mealDraft?.entries.map(\.id), entryIDs)
        XCTAssertEqual(model.mealDraft?.date, yesterday)
        XCTAssertEqual(model.mealDraft?.mealName, "Breakfast")
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
    }

    func testMealDraftCannotCrossAccountsAndRemovingAnEntryPersists() throws {
        model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "oats", name: "Oats", calories: 200))
        model.quickLog(food: FoodItem(id: "milk", name: "Milk", calories: 100))
        model.updateMealDraft { $0.entries.removeFirst() }
        let saved = try XCTUnwrap(EditorDraftStore(directory: draftDirectory).load(FoodLoggingDraft.self, userID: "repeat-test-user", scope: "food-logging-meal"))
        XCTAssertEqual(saved.value.entries.map(\.sourceID), ["milk"])
        auth.currentUserID = "another-account"
        model.fetchData()
        XCTAssertNil(model.mealDraft)
        auth.currentUserID = "repeat-test-user"
        model.fetchData()
        XCTAssertEqual(model.mealDraft?.entries.map(\.sourceID), ["milk"])
        XCTAssertTrue(model.discardMealDraft())
        XCTAssertNil(try EditorDraftStore(directory: draftDirectory).load(FoodLoggingDraft.self, userID: "repeat-test-user", scope: "food-logging-meal"))
    }

    func testMealDraftDestinationStaysInSyncAcrossReviewModeChangesAndRelaunch() throws {
        model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "oats", name: "Oats", calories: 200))
        let originalDate = try XCTUnwrap(model.mealDraft?.date)
        XCTAssertTrue(model.updateMealDraft { $0.mealName = "Lunch" })
        XCTAssertEqual(model.selectedMeal, "Lunch")

        model.isBuildingMeal = false
        model.selectedMeal = "Dinner"
        XCTAssertEqual(model.mealDraft?.mealName, "Lunch", "Quick logging cannot redirect an unfinished meal")
        model.isBuildingMeal = true
        XCTAssertEqual(model.selectedMeal, "Lunch")

        model = FoodSearchViewModel(selectedMeal: "Snacks", draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData()
        XCTAssertTrue(model.isBuildingMeal)
        XCTAssertEqual(model.selectedMeal, "Lunch")
        XCTAssertEqual(model.mealDraft?.mealName, "Lunch")
        XCTAssertEqual(model.mealDraft?.date, originalDate)
        XCTAssertEqual(model.mealDraft?.entries.map(\.sourceID), ["oats"])
    }

    func testMealDraftWithInvalidMemberCannotLogOnlyTheOtherFoods() async {
        model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "oats", name: "Oats", calories: 200))
        model.quickLog(food: FoodItem(id: "milk", name: "Milk", calories: 100))
        XCTAssertTrue(model.updateMealDraft { $0.entries[1].multiplier = 0 })
        let accepted = await withCheckedContinuation { continuation in
            model.logMealDraft { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(accepted)
        XCTAssertNil(repository.lastUpdatedLog)
        XCTAssertEqual(model.mealDraft?.entries.count, 2)
        XCTAssertFalse(model.mealDraft?.isSubmitted == true)
    }

    func testDurableHydrationPreviewRestoresSameEntryAndDestination() throws {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        var draft = FoodLoggingDraft(date: date, mealName: "Lunch")
        var entry = FoodLoggingDraft.Entry(food: FoodItem(id: "local-oats", name: "Oats", calories: 200))
        entry.hydrationPending = true
        draft.entries = [entry]
        try EditorDraftStore(directory: draftDirectory).save(draft, userID: "repeat-test-user", scope: "food-logging-meal")
        let homeDate = service.activelyViewedDate
        model = FoodSearchViewModel(selectedMeal: "Dinner", draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData() // A local snapshot finishes hydration without a network dependency.
        XCTAssertEqual(model.mealDraft?.entries.first?.id, entry.id)
        XCTAssertEqual(model.mealDraft?.entries.count, 1)
        XCTAssertEqual(model.mealDraft?.hasPendingHydration, false)
        XCTAssertEqual(model.mealDraft?.isReadyToSubmit, true)
        XCTAssertEqual(model.mealDraft?.date, date)
        XCTAssertEqual(model.selectedMeal, "Lunch")
        XCTAssertEqual(service.activelyViewedDate, homeDate)
    }

    func testUnreadableMealDraftCannotBeOverwrittenOrDiscardedByAnAutomaticNewSelection() throws {
        model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "oats", name: "Oats", calories: 200))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: draftDirectory, includingPropertiesForKeys: nil))
        let file = try XCTUnwrap(files.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
        let originalBytes = Data("valuable unreadable meal checkpoint".utf8)
        try originalBytes.write(to: file)
        model = FoodSearchViewModel(draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service); model.fetchData(); model.isBuildingMeal = true
        model.quickLog(food: FoodItem(id: "new", name: "New selection", calories: 100))
        XCTAssertNil(model.mealDraft)
        XCTAssertFalse(model.discardMealDraft())
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
    }

    func testTypingClearsPreviousResultsBeforeDebouncedSearch() {
        model.searchResults = [FoodItem(id: "old", name: "Old result", calories: 10)]
        model.supplementResults = [FoodItem(id: "old-label", name: "Old supplement", calories: 0)]
        model.searchText = "Chicken"
        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.supplementResults.isEmpty)
        XCTAssertEqual(model.activeSearchQuery, "Chicken")
        XCTAssertTrue(model.isLoading)
        model.searchText = ""
        XCTAssertFalse(model.isLoading)
    }

    func testRecentQueriesAreAccountScopedAndCanBeCleared() {
        let suite = "search-history-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let search = FoodSearchViewModel(defaults: defaults)
        search.setup(dailyLogService: service)
        search.fetchData()
        search.searchText = "Greek yogurt"
        search.submitSearch()
        search.searchText = "greek yogurt"
        search.submitSearch()
        XCTAssertEqual(search.recentSearches, ["greek yogurt"])
        auth.currentUserID = "different-account"
        search.fetchData()
        XCTAssertTrue(search.recentSearches.isEmpty)
        auth.currentUserID = "repeat-test-user"
        search.fetchData()
        XCTAssertEqual(search.recentSearches, ["greek yogurt"])
        search.clearRecentSearches()
        XCTAssertTrue(search.recentSearches.isEmpty)
    }

    func testFailedQuickLogRetryUsesOriginalDestination() async {
        let originalDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        service.activelyViewedDate = originalDate
        repository.updateLogSuccess = false
        let failed = expectation(description: "failed")
        model.$lastLogMessage.compactMap { $0 }.prefix(1).sink { _ in failed.fulfill() }.store(in: &subscriptions)
        model.quickLog(food: FoodItem(id: "food", name: "Oats", calories: 200))
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertTrue(model.canRetryLog)
        repository.updateLogSuccess = true
        service.activelyViewedDate = Date()
        model.selectedMeal = "Dinner"
        let saved = expectation(description: "retry saved")
        model.$lastLogMessage.dropFirst().compactMap { $0 }.prefix(1).sink { _ in saved.fulfill() }.store(in: &subscriptions)
        model.retryQuickLog()
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(repository.lastUpdatedLog?.date, originalDate)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Breakfast")
        XCTAssertTrue(model.lastLogSucceeded)
    }

    func testSearchUndoCannotReverseAnUnrelatedLaterDiaryEdit() async {
        let saved = expectation(description: "saved")
        model.$lastLogMessage.compactMap { $0 }.prefix(1).sink { _ in saved.fulfill() }.store(in: &subscriptions)
        model.quickLog(food: FoodItem(id: "food", name: "Oats", calories: 200))
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertTrue(model.canUndoQuickLog)
        let otherSaved = expectation(description: "other action")
        service.addMealToLog(for: "repeat-test-user", date: service.activelyViewedDate, mealName: "Lunch",
                            foodItems: [FoodItem(id: "other", name: "Apple", calories: 90)], source: "manual_add") { _ in
            otherSaved.fulfill()
        }
        await fulfillment(of: [otherSaved], timeout: 3)
        XCTAssertFalse(model.canUndoQuickLog)
        model.undoQuickLog()
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 2)
    }
    private var repository: MockNutritionRepository!
    private var auth: MockAuthService!
    private var service: DailyLogService!
    private var model: FoodSearchViewModel!
    private var subscriptions = Set<AnyCancellable>()
    private var draftDirectory: URL!

    override func setUp() {
        super.setUp()
        repository = MockNutritionRepository()
        auth = MockAuthService()
        auth.currentUserID = "repeat-test-user"
        DIContainer.shared.nutritionRepository = repository
        DIContainer.shared.authService = auth
        DIContainer.shared.analyticsManager = MockAnalyticsManager()
        DIContainer.shared.crashManager = MockCrashManager()
        draftDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        service = DailyLogService(undoStore: EditorDraftStore(directory: draftDirectory))
        service.activateAccount(auth.currentUserID)
        model = FoodSearchViewModel(selectedMeal: "Breakfast", draftStore: EditorDraftStore(directory: draftDirectory))
        model.setup(dailyLogService: service)
        model.fetchData()
    }

    override func tearDown() {
        subscriptions.removeAll()
        service.activateAccount(nil)
        model = nil
        service = nil
        try? FileManager.default.removeItem(at: draftDirectory)
        repository = nil
        auth = nil
        super.tearDown()
    }

    func testQuickLogWaitsForAcceptanceAndRapidTapsCreateOnlyOneEntry() async {
        let saved = expectation(description: "accepted")
        model.$lastLogMessage.compactMap { $0 }.prefix(1).sink { _ in saved.fulfill() }.store(in: &subscriptions)
        let food = FoodItem(id: "usual-oats", name: "Oats", calories: 200, servingSize: "1 cup")
        model.quickLog(food: food)
        model.quickLog(food: food)
        XCTAssertTrue(model.loggingFoodIDs.contains(food.id))
        XCTAssertFalse(model.quickLoggedFoodIDs.contains(food.id))
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertTrue(model.lastLogSucceeded)
        XCTAssertTrue(model.loggingFoodIDs.isEmpty)
        XCTAssertTrue(model.quickLoggedFoodIDs.contains(food.id))
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertTrue(service.canUndoDiaryChange)
    }

    func testFailedSaveDoesNotClaimSuccessAndAllowsRetry() async {
        repository.saveDailyLogError = URLError(.cannotWriteToFile)
        repository.updateLogSuccess = false
        let rejected = expectation(description: "rejected")
        model.$lastLogMessage.compactMap { $0 }.prefix(1).sink { _ in rejected.fulfill() }.store(in: &subscriptions)
        model.quickLog(food: FoodItem(id: "usual-oats", name: "Oats", calories: 200))
        await fulfillment(of: [rejected], timeout: 3)
        XCTAssertFalse(model.lastLogSucceeded)
        XCTAssertTrue(model.loggingFoodIDs.isEmpty)
        XCTAssertTrue(model.quickLoggedFoodIDs.isEmpty)
        XCTAssertTrue(repository.savedDailyLogs.isEmpty)
    }

    func testQuickLogKeepsDateAndMealChosenAtTapTime() async {
        let target = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        service.activelyViewedDate = target
        let saved = expectation(description: "saved to original day")
        model.$lastLogMessage.compactMap { $0 }.prefix(1).sink { _ in saved.fulfill() }.store(in: &subscriptions)
        model.quickLog(food: FoodItem(id: "usual-oats", name: "Oats", calories: 200))
        service.activelyViewedDate = Date()
        model.selectedMeal = "Dinner"
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(repository.lastUpdatedLog?.date, Calendar.current.startOfDay(for: target))
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Breakfast")
    }

    func testRepeatMealCreatesNewEntriesPreservesNutrientsAndSupportsUndo() async throws {
        let food = FoodItem(id: "old-entry", name: "Yogurt", calories: 140, protein: 16, servingSize: "1 cup", calcium: 200)
        let saved = expectation(description: "repeat")
        model.logRepeatedMeal([food], mealName: "Lunch", date: service.activelyViewedDate) { success in
            XCTAssertTrue(success)
            saved.fulfill()
        }
        await fulfillment(of: [saved], timeout: 3)
        let repeated = try XCTUnwrap(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).first)
        XCTAssertNotEqual(repeated.id, food.id)
        XCTAssertEqual(repeated.calcium, 200)
        XCTAssertEqual(repeated.servingSize, "1 cup")
        let undone = expectation(description: "undo")
        service.$currentDailyLog.compactMap { $0 }.filter { $0.meals.flatMap(\.foodItems).isEmpty }
            .prefix(1).sink { _ in undone.fulfill() }.store(in: &subscriptions)
        model.undoQuickLog()
        await fulfillment(of: [undone], timeout: 3)
        XCTAssertTrue(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).isEmpty ?? false)
    }

    func testReviewFromPreviousAccountCannotBeSavedIntoNewAccount() {
        auth.currentUserID = "another-user"
        model.logRepeatedMeal([FoodItem(id: "old-entry", name: "Yogurt", calories: 140)],
                              mealName: "Lunch", date: Date()) { success in
            XCTAssertFalse(success)
        }
        XCTAssertTrue(repository.savedDailyLogs.isEmpty)
    }
}
