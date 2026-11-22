import SwiftUI

@MainActor
public class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    @Published public private(set) var currentRoute: Route = .home
    @Published public private(set) var pendingRoute: Route?
    @Published public private(set) var pendingRequest: AppLinkRequest?
    
    public init() {}
    
    @discardableResult
    public func handle(url: URL) -> Route? {
        guard url.scheme?.lowercased() == "myfitplate" else { return nil }

        let paths = url.pathComponents.filter { $0 != "/" }
        let host = url.host?.lowercased()
        let routeName = host?.isEmpty == false ? host : paths.first?.lowercased()
        let extraPath = host?.isEmpty == false ? paths : Array(paths.dropFirst())
        let route = route(for: routeName)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ownerItems = query.filter { ["user", "userid", "owner"].contains($0.name.lowercased()) }
        let dayItems = query.filter { ["day", "date"].contains($0.name.lowercased()) }
        let objectItems = query.filter { $0.name.lowercased() == "id" }
        let mutates = query.contains { ["action", "delete", "save", "log", "complete"].contains($0.name.lowercased()) }
        let owner = ownerItems.first?.value
        let day = dayItems.first?.value
        let object = extraPath.first ?? objectItems.first?.value
        let validToken: (String?) -> Bool = { value in
            value.map { !$0.isEmpty && $0.count <= 256 && !$0.contains("/") && !$0.contains("\\") } ?? true
        }
        let validDay = day.map { DiaryDayContext(userID: "link-validation", date: Date(), dayKey: $0) != nil } ?? true
        let valid = !mutates && ownerItems.count <= 1 && dayItems.count <= 1 && objectItems.count <= 1 && extraPath.count <= 1
            && !(extraPath.first != nil && !objectItems.isEmpty) && validToken(owner) && validToken(object) && validDay
            && (object == nil || route == .recipes) && (day == nil || [.home, .foodSearch, .trust].contains(route))
        let request = valid ? AppLinkRequest(route: route, ownerID: owner, objectID: object, dayKey: day) : AppLinkRequest(route: .unavailable)
        enqueue(request)
        return request.route
    }

    public func handle(url: URL, appState: AppState) {
        guard let route = handle(url: url) else { return }
        appState.selectedTab = route.selectedTab
    }

    public func takePendingRoute() -> Route? {
        defer { pendingRoute = nil; pendingRequest = nil }
        return pendingRoute
    }

    public func navigate(to route: Route) { enqueue(AppLinkRequest(route: route)) }

    public func handleCookingNotification(identifier: String) {
        let prefix = CookingNotificationRules.identifierPrefix
        guard identifier.hasPrefix(prefix) else { return }
        let hash = identifier.utf8.dropFirst(prefix.utf8.count)
        guard hash.count == 64, hash.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return }
        enqueue(AppLinkRequest(route: .cookingTimer, objectID: identifier))
    }

    public func takePendingRequest() -> AppLinkRequest? {
        defer { pendingRoute = nil; pendingRequest = nil }
        return pendingRequest
    }

    private func enqueue(_ request: AppLinkRequest) {
        currentRoute = request.route
        pendingRequest = request
        pendingRoute = request.route
    }

    private func route(for routeName: String?) -> Route {
        switch routeName {
        case "home", nil:
            return .home
        case "maia", "coach", "coaching":
            return .maia
        case "nutrition", "meal-plan", "meal-planner", "mealplanner", "meals":
            return .nutrition
        case "workouts", "workout", "train", "training":
            return .workouts
        case "reports", "progress":
            return .reports
        case "food-search", "foodsearch", "food", "log-food":
            return .foodSearch
        case "trust", "trust-score", "food-trust":
            return .trust
        case "builder", "fast-food-builder", "restaurant-builder":
            return .builder
        case "runs", "running", "run-history":
            return .runs
        case "training-fuel", "fuel", "recovery-fuel":
            return .trainingFuel
        case "tools", "all-tools": return .tools
        case "food-preferences", "suggestion-preferences": return .foodPreferences
        case "recipes", "recipe": return .recipes
        case "pantry": return .pantry
        case "grocery", "groceries", "grocery-list": return .grocery
        case "buffet", "ayce", "sushi", "kbbq": return .buffet
        case "plate-calculator", "plate-loading", "plate-math": return .plateCalculator
        case "week-rescue", "rescue-my-week": return .weekRescue
        case "meal-experiments", "what-works-for-me": return .mealExperiments
        case "diary", "food-log": return .home
        case "profile":
            return .profile
        case "settings":
            return .settings
        case "community":
            return .unavailable
        default:
            return .unavailable
        }
    }
}
