import Foundation

public enum WorkoutReceiptCompletion: String, Codable, Sendable {
    case completed, partial, unknown
    public var title: String {
        switch self {
        case .completed: "Completed planned sets"
        case .partial: "Partial planned sets"
        case .unknown: "Coverage unknown"
        }
    }
}

/// Coverage describes the frozen original sets, not target achievement or movement equivalence.
public struct WorkoutSessionOutcomeEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sessionID }
    public let sessionID: String
    public let date: Date
    public let programID: String?
    public let blockID: String?
    public let slotIndex: Int?
    public let completion: WorkoutReceiptCompletion
    public let isUnassigned: Bool
    public let expectedWorkingSets: Int?
    public let recordedOriginalWorkingSets: Int
    public let recordedWorkingSets: Int
    public let substitutionExerciseIDs: [String]
    public let explanation: String
    public var title: String { (isUnassigned ? "Unassigned · " : "") + completion.title }
}
public enum WorkoutPlannedSlotState: String, Codable, Sendable {
    case completed, partial, skipped, unknown, notLogged
    public var title: String {
        switch self {
        case .completed: "Completed planned sets"
        case .partial: "Partial planned sets"
        case .skipped: "Declared skip"
        case .unknown: "Coverage unknown"
        case .notLogged: "No recorded session"
        }
    }
}
public struct WorkoutSlotOutcomeEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let slotIndex: Int
    public let state: WorkoutPlannedSlotState
    public let sessions: [WorkoutSessionOutcomeEvidence]
    public let originalDay: TrainingCalendarDay?
    public let scheduledDay: TrainingCalendarDay?
    public let isMoved: Bool
    public let explanation: String
}
public struct WorkoutRecordedBreak: Codable, Equatable, Identifiable, Sendable {
    public var id: String { previousSessionID + "|" + nextSessionID }
    public let previousSessionID: String
    public let nextSessionID: String
    public let from: Date
    public let through: Date
    public var days: Int { Int(through.timeIntervalSince(from) / 86_400) }
}

