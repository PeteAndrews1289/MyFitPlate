import XCTest
@testable import MyFitPlateCore

final class RecipePortionTests: XCTestCase {
    private func recipe(basis: RecipeNutritionBasis? = .wholeRecipe, weight: Double? = 800) -> Recipe {
        let ingredient = FoodItem(id: "beans", name: "Beans", calories: 800, protein: 40, carbs: 120, fats: 8,
            servingSize: "400 g", servingWeight: 400,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "beans"), calcium: 400,
            quantityValue: 400, servingUnit: "g")
        return Recipe(id: "soup", name: "Bean soup", ingredients: ["400 g beans"], detailedIngredients: [ingredient],
            instructions: ["Simmer"], nutrition: Nutrition(calories: basis == .perServing ? 200 : 800,
                protein: basis == .perServing ? 10 : 40, carbs: basis == .perServing ? 30 : 120,
                fats: basis == .perServing ? 2 : 8, calcium: basis == .perServing ? 100 : 400),
            servings: 4, nutritionBasis: basis, nutritionOrigin: .ingredients,
            unresolvedIngredients: [], cookedWeightGrams: weight)
    }

    func testServingsGramsAndBatchFractionsResolveTheSameFourServingRecipe() throws {
        let source = recipe()
        let selections = [RecipePortionSelection(unit: .servings, amount: 1.5),
                          RecipePortionSelection(unit: .cookedGrams, amount: 300),
                          RecipePortionSelection(unit: .batchFraction, amount: 0.375)]
        for selection in selections {
            let food = try RecipePortionRules.foodItem(for: source, selection: selection)
            XCTAssertEqual(food.calories, 300)
            XCTAssertEqual(food.calcium, 150)
            XCTAssertNil(food.vitaminD, "Unknown nutrition must not become zero")
            XCTAssertEqual(food.servingWeight, 300)
            XCTAssertEqual(food.recipePortionSnapshot?.servingsEquivalent, 1.5)
            XCTAssertEqual(food.recipePortionSnapshot?.batchFraction, 0.375)
            XCTAssertEqual(food.recipePortionSnapshot?.sourceNutrition.calories, 800)
        }
        XCTAssertEqual(source.nutrition.calories, 800)
        XCTAssertEqual(source.servings, 4)
    }

    func testPerServingSourceUsesTheConfirmedYieldForBatchAndGramMeasures() throws {
        let source = recipe(basis: .perServing)
        XCTAssertEqual(RecipeEditingState(recipe: source).servings, 4)
        for selection in [RecipePortionSelection(unit: .servings, amount: 1.5),
                          RecipePortionSelection(unit: .cookedGrams, amount: 300),
                          RecipePortionSelection(unit: .batchFraction, amount: 0.375)] {
            XCTAssertEqual(try RecipePortionRules.foodItem(for: source, selection: selection).calories, 300)
        }
        XCTAssertEqual(source.nutrition.calories, 200, "The saved source remains per serving")
    }

    func testRawIngredientMassNeverBecomesCookedYield() throws {
        let source = recipe(weight: nil)
        XCTAssertEqual(source.detailedIngredients?.first?.servingWeight, 400)
        XCTAssertFalse(RecipePortionRules.availableUnits(for: source).contains(.cookedGrams))
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: source, selection: .init(unit: .cookedGrams, amount: 100)))
    }

    func testLegacyUnconfirmedYieldRemainsSavedAmountUntilExplicitConfirmation() throws {
        let source = recipe(basis: nil, weight: nil)
        XCTAssertEqual(RecipePortionRules.availableUnits(for: source), [.savedAmount])
        let food = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .savedAmount, amount: 1.5))
        XCTAssertEqual(food.calories, 1_200)
        XCTAssertNil(food.recipePortionSnapshot?.yieldServings)
        XCTAssertNil(food.recipePortionSnapshot?.batchFraction)
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: source, selection: .init(unit: .servings, amount: 1.5)))

        var edit = RecipeEditingState(recipe: source)
        edit.yieldChoice = .wholeRecipe
        edit.servings = 4
        edit.cookedWeightGrams = 800
        let confirmed = try edit.makeRecipe(name: source.name, instructions: source.instructions)
        XCTAssertEqual(confirmed.nutrition, source.nutrition)
        XCTAssertEqual(confirmed.nutritionBasis, .wholeRecipe)
        XCTAssertEqual(try RecipePortionRules.foodItem(for: confirmed, selection: .init(unit: .servings, amount: 1.5)).calories, 300)
        XCTAssertEqual(food.calories, 1_200, "Existing consumption is not recalculated")
    }

    func testLegacyRecipeAndFoodDecodeWithoutNewFields() throws {
        let data = Data(#"{"id":"old","name":"Old soup","ingredients":["Beans"],"instructions":["Heat"],"nutrition":{"calories":600,"protein":20,"carbs":80,"fats":10},"servings":4}"#.utf8)
        let source = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertNil(source.revisionID)
        XCTAssertNil(source.cookedWeightGrams)
        XCTAssertEqual(source.nutritionPerPortion.calories, 600)
        let food = try JSONDecoder().decode(FoodItem.self, from: Data(#"{"id":"old-food","name":"Old soup","calories":600,"protein":20,"carbs":80,"fats":10,"servingSize":"saved amount","servingWeight":0}"#.utf8))
        XCTAssertNil(food.recipePortionSnapshot)
        XCTAssertEqual(try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(food)).calories, 600)
    }

    func testPortionSnapshotSurvivesCodableAndLaterRecipeEdits() throws {
        var source = recipe()
        let food = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings, amount: 1.5), entryID: "logged")
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(food))
        let originalRevision = restored.recipePortionSnapshot?.recipeRevisionID
        source.nutrition.calories = 1_600
        source.servings = 8
        source.cookedWeightGrams = 1_600
        XCTAssertEqual(restored.calories, 300)
        XCTAssertEqual(restored.recipePortionSnapshot?.sourceNutrition.calories, 800)
        XCTAssertEqual(restored.recipePortionSnapshot?.yieldServings, 4)
        XCTAssertEqual(restored.recipePortionSnapshot?.recipeRevisionID, originalRevision)
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: source), originalRevision)
    }

    func testRepeatAndPlanMultiplierScaleThePortionEvidenceOnce() throws {
        let source = recipe()
        let selection = RecipePortionSelection(unit: .servings, amount: 1.5)
        let food = try RecipePortionRules.foodItem(for: source, selection: selection)
        let repeated = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 2))
        XCTAssertEqual(repeated.calories, 600)
        XCTAssertEqual(repeated.recipePortionSnapshot?.selection.amount, 3)
        XCTAssertEqual(repeated.recipePortionSnapshot?.selectedNutrition.calories, 600)
        XCTAssertEqual(repeated.recipePortionSnapshot?.sourceNutrition.calories, 800)
        let meal = PlannedMeal(mealType: "Dinner", recipeID: source.id, foodItem: food,
            ingredients: try RecipePortionRules.ingredients(for: source, selection: selection), portionMultiplier: 2)
        XCTAssertEqual(meal.plannedFood?.calories, 600)
        XCTAssertEqual(meal.plannedFood?.recipePortionSnapshot?.servingsEquivalent, 3)
        XCTAssertEqual(meal.plannedIngredients.first?.quantity, 300)
    }

    func testRepeatedSelectionsAlwaysCalculateFromTheUnchangedBatch() throws {
        let source = recipe()
        let before = try JSONEncoder().encode(source)
        for _ in 0..<50 {
            for amount in [1.0, 2.0, 0.5, 1.5, 1.0] {
                let food = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings, amount: amount))
                XCTAssertEqual(food.calories, amount * 200)
            }
        }
        let after = try JSONDecoder().decode(Recipe.self, from: before)
        XCTAssertEqual(source, after)
        XCTAssertEqual(source.nutrition.calories, 800)
    }

    func testDetailCorrectionKeepsSourceAndMakesNutritionOverrideExplicit() throws {
        let original = try RecipePortionRules.foodItem(for: recipe(), selection: .init(unit: .servings, amount: 1.5))
        var edited = original
        edited.calories = 180
        edited.servingWeight = 100
        edited = edited.preservingRecipePortion(from: original, quantity: 0.5, unit: "serving")
        XCTAssertEqual(edited.recipePortionSnapshot?.servingsEquivalent, 0.5)
        XCTAssertEqual(edited.recipePortionSnapshot?.selectedNutrition.calories, 180)
        XCTAssertEqual(edited.recipePortionSnapshot?.sourceNutrition.calories, 800)
        XCTAssertEqual(edited.recipePortionSnapshot?.nutritionAdjustedForThisLog, true)
        XCTAssertEqual(edited.recipePortionSnapshot?.portionRequiresReview, false)
    }

    func testIncompatibleDetailUnitRetainsSourceWithoutInventingBatchAllocation() throws {
        let original = try RecipePortionRules.foodItem(for: recipe(weight: nil), selection: .init(unit: .servings))
        var edited = original
        edited.servingWeight = 0
        edited = edited.preservingRecipePortion(from: original, quantity: 2, unit: "ladle")
        XCTAssertEqual(edited.recipePortionSnapshot?.sourceNutrition.calories, 800)
        XCTAssertNil(edited.recipePortionSnapshot?.batchFraction)
        XCTAssertNil(edited.recipePortionSnapshot?.servingsEquivalent)
        XCTAssertEqual(edited.recipePortionSnapshot?.portionRequiresReview, true)
        XCTAssertEqual(edited.sourceMetadata?.confidence, .needsReview)
    }

    func testInvalidAmountsAndMissingYieldAreRejected() {
        let source = recipe()
        for amount in [0, -1, Double.nan, .infinity, 1_001] {
            XCTAssertThrowsError(try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings, amount: amount)))
        }
        var invalid = source
        invalid.servings = nil
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: invalid, selection: .init(unit: .batchFraction, amount: 0.5)))
        invalid = source; invalid.cookedWeightGrams = .infinity
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: invalid, selection: .init(unit: .cookedGrams, amount: 100)))
    }

    func testContentRevisionIgnoresObservationClocksAndSeparatesSourceIdentity() throws {
        let first = recipe()
        var second = first
        second.id = "another-library-id"
        second.revisionID = "old-marker"
        second.detailedIngredients?[0].timestamp = Date(timeIntervalSince1970: 1_700_000_000.1234567)
        second.detailedIngredients?[0].sourceMetadata?.createdAt = Date(timeIntervalSince1970: 1_800_000_000.7654321)
        second.detailedIngredients?[0].sourceMetadata?.sourceObservedAt = Date(timeIntervalSince1970: -1.2345678)
        XCTAssertEqual(try RecipePortionRules.revisionID(for: first), try RecipePortionRules.revisionID(for: second))
        second.detailedIngredients?[0].sourceMetadata?.sourceID = "another-product"
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: first), try RecipePortionRules.revisionID(for: second))
    }

    func testProviderRevisionDatesAreStableAcrossSubmicrosecondWirePrecision() throws {
        for time in [1_700_000_000.1234567, -1_700_000_000.1234567, -0.1234567] {
            var first = recipe(), second = first
            first.detailedIngredients?[0].sourceMetadata?.sourceUpdatedAt = Date(timeIntervalSince1970: time)
            second.detailedIngredients?[0].sourceMetadata?.sourceUpdatedAt = Date(timeIntervalSince1970: (time * 1_000_000).rounded() / 1_000_000)
            XCTAssertEqual(try RecipePortionRules.revisionID(for: first), try RecipePortionRules.revisionID(for: second))
        }
    }

    func testRevisionChangesForRealNutrientsYieldAndCookedMass() throws {
        let source = recipe(), original = try RecipePortionRules.revisionID(for: source)
        var changed = source; changed.nutrition.calories += 0.01
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: changed), original)
        changed = source; changed.servings = 5
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: changed), original)
        changed = source; changed.cookedWeightGrams = 801
        XCTAssertNotEqual(try RecipePortionRules.revisionID(for: changed), original)
    }

    func testUnsupportedPortionEvidenceIsRetainedWhenAmountsChange() throws {
        let food = try RecipePortionRules.foodItem(for: recipe(), selection: .init(unit: .servings, amount: 1.5))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(food)) as? [String: Any])
        var evidence = try XCTUnwrap(object["recipePortionSnapshot"] as? [String: Any])
        evidence["schemaVersion"] = 99; object["recipePortionSnapshot"] = evidence
        let original = try JSONDecoder().decode(FoodItem.self, from: JSONSerialization.data(withJSONObject: object))
        let before = try PlanFingerprint.make(original.recipePortionSnapshot)
        let scaled = original.scalingNutritionAndServing(by: 2)
        XCTAssertEqual(scaled.calories, 600)
        XCTAssertEqual(try PlanFingerprint.make(scaled.recipePortionSnapshot), before)
        XCTAssertEqual(scaled.sourceMetadata?.confidence, .needsReview)
        let fresh = FoodItem(name: original.name, calories: 400, servingSize: "2 ladles", servingWeight: 0,
            sourceMetadata: original.sourceMetadata)
            .preservingRecipePortion(from: original, quantity: 2, unit: "ladle")
        XCTAssertEqual(try PlanFingerprint.make(fresh.recipePortionSnapshot), before)
        XCTAssertEqual(fresh.sourceMetadata?.confidence, .needsReview)
    }

    func testPlannedIngredientsScaleOriginalBatchBeforeFinalDisplayRounding() throws {
        var source = recipe()
        source.servings = 3
        let selection = RecipePortionSelection(unit: .servings, amount: 1.5)
        XCTAssertEqual(try RecipePortionRules.ingredients(for: source, selection: selection), ["200 g Beans"])
        source.detailedIngredients = nil
        source.unresolvedIngredients = ["400 g beans"]
        XCTAssertEqual(try RecipePortionRules.ingredients(for: source, selection: selection), ["200 gram beans"])
        let gramPortion = RecipePortionSelection(unit: .cookedGrams, amount: 400)
        XCTAssertEqual(try RecipePortionRules.ingredients(for: source, selection: gramPortion), ["200 gram beans"])
        XCTAssertEqual(source.ingredients, ["400 g beans"])
    }

    func testPlannerPortionEditsUseFrozenNumericRequirementsWithoutStringDrift() throws {
        var source = recipe(); source.servings = 3
        let food = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .servings))
        var meal = PlannedMeal(mealType: "Dinner", recipeID: source.id, foodItem: food,
            ingredients: MealPlanEditingRules.ingredients(for: source))
        XCTAssertEqual(meal.ingredients, ["133.333 g Beans"], "The existing display projection is rounded")
        for _ in 0..<10 {
            meal.portionMultiplier = 1.5
            XCTAssertEqual(try XCTUnwrap(meal.plannedIngredients.first?.quantity), 200, accuracy: 0.000_000_001)
            meal.portionMultiplier = 1
            XCTAssertEqual(try XCTUnwrap(meal.plannedIngredients.first?.quantity), 400 / 3, accuracy: 0.000_000_001)
        }
        meal.portionMultiplier = 1.5
        let restored = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(meal))
        XCTAssertEqual(try XCTUnwrap(restored.plannedIngredients.first?.quantity), 200, accuracy: 0.000_000_001)
        XCTAssertEqual(restored.plannedFood?.recipePortionSnapshot?.ingredientQuantities?.first?.amount, 400)
        XCTAssertEqual(source.resolvedIngredientFoods.first?.servingWeight, 400)
    }

    func testMissingOptionalIngredientQuantitiesKeepsLegacyPlanProjection() throws {
        let food = try RecipePortionRules.foodItem(for: recipe(), selection: .init(unit: .servings))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(food)) as? [String: Any])
        var snapshot = try XCTUnwrap(object["recipePortionSnapshot"] as? [String: Any])
        snapshot.removeValue(forKey: "ingredientQuantities"); object["recipePortionSnapshot"] = snapshot
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.recipePortionSnapshot?.ingredientQuantities)
        let meal = PlannedMeal(mealType: "Dinner", foodItem: restored, ingredients: ["100 g Beans"], portionMultiplier: 1.5)
        XCTAssertEqual(meal.plannedIngredients.first?.quantity, 150)
        XCTAssertEqual(meal.plannedFood?.calories, 300)
    }
}
