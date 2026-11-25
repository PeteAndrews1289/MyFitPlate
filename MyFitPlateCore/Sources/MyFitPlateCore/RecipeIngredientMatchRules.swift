import Foundation

public struct RecipeIngredientMatchSuggestion: Sendable {
    public let food: FoodItem
    public let sourceAmountMatched: Bool
    public let explanation: String
}

/// Matching a food identifies its nutrition source; it does not establish a new recipe quantity.
public enum RecipeIngredientMatchRules {
    public static func suggestion(sourceText: String, selectedFood: FoodItem) -> RecipeIngredientMatchSuggestion {
        let fallback = normalizedSelectedAmount(selectedFood)
        guard let source = explicitQuantity(sourceText),
              let reference = reference(for: selectedFood, compatibleWith: source.unit),
              let amount = InventoryQuantityRules.convert(source.amount, from: source.unit, to: reference.unit),
              let adjusted = scaled(selectedFood, from: reference.amount, to: amount, unit: reference.unit) else {
            return RecipeIngredientMatchSuggestion(food: fallback, sourceAmountMatched: false,
                explanation: "The original amount cannot be converted safely to this food's measured amount. Review and enter the amount below. Package sizes and ingredient density are not assumed.")
        }
        return RecipeIngredientMatchSuggestion(food: adjusted, sourceAmountMatched: true,
            explanation: "The proposed amount preserves the original quantity using compatible measured units. Check the food and amount before confirming.")
    }

    /// Nil means that no quantity conversion is established, rather than an invented one-item amount.
    public static func suggestedAmount(sourceText: String, selectedFood: FoodItem) -> Double? {
        let result = suggestion(sourceText: sourceText, selectedFood: selectedFood)
        return result.sourceAmountMatched ? result.food.quantityValue : nil
    }

    public static func reviewedAmount(_ amount: Double, for food: FoodItem) -> FoodItem? {
        guard let reference = food.quantityValue, let unit = food.servingUnit else { return nil }
        return scaled(food, from: reference, to: amount, unit: unit)
    }

    private static let mass = Set(["g", "kg", "oz", "lb"])
    private static let volume = Set(["ml", "L", "cup", "tbsp", "tsp", "fl oz"])
    private static let count = Set(["item", "slice", "clove", "egg"])

    private static func reference(for food: FoodItem, compatibleWith source: String) -> (amount: Double, unit: String)? {
        if let amount = food.quantityValue, amount.isFinite, amount > 0, let rawUnit = food.servingUnit {
            let unit = normalizedUnit(rawUnit)
            let compatible = mass.contains(source) && mass.contains(unit)
                || volume.contains(source) && volume.contains(unit)
                || count.contains(source) && source == unit
            if compatible { return (amount, unit) }
        }
        if mass.contains(source), food.servingWeight.isFinite, food.servingWeight > 0 {
            return (food.servingWeight, "g")
        }
        return nil
    }

    private static func normalizedSelectedAmount(_ food: FoodItem) -> FoodItem {
        if let amount = food.quantityValue, amount.isFinite, amount > 0,
           let unit = food.servingUnit, !unit.trimmingCharacters(in: .whitespaces).isEmpty {
            return scaled(food, from: amount, to: amount, unit: normalizedUnit(unit)) ?? food
        }
        if food.servingWeight.isFinite, food.servingWeight > 0 {
            return scaled(food, from: food.servingWeight, to: food.servingWeight, unit: "g") ?? food
        }
        return scaled(food, from: 1, to: 1, unit: "selected amount") ?? food
    }

    private static func scaled(_ food: FoodItem, from original: Double, to amount: Double, unit: String) -> FoodItem? {
        guard original.isFinite, original > 0, amount.isFinite, (0...1_000_000).contains(amount), amount > 0 else { return nil }
        let multiplier = amount / original
        guard multiplier.isFinite, multiplier > 0 else { return nil }
        var adjusted = food.scalingNutritionAndServing(by: multiplier)
        guard [adjusted.calories, adjusted.protein, adjusted.carbs, adjusted.fats, adjusted.servingWeight]
            .allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        adjusted.quantityValue = amount; adjusted.servingUnit = unit
        adjusted.servingSize = "\(amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))) \(unit)"
        return adjusted
    }

    private static func explicitQuantity(_ text: String) -> (amount: Double, unit: String)? {
        guard let amount = InventoryQuantityRules.explicitLeadingAmount(text) else { return nil }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-]\s+"#, with: "", options: .regularExpression)
        let leading = #"^(?:(?:\d+\s+)?\d+/\d+|(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|\.\d+|[½⅓⅔¼¾⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚])\s+"#
        guard let range = clean.range(of: leading, options: .regularExpression) else { return nil }
        let remainder = clean[range.upperBound...].lowercased()
        let aliases = ["fluid ounces", "fluid ounce", "fl oz", "tablespoons", "tablespoon", "teaspoons", "teaspoon",
            "milliliters", "milliliter", "kilograms", "kilogram", "grams", "gram", "pounds", "pound", "ounces", "ounce",
            "liters", "liter", "cups", "cup", "tbsp", "tsp", "slices", "slice", "cloves", "clove", "pieces", "piece",
            "items", "item", "eggs", "egg", "kg", "ml", "lbs", "lb", "oz", "g", "l"]
        guard let alias = aliases.first(where: { remainder == $0 || remainder.hasPrefix($0 + " ") }) else { return nil }
        return (amount, normalizedUnit(alias))
    }

    private static func normalizedUnit(_ unit: String) -> String {
        let text = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["fluid ounces", "fluid ounce", "fl oz"].contains(text) { return "fl oz" }
        if ["egg", "eggs"].contains(text) { return "egg" }
        return IngredientUnitNormalizer.normalized(text)
    }
}
