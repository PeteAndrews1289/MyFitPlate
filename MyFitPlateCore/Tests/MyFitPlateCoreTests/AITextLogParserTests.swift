import XCTest
@testable import MyFitPlateCore

final class AITextLogParserTests: XCTestCase {
    func testPromptIncludesMealDescriptionAndStrictJSONContract() {
        let prompt = AITextLogParser.createPrompt(for: "6 oz salmon and one cup rice")

        XCTAssertTrue(prompt.contains("6 oz salmon and one cup rice"))
        XCTAssertTrue(prompt.contains("valid JSON object only"))
        XCTAssertTrue(prompt.contains("\"foods\""))
        XCTAssertTrue(prompt.contains("\"itemName\""))
        XCTAssertTrue(prompt.contains("Medical Disclaimer"))
    }

    func testDecodeResponseAndParseMapsNutritionIntoFoodItems() throws {
        let response = try AITextLogParser.decodeResponse(from: """
        {
            "foods": [
                {
                    "itemName": "Salmon",
                    "servingSize": "6 oz",
                    "calories": 340,
                    "protein": 34,
                    "carbs": 0,
                    "fats": 22,
                    "fiber": 0,
                    "calcium": 25,
                    "iron": 1,
                    "potassium": 970,
                    "sodium": 100,
                    "vitaminA": 50,
                    "vitaminC": 0,
                    "vitaminD": 12,
                    "vitaminB12": 4.5,
                    "folate": 25
                },
                {
                    "itemName": "Rice",
                    "servingSize": "1 cup",
                    "calories": 205,
                    "protein": 4,
                    "carbs": 45,
                    "fats": 0.5,
                    "fiber": 0.6,
                    "calcium": null,
                    "iron": null,
                    "potassium": null,
                    "sodium": 1,
                    "vitaminA": null,
                    "vitaminC": null,
                    "vitaminD": null,
                    "vitaminB12": null,
                    "folate": 90
                }
            ]
        }
        """)
        let timestamp = Date(timeIntervalSince1970: 123)
        var nextID = 0

        let foods = AITextLogParser.parse(response, timestamp: timestamp) {
            defer { nextID += 1 }
            return "ai-food-\(nextID)"
        }

        XCTAssertEqual(foods.count, 2)
        XCTAssertEqual(foods[0].id, "ai-food-0")
        XCTAssertEqual(foods[0].name, "Salmon")
        XCTAssertEqual(foods[0].servingSize, "6 oz")
        XCTAssertEqual(foods[0].timestamp, timestamp)
        XCTAssertEqual(foods[0].calories, 340, accuracy: 0.001)
        XCTAssertEqual(foods[0].protein, 34, accuracy: 0.001)
        XCTAssertEqual(foods[0].carbs, 0, accuracy: 0.001)
        XCTAssertEqual(foods[0].fats, 22, accuracy: 0.001)
        XCTAssertEqual(foods[0].fiber ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(foods[0].calcium ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(foods[0].iron ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(foods[0].potassium ?? 0, 970, accuracy: 0.001)
        XCTAssertEqual(foods[0].sodium ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(foods[0].vitaminA ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(foods[0].vitaminD ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(foods[0].vitaminB12 ?? 0, 4.5, accuracy: 0.001)
        XCTAssertEqual(foods[0].folate ?? 0, 25, accuracy: 0.001)

        XCTAssertEqual(foods[1].id, "ai-food-1")
        XCTAssertEqual(foods[1].name, "Rice")
        XCTAssertNil(foods[1].calcium)
        XCTAssertNil(foods[1].iron)
        XCTAssertNil(foods[1].potassium)
        XCTAssertEqual(foods[1].sodium ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(foods[1].folate ?? 0, 90, accuracy: 0.001)
    }

    func testDecodeResponseThrowsParsingErrorForInvalidJSON() {
        XCTAssertThrowsError(try AITextLogParser.decodeResponse(from: "{ not-json")) { error in
            guard case AITextLogError.parsingError(let details) = error else {
                return XCTFail("Expected parsing error, got \(error)")
            }
            XCTAssertFalse(details.isEmpty)
        }
    }

    func testAITextLogErrorDescriptionsAreActionable() {
        XCTAssertEqual(
            AITextLogError.apiError("quota exceeded").errorDescription,
            "An error occurred with the AI service: quota exceeded"
        )
        XCTAssertEqual(
            AITextLogError.networkError(URLError(.notConnectedToInternet)).errorDescription,
            "A network error occurred. Please check your connection and try again."
        )
        XCTAssertEqual(
            AITextLogError.parsingError("missing foods").errorDescription,
            "The AI response could not be understood. Details: missing foods"
        )
    }
}
