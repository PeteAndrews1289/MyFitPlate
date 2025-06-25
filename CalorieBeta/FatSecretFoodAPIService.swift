import Foundation

struct FatSecretResponse: Decodable {
    let foods: FoodList?
}

struct FoodList: Decodable {
    let food: [FatSecretFoodItem]?
}

struct FatSecretFoodItem: Decodable {
    let foodID: String
    let foodName: String?
    let brandName: String?
    let foodDescription: String?

    enum CodingKeys: String, CodingKey {
        case foodID = "food_id"
        case foodName = "food_name"
        case brandName = "brand_name"
        case foodDescription = "food_description"
    }
}

struct FatSecretFoodResponse: Decodable { let food: FatSecretFood? }
struct FatSecretFood: Decodable { let foodID: String; let foodName: String; let brandName: String?; let servings: FatSecretServings; enum CodingKeys: String, CodingKey { case foodID = "food_id"; case foodName = "food_name"; case brandName = "brand_name"; case servings } }
struct FatSecretServings: Decodable { let serving: [FatSecretServing]; enum CodingKeys: String, CodingKey { case serving }; init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); if let a = try? c.decode([FatSecretServing].self, forKey: .serving) { self.serving = a } else if let s = try? c.decode(FatSecretServing.self, forKey: .serving) { self.serving = [s] } else { self.serving = [] } } }

struct FatSecretServing: Decodable {
    let calories: String?; let protein: String?; let carbohydrate: String?; let fat: String?
    let saturatedFat: String?; let polyunsaturatedFat: String?; let monounsaturatedFat: String?; let fiber: String?
    let servingDescription: String?; let metricServingAmount: String?; let metricServingUnit: String?
    let calcium: String?; let iron: String?; let potassium: String?; let sodium: String?
    let vitamin_a: String?; let vitamin_c: String?; let vitamin_d: String?
    enum CodingKeys: String, CodingKey { case calories, protein, carbohydrate, fat, calcium, iron, potassium, sodium, vitamin_a, vitamin_c, vitamin_d; case saturatedFat = "saturated_fat"; case polyunsaturatedFat = "polyunsaturated_fat"; case monounsaturatedFat = "monounsaturated_fat"; case fiber; case servingDescription = "serving_description"; case metricServingAmount = "metric_serving_amount"; case metricServingUnit = "metric_serving_unit" }

    private func parseDouble(from string: String?) -> Double { guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "n/a" else { return 0.0 }; let cleaned = s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: ""); return Double(cleaned) ?? 0.0 }
    func parsedNutrient(_ key: CodingKeys) -> Double { switch key { case .calories: return parseDouble(from: calories); case .protein: return parseDouble(from: protein); case .carbohydrate: return parseDouble(from: carbohydrate); case .fat: return parseDouble(from: fat); case .saturatedFat: return parseDouble(from: saturatedFat); case .polyunsaturatedFat: return parseDouble(from: polyunsaturatedFat); case .monounsaturatedFat: return parseDouble(from: monounsaturatedFat); case .fiber: return parseDouble(from: fiber); case .calcium: return parseDouble(from: calcium); case .iron: return parseDouble(from: iron); case .potassium: return parseDouble(from: potassium); case .sodium: return parseDouble(from: sodium); case .vitamin_a: return parseDouble(from: vitamin_a); case .vitamin_c: return parseDouble(from: vitamin_c); case .vitamin_d: return parseDouble(from: vitamin_d); default: return 0.0 } }
    var parsedServingWeightGrams: Double? { guard let amountStr = metricServingAmount, let unit = metricServingUnit?.lowercased(), let amount = Double(amountStr), amount > 0 else { return nil }; if unit == "g" { return amount }; if unit == "ml" { return amount }; if unit == "oz" { return amount * 28.3495 }; if unit == "fl oz" { return amount * 29.5735 }; return nil }
    var displayDescription: String { servingDescription ?? "Serving" }
}

class FatSecretFoodAPIService {
    private let proxyURL = "http://34.75.143.244:8080"
    private var barcodeCache = Set<String>()
    
