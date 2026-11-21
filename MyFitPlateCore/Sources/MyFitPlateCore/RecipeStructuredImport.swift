import Foundation
import SwiftSoup

/// Exact published recipe text is a review draft. A web page's yield does not establish
/// whether its nutrition describes a serving or a batch.
public enum RecipeStructuredImport {
    public static func drafts(html: String, sourceURL: String) throws -> [Recipe] {
        let document = try SwiftSoup.parse(html)
        var objects: [[String: Any]] = []
        func walk(_ value: Any, depth: Int = 0) {
            guard depth < 20, objects.count < 30 else { return }
            if let array = value as? [Any] { array.forEach { walk($0, depth: depth + 1) } }
            guard let object = value as? [String: Any] else { return }
            let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
            if types.contains(where: { $0 == "Recipe" || $0.hasSuffix("/Recipe") }) { objects.append(object) }
            for key in ["@graph", "mainEntity", "itemListElement", "item"] {
                if let child = object[key] { walk(child, depth: depth + 1) }
            }
        }
        for script in try document.select("script[type=application/ld+json]").array() {
            let data = try script.data().data(using: .utf8) ?? Data()
            if let value = try? JSONSerialization.jsonObject(with: data) { walk(value) }
        }
        var seen = Set<String>()
        return objects.compactMap { object in
            guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let ingredients = object["recipeIngredient"] as? [String], !ingredients.isEmpty,
                  ingredients.count <= 200 else { return nil }
            func steps(_ value: Any?) -> [String] {
                if let text = value as? String { return [text] }
                if let array = value as? [Any] { return array.flatMap { steps($0) } }
                if let object = value as? [String: Any] {
                    if let text = object["text"] as? String { return [text] }
                    return steps(object["itemListElement"])
                }
                return []
            }
            let instructions = steps(object["recipeInstructions"])
            guard !instructions.isEmpty, seen.insert(name + ingredients.joined()).inserted else { return nil }
            let published = object["nutrition"] as? [String: Any] ?? [:]
            func number(_ value: Any?, kind: String? = nil) -> Double? {
                if let n = value as? NSNumber, n.doubleValue.isFinite, n.doubleValue >= 0 { return n.doubleValue }
                guard let text = value as? String,
                      let regex = try? NSRegularExpression(pattern: #"^\s*((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)\s*([a-zA-Zµμ]*)"#),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let amountRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text),
                      let fullRange = Range(match.range, in: text),
                      let amount = Double(text[amountRange].replacingOccurrences(of: ",", with: "")), amount.isFinite else { return nil }
                let remaining = text[fullRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if let next = remaining.first, next.isNumber || ",./–−-".contains(next) { return nil }
                let unit = text[unitRange].lowercased()
                if kind == "energy" {
                    if unit == "kj" { return amount / 4.184 }
                    guard ["", "kcal", "cal", "cals", "calorie", "calories"].contains(unit) else { return nil }
                } else if kind == "macro" {
                    switch unit {
                    case "", "g", "gram", "grams": break
                    case "mg", "milligram", "milligrams": return amount / 1_000
                    case "kg", "kilogram", "kilograms": return amount * 1_000
                    case "ug", "µg", "μg": return amount / 1_000_000
                    default: return nil
                    }
                }
                return amount
            }
            let yieldText = (object["recipeYield"] as? String) ?? (object["recipeYield"] as? [String])?.first
            let yield = number(object["recipeYield"]) ?? number(yieldText)
            var recipe = Recipe(name: String(name.prefix(200)), ingredients: ingredients, instructions: instructions,
                nutrition: Nutrition(calories: number(published["calories"], kind: "energy") ?? 0,
                    protein: number(published["proteinContent"], kind: "macro") ?? 0, carbs: number(published["carbohydrateContent"], kind: "macro") ?? 0,
                    fats: number(published["fatContent"], kind: "macro") ?? 0),
                servings: yield.flatMap { (0.01...100).contains($0) ? $0 : nil },
                nutritionNeedsReview: true, ingredientBasis: .wholeRecipe)
            let sourceText = ([name, "Published yield: " + (yieldText ?? "not stated")]
                + ingredients + instructions + ["Published nutrition: \(published)"]).joined(separator: "\n")
            recipe.importProvenance = RecipeImportProvenance(kind: .structuredURL,
                sourceURL: sourceURL, originalText: String(sourceText.prefix(50_000)))
            let required = [("Calories", "calories"), ("Protein", "proteinContent"), ("Carbohydrate", "carbohydrateContent"), ("Fat", "fatContent")]
            recipe.importProvenance?.missingNutritionFields = required.compactMap { number(published[$0.1], kind: $0.1 == "calories" ? "energy" : "macro") == nil ? $0.0 : nil }
            return recipe
        }
    }
}
