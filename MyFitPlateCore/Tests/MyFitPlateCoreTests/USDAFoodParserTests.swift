import XCTest
@testable import MyFitPlateCore

final class USDAFoodParserTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testScalesToServingGramsAndCleansNameAndUsesHouseholdServing() throws {
        // serving 50 g => scale 0.5; "APPLE, RAW" => "Apple"; household text wins for serving label.
        let json = """
        {
          "foods": [
            {
              "fdcId": 1102702,
              "description": "APPLE, RAW",
              "servingSize": 50,
              "servingSizeUnit": "g",
              "householdServingFullText": "1 medium",
              "foodNutrients": [
                {"nutrientNumber": "208", "value": 52},
                {"nutrientNumber": "203", "value": 0.3},
                {"nutrientNumber": "205", "value": 14},
                {"nutrientNumber": "204", "value": 0},
                {"nutrientNumber": "301", "value": 6}
              ]
            }
          ]
        }
        """
        let items = try USDAFoodParser.foodItems(from: data(json))
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(item.id, "usda_1102702")
        XCTAssertEqual(item.name, "Apple")
        XCTAssertEqual(item.calories, 26, accuracy: 0.001)     // 52 * 0.5
        XCTAssertEqual(item.protein, 0.15, accuracy: 0.001)    // 0.3 * 0.5
        XCTAssertEqual(item.carbs, 7, accuracy: 0.001)         // 14 * 0.5
        XCTAssertEqual(item.fats, 0, accuracy: 0.001)
        XCTAssertEqual(item.calcium ?? 0, 3, accuracy: 0.001)  // 6 * 0.5
        XCTAssertNil(item.saturatedFat)                        // not present -> nil
        XCTAssertEqual(item.servingSize, "1 medium")
        XCTAssertEqual(item.servingWeight, 50, accuracy: 0.001)
    }

    func testZeroValuedOptionalNutrientBecomesNilAndDefaultServing() throws {
        // No serving info => 100 g default, scale 1.0; a 0-valued optional nutrient => nil.
        let json = """
        {"foods": [{"fdcId": 999, "description": "Plain Thing",
          "foodNutrients": [
            {"nutrientNumber": "208", "value": 100},
            {"nutrientNumber": "301", "value": 0}
          ]}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.calories, 100, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "100 g")
        XCTAssertEqual(item.servingWeight, 100, accuracy: 0.001)
        XCTAssertNil(item.calcium)  // 0 filtered out
    }

    func testServingDescriptionFromSizeWhenNoHouseholdText() throws {
        let json = """
        {"foods": [{"fdcId": 1, "description": "Foo", "servingSize": 30,
          "servingSizeUnit": "g", "foodNutrients": []}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.servingSize, "30 g")
        XCTAssertEqual(item.servingWeight, 30, accuracy: 0.001)
        XCTAssertEqual(item.calories, 0, accuracy: 0.001)
    }

    func testNonGramServingUnitDoesNotScale() throws {
        // serving unit "ml" => grams fall back to 100 (scale 1.0), but label uses the declared size.
        let json = """
        {"foods": [{"fdcId": 2, "description": "Juice", "servingSize": 240,
          "servingSizeUnit": "ml",
          "foodNutrients": [{"nutrientNumber": "208", "value": 45}]}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.calories, 45, accuracy: 0.001)   // not scaled
        XCTAssertEqual(item.servingWeight, 100, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "240 ml")
    }

    func testEmptyAndMultipleFoods() throws {
        XCTAssertTrue(try USDAFoodParser.foodItems(from: data(#"{"foods": []}"#)).isEmpty)
        let two = """
        {"foods": [
          {"fdcId": 1, "description": "A", "foodNutrients": []},
          {"fdcId": 2, "description": "B", "foodNutrients": []}
        ]}
        """
        XCTAssertEqual(try USDAFoodParser.foodItems(from: data(two)).count, 2)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try USDAFoodParser.foodItems(from: data("not json")))
    }
}
