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
              "potassium_100g": 0.3,
              "vitamin-c_100g": 0.06
            }
          }
        }
        """
        let item = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: data(json)))

        XCTAssertEqual(item.id, "off_12345")
        XCTAssertEqual(item.name, "Test Bar")
        XCTAssertEqual(item.calories, 160, accuracy: 0.001)
        XCTAssertEqual(item.protein, 8, accuracy: 0.001)
        XCTAssertEqual(item.carbs, 20, accuracy: 0.001)
        XCTAssertEqual(item.fats, 4, accuracy: 0.001)
        XCTAssertEqual(item.fiber ?? 0, 2.4, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "40g")
        XCTAssertEqual(item.servingWeight, 40, accuracy: 0.001)
        // grams/100g -> mg
        XCTAssertEqual(item.sodium ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(item.calcium ?? 0, 48, accuracy: 0.001)
        XCTAssertEqual(item.iron ?? 0, 3.2, accuracy: 0.001)
        // Regression: potassium was the one mineral missing the g->mg conversion.
        XCTAssertEqual(item.potassium ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(item.vitaminC ?? 0, 24, accuracy: 0.001)
    }

    func testParsesFullVitaminAndMineralPanelWithCanonicalUnits() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "rich-panel",
            "product_name": "Fortified Food",
            "serving_size": "50 g",
            "nutriments": {
              "energy-kcal_100g": 200,
              "proteins_100g": 10,
              "carbohydrates_100g": 20,
              "fat_100g": 8,
              "calcium_100g": 0.1,
              "iron_100g": 0.01,
              "potassium_100g": 0.4,
              "sodium_100g": 0.2,
              "vitamin-a_100g": 0.00009,
              "vitamin-c_100g": 0.06,
              "vitamin-d_100g": 0.00001,
              "vitamin-b12_100g": 0.000002,
              "vitamin-b12_serving": 0.000003,
              "vitamin-b9_100g": 0.0004,
              "magnesium_100g": 0.1,
              "phosphorus_100g": 0.2,
              "zinc_100g": 0.01,
              "copper_100g": 0.001,
              "manganese_100g": 0.002,
              "selenium_100g": 0.00006,
              "vitamin-b1_100g": 0.0012,
              "vitamin-b2_100g": 0.0014,
              "vitamin-pp_100g": 0.016,
              "pantothenic-acid_100g": 0.005,
              "vitamin-b6_100g": 0.0013,
              "vitamin-e_100g": 0.015,
              "vitamin-k_100g": 0.00012
            }
          }
        }
        """

        let item = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: data(json)))

        XCTAssertEqual(item.reportedVitaminMineralCount, 22)
        XCTAssertEqual(item.vitaminA ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(item.vitaminD ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(item.vitaminB12 ?? 0, 3, accuracy: 0.001, "Per-serving values win")
        XCTAssertEqual(item.folate ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(item.magnesium ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(item.copper ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(item.selenium ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(item.vitaminB3 ?? 0, 8, accuracy: 0.001, "Open Food Facts vitamin-pp maps to B3")
        XCTAssertEqual(item.vitaminB5 ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(item.vitaminK ?? 0, 60, accuracy: 0.001)
    }

    func testStatusZeroReturnsNil() throws {
        XCTAssertNil(try OpenFoodFactsParser.foodItem(from: data(#"{"status": 0}"#)))
    }

    func testMissingProductReturnsNil() throws {
        XCTAssertNil(try OpenFoodFactsParser.foodItem(from: data(#"{"status": 1}"#)))
    }

    func testRejectsProductsWithoutNutrition() throws {
        let json = #"{"status": 1, "product": {"code": "x", "nutriments": {}}}"#
        XCTAssertNil(try OpenFoodFactsParser.foodItem(from: data(json)))
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try OpenFoodFactsParser.foodItem(from: data("not json")))
    }
}
