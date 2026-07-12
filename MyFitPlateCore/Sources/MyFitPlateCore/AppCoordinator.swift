import SwiftUI

@MainActor
public class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    @Published public private(set) var currentRoute: Route = .home
    @Published public private(set) var pendingRoute: Route?
    
    public init() {}
    
    @discardableResult
    public func handle(url: URL) -> Route? {
        guard url.scheme?.lowercased() == "myfitplate" else { return nil }

        let routeName = [
            url.host,
            url.pathComponents.dropFirst().first
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }

        let route = route(for: routeName)
        currentRoute = route
        pendingRoute = route
        return route
    }

    public func handle(url: URL, appState: AppState) {
        guard let route = handle(url: url) else { return }
        appState.selectedTab = route.selectedTab
    }

    public func takePendingRoute() -> Route? {
        defer { pendingRoute = nil }
        return pendingRoute
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
        case "profile":
            return .profile
        case "settings":
            return .settings
        case "community":
            return .community
        default:
            return .home
        }
    }
}
