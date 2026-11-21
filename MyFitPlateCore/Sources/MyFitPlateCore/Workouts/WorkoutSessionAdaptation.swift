import Foundation

public struct WorkoutSessionEditReceipt: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case removeUnfinished, shorten, substitute }
    public let id: String
    public let kind: Kind
    public let title: String
    public let explanation: String
    public let createdAt: Date
    public let before: Data
    public let after: Data
    public let beforeMinutes: Int
    public let afterMinutes: Int
}
public struct WorkoutSubstitutionProvenance: Codable, Sendable {
    public enum Reason: String, Codable, CaseIterable, Identifiable, Sendable {
        case occupied = "Equipment occupied", unavailable = "Equipment unavailable", preference = "Preference", avoid = "Avoid this movement"
        public var id: String { rawValue }
    }
    public var originalSlotID: String
    public var originalMovement: WorkoutMovementIdentity?
    public var originalName: String
    public var originalPrescription: Data
    public var reason: Reason
    public var acceptedAt: Date
}
public enum WorkoutSessionAdaptationRules {
    /// Authored alternatives first, then exact catalog movements in the same primary category.
    /// This is a training-role shortlist, never a claim that a bench, attachment or implement exists.
    public static func substitutionCandidates(for source: RoutineExercise, limit: Int = 8) -> [String] {
        let category = ExerciseList.entries.first { $0.name == source.name }?.category
        let authored = (source.alternatives ?? []).compactMap(WorkoutMovementCatalog.canonicalName)
        let related = ExerciseList.entries.filter { $0.category == category && $0.name != source.name }
            .filter { RoutineEditorDefaults.inferredType(name: $0.name, category: $0.category) == source.type }
            .map(\.name)
        var seen = Set<String>()
        return (authored + related).filter { $0 != source.name && seen.insert($0).inserted }.prefix(max(0, min(20, limit))).map { $0 }
    }

    public static func remainingMinutes(_ exercises: [RoutineExercise]) -> Int {
        let seconds = exercises.reduce(0.0) { total, exercise in
            total + exercise.sets.filter { !$0.isCompleted }.reduce(0.0) { sum, set in
                let prescribed = set.prescription?.validationMessage == nil && set.prescription?.kind == .duration ? set.prescription?.upperBound ?? set.prescription?.lowerBound : nil
                let work: Double
                if let prescribed { work = prescribed } else if exercise.type == .strength { work = max(30, Double(ProgressionRules.repRange(set.target ?? exercise.targetReps)?.upperBound ?? 10) * 4) } else { work = Double(max(set.durationInSeconds, WorkoutDurationEntryRules.targetSeconds(set.target, bareNumberIsSeconds: exercise.type == .flexibility) ?? 30)) }
                return sum + min(86_400, max(0, work)) + Double(min(900, max(0, exercise.restTimeInSeconds)))
            }
        }
        return Int(ceil(seconds / 60))
    }
    public static func removingUnfinished(exerciseID: String, from exercises: [RoutineExercise]) throws -> WorkoutSessionEditReceipt {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { throw WorkoutBlockError.changed }
        var after = exercises
        let performed = exercises[index].sets.filter(\.isCompleted)
        let removed = exercises[index].sets.count - performed.count
        guard removed > 0 else { throw WorkoutBlockError.invalid }
        if performed.isEmpty { after.remove(at: index) } else { after[index].sets = performed; after[index].targetSets = performed.count }
        after = WorkoutExerciseGroupRules.repairing(after)
        return try receipt(kind: .removeUnfinished, title: "Unfinished work removed", explanation: "Removes \(removed) unfinished sets of \(exercises[index].name). \(performed.count) recorded sets stay in this workout and its final receipt.", before: exercises, after: after)
    }
    public static func shortening(_ exercises: [RoutineExercise], toMinutes: Int, protectedMovementIDs: Set<String>) throws -> WorkoutSessionEditReceipt {
        guard (5...180).contains(toMinutes), Set(exercises.map(\.id)).isSuperset(of: protectedMovementIDs) else { throw WorkoutBlockError.invalid }
        var after = exercises
        for exercise in after.indices.reversed() {
            for set in after[exercise].sets.indices.reversed() where remainingMinutes(after) > toMinutes {
                guard !after[exercise].sets[set].isCompleted, after[exercise].sets[set].resolvedSetType == .normal else { continue }
                let unfinished = after[exercise].sets.filter { !$0.isCompleted && $0.resolvedSetType == .normal }.count
                if protectedMovementIDs.contains(after[exercise].id) && unfinished <= 1 { continue }
                after[exercise].sets.remove(at: set)
            }
            after[exercise].targetSets = after[exercise].sets.count
        }
        after.removeAll { $0.sets.isEmpty }
        after = WorkoutExerciseGroupRules.repairing(after)
        guard remainingMinutes(after) <= toMinutes, try PlanFingerprint.make(after) != PlanFingerprint.make(exercises) else { throw WorkoutBlockError.invalid }
        let removed = exercises.reduce(0) { $0 + $1.sets.count } - after.reduce(0) { $0 + $1.sets.count }
        return try receipt(kind: .shorten, title: "Today's work shortened", explanation: "Removes \(removed) unfinished working sets, from the end first. Recorded work, warm-ups and at least one remaining working set of each selected priority movement stay intact. Estimates include prescribed work and rests; this changes today only.", before: exercises, after: after)
    }
    public static func swapping(exerciseID: String, to selection: ExercisePickerDraft, in exercises: [RoutineExercise],
                                history: [WorkoutSessionLog], reason: WorkoutSubstitutionProvenance.Reason = .preference) throws -> WorkoutSessionEditReceipt {
        var replacement = RoutineExercise(name: selection.name, type: selection.type)
        replacement.movementIdentity = selection.movementIdentity ?? WorkoutMovementCatalog.identity(for: selection.name)
        guard let source = exercises.first(where: { $0.id == exerciseID }) else { throw WorkoutBlockError.changed }
        func identifiesReplacement(_ exercise: RoutineExercise) -> Bool {
            guard exercise.type == replacement.type else { return false }
            let identity = exercise.movementIdentity ?? WorkoutMovementCatalog.identity(for: exercise.name)
            if let selected = replacement.movementIdentity { return selected == identity }
            return identity == nil && exercise.name.caseInsensitiveCompare(replacement.name) == .orderedSame
        }
        guard !identifiesReplacement(source) else { throw SwapError.sameMovement }
        // Only reuse an exact setup already present for this movement in this workout.
        let matches = exercises.filter(identifiesReplacement)
        if let setup = matches.first?.loadEquipment, setup.isValid, matches.allSatisfy({ $0.loadEquipment == setup }) {
            replacement.loadEquipment = setup
        }
        return try substituting(exerciseID: exerciseID, replacement: replacement, reason: reason, in: exercises, history: history)
    }

