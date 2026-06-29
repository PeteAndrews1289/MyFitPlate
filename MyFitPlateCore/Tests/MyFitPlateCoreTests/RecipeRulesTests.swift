import XCTest
@testable import MyFitPlateCore

final class RecipeRulesTests: XCTestCase {

    func testCreateRecipeFromAIPrompt() {
        let prompt = RecipeRules.createRecipeFromAIPrompt(description: "A simple salad")
        XCTAssertTrue(prompt.contains("A simple salad"))
        XCTAssertTrue(prompt.contains("structured JSON object"))
    }

    func testCreateRecipeFromTextPrompt() {
        let prompt = RecipeRules.createRecipeFromTextPrompt(text: "Mix lettuce and tomatoes.")
        XCTAssertTrue(prompt.contains("Mix lettuce and tomatoes."))
        XCTAssertTrue(prompt.contains("estimate it based on the ingredients"))
    }

    func testCreateRecipeFromPantryPrompt() {
        let prompt = RecipeRules.createRecipeFromPantryPrompt(itemsString: "chicken, rice")
        XCTAssertTrue(prompt.contains("chicken, rice"))
        XCTAssertTrue(prompt.contains("STRICTLY using ONLY the following"))
    }

    func testCreateRecipesFromPantryPrompt() {
        let prompt = RecipeRules.createRecipesFromPantryPrompt(itemsString: "beef, broccoli")
        XCTAssertTrue(prompt.contains("beef, broccoli"))
        XCTAssertTrue(prompt.contains("3 distinct"))
    }

    func testCreateRecipeFromURLPrompt() {
        let prompt = RecipeRules.createRecipeFromURLPrompt(scrapedText: "Healthy oats recipe here.")
        XCTAssertTrue(prompt.contains("Healthy oats recipe here."))
        XCTAssertTrue(prompt.contains("recipe blog"))
    }

    func testParseRecipeFromAIResponseSuccess() throws {
        let json = """
        {
            "name": "Test Recipe",
            "ingredients": ["1 apple", "2 bananas"],
            "instructions": ["Chop", "Eat"],
            "nutrition": {
                "calories": 200,
                "protein": 2,
                "carbs": 50,
                "fats": 1,
                "saturatedFat": 0,
                "fiber": 5,
                "sodium": 10
            }
        }
        """
        
        let recipe = try RecipeRules.parseRecipeFromAIResponse(json)
        XCTAssertEqual(recipe.name, "Test Recipe")
        XCTAssertEqual(recipe.ingredients.count, 2)
        XCTAssertEqual(recipe.instructions.count, 2)
        XCTAssertEqual(recipe.nutrition.calories, 200)
    }

    func testParseRecipesFromAIResponseSuccess() throws {
        let json = """
        {
            "recipes": [
                {
                    "name": "Recipe 1",
                    "ingredients": ["1 apple"],
                    "instructions": ["Eat"],
                    "nutrition": {
                        "calories": 100,
                        "protein": 1,
                        "carbs": 25,
                        "fats": 0,
                        "saturatedFat": 0,
                        "fiber": 2,
                        "sodium": 5
                    }
                },
                {
                    "name": "Recipe 2",
                    "ingredients": ["1 banana"],
                    "instructions": ["Peel", "Eat"],
                    "nutrition": {
                        "calories": 105,
                        "protein": 1,
                        "carbs": 27,
                        "fats": 0,
                        "saturatedFat": 0,
                        "fiber": 3,
                        "sodium": 1
                    }
                }
            ]
        }
        """
        
        let recipes = try RecipeRules.parseRecipesFromAIResponse(json)
        XCTAssertEqual(recipes.count, 2)
        XCTAssertEqual(recipes[0].name, "Recipe 1")
        XCTAssertEqual(recipes[1].name, "Recipe 2")
    }

    func testParseRecipeFromAIResponseFailsOnBadJSON() {
        let badJSON = "{ invalid_json }"
        XCTAssertThrowsError(try RecipeRules.parseRecipeFromAIResponse(badJSON))
    }
}
