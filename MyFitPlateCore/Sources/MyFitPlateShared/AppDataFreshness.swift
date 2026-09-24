import Foundation

public enum AppDataFreshnessState: CaseIterable, Equatable, Sendable {
    case current
    case aging
    case stale
    case unavailable
}

/// A shared, deterministic interpretation of when synchronized data should still be trusted.
public struct AppDataFreshness: Equatable, Sendable {
    public let state: AppDataFreshnessState
    public let updatedAt: Date?
    public let age: TimeInterval?

    public init(
        updatedAt: Date?,
        now: Date = Date(),
        currentFor: TimeInterval = 15 * 60,
        staleAfter: TimeInterval = 2 * 60 * 60
    ) {
        self.updatedAt = updatedAt

        guard let updatedAt else {
            state = .unavailable
            age = nil
            return
        }

        let age = max(0, now.timeIntervalSince(updatedAt))
        self.age = age

        if age <= currentFor {
            state = .current
        } else if age <= staleAfter {
            state = .aging
        } else {
            state = .stale
        }
    }

    public var shortLabel: String {
        guard let age else { return "Not synced" }

        if age < 90 {
            return "Updated now"
        }
        if age < 60 * 60 {
            return "Updated \(max(1, Int(age / 60)))m ago"
        }
        if age < 24 * 60 * 60 {
            return "Updated \(max(1, Int(age / (60 * 60))))h ago"
        }
        return "Updated \(max(1, Int(age / (24 * 60 * 60))))d ago"
    }

    public var accessibilityLabel: String {
        switch state {
        case .current:
            shortLabel
        case .aging:
            "\(shortLabel). Recent data may still be syncing."
        case .stale:
            "\(shortLabel). Data may be out of date."
        case .unavailable:
            "Not synced. Open MyFitPlate on your phone to update this data."
        }
    }
}
