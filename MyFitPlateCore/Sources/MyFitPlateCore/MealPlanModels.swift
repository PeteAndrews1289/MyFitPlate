import Foundation
public struct PlannedMeal: Identifiable, Codable {
    public var id: String
    public var mealType: String
    public var recipeID: String?
    public var foodItem: FoodItem?
    public var ingredients: [String]?
    public var instructions: String?
    
    public init(id: String = UUID().uuidString, mealType: String, recipeID: String? = nil, foodItem: FoodItem? = nil, ingredients: [String]? = nil, instructions: String? = nil) {
        self.id = id
        self.mealType = mealType
        self.recipeID = recipeID
        self.foodItem = foodItem
        self.ingredients = ingredients
        self.instructions = instructions
    }
}

public struct MealPlanDay: Identifiable, Codable {
    public var id: String
    public var date: Date
    public var meals: [PlannedMeal]
    
    public init(id: String, date: Date, meals: [PlannedMeal]) {
        self.id = id
        self.date = date
        self.meals = meals
    }
}

public struct GroceryListItem: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var quantity: Double
    public var unit: String
    public var isCompleted: Bool = false
    public var category: String = "Misc"
    public var source: String?

    public init(id: UUID = UUID(), name: String, quantity: Double, unit: String, isCompleted: Bool = false, category: String = "Misc", source: String? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.isCompleted = isCompleted
        self.category = category
        self.source = source
    }
}

public enum GroceryUnitSystem: String, Codable {
    case imperial
    case metric
}
