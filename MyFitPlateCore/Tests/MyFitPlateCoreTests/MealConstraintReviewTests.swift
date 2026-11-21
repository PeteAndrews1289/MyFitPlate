import XCTest
@testable import MyFitPlateCore

@MainActor final class MealConstraintReviewTests: XCTestCase {
    private var oldAuth: AuthServiceProtocol!
    private var oldRepository: NutritionRepositoryProtocol!
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var directory: URL!
    private var disk: EditorDraftStore!
    private var service: DailyLogService!
    private var goals: GoalSettings!
    private let owner = "constraint-review-owner"
    override func setUp() {
        oldAuth = DIContainer.shared.authService; oldRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository(); repository.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("meal-constraints-\(UUID())")
        disk = EditorDraftStore(directory: directory)
        goals = GoalSettings(isEditingPreview: true); goals.activateAccount(owner); goals.calories = 2_000
        service = DailyLogService(undoStore: disk); service.activateAccount(owner); service.goalSettings = goals
    }
    override func tearDown() {
        service.activateAccount(nil); service = nil
        DIContainer.shared.authService = oldAuth; DIContainer.shared.nutritionRepository = oldRepository
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func suggestion(name: String = "Rice bowl", ingredients: [String] = ["150 g rice", "100 g beans"]) -> MealSuggestion {
        .init(title: name, calories: 400, mealName: name, protein: 20, carbs: 60, fats: 9, ingredients: ingredients, instructions: "Mix the listed ingredients.")
    }
    private func save(_ review: MealReviewSaveSession) async -> Bool {
        await withCheckedContinuation { continuation in review.save(using: service) { continuation.resume(returning: $0) } }
    }
    func testCurrentProfileRevalidatedBeforeFirstSubmitAndUncertainRetryKeepsAcceptedIntent() async throws {
        let first = MealConstraintProfile(revisionID: "first", hardExclusions: ["peanut"])
        goals.mealConstraintProfile = first
        let originalDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -2, to: Date()))
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: originalDay))
        let review = suggestion().makeReview(userID: owner, day: day, source: "constraints", meal: "Lunch", store: disk)
        XCTAssertTrue(review.confirmIngredientReview(profile: first))
        let second = MealConstraintProfile(revisionID: "second", hardExclusions: ["egg"])
        goals.mealConstraintProfile = second
        let blocked = await save(review)
        XCTAssertFalse(blocked); XCTAssertFalse(review.isSubmitted); XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertTrue(review.confirmIngredientReview(profile: second))
        repository.updateLogSuccess = false
        let uncertain = await save(review)
        XCTAssertFalse(uncertain); XCTAssertTrue(review.isSubmitted)
        let foods = review.checkpoint.draft.foods
        goals.mealConstraintProfile = MealConstraintProfile(revisionID: "third", hardExclusions: ["rice"])
        let resumed = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "constraints", userID: owner, store: disk))
        XCTAssertFalse(resumed.confirmIngredientReview(profile: goals.mealConstraintProfile))
        repository.updateLogSuccess = true
        let accepted = await save(resumed)
        XCTAssertTrue(accepted, resumed.errorMessage ?? "No save error reported")
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).map(\.id), foods.map(\.id))
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Lunch")
        XCTAssertEqual(resumed.checkpoint.ingredientReview?.profileFingerprint, second.fingerprint)
    }
    func testRegenerationInvalidatesPersonalIngredientReviewWithoutChangingDestination() throws {
        let profile = MealConstraintProfile(hardExclusions: ["peanut"])
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: Date()))
        let review = suggestion().makeReview(userID: owner, day: day, source: "regenerated", store: disk)
        XCTAssertTrue(review.confirmIngredientReview(profile: profile))
        XCTAssertTrue(review.replaceMealSuggestion(suggestion(name: "Different bowl", ingredients: ["150 g potato", "100 g beans"])))
        XCTAssertNil(review.checkpoint.ingredientReview)
        XCTAssertTrue(review.ingredientAssessment(profile: profile)?.needsPersonalReview == true)
        XCTAssertEqual(review.checkpoint.draft.dayContext, day)
        let restored = try XCTUnwrap(MealReviewSaveSession.resumeMealSuggestion(source: "regenerated", userID: owner, store: disk))
        XCTAssertNil(restored.checkpoint.ingredientReview)
    }
    func testAccountSwitchCannotCertifyAnotherAccountsIngredientReview() throws {
        let profile = MealConstraintProfile(hardExclusions: ["peanut"])
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: Date()))
        let review = suggestion().makeReview(userID: owner, day: day, source: "owner", store: disk)
        auth.currentUserID = "other"
        XCTAssertFalse(review.confirmIngredientReview(profile: profile))
        let stored = try XCTUnwrap(disk.load(MealReviewCheckpoint.self, userID: owner, scope: MealReviewSaveSession.scope(for: "owner")))
        XCTAssertNil(stored.value.ingredientReview)
    }
    func testWeeklyAdoptionRejectsNewContradictionButKeepsUnchangedExistingMeals() throws {
        let date = Calendar.current.startOfDay(for: Date())
        let existing = PlannedMeal(id: "existing", mealType: "Breakfast", foodItem: FoodItem(name: "Peanut toast", calories: 300), ingredients: ["20 g peanut butter"])
        var before = MealPlanEditingRules.emptyDay(date); before.meals = [existing]
        var after = before
        after.meals.append(PlannedMeal(id: "new", mealType: "Lunch", foodItem: FoodItem(name: "Rice", calories: 400), ingredients: ["200 g rice"]))
        let profile = MealConstraintProfile(hardExclusions: ["peanut"])
        let personal = RecipePlanningProfile(diet: .vegan, reviewedExclusions: ["peanut"], reviewedAt: Date())
        after.meals[1].planningEvidence = try PlannedMealEvidence(profile: personal, meal: after.meals[1])
        let draft = MealPlanWeekDraft(days: [after], title: "Review", preserveCookingBatches: true)
        let review = MealPlanWeekSaveSession(userID: owner, draft: draft, store: disk)
        XCTAssertTrue(review.prepare(MealPlanChange(title: "Keep existing", before: [before], after: [after]), ingredientProfile: profile))
        XCTAssertEqual(try PlanFingerprint.make(review.checkpoint?.change?.after[0].meals[0]), try PlanFingerprint.make(existing))
        var contradictory = after; contradictory.meals[1].ingredients = ["20 g peanut butter"]
        contradictory.meals[1].planningEvidence = try PlannedMealEvidence(profile: personal, meal: contradictory.meals[1])
        XCTAssertFalse(review.prepare(MealPlanChange(title: "Rejected", before: [before], after: [contradictory]), ingredientProfile: profile))
        XCTAssertEqual(review.checkpoint?.change?.title, "Keep existing")
    }
}
