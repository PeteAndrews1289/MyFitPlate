import Foundation

// USDA FoodData Central API. Production search requires a dedicated key from
// https://fdc.nal.usda.gov/api-key-signup.html; the shared DEMO_KEY is intentionally not used.
public class USDAFoodAPIService {
    private let apiKey: String?
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let requestTimeout: TimeInterval = 6
    private let session: URLSession

    public init() {
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String
        apiKey = (plistKey?.isEmpty == false && plistKey != "$(USDA_API_KEY)") ? plistKey : nil

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    // Text search — lab/reference foods plus FNDDS prepared-food records.
    // FatSecret covers branded foods, so USDA complements it with richer nutrient panels.
    public func searchFoods(query: String) async -> [FoodItem] {
        guard let apiKey else { return [] }
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)")
        ]
        guard let url = components.url else { return [] }
        do {
            let data = try await responseData(from: url)
            return FoodSearchRanking.rankedRemoteMatches(
                query: query,
                foods: try USDAFoodParser.foodItems(from: data)
            )
        } catch {
            return []
        }
    }

    // Barcode (GTIN/UPC) lookup — searches Branded foods dataset by the UPC string.
    public func lookupBarcode(_ barcode: String) async -> FoodItem? {
        guard let apiKey else { return nil }
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard (8...14).contains(normalized.count),
              normalized.allSatisfy(\.isNumber) else { return nil }
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: normalized),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "dataType", value: "Branded")
        ]
        guard let url = components.url else { return nil }
        do {
            let data = try await responseData(from: url)
            return try USDAFoodParser.foodItem(matchingBarcode: normalized, from: data)
        } catch {
            return nil
        }
    }

    private func responseData(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Pure, testable parsing of a USDA FoodData Central search response into `FoodItem`s.
/// Extracted from the network call so the per-serving scaling, unit conversion and name/serving
/// cleanup can be unit-tested without hitting the network.
public enum USDAFoodParser {
    public static func foodItems(from data: Data) throws -> [FoodItem] {
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return response.foods.map { foodItem(from: $0) }
    }

    /// USDA's barcode endpoint is a text search, so the first result is not proof of identity.
    /// Accept only a response carrying the scanned GTIN or a zero-padded equivalent.
    public static func foodItem(matchingBarcode barcode: String, from data: Data) throws -> FoodItem? {
        let candidates = Set(BarcodeCorrectionRules.lookupCandidates(for: barcode))
        guard !candidates.isEmpty else { return nil }
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        guard let match = response.foods.first(where: { food in
            guard let gtin = food.gtinUpc else { return false }
            return candidates.contains(BarcodeCorrectionRules.normalizedBarcode(gtin))
        }) else {
            return nil
        }
        return foodItem(from: match)
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
        func o(_ num: String, multiplier: Double = 1) -> Double? {
            guard let value = nutrients[num], value.isFinite, value >= 0 else { return nil }
            return value * scale * multiplier
        }

        let servingDescription: String
        if let hh = food.householdServingFullText, !hh.isEmpty {
            servingDescription = hh
        } else if let size = food.servingSize {
            servingDescription = "\(Int(size.rounded())) \(food.servingSizeUnit ?? "g")"
        } else {
            servingDescription = "100 g"
        }

        // Preserve preparation and form qualifiers. "APPLES, DRIED" must never be presented as
        // plain "Apples" because the calorie density is materially different.
        let displayName = food.description
            .lowercased()
            .capitalized
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")

        let item = FoodItem(
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
            // FoodItem uses mcg RAE. Nutrient 318 is IU and cannot be relabeled as mcg.
            vitaminA: o("320"),
            vitaminC: o("401"),
            vitaminD: o("328"),
            vitaminB12: o("418"),
            folate: o("417"),
            magnesium: o("304"),
            phosphorus: o("305"),
            zinc: o("309"),
            // USDA reports copper in mg; FoodItem's established display/goal unit is mcg.
            copper: o("312", multiplier: 1_000),
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
        var metadata = FoodSourceMetadata.database(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_\(food.fdcId)",
            barcode: food.gtinUpc
        )
        metadata.confidence = usdaConfidence(for: food.dataType)
        metadata.evidenceLineage = usdaLineage(for: food.dataType)
        metadata.sourceUpdatedAt = usdaDate(food.modifiedDate ?? food.publishedDate)
        return item.withSourceMetadata(metadata)
    }

    private static func usdaConfidence(for dataType: String?) -> FoodConfidenceLevel {
        let normalized = dataType?.lowercased() ?? ""
        if normalized.contains("foundation") || normalized.contains("sr legacy") {
            return .verified
        }
        // Branded records are manufacturer label submissions hosted by USDA, not an
        // independent laboratory confirmation. Unknown future types stay conservative.
        return .databaseMatch
    }

    private static func usdaLineage(for dataType: String?) -> FoodEvidenceLineage {
        let normalized = dataType?.lowercased() ?? ""
        if normalized.contains("foundation") ||
            normalized.contains("sr legacy") ||
            normalized.contains("experimental") {
            return .analyticalReference
        }
        if normalized.contains("survey") || normalized.contains("fndds") {
            return .governmentCompilation
        }
        if normalized.contains("branded") {
            return .manufacturerLabel
        }
        return .unknown
    }

    private static func usdaDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
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
    public let gtinUpc: String?
    public let servingSize: Double?
    public let servingSizeUnit: String?
    public let householdServingFullText: String?
    public let publishedDate: String?
    public let modifiedDate: String?
    public let foodNutrients: [USDANutrient]
}

private struct USDANutrient: Decodable {
    public let nutrientId: Int?
    public let nutrientNumber: String?
    public let value: Double?
    public let unitName: String?
}
