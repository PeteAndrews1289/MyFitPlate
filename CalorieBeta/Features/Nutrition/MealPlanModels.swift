import Foundation
import FirebaseFirestore

struct PlannedMeal: Identifiable, Codable {
    let id: String
    let mealType: String
    var recipeID: String?
    var foodItem: FoodItem?
    var ingredients: [String]?
    var instructions: String?
}

struct MealPlanDay: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Timestamp
    var meals: [PlannedMeal]
}

struct GroceryListItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unit: String
    var isCompleted: Bool = false
    var category: String = "Misc"
    var source: String?
}

enum GroceryUnitSystem: String, Codable {
    case imperial
    case metric
}
