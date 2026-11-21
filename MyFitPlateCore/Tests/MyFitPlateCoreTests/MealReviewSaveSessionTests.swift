import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealReviewSaveSessionTests: XCTestCase {
    private let owner = "meal-review-owner"
    private var repository: MockNutritionRepository!
    private var auth: MockAuthService!
    private var service: DailyLogService!
    private var goals: GoalSettings!
    private var store: EditorDraftStore!
    private var directory: URL!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private var previousAnalytics: AnalyticsManagerProtocol?

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService
        previousRepository = DIContainer.shared.nutritionRepository
        previousAnalytics = DIContainer.shared.analyticsManager
        auth = MockAuthService()
        auth.currentUserID = owner
        repository = MockNutritionRepository()
        repository.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repository
        DIContainer.shared.analyticsManager = MockAnalyticsManager()
        service = DailyLogService()
        service.activateAccount(owner)
        goals = GoalSettings(isEditingPreview: true); goals.activateAccount(owner); goals.calories = 2_000
        service.goalSettings = goals
        service.activelyViewedDate = day()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("meal-review-tests-\(UUID().uuidString)")
        store = EditorDraftStore(directory: directory)
    }

    override func tearDown() {
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.nutritionRepository = previousRepository
        DIContainer.shared.analyticsManager = previousAnalytics
        try? FileManager.default.removeItem(at: directory)
        service = nil
        repository = nil
        auth = nil
        store = nil
        super.tearDown()
    }

    func testChangedSuggestionBudgetRequiresExactReviewedAcknowledgementAndRetryStaysFrozen() async throws {
        let chosen = day(-2), context = try XCTUnwrap(DiaryDayContext(userID: owner, date: day(-2)))
        let idea = MealSuggestion(title: "Bowl", calories: 400, mealName: "Bowl", protein: 20, carbs: 60, fats: 9,
            ingredients: ["150 g rice", "100 g beans"], instructions: "Mix.", prepMinutes: 12).withGeneratedEvidence()
        let review = idea.makeReview(userID: owner, day: context, source: "budget-review", store: store)
        goals.calories = 300
        let first = await save(review)
        XCTAssertFalse(first); XCTAssertFalse(review.isSubmitted)
        XCTAssertEqual(review.pendingBudgetReview?.day.dayKey, context.dayKey)
        XCTAssertTrue(review.acceptChangedSuggestionBudget())
        goals.calories = 250
        let changed = await save(review)
        XCTAssertFalse(changed); XCTAssertFalse(review.isSubmitted, "A prior acknowledgement cannot approve newly changed goals")
        XCTAssertTrue(review.acceptChangedSuggestionBudget())
        repository.updateLogSuccess = false
        let failed = await save(review)
        XCTAssertFalse(failed); XCTAssertTrue(review.isSubmitted)
        let ids = review.checkpoint.draft.entries.map(\.id)
        goals.calories = 0; service.activelyViewedDate = day()
        repository.updateLogSuccess = true
        let restored = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "budget-review", userID: owner, store: store))
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let stored = try await reload(chosen)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), ids)
        XCTAssertEqual(stored.meals.first?.foodItems.first?.sourceMetadata?.mealSuggestionEvidence?.prepMinutes, 12)
    }

    func testRequestedAlternativeAndPreviousFullIdeaSurviveRelaunchWithoutLogging() async throws {
        let context = try XCTUnwrap(DiaryDayContext(userID: owner, date: day(-1)))
        let original = MealSuggestion(title: "Original", calories: 400, mealName: "Original", protein: 20, carbs: 50, fats: 8,
            ingredients: ["Original ingredients"], instructions: "Original instructions", prepMinutes: 40)
        let next = MealSuggestion(title: "Quicker", calories: 350, mealName: "Quicker", protein: 20, carbs: 45, fats: 8,
            ingredients: ["Quick ingredients"], instructions: "Quick instructions", prepMinutes: 15)
        let review = original.makeReview(userID: owner, day: context, source: "alternative-review", store: store)
        XCTAssertTrue(review.requestAlternative(.quicker))
        let resumed = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "alternative-review", userID: owner, store: store))
        XCTAssertEqual(resumed.checkpoint.requestedAlternative, .quicker)
        XCTAssertEqual(resumed.checkpoint.mealSuggestion?.id, original.id, "A pending request retains its original choice")
        XCTAssertTrue(resumed.replaceMealSuggestion(next))
        XCTAssertEqual(resumed.checkpoint.alternativeHistory?.last?.reason, .quicker)
        XCTAssertEqual(resumed.checkpoint.alternativeHistory?.last?.previous.instructions, original.instructions)
        XCTAssertTrue(resumed.restorePreviousSuggestion())
        XCTAssertEqual(resumed.checkpoint.mealSuggestion?.id, original.id)
        XCTAssertEqual(resumed.date, context.originalDate)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        let accepted = await save(resumed)
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.sourceMetadata?.mealSuggestionRejections?.first?.reason, .quicker)
    }

    func testMaiaSuggestionResumesFullRecipeAndExactDayAfterFailureThenLogsOnce() async throws {
        let chosen = day(-2)
        let context = try XCTUnwrap(DiaryDayContext(userID: owner, date: chosen))
        let idea = MealSuggestion(title: "Lunch idea", calories: 480, mealName: "Rice bowl",
            protein: 35, carbs: 60, fats: 12, ingredients: ["150 g rice", "120 g chicken"],
            instructions: "Cook chicken. Serve with rice.")
        let review = idea.makeReview(userID: owner, day: context, source: "ai_suggestion", meal: "Lunch", store: store)
        let loggingID = try XCTUnwrap(review.checkpoint.draft.entries.first?.id)
        repository.updateLogSuccess = false
        let rejected = await save(review)
        XCTAssertFalse(rejected)
        service.activelyViewedDate = day()
        let restored = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "ai_suggestion", userID: owner, store: store))
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.id, idea.id)
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.ingredients, idea.ingredients)
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.instructions, idea.instructions)
        XCTAssertEqual(restored.date, chosen)
        XCTAssertEqual(restored.checkpoint.draft.entries.first?.id, loggingID)
        repository.updateLogSuccess = true
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let saved = try await reload(chosen)
        XCTAssertEqual(saved.meals.flatMap(\.foodItems).map(\.id), [loggingID])
        XCTAssertNil(MealReviewSaveSession.resumeMealSuggestion(source: "ai_suggestion", userID: owner, store: store))
        let today = try await reload(day())
        XCTAssertTrue(today.meals.isEmpty)
    }

    func testSuggestionRegenerationIsAtomicAndCannotReplaceSubmittedFood() async throws {
        let context = try XCTUnwrap(DiaryDayContext(userID: owner, date: day(-1)))
        let first = MealSuggestion(title: "First", calories: 300, mealName: "Rice", protein: 5, carbs: 60, fats: 2)
        let next = MealSuggestion(title: "Next", calories: 400, mealName: "Beans", protein: 22, carbs: 60, fats: 5)
        let review = first.makeReview(userID: owner, day: context, source: "maia_action_card", meal: "Dinner", store: store)
        XCTAssertTrue(review.replaceMealSuggestion(next))
        XCTAssertEqual(review.date, context.originalDate)
        XCTAssertEqual(review.mealName, "Dinner")
        XCTAssertEqual(review.items.first?.name, "Beans")
        let restored = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "maia_action_card", userID: owner, store: store))
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.id, next.id)
        XCTAssertEqual(restored.items.first?.name, "Beans")
        let invalid = MealSuggestion(title: "Bad", calories: .nan, mealName: "Bad", protein: 2, carbs: 2, fats: 2)
        XCTAssertFalse(restored.replaceMealSuggestion(invalid))
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.id, next.id)
        repository.updateLogSuccess = false
        let rejected = await save(restored)
        XCTAssertFalse(rejected)
        let frozenID = restored.checkpoint.draft.entries.first?.id
        XCTAssertFalse(restored.replaceMealSuggestion(first))
        XCTAssertEqual(restored.checkpoint.draft.entries.first?.id, frozenID)
        XCTAssertEqual(restored.checkpoint.mealSuggestion?.id, next.id)
    }

    func testPendingSuggestionCannotBeReplacedByNewGenerationOrAnotherAccount() throws {
        let context = try XCTUnwrap(DiaryDayContext(userID: owner, date: day(-1)))
        let first = MealSuggestion(title: "Kept", calories: 300, mealName: "Kept", protein: 5, carbs: 60, fats: 2)
        let second = MealSuggestion(title: "New", calories: 400, mealName: "New", protein: 10, carbs: 60, fats: 5)
        let original = first.makeReview(userID: owner, day: context, source: "ai_suggestion", store: store)
        let attempted = second.makeReview(userID: owner, day: try XCTUnwrap(DiaryDayContext(userID: owner, date: day())), source: "ai_suggestion", store: store)
        XCTAssertEqual(attempted.checkpoint.mealSuggestion?.id, first.id)
        XCTAssertEqual(attempted.checkpoint.draft.entries.first?.id, original.checkpoint.draft.entries.first?.id)
        XCTAssertEqual(attempted.date, context.originalDate)
        XCTAssertNil(MealReviewSaveSession.resumeMealSuggestion(source: "ai_suggestion", userID: "other-owner", store: store))
    }

    func testFailedSaveRestoresFrozenIDsFoodsMealAndDateThenRetriesToThatDay() async throws {
        let viewed = day()
        let chosen = day(-2)
        let todayFood = food("today", name: "Keep today's meal")
        try await repository.saveDailyLog(userID: owner, log: DailyLog(
            id: DiaryDayContext.dayKey(for: viewed), date: viewed, meals: [Meal(name: "Breakfast", foodItems: [todayFood])]
        ))
        service.currentDailyLog = try await reload(viewed)
        let review = makeReview([food("rice"), food("chicken")], source: "ai_text")
        XCTAssertTrue(review.updateDestination(date: chosen, mealName: "Dinner"))
        let draftID = review.checkpoint.draft.id
        let entryIDs = review.checkpoint.draft.entries.map(\.id)
        repository.updateLogSuccess = false
        let rejected = await save(review)
        XCTAssertFalse(rejected)
        XCTAssertTrue(review.isSubmitted)
        XCTAssertFalse(review.isSaving)
        XCTAssertFalse(review.isAccepted)
        XCTAssertNotNil(review.errorMessage)
        let failedDay = try await reload(chosen)
        XCTAssertTrue(failedDay.meals.isEmpty)

        let restored = makeReview([food("replacement")], date: day(1), meal: "Lunch", source: "ai_text")
        XCTAssertTrue(restored.restoredReview)
        XCTAssertEqual(restored.checkpoint.draft.id, draftID)
        XCTAssertEqual(restored.checkpoint.draft.entries.map(\.id), entryIDs)
        XCTAssertEqual(restored.items.map(\.id), ["rice", "chicken"])
        XCTAssertEqual(restored.date, chosen)
        XCTAssertEqual(restored.mealName, "Dinner")
        XCTAssertTrue(restored.isLocked)

        repository.updateLogSuccess = true
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let stored = try await reload(chosen)
        XCTAssertEqual(stored.meals.map(\.name), ["Dinner"])
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), entryIDs)
        let unchangedToday = try await reload(viewed)
        XCTAssertEqual(try encoded(unchangedToday.meals[0].foodItems[0]), try encoded(todayFood))
        XCTAssertEqual(service.currentDailyLog?.date, viewed)
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
    }

    func testRapidDoubleTapWhileWriteDeferredStartsOneLogicalSave() async throws {
        repository.shouldDeferDailyLogUpdateCompletions = true
        let review = makeReview([food("bowl")])
        let first = expectation(description: "first save accepted")
        review.save(using: service) { accepted in
            XCTAssertTrue(accepted)
            first.fulfill()
        }
        XCTAssertTrue(review.isSaving)
        XCTAssertTrue(review.isSubmitted)
        var duplicateResult: Bool?
        review.save(using: service) { duplicateResult = $0 }
        XCTAssertEqual(duplicateResult, false)
        await waitForDeferredWrite()
        XCTAssertEqual(repository.dailyLogUpdateUserIDs, [owner])
        let beforeCommit = try await reload(review.date)
        XCTAssertTrue(beforeCommit.meals.isEmpty)
        repository.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [first], timeout: 1)
        let stored = try await reload(review.date)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).count, 1)
        XCTAssertFalse(review.isSaving)
        XCTAssertTrue(review.isAccepted)
    }

    func testPreviouslyCommittedSubmittedCheckpointRetriesWithoutDuplicatingFoods() async throws {
        let chosen = day(-1)
        let existing = food("unrelated", name: "Existing food")
        let original = makeReview([food("menu-item")], date: chosen, meal: "Lunch", source: "ai_menu")
        var checkpoint = original.checkpoint
        checkpoint.draft.isSubmitted = true
        try store.save(checkpoint, userID: owner, scope: MealReviewSaveSession.scope(for: "ai_menu"))
        let committedFoods = checkpoint.draft.entries.compactMap(\.preparedFood)
        try await repository.saveDailyLog(userID: owner, log: DailyLog(
            id: DiaryDayContext.dayKey(for: chosen), date: chosen, meals: [Meal(name: "Lunch", foodItems: [existing] + committedFoods)]
        ))

        let restored = makeReview([], date: day(), meal: "Breakfast", source: "ai_menu")
        XCTAssertTrue(restored.restoredReview)
        XCTAssertTrue(restored.isSubmitted)
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let stored = try await reload(chosen)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), [existing.id] + committedFoods.map(\.id))
        XCTAssertEqual(try encoded(stored.meals[0].foodItems[0]), try encoded(existing))
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_menu", userID: owner, store: store))
    }

    func testProviderIDDoesNotDeduplicateAnUnrelatedExistingFood() async throws {
        let chosen = day(-1)
        let existing = food("provider-id", name: "Original portion")
        try await repository.saveDailyLog(userID: owner, log: DailyLog(
            id: DiaryDayContext.dayKey(for: chosen), date: chosen, meals: [Meal(name: "Dinner", foodItems: [existing])]
        ))
        var newPortion = food("provider-id", name: "Another portion")
        newPortion.servingWeight = 250
        let review = makeReview([newPortion], date: chosen, meal: "Dinner")
        let loggingID = try XCTUnwrap(review.checkpoint.draft.entries.first?.id)
        XCTAssertNotEqual(loggingID, existing.id)
        let accepted = await save(review)
        XCTAssertTrue(accepted)
        let stored = try await reload(chosen)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), [existing.id, loggingID])
        XCTAssertEqual(try encoded(stored.meals[0].foodItems[0]), try encoded(existing))
        XCTAssertEqual(stored.meals[0].foodItems[1].servingWeight, 250)
    }

    func testMenuSelectionRestoresAndOnlySelectedItemsArePersisted() async throws {
        let source = "ai_menu"
        let review = makeReview([food("a"), food("b"), food("c")], source: source, selectsAll: false)
        XCTAssertTrue(review.selectedItems.isEmpty)
        XCTAssertTrue(review.toggleSelection(id: "a"))
        XCTAssertTrue(review.toggleSelection(id: "c"))
        XCTAssertFalse(review.toggleSelection(id: "unknown"))
        let expectedIDs = review.checkpoint.draft.entries.filter { ["a", "c"].contains($0.food.id) }.map(\.id)
        let restored = makeReview([], source: source, selectsAll: false)
        XCTAssertEqual(restored.selectedItemIDs, ["a", "c"])
        XCTAssertEqual(restored.selectedItems.map(\.id), ["a", "c"])
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let stored = try await reload(restored.date)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), expectedIDs)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.name), ["a", "c"])
    }

    func testEditedFoodAndItsLoggingIdentitySurviveRelaunchAndSave() async throws {
        let review = makeReview([food("editable")], confirmingSource: .aiText)
        let originalLoggingID = try XCTUnwrap(review.checkpoint.draft.entries.first?.id)
        var edited = try XCTUnwrap(review.items.first)
        edited.name = "Corrected portion"
        edited.calories = 360
        edited.protein = 30
        edited.carbs = 42
        edited.fats = 8
        edited.servingWeight = 300
        edited.servingSize = "300 g"
        edited.quantityValue = 300
        edited.servingUnit = "g"
        XCTAssertTrue(review.updateItem(edited))
        let restored = makeReview([], confirmingSource: .aiText)
        XCTAssertEqual(restored.checkpoint.draft.entries.first?.id, originalLoggingID)
        XCTAssertEqual(restored.items.first?.calories, 360)
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let stored = try await reload(restored.date)
        let saved = try XCTUnwrap(stored.meals.flatMap(\.foodItems).first)
        XCTAssertEqual(saved.id, originalLoggingID)
        XCTAssertEqual(saved.name, edited.name)
        XCTAssertEqual(saved.calories, 360)
        XCTAssertEqual(saved.protein, 30)
        XCTAssertEqual(saved.carbs, 42)
        XCTAssertEqual(saved.fats, 8)
        XCTAssertEqual(saved.servingWeight, 300)
        XCTAssertEqual(saved.servingSize, "300 g")
        XCTAssertEqual(saved.quantityValue, 300)
        XCTAssertEqual(saved.servingUnit, "g")
        XCTAssertEqual(saved.sourceMetadata?.sourceType, .aiText)
        XCTAssertEqual(saved.sourceMetadata?.reviewStatus, .userConfirmed)
    }

    func testLocalCheckpointIOFailureRetainsEditedInputAndBlocksDiaryUntilDurableRetry() async throws {
        let review = makeReview([food("edited-during-io-failure")], meal: "Dinner")
        let loggingIDs = review.checkpoint.draft.entries.map(\.id)
        let backup = directory.appendingPathExtension("preserved-directory")
        defer { try? FileManager.default.removeItem(at: backup) }
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("This is a regular file, not a draft directory.".utf8).write(to: directory)

        var edited = try XCTUnwrap(review.items.first)
        edited.name = "Reviewed double portion"
        edited.calories = 360
        edited.protein = 30
        edited.carbs = 42
        edited.fats = 8
        edited.servingWeight = 300
        edited.servingSize = "300 g"
        XCTAssertFalse(review.updateItem(edited), "A failed disk write must not report a durable checkpoint")
        XCTAssertEqual(review.items.first?.name, edited.name)
        XCTAssertEqual(review.items.first?.calories, 360, "The user's latest input must remain visible in memory")
        XCTAssertEqual(review.items.first?.servingWeight, 300)
        XCTAssertNotNil(review.errorMessage)

        let blocked = await save(review)
        XCTAssertFalse(blocked)
        XCTAssertFalse(review.isSaving)
        XCTAssertFalse(review.isAccepted)
        XCTAssertNotNil(review.errorMessage)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty, "No diary command may precede durable local payload acceptance")
        let beforeRepair = try await reload(review.date)
        XCTAssertTrue(beforeRepair.meals.isEmpty)

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        let olderDurableReview = makeReview([])
        XCTAssertEqual(olderDurableReview.items.first?.calories, 180, "A relaunch can only restore the previous successful checkpoint")
        XCTAssertEqual(olderDurableReview.checkpoint.draft.entries.map(\.id), loggingIDs)

        repository.shouldDeferDailyLogUpdateCompletions = true
        let finished = expectation(description: "repaired checkpoint and diary save accepted")
        review.save(using: service) { accepted in
            XCTAssertTrue(accepted)
            finished.fulfill()
        }
        await waitForDeferredWrite()
        let restoredAfterLocalAcceptance = makeReview([])
        XCTAssertTrue(restoredAfterLocalAcceptance.isSubmitted)
        XCTAssertEqual(restoredAfterLocalAcceptance.items.first?.calories, 360)
        XCTAssertEqual(restoredAfterLocalAcceptance.items.first?.servingWeight, 300)
        XCTAssertEqual(restoredAfterLocalAcceptance.mealName, "Dinner")
        XCTAssertEqual(restoredAfterLocalAcceptance.checkpoint.draft.entries.map(\.id), loggingIDs)
        let beforeDiaryAcceptance = try await reload(review.date)
        XCTAssertTrue(beforeDiaryAcceptance.meals.isEmpty)

        repository.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [finished], timeout: 1)
        repository.shouldDeferDailyLogUpdateCompletions = false
        let relaunchedRetry = await save(restoredAfterLocalAcceptance)
        XCTAssertTrue(relaunchedRetry)
        let stored = try await reload(review.date)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), loggingIDs)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).first?.calories, 360)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).first?.name, edited.name)
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
    }

    func testPhotoSelectionKeepsReviewedIDsAcrossRetryAndLeavesDiaryAndStandaloneReviewIntact() {
        let source = "ai_image_selection_test"
        let standalone = makeReview([food("separate")], source: "ai_image")
        let photo = makeReview([food("one"), food("two")], source: source, confirmingSource: .aiImage)
        let ids = photo.checkpoint.draft.entries.map(\.id)
        XCTAssertFalse(photo.moveToMeal { foods in
            XCTAssertEqual(foods.map(\.id), ids)
            return false
        })
        let resumed = makeReview([], source: source, confirmingSource: .aiImage)
        auth.currentUserID = "another"
        XCTAssertFalse(resumed.moveToMeal { _ in XCTFail("Another account must not receive these foods"); return true })
        auth.currentUserID = owner
        XCTAssertTrue(resumed.moveToMeal { foods in
            XCTAssertEqual(foods.map(\.id), ids)
            XCTAssertTrue(foods.allSatisfy { $0.sourceMetadata?.reviewStatus == .userConfirmed })
            return true
        })
        XCTAssertFalse(resumed.moveToMeal { _ in XCTFail("Accepted handoff must not repeat"); return true })
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: source, userID: owner, store: store))
        XCTAssertEqual(standalone.items.map(\.id), ["separate"])
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_image", userID: owner, store: store))
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
    }

    func testUnsubmittedDiscardRemovesOnlyItsScopeAndDoesNotWriteDiary() throws {
        let review = makeReview([food("discard")], source: "ai_text")
        let keep = makeReview([food("keep")], source: "ai_menu")
        let originalIDs = review.checkpoint.draft.entries.map(\.id)
        XCTAssertTrue(review.discard())
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_menu", userID: owner, store: store))
        XCTAssertEqual(keep.items.map(\.id), ["keep"])
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        let next = makeReview([food("replacement")], source: "ai_text")
        XCTAssertFalse(next.restoredReview)
        XCTAssertTrue(Set(originalIDs).isDisjoint(with: next.checkpoint.draft.entries.map(\.id)))
    }

    func testDiscardedSessionRejectsLateSaveAndCannotRecreateItsCheckpoint() async throws {
        let review = makeReview([food("discarded")])
        XCTAssertTrue(review.discard())
        XCTAssertTrue(review.isDiscarded)
        XCTAssertTrue(review.isLocked)
        XCTAssertFalse(review.updateDestination(date: day(-3), mealName: "Dinner"))
        XCTAssertFalse(review.updateItem(food("discarded", name: "Late edit")))
        XCTAssertFalse(review.replaceItems([food("replacement")]))
        XCTAssertFalse(review.toggleSelection(id: "discarded"))
        let accepted = await save(review)
        XCTAssertFalse(accepted)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
        let stored = try await reload(review.date)
        XCTAssertTrue(stored.meals.isEmpty)
    }

    func testSubmittedFailedReviewCannotBeDiscardedOrEdited() async throws {
        let review = makeReview([food("locked")])
        repository.updateLogSuccess = false
        let failed = await save(review)
        XCTAssertFalse(failed)
        let frozen = try encoded(review.checkpoint)
        XCTAssertTrue(review.isSubmitted)
        XCTAssertFalse(review.discard())
        XCTAssertFalse(review.updateDestination(date: day(-3), mealName: "Breakfast"))
        XCTAssertFalse(review.updateItem(food("locked", name: "Changed")))
        XCTAssertFalse(review.replaceItems([food("new")]))
        XCTAssertFalse(review.removeItem(id: "locked"))
        XCTAssertFalse(review.toggleSelection(id: "locked"))
        XCTAssertEqual(try encoded(review.checkpoint), frozen)
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
    }

    func testAccountSwitchBeforeSaveRejectsWithoutCrossPublication() async throws {
        let review = makeReview([food("private")], date: day(-1))
        auth.currentUserID = "other"
        service.activateAccount("other")
        let otherDate = day()
        let otherProjection = DailyLog(id: DiaryDayContext.dayKey(for: otherDate), date: otherDate, meals: [])
        service.currentDailyLog = otherProjection
        let accepted = await save(review)
        XCTAssertFalse(accepted)
        XCTAssertFalse(review.isSubmitted)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertEqual(service.currentDailyLog, otherProjection)
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: "other", store: store))
    }

    func testAccountSwitchAfterSubmissionBeforeWriteRetainsOriginalCheckpoint() async throws {
        let review = makeReview([food("private")])
        let finished = expectation(description: "account-switched save rejected")
        review.save(using: service) { accepted in
            XCTAssertFalse(accepted)
            finished.fulfill()
        }
        auth.currentUserID = "other"
        service.activateAccount("other")
        let otherDate = day()
        let otherProjection = DailyLog(id: DiaryDayContext.dayKey(for: otherDate), date: otherDate, meals: [])
        service.currentDailyLog = otherProjection
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(review.isSubmitted)
        XCTAssertFalse(review.isAccepted)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertEqual(service.currentDailyLog, otherProjection)
        let stored = try await reload(review.date, userID: owner)
        XCTAssertTrue(stored.meals.isEmpty)
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))
    }

    func testAcceptedOriginalAccountWriteAfterSwitchRetainsCheckpointAndRetryDeduplicates() async throws {
        repository.shouldDeferDailyLogUpdateCompletions = true
        let review = makeReview([food("private")], date: day(-1))
        let loggingIDs = review.checkpoint.draft.entries.map(\.id)
        let finished = expectation(description: "old account UI remains isolated")
        review.save(using: service) { accepted in
            XCTAssertFalse(accepted, "The old account may have committed, but the new account UI must not accept its review")
            finished.fulfill()
        }
        await waitForDeferredWrite()
        auth.currentUserID = "other"
        service.activateAccount("other")
        let otherDate = day()
        let otherProjection = DailyLog(id: DiaryDayContext.dayKey(for: otherDate), date: otherDate, meals: [])
        service.currentDailyLog = otherProjection
        repository.completeDeferredDailyLogUpdates(success: true)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(service.currentDailyLog, otherProjection)
        let ownerStored = try await reload(review.date, userID: owner)
        let otherStored = try await reload(review.date, userID: "other")
        XCTAssertEqual(ownerStored.meals.flatMap(\.foodItems).map(\.id), loggingIDs)
        XCTAssertTrue(otherStored.meals.isEmpty)
        XCTAssertEqual(repository.dailyLogUpdateUserIDs, [owner])
        XCTAssertNotNil(MealReviewSaveSession.pendingReview(source: "ai_text", userID: owner, store: store))

        auth.currentUserID = owner
        service.activateAccount(owner)
        repository.shouldDeferDailyLogUpdateCompletions = false
        let restored = makeReview([])
        let accepted = await save(restored)
        XCTAssertTrue(accepted)
        let afterRetry = try await reload(review.date)
        XCTAssertEqual(afterRetry.meals.flatMap(\.foodItems).map(\.id), loggingIDs)
    }

    func testNewSecondHelpingAfterAcceptanceGetsFreshLoggingIDs() async throws {
        let base = food("same-provider-item")
        let first = makeReview([base])
        let firstIDs = first.checkpoint.draft.entries.map(\.id)
        let firstAccepted = await save(first)
        XCTAssertTrue(firstAccepted)
        let second = makeReview([base])
        XCTAssertFalse(second.restoredReview)
        let secondIDs = second.checkpoint.draft.entries.map(\.id)
        XCTAssertTrue(Set(firstIDs).isDisjoint(with: secondIDs))
        let secondAccepted = await save(second)
        XCTAssertTrue(secondAccepted)
        let stored = try await reload(first.date)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).map(\.id), firstIDs + secondIDs)
    }

    func testAcceptedSessionCannotBeSavedEditedOrDiscardedAgain() async throws {
        let review = makeReview([food("accepted")])
        let accepted = await save(review)
        XCTAssertTrue(accepted)
        XCTAssertTrue(review.isAccepted)
        XCTAssertTrue(review.isLocked)
        XCTAssertFalse(review.updateItem(food("accepted", name: "Changed")))
        XCTAssertFalse(review.discard())
        let repeated = await save(review)
        XCTAssertFalse(repeated)
        let stored = try await reload(review.date)
        XCTAssertEqual(stored.meals.flatMap(\.foodItems).count, 1)
    }

    func testCustomRecipeScopeRestoresItsPortionAndDoesNotCollideWithOtherRecipes() async throws {
        let recipeScope = "recipe-review-recipe-a"
        let first = makeReview([food("recipe-a")], meal: "Dinner", source: "recipe", scope: recipeScope)
        var portion = try XCTUnwrap(first.items.first)
        portion.calories = 360
        portion.protein = 30
        portion.carbs = 42
        portion.fats = 8
        portion.servingSize = "2 portions"
        XCTAssertTrue(first.replaceItems([portion]))
        repository.updateLogSuccess = false
        let failed = await save(first)
        XCTAssertFalse(failed)
        let frozenIDs = first.checkpoint.draft.entries.map(\.id)
        let restored = makeReview([food("unexpected")], date: day(-3), meal: "Breakfast", source: "recipe", scope: recipeScope)
        let secondRecipe = makeReview([food("recipe-b")], source: "recipe", scope: "recipe-review-recipe-b")
        XCTAssertTrue(restored.restoredReview)
        XCTAssertFalse(secondRecipe.restoredReview)
        XCTAssertEqual(restored.checkpoint.draft.entries.map(\.id), frozenIDs)
        XCTAssertEqual(restored.items.first?.calories, 360)
        XCTAssertEqual(restored.items.first?.servingSize, "2 portions")
        XCTAssertEqual(restored.mealName, "Dinner")
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "recipe", userID: owner, store: store))
        repository.updateLogSuccess = true
        let firstAccepted = await save(restored)
        let secondAccepted = await save(secondRecipe)
        XCTAssertTrue(firstAccepted)
        XCTAssertTrue(secondAccepted)
        let stored = try await reload(first.date)
        XCTAssertEqual(Set(stored.meals.flatMap(\.foodItems).map(\.id)), Set(frozenIDs + secondRecipe.checkpoint.draft.entries.map(\.id)))
        XCTAssertNil(try store.load(MealReviewCheckpoint.self, userID: owner, scope: recipeScope))
        XCTAssertNil(try store.load(MealReviewCheckpoint.self, userID: owner, scope: "recipe-review-recipe-b"))
    }

    private func makeReview(
        _ items: [FoodItem], date: Date? = nil, meal: String = "Lunch", source: String = "ai_text",
        selectsAll: Bool = true, scope: String? = nil, confirmingSource: FoodSourceType? = nil
    ) -> MealReviewSaveSession {
        MealReviewSaveSession(
            items: items, userID: owner, date: date ?? day(-1), mealName: meal,
            source: source, selectsAllItems: selectsAll, draftScope: scope,
            confirmingSourceType: confirmingSource, store: store
        )
    }

    private func food(_ id: String, name: String? = nil) -> FoodItem {
        FoodItem(id: id, name: name ?? id, calories: 180, protein: 15, carbs: 21, fats: 4,
                 servingSize: "150 g", servingWeight: 150, quantityValue: 150, servingUnit: "g")
    }

    private func day(_ offset: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        return Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: base))!
    }

    private func save(_ review: MealReviewSaveSession) async -> Bool {
        await withCheckedContinuation { continuation in
            review.save(using: service) { continuation.resume(returning: $0) }
        }
    }

    private func reload(_ date: Date, userID: String? = nil) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            repository.fetchLogInternal(userID: userID ?? owner, date: date) { continuation.resume(with: $0) }
        }
    }

    private func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func waitForDeferredWrite() async {
        for _ in 0..<200 where repository.deferredDailyLogUpdateCompletions.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertFalse(repository.deferredDailyLogUpdateCompletions.isEmpty)
    }
}
