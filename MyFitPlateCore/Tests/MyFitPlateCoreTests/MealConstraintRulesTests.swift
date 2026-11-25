import XCTest
@testable import MyFitPlateCore

final class MealConstraintRulesTests: XCTestCase {
    private func candidate(_ ingredients: [String], name: String = "Reviewed bowl", calories: Double = 400,
                           instructions: String = "Mix the listed ingredients.") -> MealConstraintCandidate {
        .init(name: name, ingredients: ingredients, instructions: instructions,
            food: FoodItem(id: "fixed-food", name: name, calories: calories, protein: 20, carbs: 50, fats: 10))
    }
    func testAdversarialIngredientCorpusUsesTheSameChecksForGeneralFuelAndWeekProposals() {
        let cases: [(String, String)] = [
            ("peanut", "1 tbsp groundnut oil"), ("peanuts", "20 g PEANUT-BUTTER"),
            ("peanut", "20 g pea\u{200B}nut butter"), ("soy", "100 g tofu"), ("soy", "1 tbsp tamari"),
            ("sesame", "15 g tahini"), ("milk", "30 g whey protein"), ("dairy", "10 g ghee"),
            ("wheat", "100 g semolina"), ("gluten", "100 g seitan"),
            ("fish", "1 tsp anchovies"), ("shellfish", "100 g prawns"), ("egg", "10 g mayonnaise")
        ]
        for (excluded, ingredient) in cases {
            let profile = MealConstraintProfile(revisionID: "corpus", hardExclusions: [excluded])
            let value = candidate([ingredient])
            let fakeReview = MealIngredientReview(candidate: value, profile: profile)
            let result = MealConstraintRules.report(candidate: value, profile: profile, personalReview: fakeReview)
            XCTAssertTrue(result.isBlocked, "\(excluded): \(ingredient)")
            XCTAssertTrue(result.issues.contains { $0.kind == .excludedIngredient })
            let meal = PlannedMeal(mealType: "Lunch", foodItem: value.food, ingredients: value.ingredients, instructions: value.instructions)
            XCTAssertTrue(MealConstraintRules.report(candidate: meal.constraintCandidate, profile: profile).isBlocked)
        }
    }
    func testTokenBoundariesAndClearPlantAlternativesDoNotInventContradictions() {
        for (exclusion, ingredient) in [("egg", "200 g eggplant"), ("meat", "1 cup chamomile tea"),
                                        ("dairy", "100 ml coconut milk"), ("dairy", "20 g almond butter"),
                                        ("peanut", "1 serving peanut-free rice crackers")] {
            let result = MealConstraintRules.report(candidate: candidate([ingredient]),
                profile: MealConstraintProfile(hardExclusions: [exclusion]))
            XCTAssertTrue(result.needsPersonalReview, "Absence of a detected match is still not verified: \(ingredient)")
        }
        XCTAssertTrue(MealConstraintRules.contains(["peanut-free rice with peanut butter"], exclusion: "peanut"))
        XCTAssertTrue(MealConstraintRules.contains(["coconut milk and dairy milk"], exclusion: "dairy"))
    }
    func testDietAndExclusionContradictionsCannotBeOverriddenByPersonalReview() {
        for (diet, ingredient) in [(PlanningDiet.vegan, "1 tsp honey"), (.vegetarian, "1 tsp fish sauce"), (.pescatarian, "100 ml chicken stock")] {
            let profile = MealConstraintProfile(diet: diet)
            let meal = candidate([ingredient])
            XCTAssertTrue(MealConstraintRules.report(candidate: meal, profile: profile,
                personalReview: .init(candidate: meal, profile: profile)).isBlocked)
        }
    }
    func testReviewBindsExactIngredientPortionAndProfileRevision() {
        let profile = MealConstraintProfile(revisionID: "first", hardExclusions: ["peanut"])
        let meal = candidate(["150 g rice", "100 g beans"])
        let review = MealIngredientReview(candidate: meal, profile: profile)
        XCTAssertTrue(MealConstraintRules.report(candidate: meal, profile: profile, personalReview: review).canAccept)
        XCTAssertTrue(MealConstraintRules.report(candidate: candidate(["150 g rice", "100 g beans"], calories: 800), profile: profile, personalReview: review).needsPersonalReview)
        XCTAssertTrue(MealConstraintRules.report(candidate: candidate(["200 g rice", "100 g beans"]), profile: profile, personalReview: review).needsPersonalReview)
        var changed = profile; changed.revisionID = "second"
        XCTAssertTrue(MealConstraintRules.report(candidate: meal, profile: changed, personalReview: review).needsPersonalReview)
        XCTAssertNotEqual(meal, candidate(meal.ingredients, calories: 900), "FoodItem identity equality must not collapse different portion evidence")
    }
    func testMissingIngredientsAndInvalidNutritionCannotPassByAcknowledgement() {
        let profile = MealConstraintProfile(hardExclusions: ["sesame"])
        let missing = candidate([])
        XCTAssertTrue(MealConstraintRules.report(candidate: missing, profile: profile,
            personalReview: .init(candidate: missing, profile: profile)).isBlocked)
        XCTAssertTrue(MealConstraintRules.report(candidate: candidate(["Rice"], calories: -.infinity), profile: nil).isBlocked)
        XCTAssertTrue(MealConstraintRules.report(candidate: candidate(["Rice"], calories: -1), profile: nil).isBlocked)
    }
    func testUnknownProfileVersionsFailClosedAndLegacyPreferencesRemainReadable() throws {
        let data = Data(#"{"proteins":["Chicken"],"carbs":[],"vegetables":[],"cuisines":["Any"]}"#.utf8)
        let legacy = try JSONDecoder().decode(FoodPreferencesDraft.self, from: data)
        XCTAssertNil(legacy.mealConstraintProfile)
        let profile = MealConstraintProfile(schemaVersion: 99, revisionID: "newer", hardExclusions: ["peanut"])
        XCTAssertEqual(try MealConstraintProfile.decodeField(profile.fields), profile)
        XCTAssertThrowsError(try profile.validate())
        XCTAssertTrue(MealConstraintRules.report(candidate: candidate(["Rice"]), profile: profile).isBlocked)
        var proposed = legacy; proposed.mealConstraintProfile = profile
        XCTAssertThrowsError(try proposed.validated())
    }
    func testHardConstraintsAreComparedSeparatelyFromLikesAndCanBeExplicitlyCleared() throws {
        let original = FoodPreferencesDraft.defaults
        var restricted = original
        restricted.mealConstraintProfile = MealConstraintProfile(revisionID: "saved", hardExclusions: ["peanut"])
        var persisted: [String: Any] = restricted.fields
        persisted["mealConstraintProfile"] = restricted.mealConstraintProfile?.fields
        XCTAssertFalse(original.matchesPersistedPreferences(["goals": persisted]))
        XCTAssertTrue(restricted.matchesPersistedPreferences(["goals": persisted]))
        XCTAssertTrue(restricted.profilePatch(updatedAt: Date())["goals.mealConstraintProfile"] is [String: Any])
        XCTAssertTrue(original.profilePatch(updatedAt: Date())["goals.mealConstraintProfile"] is NSNull)
        XCTAssertEqual(restricted.proteins, original.proteins)
        XCTAssertNil(restricted.profilePatch(updatedAt: Date())["goals.calories"])
    }
    func testCurrentRecipeReviewAndPortionProvenanceAreRetained() throws {
        var recipe = Recipe(id: "rice", name: "Rice bowl", ingredients: ["200 g rice"],
            instructions: ["Cook rice."], nutrition: .init(calories: 400, protein: 10, carbs: 80, fats: 2),
            servings: 2, nutritionBasis: .wholeRecipe)
        recipe.planningProfile = .init(diet: .vegan, reviewedExclusions: ["peanut"], reviewedAt: Date(),
            contentFingerprint: try RecipePlanningProfile.fingerprint(recipe))
        let food = try RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings, amount: 1.5))
        let meal = PlannedMeal(mealType: "Lunch", recipeID: recipe.id, foodItem: food,
            ingredients: try RecipePortionRules.ingredients(for: recipe, selection: .init(unit: .servings, amount: 1.5)), instructions: "Cook rice.")
        let profile = MealConstraintProfile(diet: .vegan, hardExclusions: ["peanut"])
        XCTAssertTrue(MealConstraintRules.report(candidate: meal.constraintCandidate, profile: profile, recipeReview: recipe.planningProfile).canAccept)
        XCTAssertEqual(meal.constraintCandidate.food?.recipePortionSnapshot?.selection.amount, 1.5)
        XCTAssertEqual(meal.constraintCandidate.food?.recipePortionSnapshot?.recipeID, "rice")
        XCTAssertEqual(meal.constraintCandidate.food?.recipePortionSnapshot?.selectedNutrition.calories, 300)
    }
}
