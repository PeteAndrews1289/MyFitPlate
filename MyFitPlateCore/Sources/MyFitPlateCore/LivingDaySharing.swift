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

public enum WidgetPathProjection {
    public static func make(
        from snapshot: LivingDaySnapshot,
        limit: Int = 5
    ) -> [WidgetPathEvent] {
        let usableLimit = max(0, limit)
        guard usableLimit > 0 else { return [] }

        let events = snapshot.events.enumerated().compactMap { index, event in
            makeEvent(event, sequence: index)
        }
        guard events.count > usableLimit else { return events }

        let now = snapshot.currentTime ?? snapshot.generatedAt
        let nextIndex = events.firstIndex { $0.startDate > now } ?? events.count
        let start = min(max(0, nextIndex - 1), events.count - usableLimit)
        return Array(events[start..<(start + usableLimit)])
    }

    private static func makeEvent(
        _ event: LivingDaySnapshot.Event,
        sequence: Int
    ) -> WidgetPathEvent? {
        guard event.state != .skipped else { return nil }

        let kind: WidgetPathEvent.Kind
        switch event.kind {
        case .meal, .plannedMeal: kind = .meal
        case .strength: kind = .strength
        case .run: kind = .run
        case .walk, .activity: kind = .activity
        case .recovery: kind = .recovery
        }

        let state: WidgetPathEvent.State
        switch event.state {
        case .completed: state = .completed
        case .planned: state = .planned
        case .active: state = .active
        case .skipped: return nil
        }

        return WidgetPathEvent(
            kind: kind,
            state: state,
            sequence: sequence,
            startDate: event.startDate,
            isApproximate: event.timing == .approximate,
            needsTrustReview: event.evidence == .review || event.evidence == .correction
        )
    }
}

public struct LivingDayShareSelection: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let budget = LivingDayShareSelection(rawValue: 1 << 0)
    public static let path = LivingDayShareSelection(rawValue: 1 << 1)
    public static let trust = LivingDayShareSelection(rawValue: 1 << 2)
    public static let action = LivingDayShareSelection(rawValue: 1 << 3)
    public static let standard: LivingDayShareSelection = [.budget, .path, .action]
}

public struct LivingDayShareSnapshot: Equatable, Sendable {
    public struct Event: Equatable, Identifiable, Sendable {
        public let kind: WidgetPathEvent.Kind
        public let state: WidgetPathEvent.State
        public let sequence: Int
        public let startDate: Date
        public let isApproximate: Bool
        public let needsTrustReview: Bool

        public var id: String {
            "\(sequence):\(kind.rawValue):\(state.rawValue):\(startDate.timeIntervalSinceReferenceDate)"
        }
    }

    public let date: Date
    public let selection: LivingDayShareSelection
    public let budget: LivingDaySnapshot.Budget?
    public let events: [Event]
    public let nextActionKind: DailyNextAction.Kind?
    public let trustReviewCount: Int?

    public init(
        date: Date,
        selection: LivingDayShareSelection,
        budget: LivingDaySnapshot.Budget?,
        events: [Event],
        nextActionKind: DailyNextAction.Kind?,
        trustReviewCount: Int?
    ) {
        self.date = date
        self.selection = selection
        self.budget = budget
        self.events = events
        self.nextActionKind = nextActionKind
        self.trustReviewCount = trustReviewCount
    }
}

public enum LivingDayShareBuilder {
    public static func make(
        from snapshot: LivingDaySnapshot,
        selection requestedSelection: LivingDayShareSelection
    ) -> LivingDayShareSnapshot {
        let selection = requestedSelection.isEmpty ? LivingDayShareSelection.standard : requestedSelection
        let projectedEvents = WidgetPathProjection.make(from: snapshot, limit: snapshot.events.count)
        let events: [LivingDayShareSnapshot.Event]
        if selection.contains(.path) {
            events = projectedEvents.map {
                LivingDayShareSnapshot.Event(
                    kind: $0.kind,
                    state: $0.state,
                    sequence: $0.sequence,
                    startDate: $0.startDate,
                    isApproximate: $0.isApproximate,
                    needsTrustReview: selection.contains(.trust) && $0.needsTrustReview
                )
            }
        } else {
            events = []
        }

        let trustReviewCount: Int?
        if selection.contains(.trust) {
            trustReviewCount = projectedEvents.filter(\.needsTrustReview).count
        } else {
            trustReviewCount = nil
        }

        return LivingDayShareSnapshot(
            date: snapshot.date,
            selection: selection,
            budget: selection.contains(.budget) ? snapshot.budget : nil,
            events: events,
            nextActionKind: selection.contains(.action) ? snapshot.nextAction.kind : nil,
            trustReviewCount: trustReviewCount
        )
    }
}
