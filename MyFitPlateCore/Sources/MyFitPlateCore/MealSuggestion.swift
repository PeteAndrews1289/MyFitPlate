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

    // The AI response contains only the keys the prompt asks for: mealName, calories,
    // protein, carbs, fats, ingredients, instructions. The synthesized decoder demanded
    // "id" and "title" too, so EVERY generated suggestion failed to decode — the feature
    // was dead on arrival. Decode defensively: id is minted locally, title falls back to
    // the meal name, and the optional extras tolerate absence.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mealName = try container.decode(String.self, forKey: .mealName)

        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.mealName = mealName
        self.title = (try? container.decode(String.self, forKey: .title)) ?? mealName
        self.calories = try container.decode(Double.self, forKey: .calories)
        self.protein = try container.decode(Double.self, forKey: .protein)
        self.carbs = try container.decode(Double.self, forKey: .carbs)
        self.fats = try container.decode(Double.self, forKey: .fats)
        self.ingredients = (try? container.decode([String].self, forKey: .ingredients)) ?? []
        self.instructions = (try? container.decode(String.self, forKey: .instructions)) ?? ""
    }
}
