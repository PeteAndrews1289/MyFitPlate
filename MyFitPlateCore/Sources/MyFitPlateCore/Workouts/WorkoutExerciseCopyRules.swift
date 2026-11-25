import Foundation

public enum WorkoutExerciseCopyRules {
    /// Fresh prescription identities; canonical movement/setup references remain comparable.
    /// Performed values, today's cues, substitutions and running clocks never become a template.
    public static func freshTemplate(_ source: [RoutineExercise], copyNotes: Bool = true, copyPrescribedValues: Bool = false) -> [RoutineExercise] {
        let counts = Dictionary(source.map { ($0.id, 1) }, uniquingKeysWith: +)
        let identities = Dictionary(uniqueKeysWithValues: source.filter { counts[$0.id] == 1 }.map { ($0.id, UUID().uuidString) })
        let groups = Dictionary(uniqueKeysWithValues: Set(source.compactMap { $0.groupPlan?.id }).map { ($0, UUID().uuidString) })
        return source.map { original in
            var exercise = original
            exercise.id = identities[original.id] ?? UUID().uuidString
            exercise.substitution = nil; exercise.cueSnapshot = nil
            if !copyNotes { exercise.notes = nil }
            exercise.sets = original.sets.map { old in
                var set = old; set.id = UUID().uuidString; set.isCompleted = false
                set.weight = copyPrescribedValues && !old.isCompleted ? old.weight : 0
                set.reps = copyPrescribedValues && !old.isCompleted ? old.reps : 0
                set.distance = copyPrescribedValues && !old.isCompleted ? old.distance : 0
                set.durationInSeconds = copyPrescribedValues && !old.isCompleted ? old.durationInSeconds : 0; set.effort = nil; set.previousPerformance = nil
                set.generatedWarmup = nil; set.intervalTimer = nil; set.isDeferred = nil
                return set
            }
            if var group = original.groupPlan, group.isValid,
               group.memberSlotIDs.allSatisfy({ identities[$0] != nil }) {
                let oldRest = group.transitionRestSeconds
                group.id = groups[group.id] ?? UUID().uuidString
                group.memberSlotIDs = group.memberSlotIDs.compactMap { identities[$0] }
                group.transitionRestSeconds = Dictionary(uniqueKeysWithValues: oldRest.compactMap { key, value in identities[key].map { ($0, value) } })
                exercise.groupPlan = group; exercise.supersetGroupID = group.id
            } else { exercise.groupPlan = nil; exercise.supersetGroupID = nil }
            return exercise
        }
    }
    public static func routine(from log: WorkoutSessionLog, userID: String, name: String = "Reviewed session template") -> WorkoutRoutine {
        WorkoutRoutine(userID: userID, name: name, dateCreated: Date(),
            exercises: freshTemplate(log.completedExercises.map(\.exercise), copyNotes: false))
    }
}
