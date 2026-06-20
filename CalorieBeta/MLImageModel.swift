import Foundation
import UIKit

// MARK: - AI Response Models
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
    init() {}

    // MARK: - Nutrition Label Parsing
    func parseNutritionLabel(from image: UIImage, completion: @escaping (Result<NutritionLabelData, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are a highly accurate nutrition label parser. Analyze the image of the nutrition label provided.
        Your response MUST be a valid JSON object only.
        The root object must contain these exact keys: "foodName", "calories", "protein", "carbs", "fats", "saturatedFat", "polyunsaturatedFat", "monounsaturatedFat", "fiber", "calcium", "iron", "potassium", "sodium", "vitaminA", "vitaminC", "vitaminD", "vitaminB12", "folate", "magnesium", "phosphorus", "zinc", "copper", "manganese", "selenium", "vitaminB1", "vitaminB2", "vitaminB3", "vitaminB5", "vitaminB6", "vitaminE", "vitaminK".
        - "foodName" should be the product name if visible, otherwise use a generic name like "Scanned Food".
        - All nutritional values must be numbers. If a value is not found, it should be 0.
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image]]
                ]
            ]
        ]

        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini", // Or gpt-4o if better vision needed
                responseFormat: ["type": "json_object"]
            )

            switch result {
            case .success(let jsonString):
                guard let data = jsonString.data(using: .utf8) else {
                    completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    return
                }
                do {
                    let decodedLabelData = try JSONDecoder().decode(NutritionLabelData.self, from: data)
                    DispatchQueue.main.async { completion(.success(decodedLabelData)) }
                } catch {
                    completion(.failure(ImageRecognitionError.decodingError(error)))
                }
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }

    // MARK: - Meal Estimation
    func estimateNutritionFromImage(image: UIImage, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        performEstimateRequest(image: image, retryCount: 1, completion: completion)
    }

    private func performEstimateRequest(image: UIImage, retryCount: Int, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are an expert nutritional analysis assistant. Analyze the food and beverages in the provided image.
        Your task is to identify every item (including drinks, alcohol, sauces), estimate its quantity, and provide a nutritional breakdown.

        RULES:
        1. Response MUST be a valid JSON object. Root key: "foods" (array of objects).
        2. Keys per object: "itemName", "servingSize" (e.g. '1 cup', '12 oz'), "calories", "protein", "carbs", "fats".
        3. **Beverages:** If you see a drink (beer, wine, juice, soda), estimate based on standard glass sizes. Do not ignore them.
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image]]
                ]
            ]
        ]

        Task {
            // Note: We handle the recursion manually here if parsing fails,
            // so we pass retryCount: 0 to the service to avoid double-retrying network errors.
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini",
                maxTokens: 1000,
                retryCount: 0
            )

            switch result {
            case .success(let jsonString):
                // Clean markdown if present
                let cleanedContent = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let contentData = cleanedContent.data(using: .utf8) else {
                    if retryCount > 0 {
                        performEstimateRequest(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    }
                    return
                }
                
                do {
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
                            servingWeight: 0,
                            quantityValue: 1.0,
                            servingUnit: item.servingSize
                        )
                    }
                    DispatchQueue.main.async { completion(.success(foodItems)) }
                } catch {
                    if retryCount > 0 {
                        AppLog.ai.warning("AI vision response decoding failed. Retrying: \(error.localizedDescription, privacy: .public)")
                        performEstimateRequest(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.decodingError(error)))
                    }
                }
                
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }
}
