import Foundation

enum AITextLogError: Error, LocalizedError {
    case apiError(String)
    case networkError(Error)
    case parsingError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "An error occurred with the AI service: \(message)"
        case .networkError:
            return "A network error occurred. Please check your connection and try again."
        case .parsingError(let details):
            return "The AI response could not be understood. Details: \(details)"
        }
    }
}

private struct OpenAICompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct AILogResponse: Codable {
    let foods: [AILoggedItem]
}

private struct AILoggedItem: Codable {
    let itemName: String
    let servingSize: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let fiber: Double?
    let calcium: Double?
    let iron: Double?
    let potassium: Double?
    let sodium: Double?
    let vitaminA: Double?
    let vitaminC: Double?
    let vitaminD: Double?
    let vitaminB12: Double?
    let folate: Double?
}

@MainActor
class AITextLogService {
    private let apiKey = getAPIKey()

    func estimateNutrition(from text: String) async -> Result<[FoodItem], AITextLogError> {
        let prompt = createPrompt(for: text)
        
        do {
            let aiResponse = try await fetchAIResponse(prompt: prompt)
            let foodItems = parseAIResponse(aiResponse)
            return .success(foodItems)
        } catch let error as AITextLogError {
            return .failure(error)
        } catch {
            return .failure(.parsingError(error.localizedDescription))
        }
    }

    private func createPrompt(for text: String) -> String {
        return """
        You are an expert nutritional analysis assistant named Maia. A user has provided a text description of a meal they ate.
        Your task is to identify each distinct food item and provide a full nutritional breakdown.

        USER'S MEAL DESCRIPTION: "\(text)"

        RULES:
        1.  **Prioritize User Input**: If the user provides a specific quantity and unit (e.g., "8 oz", "1 cup", "150g"), you MUST use that exact measurement for your calculations.
        2.  **Estimate if Vague**: Only estimate a reasonable serving size if the user is vague (e.g., "a glass of juice", "a handful of almonds").
        3.  **JSON Response**: Your response MUST be a valid JSON object only. Do not include any other text.
        4.  **Root Object**: The root object must have a single key "foods" which is an array of JSON objects.
        5.  **Food Object Keys**: Each food object must contain these exact keys: "itemName", "servingSize", "calories", "protein", "carbs", "fats", "fiber", "calcium", "iron", "potassium", "sodium", "vitaminA", "vitaminC", "vitaminD", "vitaminB12", "folate".
        6.  **Numeric Values**: All nutritional values must be numbers. If a micronutrient is not applicable or is unknown, its value should be 0.
        
        Example for a specific user input "6 oz salmon, 1 cup of rice":
        {
            "foods": [
                { "itemName": "Salmon", "servingSize": "6 oz", "calories": 340, "protein": 34, "carbs": 0, "fats": 22, "fiber": 0, "calcium": 25, "iron": 1, "potassium": 970, "sodium": 100, "vitaminA": 50, "vitaminC": 0, "vitaminD": 12, "vitaminB12": 4.5, "folate": 25 },
                { "itemName": "Rice", "servingSize": "1 cup", "calories": 205, "protein": 4, "carbs": 45, "fats": 0.5, "fiber": 0.6, "calcium": 19, "iron": 2, "potassium": 55, "sodium": 1, "vitaminA": 0, "vitaminC": 0, "vitaminD": 0, "vitaminB12": 0, "folate": 90 }
            ]
        }
        """
    }

    private func fetchAIResponse(prompt: String) async throws -> AILogResponse {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AITextLogError.apiError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            let openAIResponse = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)
            
            guard let contentString = openAIResponse.choices.first?.message.content else {
                throw AITextLogError.parsingError("The AI response was empty or in an unexpected format.")
            }
            
            guard let contentData = contentString.data(using: .utf8) else {
                throw AITextLogError.parsingError("Could not convert the AI's content string to data.")
            }
            
            let decodedResponse = try JSONDecoder().decode(AILogResponse.self, from: contentData)
            return decodedResponse
            
        } catch {
            throw AITextLogError.parsingError(error.localizedDescription)
        }
    }
    
    private func parseAIResponse(_ aiResponse: AILogResponse) -> [FoodItem] {
        return aiResponse.foods.map { item in
            FoodItem(
                id: UUID().uuidString, name: item.itemName,
                calories: item.calories, protein: item.protein, carbs: item.carbs, fats: item.fats,
                saturatedFat: nil, polyunsaturatedFat: nil, monounsaturatedFat: nil,
                fiber: item.fiber, servingSize: item.servingSize, servingWeight: 0,
                timestamp: Date(), calcium: item.calcium, iron: item.iron,
                potassium: item.potassium, sodium: item.sodium, vitaminA: item.vitaminA,
                vitaminC: item.vitaminC, vitaminD: item.vitaminD, vitaminB12: item.vitaminB12,
                folate: item.folate
            )
        }
    }
}
