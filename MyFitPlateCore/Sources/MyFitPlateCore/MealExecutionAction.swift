import Foundation

/// Presentation choices preserve the distinction between planning, cooking, stock
/// consumption and accepted intake. Selecting an action never implies eating a meal.
public enum MealExecutionAction: Equatable {
    case review, cook, useStock, recordStockUse, log, logged, checkStock, loadingStock

    public var title: String {
        switch self {
        case .review: return "Review meal"
        case .cook: return "Open Cook"
        case .useStock: return "Use cooked portion"
        case .recordStockUse: return "Record stock use"
        case .log: return "Log meal"
        case .logged: return "Logged"
        case .checkStock: return "Review stock"
        case .loadingStock: return "Checking stock…"
        }
    }

    public var isEnabled: Bool { self != .logged && self != .loadingStock }

    public static func resolve(meal: PlannedMeal, date: Date, isLogged: Bool,
                               stock: [PantryItem], stockLoaded: Bool, now: Date = Date(),
                               calendar: Calendar = .current) -> Self {
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else { return .review }
        guard let batchID = meal.preparedStock?.batchID ?? meal.cookingBatch?.id else { return isLogged ? .logged : .log }
        guard stockLoaded else { return .loadingStock }
        guard let item = stock.first(where: { item in
            if let reference = meal.preparedStock { return reference.matches(item, meal: meal) }
            return item.cookedBatch?.id == batchID && item.creationUndone != true
        }) else { return meal.preparedStock == nil && !isLogged ? .cook : .checkStock }
        let consumption = PreparedMealStockRules.consumptionKey(meal: meal, date: date, batchID: batchID)
        if item.recordedPlannedPortions?.contains(consumption) == true { return isLogged ? .logged : .log }
        guard InventoryQuantityRules.usable(item, now: now), item.availableQuantity + 0.000001 >= meal.portions else { return .checkStock }
        return isLogged ? .recordStockUse : .useStock
    }
}