    private enum SwapError: LocalizedError {
        case sameMovement
        var errorDescription: String? { "Choose a different exercise to swap." }
    }

    public static func substituting(exerciseID: String, replacement: RoutineExercise, reason: WorkoutSubstitutionProvenance.Reason,
                                    in exercises: [RoutineExercise], history: [WorkoutSessionLog] = [], now: Date = Date()) throws -> WorkoutSessionEditReceipt {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }), !replacement.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              replacement.loadEquipment?.isValid != false else { throw WorkoutBlockError.invalid }
        let source = exercises[index]
        guard source.sets.contains(where: { !$0.isCompleted }) else { throw WorkoutBlockError.progressChanged }
        var alternative = replacement
        alternative.id = UUID().uuidString; alternative.notes = nil; alternative.groupPlan = nil; alternative.supersetGroupID = nil
        alternative.movementIdentity = replacement.movementIdentity ?? WorkoutMovementCatalog.identity(for: replacement.name)
        let defaults = RoutineEditorDefaults.defaults(for: alternative.type)
        alternative.targetReps = alternative.type == source.type ? source.targetReps : defaults.target
        alternative.restTimeInSeconds = alternative.type == source.type ? source.restTimeInSeconds : defaults.rest
        alternative.sets = source.sets.filter { !$0.isCompleted }.map { old in
            var set = ExerciseSet(target: alternative.type == source.type ? old.target : defaults.target, isWarmup: old.isWarmup, setType: old.setType)
            if let oldTarget = old.prescription, oldTarget.isSupported(for: alternative.type) {
                var target = oldTarget; target.loadPercentage = nil; target.loadReference = nil; target.notes = nil
                set.prescription = target
            } else { set.prescription = WorkoutPrescription.legacy(set.target, type: alternative.type) }
            return set
        }
        alternative.targetSets = alternative.sets.count
        var sourceSnapshot = source; sourceSnapshot.substitution = nil
        alternative.substitution = WorkoutSubstitutionProvenance(originalSlotID: source.id, originalMovement: source.movementIdentity,
            originalName: source.name, originalPrescription: try JSONEncoder().encode(sourceSnapshot), reason: reason, acceptedAt: now)
        let meaning = alternative.loadEquipment?.loadingMeaning
        if alternative.type == .strength {
            alternative.progressionPolicy = WorkoutProgressionPolicy(kind: meaning == .assistance ? .assistance : meaning == .bodyweightOnly ? .bodyweight : .conservativeDouble)
            if let plan = ProgressionRules.plan(for: alternative, history: history, now: now) { alternative = ProgressionRules.applying(plan, to: alternative) }
        }
        var after = exercises
        let performed = source.sets.filter(\.isCompleted)
        if performed.isEmpty { after[index] = alternative } else { after[index].sets = performed; after[index].targetSets = performed.count; after.insert(alternative, at: index + 1) }
        after = WorkoutExerciseGroupRules.repairing(after)
        return try receipt(kind: .substitute, title: "Exercise swapped", explanation: "\(source.name) → \(alternative.name)", before: exercises, after: after)
    }
    public static func applying(_ receipt: WorkoutSessionEditReceipt, to exercises: [RoutineExercise]) throws -> [RoutineExercise] {
        let before = try JSONDecoder().decode([RoutineExercise].self, from: receipt.before)
        guard try PlanFingerprint.make(exercises) == PlanFingerprint.make(before) else { throw WorkoutBlockError.changed }
        return try JSONDecoder().decode([RoutineExercise].self, from: receipt.after)
    }
    public static func undo(_ receipt: WorkoutSessionEditReceipt, in exercises: [RoutineExercise]) throws -> [RoutineExercise] {
        let accepted = try JSONDecoder().decode([RoutineExercise].self, from: receipt.after)
        guard try PlanFingerprint.make(exercises) == PlanFingerprint.make(accepted) else { throw WorkoutBlockError.changed }
        return try JSONDecoder().decode([RoutineExercise].self, from: receipt.before)
    }
    private static func receipt(kind: WorkoutSessionEditReceipt.Kind, title: String, explanation: String,
                                before: [RoutineExercise], after: [RoutineExercise]) throws -> WorkoutSessionEditReceipt {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return WorkoutSessionEditReceipt(id: UUID().uuidString, kind: kind, title: title, explanation: explanation, createdAt: Date(),
            before: try encoder.encode(before), after: try encoder.encode(after), beforeMinutes: remainingMinutes(before), afterMinutes: remainingMinutes(after))
    }
}
