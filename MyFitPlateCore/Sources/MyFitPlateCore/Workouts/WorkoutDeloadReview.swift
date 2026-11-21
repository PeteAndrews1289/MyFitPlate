import Foundation

public struct WorkoutDeloadReceipt: Codable, Equatable, Sendable {
    public let id: String
    public let beforeTargets: Data
    public let acceptedFingerprint: String
    public let originallyDeload: Bool
    public let loadPercent: Double
    public let setPercent: Double
    public let createdAt: Date
    public let frozenLinks: [String: String]?
    public let frozenTargetFingerprints: [String: String]?
}
public enum WorkoutDeloadError: LocalizedError {
    case alreadyAdjusted
    public var errorDescription: String? { "This week already has a reviewed lighter adjustment. Undo it before preparing another; later target edits stay protected." }
}

public struct WorkoutDeloadReview: Identifiable {
    public let id: String
    public let weekIndex: Int
    public let loadPercent: Double
    public let setPercent: Double
    public let beforeSets: Int
    public let afterSets: Int
    public let returnWeekName: String?
    public let summary: String
    fileprivate let basis: String
    fileprivate let proposal: Data
}

public enum WorkoutDeloadRules {
    /// One future week only. Every later week retains its original targets, including an authored return.
    public static func review(program: WorkoutProgram, week: Int, loadPercent: Double = 90,
                              setPercent: Double = 75, protectedSlots: Set<Int> = []) throws -> WorkoutDeloadReview {
        guard let block = program.trainingBlock, block.weeks.indices.contains(week),
              (40...100).contains(loadPercent), (25...100).contains(setPercent),
              loadPercent.isFinite, setPercent.isFinite else { throw WorkoutBlockError.invalid }
        guard block.weeks[week].deloadAdjustment == nil else { throw WorkoutDeloadError.alreadyAdjusted }
        let originalTargets = try routines(program: program, week: week)
        let slots = (week * block.sessionsPerWeek)..<((week + 1) * block.sessionsPerWeek)
        guard !slots.contains(where: { $0 < max(program.currentProgressIndex ?? 0, 0) || protectedSlots.contains($0) }) else { throw WorkoutBlockError.progressChanged }
        var result = try WorkoutWeekLinkRules.freezingProtectedWeeks(in: program, protectedSlots: protectedSlots)
        var frozenLinks: [String: String] = [:], frozenFingerprints: [String: String] = [:]
        let targetID = block.weeks[week].id
        for candidate in block.weeks.indices where candidate != week {
            var cursor = block.weeks[candidate].linkedSourceWeekID, seen = Set<String>()
            var dependsOnTarget = false
            while let id = cursor, seen.insert(id).inserted {
                if id == targetID { dependsOnTarget = true; break }
                cursor = block.weeks.first(where: { $0.id == id })?.linkedSourceWeekID
            }
            guard dependsOnTarget else { continue }
            let original = try routines(program: program, week: candidate)
            if let link = result.weeks[candidate].linkedSourceWeekID {
                frozenLinks[result.weeks[candidate].id] = link
                frozenFingerprints[result.weeks[candidate].id] = try PlanFingerprint.make(original)
            }
            result.weeks[candidate].linkedSourceWeekID = nil
            let lower = candidate * block.sessionsPerWeek, upper = (candidate + 1) * block.sessionsPerWeek
            result.overrides.removeAll { (lower..<upper).contains($0.slotIndex) }
            result.overrides += original.enumerated().map { WorkoutBlockSlotOverride(slotIndex: lower + $0.offset, routine: $0.element) }
        }
        var before = 0, after = 0
        result.weeks[week].linkedSourceWeekID = nil
        for slot in slots {
            guard let routine = program.routine(forSlot: slot)?.deepCopy() else { throw WorkoutBlockError.invalid }
            for exercise in routine.exercises.indices {
                let normal = routine.exercises[exercise].sets.filter { $0.resolvedSetType == .normal }
                before += normal.count
                let keep = max(1, Int((Double(normal.count) * setPercent / 100).rounded(.down)))
                var ordinal = 0
                routine.exercises[exercise].sets = routine.exercises[exercise].sets.compactMap { original in
                    guard original.resolvedSetType == .normal else { return original }
                    ordinal += 1
                    guard ordinal <= keep else { return nil }
                    var set = original
                    if routine.exercises[exercise].loadEquipment?.loadingMeaning == .assistance {
                        // Assistance is not bodyweight: do not invent an inverse percentage formula.
                        // This review reduces set count and leaves its selected assistance intact.
                    } else if var target = set.prescription, let percentage = target.loadPercentage {
                        target.loadPercentage = percentage * loadPercent / 100
                        set.prescription = target
                    } else if set.weight > 0 {
                        let reduced = set.weight * loadPercent / 100
                        if let equipment = routine.exercises[exercise].loadEquipment {
                            guard let available = equipment.atOrBelow(reduced) else { return original }
                            set.weight = available
                        } else { set.weight = reduced }
                    }
                    return set
                }
                after += routine.exercises[exercise].sets.filter { $0.resolvedSetType == .normal }.count
                routine.exercises[exercise].targetSets = routine.exercises[exercise].sets.count
            }
            result.overrides.removeAll { $0.slotIndex == slot }
            result.overrides.append(WorkoutBlockSlotOverride(slotIndex: slot, routine: routine))
        }
        result.weeks[week].isDeload = true
        var accepted = program; accepted.trainingBlock = result
        result.weeks[week].deloadAdjustment = WorkoutDeloadReceipt(id: UUID().uuidString,
            beforeTargets: try JSONEncoder().encode(originalTargets), acceptedFingerprint: try PlanFingerprint.make(routines(program: accepted, week: week)),
            originallyDeload: block.weeks[week].isDeload, loadPercent: loadPercent, setPercent: setPercent, createdAt: Date(), frozenLinks: frozenLinks, frozenTargetFingerprints: frozenFingerprints)
        let returnName = block.weeks.indices.contains(week + 1) ? block.weeks[week + 1].name : nil
        let summary = "Linked later weeks keep their original targets independently. \(before) → \(after) working sets. Loaded targets use \(Int(loadPercent))%; unknown starting loads and assistance stay manual. "
            + (returnName.map { "\($0) keeps its original targets for the return to normal training." } ?? "This is the final week; review a new block afterward.")
        return WorkoutDeloadReview(id: UUID().uuidString, weekIndex: week, loadPercent: loadPercent, setPercent: setPercent,
            beforeSets: before, afterSets: after, returnWeekName: returnName, summary: summary,
            basis: try WorkoutBlockRules.structureFingerprint(program), proposal: try JSONEncoder().encode(result))
    }
    public static func applying(_ review: WorkoutDeloadReview, to program: WorkoutProgram, protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        guard try WorkoutBlockRules.structureFingerprint(program) == review.basis else { throw WorkoutBlockError.changed }
        _ = try self.review(program: program, week: review.weekIndex, loadPercent: review.loadPercent, setPercent: review.setPercent, protectedSlots: protectedSlots)
        var candidate = try JSONDecoder().decode(WorkoutProgramBlock.self, from: review.proposal)
        candidate.revisionID = UUID().uuidString
        _ = try WorkoutBlockRules.applying(candidate, to: program, expected: program, protectedSlots: protectedSlots)
        return candidate
    }
    public static func undo(in program: WorkoutProgram, week: Int, protectedSlots: Set<Int> = []) throws -> WorkoutProgramBlock {
        guard var block = program.trainingBlock, block.weeks.indices.contains(week),
              let receipt = block.weeks[week].deloadAdjustment, block.weeks[week].isDeload,
              try PlanFingerprint.make(routines(program: program, week: week)) == receipt.acceptedFingerprint else { throw WorkoutBlockError.changed }
        let slots = (week * block.sessionsPerWeek)..<((week + 1) * block.sessionsPerWeek)
        guard !slots.contains(where: { $0 < max(program.currentProgressIndex ?? 0, 0) || protectedSlots.contains($0) }) else { throw WorkoutBlockError.progressChanged }
        let before = try JSONDecoder().decode([WorkoutRoutine].self, from: receipt.beforeTargets)
        guard before.count == block.sessionsPerWeek else { throw WorkoutBlockError.invalid }
        block.weeks[week].linkedSourceWeekID = nil
        block.overrides.removeAll { slots.contains($0.slotIndex) }
        let lower = week * block.sessionsPerWeek
        let restored = before.enumerated().map { WorkoutBlockSlotOverride(slotIndex: lower + $0.offset, routine: $0.element) }
        block.overrides.append(contentsOf: restored)
        block.weeks[week].isDeload = receipt.originallyDeload; block.weeks[week].deloadAdjustment = nil
        for (weekID, link) in receipt.frozenLinks ?? [:] {
            guard let index = block.weeks.firstIndex(where: { $0.id == weekID }), block.weeks[index].linkedSourceWeekID == nil,
                  index * block.sessionsPerWeek >= max(program.currentProgressIndex ?? 0, 0) else { continue }
            let linkedSlots = (index * block.sessionsPerWeek)..<((index + 1) * block.sessionsPerWeek)
            guard !linkedSlots.contains(where: { protectedSlots.contains($0) }) else { continue }
            var current = program; current.trainingBlock = block
            if try PlanFingerprint.make(routines(program: current, week: index)) == receipt.frozenTargetFingerprints?[weekID] {
                block.weeks[index].linkedSourceWeekID = link
                block.overrides.removeAll { linkedSlots.contains($0.slotIndex) }
            }
        }
        block.revisionID = UUID().uuidString
        _ = try WorkoutBlockRules.applying(block, to: program, expected: program, protectedSlots: protectedSlots)
        return block
    }
    private static func routines(program: WorkoutProgram, week: Int) throws -> [WorkoutRoutine] {
        guard let block = program.trainingBlock else { throw WorkoutBlockError.invalid }
        return try (0..<block.sessionsPerWeek).map { day in
            guard let routine = WorkoutBlockRules.baseRoutine(for: program, slot: week * block.sessionsPerWeek + day)?.deepCopy() else { throw WorkoutBlockError.invalid }
            return routine
        }
    }

}
