import XCTest
@testable import MyFitPlateCore

@MainActor final class MealPlanningWorkspaceTests: XCTestCase {
    private let user = "full-w2-meal-owner"
    private let day = Date(timeIntervalSince1970: 1_790_000_000)
    private func activate() -> MockNutritionRepository {
        let auth = MockAuthService(); auth.currentUserID = user; DIContainer.shared.authService = auth
        let repo = MockNutritionRepository(); DIContainer.shared.nutritionRepository = repo; return repo
    }
    private func food(_ id: String = "rice", calories: Double = 100, grams: Double = 100) -> FoodItem {
        FoodItem(id: id, name: id, calories: calories, protein: 10, carbs: 20, fats: 2, servingSize: "100 g", servingWeight: grams, sodium: 15)
    }
    private func store() -> EditorDraftStore { EditorDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    func testCompositionScalingPreservesComponentsAndScalesOnce() throws {
        _ = activate()
        let value = try MealCompositionRules.food(.init(title: "Breakfast", components: [food(), food("eggs", calories: 200)]), entryID: "meal")
        let scaled = try XCTUnwrap(FoodRepeatRules.adjusting(value, by: 1.5))
        XCTAssertEqual(scaled.calories, 450)
        XCTAssertEqual(scaled.mealComposition?.components.map(\.id), ["rice", "eggs"])
        XCTAssertEqual(scaled.mealComposition?.components[0].calories, 150)
        XCTAssertEqual(scaled.mealComposition?.components[1].sodium, 22.5)
        let restored = try XCTUnwrap(FoodRepeatRules.adjusting(scaled, by: 1 / 1.5))
        XCTAssertEqual(restored.calories, value.calories, accuracy: 0.000001)
        XCTAssertEqual(restored.mealComposition?.components[0].servingWeight, 100)
    }
    func testNestedOrDuplicateCompositionComponentsCannotBeSaved() throws {
        let composed = try MealCompositionRules.food(.init(title: "One", components: [food()]))
        XCTAssertThrowsError(try SavedMealComposition(name: "Nested", components: [composed]).validate())
        XCTAssertThrowsError(try SavedMealComposition(name: "Duplicate", components: [food(), food()]).validate())
    }
    func testPlanningDocumentCASUsesContentAndCanonicalMilliseconds() throws {
        var value = SavedMealComposition(name: "Lunch", components: [food()])
        value.updatedAt = Date(timeIntervalSince1970: 1_790_000_000.123456)
        value.components[0].timestamp = Date(timeIntervalSince1970: 1_790_000_000.987654)
        let canonical = try PlanningDocumentRules.canonicalized(value)
        var changed = canonical; changed.name = "Dinner"; changed.revisionID = UUID().uuidString
        let proposal = MealCompositionSaveProposal(userID: user, expected: value, updated: changed)
        XCTAssertNoThrow(try proposal.applying(to: canonical))
        var conflicting = canonical; conflicting.components[0].calories += 1
        XCTAssertThrowsError(try proposal.applying(to: conflicting))
        var bad = canonical; bad.id = "unsafe/id"
        XCTAssertThrowsError(try bad.validate())
    }
    func testHistoryUndoPreservesUnrelatedNewerMealAndRejectsChangedAffectedMeal() throws {
        var before = MealPlanEditingRules.emptyDay(day), after = MealPlanEditingRules.emptyDay(day)
        before.meals = [.init(id: "one", mealType: "Lunch", foodItem: food())]
        after.meals = []; let command = MealPlanChange(title: "Removed", before: [before], after: [after])
        var current = after; current.meals = [.init(id: "newer", mealType: "Dinner", foodItem: food("newer"))]
        let inverse = try MealPlanHistoryRules.inverse(command, current: [current])
        XCTAssertEqual(Set(inverse.after[0].meals.map(\.id)), ["one", "newer"])
        current.meals.append(.init(id: "one", mealType: "Lunch", foodItem: food("different")))
        XCTAssertThrowsError(try MealPlanHistoryRules.inverse(command, current: [current]))
    }
    func testTemplateRebasesCookingGraphAndRejectsPartialBatchExclusion() throws {
        let first = MealPlanEditingRules.emptyDay(day)
        let meal = PlannedMeal(id: "source", mealType: "Dinner", foodItem: food(), ingredients: ["100 g rice"])
        let batch = try MealPlanCookingRules.configuring(meal, date: first.date, cookingPortions: 4)
        var source = first; source.meals = [batch]
        let next = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: 1, to: first.date)!)
        let change = try MealPlanCookingRules.planningLeftover(from: batch, source: source, relatedDays: [], destination: next, mealType: "Lunch", portions: 1)
        var days = (0..<7).map { MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: $0, to: first.date)!) }
        for value in change.after { days[Calendar.current.dateComponents([.day], from: first.date, to: value.date).day!] = value }
        let template = SavedMealWeekTemplate(name: "Good week", days: days)
        let newDate = Calendar.current.date(byAdding: .day, value: 28, to: first.date)!
        let draft = try MealWeekTemplateRules.draft(template, starting: newDate)
        XCTAssertEqual(draft.days[0].date, newDate)
        XCTAssertEqual(draft.days[0].meals[0].cookingBatch?.cookingDate, newDate)
        let destination = draft.days.map { MealPlanEditingRules.emptyDay($0.date) }
        let accepted = try MealPlanWeekReviewRules.merging(draft, existing: destination, replace: false)
        XCTAssertNotEqual(accepted.after[0].meals[0].id, "source")
        XCTAssertEqual(Set(accepted.after.flatMap(\.meals).compactMap { $0.cookingBatch?.id }).count, 1)
        XCTAssertThrowsError(try MealWeekTemplateRules.draft(template, starting: newDate, excluding: ["source"]))
    }
    func testMeasuredAmountsDoNotInventDensityOrCountMass() throws {
        XCTAssertEqual(try PlannedMealMeasurementRules.multiplier(amount: 150, unit: "g", base: food()), 1.5)
        XCTAssertThrowsError(try PlannedMealMeasurementRules.multiplier(amount: 1, unit: "cup", base: food()))
        XCTAssertThrowsError(try PlannedMealMeasurementRules.multiplier(amount: 1, unit: "g", base: food(grams: 0)))
    }
    func testRetainedDocumentReviewResolvesLostAcknowledgementAndAccountIsolation() async throws {
        let repo = activate(); repo.planningWorkspaceFailureAfterCommit = URLError(.timedOut)
        let value = SavedMealComposition(name: "My meal", components: [food()])
        let proposal = MealCompositionSaveProposal(userID: user, expected: nil, updated: value)
        let directory = store()
        let session = PlanningDocumentSaveSession(userID: user, scope: "test-compositions", proposal: proposal, store: directory)
        await session.save { try await repo.saveSavedMealComposition(userID: self.user, proposal: $0) }
        XCTAssertEqual(session.checkpoint?.proposal.operationID, proposal.operationID)
        XCTAssertEqual(session.checkpoint?.resolution, .pending)
        let restored = PlanningDocumentSaveSession<SavedMealComposition>(userID: user, scope: "test-compositions", store: directory)
        await restored.resolve(cancelPending: true) { try await repo.resolveSavedMealComposition(userID: self.user, proposal: $0, cancelPending: $1) }
        XCTAssertEqual(restored.checkpoint?.resolution, .accepted)
        XCTAssertNil(restored.errorMessage, "Accepted status clears any earlier transport or pending copy")
        let saved = try await repo.fetchSavedMealCompositions(userID: user)
        XCTAssertEqual(saved.count, 1)
        let other = PlanningDocumentSaveSession<SavedMealComposition>(userID: "other-owner", scope: "test-compositions", store: directory)
        XCTAssertNil(other.checkpoint)
    }
    func testStockIdeaCoverageAllocatesLotsOnlyOnceAndLeavesUnknownUncovered() throws {
        let recipe = Recipe(name: "Two rice uses", ingredients: ["100 g rice", "100 g rice", "salt to taste"], instructions: [], nutrition: .init(calories: 400), servings: 1, nutritionBasis: .perServing, ingredientBasis: .perServing)
        var lot = PantryItem(name: "rice", quantity: 150, unit: "g"); lot.quantityVerified = true
        let review = try PantryRecipeFitRules.review(recipe: recipe, servings: 1, stock: [lot], exclusions: [], equipment: [])
        XCTAssertEqual(review.rows.map(\.available), [100, 50, 0])
        XCTAssertNil(review.rows[2].required)
        XCTAssertFalse(review.canUseWithoutShopping)
        XCTAssertEqual(lot.quantity, 150)
    }
}

