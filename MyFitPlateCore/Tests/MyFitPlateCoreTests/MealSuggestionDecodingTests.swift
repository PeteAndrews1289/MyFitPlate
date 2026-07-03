import XCTest
@testable import MyFitPlateCore

/// The regression that shipped a dead feature: MealSuggestion's synthesized decoder
/// required "id" and "title" keys the AI prompt never asks for, so every generated
/// suggestion failed to decode. These tests decode exactly what the prompt specifies.
final class MealSuggestionDecodingTests: XCTestCase {

    private let aiShapedJSON = """
    {
      "mealName": "Turkey pepper skillet",
      "calories": 620,
      "protein": 48,
      "carbs": 55,
      "fats": 21,
      "ingredients": ["Ground turkey", "Bell peppers", "Brown rice"],
      "instructions": "Brown the turkey.\\nAdd peppers and rice."
    }
    """

    func testDecodesTheExactShapeThePromptAsksFor() throws {
        let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: Data(aiShapedJSON.utf8))

        XCTAssertEqual(suggestion.mealName, "Turkey pepper skillet")
        XCTAssertEqual(suggestion.title, "Turkey pepper skillet", "Title falls back to the meal name")
        XCTAssertEqual(suggestion.calories, 620, accuracy: 0.001)
        XCTAssertEqual(suggestion.ingredients.count, 3)
    }

    func testDecodesMinimalResponseWithoutOptionalExtras() throws {
        let minimal = #"{"mealName": "Omelet", "calories": 320, "protein": 24, "carbs": 4, "fats": 22}"#
        let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: Data(minimal.utf8))

        XCTAssertEqual(suggestion.mealName, "Omelet")
        XCTAssertTrue(suggestion.ingredients.isEmpty)
        XCTAssertEqual(suggestion.instructions, "")
    }

    func testRoundTripWithFullInit() throws {
        let original = MealSuggestion(title: "Custom", calories: 500, mealName: "Bowl", protein: 40, carbs: 50, fats: 15)
        let decoded = try JSONDecoder().decode(MealSuggestion.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.title, "Custom")
        XCTAssertEqual(decoded.calories, 500, accuracy: 0.001)
    }

    func testExtractJSONPayloadStripsMarkdownFences() {
        let fenced = "```json\n\(aiShapedJSON)\n```"
        let extracted = InsightsRules.extractJSONPayload(fenced)

        XCTAssertTrue(extracted.hasPrefix("{"))
        XCTAssertTrue(extracted.hasSuffix("}"))
        XCTAssertNoThrow(try JSONDecoder().decode(MealSuggestion.self, from: Data(extracted.utf8)))
    }

    func testExtractJSONPayloadPassesCleanJSONThrough() {
        XCTAssertEqual(InsightsRules.extractJSONPayload(aiShapedJSON).first, "{")
    }
}
