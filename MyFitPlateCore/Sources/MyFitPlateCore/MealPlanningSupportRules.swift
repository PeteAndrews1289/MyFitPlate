import Foundation

public enum MealPlanningPreferenceRules {
    public static func normalizedItems(selected: Set<String>, custom: String) -> [String] {
        var values = selected.compactMap(normalizedPreference)
        if let custom = normalizedPreference(custom) {
            values.append(custom)
        }

        let canonicalValues = values.reduce(into: [String: String]()) { result, value in
            let key = value.lowercased()
            guard let existing = result[key] else {
                result[key] = value
                return
            }
            if value < existing {
                result[key] = value
            }
        }
        return canonicalValues.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public static func normalizedCuisines(_ selected: Set<String>) -> [String] {
        let choices = selected.compactMap(normalizedPreference)
        guard !choices.isEmpty, !choices.contains(where: { $0.caseInsensitiveCompare("Any") == .orderedSame }) else {
            return ["Any"]
        }
        return normalizedItems(selected: Set(choices), custom: "")
    }

    public static func toggledCuisine(_ cuisine: String, in selected: Set<String>) -> Set<String> {
        guard let cuisine = normalizedPreference(cuisine) else { return selected }
        if cuisine.caseInsensitiveCompare("Any") == .orderedSame {
            return selected.contains(where: { $0.caseInsensitiveCompare("Any") == .orderedSame })
                ? []
                : ["Any"]
        }

        var updated = selected.filter { $0.caseInsensitiveCompare("Any") != .orderedSame }
        if let existing = updated.first(where: { $0.caseInsensitiveCompare(cuisine) == .orderedSame }) {
            updated.remove(existing)
        } else {
            updated.insert(cuisine)
        }
        return updated
    }

    private static func normalizedPreference(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum MealSuggestionReviewRules {
    public static func safeValue(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    public static func safeTarget(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    public static func normalizedIngredient(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func ingredientUsesPantry(_ ingredient: String, pantryNames: [String]) -> Bool {
        let normalized = normalizedIngredient(ingredient)
        guard normalized.count >= 3 else { return false }

        return normalizedPantryNames(pantryNames).contains { pantryName in
            phrase(normalized, contains: pantryName) || phrase(pantryName, contains: normalized)
        }
    }

    public static func matchedIngredients(
        ingredients: [String],
        pantryNames: [String]
    ) -> [String] {
        ingredients.filter { ingredientUsesPantry($0, pantryNames: pantryNames) }
    }

    public static func optionalIngredients(
        ingredients: [String],
        pantryNames: [String]
    ) -> [String] {
        ingredients.filter { !ingredientUsesPantry($0, pantryNames: pantryNames) }
    }

    public static func fitSummary(calories: Double, remainingCalories: Double?) -> String {
        guard let remaining = safeTarget(remainingCalories) else {
            return "Review the estimate and adjust portions before logging."
        }

        let delta = safeValue(calories) - remaining
        if abs(delta) <= 75 {
            return "Fits your remaining calories closely."
        }
        if delta < 0 {
            return "\(Int(abs(delta).rounded()).formatted()) cal under your remaining target."
        }
        return "\(Int(delta.rounded()).formatted()) cal over your remaining target."
    }

    public static func pantrySummary(ingredients: [String], pantryNames: [String]) -> String {
        guard !ingredients.isEmpty else {
            return "Maia did not return ingredient detail for this estimate."
        }
        guard !normalizedPantryNames(pantryNames).isEmpty else {
            return "No pantry context was used; treat this as a general meal idea."
        }

        let matched = matchedIngredients(ingredients: ingredients, pantryNames: pantryNames)
        let optional = ingredients.count - matched.count
        guard optional > 0 else {
            return "Everything Maia listed appears to match your pantry."
        }
        return "\(matched.count) pantry match\(matched.count == 1 ? "" : "es"), "
            + "\(optional) optional item\(optional == 1 ? "" : "s")."
    }

    public static func substitutionGuidance(
        calories: Double,
        protein: Double,
        carbs: Double,
        ingredients: [String],
        pantryNames: [String],
        remainingCalories: Double?,
        remainingProtein: Double?,
        remainingCarbs: Double?
    ) -> [String] {
        var guidance: [String] = []

        if let target = safeTarget(remainingCalories), safeValue(calories) > target + 100 {
            guidance.append("Reduce calorie-dense extras or use a smaller starch portion.")
        }
        if let target = safeTarget(remainingProtein), target >= 15, safeValue(protein) + 8 < target {
            guidance.append("Add a lean protein anchor before logging.")
        }
        if let target = safeTarget(remainingCarbs), safeValue(carbs) > target + 15 {
            guidance.append("Swap part of the starch for vegetables or fruit.")
        }
        if !pantryNames.isEmpty,
           !optionalIngredients(ingredients: ingredients, pantryNames: pantryNames).isEmpty {
            guidance.append("Swap optional items for similar pantry staples.")
        }

        return guidance.isEmpty
            ? ["Adjust the logged portions if your actual serving changes."]
            : guidance
    }

    public static func instructionSteps(_ instructions: String) -> [String] {
        instructions
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .map {
                $0.replacingOccurrences(
                    of: "^\\s*\\d+[.)]\\s*",
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func normalizedPantryNames(_ names: [String]) -> [String] {
        names
            .map(normalizedIngredient)
            .filter { $0.count >= 3 }
    }

    private static func phrase(_ value: String, contains candidate: String) -> Bool {
        " \(value) ".contains(" \(candidate) ")
    }
}

public enum MealPrepTimerRules {
    public static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 1), 120)
    }

    public static func duration(minutes: Int) -> TimeInterval {
        TimeInterval(clampedMinutes(minutes) * 60)
    }

    public static func remaining(until endDate: Date, now: Date = Date()) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }

    public static func display(_ interval: TimeInterval) -> String {
        let safeInterval = interval.isFinite ? max(0, interval) : 0
        let wholeSeconds = Int(safeInterval.rounded(.up))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

public enum MealPrepQuantityRules {
    public static func displayUnit(_ unit: String, quantity: Double) -> String {
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else { return "" }

        let safeQuantity = quantity.isFinite ? max(0, quantity) : 0
        guard abs(safeQuantity - 1) > 0.0001 else { return trimmedUnit }

        let plurals = [
            "bottle": "bottles",
            "bunch": "bunches",
            "can": "cans",
            "clove": "cloves",
            "cup": "cups",
            "head": "heads",
            "item": "items",
            "ounce": "ounces",
            "package": "packages",
            "piece": "pieces",
            "pinch": "pinches",
            "pound": "pounds",
            "scoop": "scoops",
            "serving": "servings",
            "slice": "slices",
            "sprig": "sprigs",
            "stalk": "stalks",
            "tablespoon": "tablespoons",
            "teaspoon": "teaspoons"
        ]
        return plurals[trimmedUnit.lowercased()] ?? trimmedUnit
    }
}
