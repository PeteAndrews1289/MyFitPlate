import Foundation
import UIKit

// MARK: - AI Response Models
struct AIMealResponse: Codable {
    let foods: [AIItemResponse]
}

struct MealPhotoItemReview: Sendable {
    let itemID: String
    let confidence: Double
    let portionLowGrams: Double?
    let portionHighGrams: Double?
    let requiresConfirmation: Bool
    let clarificationQuestion: String?
    let hiddenIngredientRisks: [String]
    let referenceSourceName: String?
}

struct MealPhotoReviewContext: Sendable {
    let overallConfidence: Double
    let analysisNotes: String
    let clarificationQuestions: [String]
    let groundedItemCount: Int
    let itemReviews: [String: MealPhotoItemReview]

    var needsConfirmationCount: Int {
        itemReviews.values.filter(\.requiresConfirmation).count
    }
}

struct MealPhotoAnalysis: Sendable {
    let items: [FoodItem]
    let reviewContext: MealPhotoReviewContext
}

struct AIItemResponse: Codable {
    let itemName: String
    let servingSize: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
}

struct ScannedMenuValueItem {
    let food: FoodItem
    let listedPrice: Double
}

private struct AIMenuPriceResponse: Decodable {
    let foods: [AIMenuPriceItemResponse]
}

