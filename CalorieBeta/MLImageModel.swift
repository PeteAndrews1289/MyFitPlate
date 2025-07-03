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

enum ImageRecognitionError: Error {
    case imageProcessingError
    case invalidOutputFormat
    case apiError(String)
    case noData
}

class MLImageModel {
    private let apiKey = getAPIKey()

    init() {}
    
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
        You are an expert nutritional analysis assistant. Analyze the food in the provided image. Identify EVERY food item on the plate.
        Your response MUST be a valid JSON object only. The root object must have a single key "foods" which is an array of JSON objects.
        Each object in the "foods" array must contain these exact keys: "itemName" (string), "servingSize" (string, e.g., "3 cookies" or "1 cup"), "calories" (number), "protein" (number), "carbs" (number), and "fats" (number).
        If you see multiple of the same item, like 3 cookies, the "itemName" should be "Oreo Cookies" and the "servingSize" should be "3 cookies", with the nutritional values adjusted accordingly.
        """

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
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
            completion(.failure(ImageRecognitionError.apiError("Failed to serialize request.")))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
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
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}
