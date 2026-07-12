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
    public var magnesium: Double?
    public var phosphorus: Double?
    public var zinc: Double?
    public var copper: Double?
    public var manganese: Double?
    public var selenium: Double?
    public var vitaminB1: Double?
    public var vitaminB2: Double?
    public var vitaminB3: Double?
    public var vitaminB5: Double?
    public var vitaminB6: Double?
    public var vitaminE: Double?
    public var vitaminK: Double?

    public init(
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fats: Double = 0,
        saturatedFat: Double? = nil,
        polyunsaturatedFat: Double? = nil,
        monounsaturatedFat: Double? = nil,
        fiber: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        potassium: Double? = nil,
        sodium: Double? = nil,
        vitaminA: Double? = nil,
        vitaminC: Double? = nil,
        vitaminD: Double? = nil,
        vitaminB12: Double? = nil,
        folate: Double? = nil,
        magnesium: Double? = nil,
        phosphorus: Double? = nil,
        zinc: Double? = nil,
        copper: Double? = nil,
        manganese: Double? = nil,
        selenium: Double? = nil,
        vitaminB1: Double? = nil,
        vitaminB2: Double? = nil,
        vitaminB3: Double? = nil,
        vitaminB5: Double? = nil,
        vitaminB6: Double? = nil,
        vitaminE: Double? = nil,
        vitaminK: Double? = nil
    ) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
        self.saturatedFat = saturatedFat; self.polyunsaturatedFat = polyunsaturatedFat; self.monounsaturatedFat = monounsaturatedFat; self.fiber = fiber
        self.calcium = calcium; self.iron = iron; self.potassium = potassium; self.sodium = sodium
        self.vitaminA = vitaminA; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminB12 = vitaminB12; self.folate = folate
        self.magnesium = magnesium; self.phosphorus = phosphorus; self.zinc = zinc; self.copper = copper; self.manganese = manganese; self.selenium = selenium
        self.vitaminB1 = vitaminB1; self.vitaminB2 = vitaminB2; self.vitaminB3 = vitaminB3; self.vitaminB5 = vitaminB5; self.vitaminB6 = vitaminB6
        self.vitaminE = vitaminE; self.vitaminK = vitaminK
    }

    public static var zero: Nutrition {
        Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0)
    }

    public var reportedVitaminMineralCount: Int {
        [
            calcium, iron, potassium, sodium, vitaminA, vitaminC, vitaminD, vitaminB12,
            folate, magnesium, phosphorus, zinc, copper, manganese, selenium, vitaminB1,
            vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminE, vitaminK
        ].compactMap { $0 }.count
    }

    public static func total(for foods: [FoodItem]) -> Nutrition {
        func optionalTotal(_ keyPath: KeyPath<FoodItem, Double?>) -> Double? {
            let values = foods.compactMap { $0[keyPath: keyPath] }
            return values.isEmpty ? nil : values.reduce(0, +)
        }

        return Nutrition(
            calories: foods.reduce(0) { $0 + $1.calories },
            protein: foods.reduce(0) { $0 + $1.protein },
            carbs: foods.reduce(0) { $0 + $1.carbs },
            fats: foods.reduce(0) { $0 + $1.fats },
            saturatedFat: optionalTotal(\.saturatedFat),
            polyunsaturatedFat: optionalTotal(\.polyunsaturatedFat),
            monounsaturatedFat: optionalTotal(\.monounsaturatedFat),
            fiber: optionalTotal(\.fiber),
            calcium: optionalTotal(\.calcium),
            iron: optionalTotal(\.iron),
            potassium: optionalTotal(\.potassium),
            sodium: optionalTotal(\.sodium),
            vitaminA: optionalTotal(\.vitaminA),
            vitaminC: optionalTotal(\.vitaminC),
            vitaminD: optionalTotal(\.vitaminD),
            vitaminB12: optionalTotal(\.vitaminB12),
            folate: optionalTotal(\.folate),
            magnesium: optionalTotal(\.magnesium),
            phosphorus: optionalTotal(\.phosphorus),
            zinc: optionalTotal(\.zinc),
            copper: optionalTotal(\.copper),
            manganese: optionalTotal(\.manganese),
            selenium: optionalTotal(\.selenium),
            vitaminB1: optionalTotal(\.vitaminB1),
            vitaminB2: optionalTotal(\.vitaminB2),
            vitaminB3: optionalTotal(\.vitaminB3),
            vitaminB5: optionalTotal(\.vitaminB5),
            vitaminB6: optionalTotal(\.vitaminB6),
            vitaminE: optionalTotal(\.vitaminE),
            vitaminK: optionalTotal(\.vitaminK)
        )
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

public enum RecipeIngredientQuantityRules {
    public static func adjustedIngredient(_ ingredient: FoodItem, newQuantity: Double) -> FoodItem? {
        guard newQuantity.isFinite, newQuantity > 0 else { return nil }
        let fallbackQuantity = ingredient.servingWeight > 0 ? ingredient.servingWeight : 1
        let oldQuantity = ingredient.quantityValue ?? fallbackQuantity
        guard oldQuantity.isFinite, oldQuantity > 0 else { return nil }

        var adjusted = ingredient.scalingNutritionAndServing(by: newQuantity / oldQuantity)
        adjusted.quantityValue = newQuantity
        return adjusted
    }
}
