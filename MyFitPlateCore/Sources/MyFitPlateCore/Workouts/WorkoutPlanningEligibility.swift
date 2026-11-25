import Foundation

public enum WorkoutPlanningEquipment: String, Codable, Sendable {
    case fullGym, dumbbellsAndFloor, floorOnly

    public init?(request: String) {
        switch request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "full gym", "gym": self = .fullGym
        case "dumbbells only": self = .dumbbellsAndFloor
        case "bodyweight only": self = .floorOnly
        default: return nil
        }
    }

    public var explanation: String {
        switch self {
        case .fullGym: "Full gym; review the actual implements and loading conventions before training."
        case .dumbbellsAndFloor: "Dumbbells and floor space only. A bench, pull-up bar or cable station is not assumed."
        case .floorOnly: "Floor-based bodyweight work only. A bench, pull-up bar or machine is not assumed."
        }
    }
}

public enum WorkoutPlanningEligibilityError: LocalizedError {
    case invalid, unsupportedExercise(String), unavailableEquipment(String), unsupportedTarget(String), timeBudget(String, Int)
    public var errorDescription: String? {
        switch self {
        case .invalid: "The generated plan needs a valid name, weekly rotation and complete sessions. Your request and current program are kept."
        case .unsupportedExercise(let name): "The generated exercise ‘\(name)’ is not in the supported library. Generate again or build it manually."
        case .unavailableEquipment(let name): "‘\(name)’ needs equipment outside this request, or its implement is ambiguous. Generate again with explicit equipment."
        case .unsupportedTarget(let name): "‘\(name)’ has an open-ended or unsupported target. Generate again with numeric reps or time so the session can be reviewed."
        case .timeBudget(let name, let minutes): "‘\(name)’ is estimated at \(minutes) minutes, above your chosen budget. Reduce the work or increase the time and generate again."
        }
    }
}

public struct WorkoutProgramPlanningSummary: Equatable, Sendable {
    public let equipment: [String]
    public let ambiguousMovements: [String]
    public let minimumEstimatedMinutes: Int?
    public let maximumEstimatedMinutes: Int?
    public let manualTargetSets: Int

    public static func make(_ program: WorkoutProgram) -> WorkoutProgramPlanningSummary {
        let movements = program.routines.flatMap(\.exercises)
        let families = Set(movements.map { ExerciseList.equipment(for: $0.name) })
        let estimates = program.routines.compactMap { WorkoutPlanningEligibility.estimatedMinutes($0) }
        let manual = movements.reduce(0) { sum, exercise in
            sum + exercise.sets.filter {
                let target = $0.prescription ?? WorkoutPrescription.legacy($0.target, type: exercise.type)
                return target == nil || target?.kind == .manual || target?.kind == .amrap
            }.count
        }
        return WorkoutProgramPlanningSummary(equipment: families.filter { $0 != .flexible }.map(\.rawValue).sorted(),
            ambiguousMovements: Array(Set(movements.filter { ExerciseList.equipment(for: $0.name) == .flexible }.map(\.name))).sorted(),
            minimumEstimatedMinutes: estimates.count == program.routines.count ? estimates.min() : nil,
            maximumEstimatedMinutes: estimates.count == program.routines.count ? estimates.max() : nil, manualTargetSets: manual)
    }
}

public enum WorkoutPlanningEligibility {
    /// A deliberately narrow floor-only subset. Broad discovery labels such as
    /// bodyweight pull-ups do not establish that a user owns a bar or dip station.
    private static let floorMovements = Set([
        "push-up", "bodyweight squat", "plank", "side plank", "crunch", "bicycle crunch", "dead bug", "bird dog",
        "glute bridge", "frog pump", "leg raise", "mountain climber", "burpee", "high knees",
        "world's greatest stretch", "hip flexor stretch", "thoracic rotation", "wall slide", "scapular push-up",
        "couch stretch", "child's pose", "box breathing", "walking lunge", "reverse lunge"
    ])
    private static let dumbbellMovements = Set([
        "arnold press", "hammer curl", "goblet squat (dumbbell/kettlebell)", "farmer's carry"
    ])

