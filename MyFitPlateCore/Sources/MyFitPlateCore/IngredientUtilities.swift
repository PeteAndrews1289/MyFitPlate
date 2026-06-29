import Foundation

public enum IngredientUnitNormalizer {
    static func normalized(_ unit: String) -> String {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "cup", "cups":
            return "cup"
        case "tablespoon", "tablespoons", "tbsp":
            return "tbsp"
        case "teaspoon", "teaspoons", "tsp":
            return "tsp"
        case "gram", "grams", "g":
            return "g"
        case "kilogram", "kilograms", "kg":
            return "kg"
        case "ounce", "ounces", "oz":
            return "oz"
        case "pound", "pounds", "lb", "lbs":
            return "lb"
        case "milliliter", "milliliters", "ml":
            return "ml"
        case "liter", "liters", "l":
            return "L"
        case "piece", "pieces", "item", "items":
            return "item"
        case "unit", "units":
            return "unit"
        case "clove", "cloves":
            return "clove"
        case "slice", "slices":
            return "slice"
        case "can", "cans":
            return "can"
        default:
            return unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
}

public enum IngredientNameMatcher {
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }

        let singularLeft = singularized(left)
        let singularRight = singularized(right)

        return left == right ||
            left == singularRight ||
            singularLeft == right ||
            singularLeft == singularRight ||
            left.hasSuffix(" \(right)") ||
            right.hasSuffix(" \(left)") ||
            singularLeft.hasSuffix(" \(singularRight)") ||
            singularRight.hasSuffix(" \(singularLeft)")
    }

    static func normalized(_ name: String) -> String {
        let parsed = IngredientParser.parse(name)
        let source = parsed.name.isEmpty ? name : parsed.name
        let ignoredWords: Set<String> = [
            "fresh", "cooked", "raw", "chopped", "diced", "minced",
            "sliced", "shredded", "large", "small", "medium"
        ]

        return source
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignoredWords.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func singularized(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { word -> String in
                let text = String(word)
                if text.count > 4, text.hasSuffix("ies") {
                    return String(text.dropLast(3)) + "y"
                }
                if text.count > 4, text.hasSuffix("oes") {
                    return String(text.dropLast(2))
                }
                if text.count > 3, text.hasSuffix("s") {
                    return String(text.dropLast())
                }
                return text
            }
            .joined(separator: " ")
    }
}

public enum IngredientQuantityResolver {
    static func amountToRemove(parsed: ParsedIngredient, pantryUnit: String) -> Double {
        let parsedUnit = IngredientUnitNormalizer.normalized(parsed.unit)
        let storedUnit = IngredientUnitNormalizer.normalized(pantryUnit)
        let parsedQuantity = parsed.quantity > 0 ? parsed.quantity : 1

        if parsedUnit == storedUnit {
            return parsedQuantity
        }

        if storedUnit == "item" || storedUnit == "unit" {
            return 1
        }

        return parsedQuantity
    }
}

public enum IngredientLineParser {
    static func normalizedIngredient(from raw: String) -> ParsedIngredient {
        let cleanRaw = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[\-•\s]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parsed = IngredientParser.parse(cleanRaw)
        let parsedName = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (parsedName.isEmpty ? cleanRaw : parsedName).capitalized
        let quantity = parsed.quantity > 0 ? parsed.quantity : 1
        let unit = IngredientUnitNormalizer.normalized(parsed.unit)

        return ParsedIngredient(quantity: quantity, unit: unit, name: name, originalString: raw)
    }
}

public enum IngredientCategoryMapper {
    public static func groceryCategory(for ingredient: String) -> String {
        let lower = ingredient.lowercased()

        if ["chicken", "turkey", "beef", "salmon", "tuna", "fish", "shrimp", "steak", "pork", "lamb", "meat"].contains(where: lower.contains) {
            return "Meat & Seafood"
        }

        if ["eggs", "egg", "yogurt", "cheese", "milk", "butter", "cream", "sour cream", "cottage"].contains(where: lower.contains) {
            return "Dairy & Eggs"
        }

        if ["broccoli", "pepper", "onion", "spinach", "lettuce", "carrot", "tomato", "fruit", "berries", "banana", "apple", "vegetable", "garlic", "avocado", "lemon", "lime", "potato"].contains(where: lower.contains) {
            return "Produce"
        }

        if ["rice", "oats", "pasta", "bread", "wrap", "tortilla", "quinoa", "beans", "lentils", "bagel", "bun", "flour"].contains(where: lower.contains) {
            return "Carbohydrates"
        }

        if ["oil", "sauce", "chia", "nuts", "seeds", "peanut", "almond", "honey", "jam", "sugar", "broth"].contains(where: lower.contains) {
            return "Pantry & Oils"
        }

        if ["seasoning", "spice", "cumin", "paprika", "salt", "pepper", "cinnamon", "oregano", "basil", "thyme", "rosemary", "parsley", "cilantro", "ginger"].contains(where: lower.contains) {
            return "Spices & Seasonings"
        }

        return "Misc"
    }

    static func mealPrepCategory(for ingredient: String) -> String {
        switch groceryCategory(for: ingredient) {
        case "Meat & Seafood":
            return "Protein"
        case "Dairy & Eggs":
            let lower = ingredient.lowercased()
            return lower.contains("egg") ? "Protein" : "Dairy"
        case "Carbohydrates":
            return "Carbs"
        case "Produce":
            return "Produce"
        default:
            return "Pantry & Misc"
        }
    }
}
