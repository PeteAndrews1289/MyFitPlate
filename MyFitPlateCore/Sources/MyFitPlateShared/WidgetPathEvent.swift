import Foundation

/// A privacy-safe event used by widgets. It intentionally cannot carry event names, IDs,
/// nutrition values, routes, coordinates, or Health samples.
public struct WidgetPathEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case meal
        case strength
        case run
        case activity
        case recovery
    }

    public enum State: String, Codable, CaseIterable, Sendable {
        case completed
        case planned
        case active
    }

    public let kind: Kind
    public let state: State
    public let sequence: Int
    public let startDate: Date
    public let isApproximate: Bool
    public let needsTrustReview: Bool

    public var id: String {
        "\(sequence):\(kind.rawValue):\(state.rawValue):\(startDate.timeIntervalSinceReferenceDate)"
    }

    public init(
        kind: Kind,
        state: State,
        sequence: Int,
        startDate: Date,
        isApproximate: Bool,
        needsTrustReview: Bool
    ) {
        self.kind = kind
        self.state = state
        self.sequence = max(0, sequence)
        self.startDate = startDate
        self.isApproximate = isApproximate
        self.needsTrustReview = needsTrustReview
    }
}
