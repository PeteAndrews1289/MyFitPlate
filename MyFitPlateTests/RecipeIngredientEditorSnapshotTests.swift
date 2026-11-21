import XCTest
import MyFitPlateCore
@testable import MyFitPlate

final class RecipeIngredientEditorSnapshotTests: XCTestCase {
    private func ingredient() -> FoodItem {
        let metadata = FoodSourceMetadata(sourceType: .fatSecret, confidence: .databaseMatch, reviewStatus: .notRequired,
            sourceName: "Synthetic saved reference", sourceID: "reference-rice", createdAt: Date(timeIntervalSince1970: 100),
            sourceObservedAt: Date(timeIntervalSince1970: 101), evidenceLineage: .licensedDatabase)
        return FoodItem(id: "stable-ingredient", name: "Reference rice", calories: 640, protein: 12, carbs: 144, fats: 0,
            servingSize: "180 g", servingWeight: 180, sourceMetadata: metadata, sodium: 0, quantityValue: 180, servingUnit: "g")
    }
    func testSameIdentityQuantityChangeInvalidatesSnapshotAndKeepsSource() throws {
        let original = ingredient()
        let adjusted = try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(original, newQuantity: 400))
        XCTAssertEqual(original, adjusted, "Global FoodItem equality stays identity-only")
        XCTAssertNotEqual(RecipeIngredientEditorSnapshot([original]), RecipeIngredientEditorSnapshot([adjusted]),
            "Recipe views and rows must observe actual amount and nutrition changes")
        XCTAssertEqual(adjusted.id, original.id)
        XCTAssertEqual(adjusted.quantityValue, 400); XCTAssertEqual(adjusted.servingWeight, 400)
        XCTAssertEqual(adjusted.calories, 1_422.222222222222, accuracy: 0.000001)
        XCTAssertEqual(adjusted.protein, 26.6666666666667, accuracy: 0.000001)
        XCTAssertEqual(adjusted.carbs, 320, accuracy: 0.000001); XCTAssertEqual(adjusted.fats, 0)
        XCTAssertEqual(adjusted.sourceMetadata, original.sourceMetadata)
        XCTAssertEqual(adjusted.sodium, 0); XCTAssertNil(adjusted.vitaminC)
    }
    func testEachDigitUsesTheUpdatedAmountWithoutCompoundingOrReplacingIdentity() throws {
        var state = RecipeIngredientEditorSnapshot([ingredient()])
        for amount in [4.0, 40.0, 400.0] {
            let old = state
            let next = try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(state.ingredients[0], newQuantity: amount))
            state = RecipeIngredientEditorSnapshot([next])
            XCTAssertNotEqual(state, old)
            XCTAssertEqual(state.ingredients[0].id, "stable-ingredient")
            XCTAssertEqual(state.ingredients[0].calories, 640 * amount / 180, accuracy: 0.000001)
        }
    }
    func testUnchangedSnapshotIsEqualButQuantitySourceAndOptionalNutrientsAreObserved() {
        let original = ingredient(), opening = RecipeIngredientEditorSnapshot([ingredient()])
        XCTAssertEqual(opening, RecipeIngredientEditorSnapshot([original]))
        var nutrient = original; nutrient.vitaminC = 0
        XCTAssertNotEqual(opening, RecipeIngredientEditorSnapshot([nutrient]), "Unknown and explicit zero differ")
        var source = original; source.sourceMetadata?.sourceObservedAt = Date(timeIntervalSince1970: 102)
        XCTAssertNotEqual(opening, RecipeIngredientEditorSnapshot([source]))
        var amount = original; amount.quantityValue = 181
        XCTAssertNotEqual(opening, RecipeIngredientEditorSnapshot([amount]))
        XCTAssertNotEqual(opening, RecipeIngredientEditorSnapshot([]))
    }
    func testAdjustedStateFeedsWholeRecipeAndPersonalPortionWithoutChangingOriginal() throws {
        let original = ingredient()
        var recipe = Recipe(id: "recipe", name: "Four portions", ingredients: ["180 g Reference rice"], detailedIngredients: [original],
            instructions: ["Cook"], nutrition: Nutrition.total(for: [original]), servings: 4,
            nutritionBasis: .wholeRecipe, nutritionOrigin: .ingredients, unresolvedIngredients: [], cookedWeightGrams: 800)
        recipe.revisionID = try RecipePortionRules.revisionID(for: recipe)
        let snapshot = RecipeIngredientEditorSnapshot([try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(original, newQuantity: 400))])
        var editor = RecipeEditingState(recipe: recipe); editor.ingredients = snapshot.ingredients; editor.nutritionChoice = .recalculate
        let revised = try editor.makeRecipe(name: recipe.name, instructions: recipe.instructions)
        XCTAssertEqual(revised.nutrition.calories, 1_422.222222222222, accuracy: 0.000001)
        let serving = try RecipePortionRules.foodItem(for: revised, selection: .init(unit: .servings, amount: 1))
        XCTAssertEqual(serving.calories, 355.5555555555556, accuracy: 0.000001)
        let grams = try RecipePortionRules.foodItem(for: revised, selection: .init(unit: .cookedGrams, amount: 200))
        XCTAssertEqual(grams.calories, serving.calories, accuracy: 0.000001)
        XCTAssertEqual(recipe.nutrition.calories, 640); XCTAssertEqual(recipe.resolvedIngredientFoods[0].servingWeight, 180)
        XCTAssertEqual(revised.resolvedIngredientFoods[0].id, original.id)
        XCTAssertEqual(revised.resolvedIngredientFoods[0].sourceMetadata, original.sourceMetadata)
    }
    @MainActor
    func testEditableQuantityTextRoundTripsFractionsLargeAmountsAndFullDoublePrecision() throws {
        let amounts = [1.25, 1_000, 1_250.125, 0.125, 0.1, 0.1.nextUp, 1.2345678901234567, 0.00000001]
        for amount in amounts {
            let text = RecipeLoggingIngredientRow.formattedQuantity(amount)
            XCTAssertEqual(try XCTUnwrap(Double(text)), amount, "Recovery must not round the stored ingredient amount")
            XCTAssertFalse(text.contains(","), "Grouped text would be parsed as a decimal-comma amount")
            XCTAssertFalse(text.contains(where: \.isWhitespace))
        }
        XCTAssertEqual(RecipeLoggingIngredientRow.formattedQuantity(400), "400")
        XCTAssertEqual(RecipeLoggingIngredientRow.formattedQuantity(1_000), "1000")
        XCTAssertEqual(RecipeLoggingIngredientRow.formattedQuantity(1_250.125), "1250.125")
        let restored = try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(ingredient(), newQuantity: 1_250.125))
        let parsed = try XCTUnwrap(Double(RecipeLoggingIngredientRow.formattedQuantity(try XCTUnwrap(restored.quantityValue))))
        let unchanged = try XCTUnwrap(RecipeIngredientQuantityRules.adjustedIngredient(restored, newQuantity: parsed))
        XCTAssertEqual(unchanged.servingWeight, restored.servingWeight)
        XCTAssertEqual(unchanged.calories, restored.calories)
        XCTAssertEqual(unchanged.protein, restored.protein)
        XCTAssertEqual(unchanged.carbs, restored.carbs)
        XCTAssertEqual(unchanged.id, restored.id); XCTAssertEqual(unchanged.sourceMetadata, restored.sourceMetadata)
    }

}
