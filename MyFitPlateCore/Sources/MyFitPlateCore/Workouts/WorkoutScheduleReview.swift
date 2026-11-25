import Foundation

/// Calendar components are commitments, not instants; travel does not move them to another day.
public struct TrainingCalendarDay: Codable, Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 2000; month = parts.month ?? 1; day = parts.day ?? 1
    }
    public func date(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
public struct WorkoutScheduleException: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var slotIndex: Int
    public var originalDay: TrainingCalendarDay
    public var proposedDay: TrainingCalendarDay
    public var revision: Int
}
public struct TrainingRunCommitment: Codable, Identifiable {
    public var id: String
    public var day: TrainingCalendarDay
    public var plan: RunWorkoutPlan
    public var blockID: String?
    public var slotID: String?
    public var revisionID: String?
    public init(id: String = UUID().uuidString, date: Date, plan: RunWorkoutPlan, calendar: Calendar = .current) {
        self.id = id; day = TrainingCalendarDay(date, calendar: calendar); self.plan = plan
    }
}
@MainActor public final class TrainingRunCommitmentStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func entries(userID: String) throws -> [TrainingRunCommitment] {
        guard !userID.isEmpty, DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        let independent = try store.load([TrainingRunCommitment].self, userID: userID, scope: "training-run-commitments-v1")?.value ?? []
        return independent + (try RunTrainingBlockStore(store: store).commitments(userID: userID))
    }
    public func save(_ value: TrainingRunCommitment, userID: String) throws {
        var values = try entries(userID: userID)
        guard value.blockID == nil, !values.contains(where: { $0.id == value.id && $0.blockID != nil }) else {
            throw RunTrainingBlockError.conflict("Review this session in its running plan; its block and outcomes stay linked.")
        }
        values.removeAll { $0.blockID != nil }
        guard value.day.date() != nil, !value.plan.steps.isEmpty else { throw WorkoutBlockError.invalid }
        values.removeAll { $0.id == value.id }; values.append(value)
        try store.save(values, userID: userID, scope: "training-run-commitments-v1")
    }
    public func remove(id: String, userID: String) throws {
        let current = try entries(userID: userID)
        guard !current.contains(where: { $0.id == id && $0.blockID != nil }) else {
            throw RunTrainingBlockError.conflict("Review Skip in this run's training plan instead of deleting its calendar identity.")
        }
        let values = current.filter { $0.id != id && $0.blockID == nil }
        try store.save(values, userID: userID, scope: "training-run-commitments-v1")
    }
}
public struct WorkoutScheduleMoveReview: Identifiable {
    public let id: String
    public let slotIndex: Int
    public let oldDate: Date
    public let newDate: Date
    public let collisions: [String]
    fileprivate let basis: String
    fileprivate let exception: WorkoutScheduleException
}
public enum WorkoutScheduleReviewRules {
    public static func review(program: WorkoutProgram, slot: Int, date: Date, runCommitments: [TrainingRunCommitment] = [],
                              protectedSlots: Set<Int> = [], now: Date = Date(), calendar: Calendar = .current) throws -> WorkoutScheduleMoveReview {
        guard program.trainingBlock != nil, (0..<program.totalSlots).contains(slot), slot >= max(program.currentProgressIndex ?? 0, 0),
              !protectedSlots.contains(slot), let old = program.date(forSlot: slot, calendar: calendar),
              date.timeIntervalSinceReferenceDate.isFinite, calendar.startOfDay(for: date) >= calendar.startOfDay(for: now) else { throw WorkoutBlockError.progressChanged }
        let target = calendar.startOfDay(for: date)
        let collisions = (0..<program.totalSlots).filter { $0 != slot && program.date(forSlot: $0, calendar: calendar).map { calendar.isDate($0, inSameDayAs: target) } == true }
            .compactMap { program.routine(forSlot: $0)?.name } + runCommitments.filter { $0.day == TrainingCalendarDay(target, calendar: calendar) }.map { "Run: " + $0.plan.name }
        let prior = program.trainingBlock?.scheduleExceptions?.first { $0.slotIndex == slot }
        let exception = WorkoutScheduleException(id: prior?.id ?? UUID().uuidString, slotIndex: slot,
            originalDay: prior?.originalDay ?? TrainingCalendarDay(old, calendar: calendar), proposedDay: TrainingCalendarDay(target, calendar: calendar), revision: (prior?.revision ?? 0) + 1)
        return WorkoutScheduleMoveReview(id: UUID().uuidString, slotIndex: slot, oldDate: old, newDate: target,
            collisions: collisions, basis: try WorkoutBlockRules.structureFingerprint(program), exception: exception)
    }
    public static func applying(_ review: WorkoutScheduleMoveReview, to program: WorkoutProgram,
                                protectedSlots: Set<Int> = [], now: Date = Date(), calendar: Calendar = .current) throws -> WorkoutProgramBlock {
        guard try WorkoutBlockRules.structureFingerprint(program) == review.basis, var block = program.trainingBlock else { throw WorkoutBlockError.changed }
        _ = try self.review(program: program, slot: review.slotIndex, date: review.newDate, protectedSlots: protectedSlots, now: now, calendar: calendar)
        block.revisionID = UUID().uuidString
        block.scheduleExceptions = (block.scheduleExceptions ?? []).filter { $0.slotIndex != review.slotIndex } + [review.exception]
        return block
    }
}

public struct WorkoutScheduleDateChange: Identifiable {
    public var id: Int { slotIndex }
    public var slotIndex: Int
    public var title: String
    public var oldDate: Date?
    public var proposedDate: Date?
    public var runCollisions: [String]
}
public enum WorkoutScheduleComparison {
    public static func changes(from original: WorkoutProgram?, to proposal: WorkoutProgram,
                               runs: [TrainingRunCommitment] = [], calendar: Calendar = .current) -> [WorkoutScheduleDateChange] {
        let progress = max(original?.currentProgressIndex ?? 0, 0)
        return (progress..<max(progress, proposal.totalSlots)).compactMap { slot in
            let old = original?.date(forSlot: slot, calendar: calendar), new = proposal.date(forSlot: slot, calendar: calendar)
            guard old != new else { return nil }
            return WorkoutScheduleDateChange(slotIndex: slot, title: proposal.routine(forSlot: slot)?.name ?? "Session",
                oldDate: old, proposedDate: new, runCollisions: runs.filter { commitment in new.map { TrainingCalendarDay($0, calendar: calendar) == commitment.day } ?? false }.map { $0.plan.name })
        }
    }
}
