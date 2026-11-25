import Foundation

/// A reviewed, independent copy. Session snapshots are encoded so mutable routine
/// references cannot change the source while its destination is being reviewed.
public struct WorkoutWeekCopyReview: Identifiable, Sendable {
    public let id: String
    public let sourceWeekIndex: Int
    public let destinationWeekIndex: Int
    public let sourceName: String
    public let destinationName: String
    public let sessionNames: [String]
    public let isDeload: Bool
    fileprivate let userID: String
    fileprivate let programID: String
    fileprivate let programFingerprint: String
    fileprivate let sessions: Data
}

public enum WorkoutWeekCopyRules {
    public static func review(in program: WorkoutProgram, sourceWeek: Int, destinationWeek: Int,
                              protectedSlots: Set<Int> = []) throws -> WorkoutWeekCopyReview {
        guard let block = program.trainingBlock, let programID = program.id,
              !programID.isEmpty, !program.userID.isEmpty,
              block.weeks.indices.contains(sourceWeek), block.weeks.indices.contains(destinationWeek),
              sourceWeek != destinationWeek else { throw WorkoutBlockError.invalid }
        try WorkoutBlockRules.validate(program)
        try protectDestination(destinationWeek, in: program, protectedSlots: protectedSlots)
        let sessions = try (0..<block.sessionsPerWeek).map { day -> WorkoutBlockSlotOverride in
            let sourceSlot = sourceWeek * block.sessionsPerWeek + day
            guard let routine = WorkoutBlockRules.baseRoutine(for: program, slot: sourceSlot)?.deepCopy() else {
                throw WorkoutBlockError.invalid
            }
            return WorkoutBlockSlotOverride(slotIndex: destinationWeek * block.sessionsPerWeek + day, routine: routine)
        }
        return WorkoutWeekCopyReview(id: UUID().uuidString, sourceWeekIndex: sourceWeek,
            destinationWeekIndex: destinationWeek, sourceName: block.weeks[sourceWeek].name,
            destinationName: block.weeks[destinationWeek].name, sessionNames: sessions.map(\.routine.name),
            isDeload: block.weeks[sourceWeek].isDeload, userID: program.userID, programID: programID,
            programFingerprint: try WorkoutBlockRules.structureFingerprint(program), sessions: try JSONEncoder().encode(sessions))
    }

    public static func applying(_ review: WorkoutWeekCopyReview, to program: WorkoutProgram,
                                linked: Bool = false, protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        guard program.userID == review.userID, program.id == review.programID else { throw WorkoutBlockError.accountChanged }
        guard var block = program.trainingBlock,
              try WorkoutBlockRules.structureFingerprint(program) == review.programFingerprint else { throw WorkoutBlockError.changed }
        try protectDestination(review.destinationWeekIndex, in: program, protectedSlots: protectedSlots)
        block = try WorkoutWeekLinkRules.freezingProtectedWeeks(in: program, protectedSlots: protectedSlots)
        let sessions = try JSONDecoder().decode([WorkoutBlockSlotOverride].self, from: review.sessions)
        let destinationSlots = Set(sessions.map(\.slotIndex))
        block.overrides.removeAll { destinationSlots.contains($0.slotIndex) }
        if linked {
            block.schemaVersion = 2
            block.weeks[review.destinationWeekIndex].linkedSourceWeekID = block.weeks[review.sourceWeekIndex].id
        } else {
            block.weeks[review.destinationWeekIndex].linkedSourceWeekID = nil
            block.overrides.append(contentsOf: sessions)
        }
        block.overrides.sort { $0.slotIndex < $1.slotIndex }
        // Keep the destination's name and stable week identity. The label does not
        // invent lighter targets; the exact reviewed source prescriptions are copied.
        block.weeks[review.destinationWeekIndex].isDeload = review.isDeload
        var candidate = program; candidate.trainingBlock = block
        try WorkoutBlockRules.validate(candidate)
        return block
    }

    public static func destinationIsProtected(_ week: Int, in program: WorkoutProgram,
                                              protectedSlots: Set<Int> = []) -> Bool {
        (try? protectDestination(week, in: program, protectedSlots: protectedSlots)) == nil
    }

    private static func protectDestination(_ week: Int, in program: WorkoutProgram,
                                           protectedSlots: Set<Int>) throws {
        guard let block = program.trainingBlock, block.weeks.indices.contains(week) else { throw WorkoutBlockError.invalid }
        let destination = (week * block.sessionsPerWeek)..<((week + 1) * block.sessionsPerWeek)
        let progress = max(program.currentProgressIndex ?? 0, 0)
        guard !destination.contains(where: { $0 < progress || protectedSlots.contains($0) }) else {
            throw WorkoutBlockError.progressChanged
        }
    }
}

