import Foundation
public struct FatSecretResponse: Decodable {
    public let foods: FoodList?
}

public struct FoodList: Decodable {
    public let food: [FatSecretFoodItem]?
}

public struct FatSecretFoodItem: Decodable {
    public let foodID: String
    public let foodName: String?
    public let brandName: String?
    public let foodDescription: String?

    public enum CodingKeys: String, CodingKey {
        case foodID = "food_id"
        case foodName = "food_name"
        case brandName = "brand_name"
        case foodDescription = "food_description"
    }
}

public struct FatSecretFoodResponse: Decodable { let food: FatSecretFood? }
public struct FatSecretFood: Decodable { let foodID: String; let foodName: String; let brandName: String?; let servings: FatSecretServings; enum CodingKeys: String, CodingKey { case foodID = "food_id"; case foodName = "food_name"; case brandName = "brand_name"; case servings } }
public struct FatSecretServings: Decodable { let serving: [FatSecretServing]; enum CodingKeys: String, CodingKey { case serving }; public init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); if let a = try? c.decode([FatSecretServing].self, forKey: .serving) { self.serving = a } else if let s = try? c.decode(FatSecretServing.self, forKey: .serving) { self.serving = [s] } else { self.serving = [] } } }

public struct FatSecretServing: Decodable {
    public let calories: String?; let protein: String?; let carbohydrate: String?; let fat: String?
    public let saturatedFat: String?; let polyunsaturatedFat: String?; let monounsaturatedFat: String?; let fiber: String?
    public let servingDescription: String?; let metricServingAmount: String?; let metricServingUnit: String?
    public let calcium: String?; let iron: String?; let potassium: String?; let sodium: String?
    public let vitamin_a: String?; let vitamin_c: String?; let vitamin_d: String?; let vitamin_b12: String?; let folate: String?
    public let magnesium: String?; let phosphorus: String?; let zinc: String?; let copper: String?; let manganese: String?; let selenium: String?
    public let vitamin_b1: String?; let vitamin_b2: String?; let vitamin_b3: String?; let vitamin_b5: String?; let vitamin_b6: String?; let vitamin_e: String?; let vitamin_k: String?

    public enum CodingKeys: String, CodingKey {
        case calories, protein, carbohydrate, fat, calcium, iron, potassium, sodium, vitamin_a, vitamin_c, vitamin_d, vitamin_b12, folate, magnesium, phosphorus, zinc, copper, manganese, selenium
        case vitamin_b1 = "thiamin"; case vitamin_b2 = "riboflavin"; case vitamin_b3 = "niacin"; case vitamin_b5 = "pantothenic_acid"; case vitamin_b6 = "vitamin_b6"
        case vitamin_e = "vitamin_e"; case vitamin_k = "vitamin_k"
        case saturatedFat = "saturated_fat"; case polyunsaturatedFat = "polyunsaturated_fat"; case monounsaturatedFat = "monounsaturated_fat"; case fiber
        case servingDescription = "serving_description"; case metricServingAmount = "metric_serving_amount"; case metricServingUnit = "metric_serving_unit"
    }

    private func parseDouble(from string: String?) -> Double? {
        guard let value = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "n/a" else {
            return nil
        }
        let cleaned = value
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
        guard let parsed = Double(cleaned), parsed.isFinite, parsed >= 0 else { return nil }
        return parsed
    }

    public func parsedOptionalNutrient(_ key: CodingKeys) -> Double? {
        switch key {
        case .calories: return parseDouble(from: calories)
        case .protein: return parseDouble(from: protein)
        case .carbohydrate: return parseDouble(from: carbohydrate)
        case .fat: return parseDouble(from: fat)
        case .saturatedFat: return parseDouble(from: saturatedFat)
        case .polyunsaturatedFat: return parseDouble(from: polyunsaturatedFat)
        case .monounsaturatedFat: return parseDouble(from: monounsaturatedFat)
        case .fiber: return parseDouble(from: fiber)
        case .calcium: return parseDouble(from: calcium)
        case .iron: return parseDouble(from: iron)
        case .potassium: return parseDouble(from: potassium)
        case .sodium: return parseDouble(from: sodium)
        case .vitamin_a: return parseDouble(from: vitamin_a)
        case .vitamin_c: return parseDouble(from: vitamin_c)
        case .vitamin_d: return parseDouble(from: vitamin_d)
        case .vitamin_b12: return parseDouble(from: vitamin_b12)
        case .folate: return parseDouble(from: folate)
        case .magnesium: return parseDouble(from: magnesium)
        case .phosphorus: return parseDouble(from: phosphorus)
        case .zinc: return parseDouble(from: zinc)
        case .copper: return parseDouble(from: copper)
        case .manganese: return parseDouble(from: manganese)
        case .selenium: return parseDouble(from: selenium)
        case .vitamin_b1: return parseDouble(from: vitamin_b1)
        case .vitamin_b2: return parseDouble(from: vitamin_b2)
        case .vitamin_b3: return parseDouble(from: vitamin_b3)
        case .vitamin_b5: return parseDouble(from: vitamin_b5)
        case .vitamin_b6: return parseDouble(from: vitamin_b6)
        case .vitamin_e: return parseDouble(from: vitamin_e)
        case .vitamin_k: return parseDouble(from: vitamin_k)
        default: return nil
        }
    }

