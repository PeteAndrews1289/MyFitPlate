import Foundation

public enum AITextLogError: Error, LocalizedError {
    case apiError(String)
    case networkError(Error)
    case parsingError(String)

    public var errorDescription: String? {
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

private struct AILogResponse: Codable {
    public let foods: [AILoggedItem]
}

private struct AILoggedItem: Codable {
    public let itemName: String
    public let servingSize: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let fiber: Double?
    public let calcium: Double?
    public let iron: Double?
    public let potassium: Double?
    public let sodium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let vitaminD: Double?
    public let vitaminB12: Double?
    public let folate: Double?
}

@MainActor
public class AITextLogService {
    public init() {}
    public func estimateNutrition(from text: String) async -> Result<[FoodItem], AITextLogError> {
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
        7.  **Medical Disclaimer**: Note that generated nutritional values are AI estimates and should not be considered medical advice.
        
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
        let result = await DIContainer.shared.aiService.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-4o-mini",
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let contentString):
            guard let contentData = contentString.data(using: .utf8) else {
                throw AITextLogError.parsingError("Could not convert the AI's content string to data.")
            }
            do {
                return try JSONDecoder().decode(AILogResponse.self, from: contentData)
            } catch {
                throw AITextLogError.parsingError(error.localizedDescription)
            }
        case .failure(let error):
            throw AITextLogError.apiError(error.localizedDescription)
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
