import Foundation

/// A deliberate change to an unfinished single-goal session. The original plan
/// remains immutable; the receipt records the exact active position and both goals.
public struct RunWorkoutGoalRevision: Codable, Equatable, Identifiable {
    public let id: String
    public let stepID: String
    public let previousGoal: RunWorkoutStep.Goal
    public let revisedGoal: RunWorkoutStep.Goal
    public let activeSeconds: Double
    public let distanceMeters: Double

    public init(id: String, stepID: String, previousGoal: RunWorkoutStep.Goal, revisedGoal: RunWorkoutStep.Goal,
                activeSeconds: Double, distanceMeters: Double) {
        self.id = id
        self.stepID = stepID
        self.previousGoal = previousGoal
        self.revisedGoal = revisedGoal
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
    }

    public static func isSupported(_ goal: RunWorkoutStep.Goal, beyondSeconds: Double, beyondMeters: Double) -> Bool {
        switch goal {
        case .duration(let seconds): return seconds.isFinite && seconds > beyondSeconds && seconds <= 86_400
        case .distance(let meters): return meters.isFinite && meters > beyondMeters && meters <= 100_000
        case .open: return false
        }
    }

    public static func sameKind(_ first: RunWorkoutStep.Goal, _ second: RunWorkoutStep.Goal) -> Bool {
        switch (first, second) {
        case (.duration, .duration), (.distance, .distance): return true
        default: return false
        }
    }
}
