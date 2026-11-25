import XCTest
@testable import MyFitPlateCore
final class RecipeImportUnitTests: XCTestCase {
    func testPublishedNutrientUnitsAreConvertedAndAmbiguousUnitsStayUnknown() throws {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Bowl","recipeIngredient":["200 g beans"],"recipeInstructions":"Cook beans.","nutrition":{"calories":"1,000 kJ","proteinContent":"2000 mg","carbohydrateContent":"10 g","fatContent":"0.5 g"}}</script>"#
        let recipe = try XCTUnwrap(RecipeStructuredImport.drafts(html: html, sourceURL: "https://example.com/bowl").first)
        XCTAssertEqual(recipe.nutrition.calories, 1_000 / 4.184, accuracy: 0.000001)
        XCTAssertEqual(recipe.nutrition.protein, 2); XCTAssertEqual(recipe.nutrition.fats, 0.5)
        XCTAssertTrue(recipe.importProvenance?.missingNutritionFields?.isEmpty == true)
        let ambiguous = html.replacingOccurrences(of: "10 g", with: "1,5 g")
        let draft = try XCTUnwrap(RecipeStructuredImport.drafts(html: ambiguous, sourceURL: "https://example.com/bowl").first)
        XCTAssertTrue(draft.importProvenance?.missingNutritionFields?.contains("Carbohydrate") == true)
    }
}
