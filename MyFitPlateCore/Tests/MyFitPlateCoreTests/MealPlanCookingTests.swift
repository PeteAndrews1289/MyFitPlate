import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlanCookingTests: XCTestCase {
    private var date: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_792_000_000)) }
    private func meal() -> PlannedMeal {
        PlannedMeal(id: "rice", mealType: "Dinner", foodItem: FoodItem(id: "food-rice", name: "Rice bowl",
            calories: 400, protein: 25, carbs: 50, fats: 10, servingSize: "1 bowl", servingWeight: 300),
            ingredients: ["100 g rice"], instructions: "1. Rinse rice.\n2. Cook rice.\n3. Serve.")
    }
    private func day(_ offset: Int, _ meals: [PlannedMeal] = []) -> MealPlanDay {
        var value = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: offset, to: date)!)
        value.meals = meals; return value
    }
    private func initialBatch() throws -> MealPlanDay {
        day(0, [try MealPlanCookingRules.configuring(meal(), date: date, cookingPortions: 4)])
    }

    func testHouseholdBatchKeepsPersonalNutritionAndBuysWholeBatchOnce() throws {
        let source = try initialBatch()
        XCTAssertEqual(source.meals[0].plannedFood?.calories, 400)
        XCTAssertEqual(source.meals[0].plannedIngredients[0].quantity, 100)
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source, day(1)], destination: day(1), mealType: "Lunch", portions: 1)
        let groceries = GroceryListBuilder.makeGroceryList(from: change.after, starting: date, unitSystem: .metric)
        XCTAssertEqual(groceries.count, 1); XCTAssertEqual(groceries[0].quantity, 400)
        XCTAssertEqual(change.after[1].meals[0].plannedFood?.calories, 400)
        XCTAssertEqual(change.after[0].meals[0].cookingBatch?.unallocatedPortions, 2)
        XCTAssertEqual(change.after[0].meals[0].cookingBatch, change.after[1].meals[0].cookingBatch)
        let prep = MealPrepService(); prep.aggregate(days: change.after, starting: date)
        XCTAssertEqual(prep.bulkIngredients.values.flatMap { $0 }.first?.quantity, 400)
        XCTAssertEqual(prep.prepSteps.count, 3)
    }

    func testLegacyRoundTripAndIndependentCopyDoNotInferBatches() throws {
        let source = day(0, [meal()]); let copied = MealPlanEditingRules.duplicate(meal())
        let decoded = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(source.meals[0]))
        XCTAssertNil(decoded.cookingBatch)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [source, day(1, [copied])], unitSystem: .metric).first?.quantity, 200)
        let batchCopy = MealPlanEditingRules.duplicate(try initialBatch().meals[0])
        XCTAssertNil(batchCopy.cookingBatch)
        XCTAssertEqual(batchCopy.plannedFood?.calories, 400)
        XCTAssertEqual(batchCopy.plannedIngredients[0].quantity, 100)
    }

    func testLeftoverNextShoppingWindowDoesNotPurchaseCookedIngredientsAgain() throws {
        let source = try initialBatch()
        let destination = day(7)
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source, destination], destination: destination, mealType: "Lunch", portions: 1)
        XCTAssertTrue(GroceryListBuilder.makeGroceryList(from: [change.after[1]], starting: destination.date, unitSystem: .metric).isEmpty)
        XCTAssertEqual(change.after[1].meals[0].plannedFood?.calories, 400)
    }

    func testRejectsOverAllocationStaleSnapshotAndMissingMemberDay() throws {
        let source = try initialBatch()
        XCTAssertThrowsError(try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 4))
        let first = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        XCTAssertThrowsError(try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: first.after[0],
            relatedDays: first.after, destination: day(2), mealType: "Lunch", portions: 1))
        XCTAssertThrowsError(try MealPlanCookingRules.planningLeftover(from: first.after[0].meals[0], source: first.after[0],
            relatedDays: [], destination: day(2), mealType: "Lunch", portions: 1))
        XCTAssertThrowsError(try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(8), mealType: "Lunch", portions: 1))
    }

    func testDeletingOrReplacingLinkedMealRejectsPartialChange() throws {
        let source = try initialBatch()
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        let origin = change.after[0]
        XCTAssertThrowsError(try MealPlanEditingRules.validate(MealPlanChange(title: "Remove", before: [origin], after: [day(0)])))
        var replacement = meal(); replacement.id = "new-meal"
        XCTAssertThrowsError(try MealPlanEditingRules.validate(MealPlanChange(title: "Replace", before: [origin], after: [day(0, [replacement])])))
        XCTAssertThrowsError(try MealPlanEditingRules.transferring(origin.meals, from: origin, to: [day(2)], moving: true))
        var modified = origin.meals[0]; modified.portionMultiplier = 2
        XCTAssertThrowsError(try MealPlanEditingRules.validate(MealPlanEditingRules.replacing(modified, in: origin)))
        // Whole-batch plan removal is allowed when every allocation is included.
        try MealPlanEditingRules.validate(MealPlanChange(title: "Remove batch", before: change.after, after: [day(0), day(1)]))
    }

    func testBatchCookingRequiresEnoughHouseholdQuantityAndRetainsRecipeSnapshot() throws {
        XCTAssertThrowsError(try MealPlanCookingRules.configuring(meal(), date: date, cookingPortions: 0.5))
        var largePortion = meal(); largePortion.portionMultiplier = 1.5
        let batch = try MealPlanCookingRules.configuring(largePortion, date: date, cookingPortions: 4)
        XCTAssertEqual(batch.plannedFood?.calories, 600)
        XCTAssertEqual(batch.cookingBatch?.ingredientsPerPortion[0].quantity, 100)
        XCTAssertEqual(batch.cookingBatch?.allocatedPortions, 1.5)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [day(0, [batch])], unitSystem: .metric).first?.quantity, 400)
        let restored = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(batch))
        XCTAssertEqual(restored.cookingBatch, batch.cookingBatch)
    }

    func testCookingCheckpointPersistsTimerAndStepsAndIsolatesChangedRecipe() throws {
        let auth = MockAuthService(); auth.currentUserID = "cooking-test"
        DIContainer.shared.authService = auth
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let id = MealCookingCheckpointSession.contextID(days: [day(0, [meal()])])
        let session = MealCookingCheckpointSession(userID: auth.currentUserID, contextID: id, store: store)
        XCTAssertTrue(session.toggleStep(0, stepCount: 3))
        XCTAssertTrue(session.startTimer(minutes: 2, now: date))
        let restored = MealCookingCheckpointSession(userID: auth.currentUserID, contextID: id, store: store)
        XCTAssertTrue(restored.restored); XCTAssertEqual(restored.checkpoint.completedStepIndexes, [0])
        XCTAssertEqual(restored.remaining(now: date.addingTimeInterval(30)), 90)
        XCTAssertTrue(restored.pauseTimer(now: date.addingTimeInterval(30)))
        let paused = MealCookingCheckpointSession(userID: auth.currentUserID, contextID: id, store: store)
        XCTAssertFalse(paused.isRunning); XCTAssertEqual(paused.remaining(now: date.addingTimeInterval(900)), 90)
        XCTAssertTrue(paused.resumeTimer(now: date.addingTimeInterval(900)))
        XCTAssertEqual(paused.remaining(now: date.addingTimeInterval(930)), 60)
        XCTAssertTrue(paused.finishExpiredTimer(now: date.addingTimeInterval(1000)))
        XCTAssertTrue(paused.checkpoint.timerFinished)
        var changed = meal(); changed.instructions = "Different instructions"
        let changedID = MealCookingCheckpointSession.contextID(days: [day(0, [changed])])
        XCTAssertNotEqual(id, changedID)
        let different = MealCookingCheckpointSession(userID: auth.currentUserID, contextID: changedID, store: store)
        XCTAssertTrue(different.checkpoint.completedStepIndexes.isEmpty)
        auth.currentUserID = "other-account"
        XCTAssertFalse(restored.toggleStep(1, stepCount: 3))
        let other = MealCookingCheckpointSession(userID: auth.currentUserID, contextID: id, store: store)
        XCTAssertTrue(other.checkpoint.completedStepIndexes.isEmpty)
    }
    func testRemovingLeftoverReleasesCapacityAndKeepsBatchIngredients() throws {
        let source = try initialBatch()
        let linked = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        let leftoverDay = linked.after[1]
        let removed = try MealPlanCookingRules.removing(meal: leftoverDay.meals[0], source: leftoverDay, relatedDays: linked.after)
        XCTAssertTrue(removed.after[1].meals.isEmpty)
        XCTAssertEqual(removed.after[0].meals[0].cookingBatch?.unallocatedPortions, 3)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: removed.after, starting: date, unitSystem: .metric).first?.quantity, 400)
        try MealPlanEditingRules.validate(removed.reversed)
    }

    func testRemovingSoleCookingWeekAnchorRejectsCrossWeekOrphan() throws {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: date)!
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.end)!
        let nextDay = week.end
        var source = MealPlanEditingRules.emptyDay(lastDay)
        source.meals = [try MealPlanCookingRules.configuring(meal(), date: lastDay, cookingPortions: 4)]
        let destination = MealPlanEditingRules.emptyDay(nextDay)
        let linked = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: destination, mealType: "Lunch", portions: 1)
        XCTAssertThrowsError(try MealPlanCookingRules.removing(meal: linked.after[0].meals[0], source: linked.after[0], relatedDays: linked.after))
    }

    func testCookingCheckpointDoesNotFollowSameMealIntoAnotherWeek() {
        let first = MealCookingCheckpointSession.contextID(days: [day(0, [meal()])], starting: date)
        let nextDate = day(7).date
        let moved = MealCookingCheckpointSession.contextID(days: [day(7, [meal()])], starting: nextDate)
        XCTAssertNotEqual(first, moved)
    }

    func testSameDayLeftoverRejectsConflictingDestinationSnapshot() throws {
        let source = try initialBatch()
        var staleDestination = source
        staleDestination.meals.append(MealPlanEditingRules.duplicate(meal()))
        XCTAssertThrowsError(try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: staleDestination, mealType: "Lunch", portions: 1))
        let sameDay = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: source, mealType: "Lunch", portions: 1)
        XCTAssertEqual(sameDay.after.count, 1)
        XCTAssertEqual(sameDay.after[0].meals.count, 2)
    }

    func testFrozenLeftoverReviewSurvivesReopenAndCannotBeReplacedByAnotherEditor() throws {
        let auth = MockAuthService(); auth.currentUserID = "leftover-test"
        DIContainer.shared.authService = auth
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let firstEditor = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        let secondEditor = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        let source = try initialBatch()
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        let proposal = MealPlanLeftoverCheckpoint(change: change, sourceMealID: source.meals[0].id,
            destinationDate: day(1).date, mealType: "Lunch", portions: 1)
        XCTAssertTrue(firstEditor.prepare(proposal))
        var competing = proposal; competing.change.id = UUID()
        XCTAssertFalse(secondEditor.prepare(competing))
        XCTAssertEqual(secondEditor.checkpoint?.change.id, change.id)
        let reopened = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(reopened.restored)
        XCTAssertEqual(reopened.checkpoint?.change.id, change.id)
        XCTAssertEqual(reopened.checkpoint?.change.after.last?.meals.last?.id, change.after.last?.meals.last?.id)
        auth.currentUserID = "different-account"
        XCTAssertFalse(reopened.changeUnsubmittedReview())
    }

    func testLostAcknowledgementThenLaterEditResolvesPermanentReceiptWithoutDuplicate() async throws {
        let auth = MockAuthService(); auth.currentUserID = "leftover-receipt"
        let repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let defaultsName = "leftover-receipt-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let planner = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        let source = try initialBatch()
        repository.mockMealPlansByDateString[source.id] = source
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        let session = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.prepare(MealPlanLeftoverCheckpoint(change: change, sourceMealID: source.meals[0].id,
            destinationDate: day(1).date, mealType: "Lunch", portions: 1)))
        repository.mealPlanChangeFailureAfterCommit = NSError(domain: "lost-ack", code: 1)
        let acknowledged = await session.save(using: planner)
        XCTAssertFalse(acknowledged)
        XCTAssertEqual(repository.appliedMealPlanChangeIDs, [change.id])
        var later = try XCTUnwrap(repository.mockMealPlansByDateString[day(1).id])
        later.meals.append(MealPlanEditingRules.duplicate(meal()))
        repository.mockMealPlansByDateString[later.id] = later
        let reopened = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        await reopened.checkStatus(using: repository)
        XCTAssertEqual(reopened.checkpoint?.accepted, true)
        XCTAssertEqual(repository.appliedMealPlanChangeIDs, [change.id])
        XCTAssertEqual(repository.mockMealPlansByDateString[later.id]?.meals.count, 2)
        XCTAssertTrue(reopened.finishAcceptedReview())
        XCTAssertNil(MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store).checkpoint)
    }

    func testCancelledLeftoverSaveCannotApplyAfterReopen() async throws {
        let auth = MockAuthService(); auth.currentUserID = "leftover-cancel"
        let repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let source = try initialBatch()
        let change = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source,
            relatedDays: [source], destination: day(1), mealType: "Lunch", portions: 1)
        let session = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        XCTAssertTrue(session.prepare(MealPlanLeftoverCheckpoint(change: change, sourceMealID: source.meals[0].id,
            destinationDate: day(1).date, mealType: "Lunch", portions: 1)))
        await session.checkStatus(using: repository, cancelPending: true)
        XCTAssertEqual(session.checkpoint?.cancelled, true)
        let reopened = MealPlanLeftoverSaveSession(userID: auth.currentUserID, store: store)
        let accepted = await reopened.save(using: MealPlannerService(recipeService: RecipeService()))
        XCTAssertFalse(accepted)
        XCTAssertTrue(repository.appliedMealPlanChangeIDs.isEmpty)
        XCTAssertTrue(reopened.finishAcceptedReview())
    }

}
