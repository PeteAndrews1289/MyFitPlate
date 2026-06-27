import Foundation

class OpenFoodFactsAPIService {
    
    private let baseURL = "https://world.openfoodfacts.org/api/v0/product/"

    func fetchFoodItem(barcode: String, completion: @escaping (Result<FoodItem, APIError>) -> Void) {
        
        let urlString = "\(baseURL)\(barcode).json"
        
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error)))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(.noData))
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let productResponse = try decoder.decode(ProductResponse.self, from: data)
                
                if productResponse.status == 0 {
                    DispatchQueue.main.async {
                        completion(.failure(.noData))
                    }
                    return
                }

                guard let product = productResponse.product else {
                    DispatchQueue.main.async {
                        completion(.failure(.noData))
                    }
                    return
                }

                let nutriments = product.nutriments
                let servingSize = product.servingSize ?? "100g"
                
                let foodItem = FoodItem(
                    id: product.id,
                    name: product.productName ?? "Unknown Product",
                    calories: nutriments.energyKcal100g ?? 0,
                    protein: nutriments.proteins100g ?? 0,
                    carbs: nutriments.carbohydrates100g ?? 0,
                    fats: nutriments.fat100g ?? 0,
                    saturatedFat: nutriments.saturatedFat100g,
                    polyunsaturatedFat: nutriments.polyunsaturatedFat100g,
                    monounsaturatedFat: nutriments.monounsaturatedFat100g,
                    fiber: nutriments.fiber100g,
                    servingSize: servingSize,
                    servingWeight: 100,
                    timestamp: nil,
                    calcium: nutriments.calcium100g.map { $0 * 1000 },
                    iron: nutriments.iron100g.map { $0 * 1000 },
                    potassium: nutriments.potassium100g,
                    sodium: nutriments.sodium100g.map { $0 * 1000 },
                    vitaminA: nutriments.vitaminA100g,
                    vitaminC: nutriments.vitaminC100g.map { $0 * 1000 },
                    vitaminD: nutriments.vitaminD100g
                )
                
                DispatchQueue.main.async {
                    completion(.success(foodItem))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }.resume()
    }
}

private struct ProductResponse: Codable {
    let status: Int
    let product: Product?
}

private struct Product: Codable {
    let id: String
    let productName: String?
    let servingSize: String?
    let nutriments: Nutriments

    enum CodingKeys: String, CodingKey {
        case id = "code"
        case productName = "product_name"
        case servingSize = "serving_size"
        case nutriments
    }
}

private struct Nutriments: Codable {
    let carbohydrates100g: Double?
    let energyKcal100g: Double?
    let fat100g: Double?
    let proteins100g: Double?
    let saturatedFat100g: Double?
    let fiber100g: Double?
    let sodium100g: Double?
    let potassium100g: Double?
    let calcium100g: Double?
    let iron100g: Double?
    let vitaminA100g: Double?
    let vitaminC100g: Double?
    let vitaminD100g: Double?
    let polyunsaturatedFat100g: Double?
    let monounsaturatedFat100g: Double?

    enum CodingKeys: String, CodingKey {
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