extension MealPlanningWorkspaceTests {
    func testPartialComponentMicronutrientsRemainUnknownInAggregate() throws {
        var unknown = food("other"); unknown.sodium = nil
        let result = try MealCompositionRules.food(.init(title: "Partial", components: [food(), unknown]))
        XCTAssertNil(result.sodium)
        XCTAssertEqual(result.mealComposition?.components[0].sodium, 15)
    }
    func testScopeRemovalClosesWholeBatchAndPreservesUnrelatedMeal() throws {
        var source = MealPlanEditingRules.emptyDay(day)
        source.meals = [try MealPlanCookingRules.configuring(.init(id: "source", mealType: "Dinner", foodItem: food(), ingredients: ["100 g rice"]), date: source.date, cookingPortions: 4)]
        let next = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: 1, to: source.date)!)
        let allocated = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source, relatedDays: [], destination: next, mealType: "Lunch", portions: 1)
        var days = allocated.after.sorted { $0.date < $1.date }
        let ids = Set(days.flatMap(\.meals).map(\.id))
        days[1].meals.append(.init(id: "keep", mealType: "Snack", foodItem: food("keep")))
        let removal = try MealPlanHistoryRules.removing(mealIDs: ids, from: days, title: "Clear planned meals")
        XCTAssertEqual(removal.after.flatMap(\.meals).map(\.id), ["keep"])
        let inverse = try MealPlanHistoryRules.inverse(removal, current: removal.after)
        XCTAssertEqual(Set(inverse.after.flatMap(\.meals).map(\.id)), ids.union(["keep"]))
    }
    func testLinkedPersonalAndCookingEditsUpdateEveryReplicaAndRejectStaleSource() throws {
        var source = MealPlanEditingRules.emptyDay(day)
        source.meals = [try MealPlanCookingRules.configuring(.init(id: "source", mealType: "Dinner", foodItem: food(), ingredients: ["100 g rice"]), date: source.date, cookingPortions: 4)]
        let next = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: 1, to: source.date)!)
        let allocated = try MealPlanCookingRules.planningLeftover(from: source.meals[0], source: source, relatedDays: [], destination: next, mealType: "Lunch", portions: 1)
        let days = allocated.after.sorted { $0.date < $1.date }; source = days[0]
        var updated = source.meals[0]; updated.portionMultiplier = 1.5; updated.cookingBatch?.totalPortions = 5
        let edit = try MealPlanCookingRules.editingLinked(updated, original: source.meals[0], source: source, relatedDays: days)
        XCTAssertTrue(edit.after.flatMap(\.meals).allSatisfy { $0.cookingBatch?.totalPortions == 5 && $0.cookingBatch?.allocatedPortions == 2.5 })
        XCTAssertEqual(MealPlanCookingRules.changedCookingDefinitions(in: edit), [source.meals[0].cookingBatch!.id])
        var stale = days; stale[0].meals[0].foodItem?.calories += 1
        XCTAssertThrowsError(try MealPlanCookingRules.editingLinked(updated, original: source.meals[0], source: source, relatedDays: stale))
    }
    func testAlternativesHaveDistinctIdentitiesAndCheckWholeWeekBudget() throws {
        var days = (0..<7).map { MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: $0, to: day)!) }
        for index in days.indices {
            var meal = PlannedMeal(id: "old-\(index)", mealType: "Dinner", foodItem: food("old", calories: 600))
            meal.planningEvidence = try PlannedMealEvidence(profile: .init(costPerServing: 1, reviewedAt: day), meal: meal)
            days[index].meals = [meal]
        }
        func recipe(_ name: String, cost: Double) throws -> Recipe {
            var value = Recipe(name: name, ingredients: ["100 g rice"], instructions: [], nutrition: .init(calories: 600), servings: 1, nutritionBasis: .perServing)
            var profile = RecipePlanningProfile(costPerServing: cost, reviewedAt: day)
            profile.contentFingerprint = try RecipePlanningProfile.fingerprint(value); value.planningProfile = profile; return value
        }
        var c = MealPlanConstraints(calories: 600, protein: 0, carbs: 0, fats: 0); c.enforceProtein = false; c.weeklyBudget = 20
        let alternatives = MealAlternativeRules.candidates(recipes: [try recipe("Affordable bowl", cost: 5), try recipe("Expensive bowl", cost: 50)], day: days[0], replacing: days[0].meals[0], constraints: c, week: days)
        XCTAssertEqual(Set(alternatives.map(\.id)).count, alternatives.count)
        XCTAssertTrue(alternatives.contains { $0.meal.foodItem?.name == "Affordable bowl" && $0.canUse })
        XCTAssertTrue(alternatives.contains { $0.meal.foodItem?.name == "Expensive bowl" && !$0.canUse })
    }
    func testWeekAndHistorySessionsHaveSeparateStableSetScopes() throws {
        _ = activate(); let storage = store()
        var day = MealPlanEditingRules.emptyDay(self.day); day.meals = [.init(id: "meal", mealType: "Dinner", foodItem: food())]
        var draft = MealPlanWeekDraft(days: [day], title: "Keep week"); draft.lockedMealIDs = ["c", "a", "b"]; draft.existingLockedMealIDs = ["b", "c", "a"]
        let encoded = try JSONEncoder().encode(draft), decoded = try JSONDecoder().decode(MealPlanWeekDraft.self, from: encoded)
        XCTAssertEqual(try PlanFingerprint.make(draft), try PlanFingerprint.make(decoded))
        let week = MealPlanWeekSaveSession(userID: user, draft: draft, store: storage)
        let history = MealPlanWeekSaveSession(userID: user, draft: .init(days: [day], title: "Undo one meal"), store: storage, scope: "meal-plan-history-undo")
        XCTAssertEqual(week.checkpoint?.draft.title, "Keep week")
        XCTAssertEqual(history.checkpoint?.draft.title, "Undo one meal")
    }
    func testActualPlannedDraftKeepsOccurrenceAndRejectsOlderEditor() {
        _ = activate(); let storage = store()
        let original = PlannedMealSaveSession(userID: user, date: day, meals: [Meal(name: "Dinner", foodItems: [food("one"), food("two")])], store: storage)
        var changed = food("one"); changed.calories = 160
        XCTAssertTrue(original.updateFood(changed, entryID: "one"))
        let resumed = PlannedMealSaveSession(userID: user, date: day, meals: [], store: storage)
        XCTAssertTrue(resumed.restoredReview)
        XCTAssertTrue(resumed.omitFood(entryID: "two"))
        changed.calories = 170
        XCTAssertFalse(original.updateFood(changed, entryID: "one"))
        XCTAssertEqual(resumed.checkpoint.meals[0].foodItems.map(\.id), ["one"])
        XCTAssertEqual(resumed.checkpoint.meals[0].foodItems[0].calories, 160)
    }
}

