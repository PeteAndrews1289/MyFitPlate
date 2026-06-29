import XCTest
@testable import MyFitPlateCore

final class OpenFoodFactsParserTests: XCTestCase {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesValidProductWithMineralUnitConversion() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "12345",
            "product_name": "Test Bar",
            "serving_size": "40g",
            "nutriments": {
              "energy-kcal_100g": 400,
              "proteins_100g": 20,
              "carbohydrates_100g": 50,
              "fat_100g": 10,
              "saturated-fat_100g": 4,
              "fiber_100g": 6,
              "sodium_100g": 0.5,
              "calcium_100g": 0.12,
              "iron_100g": 0.008,
              "vitamin-c_100g": 0.06
            }
          }
        }
        """
        let item = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: data(json)))

        XCTAssertEqual(item.id, "12345")
        XCTAssertEqual(item.name, "Test Bar")
        XCTAssertEqual(item.calories, 400, accuracy: 0.001)
        XCTAssertEqual(item.protein, 20, accuracy: 0.001)
        XCTAssertEqual(item.carbs, 50, accuracy: 0.001)
        XCTAssertEqual(item.fats, 10, accuracy: 0.001)
        XCTAssertEqual(item.fiber ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "40g")
        XCTAssertEqual(item.servingWeight, 100, accuracy: 0.001)
        // grams/100g -> mg
        XCTAssertEqual(item.sodium ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(item.calcium ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(item.iron ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(item.vitaminC ?? 0, 60, accuracy: 0.001)
    }

    func testStatusZeroReturnsNil() throws {
        XCTAssertNil(try OpenFoodFactsParser.foodItem(from: data(#"{"status": 0}"#)))
    }

    func testMissingProductReturnsNil() throws {
        XCTAssertNil(try OpenFoodFactsParser.foodItem(from: data(#"{"status": 1}"#)))
    }

    func testDefaultsWhenFieldsMissing() throws {
        let json = #"{"status": 1, "product": {"code": "x", "nutriments": {}}}"#
        let item = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: data(json)))
        XCTAssertEqual(item.name, "Unknown Product")
        XCTAssertEqual(item.servingSize, "100g")
        XCTAssertEqual(item.calories, 0, accuracy: 0.001)
        XCTAssertNil(item.calcium)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try OpenFoodFactsParser.foodItem(from: data("not json")))
    }
}
