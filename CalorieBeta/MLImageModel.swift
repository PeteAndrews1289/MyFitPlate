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

struct ReceiptParseResponse: Codable {
    let items: [ReceiptItemResponse]
}

struct ReceiptItemResponse: Codable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
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
                model: "gpt-4o-mini",
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

        performImageAnalysis(messages: messages, retryCount: retryCount, completion: completion)
    }

    // MARK: - Menu Estimation
    func estimateMenuFromImage(image: UIImage, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are an expert nutritional analysis assistant. The user has provided an image of a restaurant menu.
        Your task is to extract ALL distinct meals, entrees, and beverages listed on this menu, and estimate their nutritional breakdown.
        We will show these to the user so they can select which ONE meal they actually ordered.

        RULES:
        1. Response MUST be a valid JSON object. Root key: "foods" (array of objects).
        2. Keys per object: "itemName", "servingSize" (e.g. '1 meal', '1 plate'), "calories", "protein", "carbs", "fats".
        3. Do NOT bundle all menu items into a single object. Create a separate object for EACH menu item.
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

        performImageAnalysis(messages: messages, retryCount: 1, completion: completion)
    }

    // MARK: - Menu Matchmaker
    func recommendMenuMeals(from image: UIImage, remainingCalories: Double, remainingProtein: Double, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are an expert nutritional analysis assistant. The user has provided an image of a restaurant menu.
        For context, the user has about \(Int(remainingCalories)) calories and \(Int(remainingProtein))g of protein left for the day. Use this ONLY to choose which dishes to recommend — never to change a dish's real nutrition.
        
        First, estimate each dish's REAL nutrition using realistic full restaurant portions (entrées are typically 400-900 calories). NEVER understate a dish's calories or macros to make it "fit" the budget — report the real plate.

        Then recommend exactly 5 dishes, chosen for VARIETY (do NOT return five near-identical high-protein entrées):
        - 3 dishes that best fit the user's remaining calories and protein. Keep these protein-forward, but vary the type (e.g. not three steaks).
        - 1 dish that is the most nutritious / healthiest option overall (nutrient density, vegetables, balance), regardless of how it fits the macros.
        - 1 lighter or plant-forward option for variety — a salad or vegetarian dish if the menu offers one.
        If the menu genuinely lacks a category (e.g. a steakhouse with no salad), pick the closest alternative and still return 5 total.
        
        RULES:
        1. Response MUST be a valid JSON object. Root key: "foods" (array of objects).
        2. Keys per object: "itemName" with a short role label in parentheses — "(Best Macro Fit)" for the 3 macro picks, "(Most Nutritious)" for the healthiest, "(Lighter Pick)" for the variety option — plus "servingSize" (e.g. '1 meal'), "calories", "protein", "carbs", "fats".
        3. Order the array as: the 3 "(Best Macro Fit)" dishes first, then "(Most Nutritious)", then "(Lighter Pick)".
        4. Calories MUST be consistent with the macros: calories ≈ (protein * 4) + (carbs * 4) + (fats * 9). Re-check this before responding — a high-protein entrée cannot be only a few calories.
        5. Report each dish's true values even if it exceeds the user's remaining calories.
        6. Provide exactly 5 recommendations.
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

        performImageAnalysis(messages: messages, retryCount: 1, completion: completion)
    }

    // MARK: - Grocery Receipt Parsing
    func parseGroceryReceipt(from image: UIImage, completion: @escaping (Result<[PantryItem], Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are a smart grocery receipt parsing assistant. The user has provided an image of a grocery store receipt.
        Your task is to identify every food item purchased and convert it into a structured inventory list for a digital pantry.
        
        RULES:
        1. Your response MUST be a valid JSON object.
        2. The root key MUST be "items" (an array of objects).
        3. Keys per object MUST be:
           - "name": Cleaned up name of the ingredient (e.g. "Chicken Breast" instead of "CHK BRST BNLSS").
           - "quantity": A numerical value representing how much was bought (e.g. 1.0, 2.5).
           - "unit": The unit of measurement (e.g. "lbs", "oz", "count", "gallon"). Default to "count" if unsure.
           - "category": The food category (e.g. "Produce", "Meat", "Dairy", "Pantry", "Frozen", "Beverages").
        4. Exclude non-food items (like toilet paper, batteries, bags, tax).
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
                model: "gpt-4o-mini",
                responseFormat: ["type": "json_object"]
            )

            switch result {
            case .success(let jsonString):
                guard let data = jsonString.data(using: .utf8) else {
                    completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    return
                }
                do {
                    let decodedResponse = try JSONDecoder().decode(ReceiptParseResponse.self, from: data)
                    let pantryItems = decodedResponse.items.map { item -> PantryItem in
                        return PantryItem(
                            name: item.name,
                            quantity: item.quantity,
                            unit: item.unit,
                            category: item.category
                        )
                    }
                    DispatchQueue.main.async { completion(.success(pantryItems)) }
                } catch {
                    completion(.failure(ImageRecognitionError.decodingError(error)))
                }
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }

    private func performImageAnalysis(messages: [[String: Any]], retryCount: Int, completion: @escaping (Result<[FoodItem], Error>) -> Void) {

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
                        performImageAnalysis(messages: messages, retryCount: retryCount - 1, completion: completion)
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
                            servingWeight: 0
                        )
                    }
                    DispatchQueue.main.async { completion(.success(foodItems)) }
                } catch {
                    if retryCount > 0 {
                        AppLog.ai.warning("AI vision response decoding failed. Retrying: \(error.localizedDescription, privacy: .public)")
                        performImageAnalysis(messages: messages, retryCount: retryCount - 1, completion: completion)
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
