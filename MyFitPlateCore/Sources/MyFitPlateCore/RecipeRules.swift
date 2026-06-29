import Foundation

public enum RecipeRules {
    
    public static func createRecipeFromAIPrompt(description: String) -> String {
        """
        Analyze the recipe description: "\(description)".
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """
    }
    
    public static func createRecipeFromTextPrompt(text: String) -> String {
        """
        Extract the recipe from the following text: "\(text)".
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium). If nutritional info is not provided in the text, estimate it based on the ingredients for 1 serving.
        """
    }
    
    public static func createRecipeFromPantryPrompt(itemsString: String) -> String {
        """
        Generate a healthy, macro-conscious recipe STRICTLY using ONLY the following ingredients: "\(itemsString)".
        Do NOT assume the user has salt, pepper, oil, water, or any other household staples unless explicitly listed above.
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings containing exactly what was used), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """
    }
    
    public static func createRecipesFromPantryPrompt(itemsString: String) -> String {
        """
        Generate 3 distinct, healthy, macro-conscious recipes STRICTLY using ONLY the following ingredients: "\(itemsString)".
        Do NOT assume the user has salt, pepper, oil, water, or any other household staples unless explicitly listed above.
        Return a JSON object with a single key "recipes" whose value is an array of exactly 3 recipe objects. Each recipe object has keys: "name" (string), "ingredients" (array of strings containing exactly what was used), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """
    }
    
    public static func createRecipeFromURLPrompt(scrapedText: String) -> String {
        """
        I scraped the following text from a recipe blog:
        ---
        \(scrapedText)
        ---
        Extract the recipe from this text.
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        If nutrition data is missing, carefully estimate it based on the ingredients for 1 serving.
        """
    }
    
    private struct AIRecipeResponse: Codable {
        let name: String
        let ingredients: [String]
        let instructions: [String]
        let nutrition: Nutrition
    }

    private struct AIPantryRecipesResponse: Codable {
        let recipes: [AIRecipeResponse]
    }

    public static func parseRecipeFromAIResponse(_ jsonString: String) throws -> Recipe {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "RecipeRules", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }
        let response = try JSONDecoder().decode(AIRecipeResponse.self, from: jsonData)
        return Recipe(name: response.name, ingredients: response.ingredients, detailedIngredients: nil, instructions: response.instructions, nutrition: response.nutrition, servings: 1.0)
    }

    public static func parseRecipesFromAIResponse(_ jsonString: String) throws -> [Recipe] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "RecipeRules", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }
        let response = try JSONDecoder().decode(AIPantryRecipesResponse.self, from: jsonData)
        return response.recipes.map {
            Recipe(name: $0.name, ingredients: $0.ingredients, detailedIngredients: nil, instructions: $0.instructions, nutrition: $0.nutrition, servings: 1.0)
        }
    }
}
