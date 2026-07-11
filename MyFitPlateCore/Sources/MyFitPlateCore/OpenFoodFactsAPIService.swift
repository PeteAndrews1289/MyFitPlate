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

        let servingDescription = product.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayServing = servingDescription?.isEmpty == false
            ? servingDescription!
            : "\(Int(servingWeight.rounded())) g"

        return FoodItem(
            id: "off_\(product.id)",
            name: trimmedName.isEmpty ? "Unknown Product" : trimmedName,
            calories: preferred(n.energyKcalServing, n.energyKcal100g),
            protein: preferred(n.proteinsServing, n.proteins100g),
            carbs: preferred(n.carbohydratesServing, n.carbohydrates100g),
            fats: preferred(n.fatServing, n.fat100g),
            saturatedFat: preferredOptional(n.saturatedFatServing, n.saturatedFat100g),
            polyunsaturatedFat: scaled(n.polyunsaturatedFat100g),
            monounsaturatedFat: scaled(n.monounsaturatedFat100g),
            fiber: preferredOptional(n.fiberServing, n.fiber100g),
            servingSize: displayServing,
            servingWeight: servingWeight,
            timestamp: nil,
            calcium: scaled(n.calcium100g).map { $0 * 1000 },
            iron: scaled(n.iron100g).map { $0 * 1000 },
            potassium: scaled(n.potassium100g).map { $0 * 1000 },
            sodium: preferredOptional(n.sodiumServing, n.sodium100g).map { $0 * 1000 },
            vitaminA: scaled(n.vitaminA100g),
            vitaminC: scaled(n.vitaminC100g).map { $0 * 1000 },
            vitaminD: scaled(n.vitaminD100g)
        ).withDatabaseSource(
            .openFoodFacts,
            sourceName: "Open Food Facts",
            sourceID: "off_\(product.id)",
            barcode: product.id
        )
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
    public let nutriments: Nutriments

    public enum CodingKeys: String, CodingKey {
        case id = "code"
        case productName = "product_name"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
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
    public let calcium100g: Double?
    public let iron100g: Double?
    public let vitaminA100g: Double?
    public let vitaminC100g: Double?
    public let vitaminD100g: Double?
    public let polyunsaturatedFat100g: Double?
    public let monounsaturatedFat100g: Double?

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
        case calcium100g = "calcium_100g"
        case iron100g = "iron_100g"
        case vitaminA100g = "vitamin-a_100g"
        case vitaminC100g = "vitamin-c_100g"
        case vitaminD100g = "vitamin-d_100g"
        case polyunsaturatedFat100g = "polyunsaturated-fat_100g"
        case monounsaturatedFat100g = "monounsaturated-fat_100g"
    }
}