    public static func isEligible(_ name: String, for equipment: WorkoutPlanningEquipment) -> Bool {
        if equipment == .fullGym { return true }
        let normalized = name.lowercased()
        if floorMovements.contains(normalized) { return true }
        guard equipment == .dumbbellsAndFloor else { return false }
        if dumbbellMovements.contains(normalized) { return true }
        // Bench-dependent titles are not silently treated as floor substitutions.
        return ExerciseList.equipment(for: name) == .dumbbell
            && !["bench", "fly", "pullover", "incline", "decline"].contains(where: normalized.contains)
    }

    public static func validate(_ program: WorkoutProgram, daysPerWeek: Int, equipment: WorkoutPlanningEquipment,
                                maximumSessionMinutes: Int? = nil) throws {
        let supported = Set(ExerciseList.entries.map(\.name))
        guard (1...7).contains(daysPerWeek), !program.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              program.name.count <= 200, (1...daysPerWeek).contains(program.routines.count),
              maximumSessionMinutes == nil || (10...180).contains(maximumSessionMinutes ?? 0) else {
            throw WorkoutPlanningEligibilityError.invalid
        }
        for routine in program.routines {
            guard !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (1...12).contains(routine.exercises.count) else { throw WorkoutPlanningEligibilityError.invalid }
            for exercise in routine.exercises {
                guard supported.contains(exercise.name) else { throw WorkoutPlanningEligibilityError.unsupportedExercise(exercise.name) }
                guard isEligible(exercise.name, for: equipment) else { throw WorkoutPlanningEligibilityError.unavailableEquipment(exercise.name) }
                guard (1...10).contains(exercise.sets.count) else { throw WorkoutPlanningEligibilityError.invalid }
                for set in exercise.sets {
                    guard let target = set.prescription ?? WorkoutPrescription.legacy(set.target, type: exercise.type),
                          target.validationMessage == nil, target.kind != .manual, target.kind != .amrap || maximumSessionMinutes == nil,
                          target.isSupported(for: exercise.type) else { throw WorkoutPlanningEligibilityError.unsupportedTarget(exercise.name) }
                }
                for alternative in exercise.alternatives ?? [] {
                    guard supported.contains(alternative), isEligible(alternative, for: equipment) else {
                        throw WorkoutPlanningEligibilityError.unavailableEquipment(alternative)
                    }
                }
            }
            if let maximumSessionMinutes {
                guard let estimate = estimatedMinutes(routine) else { throw WorkoutPlanningEligibilityError.unsupportedTarget(routine.name) }
                guard estimate <= maximumSessionMinutes else { throw WorkoutPlanningEligibilityError.timeBudget(routine.name, estimate) }
            }
        }
    }

    /// Planning estimate, not a measured promise: 5 minutes warm-up, 1 minute setup
    /// per movement, explicit timed work, or 4 seconds per upper-target rep (at
    /// least 30 seconds a set), plus all prescribed between-set rests.
    public static func estimatedMinutes(_ routine: WorkoutRoutine) -> Int? {
        guard !routine.exercises.isEmpty else { return nil }
        var seconds = 300.0 + Double(routine.exercises.count) * 60
        for exercise in routine.exercises {
            guard !exercise.sets.isEmpty else { return nil }
            for set in exercise.sets {
                guard let target = set.prescription ?? WorkoutPrescription.legacy(set.target, type: exercise.type),
                      target.validationMessage == nil else { return nil }
                switch target.kind {
                case .repetitions:
                    guard let upper = target.upperBound ?? target.lowerBound else { return nil }
                    seconds += max(30, upper * 4)
                case .duration:
                    guard let upper = target.upperBound ?? target.lowerBound else { return nil }
                    seconds += upper
                case .distance, .amrap, .manual: return nil
                }
            }
            seconds += Double(max(exercise.sets.count - 1, 0)) * Double(max(exercise.restTimeInSeconds, 0))
        }
        guard seconds.isFinite, seconds < 7 * 86_400 else { return nil }
        return Int(ceil(seconds / 60))
    }
}
