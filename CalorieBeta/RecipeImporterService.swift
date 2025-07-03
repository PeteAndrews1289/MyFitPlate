import Foundation
import SwiftSoup

@MainActor
class RecipeImporterService: ObservableObject {

    enum ImporterError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case noContent
        case parsingError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The provided URL is not valid."
            case .networkError(let error):
                return "Could not fetch content. Please check your network connection. (\(error.localizedDescription))"
            case .noContent:
                return "Could not find any readable recipe content at the provided URL."
            case .parsingError(let details):
                return "The AI failed to parse the recipe. (\(details))"
            }
        }
    }
    
    let apiKey = getAPIKey()

    func fetchAndParseRecipe(from urlString: String) async -> Result<UserRecipe, ImporterError> {
        let contentResult = await fetchContent(from: urlString)
        
        guard case .success(let pageContent) = contentResult else {
            return .failure(contentResult.error as? ImporterError ?? .parsingError("Unknown content fetch error."))
        }
        
        let prompt = createAIPrompt(with: pageContent, url: urlString)
        
        do {
            let aiResponse = try await fetchAIResponse(prompt: prompt)
            let recipe = parseAIResponse(aiResponse)
            return .success(recipe)
        } catch {
            return .failure(error as? ImporterError ?? .parsingError(error.localizedDescription))
        }
    }
    
    private func fetchContent(from urlString: String) async -> Result<String, ImporterError> {
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let html = String(data: data, encoding: .utf8) else {
                return .failure(.noContent)
            }
            
            let doc: Document = try SwiftSoup.parse(html)
            
            guard let recipeContainer = try doc.select("[class*='wprm-recipe-container'], [class*='tasty-recipes'], [class*='mv-recipe-card'], [class*='recipe-card']").first() else {
                return .failure(.noContent)
            }
            
            let contentToParse = try recipeContainer.text()
            
            if contentToParse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(.noContent)
            }
            
            return .success(contentToParse)

        } catch {
            return .failure(.networkError(error))
        }
    }
    
    private func createAIPrompt(with pageContent: String, url: String) -> String {
        return """
        You are a recipe parsing assistant. Analyze the following plain text, which was extracted from a recipe card on the webpage at "\(url)".
        Your primary goal is to identify the main recipe.
        Extract its name, ingredients, instructions, total servings, and nutrition facts (calories, protein, carbs, fat) if available.

        Your response MUST be a valid JSON object. Do not include any other text.
        The JSON object must have these keys: "recipeName", "servings", "ingredients", "instructions", and "nutrition".
        - "servings" MUST be a number.
        - "nutrition" should be an object with "calories", "protein", "carbs", and "fat" as keys. All these values MUST be numbers, not strings. If nutrition info is not found, these values should be 0.

        Example format:
        {
          "recipeName": "General Tso's Chicken",
          "servings": 8,
          "ingredients": [
            "2 lb chicken thighs, trimmed and cut into 1-inch pieces",
            "1/2 cup corn starch",
            "..."
          ],
          "instructions": [
            "Cut chicken into 1-inch cubes.",
            "..."
          ],
          "nutrition": {
            "calories": 386,
            "protein": 26,
            "carbs": 18,
            "fat": 26
          }
        }

        Here is the webpage text content to parse:
        
        \(pageContent)
        """
    }

    private func fetchAIResponse(prompt: String) async throws -> AIRecipeResponse {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw ImporterError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data), errorResponse.error != nil {
            throw ImporterError.parsingError(errorResponse.error?.message ?? "Unknown AI Error")
        }

        let apiResponse = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content else {
            throw ImporterError.parsingError("AI response was empty.")
        }
        
        guard let jsonData = content.data(using: .utf8) else {
            throw ImporterError.parsingError("Could not convert AI response to data.")
        }
        
        let recipeResponse = try JSONDecoder().decode(AIRecipeResponse.self, from: jsonData)
        return recipeResponse
    }
    
    private func parseAIResponse(_ aiResponse: AIRecipeResponse) -> UserRecipe {
        let recipeIngredients = aiResponse.ingredients.map {
            RecipeIngredient(
                foodName: $0,
                quantity: 1,
                selectedServingDescription: "Imported - Tap to match",
                calories: 0, protein: 0, carbs: 0, fats: 0,
                originalImportedString: $0
            )
        }

        var newRecipe = UserRecipe(
            userID: "",
            name: aiResponse.recipeName,
            ingredients: recipeIngredients,
            totalServings: aiResponse.servings,
            instructions: aiResponse.instructions
        )

        if let nutrition = aiResponse.nutrition, nutrition.calories > 0 {
            newRecipe.nutritionPerServing = .init(
                calories: nutrition.calories,
                protein: nutrition.protein,
                carbs: nutrition.carbs,
                fats: nutrition.fat
            )
            newRecipe.totalNutrition = .init(
                calories: (nutrition.calories * newRecipe.totalServings),
                protein: (nutrition.protein * newRecipe.totalServings),
                carbs: (nutrition.carbs * newRecipe.totalServings),
                fats: (nutrition.fat * newRecipe.totalServings)
            )
        }
        
        return newRecipe
    }
    
    private struct OpenAICompletionResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        let choices: [Choice]
    }
    
    private struct OpenAIErrorResponse: Decodable {
        struct OpenAIError: Decodable {
            let message: String
        }
        let error: OpenAIError?
    }

    private struct AIRecipeResponse: Decodable {
        struct Nutrition: Decodable {
            let calories: Double
            let protein: Double
            let carbs: Double
            let fat: Double
        }
        let recipeName: String
        let servings: Double
        let ingredients: [String]
        let instructions: [String]
        let nutrition: Nutrition?
    }
}

extension Result {
    var error: Error? { if case .failure(let error) = self { return error }; return nil }
}
