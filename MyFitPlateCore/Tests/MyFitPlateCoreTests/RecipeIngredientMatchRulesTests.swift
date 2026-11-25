import XCTest
@testable import MyFitPlateCore

final class RecipeIngredientMatchRulesTests: XCTestCase {
    private func food(quantity: Double? = 100, unit: String? = "g", grams: Double = 100) -> FoodItem {
        FoodItem(id: "rice", name: "Rice", calories: 100, protein: 4, carbs: 20, fats: 2,
            fiber: 3, servingSize: "Selected amount", servingWeight: grams,
            sourceMetadata: .database(.usda, sourceName: "USDA", sourceID: "rice"),
            calcium: 12, sodium: 30, quantityValue: quantity, servingUnit: unit)
    }

    func testMatching400GramsScalesEveryNutrientWithoutChangingSelectedFood() throws {
        let selected = food()
        let result = RecipeIngredientMatchRules.suggestion(sourceText: "400 g Rice", selectedFood: selected)
        XCTAssertTrue(result.sourceAmountMatched)
        XCTAssertEqual(result.food.quantityValue, 400)
        XCTAssertEqual(result.food.servingUnit, "g")
        XCTAssertEqual(result.food.servingWeight, 400)
        XCTAssertEqual(result.food.calories, 400)
        XCTAssertEqual(result.food.protein, 16)
        XCTAssertEqual(result.food.fiber, 12)
        XCTAssertEqual(result.food.calcium, 48)
        XCTAssertEqual(result.food.sodium, 120)
        XCTAssertNil(result.food.vitaminD)
        XCTAssertEqual(result.food.sourceMetadata, selected.sourceMetadata)
        XCTAssertEqual(selected.quantityValue, 100)
        XCTAssertEqual(selected.calories, 100)
        let edited = try XCTUnwrap(RecipeIngredientMatchRules.reviewedAmount(200, for: result.food))
        XCTAssertEqual(edited.calories, 200)
        XCTAssertEqual(edited.fiber, 6)
        XCTAssertNil(edited.vitaminD)
    }

    func testCompatibleMassVolumeAndExactFractionsPreserveSourceAmount() throws {
        XCTAssertEqual(RecipeIngredientMatchRules.suggestedAmount(sourceText: "0.5 kg rice", selectedFood: food()), 500)
        XCTAssertEqual(RecipeIngredientMatchRules.suggestedAmount(sourceText: "1,200 g rice", selectedFood: food()), 1_200)
        let milliliters = food(quantity: 100, unit: "ml", grams: 0)
        let cup = try XCTUnwrap(RecipeIngredientMatchRules.suggestedAmount(sourceText: "½ cup milk", selectedFood: milliliters))
        XCTAssertEqual(cup, 118.29411825, accuracy: 0.000001)
        let third = try XCTUnwrap(RecipeIngredientMatchRules.suggestedAmount(sourceText: "⅓ cup milk", selectedFood: milliliters))
        XCTAssertEqual(third, 236.5882365 / 3, accuracy: 0.000001)
        XCTAssertEqual(RecipeIngredientMatchRules.suggestedAmount(sourceText: "2 fl oz milk", selectedFood: milliliters), 59.147059125)
        let weightedServing = food(quantity: 1, unit: "serving", grams: 100)
        let matched = RecipeIngredientMatchRules.suggestion(sourceText: "400 g rice", selectedFood: weightedServing)
        XCTAssertTrue(matched.sourceAmountMatched)
        XCTAssertEqual(matched.food.calories, 400)
        XCTAssertEqual(matched.food.quantityValue, 400)
        XCTAssertEqual(matched.food.servingUnit, "g")
    }

    func testExplicitSameCountIsAllowedButPackagesAndDifferentCountsAreNotInferred() {
        let slice = food(quantity: 1, unit: "slice", grams: 30)
        let result = RecipeIngredientMatchRules.suggestion(sourceText: "2 slices bread", selectedFood: slice)
        XCTAssertTrue(result.sourceAmountMatched)
        XCTAssertEqual(result.food.quantityValue, 2)
        XCTAssertEqual(result.food.servingWeight, 60)
        XCTAssertEqual(result.food.calories, 200)
        for source in ["2 bread", "2 cloves garlic", "2 cans beans", "2 packages rice", "1 pinch salt"] {
            XCTAssertNil(RecipeIngredientMatchRules.suggestedAmount(sourceText: source, selectedFood: slice), source)
        }
        XCTAssertNil(RecipeIngredientMatchRules.suggestedAmount(sourceText: "2 cans beans", selectedFood: food(quantity: 1, unit: "can", grams: 400)))
    }

    func testUnknownRangesAndDensityMismatchRemainExplicitReviewWithoutAutomaticReplacement() {
        for source in ["Rice to taste", "1-2 g rice", "1 to 2 cups milk", "400g rice", "0 g rice", "1 cup rice", "2 large eggs"] {
            let result = RecipeIngredientMatchRules.suggestion(sourceText: source, selectedFood: food())
            XCTAssertFalse(result.sourceAmountMatched, source)
            XCTAssertEqual(result.food.calories, 100, source)
            XCTAssertEqual(result.food.quantityValue, 100, source)
        }
        let unknown = food(quantity: nil, unit: nil, grams: 0)
        let fallback = RecipeIngredientMatchRules.suggestion(sourceText: "400 g rice", selectedFood: unknown)
        XCTAssertFalse(fallback.sourceAmountMatched)
        XCTAssertEqual(fallback.food.quantityValue, 1)
        XCTAssertEqual(fallback.food.servingUnit, "selected amount")
    }

    func testInvalidManualAmountsCannotCreateNonfiniteOrNegativeNutrition() {
        for amount in [0, -1, Double.nan, .infinity, 1_000_001] {
            XCTAssertNil(RecipeIngredientMatchRules.reviewedAmount(amount, for: food()))
        }
        var invalid = food(); invalid.calories = .nan
        XCTAssertNil(RecipeIngredientMatchRules.reviewedAmount(100, for: invalid))
    }

    func testMatchedRecipeIngredientKeepsFrozenPortionEvidenceWhenScaled() throws {
        let source = Recipe(id: "r", name: "Rice", ingredients: ["400 g rice"], instructions: ["Cook"],
            nutrition: Nutrition(calories: 400), servings: 4, nutritionBasis: .wholeRecipe,
            cookedWeightGrams: 800, ingredientBasis: .wholeRecipe)
        let selected = try RecipePortionRules.foodItem(for: source, selection: .init(unit: .cookedGrams, amount: 100))
        let matched = RecipeIngredientMatchRules.suggestion(sourceText: "400 g rice", selectedFood: selected)
        XCTAssertTrue(matched.sourceAmountMatched)
        XCTAssertEqual(matched.food.calories, 200)
        XCTAssertEqual(matched.food.recipePortionSnapshot?.selectedNutrition.calories, 200)
        XCTAssertEqual(matched.food.recipePortionSnapshot?.selection.amount, 400)
        XCTAssertEqual(matched.food.recipePortionSnapshot?.sourceIngredientBasis, .wholeRecipe)
    }
}
