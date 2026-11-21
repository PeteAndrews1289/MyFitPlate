import Foundation

public struct WorkoutBlockMergeReview {
    public let conflicts: [WorkoutEditorConflict]
    fileprivate let baseline: Data
    fileprivate let local: Data
    fileprivate let saved: Data
}
public enum WorkoutBlockMergeRules {
    public static func review(baseline: WorkoutProgram, local: WorkoutProgram, saved: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutBlockMergeReview {
        guard baseline.id == saved.id, local.id == saved.id, baseline.userID == saved.userID, local.userID == saved.userID,
              let block = local.trainingBlock, let remote = saved.trainingBlock,
              block.sessionsPerWeek == remote.sessionsPerWeek else { throw WorkoutBlockError.changed }
        var conflicts: [WorkoutEditorConflict] = []
        func append<Value: Encodable>(_ id: String, _ title: String, _ before: Value, _ mine: Value, _ other: Value,
                                      mineText: String, savedText: String) throws {
            let a = try PlanFingerprint.make(before), b = try PlanFingerprint.make(mine), c = try PlanFingerprint.make(other)
            if b != a && c != a && b != c { conflicts.append(WorkoutEditorConflict(id: id, title: title, localSummary: mineText, savedSummary: savedText)) }
        }
        try append("name", "Block name", baseline.trainingBlock?.name, Optional(block.name), Optional(remote.name), mineText: block.name, savedText: remote.name)
        try append("length", "Block length", baseline.trainingBlock?.weeks.count, Optional(block.weeks.count), Optional(remote.weeks.count), mineText: "\(block.weeks.count) weeks", savedText: "\(remote.weeks.count) weeks")
        for index in 0..<max(block.totalSlots, remote.totalSlots) {
            let before = baseline.routine(forSlot: index), mine = local.routine(forSlot: index), other = saved.routine(forSlot: index)
            try append("slot:\(index)", "Week \(index / block.sessionsPerWeek + 1), day \(index % block.sessionsPerWeek + 1)", before, mine, other,
                mineText: summary(mine), savedText: summary(other))
            let isProtected = index < (saved.currentProgressIndex ?? 0) || protectedSlots.contains(index)
            if isProtected,
               try PlanFingerprint.make(mine) != PlanFingerprint.make(other),
               !conflicts.contains(where: { $0.id == "slot:\(index)" }) {
                conflicts.append(WorkoutEditorConflict(id: "slot:\(index)", title: "Protected session \(index + 1)", localSummary: summary(mine), savedSummary: summary(other)))
            }
        }
        for index in 0..<max(block.weeks.count, remote.weeks.count) {
            let before = baseline.trainingBlock?.weeks.indices.contains(index) == true ? baseline.trainingBlock?.weeks[index] : nil
            let mine = block.weeks.indices.contains(index) ? block.weeks[index] : nil
            let other = remote.weeks.indices.contains(index) ? remote.weeks[index] : nil
            // Stable week IDs may differ on concurrent first adoption; compare editable labels only.
            try append("week:\(index)", "Week \(index + 1) labels", before.map { "\($0.name)|\($0.isDeload)" }, mine.map { "\($0.name)|\($0.isDeload)" }, other.map { "\($0.name)|\($0.isDeload)" },
                mineText: mine.map { "\($0.name) · lighter: \($0.isDeload)" } ?? "Removed", savedText: other.map { "\($0.name) · lighter: \($0.isDeload)" } ?? "Removed")
        }
        try append("schedule", "Future date exceptions", baseline.trainingBlock?.scheduleExceptions, block.scheduleExceptions, remote.scheduleExceptions,
            mineText: "\(block.scheduleExceptions?.count ?? 0) reviewed moves", savedText: "\(remote.scheduleExceptions?.count ?? 0) reviewed moves")
        return WorkoutBlockMergeReview(conflicts: conflicts, baseline: try JSONEncoder().encode(baseline), local: try JSONEncoder().encode(local), saved: try JSONEncoder().encode(saved))
    }
    public static func resolving(_ review: WorkoutBlockMergeReview, choices: [String: WorkoutEditorConflictChoice], latest: WorkoutProgram,
                                 protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        let decoder = JSONDecoder()
        let before = try decoder.decode(WorkoutProgram.self, from: review.baseline)
        let local = try decoder.decode(WorkoutProgram.self, from: review.local)
        let saved = try decoder.decode(WorkoutProgram.self, from: review.saved)
        guard try WorkoutBlockRules.structureFingerprint(saved) == WorkoutBlockRules.structureFingerprint(latest),
              let mine = local.trainingBlock, var block = saved.trainingBlock,
              review.conflicts.allSatisfy({ choices[$0.id] != nil }) else { throw WorkoutBlockError.changed }
        func useMine<Value: Encodable>(_ id: String, _ original: Value, _ proposed: Value) throws -> Bool {
            if review.conflicts.contains(where: { $0.id == id }) { return choices[id] == .mine }
            return try PlanFingerprint.make(original) != PlanFingerprint.make(proposed)
        }
        if try useMine("name", before.trainingBlock?.name, Optional(mine.name)) { block.name = mine.name }
        if try useMine("length", before.trainingBlock?.weeks.count, Optional(mine.weeks.count)) {
            if mine.weeks.count < block.weeks.count { block.weeks = Array(block.weeks.prefix(mine.weeks.count)) }
            while block.weeks.count < mine.weeks.count { block.weeks.append(WorkoutBlockWeek(name: mine.weeks[block.weeks.count].name, isDeload: mine.weeks[block.weeks.count].isDeload)) }
        }
        var resolution = latest; resolution.trainingBlock = block
        // Materialize only changed slots; links in untouched saved weeks remain intact.
        for index in 0..<block.totalSlots {
            if try useMine("slot:\(index)", before.routine(forSlot: index), local.routine(forSlot: index)),
               let routine = local.routine(forSlot: index)?.deepCopy() {
                let week = index / block.sessionsPerWeek
                resolution.trainingBlock = block
                block = try WorkoutWeekLinkRules.detaching(week: week, in: resolution)
                block.overrides.removeAll { $0.slotIndex == index }
                block.overrides.append(WorkoutBlockSlotOverride(slotIndex: index, routine: routine))
            }
        }
        for index in block.weeks.indices where mine.weeks.indices.contains(index) {
            let old = before.trainingBlock?.weeks.indices.contains(index) == true ? before.trainingBlock?.weeks[index] : nil
            if try useMine("week:\(index)", old.map { "\($0.name)|\($0.isDeload)" }, "\(mine.weeks[index].name)|\(mine.weeks[index].isDeload)") {
                block.weeks[index].name = mine.weeks[index].name; block.weeks[index].isDeload = mine.weeks[index].isDeload
            }
        }
        if try useMine("schedule", before.trainingBlock?.scheduleExceptions, mine.scheduleExceptions) { block.scheduleExceptions = mine.scheduleExceptions }
        let totalSlots = block.totalSlots
        block.overrides = block.overrides.filter { $0.slotIndex < totalSlots }.sorted { $0.slotIndex < $1.slotIndex }
        block.revisionID = UUID().uuidString
        _ = try WorkoutBlockRules.applying(block, to: latest, expected: latest, protectedSlots: protectedSlots)
        return block
    }
    private static func summary(_ routine: WorkoutRoutine?) -> String {
        guard let routine else { return "No session in this version" }
        return routine.name + "\n" + routine.exercises.map { $0.name + ": " + $0.sets.map { $0.prescription?.summary ?? $0.target ?? "Manual" }.joined(separator: ", ") }.joined(separator: "\n")
    }
}