private struct AIMenuPriceItemResponse: Decodable {
    let itemName: String
    let servingSize: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let price: Double?
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
    let servingDescription: String?
    let servingWeightGrams: Double?
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
        guard let imageData = image.aiPreparedJPEGData() else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        You are a highly accurate nutrition label parser. Analyze the image of the nutrition label provided.
        Your response MUST be a valid JSON object only.
        The root object must contain these exact keys: "foodName", "servingDescription", "servingWeightGrams", "calories", "protein", "carbs", "fats", "saturatedFat", "polyunsaturatedFat", "monounsaturatedFat", "fiber", "calcium", "iron", "potassium", "sodium", "vitaminA", "vitaminC", "vitaminD", "vitaminB12", "folate", "magnesium", "phosphorus", "zinc", "copper", "manganese", "selenium", "vitaminB1", "vitaminB2", "vitaminB3", "vitaminB5", "vitaminB6", "vitaminE", "vitaminK".
        - "foodName" should be the product name if visible, otherwise use a generic name like "Scanned Food".
        - "servingDescription" should copy the complete label serving, such as "2 cookies (29 g)", or be null when it is not visible.
        - "servingWeightGrams" should be only the serving's gram weight as a number, or null when no gram weight is printed.
        - Calories, protein, carbs, and fats must be numbers copied from the label.
        - Optional nutrients must be numbers only when explicitly printed on the label. Use null when an optional nutrient is not shown; do not invent zero.
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]

        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini",
                responseFormat: ["type": "json_object"],
                requestKind: .nutritionLabel
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
        analyzeNutritionFromImage(image: image) { result in
            completion(result.map(\.items))
        }
    }

    func analyzeNutritionFromImage(
        image: UIImage,
        completion: @escaping (Result<MealPhotoAnalysis, Error>) -> Void
    ) {
        performEstimateRequest(image: image, retryCount: 1, completion: completion)
    }

    private func performEstimateRequest(
        image: UIImage,
        retryCount: Int,
        completion: @escaping (Result<MealPhotoAnalysis, Error>) -> Void
    ) {
        guard let imageData = image.aiPreparedJPEGData() else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"

        let prompt = """
        Analyze this meal photo as an honest draft for a nutrition log. Speed is useful, but false
        precision is harmful. Identify every clearly visible food, beverage, sauce, and topping as a
        separate item when possible.

        Follow these rules:
        - Report only visible or strongly supported foods. Do not turn a possibility into a fact.
        - Use a concise generic food identity suitable for a composition-database search. Do not
          invent a brand. Keep preparation separate, such as grilled, fried, raw, or steamed.
        - Estimate a best gram weight plus a realistic low/high gram range whenever the image permits.
          Use null for all three gram fields when visual scale is genuinely unavailable.
        - Calories and macros are fallback estimates for the best portion. Keep them internally
          consistent and realistic, but do not imply that they were read from a label or database.
        - Put oils, butter, dressings, fillings, and other plausible but unmeasurable additions in
          hiddenIngredientRisks. Do not silently include a precise hidden amount.
        - Confidence is 0 to 1 and reflects both identity and portion confidence. Set
          requiresConfirmation when uncertainty could materially change nutrition.
        - Ask no more than two short clarification questions for ambiguities with the largest likely
          calorie or macro impact. Do not ask about details that are already clear.
        - If the image is too unclear or does not show food, set imageUsable to false and return no foods.
        """

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]

        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                maxTokens: 4_000,
                temperature: 0,
                requestKind: .mealPhoto,
                retryCount: 0
            )

            switch result {
            case .success(let jsonString):
                do {
                    let response = try JSONDecoder().decode(
                        MealPhotoAnalysisResponse.self,
                        from: Data(jsonString.utf8)
                    )
                    guard response.imageUsable, !response.foods.isEmpty else {
                        completion(.failure(ImageRecognitionError.noData))
                        return
                    }

                    let outcomes = await groundMealPhotoFoods(response.foods)
                    guard !outcomes.isEmpty else {
                        completion(.failure(ImageRecognitionError.invalidOutputFormat))
                        return
                    }
                    let items = outcomes.map(\.item)
                    let itemReviews = Dictionary(uniqueKeysWithValues: outcomes.map { outcome in
                        (
                            outcome.item.id,
                            MealPhotoItemReview(
                                itemID: outcome.item.id,
                                confidence: outcome.modelConfidence,
                                portionLowGrams: outcome.portionLowGrams,
                                portionHighGrams: outcome.portionHighGrams,
                                requiresConfirmation: outcome.requiresConfirmation,
                                clarificationQuestion: outcome.clarificationQuestion,
                                hiddenIngredientRisks: outcome.hiddenIngredientRisks,
                                referenceSourceName: outcome.referenceSourceName
                            )
                        )
                    })
                    let analysis = MealPhotoAnalysis(
                        items: items,
                        reviewContext: MealPhotoReviewContext(
                            overallConfidence: min(max(response.overallConfidence, 0), 1),
                            analysisNotes: response.analysisNotes,
                            clarificationQuestions: Array(response.clarificationQuestions.prefix(2)),
                            groundedItemCount: outcomes.filter(\.usedNutrientReference).count,
                            itemReviews: itemReviews
                        )
                    )
                    DispatchQueue.main.async { completion(.success(analysis)) }
                } catch {
                    if retryCount > 0 {
                        performEstimateRequest(
                            image: image,
                            retryCount: retryCount - 1,
                            completion: completion
                        )
                    } else {
                        completion(.failure(ImageRecognitionError.decodingError(error)))
                    }
                }
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }

    private func groundMealPhotoFoods(
        _ estimates: [MealPhotoFoodEstimate]
    ) async -> [MealPhotoGroundingOutcome] {
        let limitedEstimates = Array(estimates.prefix(12))
        return await withTaskGroup(of: (Int, MealPhotoGroundingOutcome?).self) { group in
            for (index, estimate) in limitedEstimates.enumerated() {
                group.addTask {
                    let query = [estimate.itemName, estimate.preparation]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .joined(separator: " ")
                    async let usda = USDAFoodAPIService().searchFoods(query: query)
                    async let canada = HealthCanadaFoodAPIService().searchFoods(query: query, limit: 8)
                    let (usdaFoods, canadaFoods) = await (usda, canada)
                    let candidates = usdaFoods + canadaFoods
                    return (
                        index,
                        MealPhotoGrounding.makeOutcome(estimate: estimate, candidates: candidates)
                    )
                }
            }

            var ordered: [(Int, MealPhotoGroundingOutcome)] = []
            for await (index, outcome) in group {
                if let outcome { ordered.append((index, outcome)) }
            }
            return ordered.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - Menu Estimation
    func estimateMenuFromImage(image: UIImage, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.aiPreparedJPEGData() else {
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
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]

        performImageAnalysis(
            messages: messages,
            retryCount: 1,
            sourceType: .aiMenu,
            sourceName: "Maia Menu",
            requestKind: .menuPhoto,
            completion: completion
        )
    }

    func estimateMenuItemsWithListedPrices(
        image: UIImage,
        completion: @escaping (Result<[ScannedMenuValueItem], Error>) -> Void
    ) {
        guard let imageData = image.aiPreparedJPEGData() else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let prompt = """
        Read the restaurant menu image. Return one entry per clearly visible dish or beverage.
        Estimate nutrition for one listed serving, but copy only prices that are visibly printed
        next to that item. Never infer, calculate, or invent a price. Use null when no price is visible.

        JSON object only with root key "foods". Each item must contain:
        "itemName", "servingSize", "calories", "protein", "carbs", "fats", and "price".
        """
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
            ]
        ]]

        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini",
                responseFormat: ["type": "json_object"],
                requestKind: .menuPhoto
            )
            switch result {
            case .success(let json):
                guard let data = json.data(using: .utf8) else {
                    completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    return
                }
                do {
                    let response = try JSONDecoder().decode(AIMenuPriceResponse.self, from: data)
                    let items = response.foods.compactMap { item -> ScannedMenuValueItem? in
                        guard let price = item.price, price > 0 else { return nil }
                        let food = FoodItem(
                            name: item.itemName,
                            calories: item.calories,
                            protein: item.protein,
                            carbs: item.carbs,
                            fats: item.fats,
                            servingSize: item.servingSize
                        ).withAIEstimateSource(.aiMenu, sourceName: "Maia Menu")
                        return ScannedMenuValueItem(food: food, listedPrice: price)
                    }
                    completion(.success(items))
                } catch {
                    completion(.failure(ImageRecognitionError.decodingError(error)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Menu Matchmaker
    func recommendMenuMeals(from image: UIImage, remainingCalories: Double, remainingProtein: Double, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let imageData = image.aiPreparedJPEGData() else {
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
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]

        performImageAnalysis(
            messages: messages,
            retryCount: 1,
            sourceType: .aiMenu,
            sourceName: "Maia Menu",
            requestKind: .menuPhoto,
            completion: completion
        )
    }

    // MARK: - Grocery Receipt Parsing
    func parseGroceryReceipt(from image: UIImage, completion: @escaping (Result<[PantryItem], Error>) -> Void) {
        guard let imageData = image.aiPreparedJPEGData() else {
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
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]

        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini",
                responseFormat: ["type": "json_object"],
                requestKind: .receiptPhoto
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

    private func performImageAnalysis(
        messages: [[String: Any]],
        retryCount: Int,
        sourceType: FoodSourceType,
        sourceName: String,
        requestKind: AIRequestKind,
        completion: @escaping (Result<[FoodItem], Error>) -> Void
    ) {

        Task {
            // Note: We handle the recursion manually here if parsing fails,
            // so we pass retryCount: 0 to the service to avoid double-retrying network errors.
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-4o-mini",
                maxTokens: 3_000,
                requestKind: requestKind,
                retryCount: 0
            )

            switch result {
            case .success(let jsonString):
                // Clean markdown if present
                let cleanedContent = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let contentData = cleanedContent.data(using: .utf8) else {
                    if retryCount > 0 {
                        performImageAnalysis(
                            messages: messages,
                            retryCount: retryCount - 1,
                            sourceType: sourceType,
                            sourceName: sourceName,
                            requestKind: requestKind,
                            completion: completion
                        )
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
                        ).withAIEstimateSource(sourceType, sourceName: sourceName)
                    }
                    DispatchQueue.main.async { completion(.success(foodItems)) }
                } catch {
                    if retryCount > 0 {
                        AppLog.ai.warning("AI vision response decoding failed. Retrying: \(error.localizedDescription, privacy: .public)")
                        performImageAnalysis(
                            messages: messages,
                            retryCount: retryCount - 1,
                            sourceType: sourceType,
                            sourceName: sourceName,
                            requestKind: requestKind,
                            completion: completion
                        )
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

extension UIImage {
    /// Normalizes orientation and bounds payload size without corrupting the encoded image.
    func aiPreparedJPEGData(
        maxPixelDimension: CGFloat = 2_048,
        maxBytes: Int = 6_000_000
    ) -> Data? {
        guard maxPixelDimension > 0, maxBytes > 0 else { return nil }

        let pixelWidth = CGFloat(cgImage?.width ?? Int(size.width * scale))
        let pixelHeight = CGFloat(cgImage?.height ?? Int(size.height * scale))
        guard pixelWidth.isFinite, pixelHeight.isFinite, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        let resizeScale = min(1, maxPixelDimension / max(pixelWidth, pixelHeight))
        let targetSize = CGSize(
            width: max(1, (pixelWidth * resizeScale).rounded()),
            height: max(1, (pixelHeight * resizeScale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalizedImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        for quality: CGFloat in [0.82, 0.68, 0.52] {
            if let data = normalizedImage.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        return nil
    }
}
