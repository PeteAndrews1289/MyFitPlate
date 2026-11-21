import Foundation

/// A review destination captures the exact plan and future slot it was offered for.
/// It never grants permission to alter a completed session or a different account.
public struct WorkoutNextSessionContext: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let ownerID: String
    public let programID: String
    public let slotIndex: Int
    public let routineID: String
    public let structureFingerprint: String
    public let evidenceSessionID: String?
    public let evidenceFingerprint: String?
    public let createdAt: Date
    public var id: String { "\(programID)-\(slotIndex)-\(structureFingerprint)" }

    /// Without evidence, review the next pending slot. After a completed session,
    /// review its next occurrence rather than borrowing another training day's loads.
    public static func next(for program: WorkoutProgram, ownerID: String,
                            evidenceSession: WorkoutSessionLog? = nil,
                            protectedSlots: Set<Int> = [], now: Date = Date()) throws -> Self? {
        guard ownerID == program.userID, let programID = program.id, !programID.isEmpty else {
            throw WorkoutBlockError.accountChanged
        }
        if let evidenceSession {
            guard evidenceSession.id?.isEmpty == false, evidenceSession.date <= now,
                  WorkoutRules.logBelongsToProgram(evidenceSession, program: program) else {
                throw WorkoutBlockError.changed
            }
        }
        let first = max(max(program.currentProgressIndex ?? 0, 0), (evidenceSession?.programContext?.slotIndex ?? -1) + 1)
        guard first < program.totalSlots else { return nil }
        guard let slot = (first..<program.totalSlots).first(where: { slot in
            !protectedSlots.contains(slot) && !(program.skippedIndices ?? []).contains(slot)
                && !(program.slotCompletionProofs ?? []).contains(where: { $0.slotIndex == slot })
                && program.routine(forSlot: slot).map { evidenceSession == nil || $0.id == evidenceSession?.routineID } == true
        }), let routine = program.routine(forSlot: slot) else { return nil }
        return Self(schemaVersion: 1, ownerID: ownerID, programID: programID, slotIndex: slot,
                    routineID: routine.id, structureFingerprint: try WorkoutBlockRules.structureFingerprint(program),
                    evidenceSessionID: evidenceSession?.id,
                    evidenceFingerprint: try evidenceSession.map(WorkoutNextSessionRules.evidenceFingerprint), createdAt: now)
    }
}

public struct WorkoutNextSessionRecommendation: Identifiable {
    public let exercise: RoutineExercise
    public let recorded: CompletedExercise?
    public let recordedAt: Date?
    public let plan: ProgressionPlan?
    public var id: String { exercise.id }
}

public enum WorkoutNextSessionRules {
    public static func evidenceFingerprint(_ log: WorkoutSessionLog) throws -> String {
        // Newly generated analysis must not invalidate unchanged measured evidence.
        var measured = log
        measured.aiInsights = nil
        return try WorkoutBlockRules.fingerprint(measured)
    }

    public static func validate(_ context: WorkoutNextSessionContext, program: WorkoutProgram,
                                ownerID: String, protectedSlots: Set<Int> = [], now: Date = Date()) throws {
        guard context.ownerID == ownerID, program.userID == ownerID, program.id == context.programID else {
            throw WorkoutBlockError.accountChanged
        }
        guard context.schemaVersion == 1, context.createdAt.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSince(context.createdAt) >= -60,
              now.timeIntervalSince(context.createdAt) <= 86_400,
              try WorkoutBlockRules.structureFingerprint(program) == context.structureFingerprint,
              program.routine(forSlot: context.slotIndex)?.id == context.routineID else { throw WorkoutBlockError.changed }
        guard context.slotIndex >= max(program.currentProgressIndex ?? 0, 0),
              context.slotIndex < program.totalSlots, !protectedSlots.contains(context.slotIndex),
              !(program.skippedIndices ?? []).contains(context.slotIndex),
              !(program.slotCompletionProofs ?? []).contains(where: { $0.slotIndex == context.slotIndex }) else { throw WorkoutBlockError.progressChanged }
    }

