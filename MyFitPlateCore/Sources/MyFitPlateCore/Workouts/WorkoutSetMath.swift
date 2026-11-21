import Foundation

/// Recorded-load arithmetic. Per-hand and added loads stay as logged; this does
/// not invent missing body weight, assistance, or a second implement.
public enum WorkoutSetMath {
    public static func workingSets(in exercise: CompletedExercise) -> [CompletedSet] {
        exercise.sets.filter {
            $0.isWorkingSet && $0.weight.isFinite && $0.weight >= 0 && $0.reps >= 0
                && ($0.distance.map { $0.isFinite && $0 >= 0 } ?? true)
                && ($0.durationInSeconds.map { $0 >= 0 } ?? true)
        }
    }
    public static func volume(_ exercise: CompletedExercise) -> Double {
        guard exercise.exercise.type == .strength, exercise.exercise.loadEquipment?.loadingMeaning != .assistance,
              exercise.exercise.loadEquipment?.loadingMeaning != .bodyweightOnly else { return 0 }
        return workingSets(in: exercise).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
    public static func volume(_ log: WorkoutSessionLog) -> Double { log.completedExercises.reduce(0) { $0 + volume($1) } }
    public static func workingSetCount(_ log: WorkoutSessionLog) -> Int {
        log.completedExercises.reduce(0) { $0 + workingSets(in: $1).count }
    }
    public static func strengthScore(_ set: CompletedSet) -> Double {
        guard set.isWorkingSet, set.weight.isFinite, set.weight > 0, set.reps > 0 else { return 0 }
        return set.weight * (1 + Double(set.reps) / 30)
    }
    public static func bestSet(_ exercise: CompletedExercise) -> CompletedSet? {
        guard exercise.exercise.type == .strength, exercise.exercise.loadEquipment?.loadingMeaning != .assistance,
              exercise.exercise.loadEquipment?.loadingMeaning != .bodyweightOnly else { return nil }
        return workingSets(in: exercise).filter { strengthScore($0) > 0 }.max { strengthScore($0) < strengthScore($1) }
    }
    public static func normalizedName(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }
    public static func compatible(_ lhs: CompletedExercise, _ rhs: CompletedExercise) -> Bool {
        WorkoutMovementCatalog.matches(lhs.exercise, rhs.exercise)
            && lhs.exercise.type == rhs.exercise.type
            && StrengthEquipment.historyCompatible(current: lhs.exercise.loadEquipment, previous: rhs.exercise.loadEquipment)
    }
    public static func prescriptionCompatible(_ first: RoutineExercise, _ second: RoutineExercise) -> Bool {
        first.type == second.type && first.progressionPolicy == second.progressionPolicy
            && first.sets.filter { $0.resolvedSetType != .warmup }.map(\.target) == second.sets.filter { $0.resolvedSetType != .warmup }.map(\.target)
            && first.sets.filter { $0.resolvedSetType != .warmup }.map(\.prescription) == second.sets.filter { $0.resolvedSetType != .warmup }.map(\.prescription)
            && first.sets.filter { $0.resolvedSetType != .warmup }.map(\.resolvedSetType) == second.sets.filter { $0.resolvedSetType != .warmup }.map(\.resolvedSetType)
    }
    public static func contextLabel(_ exercise: RoutineExercise) -> String {
        let equipment = exercise.loadEquipment
        return [equipment?.name, equipment?.loadingMeaning.title ?? "Legacy load as logged", equipment?.unit.rawValue ?? "lb"]
            .compactMap { $0 }.joined(separator: " · ")
    }
    public static func uniqueSessions(_ logs: [WorkoutSessionLog]) -> [WorkoutSessionLog] {
        var seen = Set<String>()
        return logs.filter { seen.insert($0.id ?? "\($0.routineID)|\($0.date.timeIntervalSinceReferenceDate)").inserted }
    }
    public static func recordCount(in log: WorkoutSessionLog, history: [WorkoutSessionLog]) -> Int {
        var seen = Set<String>()
        return log.completedExercises.reduce(0) { count, exercise in
            let name = normalizedName(exercise.exerciseName)
            let currentGroup = log.completedExercises.filter { normalizedName($0.exerciseName) == name }
            guard seen.insert(name).inserted,
                  let best = currentGroup.compactMap(bestSet).max(by: { strengthScore($0) < strengthScore($1) }),
                  currentGroup.allSatisfy({ compatible(exercise, $0) }) else { return count }
            let previous = uniqueSessions(history).filter { $0.date < log.date && (log.id == nil || $0.id != log.id) }
                .flatMap(\.completedExercises).filter { compatible(exercise, $0) }.compactMap(bestSet)
                .map(strengthScore).max()
            guard let previous, strengthScore(best) > previous * 1.005 else { return count }
            return count + 1
        }
    }
}
