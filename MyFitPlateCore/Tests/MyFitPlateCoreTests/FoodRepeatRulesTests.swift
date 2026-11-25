import XCTest
@testable import MyFitPlateCore

final class FoodRepeatRulesTests: XCTestCase {
    func testChangedPortionScalesMacroMicroWeightAndStructuredQuantityTogether() throws {
        var original = FoodItem(id: "oats", name: "Oats", calories: 300, protein: 12, carbs: 50, fats: 8,
                                fiber: 6, servingSize: "2 cups", servingWeight: 200, calcium: 100, sodium: 20)
        original.quantityValue = 2
        original.servingUnit = "cup"
        let half = try XCTUnwrap(FoodRepeatRules.adjusting(original, by: 0.5))
        XCTAssertEqual(half.calories, 150)
        XCTAssertEqual(half.protein, 6)
        XCTAssertEqual(half.calcium, 50)
        XCTAssertEqual(half.fiber, 3)
        XCTAssertEqual(half.servingWeight, 100)
        XCTAssertEqual(half.quantityValue, 1)
        XCTAssertEqual(half.servingSize, "1 x cup")
        let base = ServingNutritionCalculator.baseServing(from: half)
        XCTAssertEqual(base.calories * (half.quantityValue ?? 1), half.calories, accuracy: 0.001)
        XCTAssertNil(half.vitaminD)
        XCTAssertEqual(original.calories, 300)
    }

    func testSkippedAndInvalidAmountsCannotCreateEntries() {
        let food = FoodItem(id: "oats", name: "Oats", calories: 300)
        for amount in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(FoodRepeatRules.adjusting(food, by: amount))
        }
        XCTAssertEqual(FoodRepeatRules.adjusting(food, by: 1)?.servingSize, food.servingSize)
    }
}
