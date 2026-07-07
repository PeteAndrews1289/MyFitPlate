#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Shared between the app and the LiveActivity extension (dual target membership,
/// same as FastingActivityAttributes). State carries pre-formatted strings so the
/// widget needs no formatting logic or Core dependency.
public struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startTime: Date
        public var distanceText: String
        public var paceText: String
        /// Frozen elapsed display used while paused (the live timer stops being true).
        public var elapsedText: String
        public var isPaused: Bool
        public var workoutStepText: String?
        public var workoutTargetText: String?

        public init(
            startTime: Date,
            distanceText: String,
            paceText: String,
            elapsedText: String,
            isPaused: Bool,
            workoutStepText: String? = nil,
            workoutTargetText: String? = nil
        ) {
            self.startTime = startTime
            self.distanceText = distanceText
            self.paceText = paceText
            self.elapsedText = elapsedText
            self.isPaused = isPaused
            self.workoutStepText = workoutStepText
            self.workoutTargetText = workoutTargetText
        }
    }

    public init() {}
}
#endif
