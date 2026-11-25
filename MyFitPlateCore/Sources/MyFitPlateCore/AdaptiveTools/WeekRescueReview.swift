import Foundation

public enum WeekRescueScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case thisSession, remainingWeek
    public var id: String { rawValue }
    public var title: String { self == .thisSession ? "This session" : "Remaining week" }
}

public enum WeekRescueReviewError: LocalizedError {
    case infeasible, protectedWork, missingDraft
    public var errorDescription: String? {
        switch self {
        case .infeasible: "Your available days cannot fit these sessions while keeping their existing recovery gaps. Add an available day or extend the recovery window."
        case .protectedWork: "This change would move or alter an active or already completed session. Finish the active workout or choose another scope."
        case .missingDraft: "This rescue review changed. Reopen it before continuing."
        }
    }
}

public enum WeekRescueReviewRules {
    public static func preview(program: WorkoutProgram, reason: WeekRescueReason, workoutDate: Date,
                               scope: WeekRescueScope, windowDays: Int, availableWeekdays: Set<Int> = [],
                               minutes: Int = 30, mealChanges: [RescueMealChange] = [], protectedSlots: Set<Int> = [],
                               now: Date = Date(), calendar: Calendar = .current) throws -> WeekRescueAdjustment {
        guard (1...14).contains(windowDays), availableWeekdays.allSatisfy({ (1...7).contains($0) }) else { throw WeekRescueError.invalidDate }
        let passed = max(0, program.currentProgressIndex ?? 0)
        let protected = protectedSlots.union((program.slotCompletionProofs ?? []).map(\.slotIndex))
            .union(program.skippedIndices ?? [])
        if scope == .thisSession, protected.contains(passed), reason == .lessTime || reason == .lighterWeek {
            throw WeekRescueReviewError.protectedWork
        }
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: windowDays, to: today) else { throw WeekRescueError.invalidDate }
        let base = try WeekRescueRules.preview(program: program, reason: reason, workoutDate: workoutDate,
            minutes: minutes, mealChanges: mealChanges, windowDays: windowDays, now: now, calendar: calendar)
        var slots = base.slots.filter { $0.index >= passed && !protected.contains($0.index) }
        var explanation = base.explanation
        if reason == .lessTime, scope == .remainingWeek {
            for slot in passed..<program.totalSlots where !protected.contains(slot) && slot != passed {
                guard let date = program.date(forSlot: slot, calendar: calendar), date >= today, date < end else { continue }
                var source = program; source.currentProgressIndex = slot
                let short = try WeekRescueRules.preview(program: source, reason: .lessTime, workoutDate: date,
                    minutes: minutes, windowDays: windowDays, now: now, calendar: calendar)
                if let value = short.slots.first(where: { $0.index == slot }) {
                    slots.removeAll { $0.index == slot }; slots.append(value)
                }
            }
            explanation = ["Shorten each eligible session in the next \(windowDays) days to about \(minutes) minutes. Your workout order, loads and rep prescriptions remain yours to review.",
                           "Warm-up sets and completed work are kept. Only the sessions shown below receive shorter targets."]
        } else if reason == .lighterWeek, scope == .thisSession {
            slots = slots.map { slot in
                RescueWorkoutSlot(index: slot.index, originalDate: slot.originalDate, date: slot.date,
                    routine: slot.index == passed ? slot.routine : nil,
                    originalRoutineFingerprint: slot.index == passed ? slot.originalRoutineFingerprint : nil)
            }.filter { $0.routine != nil || $0.date != $0.originalDate }
            explanation = ["Reduce regular working sets in this session only, keeping at least one per eligible movement. Later targets stay unchanged.",
                           "Any overdue date shift is shown separately below so recovery gaps remain visible."]
        }
        if !availableWeekdays.isEmpty, reason == .missedWorkout || reason == .busyDay {
            var previousDate: Date?
            var previousOriginal: Date?
            var shift = 0
            for index in slots.indices.sorted(by: { slots[$0].index < slots[$1].index }) {
                guard let original = slots[index].originalDate else { throw WeekRescueReviewError.infeasible }
                var date = slots[index].date
                if let previousDate, let previousOriginal {
                    let gap = max(1, calendar.dateComponents([.day], from: previousOriginal, to: original).day ?? 1)
                    guard let earliest = calendar.date(byAdding: .day, value: gap, to: previousDate) else { throw WeekRescueReviewError.infeasible }
                    date = max(date, earliest)
                }
                if original < end {
                    while date < end && !availableWeekdays.contains(calendar.component(.weekday, from: date)) {
                        guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { throw WeekRescueReviewError.infeasible }
                        date = next
                    }
                    guard date < end else { throw WeekRescueReviewError.infeasible }
                    shift = calendar.dateComponents([.day], from: original, to: date).day ?? 0
                } else if let shifted = calendar.date(byAdding: .day, value: shift, to: original) { date = max(date, shifted) }
                let old = slots[index]
                slots[index] = RescueWorkoutSlot(index: old.index, originalDate: original, date: date,
                    routine: old.routine, originalRoutineFingerprint: old.originalRoutineFingerprint)
                previousOriginal = original; previousDate = date
            }
            explanation.append("Use your selected available weekdays within the recovery window, then preserve the later schedule gaps.")
        }
        guard !slots.isEmpty || !mealChanges.isEmpty else { throw WeekRescueReviewError.protectedWork }
        let result = WeekRescueAdjustment(id: base.id, createdAt: base.createdAt, reason: reason,
            sourceProgramFingerprint: base.sourceProgramFingerprint, slots: slots.sorted { $0.index < $1.index },
            meals: mealChanges, explanation: explanation)
        let adjusted = try WeekRescueRules.applying(result, to: program)
        // An excluded active/early-completed slot must not be squeezed by moving its neighbour.
        for slot in passed..<program.totalSlots where protected.contains(slot) {
            for neighbour in [slot - 1, slot + 1] where (passed..<program.totalSlots).contains(neighbour) {
                guard let oldA = program.date(forSlot: min(slot, neighbour), calendar: calendar),
                      let oldB = program.date(forSlot: max(slot, neighbour), calendar: calendar),
                      let newA = adjusted.date(forSlot: min(slot, neighbour), calendar: calendar),
                      let newB = adjusted.date(forSlot: max(slot, neighbour), calendar: calendar) else { continue }
                let oldGap = calendar.dateComponents([.day], from: oldA, to: oldB).day ?? 0
                let newGap = calendar.dateComponents([.day], from: newA, to: newB).day ?? 0
                guard newGap >= max(0, oldGap) else { throw WeekRescueReviewError.protectedWork }
            }
        }
        return result
    }
}

