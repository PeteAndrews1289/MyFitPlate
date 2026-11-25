import Foundation

public struct RunScheduledContext: Codable, Equatable {
    public let commitmentID: String
    public let plannedDay: TrainingCalendarDay
    public let blockID: String?
    public let slotID: String?
    public let revisionID: String?
    public let plan: RunWorkoutPlan
    public init(commitment: TrainingRunCommitment) {
        commitmentID = commitment.id; plannedDay = commitment.day
        blockID = commitment.blockID; slotID = commitment.slotID; revisionID = commitment.revisionID; plan = commitment.plan
    }
}

public enum RunBlockAbility: String, Codable, CaseIterable, Identifiable {
    case starting, returning, established
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .starting: "Run/walk foundation"
        case .returning: "Returning to running"
        case .established: "Running regularly"
        }
    }
}
public enum RunBlockGoal: String, Codable, CaseIterable, Identifiable {
    case consistency, fiveKilometers, tenKilometers
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .consistency: "Consistent running"
        case .fiveKilometers: "5K foundation"
        case .tenKilometers: "10K foundation"
        }
    }
}
public struct RunTrainingBlockBrief: Codable, Equatable {
    public var start: TrainingCalendarDay
    public var weeks: Int
    public var ability: RunBlockAbility
    public var goal: RunBlockGoal
    public var recentWeeklyMinutes: Double
    public var recentLongestMinutes: Double
    /// Calendar weekday numbers (Sunday = 1), independent of firstWeekday display preference.
    public var weekdays: [Int]
    public var preferredLongWeekday: Int
    public var includeQuality: Bool
    public var targetDay: TrainingCalendarDay?
    public init(start: Date = Date(), weeks: Int = 4, ability: RunBlockAbility = .returning, goal: RunBlockGoal = .consistency,
                recentWeeklyMinutes: Double = 60, recentLongestMinutes: Double = 25,
                weekdays: [Int] = [2, 4, 7], preferredLongWeekday: Int = 7, includeQuality: Bool = false) {
        self.start = TrainingCalendarDay(start); self.weeks = weeks; self.ability = ability; self.goal = goal
        self.recentWeeklyMinutes = recentWeeklyMinutes; self.recentLongestMinutes = recentLongestMinutes
        self.weekdays = weekdays; self.preferredLongWeekday = preferredLongWeekday; self.includeQuality = includeQuality
    }
}
public enum RunBlockRole: String, Codable {
    case easy, long, quality, runWalk, recovery
    public var title: String {
        switch self {
        case .easy: "Easy run"
        case .long: "Long easy run"
        case .quality: "Controlled intervals"
        case .runWalk: "Run/walk"
        case .recovery: "Recovery run"
        }
    }
}
public struct RunBlockOutcome: Codable, Equatable {
    public enum State: String, Codable { case started, recorded, skipped, abandoned }
    public var state: State
    public var recordingID: String?
    public var runID: String?
    public var acceptedAt: Date
    public var actualStart: Date?
    public var movingSeconds: Double?
    public var distanceMeters: Double?
    public var prescription: RunScheduledContext?
}
public struct RunTrainingBlockSlot: Codable, Identifiable, Equatable {
    public var id: String
    public var revisionID: String
    public var weekIndex: Int
    public var day: TrainingCalendarDay
    public var role: RunBlockRole
    public var plan: RunWorkoutPlan
    public var outcome: RunBlockOutcome?
    public var plannedMinutes: Double { plan.estimatedDurationSeconds / 60 }
    public var canChange: Bool { outcome == nil }
}
public struct RunTrainingBlock: Codable, Identifiable, Equatable {
    public let schemaVersion: Int
    public var id: String
    public var revisionID: String
    public var createdAt: Date
    public var brief: RunTrainingBlockBrief
    public var slots: [RunTrainingBlockSlot]
    public var weeklyMinuteCeilings: [Double]
    public var notes: [String]
    public var archived: Bool
    public init(id: String = UUID().uuidString, brief: RunTrainingBlockBrief, slots: [RunTrainingBlockSlot],
                ceilings: [Double], notes: [String], now: Date = Date()) {
        schemaVersion = 1; self.id = id; revisionID = UUID().uuidString; createdAt = now; self.brief = brief
        self.slots = slots; weeklyMinuteCeilings = ceilings; self.notes = notes; archived = false
    }
    public func commitment(for slot: RunTrainingBlockSlot) -> TrainingRunCommitment? {
        guard !archived, slot.outcome == nil, let date = slot.day.date() else { return nil }
        var value = TrainingRunCommitment(id: slot.id, date: date, plan: slot.plan)
        value.blockID = id; value.slotID = slot.id; value.revisionID = slot.revisionID
        return value
    }
}
public struct RunTrainingBlockChange: Codable, Identifiable {
    public var id: String
    public var ownerID: String
    public var before: RunTrainingBlock?
    public var after: RunTrainingBlock
    public var explanation: String
    public init(ownerID: String, before: RunTrainingBlock?, after: RunTrainingBlock, explanation: String) {
        id = UUID().uuidString; self.ownerID = ownerID; self.before = before; self.after = after; self.explanation = explanation
    }
}
public enum RunTrainingBlockError: LocalizedError {
    case invalid, changed, accountChanged, completed, conflict(String), overload
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review your running baseline, available days and plan dates."
        case .changed: "This running plan changed. Your review is kept; reopen the current plan before applying changes."
        case .accountChanged: "Sign in to the same account to use this running plan."
        case .completed: "This run has started or has an accepted outcome. Its original prescription stays intact."
        case .conflict(let message): message
        case .overload: "That move would increase a week's reviewed workload. Shorten or skip a future session before moving it; missed runs are not automatically added back."
        }
    }
}
