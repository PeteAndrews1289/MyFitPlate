import Foundation

public struct WorkoutExerciseGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var version: Int
    public var memberSlotIDs: [String]
    /// Seconds after a working set of each member. Zero means move directly to its partner.
    public var transitionRestSeconds: [String: Int]
    public init(id: String = UUID().uuidString, memberSlotIDs: [String], transitionRestSeconds: [String: Int]) {
        self.id = id; version = 1; self.memberSlotIDs = memberSlotIDs; self.transitionRestSeconds = transitionRestSeconds
    }
    public var isValid: Bool {
        version == 1 && (2...8).contains(memberSlotIDs.count) && Set(memberSlotIDs).count == memberSlotIDs.count
            && memberSlotIDs.allSatisfy { !$0.isEmpty } && Set(transitionRestSeconds.keys) == Set(memberSlotIDs)
            && transitionRestSeconds.values.allSatisfy { (0...900).contains($0) }
    }
}
public enum WorkoutExerciseGroupRules {
    public static func applying(_ group: WorkoutExerciseGroup, to exercises: [RoutineExercise]) throws -> [RoutineExercise] {
        guard group.isValid, Set(group.memberSlotIDs).isSubset(of: Set(exercises.map(\.id))),
              exercises.filter({ group.memberSlotIDs.contains($0.id) }).allSatisfy({ $0.type == .strength && !$0.sets.contains(where: \.isCompleted) }) else { throw WorkoutBlockError.invalid }
        let first = exercises.firstIndex { group.memberSlotIDs.contains($0.id) } ?? 0
        var result = repairing(exercises.map { original in
            var value = original
            if group.memberSlotIDs.contains(value.id) { value.groupPlan = group; value.supersetGroupID = group.id }
            return value
        })
        let members = group.memberSlotIDs.compactMap { id in result.first { $0.id == id } }
        result.removeAll { group.memberSlotIDs.contains($0.id) }
        result.insert(contentsOf: members, at: min(first, result.count))
        return result
    }
    public static func repairing(_ exercises: [RoutineExercise]) -> [RoutineExercise] {
        return exercises.map { original in
            var value = original
            guard var group = value.groupPlan else { return value }
            // Do not infer new members; edits only retain explicitly authored matching members.
            group.memberSlotIDs = (original.groupPlan?.memberSlotIDs ?? []).filter { id in
                exercises.contains { $0.id == id && $0.groupPlan?.id == group.id }
            }
            group.transitionRestSeconds = group.transitionRestSeconds.filter { group.memberSlotIDs.contains($0.key) }
            if group.memberSlotIDs.last != original.groupPlan?.memberSlotIDs.last, let last = group.memberSlotIDs.last,
               let originalLast = original.groupPlan?.memberSlotIDs.last {
                group.transitionRestSeconds[last] = original.groupPlan?.transitionRestSeconds[originalLast] ?? value.restTimeInSeconds
            }
            if group.memberSlotIDs.count < 2 { value.groupPlan = nil; value.supersetGroupID = nil } else { value.groupPlan = group; value.supersetGroupID = group.id }
            return value
        }
    }
}

public extension WorkoutExerciseGroupRules {
    static func restAfterCompleting(setID: String, in exercises: [RoutineExercise]) -> Int? {
        guard let exercise = exercises.first(where: { $0.sets.contains { $0.id == setID } }),
              let set = exercise.sets.first(where: { $0.id == setID }) else { return nil }
        if set.resolvedSetType == .warmup { return set.generatedWarmup?.restSeconds ?? exercise.restTimeInSeconds }
        guard let group = exercise.groupPlan, group.isValid, let member = group.memberSlotIDs.firstIndex(of: exercise.id) else { return nil }
        let laterHaveWork = group.memberSlotIDs.dropFirst(member + 1).contains { id in
            exercises.first(where: { $0.id == id })?.sets.contains { !$0.isCompleted && $0.isDeferred != true && $0.resolvedSetType != .warmup } == true
        }
        return laterHaveWork ? group.transitionRestSeconds[exercise.id] : group.memberSlotIDs.last.flatMap { group.transitionRestSeconds[$0] }
    }
}
