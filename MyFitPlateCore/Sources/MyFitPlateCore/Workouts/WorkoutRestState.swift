import Foundation

/// The session draft owns rest recovery, so another account or workout cannot inherit a timer.
/// A deadline keeps rest on wall-clock time while the app is suspended or relaunched.
public struct WorkoutRestState: Codable, Equatable, Sendable {
    public static let maximumDuration: TimeInterval = 60 * 60

    public let id: UUID
    public let startedAt: Date
    public private(set) var deadline: Date
    public let routineName: String
    public let exerciseID: String?
    public let setID: String?

    public init?(duration: TimeInterval, routineName: String, exerciseID: String? = nil,
                 setID: String? = nil, now: Date = Date()) {
        guard duration.isFinite, duration > 0, duration <= Self.maximumDuration,
              now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        id = UUID()
        startedAt = now
        deadline = now.addingTimeInterval(duration)
        self.routineName = routineName
        self.exerciseID = exerciseID
        self.setID = setID
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        let duration = deadline.timeIntervalSince(startedAt)
        let remaining = deadline.timeIntervalSince(now)
        guard duration.isFinite, duration > 0, duration <= Self.maximumDuration,
              remaining.isFinite, remaining > 0,
              now >= startedAt else { return 0 }
        return min(duration, remaining)
    }

    /// Adjust this rest's existing deadline, retaining its identity and completed-set
    /// association. A finished rest cannot be extended into a new rest accidentally.
    public func adjusted(by adjustment: TimeInterval, at now: Date = Date()) -> WorkoutRestState? {
        guard adjustment.isFinite, remaining(at: now) > 0 else { return nil }
        let adjustedDeadline = min(deadline.addingTimeInterval(adjustment), startedAt.addingTimeInterval(Self.maximumDuration))
        guard adjustedDeadline > now else { return nil }
        var adjusted = self
        adjusted.deadline = adjustedDeadline
        return adjusted
    }
}
