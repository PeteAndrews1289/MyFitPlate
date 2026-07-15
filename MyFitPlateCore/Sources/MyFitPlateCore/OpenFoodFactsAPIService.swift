import Foundation

public class OpenFoodFactsAPIService {

    private let baseURL = "https://world.openfoodfacts.org/api/v2/product/"
    private let userAgent = "MyFitPlate/2.2 (iOS; contact: peteandrews1289@gmail.com)"
    private let requestTimeout: TimeInterval = 6

    public init() {}

    public func fetchFoodItem(barcode: String, completion: @escaping (Result<FoodItem, APIError>) -> Void) {

        let urlString = "\(baseURL)\(barcode).json"

        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error))) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(.noData)) }
                return
            }

            do {
                if let foodItem = try OpenFoodFactsParser.foodItem(from: data) {
                    DispatchQueue.main.async { completion(.success(foodItem)) }
                } else {
                    DispatchQueue.main.async { completion(.failure(.noData)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(.decodingError(error))) }
            }
        }.resume()
    }

    /// Asynchronous text search across Open Food Facts global database (~3.2M products).
    public func searchFoods(query: String) async -> [FoodItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=25") else {
            return []
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: requestTimeout)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            return try OpenFoodFactsParser.searchFoods(from: data)
        } catch {
            return []
        }
    }
}

/// Pure, testable parsing of an Open Food Facts product payload into a `FoodItem` (per 100g).
/// Extracted from the network call so the mapping (unit conversions, defaults, missing-product
/// handling) can be unit-tested without hitting the network.
public enum OpenFoodFactsParser {
    /// Returns nil when the response has no usable product (status 0 / missing product) — the
    /// network layer treats that as `.noData`. Throws on malformed JSON.
    public static func foodItem(from data: Data) throws -> FoodItem? {
        let response = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard response.status != 0, let product = response.product else { return nil }
        return foodItem(from: product, allowsUnknownName: true)
    }