public struct WorkoutBlockWeekReview: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isDeload: Bool
    public let totalSlots: Int
    public let passedSlots: Int
    public let linkedLogs: Int
    public let legacyMatches: Int
    public let skippedSlots: Int
    public let passedWithoutLog: Int
    public var outcomes: [WorkoutSlotOutcomeEvidence] = []
}

/// Descriptive evidence only. A passed pointer, a skip and a linked workout log
/// are deliberately different; none establishes that every prescribed set was done.
public struct WorkoutBlockReview: Equatable, Sendable {
    public let totalSlots: Int
    public let passedSlots: Int
    public let linkedLogs: Int
    public let legacyMatches: Int
    public let skippedSlots: Int
    public let passedWithoutLog: Int
    public let loggedAhead: Int
    public let logsOnSkippedSlots: Int
    public let weeks: [WorkoutBlockWeekReview]
    public var outcomes: [WorkoutSlotOutcomeEvidence] = []
    public var completedSlots: Int { outcomes.filter { $0.state == .completed }.count }
    public var partialSlots: Int { outcomes.filter { $0.state == .partial }.count }
    public var unknownSlots: Int { outcomes.filter { $0.state == .unknown }.count }
    public var movedSlots: Int { outcomes.filter(\.isMoved).count }
    public var substitutedReceipts: Int { outcomes.flatMap(\.sessions).filter { !$0.substitutionExerciseIDs.isEmpty }.count }

    public static func make(program: WorkoutProgram, logs: [WorkoutSessionLog], now: Date = Date(),
                            calendar: Calendar = .current) -> WorkoutBlockReview {
        let outcomes = WorkoutOutcomeEvidenceRules.slots(program: program, logs: logs, now: now, calendar: calendar)
        let total = max(program.totalSlots, 0)
        let passed = min(max(program.currentProgressIndex ?? 0, 0), total)
        let linked = Set(logs.compactMap { log -> Int? in
            guard log.programLinkDecision != .standalone, let context = log.programContext,
                  context.programID == program.id, (0..<total).contains(context.slotIndex),
                  log.date.timeIntervalSinceReferenceDate.isFinite, log.date <= now else { return nil }
            if let recordedBlock = context.blockSession, recordedBlock.blockID != program.trainingBlock?.id { return nil }
            return context.slotIndex
        })
        // Existing conservative legacy matching is review evidence, kept separate
        // from the explicit program/slot references above.
        let legacy = Set(WorkoutRules.sessionLogsBySlot(in: program,
            sessionLogs: logs.filter { $0.programContext == nil && $0.date <= now }, calendar: calendar).keys)
            .subtracting(linked)
        let declaredSkips = Set((program.skippedIndices ?? []).filter { (0..<total).contains($0) })
        let skipped = declaredSkips.subtracting(linked).subtracting(legacy)
        let unlinkedPassed = Set(0..<passed).subtracting(linked).subtracting(legacy).subtracting(skipped)
        let sessionsPerWeek = max(program.trainingBlock?.sessionsPerWeek ?? program.daysOfWeek?.count ?? 0, 1)
        let weekCount = total == 0 ? 0 : (total + sessionsPerWeek - 1) / sessionsPerWeek
        let weeks = (0..<weekCount).map { index -> WorkoutBlockWeekReview in
            let slots = Set((index * sessionsPerWeek)..<min((index + 1) * sessionsPerWeek, total))
            let week = program.trainingBlock.flatMap { $0.weeks.indices.contains(index) ? $0.weeks[index] : nil }
            return WorkoutBlockWeekReview(id: week?.id ?? "legacy-week-\(index)", name: week?.name ?? "Week \(index + 1)",
                isDeload: week?.isDeload ?? false, totalSlots: slots.count,
                passedSlots: slots.intersection(0..<passed).count, linkedLogs: slots.intersection(linked).count,
                legacyMatches: slots.intersection(legacy).count, skippedSlots: slots.intersection(skipped).count,
                passedWithoutLog: slots.intersection(unlinkedPassed).count,
                outcomes: outcomes.filter { slots.contains($0.slotIndex) })
        }
        return WorkoutBlockReview(totalSlots: total, passedSlots: passed, linkedLogs: linked.count,
            legacyMatches: legacy.count, skippedSlots: skipped.count, passedWithoutLog: unlinkedPassed.count,
            loggedAhead: linked.filter { $0 >= passed }.count,
            logsOnSkippedSlots: declaredSkips.intersection(linked.union(legacy)).count, weeks: weeks, outcomes: outcomes)
    }
}
