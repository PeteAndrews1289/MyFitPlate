import Foundation

func capitalizedFirstLetter(of string: String) -> String {
    guard let first = string.first else { return "" }
    return first.uppercased() + string.dropFirst()
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let isUser: Bool
}

struct MaiaActionPayload: Codable, Identifiable {
    var id: UUID { UUID() }
    let type: String?
    let mealName: String?
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fats: Double?
    
    let exerciseName: String?
    let durationMinutes: Int?
    let caloriesBurned: Double?
    
    let amountOunces: Double?
    let fastHours: Int?
    let weightPounds: Double?
}

enum MaiaAction {
    case generateMealPlan
    case logWorkout(exerciseName: String, durationMinutes: Int, caloriesBurned: Double)
    case logWater(amountOunces: Double)
    case startFast(hours: Int)
    case stopFast
    case logWeight(weightPounds: Double)
}
