import Foundation

// USDA FoodData Central API (free, no secret - DEMO_KEY is fine for moderate usage).
// Register at https://fdc.nal.usda.gov/api-key-signup.html for a dedicated key.
public class USDAFoodAPIService {
    private let apiKey: String
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"

    public init() {
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String
        apiKey = (plistKey?.isEmpty == false && plistKey != "$(USDA_API_KEY)") ? plistKey! : "DEMO_KEY"
    }

    // Text search — Foundation + SR Legacy data types (whole foods, ingredients).
    // FatSecret covers branded foods, so USDA complements with raw/cooked whole-food data.
    public func searchFoods(query: String) async -> [FoodItem] {
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
            return try USDAFoodParser.foodItems(from: data)
        } catch {
            return []
        }
    }

    // Barcode (GTIN/UPC) lookup — searches Branded foods dataset by the UPC string.
    public func lookupBarcode(_ barcode: String) async -> FoodItem? {
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
            return try USDAFoodParser.foodItems(from: data).first
        } catch {
            return nil
        }
    }
}

/// Pure, testable parsing of a USDA FoodData Central search response into `FoodItem`s.
/// Extracted from the network call so the per-serving scaling, zero-filtering and name/serving
/// cleanup can be unit-tested without hitting the network.
public enum USDAFoodParser {
    public static func foodItems(from data: Data) throws -> [FoodItem] {
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return response.foods.map { foodItem(from: $0) }
    }

    fileprivate static func foodItem(from food: USDAFood) -> FoodItem {
        // Build lookup by standard nutrient number string ("208", "203", etc.)
        var nutrients = [String: Double]()
        for n in food.foodNutrients {
            if let num = n.nutrientNumber, let val = n.value {
                nutrients[num] = val
            }
        }

        // USDA reports per 100 g; scale to the item's declared serving size (grams only).
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
        ).withDatabaseSource(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_\(food.fdcId)"
        )
    }
}

// MARK: - Response Models

private struct USDASearchResponse: Decodable {
    public let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    public let fdcId: Int
    public let description: String
    public let dataType: String?
    public let brandOwner: String?
    public let servingSize: Double?
    public let servingSizeUnit: String?
    public let householdServingFullText: String?
    public let foodNutrients: [USDANutrient]
}

private struct USDANutrient: Decodable {
    public let nutrientId: Int?
    public let nutrientNumber: String?
    public let value: Double?
    public let unitName: String?
}
