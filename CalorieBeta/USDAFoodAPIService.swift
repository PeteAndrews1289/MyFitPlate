import Foundation

// USDA FoodData Central API (free, no secret - DEMO_KEY is fine for moderate usage).
// Register at https://fdc.nal.usda.gov/api-key-signup.html for a dedicated key.
class USDAFoodAPIService {
    private let apiKey: String
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"

    init() {
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String
        apiKey = (plistKey?.isEmpty == false && plistKey != "$(USDA_API_KEY)") ? plistKey! : "DEMO_KEY"
    }

    // Text search — Foundation + SR Legacy data types (whole foods, ingredients).
    // FatSecret covers branded foods, so USDA complements with raw/cooked whole-food data.
    func searchFoods(query: String) async -> [FoodItem] {
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy")
        ]
        guard let url = components.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            return response.foods.map { mapToFoodItem($0) }
        } catch {
            return []
        }
    }

    // Barcode (GTIN/UPC) lookup — searches Branded foods dataset by the UPC string.
    func lookupBarcode(_ barcode: String) async -> FoodItem? {
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: barcode),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "dataType", value: "Branded")
        ]
        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            return response.foods.first.map { mapToFoodItem($0) }
        } catch {
            return nil
        }
    }

    private func mapToFoodItem(_ food: USDAFood) -> FoodItem {
        // Build lookup by standard nutrient number string ("208", "203", etc.)
        var nutrients = [String: Double]()
        for n in food.foodNutrients {
            if let num = n.nutrientNumber, let val = n.value {
                nutrients[num] = val
            }
        }

        // USDA reports per 100 g; scale to the item's declared serving size
        let servingGrams = (food.servingSizeUnit?.lowercased() == "g" ? food.servingSize : nil) ?? 100.0
        let scale = servingGrams / 100.0

        func v(_ num: String) -> Double { (nutrients[num] ?? 0) * scale }
        func o(_ num: String) -> Double? { nutrients[num].map { $0 * scale }.flatMap { $0 > 0 ? $0 : nil } }

        let servingDescription: String
        if let hh = food.householdServingFullText, !hh.isEmpty {
            servingDescription = hh
        } else if let size = food.servingSize {
            servingDescription = "\(Int(size.rounded())) \(food.servingSizeUnit ?? "g")"
        } else {
            servingDescription = "100 g"
        }

        // Capitalise only the first word cluster (e.g. "APPLE, RAW" → "Apple")
        let displayName: String = {
            let first = food.description.split(separator: ",").first.map(String.init) ?? food.description
            return first.trimmingCharacters(in: .whitespaces).capitalized
        }()

        return FoodItem(
            id: "usda_\(food.fdcId)",
            name: displayName,
            calories: v("208"),
            protein: v("203"),
            carbs: v("205"),
            fats: v("204"),
            saturatedFat: o("606"),
            polyunsaturatedFat: o("646"),
            monounsaturatedFat: o("645"),
            fiber: o("291"),
            servingSize: servingDescription,
            servingWeight: servingGrams,
            timestamp: nil,
            calcium: o("301"),
            iron: o("303"),
            potassium: o("306"),
            sodium: o("307"),
            vitaminA: o("318"),
            vitaminC: o("401"),
            vitaminD: o("328"),
            vitaminB12: o("418"),
            folate: o("417"),
            magnesium: o("304"),
            phosphorus: o("305"),
            zinc: o("309"),
            copper: o("312"),
            manganese: o("315"),
            selenium: o("317"),
            vitaminB1: o("404"),
            vitaminB2: o("405"),
            vitaminB3: o("406"),
            vitaminB5: o("410"),
            vitaminB6: o("415"),
            vitaminE: o("323"),
            vitaminK: o("430")
        )
    }
}

// MARK: - Response Models

private struct USDASearchResponse: Decodable {
    let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodNutrients: [USDANutrient]
}

private struct USDANutrient: Decodable {
    let nutrientId: Int?
    let nutrientNumber: String?
    let value: Double?
    let unitName: String?
}
