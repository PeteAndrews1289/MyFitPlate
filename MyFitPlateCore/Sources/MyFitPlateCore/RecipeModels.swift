import Foundation
public struct Nutrition: Codable, Equatable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fats: Double
    public var saturatedFat: Double?
    public var polyunsaturatedFat: Double?
    public var monounsaturatedFat: Double?
    public var fiber: Double?
    public var calcium: Double?
    public var iron: Double?
    public var potassium: Double?
    public var sodium: Double?
    public var vitaminA: Double?
    public var vitaminC: Double?
    public var vitaminD: Double?
    public var vitaminB12: Double?
    public var folate: Double?

    public init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fats: Double = 0, saturatedFat: Double? = nil, polyunsaturatedFat: Double? = nil, monounsaturatedFat: Double? = nil, fiber: Double? = nil, calcium: Double? = nil, iron: Double? = nil, potassium: Double? = nil, sodium: Double? = nil, vitaminA: Double? = nil, vitaminC: Double? = nil, vitaminD: Double? = nil, vitaminB12: Double? = nil, folate: Double? = nil) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
        self.saturatedFat = saturatedFat; self.polyunsaturatedFat = polyunsaturatedFat; self.monounsaturatedFat = monounsaturatedFat; self.fiber = fiber
        self.calcium = calcium; self.iron = iron; self.potassium = potassium; self.sodium = sodium
        self.vitaminA = vitaminA; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminB12 = vitaminB12; self.folate = folate
    }

    public static var zero: Nutrition {
        Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0)
    }
}

public struct Recipe: Identifiable, Codable, Equatable {
    public var id: String?
    public let name: String
    public let ingredients: [String]
    public var detailedIngredients: [FoodItem]?
    public let instructions: [String]
    public var nutrition: Nutrition
    public var servings: Double?
    public var imageURL: String?
    
    public init(id: String? = nil, name: String, ingredients: [String], detailedIngredients: [FoodItem]? = nil, instructions: [String], nutrition: Nutrition, servings: Double? = nil, imageURL: String? = nil) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
        self.detailedIngredients = detailedIngredients
        self.instructions = instructions
        self.nutrition = nutrition
        self.servings = servings
        self.imageURL = imageURL
    }
}
