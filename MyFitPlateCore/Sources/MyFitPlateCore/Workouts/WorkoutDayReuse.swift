import Foundation

public struct WorkoutDayReuseReview: Identifiable {
    public enum Mode: String, CaseIterable, Identifiable { case copy = "Copy", swap = "Swap order"; public var id: String { rawValue } }
    public let id: String
    public let sourceSlot: Int
    public let destinationSlot: Int
    public let mode: Mode
    public let summary: [String]
    fileprivate let fingerprint: String
    fileprivate let targets: Data
}
public enum WorkoutDayReuseRules {
    public static func review(program: WorkoutProgram, sourceSlot: Int, destinationSlot: Int, mode: WorkoutDayReuseReview.Mode,
                              protectedSlots: Set<Int> = []) throws -> WorkoutDayReuseReview {
        guard program.trainingBlock != nil, sourceSlot != destinationSlot,
              let source = WorkoutBlockRules.baseRoutine(for: program, slot: sourceSlot),
              let destination = WorkoutBlockRules.baseRoutine(for: program, slot: destinationSlot) else { throw WorkoutBlockError.invalid }
        try protect(destinationSlot, program: program, protectedSlots: protectedSlots)
        if mode == .swap { try protect(sourceSlot, program: program, protectedSlots: protectedSlots) }
        func copy(_ source: WorkoutRoutine, into target: WorkoutRoutine, slot: Int) -> WorkoutBlockSlotOverride {
            let routine = WorkoutRoutine(id: target.id, userID: program.userID, name: source.name, dateCreated: target.dateCreated,
                exercises: WorkoutExerciseCopyRules.freshTemplate(source.exercises, copyPrescribedValues: true), notes: source.notes)
            return WorkoutBlockSlotOverride(slotIndex: slot, routine: routine)
        }
        var targets = [copy(source, into: destination, slot: destinationSlot)]
        if mode == .swap { targets.append(copy(destination, into: source, slot: sourceSlot)) }
        let summary = targets.map { target in
            "Slot \(target.slotIndex + 1): \(target.routine.name) · " + target.routine.exercises.map {
                $0.name + " [" + $0.sets.map { $0.prescription?.summary ?? $0.target ?? "Manual" }.joined(separator: ", ") + "]"
            }.joined(separator: "; ")
        }
        return WorkoutDayReuseReview(id: UUID().uuidString, sourceSlot: sourceSlot, destinationSlot: destinationSlot, mode: mode,
            summary: summary, fingerprint: try WorkoutBlockRules.structureFingerprint(program), targets: try JSONEncoder().encode(targets))
    }
    public static func applying(_ review: WorkoutDayReuseReview, to program: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        guard try WorkoutBlockRules.structureFingerprint(program) == review.fingerprint, var block = program.trainingBlock else { throw WorkoutBlockError.changed }
        _ = try self.review(program: program, sourceSlot: review.sourceSlot, destinationSlot: review.destinationSlot, mode: review.mode, protectedSlots: protectedSlots)
        block = try WorkoutWeekLinkRules.freezingProtectedWeeks(in: program, protectedSlots: protectedSlots)
        let targets = try JSONDecoder().decode([WorkoutBlockSlotOverride].self, from: review.targets)
        for target in targets {
            var current = program; current.trainingBlock = block
            block = try WorkoutWeekLinkRules.detaching(week: target.slotIndex / block.sessionsPerWeek, in: current)
            block.overrides.removeAll { $0.slotIndex == target.slotIndex }; block.overrides.append(target)
        }
        block.overrides.sort { $0.slotIndex < $1.slotIndex }
        var result = program; result.trainingBlock = block; try WorkoutBlockRules.validate(result)
        return block
    }
    private static func protect(_ slot: Int, program: WorkoutProgram, protectedSlots: Set<Int>) throws {
        guard (0..<program.totalSlots).contains(slot), slot >= max(program.currentProgressIndex ?? 0, 0), !protectedSlots.contains(slot) else { throw WorkoutBlockError.progressChanged }
    }
}
