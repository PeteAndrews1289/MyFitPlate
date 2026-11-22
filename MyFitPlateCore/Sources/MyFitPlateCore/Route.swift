import Foundation

public enum Route: String, Hashable, Identifiable, Sendable {
    case home
    case maia
    case profile
    case settings
    case nutrition
    case cookingTimer
    case workouts
    case reports
    case community
    case foodSearch
    case trust
    case builder
    case runs
    case trainingFuel
    case tools
    case foodPreferences
    case recipes
    case pantry
    case grocery
    case buffet
    case plateCalculator
    case weekRescue
    case mealExperiments
    case unavailable

    public var id: String { rawValue }

    public var selectedTab: Int {
        switch self {
        case .home, .profile, .settings, .community, .foodSearch, .trust, .builder, .trainingFuel, .unavailable,
             .tools, .foodPreferences, .recipes, .pantry, .grocery, .buffet:
            return 0
        case .maia, .mealExperiments:
            return 1
        case .workouts, .runs, .plateCalculator, .weekRescue:
            return 2
        case .nutrition, .cookingTimer:
            return 3
        case .reports:
            return 4
        }
    }
}
