import XCTest
@testable import MyFitPlateCore

final class MealPlanConstraintsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private var constraints: MealPlanConstraints { .init(calories: 2_000, protein: 150, carbs: 250, fats: 70) }
    private func recipe(cost: Double? = 2) throws -> Recipe {
        var recipe = Recipe(id: "bowl", name: "Bean bowl", ingredients: ["200 g beans", "100 g rice"], instructions: ["Cook rice. Mix beans."], nutrition: .init(calories: 500, protein: 40, carbs: 60, fats: 10), servings: 1, nutritionBasis: .perServing)
        recipe.planningProfile = .init(prepMinutes: 20, equipment: ["stove"], diet: .vegan, reviewedExclusions: ["peanut"], costPerServing: cost, reviewedAt: date, contentFingerprint: try RecipePlanningProfile.fingerprint(recipe))
        return recipe
    }
    func testHouseholdCookingDoesNotMultiplyPersonalIntakeAndGraphSurvivesAcceptance() throws {
        var request = constraints; request.householdPortions = 3
        let days = try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: request, starting: date)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { (1_600...2_400).contains($0.meals.compactMap(\.plannedFood).reduce(0) { $0+$1.calories }) })
        let draft = MealPlanWeekDraft(days: days, title: "Test", constraints: request, preserveCookingBatches: true)
        let change = try MealPlanWeekReviewRules.merging(draft, existing: days.map { MealPlanEditingRules.emptyDay($0.date) }, replace: false)
        try MealPlanEditingRules.validate(change)
        XCTAssertEqual(change.after.flatMap(\.meals).filter { $0.cookingBatch?.totalPortions == 3 && $0.portions == 1 }.count, 28)
        XCTAssertTrue(MealPlanConstraintRules.report(days: change.after, constraints: request).canSave)
        XCTAssertTrue(Set(days.flatMap(\.meals).map(\.id)).isDisjoint(with: change.after.flatMap(\.meals).map(\.id)))
    }
    func testMissingAndStaleReviewsCannotPassHardConstraints() throws {
        var source = try recipe(); source.cookedWeightGrams = 500
        var request = constraints; request.maxPrepMinutes = 30
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [source], constraints: request, starting: date))
        source.planningProfile = nil
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [source], constraints: request, starting: date))
        source = try recipe(); source.nutritionBasis = nil
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [source], constraints: constraints, starting: date))
    }
    func testExclusionContradictionOverridesDeclaration() throws {
        var request = constraints; request.exclusions = ["beans"]
        var source = try recipe(); source.planningProfile?.reviewedExclusions = ["beans"]
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [source], constraints: request, starting: date))
        XCTAssertFalse(MealPlanConstraintRules.contains("peanut butter", phrase: "nut"))
        XCTAssertTrue(MealPlanConstraintRules.contains("Peanut-butter", phrase: "peanut butter"))
    }
    func testBudgetNeedsPricesAndRejectsOverspend() throws {
        var request = constraints; request.weeklyBudget = 1
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: request, starting: date))
        request.weeklyBudget = 100
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [recipe(cost: nil)], constraints: request, starting: date))
        let days = try SavedRecipeWeekPlanner.make(recipes: [recipe(cost: 1)], constraints: request, starting: date)
        XCTAssertLessThanOrEqual(MealPlanConstraintRules.report(days: days, constraints: request).knownWeeklyCost, 100)
    }
    func testLockedMealRemainsExactWhileGapsAreFilled() throws {
        var locked = MealPlanEditingRules.emptyDay(date)
        locked.meals = [PlannedMeal(id: "owner-breakfast", mealType: "Breakfast", foodItem: try RecipePortionRules.foodItem(for: recipe(), selection: .init(unit: .servings)))]
        let days = try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: constraints, starting: date, locked: [locked])
        XCTAssertEqual(try PlanFingerprint.make(days[0].meals.first { $0.id == "owner-breakfast" }), try PlanFingerprint.make(locked.meals.first))
    }
    func testImpossibleProteinNeverInventsNutrients() throws {
        var request = constraints; request.protein = 1_800
        XCTAssertThrowsError(try SavedRecipeWeekPlanner.make(recipes: [recipe()], constraints: request, starting: date))
    }
}

