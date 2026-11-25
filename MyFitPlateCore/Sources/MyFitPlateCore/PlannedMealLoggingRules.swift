import CryptoKit
import Foundation

public enum PlannedMealLoggingRules {
    /// Use a measured cooked yield when available. Older entries can describe the
    /// same portion as a structured quantity or a single printed serving.
    public static func editablePortion(of food: FoodItem) -> (amount: Double, unit: String) {
        if let snapshot = food.recipePortionSnapshot {
            if let grams = snapshot.cookedGrams, grams.isFinite, grams > 0 { return (grams, "g") }
            return (snapshot.selection.amount, snapshot.selection.unit.quantityUnit)
        }
        let parsed = ServingNutritionCalculator.parseQuantity(from: food.servingSize)
        let count = food.quantityValue ?? parsed.quantity
        let stored = food.servingUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usePrinted = stored?.isEmpty != false ||
            (stored?.lowercased() == "serving" && parsed.quantity == count && !parsed.baseDescription.isEmpty)
        let description = usePrinted ? parsed.baseDescription : (stored ?? "")
        let parts = description.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        if parts.count == 2, let number = Double(parts[0]), number.isFinite, number > 0 {
            let baseCount = usePrinted && !food.servingSize.contains(" x ") ? 1 : count
            return (baseCount * number, String(parts[1]))
        }
        return (count, description.isEmpty ? "serving" : description)
    }

    public static func actualPortion(of food: FoodItem, amount: Double) -> FoodItem? {
        let portion = editablePortion(of: food)
        guard amount.isFinite, amount > 0, portion.amount.isFinite, portion.amount > 0 else { return nil }
        if amount == portion.amount { return food }
        guard food.recipePortionSnapshot.map({ $0.schemaVersion == 1 }) ?? true,
              var result = FoodRepeatRules.adjusting(food, by: amount / portion.amount) else { return nil }
        let components = result.mealComposition?.components ?? [result]
        do {
            try SavedMealComposition(name: result.name, components: components).validate()
        } catch {
            return nil
        }
        result.quantityValue = amount
        result.servingUnit = portion.unit
        result.servingSize = amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.significantDigits(1...16))) + " x " + portion.unit
        return result
    }

    public static func isLogged(_ meal: PlannedMeal, date: Date, loggedFoodIDs: Set<String>, calendar: Calendar = .current) -> Bool {
        loggedFoodIDs.contains(entryID(for: meal, date: date, calendar: calendar))
    }

    public static func entryID(for meal: PlannedMeal, date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let identity = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0):\(meal.id)"
        return "planned-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func food(for meal: PlannedMeal, date: Date, now: Date = Date(), calendar: Calendar = .current) -> FoodItem? {
        guard var food = meal.plannedFood else { return nil }
        food.id = entryID(for: meal, date: date, calendar: calendar)
        food.timestamp = now
        return food
    }
}
