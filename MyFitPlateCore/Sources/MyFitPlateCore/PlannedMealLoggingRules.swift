import CryptoKit
import Foundation

public enum PlannedMealLoggingRules {
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
