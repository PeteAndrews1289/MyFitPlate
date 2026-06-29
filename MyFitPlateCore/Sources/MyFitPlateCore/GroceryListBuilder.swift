import Foundation

public enum GroceryListBuilder {
    public static func makeGroceryList(
        from days: [MealPlanDay],
        unitSystem: GroceryUnitSystem = currentUnitSystem()
    ) -> [GroceryListItem] {
        let ingredients = days
            .flatMap(\.meals)
            .flatMap { $0.ingredients ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !ingredients.isEmpty else { return [] }

        var grouped: [String: GroceryListItem] = [:]

        for ingredient in ingredients {
            let parsed = IngredientLineParser.normalizedIngredient(from: ingredient)
            let key = "\(IngredientNameMatcher.normalized(parsed.name))_\(parsed.unit)"
            let category = IngredientCategoryMapper.groceryCategory(for: parsed.name)

            if var existing = grouped[key] {
                existing.quantity += parsed.quantity
                grouped[key] = existing
            } else {
                grouped[key] = GroceryListItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: category,
                    source: "mealPlan"
                )
            }
        }

        return grouped.values
            .map { applyUnitSystem($0, system: unitSystem) }
            .sorted { first, second in
                if first.category == second.category {
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                }
                return first.category < second.category
            }
    }

    static func mergeKey(for name: String) -> String {
        IngredientNameMatcher.normalized(name)
    }

    static func applyUnitSystem(_ item: GroceryListItem, system: GroceryUnitSystem) -> GroceryListItem {
        var newItem = item

        if system == .imperial {
            if item.unit == "g" {
                let lbs = item.quantity / 453.592
                if lbs >= 1.0 {
                    newItem.quantity = lbs
                    newItem.unit = "lbs"
                } else {
                    newItem.quantity = item.quantity / 28.3495
                    newItem.unit = "oz"
                }
            } else if item.unit == "kg" {
                newItem.quantity = item.quantity * 2.20462
                newItem.unit = "lbs"
            } else if item.unit == "ml" {
                let flOz = item.quantity / 29.5735
                newItem.quantity = flOz
                newItem.unit = "fl oz"
            } else if item.unit == "L" {
                newItem.quantity = item.quantity * 33.814
                newItem.unit = "fl oz"
            }
        } else {
            if item.unit == "oz" {
                newItem.quantity = item.quantity * 28.3495
                newItem.unit = "g"
            } else if item.unit == "lb" || item.unit == "lbs" {
                newItem.quantity = item.quantity * 453.592
                newItem.unit = "g"
            } else if item.unit == "fl oz" {
                newItem.quantity = item.quantity * 29.5735
                newItem.unit = "ml"
            }

            if newItem.unit == "g" && newItem.quantity >= 1000 {
                newItem.quantity = newItem.quantity / 1000
                newItem.unit = "kg"
            }
            if newItem.unit == "ml" && newItem.quantity >= 1000 {
                newItem.quantity = newItem.quantity / 1000
                newItem.unit = "L"
            }
        }

        return newItem
    }

    public static func currentUnitSystem() -> GroceryUnitSystem {
        let rawPreference = UserDefaults.standard.string(forKey: "groceryUnitSystem") ?? "imperial"
        return GroceryUnitSystem(rawValue: rawPreference) ?? .imperial
    }

    public static func parseGroceryList(from text: String) -> [GroceryListItem] {
        var items: [GroceryListItem] = []
        var currentCategory = "Misc"
        let categories = ["Produce", "Protein", "Pantry", "Dairy & Misc", "Carbohydrates"]

        text.split(whereSeparator: \.isNewline).forEach { line in
            let trimmedLine = String(line).trimmingCharacters(in: .whitespaces)
            if let category = categories.first(where: { trimmedLine.hasPrefix($0 + ":") }) {
                currentCategory = category
                return
            }
            if trimmedLine.hasPrefix("-") {
                let itemString = trimmedLine.dropFirst().trimmingCharacters(in: .whitespaces)
                var name = String(itemString); let quantity: Double = 1; let unit = "item"
                if let parenIndex = itemString.lastIndex(of: "(") {
                    name = String(itemString[..<parenIndex]).trimmingCharacters(in: .whitespaces)
                }
                items.append(GroceryListItem(name: name.capitalized, quantity: quantity, unit: unit, category: currentCategory, source: "mealPlan"))
            }
        }
        return items
    }

    public static func isManualGroceryItem(_ item: GroceryListItem) -> Bool {
        if item.source == "manual" || item.source == "barcode" { return true }
        if item.source == nil {
            return item.unit.lowercased() == "item" && item.category == "Misc"
        }
        return false
    }

    public static func mergeGroceryItems(generatedItems: [GroceryListItem], existingItems: [GroceryListItem]) -> [GroceryListItem] {
        let generatedKeys = Set(generatedItems.map { mergeKey(for: $0.name) })
        
        let manualItems = existingItems.filter { item in
            isManualGroceryItem(item) && !generatedKeys.contains(mergeKey(for: item.name))
        }

        let mergedGeneratedItems = generatedItems.map { generatedItem -> GroceryListItem in
            var item = generatedItem
            if let existing = existingItems.first(where: { mergeKey(for: $0.name) == mergeKey(for: generatedItem.name) }) {
                item.isCompleted = existing.isCompleted
            }
            return item
        }

        return mergedGeneratedItems + manualItems
    }
}
