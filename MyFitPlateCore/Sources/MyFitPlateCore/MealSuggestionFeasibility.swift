import Foundation

/// Text is evidence of what Maia proposed, not proof of food identity or a gram conversion.
public struct MealSuggestionIngredientReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let description: String
    public let quantityText: String?
    public let source: String
    public let resolvedFood: FoodItem?
    public init(id: String, description: String, quantityText: String? = nil, source: String = "Maia estimate", resolvedFood: FoodItem? = nil) {
        self.id = id; self.description = description; self.quantityText = quantityText; self.source = source; self.resolvedFood = resolvedFood
    }
    public var isResolved: Bool { resolvedFood != nil }
}

public struct MealSuggestionFeasibility: Codable, Hashable, Sendable {
    public let version: Int
    public let prepMinutes: Int?
    public let ingredients: [MealSuggestionIngredientReceipt]
    public let capturedAt: Date
    public init(prepMinutes: Int?, ingredients: [MealSuggestionIngredientReceipt], capturedAt: Date = Date()) {
        version = 1; self.prepMinutes = prepMinutes.flatMap { (1...240).contains($0) ? $0 : nil }
        self.ingredients = ingredients; self.capturedAt = capturedAt
    }
    public var unresolvedCount: Int { ingredients.filter { !$0.isResolved }.count }
}

public enum MealSuggestionAlternativeReason: String, Codable, CaseIterable, Sendable {
    case anotherIdea, cheaper, quicker, differentCuisine, vegetarian
    public var title: String {
        switch self {
        case .anotherIdea: "Another idea"
        case .cheaper: "Lower-cost ingredients"
        case .quicker: "Less prep time"
        case .differentCuisine: "Different cuisine"
        case .vegetarian: "Vegetarian option"
        }
    }
    public var instruction: String {
        switch self {
        case .anotherIdea: "Use a different main ingredient and preparation."
        case .cheaper: "Use commonly inexpensive ingredients; do not invent local prices or guarantee savings."
        case .quicker: "Reduce the estimated preparation time, using fewer steps and ingredients."
        case .differentCuisine: "Choose a clearly different cuisine and preparation from the prior idea, while honoring hard constraints."
        case .vegetarian: "Use no meat, poultry, fish, seafood, animal stock or gelatin; respect any stricter saved ingredient constraints."
        }
    }
}

public struct MealSuggestionRejectionEvidence: Codable, Hashable, Sendable {
    public let suggestionID: UUID
    public let name: String
    public let reason: MealSuggestionAlternativeReason
    public let recordedAt: Date
    public init(suggestionID: UUID, name: String, reason: MealSuggestionAlternativeReason, recordedAt: Date) {
        self.suggestionID = suggestionID; self.name = name; self.reason = reason; self.recordedAt = recordedAt
    }
}

public struct MealSuggestionAlternativeReceipt: Codable {
    public let previous: MealSuggestion
    public let reason: MealSuggestionAlternativeReason
    public let replacedAt: Date
}

public struct MealSuggestionBudget: Codable, Equatable, Sendable {
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public init(calories: Double, protein: Double, carbs: Double, fats: Double) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
    }
    public var isValid: Bool { calories.isFinite && (0...1_000_000).contains(calories) && [protein, carbs, fats].allSatisfy { $0.isFinite && (0...100_000).contains($0) } }
    public func fits(_ foods: [FoodItem]) -> Bool {
        guard isValid, !foods.isEmpty,
              foods.allSatisfy({ [$0.calories, $0.protein, $0.carbs, $0.fats].allSatisfy { $0.isFinite && $0 >= 0 } }) else { return false }
        return foods.reduce(0) { $0 + $1.calories } <= calories + 0.01 &&
            foods.reduce(0) { $0 + $1.protein } <= protein + 0.01 &&
            foods.reduce(0) { $0 + $1.carbs } <= carbs + 0.01 &&
            foods.reduce(0) { $0 + $1.fats } <= fats + 0.01
    }
    public func subtracting(_ log: DailyLog) -> MealSuggestionBudget? {
        let values = log.meals.flatMap(\.foodItems)
        guard isValid, values.allSatisfy({ [$0.calories, $0.protein, $0.carbs, $0.fats].allSatisfy { $0.isFinite && $0 >= 0 } }) else { return nil }
        guard log.totalCalories().isFinite, log.totalCalories() >= 0,
              [log.totalMacros().protein, log.totalMacros().carbs, log.totalMacros().fats].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return .init(calories: max(0, calories - log.totalCalories()), protein: max(0, protein - log.totalMacros().protein),
                     carbs: max(0, carbs - log.totalMacros().carbs), fats: max(0, fats - log.totalMacros().fats))
    }
}

