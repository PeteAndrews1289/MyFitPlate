import SwiftUI

@MainActor
public class AppCoordinator: ObservableObject {
    public static let shared = AppCoordinator()
    @Published public var currentRoute: Route = .home
    
    public init() {}
    
    public func handle(url: URL, appState: AppState) {
        guard url.scheme?.lowercased() == "myfitplate" else { return }

        let routeName = [
            url.host,
            url.pathComponents.dropFirst().first
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .first { !$0.isEmpty }

        switch routeName {
        case "home", nil:
            navigate(to: .home, appState: appState)
        case "nutrition", "meal-planner", "mealplanner", "meals":
            navigate(to: .nutrition, appState: appState)
        case "workouts", "workout":
            navigate(to: .workouts, appState: appState)
        case "profile":
            navigate(to: .profile, appState: appState)
        case "settings":
            navigate(to: .settings, appState: appState)
        case "community":
            navigate(to: .community, appState: appState)
        default:
            navigate(to: .home, appState: appState)
        }
    }

    private func navigate(to route: Route, appState: AppState) {
        currentRoute = route

        switch route {
        case .home, .profile, .settings, .community:
            appState.selectedTab = 0
        case .nutrition:
            appState.selectedTab = 3
        case .workouts:
            appState.selectedTab = 2
        }
    }
}
