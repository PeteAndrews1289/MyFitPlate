import Foundation

public func capitalizedFirstLetter(of string: String) -> String {
    guard let first = string.first else { return "" }
    return first.uppercased() + string.dropFirst()
}

public struct ChatMessage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let text: String
    public let isUser: Bool

    public init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

public struct MaiaActionPayload: Codable, Identifiable {
    public var id: UUID { UUID() }
    public let type: String?
    public let mealName: String?
    public let calories: Double?
    public let protein: Double?
    public let carbs: Double?
    public let fats: Double?
    
    public let exerciseName: String?
    public let durationMinutes: Int?
    public let caloriesBurned: Double?
    
    public let amountOunces: Double?
    public let fastHours: Int?
    public let weightPounds: Double?
}

public enum MaiaAction {
    case generateMealPlan
    case logWorkout(exerciseName: String, durationMinutes: Int, caloriesBurned: Double)
    case logWater(amountOunces: Double)
    case startFast(hours: Int)
    case stopFast
    case logWeight(weightPounds: Double)
}