extension MealPlanningWorkspaceTests {
    func testStoredPlanCalendarIdentityCannotRedirectAfterTravel() throws {
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let date = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        let original = MealPlanDay(id: "2026-11-02", date: date, meals: [.init(id: "same-legacy-id", mealType: "Dinner", foodItem: food())])
        var updated = original; updated.meals[0].portionMultiplier = 2
        let previous = NSTimeZone.default; defer { NSTimeZone.default = previous }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(MealPlanEditingRules.dayID(original.date), "2026-11-01")
        XCTAssertThrowsError(try MealPlanEditingRules.validate(.init(title: "Travel edit", before: [original], after: [updated]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("time zone"))
        }
        XCTAssertEqual(original.id, "2026-11-02")
        XCTAssertEqual(original.meals[0].plannedFood?.calories, 100)
    }
}

extension MealPlanningWorkspaceTests {
    func testSavedWeekCopyUsesFrozenCivilKeysAcrossTimeZonesWithoutRewritingSource() throws {
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let start = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        var days = (0..<7).map { MealPlanEditingRules.emptyDay(newYork.date(byAdding: .day, value: $0, to: start)!, calendar: newYork) }
        days[0].meals = [.init(id: "source", mealType: "Dinner", foodItem: food())]
        let value = SavedMealWeekTemplate(name: "Home week", days: days)
        let sourceHash = try PlanFingerprint.make(value)
        let previous = NSTimeZone.default; defer { NSTimeZone.default = previous }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let target = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let draft = try MealWeekTemplateRules.draft(value, starting: target)
        XCTAssertEqual(draft.days.map(\.id), ["2026-12-01", "2026-12-02", "2026-12-03", "2026-12-04", "2026-12-05", "2026-12-06", "2026-12-07"])
        XCTAssertEqual(draft.days[0].meals[0].foodItem?.calories, 100)
        XCTAssertEqual(try PlanFingerprint.make(value), sourceHash)
    }
}

extension MealPlanningWorkspaceTests {
    func testPendingTemplateCanRestoreCheckStatusAndCancelAfterTravel() async throws {
        let repo = activate()
        let previous = NSTimeZone.default; defer { NSTimeZone.default = previous }
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        let start = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        var days = (0..<7).map { MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: $0, to: start)!) }
        days[0].meals = [.init(id: "home-meal", mealType: "Dinner", foodItem: food())]
        let proposal = MealWeekTemplateSaveProposal(userID: user, expected: nil, updated: SavedMealWeekTemplate(name: "Home week", days: days))
        let directory = store()
        let original = PlanningDocumentSaveSession(userID: user, scope: "travel-template", proposal: proposal, store: directory)
        XCTAssertNotNil(original.checkpoint)
        let frozenFingerprint = try proposal.fingerprint()
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertThrowsError(try proposal.validate())
        XCTAssertNoThrow(try proposal.updated.validateStoredSnapshot())
        XCTAssertEqual(try proposal.fingerprint(), frozenFingerprint)
        let restored = PlanningDocumentSaveSession<SavedMealWeekTemplate>(userID: user, scope: "travel-template", store: directory)
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.checkpoint?.proposal.operationID, proposal.operationID)
        await restored.resolve(cancelPending: false) { try await repo.resolveSavedMealWeekTemplate(userID: self.user, proposal: $0, cancelPending: $1) }
        XCTAssertEqual(restored.checkpoint?.resolution, .pending)
        XCTAssertNotNil(restored.errorMessage)
        await restored.resolve(cancelPending: true) { try await repo.resolveSavedMealWeekTemplate(userID: self.user, proposal: $0, cancelPending: $1) }
        XCTAssertEqual(restored.checkpoint?.resolution, .cancelled)
        XCTAssertNil(restored.errorMessage, "Confirmed cancellation clears the previous pending retry message")
        XCTAssertTrue(restored.finish())
        let templates = try await repo.fetchSavedMealWeekTemplates(userID: user)
        XCTAssertTrue(templates.isEmpty)
    }
}