    public static func recommendations(for context: WorkoutNextSessionContext, program: WorkoutProgram,
                                       history: [WorkoutSessionLog], ownerID: String,
                                       protectedSlots: Set<Int> = [], now: Date = Date()) throws -> [WorkoutNextSessionRecommendation] {
        try validate(context, program: program, ownerID: ownerID, protectedSlots: protectedSlots, now: now)
        guard let routine = program.routine(forSlot: context.slotIndex) else { throw WorkoutBlockError.unavailable }
        let history = history.filter { $0.date <= now && WorkoutRules.logBelongsToProgram($0, program: program) }
        return routine.exercises.filter { $0.type == .strength }.map { exercise in
            let previous = ProgressionRules.history(for: exercise, in: history, routineID: routine.id, now: now).first
            return WorkoutNextSessionRecommendation(exercise: exercise,
                recorded: previous.flatMap { ProgressionRules.performance(for: exercise, in: $0) }, recordedAt: previous?.date,
                plan: ProgressionRules.plan(for: exercise, history: history, routineID: routine.id, now: now))
        }
    }

    /// Stages only explicitly reviewed movements in one future occurrence. The
    /// existing block editor owns final review, durable submission and checked save.
    public static func proposedBlock(context: WorkoutNextSessionContext, program: WorkoutProgram,
                                     reviewedPlans: [ProgressionPlan], history: [WorkoutSessionLog], ownerID: String,
                                     protectedSlots: Set<Int> = [], now: Date = Date()) throws -> WorkoutProgramBlock {
        try validate(context, program: program, ownerID: ownerID, protectedSlots: protectedSlots, now: now)
        guard !reviewedPlans.isEmpty, Set(reviewedPlans.map(\.exerciseID)).count == reviewedPlans.count else { throw WorkoutBlockError.invalid }
        if let evidenceID = context.evidenceSessionID {
            guard let evidence = history.first(where: { $0.id == evidenceID }),
                  try evidenceFingerprint(evidence) == context.evidenceFingerprint else { throw WorkoutBlockError.changed }
        }
        guard let routine = program.routine(forSlot: context.slotIndex)?.deepCopy() else { throw WorkoutBlockError.unavailable }
        for plan in reviewedPlans {
            guard let index = routine.exercises.firstIndex(where: { $0.id == plan.exerciseID }), plan.isValid,
                  !routine.exercises[index].sets.contains(where: \.isCompleted) else { throw WorkoutBlockError.progressChanged }
            let original = routine.exercises[index]
            let updated = ProgressionRules.applying(plan, to: original)
            guard plan.targets.allSatisfy({ target in
                updated.sets.contains { $0.id == target.id && $0.resolvedSetType == .normal && $0.weight == target.weight && $0.reps == target.reps }
            }), updated.loadEquipment == original.loadEquipment, updated.progressionPolicy == original.progressionPolicy else {
                throw WorkoutBlockError.changed
            }
            routine.exercises[index] = updated
        }
        var proposal = program
        proposal.trainingBlock = try program.trainingBlock ?? WorkoutBlockRules.createRepeatingBlock(for: program)
        guard var block = proposal.trainingBlock else { throw WorkoutBlockError.invalid }
        let week = context.slotIndex / block.sessionsPerWeek
        if block.weeks[week].linkedSourceWeekID != nil {
            block = try WorkoutWeekLinkRules.detaching(week: week, in: proposal)
        }
        // A source week can have linked future weeks. Freeze their original targets
        // before editing this one slot so the proposal cannot spread into other weeks.
        proposal.trainingBlock = block
        let sourceWeekID = block.weeks[week].id
        for index in block.weeks.indices where block.weeks[index].linkedSourceWeekID == sourceWeekID {
            block = try WorkoutWeekLinkRules.detaching(week: index, in: proposal)
            proposal.trainingBlock = block
        }
        block.revisionID = UUID().uuidString
        block.overrides.removeAll { $0.slotIndex == context.slotIndex }
        block.overrides.append(WorkoutBlockSlotOverride(slotIndex: context.slotIndex, routine: routine))
        _ = try WorkoutBlockRules.applying(block, to: program, expected: program, protectedSlots: protectedSlots)
        return block
    }
}