    public func parsedNutrient(_ key: CodingKeys) -> Double {
        parsedOptionalNutrient(key) ?? 0
    }
    public var parsedServingWeightGrams: Double? { guard let amountStr = metricServingAmount, let unit = metricServingUnit?.lowercased(), let amount = Double(amountStr), amount > 0 else { return nil }; if unit == "g" { return amount }; if unit == "ml" { return amount }; if unit == "oz" { return amount * 28.3495 }; if unit == "fl oz" { return amount * 29.5735 }; return nil }
    public var displayDescription: String { servingDescription ?? "Serving" }
}

public class FatSecretFoodAPIService {
    public init() {}
    

    /// Calls FatSecret through the `fatSecretProxy` Cloud Function over HTTPS instead of hitting the
    /// proxy host directly. The function forwards to the same proxy server-side and returns its JSON
    /// verbatim, so all decoding below is unchanged — only the transport moved off plaintext HTTP.
    private func callProxy(path: String, params: [String: String], completion: @escaping (Result<Data, Error>) -> Void) {
        Task {
            do {
                let data = try await DIContainer.shared.cloudFunctionService.callFunction("fatSecretProxy", with: ["path": path, "params": params])
                guard let payload = data, JSONSerialization.isValidJSONObject(payload) else {
                    completion(.failure(APIError.noData))
                    return
                }
                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                completion(.success(jsonData))
            } catch {
                completion(.failure(APIError.networkError(error)))
            }
        }
    }

    private let barcodeLookupLock = NSLock()
    private var barcodeLookupCompletions: [String: [(Result<FoodItem, Error>) -> Void]] = [:]
    
    public func fetchFoodByBarcode(barcode: String, completion: @escaping (Result<FoodItem, Error>) -> Void) {
        barcodeLookupLock.lock()
        if barcodeLookupCompletions[barcode] != nil {
            barcodeLookupCompletions[barcode]?.append(completion)
            barcodeLookupLock.unlock()
            return
        }
        barcodeLookupCompletions[barcode] = [completion]
        barcodeLookupLock.unlock()

        callProxy(path: "barcode", params: ["barcode": barcode]) { result in
            switch result {
            case .failure(let error):
                self.finishBarcodeLookup(barcode: barcode, result: .failure(error))
            case .success(let data):
                do {
                    let decodedResponse = try JSONDecoder().decode([String: [String: String]].self, from: data)
                    if let foodId = decodedResponse["food_id"]?["value"] {
                        self.fetchFoodDetails(foodId: foodId) { detailsResult in
                            switch detailsResult {
                            case .success(let details):
                                self.finishBarcodeLookup(barcode: barcode, result: .success(details.foodInfo))
                            case .failure(let detailError):
                                self.finishBarcodeLookup(barcode: barcode, result: .failure(detailError))
                            }
                        }
                    } else {
                        self.finishBarcodeLookup(
                            barcode: barcode,
                            result: .failure(APIError.apiError("No food item found for this barcode."))
                        )
                    }
                } catch {
                    self.finishBarcodeLookup(barcode: barcode, result: .failure(APIError.decodingError(error)))
                }
            }
        }
    }

    private func finishBarcodeLookup(barcode: String, result: Result<FoodItem, Error>) {
        barcodeLookupLock.lock()
        let completions = barcodeLookupCompletions.removeValue(forKey: barcode) ?? []
        barcodeLookupLock.unlock()
        completions.forEach { $0(result) }
    }
    
