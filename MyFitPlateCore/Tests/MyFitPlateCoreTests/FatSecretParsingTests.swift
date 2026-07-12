import XCTest
@testable import MyFitPlateCore

/// Regression coverage for the FatSecret detail decoding — the only source of
/// micronutrients on the FatSecret path (search results are description-string previews).
final class FatSecretParsingTests: XCTestCase {

    private func serving(_ json: String) throws -> FatSecretServing {
        try JSONDecoder().decode(FatSecretServing.self, from: Data(json.utf8))
    }

    func testDecodesMicronutrientsIncludingRenamedBVitamins() throws {
        let s = try serving("""
        {
          "calories": "165", "protein": "31", "carbohydrate": "0", "fat": "3.6",
          "serving_description": "100 g", "metric_serving_amount": "100", "metric_serving_unit": "g",
          "calcium": "15", "iron": "1", "potassium": "256", "sodium": "74",
          "thiamin": "0.07", "riboflavin": "0.1", "niacin": "13.7", "pantothenic_acid": "0.9",
          "vitamin_b6": "0.6", "vitamin_c": "0", "magnesium": "29"
        }
        """)

        XCTAssertEqual(s.parsedNutrient(.calories), 165, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.potassium), 256, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.sodium), 74, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.magnesium), 29, accuracy: 0.001)
        // FatSecret names B vitamins by their chemical names; the mapping must hold.
        XCTAssertEqual(s.parsedNutrient(.vitamin_b1), 0.07, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.vitamin_b2), 0.1, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.vitamin_b3), 13.7, accuracy: 0.001)
        XCTAssertEqual(s.parsedNutrient(.vitamin_b5), 0.9, accuracy: 0.001)
        XCTAssertEqual(s.parsedServingWeightGrams ?? 0, 100, accuracy: 0.001)
    }

    func testTolerantParsingOfMessyValues() throws {
        let s = try serving("""
        {
          "calories": "210", "protein": "8,5", "carbohydrate": "<1", "fat": "N/A",
          "serving_description": "1 bar", "metric_serving_amount": "2", "metric_serving_unit": "oz"
        }
        """)

        XCTAssertEqual(s.parsedNutrient(.protein), 8.5, accuracy: 0.001, "European decimal commas parse")
        XCTAssertEqual(s.parsedNutrient(.carbohydrate), 1, accuracy: 0.001, "'<1' strips the comparator")
        XCTAssertEqual(s.parsedNutrient(.fat), 0, accuracy: 0.001, "N/A reads as 0")
        XCTAssertEqual(s.parsedServingWeightGrams ?? 0, 2 * 28.3495, accuracy: 0.01, "oz converts to grams")
    }

    func testOptionalParsingPreservesReportedZeroAndMissingState() throws {
        let s = try serving("""
        {
          "calories": "100", "vitamin_c": "0", "sodium": "N/A"
        }
        """)

        XCTAssertEqual(s.parsedOptionalNutrient(.vitamin_c), 0)
        XCTAssertNil(s.parsedOptionalNutrient(.sodium))
        XCTAssertNil(s.parsedOptionalNutrient(.fiber))
        XCTAssertEqual(s.parsedNutrient(.fiber), 0, "Required macro callers retain their zero fallback")
    }
}
