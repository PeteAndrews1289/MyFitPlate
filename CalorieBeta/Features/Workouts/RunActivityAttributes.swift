#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Shared between the app and the LiveActivity extension (dual target membership,
/// same as FastingActivityAttributes). State carries pre-formatted strings so the
/// widget needs no formatting logic or Core dependency.
public struct RunActivityAttributes: ActivityAttributes {
    /// Optional so activities created by earlier builds remain decodable.
    public var recordingID: String?
    public struct ContentState: Codable, Hashable {
        public var startTime: Date
        public var distanceText: String
        public var paceText: String
        /// Frozen elapsed display used while paused (the live timer stops being true).
        public var elapsedText: String
        public var isPaused: Bool
        public var workoutStepText: String?
        public var workoutTargetText: String?
        /// Optional for activities produced by older builds. Missing freshness proof
        /// displays only the frozen elapsed snapshot instead of a live clock.
        public var reportedAt: Date?

        public init(
            startTime: Date,
            distanceText: String,
            paceText: String,
            elapsedText: String,
            isPaused: Bool,
            workoutStepText: String? = nil,
            workoutTargetText: String? = nil,
            reportedAt: Date? = nil
        ) {
            self.startTime = startTime
            self.distanceText = distanceText
            self.paceText = paceText
            self.elapsedText = elapsedText
            self.isPaused = isPaused
            self.workoutStepText = workoutStepText
            self.workoutTargetText = workoutTargetText
            self.reportedAt = reportedAt
        }
    }

    public init(recordingID: String? = nil) { self.recordingID = recordingID }
}
#endif
