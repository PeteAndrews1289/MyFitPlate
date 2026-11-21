import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlanEditingTests: XCTestCase {
    private var date: Date { Date(timeIntervalSince1970: 1_792_000_000) }
    private func meal(_ name: String = "Chicken bowl") -> PlannedMeal {
        PlannedMeal(id: "bowl", mealType: "Lunch", foodItem: FoodItem(id: "base-food", name: name,
            calories: 400, protein: 30, carbs: 40, fats: 10, fiber: 6, servingSize: "1 bowl", servingWeight: 300),
            ingredients: ["100 g chicken", "0.5 cup rice"], instructions: "1. Cook chicken.\n2. Add rice.")
    }
    private func day(_ offset: Int, meals: [PlannedMeal] = []) -> MealPlanDay {
        var day = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: offset, to: date)!)
        day.meals = meals; return day
    }

    func testLegacyMealDefaultsToOnePortionAndRoundTripsNewPortions() throws {
        var original = meal()
        let legacy = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PlannedMeal.self, from: legacy).portions, 1)
        original.portionMultiplier = 1.5
        let restored = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.plannedFood?.calories, 600)
        XCTAssertEqual(restored.plannedFood?.fiber, 9)
        XCTAssertEqual(restored.foodItem?.calories, 400)
        XCTAssertEqual(restored.plannedIngredients.first?.quantity, 150)
        XCTAssertEqual(PlannedMealLoggingRules.food(for: restored, date: date)?.calories, 600)
    }

    func testGroceryAndPrepUseExactPortionsAndKeepIndependentCookingSteps() {
        var portion = meal(); portion.portionMultiplier = 1.5
        let days = [day(0, meals: [portion]), day(1, meals: [MealPlanEditingRules.duplicate(portion)])]
        let groceries = GroceryListBuilder.makeGroceryList(from: days, unitSystem: .metric)
        XCTAssertEqual(groceries.first { $0.name.lowercased().contains("chicken") }?.quantity, 300)
        let prep = MealPrepService(); prep.aggregate(days: days)
        XCTAssertEqual(prep.bulkIngredients.values.flatMap { $0 }.first { $0.name.lowercased().contains("chicken") }?.quantity, 300)
        XCTAssertEqual(prep.prepSteps.count, 4)
        XCTAssertEqual(Set(prep.structuredSteps.map(\.requirementID)).count, 2)
    }

    func testCopyAppendsWithFreshIdentityAndKeepsSource() throws {
        let source = day(0, meals: [meal()])
        var existing = meal("Oats"); existing.id = "oats"
        let destination = day(1, meals: [existing])
        let change = try MealPlanEditingRules.transferring(source.meals, from: source, to: [destination], moving: false)
        XCTAssertEqual(change.before.count, 1)
        XCTAssertEqual(change.after[0].meals.count, 2)
        XCTAssertEqual(change.after[0].meals.first?.id, "oats")
        XCTAssertNotEqual(change.after[0].meals.last?.id, source.meals[0].id)
        XCTAssertNotEqual(change.after[0].meals.last?.foodItem?.id, source.meals[0].foodItem?.id)
    }

    func testMoveIncludesBothDaysAndRejectsSameDayOrMultipleDestinations() throws {
        let source = day(0, meals: [meal()])
        let change = try MealPlanEditingRules.transferring(source.meals, from: source, to: [day(1)], moving: true)
        XCTAssertEqual(change.after.count, 2)
        XCTAssertTrue(change.after[1].meals.isEmpty)
        XCTAssertEqual(change.after[0].meals.count, 1)
        XCTAssertThrowsError(try MealPlanEditingRules.transferring(source.meals, from: source, to: [source], moving: false))
        XCTAssertThrowsError(try MealPlanEditingRules.transferring(source.meals, from: source, to: [day(1), day(2)], moving: true))
    }

    func testInvalidPortionsCannotBeCommitted() throws {
        let source = day(0, meals: [meal()])
        for amount in [0, -1, 9, .infinity, .nan] {
            var changed = meal(); changed.portionMultiplier = amount
            let edit = try MealPlanEditingRules.replacing(changed, in: source)
            XCTAssertThrowsError(try MealPlanEditingRules.validate(edit))
        }
    }

    func testWeekUsesCalendarBoundariesAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York")); calendar.firstWeekday = 2
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let dates = MealPlanEditingRules.week(containing: date, calendar: calendar)
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: dates[0]), 2)
        XCTAssertEqual(Set(dates.map { MealPlanEditingRules.dayID($0, calendar: calendar) }).count, 7)
    }

    func testTransactionalSaveUndoSurvivesServiceRecreationAndRejectsStaleUndo() async throws {
        let repo = MockNutritionRepository(), auth = MockAuthService()
        auth.currentUserID = "planner-test"
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let suite = "planner-test.\(UUID())"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let service = MealPlannerService(recipeService: RecipeService(), userDefaults: store)
        let original = day(0, meals: [meal()])
        repo.mockMealPlansByDateString[original.id] = original
        var changed = meal(); changed.portionMultiplier = 2
        try await service.applyPlanChange(MealPlanEditingRules.replacing(changed, in: original), for: "planner-test")
        let reopened = MealPlannerService(recipeService: RecipeService(), userDefaults: store)
        XCTAssertNotNil(reopened.lastPlanChange(for: "planner-test"))
        try await reopened.undoLastPlanChange(for: "planner-test")
        XCTAssertEqual(repo.mockMealPlansByDateString[original.id]?.meals.first?.plannedFood?.calories, 400)
        XCTAssertNil(reopened.lastPlanChange(for: "planner-test"))
        try await reopened.applyPlanChange(MealPlanEditingRules.replacing(changed, in: original), for: "planner-test")
        repo.mockMealPlansByDateString[original.id]?.meals.append(MealPlanEditingRules.duplicate(meal("Toast")))
        do { try await reopened.undoLastPlanChange(for: "planner-test"); XCTFail("Stale undo must not erase newer meals") } catch {}
        XCTAssertEqual(repo.mockMealPlansByDateString[original.id]?.meals.count, 2)
        auth.currentUserID = "another-user"
        XCTAssertNil(reopened.lastPlanChange(for: "planner-test"))
        do { try await reopened.applyPlanChange(MealPlanEditingRules.replacing(changed, in: original), for: "planner-test"); XCTFail("Wrong account") } catch {}
    }

    func testFailedMoveLeavesBothDaysAndNoUndoReceipt() async throws {
        let repo = MockNutritionRepository(), auth = MockAuthService()
        auth.currentUserID = "planner-test"
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let suite = "planner-failure.\(UUID())"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let source = day(0, meals: [meal()]); repo.mockMealPlansByDateString[source.id] = source
        repo.mealPlanError = NSError(domain: "offline", code: 1)
        let service = MealPlannerService(recipeService: RecipeService(), userDefaults: store)
        let change = try MealPlanEditingRules.transferring(source.meals, from: source, to: [day(1)], moving: true)
        do { try await service.applyPlanChange(change, for: "planner-test"); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(repo.mockMealPlansByDateString[source.id]?.meals.count, 1)
        XCTAssertTrue(repo.batchSavedMealPlans.isEmpty)
        XCTAssertNil(service.lastPlanChange(for: "planner-test"))
    }

    func testWorkoutUpcomingFollowsCurrentRotationNotOriginalWeek() {
        let routines = ["A", "B", "C"].map { WorkoutRoutine(id: $0, userID: "u", name: $0, dateCreated: date) }
        let program = WorkoutProgram(userID: "u", name: "Rotation", routines: routines,
                                     startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 5)
        let sessions = TrainingScheduleOverview.upcoming(program, now: date)
        XCTAssertEqual(sessions.map { $0.routine.name }, ["C", "A", "B", "C"])
        XCTAssertEqual(sessions.first?.week, 2)
        XCTAssertEqual(sessions.first?.day, 2)
        XCTAssertEqual(sessions.first?.date, program.date(forSlot: 5))
    }

    func testWeekDraftFillsMissingSlotsAndPreservesSavedMealsByDefault() throws {
        var snack = meal("My snack"); snack.id = "snack"; snack.mealType = "Snacks"
        var breakfast = meal("New breakfast"); breakfast.mealType = "Breakfast"
        var proposedSnack = meal("New snack"); proposedSnack.mealType = "Snack"
        let existing = day(0, meals: [meal("My lunch"), snack])
        let draft = day(0, meals: [breakfast, meal("New lunch"), proposedSnack])
        let change = MealPlanEditingRules.mergingDraft([draft], into: [existing], replacingExisting: false)
        try MealPlanEditingRules.validate(change)
        XCTAssertEqual(change.after[0].meals.compactMap { $0.foodItem?.name }, ["New breakfast", "My lunch", "My snack"])
        XCTAssertEqual(change.after[0].meals[1].id, existing.meals[0].id)
        XCTAssertNotEqual(change.after[0].meals[0].id, breakfast.id)
        let noChange = MealPlanEditingRules.mergingDraft([draft], into: change.after, replacingExisting: false)
        XCTAssertTrue(noChange.after.isEmpty)
        let replace = MealPlanEditingRules.mergingDraft([draft], into: [existing], replacingExisting: true)
        XCTAssertEqual(replace.after[0].meals.compactMap { $0.foodItem?.name }, ["New breakfast", "New lunch", "New snack"])
        XCTAssertEqual(replace.reversed.after.first?.meals.map(\.id), existing.meals.map(\.id))
    }

    func testDraftGenerationMapsRequestedWeekWithoutSavingAnything() async throws {
        let priorAI = DIContainer.shared.aiService
        let priorAuth = DIContainer.shared.authService
        let priorRepository = DIContainer.shared.nutritionRepository
        defer {
            DIContainer.shared.aiService = priorAI
            DIContainer.shared.authService = priorAuth
            DIContainer.shared.nutritionRepository = priorRepository
        }
        let ai = MockAIService(), auth = MockAuthService(), repository = MockNutritionRepository()
        auth.currentUserID = "draft-owner"
        let meals = ["Breakfast", "Lunch", "Dinner"].map { type in
            """
            {"mealType":"\(type)","mealName":"Rice bowl","calories":400,"protein":30,"carbs":40,"fats":10,
            "ingredients":["100 g chicken","0.5 cup rice"],"instructions":["Cook and serve"]}
            """
        }.joined(separator: ",")
        let days = (0..<7).map { "{\"dayOffset\":\($0),\"meals\":[\(meals)]}" }.joined(separator: ",")
        ai.mockResult = .success("{\"days\":[\(days)]}")
        DIContainer.shared.aiService = ai; DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repository
        let service = MealPlannerService(recipeService: RecipeService())
        let requested = day(30).date
        let draft = try await service.draftWeekPlan(goals: GoalSettings(), preferredFoods: [], preferredCuisines: [],
                                                   preferredSnacks: [], starting: requested, userID: "draft-owner")
        XCTAssertEqual(draft.first?.date, requested)
        XCTAssertEqual(draft.map { MealPlanEditingRules.dayID($0.date) }, (30..<37).map { day($0).id })
        XCTAssertTrue(repository.batchSavedMealPlans.isEmpty)
        XCTAssertTrue(repository.mockMealPlansByDateString.isEmpty)
        XCTAssertNil(service.lastPlanChange(for: "draft-owner"))
    }

    func testUpcomingCountsWorkingSetsAndStopsAtEndOfBlock() {
        let exercise = RoutineExercise(name: "Press", sets: [ExerciseSet(target: "8", setType: .warmup), ExerciseSet(target: "8")])
        let routine = WorkoutRoutine(userID: "u", name: "A", dateCreated: date, exercises: [exercise])
        var program = WorkoutProgram(userID: "u", name: "Plan", routines: [routine], startDate: date, daysOfWeek: [2], currentProgressIndex: 11)
        let final = TrainingScheduleOverview.upcoming(program, now: day(100).date)
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final[0].workingSets, 1)
        XCTAssertTrue(final[0].isOverdue)
        program.currentProgressIndex = program.totalSlots
        XCTAssertTrue(TrainingScheduleOverview.upcoming(program).isEmpty)
    }

    func testManualRecipePreservesMeasuredIngredientsForShopping() {
        let recipe = Recipe(name: "Chicken", ingredients: ["Chicken"], detailedIngredients: [
            FoodItem(name: "Chicken", calories: 200, protein: 30, carbs: 0, fats: 5, servingSize: "1 portion", servingWeight: 150)
        ], instructions: ["Cook"], nutrition: Nutrition(calories: 200, protein: 30, carbs: 0, fats: 5))
        let ingredient = IngredientLineParser.normalizedIngredient(from: MealPlanEditingRules.ingredients(for: recipe)[0])
        XCTAssertEqual(ingredient.quantity, 150)
        XCTAssertEqual(ingredient.unit, "g")
        XCTAssertEqual(ingredient.name, "Chicken")
    }

    func testGroceryChecksOnlyCarryToTheSameWeekWithEnoughPurchased() {
        let old = GroceryListItem(name: "Chicken", quantity: 300, unit: "g", isCompleted: true, source: "mealPlan", sourcePlanStart: date)
        var current = old; current.id = UUID(); current.isCompleted = false
        func refreshed(_ item: GroceryListItem) -> GroceryListItem {
            GroceryListBuilder.mergeGroceryItems(generatedItems: [item], existingItems: [old])[0]
        }
        XCTAssertTrue(refreshed(current).isCompleted)
        XCTAssertEqual(refreshed(current).id, old.id)
        current.quantity = 250
        XCTAssertTrue(refreshed(current).isCompleted)
        current.quantity = 450
        XCTAssertFalse(refreshed(current).isCompleted)
        current.quantity = 300; current.sourcePlanStart = day(7).date
        XCTAssertFalse(refreshed(current).isCompleted)
        XCTAssertEqual(refreshed(current).id, current.id)
    }

    func testFailedDraftDoesNotSubstituteMadeUpGoalNutrition() async throws {
        let previousAI = DIContainer.shared.aiService, previousAuth = DIContainer.shared.authService
        defer { DIContainer.shared.aiService = previousAI; DIContainer.shared.authService = previousAuth }
        let ai = MockAIService(), auth = MockAuthService()
        ai.mockResult = .success("invalid generation")
        auth.currentUserID = "draft-failure"
        DIContainer.shared.aiService = ai; DIContainer.shared.authService = auth
        let service = MealPlannerService(recipeService: RecipeService())
        do {
            _ = try await service.draftWeekPlan(goals: GoalSettings(), preferredFoods: [], preferredCuisines: [],
                                              preferredSnacks: [], starting: date, userID: "draft-failure")
            XCTFail("An unavailable generator must fail without manufacturing nutritional values from goals")
        } catch { XCTAssertTrue(error is MealPlanEditError) }
    }
}
