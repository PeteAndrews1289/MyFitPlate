import Foundation

public enum AppToolCategory: String, CaseIterable, Identifiable, Sendable {
    case food = "Food", training = "Training", personal = "Personal"
    public var id: String { rawValue }
}

/// The delivered tools shared by Home, Train and Maia. Destinations are typed, never
/// arbitrary commands. Opening a tool does not authorize logging, deleting or saving.
public struct AppToolDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let systemImage: String
    public let category: AppToolCategory
    public let route: Route
}

public enum AppToolCatalog {
    public static let tools: [AppToolDescriptor] = [
        .init(id: "food-search", title: "Log food", detail: "Search, scan, or enter a food.", systemImage: "magnifyingglass", category: .food, route: .foodSearch),
        .init(id: "meal-planner", title: "Meal planner", detail: "Plan meals and prepare your week.", systemImage: "calendar", category: .food, route: .nutrition),
        .init(id: "recipes", title: "Recipes", detail: "Review, plan, or log saved recipes.", systemImage: "book.closed", category: .food, route: .recipes),
        .init(id: "pantry", title: "Pantry", detail: "Find ideas for ingredients you have.", systemImage: "cabinet", category: .food, route: .pantry),
        .init(id: "grocery", title: "Groceries", detail: "Shop from your meal plan.", systemImage: "cart", category: .food, route: .grocery),
        .init(id: "buffet", title: "Buffet companion", detail: "Build and review sushi, KBBQ, and buffet plates.", systemImage: "fork.knife", category: .food, route: .buffet),
        .init(id: "restaurant-builder", title: "Restaurant builder", detail: "Build a meal from restaurant options.", systemImage: "menucard", category: .food, route: .builder),
        .init(id: "food-trust", title: "Food data check", detail: "Review estimates and nutrition mismatches.", systemImage: "checkmark.shield", category: .food, route: .trust),
        .init(id: "food-preferences", title: "Food preferences", detail: "Guide meal ideas with foods you enjoy.", systemImage: "slider.horizontal.3", category: .food, route: .foodPreferences),
        .init(id: "training-fuel", title: "Training fuel", detail: "Review food around your next session.", systemImage: "bolt", category: .training, route: .trainingFuel),
        .init(id: "plate-calculator", title: "Plate calculator", detail: "Load both sides of a bar evenly.", systemImage: "scalemass", category: .training, route: .plateCalculator),
        .init(id: "runs", title: "Running", detail: "Review your running history and progress.", systemImage: "figure.run", category: .training, route: .runs),
        .init(id: "week-rescue", title: "Rescue my week", detail: "Review schedule changes before applying them.", systemImage: "calendar.badge.clock", category: .personal, route: .weekRescue),
        .init(id: "meal-experiments", title: "What works for me?", detail: "Compare meals around your training.", systemImage: "chart.xyaxis.line", category: .personal, route: .mealExperiments)
    ]

    public static func tools(in category: AppToolCategory) -> [AppToolDescriptor] { tools.filter { $0.category == category } }
}

/// A read-only navigation request. Object support is deliberately incremental: recipes
/// and civil diary days are validated; unsupported object links show an honest fallback.
public struct AppLinkRequest: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let route: Route
    public let ownerID: String?
    public let objectID: String?
    public let dayKey: String?

    public init(route: Route, ownerID: String? = nil, objectID: String? = nil, dayKey: String? = nil) {
        id = UUID(); self.route = route; self.ownerID = ownerID; self.objectID = objectID; self.dayKey = dayKey
    }

    public func resolvedRoute(currentUserID: String?, availableRecipeIDs: Set<String>) -> Route {
        guard resolvedRoute(currentUserID: currentUserID) != .unavailable else { return .unavailable }
        if let objectID { return route == .recipes && availableRecipeIDs.contains(objectID) ? .recipes : .unavailable }
        return route
    }

    public func resolvedRoute(currentUserID: String?) -> Route {
        ownerID == nil || ownerID == currentUserID ? route : .unavailable
    }

    public func diaryDayContext(for userID: String, timeZone: TimeZone = .current) -> DiaryDayContext? {
        guard resolvedRoute(currentUserID: userID) != .unavailable, let dayKey,
              let validated = DiaryDayContext(userID: userID, date: Date(timeIntervalSince1970: 0), timeZone: timeZone, dayKey: dayKey) else { return nil }
        return DiaryDayContext(userID: userID, date: validated.calendar.startOfDay(for: validated.displayDate), timeZone: timeZone, dayKey: dayKey)
    }
}