    /// Parses an Open Food Facts multi-item search response into clean FoodItem models.
    public static func searchFoods(from data: Data) throws -> [FoodItem] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let products = response.products else { return [] }
        return products.compactMap { foodItem(from: $0, allowsUnknownName: false) }
    }

    private static func foodItem(from product: Product, allowsUnknownName: Bool) -> FoodItem? {
        let trimmedName = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard allowsUnknownName || !trimmedName.isEmpty else { return nil }

        let n = product.nutriments
        let hasNutrition = n.energyKcalServing != nil || n.energyKcal100g != nil
            || n.proteinsServing != nil || n.proteins100g != nil
            || n.carbohydratesServing != nil || n.carbohydrates100g != nil
            || n.fatServing != nil || n.fat100g != nil
        guard hasNutrition else { return nil }

        let servingWeight = resolvedServingWeight(for: product)
        let scale = servingWeight / 100
        func scaled(_ value: Double?) -> Double? { value.map { $0 * scale } }
        func preferred(_ perServing: Double?, _ per100g: Double?) -> Double {
            perServing ?? scaled(per100g) ?? 0
        }
        func preferredOptional(_ perServing: Double?, _ per100g: Double?) -> Double? {
            perServing ?? scaled(per100g)
        }
        func converted(_ perServing: Double?, _ per100g: Double?, multiplier: Double) -> Double? {
            preferredOptional(perServing, per100g).map { $0 * multiplier }
        }

        let servingDescription = product.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayServing = servingDescription?.isEmpty == false
            ? servingDescription!
            : "\(Int(servingWeight.rounded())) g"

        let item = FoodItem(
            id: "off_\(product.id)",
            name: trimmedName.isEmpty ? "Unknown Product" : trimmedName,
            calories: preferred(n.energyKcalServing, n.energyKcal100g),
            protein: preferred(n.proteinsServing, n.proteins100g),
            carbs: preferred(n.carbohydratesServing, n.carbohydrates100g),
            fats: preferred(n.fatServing, n.fat100g),
            saturatedFat: preferredOptional(n.saturatedFatServing, n.saturatedFat100g),
            polyunsaturatedFat: preferredOptional(n.polyunsaturatedFatServing, n.polyunsaturatedFat100g),
            monounsaturatedFat: preferredOptional(n.monounsaturatedFatServing, n.monounsaturatedFat100g),
            fiber: preferredOptional(n.fiberServing, n.fiber100g),
            servingSize: displayServing,
            servingWeight: servingWeight,
            timestamp: nil,
            calcium: converted(n.calciumServing, n.calcium100g, multiplier: 1_000),
            iron: converted(n.ironServing, n.iron100g, multiplier: 1_000),
            potassium: converted(n.potassiumServing, n.potassium100g, multiplier: 1_000),
            sodium: converted(n.sodiumServing, n.sodium100g, multiplier: 1_000),
            vitaminA: converted(n.vitaminAServing, n.vitaminA100g, multiplier: 1_000_000),
            vitaminC: converted(n.vitaminCServing, n.vitaminC100g, multiplier: 1_000),
            vitaminD: converted(n.vitaminDServing, n.vitaminD100g, multiplier: 1_000_000),
            vitaminB12: converted(n.vitaminB12Serving, n.vitaminB12100g, multiplier: 1_000_000),
            folate: converted(
                n.vitaminB9Serving ?? n.folatesServing,
                n.vitaminB9100g ?? n.folates100g,
                multiplier: 1_000_000
            ),
            magnesium: converted(n.magnesiumServing, n.magnesium100g, multiplier: 1_000),
            phosphorus: converted(n.phosphorusServing, n.phosphorus100g, multiplier: 1_000),
            zinc: converted(n.zincServing, n.zinc100g, multiplier: 1_000),
            copper: converted(n.copperServing, n.copper100g, multiplier: 1_000_000),
            manganese: converted(n.manganeseServing, n.manganese100g, multiplier: 1_000),
            selenium: converted(n.seleniumServing, n.selenium100g, multiplier: 1_000_000),
            vitaminB1: converted(n.vitaminB1Serving, n.vitaminB1100g, multiplier: 1_000),
            vitaminB2: converted(n.vitaminB2Serving, n.vitaminB2100g, multiplier: 1_000),
            vitaminB3: converted(
                n.vitaminB3Serving ?? n.vitaminPPServing,
                n.vitaminB3100g ?? n.vitaminPP100g,
                multiplier: 1_000
            ),
            vitaminB5: converted(
                n.vitaminB5Serving ?? n.pantothenicAcidServing,
                n.vitaminB5100g ?? n.pantothenicAcid100g,
                multiplier: 1_000
            ),
            vitaminB6: converted(n.vitaminB6Serving, n.vitaminB6100g, multiplier: 1_000),
            vitaminE: converted(n.vitaminEServing, n.vitaminE100g, multiplier: 1_000),
            vitaminK: converted(n.vitaminKServing, n.vitaminK100g, multiplier: 1_000_000)
        )
        let updatedAt = product.lastModifiedTimestamp.flatMap { timestamp -> Date? in
            guard timestamp.isFinite, timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        let metadata = FoodSourceMetadata.database(
            .openFoodFacts,
            sourceName: "Open Food Facts",
            sourceID: "off_\(product.id)",
            barcode: product.id,
            evidenceLineage: .publicDatabase,
            sourceUpdatedAt: updatedAt
        )
        return item.withSourceMetadata(metadata)
    }

    private static func resolvedServingWeight(for product: Product) -> Double {
        if let quantity = product.servingQuantity, quantity > 0 { return quantity }
        guard let serving = product.servingSize else { return 100 }
        let normalized = serving.lowercased().replacingOccurrences(of: ",", with: ".")
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(?:g|ml)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let valueRange = Range(match.range(at: 1), in: normalized),
              let value = Double(normalized[valueRange]),
              value > 0 else { return 100 }
        return value
    }
}

private struct ProductResponse: Codable {
    public let status: Int
    public let product: Product?
}

private struct SearchResponse: Codable {
    public let count: Int?
    public let products: [Product]?
}

private struct Product: Codable {
    public let id: String
    public let productName: String?
    public let servingSize: String?
    public let servingQuantity: Double?
    public let lastModifiedTimestamp: Double?
    public let nutriments: Nutriments

    public enum CodingKeys: String, CodingKey {
        case id = "code"
        case productName = "product_name"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case lastModifiedTimestamp = "last_modified_t"
        case nutriments
    }
}