public struct MealSuggestionBudgetReceipt: Codable, Equatable, Sendable {
    public let day: DiaryDayContext
    public let remaining: MealSuggestionBudget
    public let goals: MealSuggestionBudget
    public let diaryFoods: Data
    public let reviewedFoods: Data
    public var acceptsAboveBudget: Bool
    public init?(day: DiaryDayContext, log: DailyLog, goals: MealSuggestionBudget, foods: [FoodItem]) {
        guard log.id == day.dayKey, let remaining = goals.subtracting(log) else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let diary = try? encoder.encode(log.meals), let selected = try? encoder.encode(foods) else { return nil }
        self.day = day; self.remaining = remaining; self.goals = goals; diaryFoods = diary; reviewedFoods = selected; acceptsAboveBudget = false
    }
    public func sameEvidence(as other: Self) -> Bool {
        day == other.day && goals == other.goals && remaining == other.remaining && diaryFoods == other.diaryFoods && reviewedFoods == other.reviewedFoods
    }
}

public enum MealSuggestionFeasibilityRules {
    /// Never trust model-supplied food IDs, provider names or resolved nutrient receipts.
    public static func generatedEvidence(for suggestion: MealSuggestion, now: Date = Date()) -> MealSuggestionFeasibility {
        .init(prepMinutes: suggestion.prepMinutes, ingredients: suggestion.ingredients.enumerated().map { index, text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Preserve an explicit leading quantity phrase verbatim; no unit-to-grams conversion.
            let words = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
            let startsWithQuantity = words.first?.first.map { $0.isNumber } ?? false
            return .init(id: "\(suggestion.id.uuidString):\(index)", description: text,
                quantityText: startsWithQuantity && words.count >= 2 ? words.prefix(2).joined(separator: " ") : nil)
        }, capturedAt: now)
    }
    public static func fitsGeneration(_ suggestion: MealSuggestion, remaining: MealSuggestionBudget) -> Bool {
        guard remaining.calories > 0, let food = suggestion.reviewFood,
              !suggestion.ingredients.isEmpty, !suggestion.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let macroCalories = food.protein * 4 + food.carbs * 4 + food.fats * 9
        guard abs(macroCalories - food.calories) <= max(25, food.calories * 0.15) else { return false }
        return remaining.fits([food])
    }
}

public struct TrainingFuelFoodAvailability: Equatable, Sendable {
    public let plannedMealCount: Int
    public let recentFoodCount: Int
    public let pantryItemCount: Int
    public init(plannedMealCount: Int = 0, recentFoodCount: Int = 0, pantryItemCount: Int = 0) {
        self.plannedMealCount = max(0, plannedMealCount); self.recentFoodCount = max(0, recentFoodCount); self.pantryItemCount = max(0, pantryItemCount)
    }
    public enum Route: String, Sendable { case plannedMeal, recentFood, pantryIdea, search }
    public var recommended: Route {
        if plannedMealCount > 0 { return .plannedMeal }
        if recentFoodCount > 0 { return .recentFood }
        if pantryItemCount > 0 { return .pantryIdea }
        return .search
    }
}