public enum WorkoutOutcomeEvidenceRules {
    private struct TargetKey: Hashable { let exercise: String; let set: String }
    public static func sessionID(_ log: WorkoutSessionLog) -> String {
        log.id ?? "\(log.routineID)|\(log.date.timeIntervalSinceReferenceDate)"
    }
    public static func session(_ log: WorkoutSessionLog) -> WorkoutSessionOutcomeEvidence {
        let unassigned = log.programContext == nil || log.programLinkDecision == .standalone
        let substitutions = Set(log.completedExercises.filter { $0.exercise.substitution != nil }.map { $0.exercise.id }).sorted()
        let recorded = log.completedExercises.reduce(0) { $0 + measuredSets($1).count }
        func evidence(_ completion: WorkoutReceiptCompletion, expected: Int? = nil, covered: Int = 0, _ reason: String) -> WorkoutSessionOutcomeEvidence {
            .init(sessionID: sessionID(log), date: log.date, programID: log.programContext?.programID,
                blockID: log.programContext?.blockSession?.blockID, slotIndex: log.programContext?.slotIndex,
                completion: completion, isUnassigned: unassigned, expectedWorkingSets: expected,
                recordedOriginalWorkingSets: covered, recordedWorkingSets: recorded,
                substitutionExerciseIDs: substitutions, explanation: reason)
        }
        guard let context = log.programContext, !context.programID.isEmpty, context.slotIndex >= 0,
              let frozen = context.blockSession, !frozen.targets.isEmpty, !frozen.blockID.isEmpty,
              frozen.targets.allSatisfy({ !$0.exerciseID.isEmpty && !$0.setID.isEmpty }) else {
            return evidence(.unknown, "No full frozen original prescription is recorded. A saved receipt or passed position alone does not establish completion.")
        }
        let targets = frozen.targets.map { TargetKey(exercise: $0.exerciseID, set: $0.setID) }
        guard Set(targets).count == targets.count,
              Set(log.completedExercises.map { $0.exercise.id }).count == log.completedExercises.count else {
            return evidence(.unknown, "Duplicate original set or exercise identities prevent a reliable coverage comparison.")
        }
        var roles: [TargetKey: Bool] = [:], covered = Set<TargetKey>(), conflictingRole = false
        func inspect(_ exercise: RoutineExercise) {
            for set in exercise.sets {
                let key = TargetKey(exercise: exercise.id, set: set.id), working = set.resolvedSetType != .warmup
                if let prior = roles[key], prior != working { conflictingRole = true }
                roles[key] = working
            }
        }
        var measurementMismatch = false
        for result in log.completedExercises {
            inspect(result.exercise)
            if let substitution = result.exercise.substitution,
               let original = try? JSONDecoder().decode(RoutineExercise.self, from: substitution.originalPrescription),
               original.id == substitution.originalSlotID { inspect(original) }
            let flagged = result.exercise.sets.filter { $0.isCompleted && $0.resolvedSetType != .warmup }
            if flagged.count != measuredSets(result).count { measurementMismatch = true }
            for set in flagged { covered.insert(TargetKey(exercise: result.exercise.id, set: set.id)) }
        }
        guard !conflictingRole, !measurementMismatch else {
            return evidence(.unknown, "Saved set roles or completed-set measurements do not agree. The recorded work is retained without inferring original prescription coverage.")
        }
        let unknown = targets.filter { roles[$0] == nil }.count
        let knownWorking = Set(targets.filter { roles[$0] == true })
        let observed = knownWorking.intersection(covered).count
        guard unknown == 0 else {
            return evidence(.unknown, covered: observed, "\(unknown) original set roles are absent from the saved exercise snapshots. Missing sets or exercises are not assumed to be working sets or warm-ups.")
        }
        guard !knownWorking.isEmpty else {
            return evidence(.unknown, "The frozen prescription has no identifiable working sets. Warm-ups do not establish workout completion.")
        }
        let suffix = substitutions.isEmpty ? "" : " \(substitutions.count) recorded substitution(s) are shown separately; replacement work is not declared equivalent to the original movement."
        return evidence(observed == knownWorking.count ? .completed : .partial, expected: knownWorking.count, covered: observed,
            "\(observed) of \(knownWorking.count) original working sets recorded. This measures set coverage, not whether rep, load or effort targets were achieved." + suffix)
    }
    public static func slots(program: WorkoutProgram, logs: [WorkoutSessionLog], now: Date = Date(), calendar: Calendar = .current) -> [WorkoutSlotOutcomeEvidence] {
        let unique = WorkoutSetMath.uniqueSessions(logs).filter { $0.date.timeIntervalSinceReferenceDate.isFinite && $0.date <= now }
        let legacy = WorkoutRules.sessionLogsBySlot(in: program, sessionLogs: unique.filter { $0.programContext == nil }, calendar: calendar)
        return (0..<max(program.totalSlots, 0)).map { slot in
            let matching = unique.filter {
                guard $0.programLinkDecision != .standalone, let context = $0.programContext,
                      context.programID == program.id, context.slotIndex == slot else { return false }
                return context.blockSession == nil || context.blockSession?.blockID == program.trainingBlock?.id
            }.map(session)
            let move = program.trainingBlock?.scheduleExceptions?.first { $0.slotIndex == slot && $0.originalDay != $0.proposedDay }
            let state: WorkoutPlannedSlotState
            let explanation: String
            if matching.contains(where: { $0.completion == .completed }) {
                state = .completed; explanation = "At least one saved receipt covers every identifiable original working set. Separate partial receipts are not combined into completion."
            } else if !matching.isEmpty {
                state = matching.allSatisfy { $0.completion == .partial } ? .partial : .unknown
                explanation = "Coverage comes from each frozen receipt. Separate receipts and replacement movements are not merged into an invented complete workout."
            } else if legacy[slot] != nil {
                state = .unknown; explanation = "An older routine/date match exists without a full explicit original prescription."
            } else if program.skippedIndices?.contains(slot) == true {
                state = .skipped; explanation = "This position is explicitly marked skipped and has no matching saved training receipt."
            } else if slot < max(program.currentProgressIndex ?? 0, 0) {
                state = .unknown; explanation = "The position has passed without a matching saved receipt. Passed does not mean completed or skipped."
            } else {
                state = .notLogged; explanation = "No matching saved receipt or declared skip is recorded. Missing records do not establish zero activity."
            }
            return WorkoutSlotOutcomeEvidence(id: "\(program.id ?? "unknown")|\(slot)", slotIndex: slot, state: state, sessions: matching,
                originalDay: move?.originalDay, scheduledDay: move?.proposedDay ?? program.date(forSlot: slot, calendar: calendar).map { TrainingCalendarDay($0, calendar: calendar) },
                isMoved: move != nil, explanation: explanation)
        }
    }
    /// A gap is only between adjacent saved receipts in this scope, not a claim of inactivity.
    public static func breaks(_ logs: [WorkoutSessionLog]) -> [WorkoutRecordedBreak] {
        let ordered = WorkoutSetMath.uniqueSessions(logs).filter { $0.date.timeIntervalSinceReferenceDate.isFinite }.sorted { $0.date < $1.date }
        return zip(ordered, ordered.dropFirst()).compactMap { first, next in
            guard next.date.timeIntervalSince(first.date) > 21 * 86_400 else { return nil }
            return WorkoutRecordedBreak(previousSessionID: sessionID(first), nextSessionID: sessionID(next), from: first.date, through: next.date)
        }
    }
    private static func measuredSets(_ result: CompletedExercise) -> [CompletedSet] {
        var seen = Set<String>()
        return WorkoutSetMath.workingSets(in: result).filter {
            guard seen.insert($0.id).inserted else { return false }
            switch result.exercise.type {
            case .strength: return $0.reps > 0
            case .cardio: return ($0.durationInSeconds ?? 0) > 0 || ($0.distance ?? 0) > 0
            case .flexibility: return ($0.durationInSeconds ?? 0) > 0
            }
        }
    }
}

/// Export keeps adherence/coverage separate from the existing comparable performance totals.
public struct WorkoutOutcomeReportDocument: Codable {
    public let schemaVersion: Int
    public let derivationVersion: Int
    public let performance: WorkoutEvidenceSnapshot
    public let sessionOutcomes: [WorkoutSessionOutcomeEvidence]
    public let recordedBreaks: [WorkoutRecordedBreak]
    public init(logs: [WorkoutSessionLog], scope: WorkoutReportScope, now: Date = Date()) throws {
        schemaVersion = 1; derivationVersion = 1
        let selected = WorkoutEvidenceReportRules.filtered(logs, scope: scope, now: now)
        performance = try WorkoutEvidenceReportRules.snapshot(logs: logs, scope: scope, now: now)
        sessionOutcomes = selected.map(WorkoutOutcomeEvidenceRules.session)
        recordedBreaks = WorkoutOutcomeEvidenceRules.breaks(selected)
    }
}
