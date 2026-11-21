import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlanWeekAdversarialTests: XCTestCase {
    private var date: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)) }
    private var constraints: MealPlanConstraints { .init(calories: 2_000, protein: 140, carbs: 200, fats: 60) }
    private func week() -> [MealPlanDay] {
        (0..<7).map { offset in
            var day = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: offset, to: date)!)
            day.meals = MealPlanEditingRules.mealTypes.enumerated().map { slot, name in
                PlannedMeal(id: "meal-\(offset)-\(slot)", mealType: name,
                    foodItem: FoodItem(id: "food-\(offset)-\(slot)", name: "Meal \(offset)-\(slot)",
                        calories: 500, protein: 35, carbs: 50, fats: 15, servingSize: "1 portion"))
            }
            return day
        }
    }
    private func emptyWeek() -> [MealPlanDay] { week().map { MealPlanEditingRules.emptyDay($0.date) } }
    private func lockedExistingDraft() -> (MealPlanWeekDraft, [MealPlanDay]) {
        let days = week()
        var draft = MealPlanWeekDraft(days: days, title: "Adversarial review", constraints: constraints, preserveCookingBatches: true)
        draft.lockedMealIDs = Set(days[0].meals.map(\.id)); draft.existingLockedMealIDs = draft.lockedMealIDs
        var existing = emptyWeek(); existing[0] = days[0]
        return (draft, existing)
    }

    func testStaleSameIdentityEditorCannotOverwriteOrDiscardSubmittedCheckpoint() async throws {
        let previousAuth = DIContainer.shared.authService
        let previousRepository = DIContainer.shared.nutritionRepository
        let auth = MockAuthService(); auth.currentUserID = "week-adversarial"
        let repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        defer { DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let defaultsName = "week-adversarial-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let planner = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        let draft = MealPlanWeekDraft(days: week(), title: "Exact pending week", preserveCookingBatches: true)
        let first = MealPlanWeekSaveSession(userID: auth.currentUserID, draft: draft, store: store)
        let stale = MealPlanWeekSaveSession(userID: auth.currentUserID, store: store)
        let staleCloser = MealPlanWeekSaveSession(userID: auth.currentUserID, store: store)
        let change = try MealPlanWeekReviewRules.merging(draft, existing: emptyWeek(), replace: false)
        XCTAssertTrue(first.prepare(change))
        repository.mealPlanEditError = CocoaError(.fileWriteUnknown)
        let accepted = await first.save(using: planner)
        XCTAssertFalse(accepted); XCTAssertTrue(first.checkpoint?.submitted == true)
        var oldDraft = draft; oldDraft.title = "Stale overwrite attempt"
        XCTAssertFalse(stale.updateDraft(oldDraft))
        XCTAssertFalse(staleCloser.closeResolvedOrUnsubmitted())
        let persisted = try XCTUnwrap(store.load(MealPlanWeekCheckpoint.self, userID: "week-adversarial", scope: MealPlanWeekSaveSession.scope)?.value)
        XCTAssertTrue(persisted.submitted)
        XCTAssertEqual(persisted.change?.id, change.id)
        XCTAssertEqual(persisted.draft.title, "Exact pending week")
        XCTAssertTrue(repository.appliedMealPlanChangeIDs.isEmpty)
    }

    func testConstrainedMergeGuardsFullyLockedDayAndConcurrentEditRejectsAllWrites() async throws {
        let (draft, existing) = lockedExistingDraft()
        let change = try MealPlanWeekReviewRules.merging(draft, existing: existing, replace: false)
        XCTAssertEqual(change.before.count, 7, "Unchanged locked days are part of the reviewed week precondition")
        let original = try XCTUnwrap(change.before.first { $0.id == existing[0].id })
        let after = try XCTUnwrap(change.after.first { $0.id == original.id })
        XCTAssertEqual(try PlanFingerprint.make(original.meals), try PlanFingerprint.make(after.meals))
        let repository = MockNutritionRepository()
        repository.mockMealPlansByDateString = Dictionary(uniqueKeysWithValues: existing.filter { !$0.meals.isEmpty }.map { ($0.id, $0) })
        var otherDeviceEdit = original; otherDeviceEdit.meals[0].foodItem?.calories = 900
        repository.mockMealPlansByDateString[original.id] = otherDeviceEdit
        do {
            try await repository.applyMealPlanChange(userID: "owner", change: change)
            XCTFail("A changed locked day must invalidate the entire reviewed save")
        } catch {}
        XCTAssertEqual(repository.mockMealPlansByDateString.count, 1)
        XCTAssertEqual(repository.mockMealPlansByDateString[original.id]?.meals[0].foodItem?.calories, 900)
        XCTAssertTrue(repository.appliedMealPlanChangeIDs.isEmpty)
    }

    func testNewLockedCandidateCannotDisappearBehindNewOccupiedSlot() throws {
        let days = week()
        let chosen = days[0].meals[0]
        var draft = MealPlanWeekDraft(days: days, title: "Keep this choice", preserveCookingBatches: true)
        draft.lockedMealIDs = [chosen.id]; draft.existingLockedMealIDs = []
        var existing = emptyWeek()
        var intruder = chosen; intruder.id = "other-device-choice"; intruder.foodItem?.name = "Another breakfast"
        existing[0].meals = [intruder]
        XCTAssertThrowsError(try MealPlanWeekReviewRules.merging(draft, existing: existing, replace: false))
    }

    func testExistingLockedContentChangeRequiresExplicitNewReview() throws {
        let (draft, original) = lockedExistingDraft()
        var changed = original
        changed[0].meals[0].portionMultiplier = 1.5
        XCTAssertThrowsError(try MealPlanWeekReviewRules.merging(draft, existing: changed, replace: false))
        changed = original; changed[0].meals[0].foodItem?.name = "Different ingredients"
        XCTAssertThrowsError(try MealPlanWeekReviewRules.merging(draft, existing: changed, replace: false))
    }

    func testDeliberatelyRemovedLockedMealIsNotRecreatedOnReopen() throws {
        let (draft, original) = lockedExistingDraft()
        var removed = original; removed[0].meals.removeFirst()
        XCTAssertThrowsError(try MealPlanWeekReviewRules.merging(draft, existing: removed, replace: false))
    }

    func testEligibleRecipeAfterEightyExcludedRecordsIsStillConsidered() throws {
        func recipe(_ index: Int, diet: PlanningDiet) throws -> Recipe {
            var value = Recipe(id: "candidate-\(index)", name: "Recipe \(index)", ingredients: ["100 g beans", "100 g rice"],
                instructions: ["Cook rice. Mix beans."], nutrition: Nutrition(calories: 500, protein: 35, carbs: 50, fats: 15),
                servings: 1, nutritionBasis: .perServing)
            value.planningProfile = RecipePlanningProfile(diet: diet, reviewedAt: date, contentFingerprint: try RecipePlanningProfile.fingerprint(value))
            return value
        }
        var request = constraints; request.diet = .vegan
        let excluded = try (0..<80).map { try recipe($0, diet: .unrestricted) }
        let eligible = try recipe(80, diet: .vegan)
        let planned = try SavedRecipeWeekPlanner.make(recipes: excluded + [eligible], constraints: request, starting: date)
        XCTAssertEqual(planned.count, 7)
        XCTAssertTrue(planned.flatMap(\.meals).allSatisfy { $0.recipeID == eligible.id })
        XCTAssertTrue(MealPlanConstraintRules.report(days: planned, constraints: request).canSave)
    }
}
