import Foundation

public struct MealSuggestion: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let calories: Double
    public let mealName: String
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let ingredients: [String]
    public let instructions: String
    
    public init(id: UUID = UUID(), title: String, calories: Double, mealName: String, protein: Double, carbs: Double, fats: Double, ingredients: [String] = [], instructions: String = "") {
        self.id = id
        self.title = title
        self.calories = calories
        self.mealName = mealName
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.ingredients = ingredients
        self.instructions = instructions
    }
}
