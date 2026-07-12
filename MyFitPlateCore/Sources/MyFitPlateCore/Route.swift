import Foundation

public enum Route: String, Hashable, Identifiable, Sendable {
    case home
    case maia
    case profile
    case settings
    case nutrition
    case workouts
    case reports
    case community
    case foodSearch
    case trust
    case builder
    case runs
    case trainingFuel

    public var id: String { rawValue }

    public var selectedTab: Int {
        switch self {
        case .home, .profile, .settings, .community, .foodSearch, .trust, .builder, .trainingFuel:
            return 0
        case .maia:
            return 1
        case .workouts, .runs:
            return 2
        case .nutrition:
            return 3
        case .reports:
            return 4
        }
    }
}
