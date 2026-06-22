import Foundation
import FirebaseFirestore

struct Nutrition: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fats: Double
    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var fiber: Double?
    var calcium: Double?
    var iron: Double?
    var potassium: Double?
    var sodium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminB12: Double?
    var folate: Double?

    static var zero: Nutrition {
        Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0)
    }
}

struct Recipe: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let name: String
    let ingredients: [String]
    var detailedIngredients: [FoodItem]?
    let instructions: [String]
    var nutrition: Nutrition
    var servings: Double?
}
