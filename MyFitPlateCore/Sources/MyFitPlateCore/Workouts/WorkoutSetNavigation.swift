import Foundation

public struct WorkoutSetPosition: Equatable, Sendable {
    public let exerciseID: String
    public let setID: String
}

public enum WorkoutSetNavigation {
    public static func firstUnfinished(in exercises: [RoutineExercise]) -> WorkoutSetPosition? {
        exercises.lazy.compactMap(position).first
    }

    /// Called only after an explicit completion. Browsing or editing never moves the cursor.
    public static func next(after setID: String, in exercises: [RoutineExercise]) -> WorkoutSetPosition? {
        guard let index = exercises.firstIndex(where: { $0.sets.contains { $0.id == setID && $0.isCompleted } }),
              let completed = exercises[index].sets.first(where: { $0.id == setID }) else { return nil }
        if completed.resolvedSetType == .warmup,
           let warmup = exercises[index].sets.first(where: { !$0.isCompleted && $0.isDeferred != true && $0.resolvedSetType == .warmup }) {
            return WorkoutSetPosition(exerciseID: exercises[index].id, setID: warmup.id)
        }
        if let group = exercises[index].groupPlan, group.isValid,
           let current = group.memberSlotIDs.firstIndex(of: exercises[index].id) {
            let order = Array(group.memberSlotIDs.dropFirst(current + 1)) + Array(group.memberSlotIDs.prefix(current + 1))
            for id in order {
                if let member = exercises.first(where: { $0.id == id && $0.groupPlan == group }), let next = position(member) { return next }
            }
            return exercises.filter { !group.memberSlotIDs.contains($0.id) }.lazy.compactMap(position).first
        }
        var first = index, last = index
        if let group = exercises[index].supersetGroupID {
            while first > 0 && exercises[first - 1].supersetGroupID == group { first -= 1 }
            while last + 1 < exercises.count && exercises[last + 1].supersetGroupID == group { last += 1 }
        }
        let order = Array((index + 1)..<(last + 1)) + Array(first...index)
        for candidate in order {
            if let next = position(exercises[candidate]) { return next }
        }
        for candidate in Array(exercises.indices.dropFirst(last + 1)) + Array(exercises.indices.prefix(first)) {
            if let next = position(exercises[candidate]) { return next }
        }
        return nil
    }

    public static func nextAfterDeferring(setID: String, in exercises: [RoutineExercise]) -> WorkoutSetPosition? {
        var copy = exercises
        guard let exercise = copy.firstIndex(where: { $0.sets.contains { $0.id == setID } }),
              let set = copy[exercise].sets.firstIndex(where: { $0.id == setID }) else { return nil }
        copy[exercise].sets[set].isCompleted = true
        return next(after: setID, in: copy)
    }

    /// Moves only the input cursor. Sets remain unfinished, and reaching the end
    /// dismisses input rather than wrapping back to work the user already reviewed.
    public static func nextInput(after setID: String, in exercises: [RoutineExercise]) -> WorkoutSetPosition? {
        let order = orderedInputs(in: exercises)
        guard let current = order.firstIndex(where: { $0.position.setID == setID }) else { return nil }
        return order.dropFirst(current + 1).first(where: { !$0.isCompleted })?.position
    }

    /// Browses earlier unfinished input in the same warm-up/superset order. It
    /// never reopens a completed set or wraps from the first row to the last.
    public static func previousInput(before setID: String, in exercises: [RoutineExercise]) -> WorkoutSetPosition? {
        let order = orderedInputs(in: exercises)
        guard let current = order.firstIndex(where: { $0.position.setID == setID }) else { return nil }
        return order.prefix(current).reversed().first(where: { !$0.isCompleted })?.position
    }

    private static func orderedInputs(in exercises: [RoutineExercise]) -> [InputPosition] {
        var order: [InputPosition] = []
        var index = 0
        var consumed = Set<String>()
        while index < exercises.count {
            if consumed.contains(exercises[index].id) { index += 1; continue }
            if let group = exercises[index].groupPlan, group.isValid {
                let members = group.memberSlotIDs.compactMap { id in exercises.first { $0.id == id && $0.groupPlan == group } }
                if members.count == group.memberSlotIDs.count {
                    order += inputOrder(in: members); consumed.formUnion(members.map(\.id)); index += 1; continue
                }
            }
            var end = index + 1
            if let group = exercises[index].supersetGroupID {
                while end < exercises.count && exercises[end].supersetGroupID == group { end += 1 }
            }
            order += inputOrder(in: exercises[index..<end].filter { $0.type == .strength })
            index = end
        }
        return order
    }

    private struct InputPosition {
        let position: WorkoutSetPosition
        let isCompleted: Bool
    }

    private static func inputOrder(in exercises: [RoutineExercise]) -> [InputPosition] {
        let working = exercises.map { $0.sets.filter { $0.resolvedSetType != .warmup } }
        let rounds = max(working.map(\.count).max() ?? 0, 1)
        var order: [InputPosition] = []
        for round in 0..<rounds {
            for index in exercises.indices {
                let exercise = exercises[index]
                // Each lift's warmups stay together immediately before its first
                // working set; working sets then alternate through the group.
                if round == 0 {
                    for set in exercise.sets where set.resolvedSetType == .warmup {
                        order.append(inputPosition(for: set, in: exercise))
                    }
                }
                if working[index].indices.contains(round) {
                    order.append(inputPosition(for: working[index][round], in: exercise))
                }
            }
        }
        return order
    }

    private static func inputPosition(for set: ExerciseSet, in exercise: RoutineExercise) -> InputPosition {
        InputPosition(position: WorkoutSetPosition(exerciseID: exercise.id, setID: set.id), isCompleted: set.isCompleted || set.isDeferred == true)
    }

    private static func position(_ exercise: RoutineExercise) -> WorkoutSetPosition? {
        guard let set = exercise.sets.first(where: { !$0.isCompleted && $0.isDeferred != true }) else { return nil }
        return WorkoutSetPosition(exerciseID: exercise.id, setID: set.id)
    }
}
