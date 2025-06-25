import Foundation

struct ParsedIngredient {
    let quantity: Double
    let unit: String
    let name: String
}

struct IngredientParser {
    
    // A mapping of common units and their variations.
    private static let unitMap: [String: [String]] = [
        "cup": ["cups", "c.", "c"],
        "tablespoon": ["tablespoons", "tbsp.", "tbsp", "tbs.", "tbs"],
        "teaspoon": ["teaspoons", "tsp.", "tsp", "t."],
        "ounce": ["ounces", "oz.", "oz"],
        "gram": ["grams", "g.", "g"],
        "pound": ["pounds", "lb.", "lb"],
        "kilogram": ["kilograms", "kg.", "kg"],
        "clove": ["cloves"],
        "pinch": ["pinches"],
        "dash": ["dashes"],
        "can": ["cans"],
        "package": ["packages", "pkg"],
        "slice": ["slices"],
        "whole": ["whole"]
    ]
    
    /// Parses a raw ingredient string (e.g., "1 1/2 cups flour, sifted") into its components.
    static func parse(_ rawString: String) -> ParsedIngredient {
        var mutableString = rawString.lowercased()
        
        // Handle unicode fractions like ½
        mutableString = replaceUnicodeFractions(in: mutableString)
        
        let (quantity, remainingString) = extractQuantity(from: mutableString)
        let (unit, finalName) = extractUnitAndName(from: remainingString.trimmingCharacters(in: .whitespaces))
        
        return ParsedIngredient(quantity: quantity, unit: unit, name: finalName)
    }
    
    /// Replaces common unicode fractions with their decimal equivalents.
    private static func replaceUnicodeFractions(in text: String) -> String {
        let fractionMap = [
            "½": "0.5", "⅓": "0.33", "⅔": "0.67", "¼": "0.25", "¾": "0.75",
            "⅕": "0.2", "⅖": "0.4", "⅗": "0.6", "⅘": "0.8", "⅙": "0.17",
            "⅚": "0.83", "⅛": "0.125", "⅜": "0.375", "⅝": "0.625", "⅞": "0.875"
        ]
        var result = text
        for (fraction, decimal) in fractionMap {
            result = result.replacingOccurrences(of: fraction, with: decimal)
        }
        return result
    }
    
    /// Extracts a numeric quantity from the beginning of the string.
    private static func extractQuantity(from text: String) -> (Double, String) {
        let components = text.split(separator: " ", maxSplits: 1)
        guard let firstComponent = components.first else {
            return (1.0, text)
        }
        
        var quantity = 0.0
        
        // Check for mixed numbers like "1 1/2"
        if let first = Double(firstComponent), components.count > 1 {
            let secondComponent = components[1]
            if let fraction = fractionToDouble(String(secondComponent.split(separator: " ").first ?? "")) {
                quantity = first + fraction
                return (quantity, String(components[1].split(separator: " ").dropFirst().joined(separator: " ")))
            }
        }
        
        // Check for simple fractions or decimals
        if let number = fractionToDouble(String(firstComponent)) {
            quantity = number
            let remaining = components.count > 1 ? String(components[1]) : ""
            return (quantity, remaining)
        }
        
        return (1.0, text)
    }

    /// Converts a string fraction (e.g., "1/2") to a Double.
    private static func fractionToDouble(_ fraction: String) -> Double? {
        if fraction.contains("/") {
            let parts = fraction.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] != 0 {
                return parts[0] / parts[1]
            }
        }
        return Double(fraction)
    }
    
    /// Extracts a unit from the string and returns the remaining text as the ingredient name.
    private static func extractUnitAndName(from text: String) -> (String, String) {
        for (canonicalUnit, variations) in unitMap {
            for variation in [canonicalUnit] + variations {
                let pattern = "\(variation) "
                if text.starts(with: pattern) {
                    let name = String(text.dropFirst(pattern.count)).trimmingCharacters(in: .whitespaces)
                    return (canonicalUnit, cleanIngredientName(name))
                }
            }
        }
        return ("item", cleanIngredientName(text)) // Default unit if none found
    }
    
    /// Cleans up the final ingredient name by removing common descriptors.
    private static func cleanIngredientName(_ name: String) -> String {
        let suffixesToRemove = [", chopped", ", diced", ", minced", ", sifted", ", melted", " of", ", to taste"]
        var cleanedName = name
        for suffix in suffixesToRemove {
            cleanedName = cleanedName.replacingOccurrences(of: suffix, with: "")
        }
        return cleanedName.trimmingCharacters(in: .whitespaces)
    }
}