    func fetchFoodByBarcode(barcode: String, completion: @escaping (Result<FoodItem, Error>) -> Void) {
        if barcodeCache.contains(barcode) { return }
        barcodeCache.insert(barcode)
        guard let url = URL(string: "\(proxyURL)/barcode?barcode=\(barcode)") else { completion(.failure(APIError.invalidURL)); return }
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { self.barcodeCache.remove(barcode) }
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            
            do {
                let decodedResponse = try JSONDecoder().decode([String: [String: String]].self, from: data)
                if let foodId = decodedResponse["food_id"]?["value"] {
                    self.fetchFoodDetails(foodId: foodId) { (detailsResult: Result<(foodInfo: FoodItem, availableServings: [ServingSizeOption]), Error>) in
                        switch detailsResult {
                        case .success(let result):
                            completion(.success(result.foodInfo))
                        case .failure(let detailError):
                            completion(.failure(detailError))
                        }
                    }
                } else {
                    completion(.failure(APIError.noData))
                }
            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }
    
    public func fetchFoodDetails(foodId: String, completion: @escaping (Result<(foodInfo: FoodItem, availableServings: [ServingSizeOption]), Error>) -> Void) {
        guard let url = URL(string: "\(proxyURL)/food?food_id=\(foodId)") else { completion(.failure(APIError.invalidURL)); return }
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { print("❌ Detail fetch error for \(foodId): \(error)"); completion(.failure(error)); return }
            guard let data = data else { print("❌ No data received for \(foodId)."); completion(.failure(APIError.noData)); return }
            
            do {
                let decodedResponse = try JSONDecoder().decode(FatSecretFoodResponse.self, from: data)
                guard let food = decodedResponse.food else { print("❌ No food object decoded for \(foodId)."); completion(.failure(APIError.noData)); return }

                guard !food.servings.serving.isEmpty else { print("❌ No serving data found for \(foodId)."); completion(.failure(APIError.noData)); return }

                var availableServings: [ServingSizeOption] = []
                for serving in food.servings.serving {
                    let option = ServingSizeOption(
                        description: serving.displayDescription,
                        servingWeightGrams: serving.parsedServingWeightGrams,
                        calories: serving.parsedNutrient(.calories),
                        protein: serving.parsedNutrient(.protein),
                        carbs: serving.parsedNutrient(.carbohydrate),
                        fats: serving.parsedNutrient(.fat),
                        saturatedFat: serving.parsedNutrient(.saturatedFat),
                        polyunsaturatedFat: serving.parsedNutrient(.polyunsaturatedFat),
                        monounsaturatedFat: serving.parsedNutrient(.monounsaturatedFat),
                        fiber: serving.parsedNutrient(.fiber),
                        calcium: serving.parsedNutrient(.calcium) > 0 ? serving.parsedNutrient(.calcium) : nil,
                        iron: serving.parsedNutrient(.iron) > 0 ? serving.parsedNutrient(.iron) : nil,
                        potassium: serving.parsedNutrient(.potassium) > 0 ? serving.parsedNutrient(.potassium) : nil,
                        sodium: serving.parsedNutrient(.sodium) > 0 ? serving.parsedNutrient(.sodium) : nil,
                        vitaminA: serving.parsedNutrient(.vitamin_a) > 0 ? serving.parsedNutrient(.vitamin_a) : nil,
                        vitaminC: serving.parsedNutrient(.vitamin_c) > 0 ? serving.parsedNutrient(.vitamin_c) : nil,
                        vitaminD: serving.parsedNutrient(.vitamin_d) > 0 ? serving.parsedNutrient(.vitamin_d) : nil
                    )
                    availableServings.append(option)
                }
                
                let baseServing = food.servings.serving.first { $0.parsedServingWeightGrams == 100.0 && $0.metricServingUnit?.lowercased() == "g" } ?? food.servings.serving.first!
                let baseFoodItem = FoodItem(
                    id: food.foodID, name: food.brandName.map { "\($0) \(food.foodName)" } ?? food.foodName,
                    calories: baseServing.parsedNutrient(.calories), protein: baseServing.parsedNutrient(.protein),
                    carbs: baseServing.parsedNutrient(.carbohydrate), fats: baseServing.parsedNutrient(.fat),
                    saturatedFat: baseServing.parsedNutrient(.saturatedFat),
                    polyunsaturatedFat: baseServing.parsedNutrient(.polyunsaturatedFat),
                    monounsaturatedFat: baseServing.parsedNutrient(.monounsaturatedFat),
                    fiber: baseServing.parsedNutrient(.fiber),
                    servingSize: baseServing.displayDescription, servingWeight: baseServing.parsedServingWeightGrams ?? 100.0,
                    timestamp: nil,
                    calcium: baseServing.parsedNutrient(.calcium) > 0 ? baseServing.parsedNutrient(.calcium) : nil,
                    iron: baseServing.parsedNutrient(.iron) > 0 ? baseServing.parsedNutrient(.iron) : nil,
                    potassium: baseServing.parsedNutrient(.potassium) > 0 ? baseServing.parsedNutrient(.potassium) : nil,
                    sodium: baseServing.parsedNutrient(.sodium) > 0 ? baseServing.parsedNutrient(.sodium) : nil,
                    vitaminA: baseServing.parsedNutrient(.vitamin_a) > 0 ? baseServing.parsedNutrient(.vitamin_a) : nil,
                    vitaminC: baseServing.parsedNutrient(.vitamin_c) > 0 ? baseServing.parsedNutrient(.vitamin_c) : nil,
                    vitaminD: baseServing.parsedNutrient(.vitamin_d) > 0 ? baseServing.parsedNutrient(.vitamin_d) : nil
                )
                
                completion(.success((foodInfo: baseFoodItem, availableServings: availableServings)))
                
            } catch {
                print("❌ Detail decoding Error for \(foodId): \(error)")
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }
    
    func fetchFoodByQuery(query: String, completion: @escaping (Result<[FoodItem], Error>) -> Void) {
        guard let url = URL(string: "\(proxyURL)/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { completion(.success([])); return }
        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { completion(.success([])); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            do {
                let decodedResponse = try JSONDecoder().decode(FatSecretResponse.self, from: data)
                if let foods = decodedResponse.foods?.food {
                    let foodItems = foods.map { self.mapSearchResultToFoodItem(from: $0) }
                    completion(.success(foodItems))
                } else {
                    completion(.success([]))
                }
            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }
    
    private func mapSearchResultToFoodItem(from fatSecretFoodItem: FatSecretFoodItem) -> FoodItem {
        let fullName = fatSecretFoodItem.brandName.map { "\($0) \(fatSecretFoodItem.foodName ?? "")" } ?? (fatSecretFoodItem.foodName ?? "Unknown")
        return FoodItem(
            id: fatSecretFoodItem.foodID, name: fullName,
            calories: 0, protein: 0, carbs: 0, fats: 0,
            saturatedFat: 0, polyunsaturatedFat: 0, monounsaturatedFat: 0, fiber: 0,
            servingSize: fatSecretFoodItem.foodDescription ?? "Tap to see details", servingWeight: 0, timestamp: nil,
            calcium: nil, iron: nil, potassium: nil, sodium: nil,
            vitaminA: nil, vitaminC: nil, vitaminD: nil
        )
    }
}
