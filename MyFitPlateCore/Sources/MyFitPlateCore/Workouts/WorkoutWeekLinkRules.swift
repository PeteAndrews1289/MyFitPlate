import Foundation

public enum WorkoutWeekLinkRules {
    public static func validate(_ block: WorkoutProgramBlock) throws {
        let ids = Set(block.weeks.map(\.id))
        for (index, week) in block.weeks.enumerated() {
            guard let source = week.linkedSourceWeekID else { continue }
            guard block.schemaVersion == 2, ids.contains(source), source != week.id,
                  !block.overrides.contains(where: { $0.slotIndex / max(block.sessionsPerWeek, 1) == index }) else {
                throw WorkoutBlockError.invalid
            }
            var visited = Set<String>(); var current: String? = week.id
            while let id = current {
                guard visited.insert(id).inserted else { throw WorkoutBlockError.invalid }
                current = block.weeks.first(where: { $0.id == id })?.linkedSourceWeekID
            }
        }
    }

    /// Detaching materializes exact resolved targets. It can safely preserve a
    /// partially completed week before only one remaining day is edited.
    public static func detaching(week index: Int, in program: WorkoutProgram) throws -> WorkoutProgramBlock {
        guard var block = program.trainingBlock, block.weeks.indices.contains(index) else { throw WorkoutBlockError.invalid }
        guard block.weeks[index].linkedSourceWeekID != nil else { return block }
        var snapshots: [WorkoutBlockSlotOverride] = []
        for day in 0..<block.sessionsPerWeek {
            let slot = index * block.sessionsPerWeek + day
            guard let routine = WorkoutBlockRules.baseRoutine(for: program, slot: slot)?.deepCopy() else { throw WorkoutBlockError.invalid }
            snapshots.append(WorkoutBlockSlotOverride(slotIndex: slot, routine: routine))
        }
        let slots = Set(snapshots.map(\.slotIndex))
        block.overrides.removeAll { slots.contains($0.slotIndex) }
        block.overrides.append(contentsOf: snapshots)
        block.overrides.sort { $0.slotIndex < $1.slotIndex }
        block.weeks[index].linkedSourceWeekID = nil
        return block
    }

    /// When a future source changes, linked weeks with any saved/active position
    /// first become independent exact snapshots. Completed history never follows it.
    public static func freezingProtectedWeeks(in program: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        guard let block = program.trainingBlock, (1...7).contains(block.sessionsPerWeek) else { throw WorkoutBlockError.invalid }
        var updated = program
        let passed = Set(0..<min(max(program.currentProgressIndex ?? 0, 0), block.totalSlots))
        let weeks = Set(passed.union(protectedSlots).filter { (0..<block.totalSlots).contains($0) }.map { $0 / block.sessionsPerWeek })
        for index in weeks.sorted() {
            updated.trainingBlock = try detaching(week: index, in: updated)
        }
        guard let result = updated.trainingBlock else { throw WorkoutBlockError.invalid }
        return result
    }
}