public struct WeekRescueReviewDraft: Codable {
    public let ownerID: String
    public let programID: String
    public let rescue: WeekRescueAdjustment
    public let command: WorkoutProgramEditCommand
    public var submitted: Bool
    public let isUndo: Bool

    public init(program: WorkoutProgram, rescue: WeekRescueAdjustment, undo: Bool = false, protectedSlots: Set<Int> = []) throws {
        guard let id = program.id else { throw WeekRescueError.noProgram }
        ownerID = program.userID; programID = id; self.rescue = rescue; submitted = false; isUndo = undo
        let proposed = try undo ? WeekRescueRules.undoing(id: rescue.id, in: program) : WeekRescueRules.applying(rescue, to: program)
        command = try WorkoutProgramEditCommand(expected: program, proposed: proposed, protectedSlots: protectedSlots, kind: .weekRescue)
    }
}

public struct WeekRescueAcceptedReceipt: Codable, Identifiable {
    public let id: String
    public let rescue: WeekRescueAdjustment
    public let acceptedAt: Date
    public let wasUndo: Bool
}

public struct WeekRescueReviewStore {
    private let storage: EditorDraftStore
    public init(storage: EditorDraftStore = EditorDraftStore()) { self.storage = storage }
    private func scope(_ programID: String) -> String { "week-rescue-review-\(programID)" }
    public func load(userID: String, programID: String) throws -> WeekRescueReviewDraft? {
        let value = try storage.load(WeekRescueReviewDraft.self, userID: userID, scope: scope(programID))?.value
        guard value == nil || (value?.ownerID == userID && value?.programID == programID) else { throw WorkoutBlockError.accountChanged }
        return value
    }
    public func save(_ value: WeekRescueReviewDraft, userID: String) throws {
        guard value.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        if let existing = try load(userID: userID, programID: value.programID), existing.command.id != value.command.id {
            throw WeekRescueReviewError.missingDraft
        }
        try storage.save(value, userID: userID, scope: scope(value.programID))
    }
    public func history(userID: String, programID: String) throws -> [WeekRescueAcceptedReceipt] {
        try storage.load([WeekRescueAcceptedReceipt].self, userID: userID, scope: scope(programID) + "-history")?.value ?? []
    }
    public func finish(_ value: WeekRescueReviewDraft, userID: String, now: Date = Date()) throws {
        guard value.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        var receipts = try history(userID: userID, programID: value.programID)
        if !receipts.contains(where: { $0.id == value.command.id }) {
            receipts.append(WeekRescueAcceptedReceipt(id: value.command.id, rescue: value.rescue, acceptedAt: now, wasUndo: value.isUndo))
            try storage.save(receipts, userID: userID, scope: scope(value.programID) + "-history")
        }
        if try load(userID: userID, programID: value.programID)?.command.id == value.command.id {
            try storage.remove(userID: userID, scope: scope(value.programID))
        }
    }
    public func discard(_ value: WeekRescueReviewDraft, userID: String, cancellationConfirmed: Bool = false) throws {
        guard value.ownerID == userID else { throw WorkoutBlockError.accountChanged }
        guard !value.submitted || cancellationConfirmed,
              try load(userID: userID, programID: value.programID)?.command.id == value.command.id else { throw WeekRescueReviewError.missingDraft }
        try storage.remove(userID: userID, scope: scope(value.programID))
    }
}
