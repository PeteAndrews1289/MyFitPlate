import XCTest
@testable import MyFitPlateCore

@MainActor
final class RecipeIngredientBasisTests: XCTestCase {
    private func recipe(ingredientBasis: RecipeNutritionBasis? = .wholeRecipe, detailed: Bool = false) -> Recipe {
        let rice = FoodItem(id: "rice", name: "Rice", calories: 2_000, protein: 40, carbs: 400, fats: 20,
            servingSize: "400 g", servingWeight: 400,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "rice"),
            quantityValue: 400, servingUnit: "g")
        return Recipe(id: "published-rice", name: "Rice bowl", ingredients: ["400 g Rice"],
            detailedIngredients: detailed ? [rice] : nil, instructions: ["Cook the rice."],
            nutrition: Nutrition(calories: 500, protein: 10, carbs: 100, fats: 5),
            servings: 4, nutritionBasis: .perServing, nutritionOrigin: .ingredients,
            unresolvedIngredients: detailed ? [] : nil, cookedWeightGrams: 800,
            ingredientBasis: ingredientBasis)
    }

    private func plannedMeal(_ source: Recipe, selection: RecipePortionSelection = .init(unit: .servings)) throws -> PlannedMeal {
        PlannedMeal(id: "planned-rice", mealType: "Dinner", recipeID: source.id,
            foodItem: try RecipePortionRules.foodItem(for: source, selection: selection),
            ingredients: try RecipePortionRules.ingredients(for: source, selection: selection),
            instructions: source.instructions.joined(separator: "\n"))
    }

    func testPublishedPerServingNutritionUsesWholeBatchIngredientsForOnePerson() throws {
        for detailed in [false, true] {
            let source = recipe(detailed: detailed)
            let meal = try plannedMeal(source)
            XCTAssertEqual(meal.plannedFood?.calories, 500)
            XCTAssertEqual(meal.plannedIngredients.first?.quantity, 100)
            XCTAssertEqual(meal.foodItem?.recipePortionSnapshot?.sourceBasis, .perServing)
            XCTAssertEqual(meal.foodItem?.recipePortionSnapshot?.sourceIngredientBasis, .wholeRecipe)
            XCTAssertEqual(RecipePortionRules.originalIngredientLines(for: source), [detailed ? "400 g Rice" : "400 gram rice"])
            XCTAssertEqual(try RecipePortionRules.ingredients(for: source, selection: .init(unit: .servings)), [detailed ? "100 g Rice" : "100 gram rice"])
            XCTAssertEqual(MealPlanEditingRules.ingredients(for: source), [detailed ? "100 g Rice" : "100 gram rice"])
        }
    }

    func testHouseholdFourPurchases400GramsOnceWhilePersonalNutritionStays500() throws {
        let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_792_000_000))
        let meal = try MealPlanCookingRules.configuring(plannedMeal(recipe()), date: date, cookingPortions: 4)
        var day = MealPlanEditingRules.emptyDay(date); day.meals = [meal]
        XCTAssertEqual(meal.plannedFood?.calories, 500)
        XCTAssertEqual(meal.cookingBatch?.ingredientsPerPortion.first?.quantity, 100)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: [day], starting: date, unitSystem: .metric).first?.quantity, 400)
        let tomorrow = MealPlanEditingRules.emptyDay(Calendar.current.date(byAdding: .day, value: 1, to: date)!)
        let change = try MealPlanCookingRules.planningLeftover(from: meal, source: day, relatedDays: [day],
            destination: tomorrow, mealType: "Lunch", portions: 1)
        XCTAssertEqual(change.after[1].meals[0].plannedFood?.calories, 500)
        XCTAssertEqual(GroceryListBuilder.makeGroceryList(from: change.after, starting: date, unitSystem: .metric).first?.quantity, 400)
    }

    func testCookedGramsAndBatchFractionsScaleIngredientsSeparatelyFromNutrition() throws {
        for selection in [RecipePortionSelection(unit: .cookedGrams, amount: 100),
                          RecipePortionSelection(unit: .batchFraction, amount: 0.125),
                          RecipePortionSelection(unit: .servings, amount: 0.5)] {
            let meal = try plannedMeal(recipe(), selection: selection)
            XCTAssertEqual(meal.plannedFood?.calories, 250)
            XCTAssertEqual(meal.plannedIngredients.first?.quantity, 50)
            XCTAssertEqual(meal.foodItem?.recipePortionSnapshot?.cookedGrams, 100)
            XCTAssertEqual(try RecipePortionRules.ingredients(for: recipe(), selection: selection), ["50 gram rice"])
        }
        var source = recipe(ingredientBasis: .perServing)
        source.detailedIngredients = nil
        // Explicit one-serving ingredients are independent of whole-batch nutrition too.
        source.nutritionBasis = .wholeRecipe; source.nutrition.calories = 2_000
        XCTAssertEqual(try plannedMeal(source).plannedFood?.calories, 500)
        XCTAssertEqual(try plannedMeal(source).plannedIngredients.first?.quantity, 400)
    }

    func testAbsentIngredientBasisPreservesEveryLegacyScalingConvention() throws {
        let source = recipe(ingredientBasis: nil)
        let oldData = try JSONEncoder().encode(source)
        XCTAssertFalse(try XCTUnwrap(String(data: oldData, encoding: .utf8)).contains("ingredientBasis"))
        let decoded = try JSONDecoder().decode(Recipe.self, from: oldData)
        XCTAssertNil(decoded.ingredientBasis)
        XCTAssertEqual(try plannedMeal(decoded).plannedIngredients.first?.quantity, 400)
        XCTAssertEqual(MealPlanEditingRules.ingredients(for: decoded), ["400 g Rice"])
        var whole = decoded; whole.nutritionBasis = .wholeRecipe
        XCTAssertEqual(try plannedMeal(whole).plannedIngredients.first?.quantity, 100)
        var unconfirmed = decoded; unconfirmed.nutritionBasis = nil; unconfirmed.cookedWeightGrams = nil
        let saved = try plannedMeal(unconfirmed, selection: .init(unit: .savedAmount))
        XCTAssertEqual(saved.plannedFood?.calories, 500)
        XCTAssertEqual(saved.plannedIngredients.first?.quantity, 400)
        let snapshot = try XCTUnwrap(saved.foodItem?.recipePortionSnapshot)
        let restored = try JSONDecoder().decode(RecipePortionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertNil(restored.sourceIngredientBasis)
        XCTAssertEqual(RecipePortionRules.plannedIngredients(for: restored, multiplier: 2)?.first?.quantity, 800)
    }

    func testFrozenIngredientBasisSurvivesLibraryEditsRepeatAndDetailCorrection() throws {
        var source = recipe()
        let meal = try plannedMeal(source)
        let food = try XCTUnwrap(meal.foodItem)
        let restored = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(meal))
        let revision = try XCTUnwrap(restored.foodItem?.recipePortionSnapshot?.recipeRevisionID)
        source.ingredientBasis = .perServing; source.servings = 8; source.nutrition.calories = 250
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: source), revision)
        XCTAssertEqual(restored.plannedIngredients.first?.quantity, 100)
        XCTAssertEqual(restored.plannedFood?.calories, 500)
        XCTAssertEqual(restored.foodItem?.recipePortionSnapshot?.sourceIngredientBasis, .wholeRecipe)
        let repeated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 2))
        XCTAssertEqual(repeated.recipePortionSnapshot?.sourceIngredientBasis, .wholeRecipe)
        XCTAssertEqual(repeated.recipePortionSnapshot.flatMap { RecipePortionRules.plannedIngredients(for: $0, multiplier: 1) }?.first?.quantity, 200)
        var incompatible = food; incompatible.servingWeight = 0
        incompatible = incompatible.preservingRecipePortion(from: food, quantity: 2, unit: "ladle")
        XCTAssertEqual(incompatible.recipePortionSnapshot?.sourceIngredientBasis, .wholeRecipe)
        XCTAssertEqual(incompatible.recipePortionSnapshot?.portionRequiresReview, true)
    }

    func testEditingDefaultsRecalculationToBatchAndPreservesExplicitPerServingIngredients() throws {
        var source = recipe(ingredientBasis: nil, detailed: true)
        var untouched = RecipeEditingState(recipe: source)
        XCTAssertNil(untouched.ingredientBasis)
        XCTAssertNil(try untouched.makeRecipe(name: source.name, instructions: source.instructions).ingredientBasis)
        untouched.nutritionChoice = .recalculate
        let recalculated = try untouched.makeRecipe(name: source.name, instructions: source.instructions)
        XCTAssertEqual(recalculated.ingredientBasis, .wholeRecipe)
        XCTAssertEqual(recalculated.nutritionBasis, .wholeRecipe)
        XCTAssertEqual(recalculated.nutritionPerPortion.calories, 500)
        XCTAssertEqual(try plannedMeal(recalculated).plannedIngredients.first?.quantity, 100)
        source.ingredientBasis = .perServing
        var explicit = RecipeEditingState(recipe: source); explicit.nutritionChoice = .recalculate
        let perServing = try explicit.makeRecipe(name: source.name, instructions: source.instructions)
        XCTAssertEqual(perServing.ingredientBasis, .perServing)
        XCTAssertEqual(perServing.nutritionBasis, .perServing)
        XCTAssertEqual(perServing.nutritionPerPortion.calories, 2_000)
        XCTAssertEqual(try plannedMeal(perServing).plannedIngredients.first?.quantity, 400)
    }

    func testFreshManualRecipeAndAllNewAIParsesConfirmWholeBatchIngredients() throws {
        let source = recipe(detailed: true)
        var manual = RecipeEditingState(); manual.ingredients = source.resolvedIngredientFoods; manual.servings = 4
        let saved = try manual.makeRecipe(name: "Manual rice", instructions: ["Cook"])
        XCTAssertEqual(saved.ingredientBasis, .wholeRecipe)
        let json = #"{"name":"Rice","ingredients":["400 g Rice"],"instructions":["Cook"],"servings":4,"nutritionBasis":"wholeRecipe","nutrition":{"calories":2000,"protein":40,"carbs":400,"fats":20}}"#
        XCTAssertEqual(try RecipeRules.parseRecipeFromAIResponse(json).ingredientBasis, .wholeRecipe)
        XCTAssertEqual(try RecipeRules.parseRecipeFromURLResponse(json.replacingOccurrences(of: "{\"name\"", with: "{\"isRecipe\":true,\"name\""))?.ingredientBasis, .wholeRecipe)
        XCTAssertEqual(try RecipeRules.parseRecipesFromAIResponse("{\"recipes\":[\(json)]}").first?.ingredientBasis, .wholeRecipe)
    }

    func testStructuredImportConfirmsBatchIngredientsWithoutInventingNutritionBasis() throws {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Rice","recipeIngredient":["400 g Rice"],"recipeInstructions":["Cook rice"],"recipeYield":"4 servings","nutrition":{"calories":"500 kcal","proteinContent":"10 g","carbohydrateContent":"100 g","fatContent":"5 g"}}</script>"#
        var source = try XCTUnwrap(RecipeStructuredImport.drafts(html: html, sourceURL: "https://example.com/rice").first)
        XCTAssertNil(source.nutritionBasis, "A webpage's nutrition panel still requires explicit review")
        XCTAssertEqual(source.ingredientBasis, .wholeRecipe)
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: source, selection: .init(unit: .savedAmount))) {
            XCTAssertEqual($0 as? RecipePortionError, .unconfirmedBasis)
        }
        source.nutritionBasis = .perServing
        XCTAssertEqual(try plannedMeal(source).plannedIngredients.first?.quantity, 100)
        XCTAssertEqual(try plannedMeal(source).plannedFood?.calories, 500)
    }
}
