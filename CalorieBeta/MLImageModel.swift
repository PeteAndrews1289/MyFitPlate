import Foundation
import UIKit

struct AIMealResponse: Codable {
    let foods: [AIItemResponse]
}

struct AIItemResponse: Codable {
    let itemName: String
    let servingSize: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
}

struct NutritionLabelData: Decodable {
    let foodName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let saturatedFat: Double?
    let polyunsaturatedFat: Double?
    let monounsaturatedFat: Double?
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
    let magnesium: Double?
    let phosphorus: Double?
    let zinc: Double?
    let copper: Double?
    let manganese: Double?
    let selenium: Double?
    let vitaminB1: Double?
    let vitaminB2: Double?
    let vitaminB3: Double?
    let vitaminB5: Double?
    let vitaminB6: Double?
    let vitaminE: Double?
    let vitaminK: Double?
}

enum ImageRecognitionError: Error, LocalizedError {
    case imageProcessingError
    case invalidOutputFormat
    case apiError(String)
    case networkError(Error)
    case decodingError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .imageProcessingError:
            return "There was an issue preparing your image for analysis. Please try again."
        case .invalidOutputFormat:
            return "The analysis returned data in an unexpected format. The AI may be unable to process this image."
        case .apiError(let message):
            return "An error occurred during analysis: \(message)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .decodingError(let error):
            return "There was a problem processing the data from the server: \(error.localizedDescription)"
        case .noData:
            return "No data was returned from the analysis. The image might not be clear enough."
        }
    }
}

class MLImageModel {
    private let apiKey = getAPIKey()

    init() {}

    func parseNutritionLabel(from image: UIImage, completion: @escaping (Result<NutritionLabelData, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        You are a highly accurate nutrition label parser. Analyze the image of the nutrition label provided.
        Your response MUST be a valid JSON object only.
        The root object must contain these exact keys: "foodName", "calories", "protein", "carbs", "fats", "saturatedFat", "polyunsaturatedFat", "monounsaturatedFat", "fiber", "calcium", "iron", "potassium", "sodium", "vitaminA", "vitaminC", "vitaminD", "vitaminB12", "folate", "magnesium", "phosphorus", "zinc", "copper", "manganese", "selenium", "vitaminB1", "vitaminB2", "vitaminB3", "vitaminB5", "vitaminB6", "vitaminE", "vitaminK".
        - "foodName" should be the product name if visible, otherwise use a generic name like "Scanned Food".
        - All nutritional values must be numbers. If a value is not found, it should be 0.
        """

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
             "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": base64Image]]
                    ]
                ]
            ],
            "max_tokens": 500
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(ImageRecognitionError.apiError("Failed to serialize the request.")))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.networkError(error))) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.noData)) }
                return
            }
            
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = jsonResponse["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                    
                    guard let contentData = cleanedContent.data(using: .utf8) else {
                        DispatchQueue.main.async { completion(.failure(ImageRecognitionError.invalidOutputFormat)) }
                        return
                    }
                    
                    let decodedLabelData = try JSONDecoder().decode(NutritionLabelData.self, from: contentData)
                    DispatchQueue.main.async { completion(.success(decodedLabelData)) }
                } else {
                     DispatchQueue.main.async { completion(.failure(ImageRecognitionError.invalidOutputFormat)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.decodingError(error))) }
            }
        }.resume()
    }

    func estimateNutritionFromImage(image: UIImage, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        You are an expert nutritional analysis assistant. Analyze the food in the provided image. Your primary task is to identify every food item, estimate its quantity, and provide a nutritional breakdown for that estimated amount.

        RULES:
        1.  Your response MUST be a valid JSON object only. Do not include any introductory text or summaries.
        2.  The root object must have a single key "foods" which is an array of JSON objects.
        3.  For each object in the "foods" array:
            -   **Estimate Quantity**: First, estimate the amount of the food item. Use common units like grams (g), ounces (oz), cups, or countable units (e.g., "3 cookies", "2 slices"). This estimation is the most critical step.
            -   **Provide Nutrition for the Estimate**: All nutritional values MUST reflect the estimated quantity.
            -   **JSON Keys**: Each object must contain these exact keys: "itemName" (string), "servingSize" (string, e.g., "approx. 6 oz" or "1.5 cups"), "calories" (number), "protein" (number), "carbs" (number), and "fats" (number).
        
        Example: If you see a piece of salmon and some rice, your response should be structured like this, with the nutrition calculated for the specific weights you estimate:
        {
            "foods": [
                {
                    "itemName": "Grilled Salmon",
                    "servingSize": "approx. 5 oz",
                    "calories": 290,
                    "protein": 40,
                    "carbs": 0,
                    "fats": 13
                },
                {
                    "itemName": "White Rice",
                    "servingSize": "approx. 1 cup",
                    "calories": 205,
                    "protein": 4,
                    "carbs": 45,
                    "fats": 0.5
                }
            ]
        }
        """

        let payload: [String: Any] = [
            "model": "gpt-5.1",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": base64Image]]
                    ]
                ]
            ],
            "max_tokens": 1000
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(ImageRecognitionError.apiError("Failed to serialize the request.")))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.networkError(error))) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.noData)) }
                return
            }
            
            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = jsonResponse["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                    
                    guard let contentData = cleanedContent.data(using: .utf8) else {
                        DispatchQueue.main.async { completion(.failure(ImageRecognitionError.invalidOutputFormat)) }
                        return
                    }
                    
                    let decodedAIResponse = try JSONDecoder().decode(AIMealResponse.self, from: contentData)
                    
                    let foodItems = decodedAIResponse.foods.map { item -> FoodItem in
                        return FoodItem(
                            id: UUID().uuidString,
                            name: item.itemName,
                            calories: item.calories,
                            protein: item.protein,
                            carbs: item.carbs,
                            fats: item.fats,
                            servingSize: item.servingSize,
                            servingWeight: 0
                        )
                    }
                    DispatchQueue.main.async { completion(.success(foodItems)) }
                } else {
                     DispatchQueue.main.async { completion(.failure(ImageRecognitionError.invalidOutputFormat)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(ImageRecognitionError.decodingError(error))) }
            }
        }.resume()
    }
}
