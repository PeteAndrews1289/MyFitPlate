import Foundation

public class OpenFoodFactsAPIService {

    private let baseURL = "https://world.openfoodfacts.org/api/v0/product/"

    public func fetchFoodItem(barcode: String, completion: @escaping (Result<FoodItem, APIError>) -> Void) {

        let urlString = "\(baseURL)\(barcode).json"

        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in

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

        let n = product.nutriments
        return FoodItem(
            id: product.id,
            name: product.productName ?? "Unknown Product",
            calories: n.energyKcal100g ?? 0,
            protein: n.proteins100g ?? 0,
            carbs: n.carbohydrates100g ?? 0,
            fats: n.fat100g ?? 0,
            saturatedFat: n.saturatedFat100g,
            polyunsaturatedFat: n.polyunsaturatedFat100g,
            monounsaturatedFat: n.monounsaturatedFat100g,
            fiber: n.fiber100g,
            servingSize: product.servingSize ?? "100g",
            servingWeight: 100,
            timestamp: nil,
            // Open Food Facts reports these minerals in grams/100g; the app stores mg.
            calcium: n.calcium100g.map { $0 * 1000 },
            iron: n.iron100g.map { $0 * 1000 },
            potassium: n.potassium100g,
            sodium: n.sodium100g.map { $0 * 1000 },
            vitaminA: n.vitaminA100g,
            vitaminC: n.vitaminC100g.map { $0 * 1000 },
            vitaminD: n.vitaminD100g
        )
    }
}

private struct ProductResponse: Codable {
    public let status: Int
    public let product: Product?
}

private struct Product: Codable {
    public let id: String
    public let productName: String?
    public let servingSize: String?
    public let nutriments: Nutriments

    public enum CodingKeys: String, CodingKey {
        case id = "code"
        case productName = "product_name"
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct Nutriments: Codable {
    public let carbohydrates100g: Double?
    public let energyKcal100g: Double?
    public let fat100g: Double?
    public let proteins100g: Double?
    public let saturatedFat100g: Double?
    public let fiber100g: Double?
    public let sodium100g: Double?
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
        case energyKcal100g = "energy-kcal_100g"
        case fat100g = "fat_100g"
        case proteins100g = "proteins_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case fiber100g = "fiber_100g"
        case sodium100g = "sodium_100g"
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