    public func fetchFoodDetails(foodId: String, completion: @escaping (Result<(foodInfo: FoodItem, availableServings: [ServingSizeOption]), Error>) -> Void) {
        callProxy(path: "food", params: ["food_id": foodId]) { result in
            let data: Data
            switch result {
            case .failure(let error): completion(.failure(error)); return
            case .success(let payload): data = payload
            }

            do {
                let decodedResponse = try JSONDecoder().decode(FatSecretFoodResponse.self, from: data)
                guard let food = decodedResponse.food else { completion(.failure(APIError.noData)); return }

                guard !food.servings.serving.isEmpty else { completion(.failure(APIError.apiError("No serving information was found for this item."))); return }

                var availableServings: [ServingSizeOption] = []
                for serving in food.servings.serving {
                    let option = ServingSizeOption(
                        description: serving.displayDescription,
                        servingWeightGrams: serving.parsedServingWeightGrams,
                        calories: serving.parsedNutrient(.calories),
                        protein: serving.parsedNutrient(.protein),
                        carbs: serving.parsedNutrient(.carbohydrate),
                        fats: serving.parsedNutrient(.fat),
                        saturatedFat: serving.parsedOptionalNutrient(.saturatedFat),
                        polyunsaturatedFat: serving.parsedOptionalNutrient(.polyunsaturatedFat),
                        monounsaturatedFat: serving.parsedOptionalNutrient(.monounsaturatedFat),
                        fiber: serving.parsedOptionalNutrient(.fiber),
                        calcium: serving.parsedOptionalNutrient(.calcium),
                        iron: serving.parsedOptionalNutrient(.iron),
                        potassium: serving.parsedOptionalNutrient(.potassium),
                        sodium: serving.parsedOptionalNutrient(.sodium),
                        vitaminA: serving.parsedOptionalNutrient(.vitamin_a),
                        vitaminC: serving.parsedOptionalNutrient(.vitamin_c),
                        vitaminD: serving.parsedOptionalNutrient(.vitamin_d),
                        vitaminB12: serving.parsedOptionalNutrient(.vitamin_b12),
                        folate: serving.parsedOptionalNutrient(.folate),
                        magnesium: serving.parsedOptionalNutrient(.magnesium),
                        phosphorus: serving.parsedOptionalNutrient(.phosphorus),
                        zinc: serving.parsedOptionalNutrient(.zinc),
                        copper: serving.parsedOptionalNutrient(.copper),
                        manganese: serving.parsedOptionalNutrient(.manganese),
                        selenium: serving.parsedOptionalNutrient(.selenium),
                        vitaminB1: serving.parsedOptionalNutrient(.vitamin_b1),
                        vitaminB2: serving.parsedOptionalNutrient(.vitamin_b2),
                        vitaminB3: serving.parsedOptionalNutrient(.vitamin_b3),
                        vitaminB5: serving.parsedOptionalNutrient(.vitamin_b5),
                        vitaminB6: serving.parsedOptionalNutrient(.vitamin_b6),
                        vitaminE: serving.parsedOptionalNutrient(.vitamin_e),
                        vitaminK: serving.parsedOptionalNutrient(.vitamin_k)
                    )
                    availableServings.append(option)
                }
                
                guard let baseServing = food.servings.serving.first(where: { $0.parsedServingWeightGrams == 100.0 && $0.metricServingUnit?.lowercased() == "g" }) ?? food.servings.serving.first else {
                    return completion(.failure(NSError(domain: "FatSecretFoodAPIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No serving options were returned for this food."])))
                }
                let baseFoodItem = FoodItem(
                    id: food.foodID, name: food.brandName.map { "\($0) \(food.foodName)" } ?? food.foodName,
                    calories: baseServing.parsedNutrient(.calories), protein: baseServing.parsedNutrient(.protein),
                    carbs: baseServing.parsedNutrient(.carbohydrate), fats: baseServing.parsedNutrient(.fat),
                    saturatedFat: baseServing.parsedOptionalNutrient(.saturatedFat),
                    polyunsaturatedFat: baseServing.parsedOptionalNutrient(.polyunsaturatedFat),
                    monounsaturatedFat: baseServing.parsedOptionalNutrient(.monounsaturatedFat),
                    fiber: baseServing.parsedOptionalNutrient(.fiber),
                    servingSize: baseServing.displayDescription,
                    servingWeight: baseServing.parsedServingWeightGrams ?? 1.0,
                    timestamp: nil,
                    calcium: baseServing.parsedOptionalNutrient(.calcium),
                    iron: baseServing.parsedOptionalNutrient(.iron),
                    potassium: baseServing.parsedOptionalNutrient(.potassium),
                    sodium: baseServing.parsedOptionalNutrient(.sodium),
                    vitaminA: baseServing.parsedOptionalNutrient(.vitamin_a),
                    vitaminC: baseServing.parsedOptionalNutrient(.vitamin_c),
                    vitaminD: baseServing.parsedOptionalNutrient(.vitamin_d),
                    vitaminB12: baseServing.parsedOptionalNutrient(.vitamin_b12),
                    folate: baseServing.parsedOptionalNutrient(.folate),
                    magnesium: baseServing.parsedOptionalNutrient(.magnesium),
                    phosphorus: baseServing.parsedOptionalNutrient(.phosphorus),
                    zinc: baseServing.parsedOptionalNutrient(.zinc),
                    copper: baseServing.parsedOptionalNutrient(.copper),
                    manganese: baseServing.parsedOptionalNutrient(.manganese),
                    selenium: baseServing.parsedOptionalNutrient(.selenium),
                    vitaminB1: baseServing.parsedOptionalNutrient(.vitamin_b1),
                    vitaminB2: baseServing.parsedOptionalNutrient(.vitamin_b2),
                    vitaminB3: baseServing.parsedOptionalNutrient(.vitamin_b3),
                    vitaminB5: baseServing.parsedOptionalNutrient(.vitamin_b5),
                    vitaminB6: baseServing.parsedOptionalNutrient(.vitamin_b6),
                    vitaminE: baseServing.parsedOptionalNutrient(.vitamin_e),
                    vitaminK: baseServing.parsedOptionalNutrient(.vitamin_k)
                ).withDatabaseSource(
                    .fatSecret,
                    sourceName: "FatSecret",
                    sourceID: food.foodID
                )
                
                completion(.success((foodInfo: baseFoodItem, availableServings: availableServings)))

            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }
    }
    
