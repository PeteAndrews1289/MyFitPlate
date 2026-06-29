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
}
