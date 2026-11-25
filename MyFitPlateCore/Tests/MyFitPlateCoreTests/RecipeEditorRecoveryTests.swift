import XCTest
@testable import MyFitPlateCore

final class RecipeEditorRecoveryTests: XCTestCase {
    private struct Form: Codable { var identity: String; var text: String }
    func testResolvedRecipeCanOnlyClearItsExactEditorCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let a = Form(identity: "editor-a", text: "submitted A"), b = Form(identity: "editor-b", text: "unsaved B")
        try store.save(a, userID: "owner", scope: "recipe-editor-A")
        try store.save(b, userID: "owner", scope: "recipe-editor-B")
        let fingerprint = try PlanFingerprint.make(a)
        XCTAssertFalse(try store.removeIfUnchanged(Form.self, userID: "owner", scope: "recipe-editor-B", fingerprint: fingerprint))
        XCTAssertEqual(try store.load(Form.self, userID: "owner", scope: "recipe-editor-B")?.value.text, "unsaved B")
        try store.save(Form(identity: "editor-a", text: "newer A"), userID: "owner", scope: "recipe-editor-A")
        XCTAssertFalse(try store.removeIfUnchanged(Form.self, userID: "owner", scope: "recipe-editor-A", fingerprint: fingerprint))
        let latest = try XCTUnwrap(store.load(Form.self, userID: "owner", scope: "recipe-editor-A")?.value)
        XCTAssertTrue(try store.removeIfUnchanged(Form.self, userID: "owner", scope: "recipe-editor-A", fingerprint: PlanFingerprint.make(latest)))
        XCTAssertEqual(try store.load(Form.self, userID: "owner", scope: "recipe-editor-B")?.value.identity, "editor-b")
    }
    func testPartialPublishedNutritionCannotBecomeZeroNutrientLog() throws {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","name":"Soup","recipeIngredient":["200 g beans"],"recipeInstructions":"Cook beans.","nutrition":{"calories":"200 kcal"}}</script>"#
        let recipe = try XCTUnwrap(RecipeStructuredImport.drafts(html: html, sourceURL: "https://example.com/soup").first)
        XCTAssertEqual(recipe.importProvenance?.missingNutritionFields, ["Protein", "Carbohydrate", "Fat"])
        XCTAssertThrowsError(try RecipePortionRules.snapshot(for: recipe, selection: .init(unit: .savedAmount)))
        XCTAssertTrue(recipe.nutritionBasisLabel.contains("incomplete"))
    }
    func testPlanningReviewSurvivesFirestoreClockPrecisionButNotYieldChange() throws {
        var recipe = Recipe(id: "r", name: "Soup", ingredients: ["200 g beans"], instructions: ["Cook beans"], nutrition: .init(calories: 400, protein: 30, carbs: 40, fats: 10), servings: 4, nutritionBasis: .wholeRecipe)
        recipe.importProvenance = .init(kind: .text, originalText: "Source", importedAt: Date(timeIntervalSince1970: 1_800_000_000.1234567))
        recipe.planningProfile = .init(prepMinutes: 20, reviewedAt: Date(), contentFingerprint: try RecipePlanningProfile.fingerprint(recipe))
        recipe.importProvenance?.importedAt = Date(timeIntervalSince1970: 1_800_000_000.1234565)
        XCTAssertTrue(recipe.planningProfile?.isCurrent(for: recipe) == true)
        recipe.servings = 8
        XCTAssertFalse(recipe.planningProfile?.isCurrent(for: recipe) == true)
    }
}
