import Foundation

public enum MealPlanEditError: LocalizedError {
    case invalid, changed, accountChanged, rescueActive, generationFailed, calendarChanged
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the meal, portions, and destination before saving."
        case .changed: "This plan changed since you opened it. Reload it before making this change."
        case .accountChanged: "Sign in to the same account before saving this plan."
        case .rescueActive: "Review or undo your active week rescue before editing these meals."
        case .generationFailed: "Couldn't create a complete meal draft. Your choices are still here. Try again."
        case .calendarChanged: "This saved plan's calendar date does not match your current time zone. Its original records and pending review are kept. Return to the original time zone to edit it, or create a separately reviewed copy for your current dates."
        }
    }
}

public struct MealPlanChange: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var before: [MealPlanDay]
    public var after: [MealPlanDay]

    public init(title: String, before: [MealPlanDay], after: [MealPlanDay]) {
        id = UUID(); self.title = title; self.before = before; self.after = after
    }

    public var reversed: MealPlanChange { MealPlanChange(title: "Undo \(title.lowercased())", before: after, after: before) }
}

public enum MealPlanEditingRules {
    public static let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    public static func dayID(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func emptyDay(_ date: Date, calendar: Calendar = .current) -> MealPlanDay {
        MealPlanDay(id: dayID(date, calendar: calendar), date: calendar.startOfDay(for: date), meals: [])
    }

    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public static func canonicalSlot(_ label: String) -> String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "snacks" { return "Snack" }
        return mealTypes.first { $0.lowercased() == value } ?? label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sorted(_ meals: [PlannedMeal]) -> [PlannedMeal] {
        meals.enumerated().sorted {
            let left = mealTypes.firstIndex(of: canonicalSlot($0.element.mealType)) ?? 4
            let right = mealTypes.firstIndex(of: canonicalSlot($1.element.mealType)) ?? 4
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    public static func duplicate(_ meal: PlannedMeal) -> PlannedMeal {
        var copy = meal
        copy.id = UUID().uuidString
        copy.foodItem?.id = "plan-food-\(copy.id)"
        // Ordinary copying means a fresh cooking requirement. Sharing leftovers is explicit.
        copy.cookingBatch = nil
        copy.preparedStock = nil
        return copy
    }

    /// Manual recipes retain their measured ingredient foods separately from display names.
    /// Prefer those quantities so a 200 g ingredient does not become "one item" in groceries.
    public static func ingredients(for recipe: Recipe) -> [String] {
        let multiplier: Double
        if (recipe.ingredientBasis ?? recipe.nutritionBasis) == .wholeRecipe,
           let yield = recipe.servings, yield.isFinite, yield > 0 {
            multiplier = 1 / yield
        } else { multiplier = 1 }
        let unresolved = recipe.unresolvedIngredientTexts.map { text -> String in
            guard multiplier != 1, text.trimmingCharacters(in: .whitespaces).first.map({ $0.isNumber || "½⅓⅔¼¾⅛⅜⅝⅞".contains($0) }) == true else { return text }
            let parsed = IngredientParser.parse(text)
            guard parsed.quantity.isFinite, parsed.quantity > 0 else { return text }
            let quantity = (parsed.quantity * multiplier).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
            return "\(quantity) \(parsed.unit == "item" ? "" : parsed.unit + " ")\(parsed.name)"
        }
        let detailed = recipe.resolvedIngredientFoods.map { original -> String in
            let food = original.scalingNutritionAndServing(by: multiplier)
            if food.servingWeight.isFinite, food.servingWeight > 0 {
                return "\(food.servingWeight.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))) g \(food.name)"
            }
            return "\(food.servingSize) \(food.name)"
        }
        // Retain unmatched source ingredients when only part of an import has been linked.
        return unresolved + detailed
    }

    public static func matches(_ actual: MealPlanDay?, expected: MealPlanDay) -> Bool {
        guard let actual else { return expected.meals.isEmpty }
        guard let actualHash = try? PlanFingerprint.make(actual.meals),
              let expectedHash = try? PlanFingerprint.make(expected.meals) else { return false }
        return actualHash == expectedHash
    }

    public static func validate(_ change: MealPlanChange) throws {
        guard (change.before + change.after).allSatisfy({ $0.id == dayID($0.date) }) else { throw MealPlanEditError.calendarChanged }
        let before = change.before.map { dayID($0.date) }
        let after = change.after.map { dayID($0.date) }
        guard !before.isEmpty, before.count <= 14, Set(before).count == before.count,
              Set(after).count == after.count, Set(before) == Set(after) else { throw MealPlanEditError.invalid }
        for day in change.after {
            guard day.meals.count <= 40, Set(day.meals.map(\.id)).count == day.meals.count else { throw MealPlanEditError.invalid }
            for meal in day.meals {
                try MealPlanCookingRules.validate(meal, on: day.date)
                guard !canonicalSlot(meal.mealType).isEmpty, !meal.id.isEmpty,
                      (meal.portionMultiplier ?? 1).isFinite, (0.25...8).contains(meal.portionMultiplier ?? 1) else {
                    throw MealPlanEditError.invalid
                }
                if meal.foodItem != nil {
                    guard let food = meal.plannedFood else { throw MealPlanEditError.invalid }
                    guard !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          [food.calories, food.protein, food.carbs, food.fats].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 100_000 }) else {
                        throw MealPlanEditError.invalid
                    }
                }
            }
        }
        try MealPlanCookingRules.validateChanges(change)
    }

    public static func replacing(_ meal: PlannedMeal, in day: MealPlanDay) throws -> MealPlanChange {
        guard let index = day.meals.firstIndex(where: { $0.id == meal.id }) else { throw MealPlanEditError.changed }
        var updated = day; updated.meals[index] = meal; updated.meals = sorted(updated.meals)
        return MealPlanChange(title: "Meal updated", before: [day], after: [updated])
    }

    public static func mergingDraft(_ draft: [MealPlanDay], into existing: [MealPlanDay], replacingExisting: Bool) -> MealPlanChange {
        var before: [MealPlanDay] = [], after: [MealPlanDay] = []
        for proposed in draft {
            let original = existing.first { dayID($0.date) == dayID(proposed.date) } ?? emptyDay(proposed.date)
            let occupied = Set(original.meals.map { canonicalSlot($0.mealType).lowercased() })
            let additions = proposed.meals.filter { replacingExisting || !occupied.contains(canonicalSlot($0.mealType).lowercased()) }
            guard !additions.isEmpty else { continue }
            var updated = original
            updated.meals = sorted((replacingExisting ? [] : original.meals) + additions.map(duplicate))
            before.append(original); after.append(updated)
        }
        return MealPlanChange(title: "Week planned", before: before, after: after)
    }

    public static func transferring(_ meals: [PlannedMeal], from source: MealPlanDay,
                                    to destinations: [MealPlanDay], moving: Bool) throws -> MealPlanChange {
        guard !moving || meals.allSatisfy({ $0.cookingBatch == nil }) else { throw MealCookingError.linkedBatch }
        guard !meals.isEmpty, !destinations.isEmpty, !moving || destinations.count == 1,
              Set(meals.map(\.id)).isSubset(of: Set(source.meals.map(\.id))),
              destinations.allSatisfy({ dayID($0.date) != dayID(source.date) }),
              Set(destinations.map { dayID($0.date) }).count == destinations.count else { throw MealPlanEditError.invalid }
        var before = destinations
        var after = destinations.map { destination in
            var updated = destination
            updated.meals = sorted(updated.meals + meals.map(duplicate))
            return updated
        }
        if moving {
            before.append(source)
            var updated = source
            let ids = Set(meals.map(\.id)); updated.meals.removeAll { ids.contains($0.id) }
            after.append(updated)
        }
        return MealPlanChange(title: moving ? "Meal moved" : "Meals copied", before: before, after: after)
    }
}

public extension NutritionRepositoryProtocol {
    /// In-memory and test repositories use this default. Firestore overrides it with a transaction.
    func applyMealPlanChange(userID: String, change: MealPlanChange) async throws {
        try MealPlanEditingRules.validate(change)
        for day in change.before {
            let actual = try await fetchMealPlan(userID: userID, dateString: MealPlanEditingRules.dayID(day.date))
            guard MealPlanEditingRules.matches(actual, expected: day) else { throw MealPlanEditError.changed }
        }
        try await saveFullMealPlanBatch(userID: userID, plans: change.after)
    }
}
