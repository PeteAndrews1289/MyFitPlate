import Foundation

public enum GroceryListBuilder {
    public static let standardCategories = [
        "Produce",
        "Meat & Seafood",
        "Dairy & Eggs",
        "Carbohydrates",
        "Pantry & Oils",
        "Spices & Seasonings",
        "Bakery",
        "Misc"
    ]

    public static func makeGroceryList(
        from days: [MealPlanDay],
        starting sourcePlanStart: Date? = nil,
        unitSystem: GroceryUnitSystem = currentUnitSystem(),
        cookedBatchIDs: Set<String> = []
    ) -> [GroceryListItem] {
        let ingredients = MealPlanCookingRules.requirements(from: days, starting: sourcePlanStart)
            .filter { requirement in !cookedBatchIDs.contains(where: { requirement.id == "batch-\($0)" }) }
            .flatMap(\.ingredients)
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !ingredients.isEmpty else { return [] }

        var grouped: [String: GroceryListItem] = [:]

        for parsed in ingredients {
            let known = InventoryQuantityRules.explicitLeadingAmount(parsed.originalString) != nil
            let key = requirementIdentity(name: parsed.name, unit: parsed.unit) + (known ? "" : "|unknown")
            let category = IngredientCategoryMapper.groceryCategory(for: parsed.name)

            if var existing = grouped[key] {
                existing.quantity += InventoryQuantityRules.convert(parsed.quantity, from: parsed.unit, to: existing.unit) ?? parsed.quantity
                grouped[key] = existing
            } else {
                var item = GroceryListItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: category,
                    source: "mealPlan",
                    sourcePlanStart: sourcePlanStart ?? days.map(\.date).min()
                )
                item.requirementKey = key
                item.quantityUnknown = known ? nil : true
                grouped[key] = item
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
        IngredientNameMatcher.canonical(name)
    }

    public static func applyUnitSystem(_ item: GroceryListItem, system: GroceryUnitSystem) -> GroceryListItem {
        var newItem = item
        let normalized = IngredientUnitNormalizer.normalized(item.unit)
        if system == .imperial {
            if normalized == "g" || normalized == "kg" {
                let pounds = InventoryQuantityRules.convert(item.quantity, from: item.unit, to: "lb") ?? 0
                newItem.unit = pounds >= 1 ? "lbs" : "oz"
            } else if normalized == "ml" || normalized == "L" { newItem.unit = "fl oz" }
        } else {
            if normalized == "oz" || normalized == "lb" { newItem.unit = "g" } else if normalized == "fl oz" { newItem.unit = "ml" }
            let quantity = InventoryQuantityRules.convert(item.quantity, from: item.unit, to: newItem.unit) ?? item.quantity
            if newItem.unit == "g", quantity >= 1_000 { newItem.unit = "kg" }
            if newItem.unit == "ml", quantity >= 1_000 { newItem.unit = "L" }
        }
        newItem.quantity = InventoryQuantityRules.convert(item.quantity, from: item.unit, to: newItem.unit) ?? item.quantity

        newItem.purchasedQuantity = item.purchasedQuantity.flatMap { InventoryQuantityRules.convert($0, from: item.unit, to: newItem.unit) }
        newItem.transferredToPantryQuantity = item.transferredToPantryQuantity.flatMap { InventoryQuantityRules.convert($0, from: item.unit, to: newItem.unit) }
        return newItem
    }

    public static func normalizedCategory(_ category: String) -> String {
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "produce": "Produce"
        case "protein", "meat", "meat & seafood": "Meat & Seafood"
        case "dairy", "dairy & eggs", "dairy & misc": "Dairy & Eggs"
        case "carbohydrates", "carbs", "grains": "Carbohydrates"
        case "pantry", "pantry & oils": "Pantry & Oils"
        case "spices", "seasonings", "spices & seasonings": "Spices & Seasonings"
        case "bakery": "Bakery"
        case "misc", "miscellaneous", "": "Misc"
        default: category.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func currentUnitSystem(userID: String? = nil) -> GroceryUnitSystem {
        let scoped = userID.flatMap { AccountScopedStorageKey.make(prefix: "groceryUnitSystem", userID: $0) }
        let rawPreference = scoped.flatMap { UserDefaults.standard.string(forKey: $0) }
            ?? UserDefaults.standard.string(forKey: "groceryUnitSystem") ?? "imperial"
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
        if item.source == "manual" || item.source == "barcode" || item.source == "retainedPurchase" { return true }
        if item.source == nil {
            return item.unit.lowercased() == "item" && item.category == "Misc"
        }
        return false
    }

    public static func mergeGroceryItems(generatedItems: [GroceryListItem], existingItems: [GroceryListItem], preservingChoicesOutside start: Date? = nil) -> [GroceryListItem] {
        let plannedByKey = Dictionary(grouping: existingItems.filter {
            $0.source == "mealPlan" || $0.source == "retainedPurchase"
        }) { item in
            item.requirementKey ?? requirementIdentity(name: item.name, unit: item.unit)
        }

        let mergedGeneratedItems = generatedItems.map { generatedItem -> GroceryListItem in
            var item = generatedItem
            let key = item.requirementKey ?? requirementIdentity(name: item.name, unit: item.unit)
            if let existing = priorItem(for: item, candidates: plannedByKey[key] ?? []) {
                let requiredQuantity = InventoryQuantityRules.convert(item.quantity, from: item.unit, to: existing.unit)
                let coversRequirement = requiredQuantity.map { amount in
                    amount.isFinite && existing.quantity.isFinite && existing.quantity + 0.0001 >= amount
                } ?? false
                item.isCompleted = existing.isCompleted && coversRequirement
                if generatedItem.source == "mealPlan" {
                    item.id = existing.id
                    item.revisionID = existing.revisionID
                    // Display preferences do not rewrite the accepted measurement basis.
                    if item.quantityUnknown == true, existing.quantityUnknown == false {
                        // A reviewed shopping amount is an explicit user override, not
                        // a claim that the recipe's unresolved ingredient became measured.
                        item.quantity = existing.quantity; item.unit = existing.unit; item.quantityUnknown = false
                    } else if let amount = requiredQuantity, amount.isFinite {
                        item.quantity = abs(existing.quantity - amount) < 0.000000001 ? existing.quantity : amount
                        item.unit = existing.unit
                    }
                    if existing.quantityUnknown == false { item.quantityUnknown = false }
                    item.name = existing.name; item.category = existing.category
                    item.barcode = existing.barcode ?? item.barcode
                    item.productSnapshot = existing.productSnapshot
                    if let override = existing.quantityOverride {
                        item = GroceryOverrideRules.applying(override, generated: item)
                    }
                    item.purchasedQuantity = existing.purchasedQuantity.flatMap { InventoryQuantityRules.convert($0, from: existing.unit, to: item.unit) }
                    item.transferredToPantryQuantity = existing.transferredToPantryQuantity.flatMap { InventoryQuantityRules.convert($0, from: existing.unit, to: item.unit) }
                    var unconverted = existing.unconvertedPurchases ?? []
                    if let bought = existing.purchasedQuantity, item.purchasedQuantity == nil, bought > 0 {
                        let recorded = GroceryPurchaseAmount(quantity: bought, unit: existing.unit, transferredToPantryQuantity: existing.transferredToPantryQuantity)
                        if !unconverted.contains(recorded) { unconverted.append(recorded) }
                    }
                    item.unconvertedPurchases = unconverted.filter { purchase in
                        guard let bought = InventoryQuantityRules.convert(purchase.quantity, from: purchase.unit, to: item.unit) else { return true }
                        item.purchasedQuantity = (item.purchasedQuantity ?? 0) + bought
                        if let transferred = purchase.transferredToPantryQuantity.flatMap({ InventoryQuantityRules.convert($0, from: purchase.unit, to: item.unit) }) {
                            item.transferredToPantryQuantity = (item.transferredToPantryQuantity ?? 0) + transferred
                        }
                        return false
                    }
                    if item.unconvertedPurchases?.isEmpty == true { item.unconvertedPurchases = nil }
                    item.skippedForPlan = existing.skippedForPlan.map { skipped in
                        skipped && item.quantityOverride?.requiresReview != true && coversRequirement
                    }
                    if let bought = item.purchasedQuantity, item.quantityUnknown != true { item.isCompleted = bought + 0.0001 >= item.quantity }
                }
            }
            return item
        }

        let currentIDs = Set(mergedGeneratedItems.map(\.id))
        let manualItems = existingItems.filter { isManualGroceryItem($0) && !currentIDs.contains($0.id) }
        let retainedPurchases = existingItems.filter {
            $0.source == "mealPlan" && $0.savedShoppingDay == nil && !currentIDs.contains($0.id) && hasPurchase($0)
        }.map { old -> GroceryListItem in var retained = old; retained.source = "retainedPurchase"; return retained }
        let selectedDay = start.map { MealPlanEditingRules.dayID($0) }
        let savedChoices = existingItems.compactMap { existing -> GroceryListItem? in
            guard let selectedDay, !currentIDs.contains(existing.id), existing.source == "mealPlan", !hasPurchase(existing),
                  hasReviewedChoice(existing), let day = existing.savedShoppingDay ?? existing.sourcePlanStart.map({ MealPlanEditingRules.dayID($0) }),
                  day != selectedDay else { return nil }
            var saved = existing
            saved.savedShoppingDay = day
            return saved
        }
        return mergedGeneratedItems + manualItems + retainedPurchases + savedChoices
    }

    private static func priorItem(for need: GroceryListItem, candidates: [GroceryListItem]) -> GroceryListItem? {
        let period = candidates.filter { item in
            if let savedDay = item.savedShoppingDay { return need.sourcePlanStart.map { MealPlanEditingRules.dayID($0) } == savedDay }
            switch (item.sourcePlanStart, need.sourcePlanStart) {
            case let (old?, new?): return Calendar.current.isDate(old, inSameDayAs: new)
            case (nil, nil): return item.source == "mealPlan"
            default: return false
            }
        }
        let active = period.first { $0.source == "mealPlan" && $0.savedShoppingDay == nil }
        if let active, hasPurchase(active) || hasReviewedChoice(active) {
            return active
        }
        // Earlier clients could leave an untouched regenerated row beside the original receipt.
        return period.first { $0.source == "retainedPurchase" } ?? period.first { $0.savedShoppingDay != nil } ?? active
    }

    private static func hasReviewedChoice(_ item: GroceryListItem) -> Bool {
        item.quantityOverride != nil || item.skippedForPlan == true || item.productSnapshot != nil || item.barcode != nil || item.quantityUnknown == false
    }

    private static func hasPurchase(_ item: GroceryListItem) -> Bool {
        item.isCompleted || (item.purchasedQuantity ?? 0) > 0 || (item.transferredToPantryQuantity ?? 0) > 0
            || item.unconvertedPurchases?.isEmpty == false
    }

    static func requirementIdentity(name: String, unit: String) -> String {
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let preparation = words.contains("cooked") ? "cooked" : words.contains("raw") ? "raw" : "unspecified"
        let dimension = InventoryQuantityRules.convert(1, from: unit, to: "g") != nil ? "mass"
            : InventoryQuantityRules.convert(1, from: unit, to: "ml") != nil ? "volume" : IngredientUnitNormalizer.normalized(unit)
        return "\(IngredientNameMatcher.canonical(name))|\(preparation)|\(dimension)"
    }
}
