import XCTest
@testable import MyFitPlateCore

@MainActor
final class UnknownIngredientQuantityTests: XCTestCase {
    private let date = Calendar.current.startOfDay(for: Date())
    private func meal(_ ingredients: [String]) -> PlannedMeal {
        PlannedMeal(id: "unknown-ingredient", mealType: "Dinner", foodItem: FoodItem(id: "food", name: "Rice and eggs", calories: 400, protein: 20, carbs: 60, fats: 10), ingredients: ingredients)
    }
    func testUnknownSaltNeverDeductsCountStockOrProducesAnExactShoppingAmount() throws {
        let planned = try MealPlanCookingRules.configuring(meal(["salt to taste", "100 g rice", "2 eggs"]), date: date, cookingPortions: 4)
        let batch = try XCTUnwrap(planned.cookingBatch)
        XCTAssertFalse(batch.ingredientsPerPortion[0].hasKnownAmount)
        XCTAssertTrue(batch.ingredientsPerPortion[1].hasKnownAmount)
        XCTAssertTrue(batch.ingredientsPerPortion[2].hasKnownAmount)
        var salt = PantryItem(name: "Salt to taste", quantity: 20, unit: "item")
        salt.quantityVerified = true; salt.preparation = "Raw"
        XCTAssertThrowsError(try InventoryPlanningRules.cooked(batch: batch, originalMeal: planned, stock: [salt], selectedLots: [0: salt.id], userID: "owner", bestBefore: nil))
        let acceptedUntracked = try InventoryPlanningRules.cooked(batch: batch, originalMeal: planned, stock: [salt], selectedLots: [:], userID: "owner", bestBefore: nil)
        XCTAssertTrue(acceptedUntracked.before.isEmpty)
        let day = MealPlanDay(id: MealPlanEditingRules.dayID(date), date: date, meals: [planned])
        let groceries = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric)
        let unresolved = try XCTUnwrap(groceries.first { $0.quantityUnknown == true })
        let coverage = InventoryPlanningRules.coverage(items: [unresolved], stock: [salt])[0]
        XCTAssertEqual(coverage.available, 0)
        XCTAssertEqual(coverage.needToBuy, 0)
        let share = GroceryPresentationRules.shareText(items: [unresolved], stock: [salt], starting: date, includeChecked: false)
        XCTAssertTrue(share.contains("amount unconfirmed"))
        XCTAssertFalse(share.contains("buy 1 item")); XCTAssertFalse(share.contains("buy 4 item"))
        XCTAssertThrowsError(try InventoryPlanningRules.purchasing(item: unresolved, totalBought: 0, transferAmount: 0, userID: "owner"))
        let manualActual = try InventoryPlanningRules.purchasing(item: unresolved, totalBought: 5, transferAmount: 5, userID: "owner")
        XCTAssertEqual(manualActual.after[0].quantity, 5)
        XCTAssertEqual(manualActual.after[0].quantityVerified, true)
        let prep = MealPrepService(); prep.aggregate(days: [day])
        XCTAssertTrue(prep.bulkIngredients.values.flatMap { $0 }.contains { $0.quantityUnknown })
    }
    func testExplicitMassAndEggCountRemainValidAndUnknownCannotMergeIntoKnown() throws {
        let planned = try MealPlanCookingRules.configuring(meal(["100 g rice", "2 eggs", "rice"]), date: date, cookingPortions: 4)
        let batch = planned.cookingBatch!
        var rice = PantryItem(name: "Rice", quantity: 1_000, unit: "g"); rice.quantityVerified = true
        var eggs = PantryItem(name: "Eggs", quantity: 12, unit: "item"); eggs.quantityVerified = true
        let operation = try InventoryPlanningRules.cooked(batch: batch, originalMeal: planned, stock: [rice, eggs], selectedLots: [0: rice.id, 1: eggs.id], userID: "owner", bestBefore: nil)
        XCTAssertEqual(operation.after.first { $0.id == rice.id }?.quantity, 600)
        XCTAssertEqual(operation.after.first { $0.id == eggs.id }?.quantity, 4)
        let day = MealPlanDay(id: MealPlanEditingRules.dayID(date), date: date, meals: [planned])
        let rows = GroceryListBuilder.makeGroceryList(from: [day], unitSystem: .metric)
        XCTAssertEqual(rows.first { $0.name == "Rice" && $0.quantityUnknown != true }?.quantity, 400)
        XCTAssertEqual(rows.filter { $0.name == "Rice" }.count, 2)
    }
    func testOlderBatchSnapshotsInferKnownOnlyFromExplicitSourceAndPreserveTheirNumbers() throws {
        struct OldIngredient: Encodable {
            let name: String
            let quantity: Double
            let unit: String
            let originalText: String
        }
        for (text, known) in [("salt to taste", false), ("100 g rice", true), ("2 eggs", true), ("1-2 eggs", false), ("1 to 2 eggs", false), ("1 – 2 eggs", false), ("0 g salt", false), ("1/0 tsp salt", false)] {
            let legacy = OldIngredient(name: "Original", quantity: 123.456, unit: "item", originalText: text)
            let decoded = try JSONDecoder().decode(MealCookingIngredient.self, from: JSONEncoder().encode(legacy))
            XCTAssertNil(decoded.amountKnown)
            XCTAssertEqual(decoded.hasKnownAmount, known)
            XCTAssertEqual(decoded.quantity, 123.456)
        }
        XCTAssertEqual(InventoryQuantityRules.explicitLeadingAmount("½ cup rice"), 0.5)
        XCTAssertEqual(InventoryQuantityRules.explicitLeadingAmount("1 1/2 cups rice"), 1.5)
        XCTAssertEqual(InventoryQuantityRules.explicitLeadingAmount("- 100 g rice"), 100)
        XCTAssertEqual(IngredientLineParser.normalizedIngredient(from: "1,000 g rice").quantity, 1_000)
    }
    func testPositiveExplicitShoppingOverrideSurvivesUnknownRecipeRegeneration() {
        let day = MealPlanDay(id: MealPlanEditingRules.dayID(date), date: date, meals: [meal(["salt to taste"])])
        let generated = GroceryListBuilder.makeGroceryList(from: [day], starting: date, unitSystem: .metric)
        var reviewed = generated[0]; reviewed.quantity = 20; reviewed.unit = "g"; reviewed.quantityUnknown = false
        let reopened = GroceryListBuilder.mergeGroceryItems(generatedItems: generated, existingItems: [reviewed])
        XCTAssertEqual(reopened[0].id, reviewed.id)
        XCTAssertEqual(reopened[0].quantity, 20)
        XCTAssertEqual(reopened[0].unit, "g")
        XCTAssertEqual(reopened[0].quantityUnknown, false)
    }
}