private struct Nutriments: Codable {
    public let carbohydrates100g: Double?
    public let carbohydratesServing: Double?
    public let energyKcal100g: Double?
    public let energyKcalServing: Double?
    public let fat100g: Double?
    public let fatServing: Double?
    public let proteins100g: Double?
    public let proteinsServing: Double?
    public let saturatedFat100g: Double?
    public let saturatedFatServing: Double?
    public let fiber100g: Double?
    public let fiberServing: Double?
    public let sodium100g: Double?
    public let sodiumServing: Double?
    public let potassium100g: Double?
    public let potassiumServing: Double?
    public let calcium100g: Double?
    public let calciumServing: Double?
    public let iron100g: Double?
    public let ironServing: Double?
    public let vitaminA100g: Double?
    public let vitaminAServing: Double?
    public let vitaminC100g: Double?
    public let vitaminCServing: Double?
    public let vitaminD100g: Double?
    public let vitaminDServing: Double?
    public let vitaminB12100g: Double?
    public let vitaminB12Serving: Double?
    public let vitaminB9100g: Double?
    public let vitaminB9Serving: Double?
    public let folates100g: Double?
    public let folatesServing: Double?
    public let magnesium100g: Double?
    public let magnesiumServing: Double?
    public let phosphorus100g: Double?
    public let phosphorusServing: Double?
    public let zinc100g: Double?
    public let zincServing: Double?
    public let copper100g: Double?
    public let copperServing: Double?
    public let manganese100g: Double?
    public let manganeseServing: Double?
    public let selenium100g: Double?
    public let seleniumServing: Double?
    public let vitaminB1100g: Double?
    public let vitaminB1Serving: Double?
    public let vitaminB2100g: Double?
    public let vitaminB2Serving: Double?
    public let vitaminB3100g: Double?
    public let vitaminB3Serving: Double?
    public let vitaminPP100g: Double?
    public let vitaminPPServing: Double?
    public let vitaminB5100g: Double?
    public let vitaminB5Serving: Double?
    public let pantothenicAcid100g: Double?
    public let pantothenicAcidServing: Double?
    public let vitaminB6100g: Double?
    public let vitaminB6Serving: Double?
    public let vitaminE100g: Double?
    public let vitaminEServing: Double?
    public let vitaminK100g: Double?
    public let vitaminKServing: Double?
    public let polyunsaturatedFat100g: Double?
    public let polyunsaturatedFatServing: Double?
    public let monounsaturatedFat100g: Double?
    public let monounsaturatedFatServing: Double?

    public enum CodingKeys: String, CodingKey {
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case saturatedFat100g = "saturated-fat_100g"
        case saturatedFatServing = "saturated-fat_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case sodium100g = "sodium_100g"
        case sodiumServing = "sodium_serving"
        case potassium100g = "potassium_100g"
        case potassiumServing = "potassium_serving"
        case calcium100g = "calcium_100g"
        case calciumServing = "calcium_serving"
        case iron100g = "iron_100g"
        case ironServing = "iron_serving"
        case vitaminA100g = "vitamin-a_100g"
        case vitaminAServing = "vitamin-a_serving"
        case vitaminC100g = "vitamin-c_100g"
        case vitaminCServing = "vitamin-c_serving"
        case vitaminD100g = "vitamin-d_100g"
        case vitaminDServing = "vitamin-d_serving"
        case vitaminB12100g = "vitamin-b12_100g"
        case vitaminB12Serving = "vitamin-b12_serving"
        case vitaminB9100g = "vitamin-b9_100g"
        case vitaminB9Serving = "vitamin-b9_serving"
        case folates100g = "folates_100g"
        case folatesServing = "folates_serving"
        case magnesium100g = "magnesium_100g"
        case magnesiumServing = "magnesium_serving"
        case phosphorus100g = "phosphorus_100g"
        case phosphorusServing = "phosphorus_serving"
        case zinc100g = "zinc_100g"
        case zincServing = "zinc_serving"
        case copper100g = "copper_100g"
        case copperServing = "copper_serving"
        case manganese100g = "manganese_100g"
        case manganeseServing = "manganese_serving"
        case selenium100g = "selenium_100g"
        case seleniumServing = "selenium_serving"
        case vitaminB1100g = "vitamin-b1_100g"
        case vitaminB1Serving = "vitamin-b1_serving"
        case vitaminB2100g = "vitamin-b2_100g"
        case vitaminB2Serving = "vitamin-b2_serving"
        case vitaminB3100g = "vitamin-b3_100g"
        case vitaminB3Serving = "vitamin-b3_serving"
        case vitaminPP100g = "vitamin-pp_100g"
        case vitaminPPServing = "vitamin-pp_serving"
        case vitaminB5100g = "vitamin-b5_100g"
        case vitaminB5Serving = "vitamin-b5_serving"
        case pantothenicAcid100g = "pantothenic-acid_100g"
        case pantothenicAcidServing = "pantothenic-acid_serving"
        case vitaminB6100g = "vitamin-b6_100g"
        case vitaminB6Serving = "vitamin-b6_serving"
        case vitaminE100g = "vitamin-e_100g"
        case vitaminEServing = "vitamin-e_serving"
        case vitaminK100g = "vitamin-k_100g"
        case vitaminKServing = "vitamin-k_serving"
        case polyunsaturatedFat100g = "polyunsaturated-fat_100g"
        case polyunsaturatedFatServing = "polyunsaturated-fat_serving"
        case monounsaturatedFat100g = "monounsaturated-fat_100g"
        case monounsaturatedFatServing = "monounsaturated-fat_serving"
    }
}
