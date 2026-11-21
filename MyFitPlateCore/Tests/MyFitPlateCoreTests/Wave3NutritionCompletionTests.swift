import XCTest
@testable import MyFitPlateCore

final class Wave3NutritionCompletionTests: XCTestCase {
    private let owner = "nutrition-completion-owner"
    private var day: Date { Calendar.current.startOfDay(for: Date().addingTimeInterval(-864_000)) }
    private func date(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: day)! }
    private func log(_ offset: Int) -> DailyLog {
        DailyLog(id: DiaryDayContext.dayKey(for: date(offset)), date: date(offset),
            meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "rice-\(offset)", name: "Rice", calories: 200, protein: 5, carbs: 40, fats: 1)])])
    }
    private func accepted(_ value: DailyLog, status: NutritionDayStatus = .complete) throws -> DailyLog {
        var result = value
        result.nutritionDayStatus = status
        result.nutritionDayReview = try .init(ownerID: owner, day: XCTUnwrap(DiaryDayContext(userID: owner, date: value.date, dayKey: value.id)), status: status, log: value)
        return result
    }
    private func recipe(minutes: Int? = 20, equipment: [String] = ["stove"]) throws -> Recipe {
        var value = Recipe(id: "rice-beans", name: "Rice and beans", ingredients: ["100 g rice", "200 g beans"],
            instructions: ["Cook and combine."], nutrition: .init(calories: 500, protein: 40, carbs: 60, fats: 10),
            servings: 1, nutritionBasis: .perServing)
        value.planningProfile = .init(prepMinutes: minutes, equipment: equipment, diet: .vegan, costPerServing: 2,
            reviewedAt: day, contentFingerprint: try RecipePlanningProfile.fingerprint(value))
        return value
    }
    private func constraints() -> MealPlanConstraints {
        var c = MealPlanConstraints(calories: 2_000, protein: 120, carbs: 250, fats: 60)
        c.practicalWeek = .init(mealTypes: ["Lunch"], days: (0..<7).map { .init(offset: $0, cookingMinutes: $0 == 2 ? 30 : 0) }, repeatMeals: false, usePreparedStock: false)
        return c
    }
    func testPreferenceCheckpointRestoresRawTypingAndOriginalRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EditorDraftStore(directory: root)
        var draft = FoodPreferencesDraft.defaults; draft.proteins = ["Tempeh"]
        let checkpoint = FoodPreferencesEditorCheckpoint(revision: .init(userID: owner, baseline: .defaults), draft: draft,
            exclusionsText: " peanut, unfinished ", ingredientPattern: .vegan, customChoices: ["Cuisines": "Ethiop"])
        try store.save(checkpoint, userID: owner, scope: FoodPreferencesEditorCheckpoint.scope)
        let restored = try XCTUnwrap(store.load(FoodPreferencesEditorCheckpoint.self, userID: owner, scope: FoodPreferencesEditorCheckpoint.scope)?.value)
        XCTAssertEqual(restored, checkpoint)
        XCTAssertEqual(restored.revision.baseline, .defaults)
        XCTAssertTrue(restored.canRestore(for: owner)); XCTAssertFalse(restored.canRestore(for: "other"))
        XCTAssertTrue(restored.requiresConflictReview(current: draft))
        XCTAssertNil(try store.load(FoodPreferencesEditorCheckpoint.self, userID: "other", scope: FoodPreferencesEditorCheckpoint.scope))
    }
    func testRemovingSubmittedPreferenceCheckpointCannotDeleteNewerEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EditorDraftStore(directory: root)
        var first = FoodPreferencesEditorCheckpoint(revision: .init(userID: owner, baseline: .defaults), draft: .defaults,
            exclusionsText: "", ingredientPattern: .unrestricted)
        let fingerprint = try PlanFingerprint.make(first)
        first.customChoices = ["Cuisines": "New typed choice"]
        try store.save(first, userID: owner, scope: FoodPreferencesEditorCheckpoint.scope)
        XCTAssertFalse(try store.removeIfUnchanged(FoodPreferencesEditorCheckpoint.self, userID: owner, scope: FoodPreferencesEditorCheckpoint.scope, fingerprint: fingerprint))
        XCTAssertEqual(try store.load(FoodPreferencesEditorCheckpoint.self, userID: owner, scope: FoodPreferencesEditorCheckpoint.scope)?.value, first)
    }
    func testBatchRetryKeepsAcceptedDatesAndRejectsChangedIntake() throws {
        let a = log(0), b = log(1), c = log(2)
        var review = try NutritionDayBatchReview(ownerID: owner, status: .complete, logs: [a, b, c])
        review.mark(a.id!, result: .saving)
        var changed = b; changed.meals[0].foodItems[0].calories = 450
        try review.reconcile(with: [accepted(a), changed, c], currentOwner: owner)
        XCTAssertEqual(review.entries.map(\.result), [.saved, .changed, .retry])
        XCTAssertEqual(review.unresolvedCount, 2)
        review.mark(a.id!, result: .retry)
        XCTAssertEqual(review.entries[0].result, .saved)
        try review.reviewLatest(changed, currentOwner: owner)
        XCTAssertEqual(review.entries[1].result, .awaitingReview)
        XCTAssertEqual(review.entries[1].reviewedLog.meals[0].foodItems[0].calories, 450)
    }
    func testBatchConflictIncludesOtherReviewAndAccountSwitch() throws {
        let a = log(0)
        var review = try NutritionDayBatchReview(ownerID: owner, status: .complete, logs: [a])
        try review.reconcile(with: [accepted(a, status: .partial)], currentOwner: owner)
        XCTAssertEqual(review.entries.first?.result, .changed)
        XCTAssertThrowsError(try review.reconcile(with: [a], currentOwner: "other"))
        XCTAssertThrowsError(try review.reviewLatest(a, currentOwner: "other"))
        XCTAssertThrowsError(try NutritionDayBatchReview(ownerID: owner, status: .complete, logs: [a, a]))
        XCTAssertThrowsError(try NutritionDayBatchReview(ownerID: owner, status: .complete, logs: [log(20)]))
    }
    func testInterruptedBatchRoundTripsAndMissingDatesStayUnconfirmed() throws {
        let a = log(0), empty = DailyLog(id: DiaryDayContext.dayKey(for: date(1)), date: date(1), meals: [])
        var value = try NutritionDayBatchReview(ownerID: owner, status: .complete, logs: [a, empty])
        value.mark(a.id!, result: .saving)
        var restored = try JSONDecoder().decode(NutritionDayBatchReview.self, from: JSONEncoder().encode(value))
        try restored.reconcile(with: [], currentOwner: owner)
        XCTAssertEqual(restored.entries.map(\.result), [.retry, .retry])
        XCTAssertNil(restored.entries[1].reviewedLog.nutritionDayReview)
        XCTAssertEqual(NutritionDayEvidence.status(of: restored.entries[1].reviewedLog), .unknown)
    }
    func testPartialPlannerKeepsUsableMealsAndRequiresExplicitScopeRepair() throws {
        let c = constraints(), source = try recipe()
        let original = try PlanFingerprint.make(source)
        XCTAssertThrowsError(try PracticalMealWeekPlanner.make(recipes: [source], constraints: c, starting: day, locked: [], stock: [], savedPlans: []))
        let days = try PracticalMealWeekPlanner.make(recipes: [source], constraints: c, starting: day, locked: [], stock: [], savedPlans: [], allowPartialReview: true)
        XCTAssertEqual(days.flatMap(\.meals).count, 1)
        XCTAssertEqual(days[2].meals.first?.mealType, "Lunch")
        let missing = MealPlanningPreflight.missingSlots(days: days, constraints: c)
        XCTAssertEqual(missing.count, 6)
        XCTAssertFalse(MealPlanConstraintRules.report(days: days, constraints: c).canSave)
        var repaired = c
        for slot in missing { repaired = try MealPlanningPreflight.leavingOpen(slot, in: repaired) }
        XCTAssertTrue(MealPlanConstraintRules.report(days: days, constraints: repaired).canSave)
        XCTAssertEqual(repaired.effectiveIngredientProfile, c.effectiveIngredientProfile)
        XCTAssertEqual(repaired.calories, c.calories); XCTAssertEqual(repaired.enforceProtein, c.enforceProtein)
        XCTAssertEqual(try PlanFingerprint.make(source), original)
    }
    func testPartialPlannerNeverAltersLockedPastMealOrInventsStock() throws {
        var c = constraints(); c.practicalWeek?.notBefore = date(1)
        let locked = MealPlanDay(id: MealPlanEditingRules.dayID(day), date: day,
            meals: [PlannedMeal(id: "owner-meal", mealType: "Dinner", foodItem: FoodItem(id: "original-food", name: "Owner meal", calories: 700))])
        var stock = PantryItem(name: "Unverified portions", quantity: 99, unit: "portion", dateAdded: day)
        stock.quantityVerified = false
        c.practicalWeek?.usePreparedStock = true
        let days = try PracticalMealWeekPlanner.make(recipes: [], constraints: c, starting: day, locked: [locked], stock: [stock], savedPlans: [], allowPartialReview: true)
        XCTAssertEqual(try PlanFingerprint.make(days[0]), try PlanFingerprint.make(locked))
        XCTAssertEqual(days.flatMap(\.meals).map(\.id), ["owner-meal"])
        XCTAssertFalse(MealPlanningPreflight.missingSlots(days: days, constraints: c).contains { $0.dayOffset == 0 })
    }
    func testPreflightNamesUnknownPrepPriceAndEquipmentWithoutInventingDefaults() throws {
        var source = try recipe(minutes: nil, equipment: [])
        source.planningProfile?.costPerServing = nil
        var c = constraints(); c.weeklyBudget = 100; c.availableEquipment = ["stove"]
        let readiness = try XCTUnwrap(MealPlanningPreflight.recipes([source], constraints: c).first)
        XCTAssertFalse(readiness.usable)
        XCTAssertTrue(readiness.issues.contains { $0.contains("prep-time") })
        XCTAssertTrue(readiness.issues.contains { $0.contains("price") })
        XCTAssertTrue(readiness.issues.contains { $0.contains("equipment") })
    }
    func testReviewedNoCookingRecipePassesPrepLimitWithoutPhantomCookingTime() throws {
        let source = try recipe(minutes: 0, equipment: ["no cooking"])
        var c = constraints(); c.maxPrepMinutes = 5; c.availableEquipment = ["no cooking"]
        XCTAssertTrue(MealPlanningPreflight.recipes([source], constraints: c).allSatisfy(\.usable))
        let days = try SavedRecipeWeekPlanner.make(recipes: [source], constraints: c, starting: day)
        XCTAssertEqual(days.flatMap(\.meals).count, 7)
        XCTAssertTrue(MealPlanConstraintRules.report(days: days, constraints: c).canSave)
    }
    func testStaleRecipeReviewCannotPassRestrictionsInPartialPlanner() throws {
        let original = try recipe()
        var source = Recipe(id: original.id, name: original.name, ingredients: original.ingredients + ["1 tbsp peanut oil"],
            instructions: original.instructions, nutrition: original.nutrition, servings: original.servings, nutritionBasis: original.nutritionBasis)
        source.planningProfile = original.planningProfile
        source.planningProfile?.reviewedExclusions = ["peanut"]
        var c = constraints(); c.ingredientProfile = .init(hardExclusions: ["peanut"])
        XCTAssertFalse(MealPlanningPreflight.recipes([source], constraints: c)[0].usable)
        let days = try PracticalMealWeekPlanner.make(recipes: [source], constraints: c, starting: day, locked: [], stock: [], savedPlans: [], allowPartialReview: true)
        XCTAssertTrue(days.flatMap(\.meals).isEmpty)
        XCTAssertEqual(c.ingredientProfile?.hardExclusions, ["peanut"])
    }
    func testNoCookingNeverBypassesKnownPrepOrExplicitUnknownPrepCap() throws {
        var c = constraints(); c.maxPrepMinutes = 10
        for source in [try recipe(minutes: 20, equipment: ["no cooking"]), try recipe(minutes: nil, equipment: ["no cooking"])] {
            XCTAssertFalse(MealPlanningPreflight.recipes([source], constraints: c)[0].usable)
            XCTAssertTrue(SavedRecipeWeekPlanner.eligibleRecipes([source], constraints: c).isEmpty)
        }
        let source = try recipe(minutes: 20, equipment: ["no cooking"])
        c.maxPrepMinutes = nil
        let days = try PracticalMealWeekPlanner.make(recipes: [source], constraints: c, starting: day,
            locked: [], stock: [], savedPlans: [], allowPartialReview: true)
        XCTAssertEqual(days.flatMap(\.meals).count, 1, "Known assembly time still uses the cooking-day allowance")
        XCTAssertTrue(MealPlanningPreflight.missingSlots(days: Array(days.prefix(6)), constraints: c).isEmpty,
            "A compacted array must not manufacture brief offsets; the existing seven-day report rejects it")
        XCTAssertFalse(MealPlanConstraintRules.report(days: Array(days.prefix(6)), constraints: c).canSave)
    }
    func testWaterContainersConvertAtBoundaryAndRetainChosenUnits() throws {
        let bottle = WaterContainer(name: "My bottle", amount: 500, unit: .milliliters)
        XCTAssertEqual(bottle.ounces, 16.9070113509215, accuracy: 0.0000001)
        XCTAssertEqual(WaterVolumeUnit.milliliters.amount(fromOunces: bottle.ounces), 500, accuracy: 0.0000001)
        XCTAssertTrue(bottle.isValid)
        XCTAssertFalse(WaterContainer(name: "", amount: 8, unit: .ounces).isValid)
        XCTAssertFalse(WaterContainer(name: "Large", amount: .infinity, unit: .milliliters).isValid)
        XCTAssertEqual(try JSONDecoder().decode(WaterContainer.self, from: JSONEncoder().encode(bottle)), bottle)
    }
    func testDatedWaterTargetsPreservePastAndRepresentTrackingOnlyWithoutZeroGoal() throws {
        var value = HydrationPreferences()
        try value.acceptTarget(64, at: date(0))
        try value.acceptTarget(nil, at: date(2))
        try value.acceptTarget(80, at: date(4))
        XCTAssertNil(value.targetPeriod(for: date(-1)))
        XCTAssertEqual(value.targetPeriod(for: date(1))?.targetOunces, 64)
        XCTAssertNotNil(value.targetPeriod(for: date(3)))
        XCTAssertNil(value.targetPeriod(for: date(3))?.targetOunces)
        XCTAssertEqual(value.targetPeriod(for: date(4))?.targetOunces, 80)
        XCTAssertFalse(value.isTrackingOnly)
        try value.acceptTarget(80, at: date(5)); XCTAssertEqual(value.targetHistory.count, 3)
        XCTAssertThrowsError(try value.acceptTarget(0, at: date(6)))
        XCTAssertThrowsError(try value.acceptTarget(60, at: date(1)))
        XCTAssertNoThrow(try value.validate())
    }
    func testHydrationChoicesAreAccountScopedAndDoNotRewriteDiary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EditorDraftStore(directory: root)
        var value = HydrationPreferences(); try value.acceptTarget(nil, at: day)
        let originalLog = log(0), original = try PlanFingerprint.make(originalLog)
        try store.save(value, userID: owner, scope: HydrationPreferences.scope)
        let restored = try XCTUnwrap(store.load(HydrationPreferences.self, userID: owner, scope: HydrationPreferences.scope)?.value)
        XCTAssertTrue(restored.isTrackingOnly)
        XCTAssertNil(try store.load(HydrationPreferences.self, userID: "other", scope: HydrationPreferences.scope))
        XCTAssertEqual(try PlanFingerprint.make(originalLog), original)
    }
}