    public func fetchFoodByQuery(query: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        callProxy(path: "search", params: ["query": query]) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let decodedResponse = try JSONDecoder().decode(FatSecretResponse.self, from: data)
                    if let foods = decodedResponse.foods?.food {
                        completion(.success(foods.map { self.mapSearchResultToFoodItem(from: $0) }))
                    } else {
                        completion(.success([]))
                    }
                } catch {
                    completion(.failure(APIError.decodingError(error)))
                }
            }
        }
    }
    
    private func mapSearchResultToFoodItem(from fatSecretFoodItem: FatSecretFoodItem) -> FoodItem {
        let fullName = fatSecretFoodItem.brandName.map { "\($0) \(fatSecretFoodItem.foodName ?? "")" } ?? (fatSecretFoodItem.foodName ?? "Unknown")
        let preview = parseSearchNutritionPreview(from: fatSecretFoodItem.foodDescription)

        return FoodItem(
            id: fatSecretFoodItem.foodID, name: fullName,
            calories: preview.calories, protein: preview.protein, carbs: preview.carbs, fats: preview.fats,
            saturatedFat: nil, polyunsaturatedFat: nil, monounsaturatedFat: nil, fiber: nil,
            servingSize: preview.servingDescription, servingWeight: preview.servingWeightGrams, timestamp: nil,
            calcium: nil, iron: nil, potassium: nil, sodium: nil,
            vitaminA: nil, vitaminC: nil, vitaminD: nil,
            vitaminB12: nil, folate: nil
        ).withDatabaseSource(
            .fatSecret,
            sourceName: "FatSecret",
            sourceID: fatSecretFoodItem.foodID
        )
    }

    private func parseSearchNutritionPreview(from description: String?) -> (servingDescription: String, servingWeightGrams: Double, calories: Double, protein: Double, carbs: Double, fats: Double) {
        guard let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("Tap to see details", 0, 0, 0, 0, 0)
        }

        let servingDescription = description.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let servingWeight = parseServingWeightGrams(from: servingDescription ?? "")

        return (
            servingDescription: servingDescription ?? "Tap to see details",
            servingWeightGrams: servingWeight,
            calories: extractNutritionValue(afterAny: ["Calories"], in: description) ?? 0,
            protein: extractNutritionValue(afterAny: ["Protein"], in: description) ?? 0,
            carbs: extractNutritionValue(afterAny: ["Carbs", "Carbohydrate"], in: description) ?? 0,
            fats: extractNutritionValue(afterAny: ["Fat", "Fats"], in: description) ?? 0
        )
    }

    private func extractNutritionValue(afterAny labels: [String], in text: String) -> Double? {
        for label in labels {
            if let value = extractNutritionValue(after: label, in: text) {
                return value
            }
        }
        return nil
    }

    private func extractNutritionValue(after label: String, in text: String) -> Double? {
        guard let range = text.range(of: "\(label):", options: .caseInsensitive) else { return nil }
        let remainder = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let numberText = remainder.prefix { character in
            character.isNumber || character == "." || character == ","
        }
        return Double(String(numberText).replacingOccurrences(of: ",", with: "."))
    }

    private func parseServingWeightGrams(from servingDescription: String) -> Double {
        let lowercased = servingDescription.lowercased()
        guard lowercased.contains("g") else { return 0 }
        let numberText = lowercased
            .replacingOccurrences(of: "per", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { character in
                character.isNumber || character == "." || character == ","
            }
        return Double(String(numberText).replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