final class RecipeImportDraftTests: XCTestCase {
    func testPastedSourceFingerprintIgnoresLayoutButPreservesAmountsAndPunctuation() throws {
        let first = RecipeImportProvenance(kind: .text, originalText: "Ingredients:\n200 g beans\nCook for 10 minutes.")
        let layout = RecipeImportProvenance(kind: .photo, originalText: "Ingredients:  200 g beans\r\nCook for 10 minutes.")
        let changed = RecipeImportProvenance(kind: .text, originalText: "Ingredients: 20 g beans Cook for 10 minutes.")
        XCTAssertNotNil(RecipeImportDuplicateRules.sourceTextFingerprint(first))
        XCTAssertEqual(RecipeImportDuplicateRules.sourceTextFingerprint(first), RecipeImportDuplicateRules.sourceTextFingerprint(layout))
        XCTAssertNotEqual(RecipeImportDuplicateRules.sourceTextFingerprint(first), RecipeImportDuplicateRules.sourceTextFingerprint(changed))
        let decoded = try JSONDecoder().decode(RecipeImportProvenance.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(RecipeImportDuplicateRules.sourceTextFingerprint(decoded), RecipeImportDuplicateRules.sourceTextFingerprint(first))
        XCTAssertNil(RecipeImportDuplicateRules.sourceTextFingerprint(.init(kind: .text, originalText: " \n ")))
        XCTAssertNil(RecipeImportDuplicateRules.sourceTextFingerprint(.init(kind: .ai, originalText: "same prompt")))
    }

    func testDuplicateImportsOfferExistingIdentityWithoutMergingDifferentSources() {
        var saved = Recipe(id: "saved", name: "Beans", ingredients: ["200 g beans"], instructions: ["Cook"], nutrition: .init(calories: 500))
        saved.importProvenance = .init(kind: .text, originalText: "Ingredients: 200 g beans. Cook.")
        var draft = saved; draft.id = nil
        draft.importProvenance = .init(kind: .photo, originalText: "Ingredients:\n200 g beans. Cook.")
        XCTAssertEqual(RecipeImportDuplicateRules.matchingRecipe(for: draft, in: [saved])?.id, "saved")
        draft.importProvenance?.originalText = "Ingredients: 300 g beans. Cook."
        XCTAssertNil(RecipeImportDuplicateRules.matchingRecipe(for: draft, in: [saved]))
        saved.importProvenance = .init(kind: .url, sourceURL: "https://example.com/beans")
        draft.importProvenance = .init(kind: .structuredURL, sourceURL: "https://example.com/beans", originalText: "New published text")
        XCTAssertEqual(RecipeImportDuplicateRules.matchingRecipe(for: draft, in: [saved])?.id, "saved")
    }

    func testPhotoDuplicateCanUseExactOrderedPagesWithoutKeepingSourceText() {
        var saved = Recipe(id: "saved", name: "Soup", ingredients: ["200 g beans"], instructions: ["Cook"], nutrition: .init(calories: 500))
        saved.importProvenance = .init(kind: .photo, pageHashes: ["page1", "page2"])
        var draft = saved; draft.id = nil
        XCTAssertEqual(RecipeImportDuplicateRules.matchingRecipe(for: draft, in: [saved])?.id, "saved")
        draft.importProvenance?.pageHashes.reverse()
        XCTAssertNil(RecipeImportDuplicateRules.matchingRecipe(for: draft, in: [saved]))
        draft.importProvenance?.pageHashes = []
        XCTAssertNil(RecipeImportDuplicateRules.sourceIdentity(draft.importProvenance))
    }

    func testStructuredSelectionKeepsTextAndUnknownBasis() throws {
        let html = #"<script type="application/ld+json">{"@graph":[{"@type":"Recipe","name":"Soup","recipeYield":"4 servings","recipeIngredient":["2 cups beans","Salt to taste"],"recipeInstructions":[{"@type":"HowToStep","text":"Simmer for 10 minutes."}],"nutrition":{"calories":"300 kcal","proteinContent":"20 g"}},{"@type":"Recipe","name":"Rice","recipeIngredient":["100 g rice"],"recipeInstructions":"Cook rice."}]}</script>"#
        let drafts = try RecipeStructuredImport.drafts(html: html, sourceURL: "https://example.com/recipes")
        XCTAssertEqual(drafts.count, 2); XCTAssertEqual(drafts[0].ingredients, ["2 cups beans", "Salt to taste"])
        XCTAssertEqual(drafts[0].nutrition.calories, 300); XCTAssertNil(drafts[0].nutritionBasis)
        XCTAssertTrue(drafts[0].nutritionNeedsReview == true); XCTAssertEqual(drafts[0].importProvenance?.kind, .structuredURL)
        XCTAssertTrue(try RecipeStructuredImport.drafts(html: "<p>restaurant menu</p>", sourceURL: "x").isEmpty)
    }
    func testPhotoReviewDeduplicatesAndCanOmitSourceText() throws {
        var draft = RecipeDocumentDraft()
        let page = RecipeDocumentPage(digest: "same", lines: [.init(text: "Ingredients: 200 g rice, 100 g beans. Instructions: cook rice, mix beans and simmer.", confidence: 0.4)])
        try draft.append(page); XCTAssertThrowsError(try draft.append(page)); XCTAssertTrue(draft.looksLikeRecipe)
        XCTAssertEqual(draft.uncertainLines.count, 1)
        draft.retainSourceText = false
        XCTAssertNil(draft.provenance.originalText); XCTAssertTrue(draft.provenance.uncertainLines.isEmpty)
    }
    func testSourceStaysFrozenInPortionAndScaledCopy() throws {
        var recipe = Recipe(id: "r", name: "Soup", ingredients: ["200 g beans"], instructions: ["Cook"], nutrition: .init(calories: 500), servings: 2, nutritionBasis: .wholeRecipe)
        recipe.importProvenance = .init(kind: .photo, originalText: "original", pageHashes: ["page"])
        let portion = try RecipePortionRules.snapshot(for: recipe, selection: .init(unit: .servings))
        recipe.importProvenance?.originalText = "later edit"
        XCTAssertEqual(portion.scaled(by: 2)?.importProvenance?.originalText, "original")
        XCTAssertEqual(try JSONDecoder().decode(RecipePortionSnapshot.self, from: JSONEncoder().encode(portion)).importProvenance?.pageHashes, ["page"])
    }
}

@MainActor final class RecipeDraftBeforeSaveTests: XCTestCase {
    func testParsingReturnsDraftWithoutLibraryWrite() async {
        let auth = MockAuthService(); auth.currentUserID = "draft-owner"
        let repo = MockNutritionRepository(), ai = MockAIService()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo; DIContainer.shared.aiService = ai
        let service = RecipeService(); service.activateAccount("draft-owner")
        ai.mockResult = .success(#"{"name":"Soup","ingredients":["100 g beans"],"instructions":["Cook beans"],"nutrition":{"calories":200,"protein":20,"carbs":20,"fats":5},"servings":1}"#)
        let aiDraft = await service.createRecipeFromAI(description: "Soup", userID: "draft-owner", saveResult: false)
        let textDraft = await service.createRecipeFromText(text: "Soup ingredients 100 g beans. Cook beans.", userID: "draft-owner", saveResult: false)
        XCTAssertNotNil(aiDraft); XCTAssertNotNil(textDraft); XCTAssertTrue(repo.savedRecipes.isEmpty); XCTAssertTrue(service.userRecipes.isEmpty)
        XCTAssertEqual(textDraft?.importProvenance?.kind, .text)
    }
}
