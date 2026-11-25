import Foundation

public enum WorkoutAIContractError: LocalizedError {
    case version, movement(String), target(String), policy(String), equipment(String), reference, constraints(String)
    public var errorDescription: String? {
        switch self {
        case .constraints(let message): message
        case .version: "The generated proposal used an unsupported format. Your request is kept; generate again."
        case .movement(let value): "The proposal did not identify the exact supported variant of ‘\(value)’. Choose an approved movement and generate again."
        case .target(let value): "The numeric target or rest for ‘\(value)’ could not be verified. Generate bounded repetitions or seconds."
        case .policy(let value): "The progression policy for ‘\(value)’ is unsupported or does not match its loading convention. Review the setup."
        case .equipment(let value): "The proposal used an unconfirmed implement for ‘\(value)’. Confirm that movement in your selected gym or choose another."
        case .reference: "A generated proposal cannot invent a training maximum. Add your own named percentage reference in the normal editor after review."
        }
    }
}
public enum WorkoutAIContract {
    public static func validateMovementChoices(preferred: [String], avoided: [String]) throws {
        guard preferred.count <= 50, avoided.count <= 50,
              (preferred + avoided).allSatisfy({ WorkoutMovementCatalog.canonicalName($0) == $0 }),
              Set(preferred).isDisjoint(with: Set(avoided)) else {
            throw WorkoutAIContractError.constraints("Choose supported catalog movements and remove any movement listed under both Prefer and Avoid.")
        }
    }
    public static func map(_ response: AIProgramResponse, userID: String, daysPerWeek: Int,
                           equipment: WorkoutPlanningEquipment, maximumSessionMinutes: Int?,
                           gym: StrengthGymProfile? = nil, confirmedMovements: [String: String] = [:], preferredMovements: [String] = [], avoidedMovements: [String] = []) throws -> WorkoutProgram {
        try validateMovementChoices(preferred: preferredMovements, avoided: avoidedMovements)
        guard response.schemaVersion == 2 else { throw WorkoutAIContractError.version }
        if let gym, !gym.isValid { throw WorkoutAIContractError.equipment(gym.name) }
        for routine in response.routines {
            for exercise in routine.exercises {
                guard !avoidedMovements.contains(exercise.name), !(exercise.alternatives ?? []).contains(where: avoidedMovements.contains) else {
                    throw WorkoutAIContractError.constraints("The proposal includes ‘\(exercise.name)’ or an alternative you chose to avoid. Your request is kept; regenerate or adjust the constraints.")
                }
                guard WorkoutMovementCatalog.canonicalName(exercise.name) == exercise.name,
                      let identity = WorkoutMovementCatalog.identity(for: exercise.name),
                      exercise.movementID == identity.movementID, exercise.variantID == identity.variantID else { throw WorkoutAIContractError.movement(exercise.name) }
                if let entry = ExerciseList.entries.first(where: { $0.name == exercise.name }) {
                    let expectedType = RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category)
                    guard exercise.type.rawValue == expectedType.rawValue else { throw WorkoutAIContractError.target(exercise.name) }
                }
                for alternative in exercise.alternatives ?? [] {
                    guard WorkoutMovementCatalog.canonicalName(alternative) == alternative,
                          gym == nil || confirmedMovements[alternative].flatMap({ gym?.equipment(for: $0) }) != nil
                            || WorkoutPlanningEligibility.isEligible(alternative, for: .floorOnly) else { throw WorkoutAIContractError.equipment(alternative) }
                }
                guard let rest = exercise.restSeconds, (0...900).contains(rest) else { throw WorkoutAIContractError.target(exercise.name) }
                if exercise.type == .strength, exercise.sets.count > 1, rest < 30 { throw WorkoutAIContractError.target(exercise.name) }
                for set in exercise.sets {
                    guard let target = set.prescription, target.validationMessage == nil,
                          target.isSupported(for: exercise.type), target.kind != .manual, target.kind != .amrap else { throw WorkoutAIContractError.target(exercise.name) }
                    guard target.loadReference == nil, target.loadPercentage == nil else { throw WorkoutAIContractError.reference }
                    guard let displayed = WorkoutPrescription.legacy(set.target, type: exercise.type),
                          displayed.kind == target.kind, displayed.lowerBound == target.lowerBound,
                          (displayed.upperBound ?? displayed.lowerBound) == (target.upperBound ?? target.lowerBound) else { throw WorkoutAIContractError.target(exercise.name) }
                }
                if exercise.type == .strength {
                    guard let policy = exercise.progressionPolicy, policy.isValid, policy.kind != .percentage else { throw WorkoutAIContractError.policy(exercise.name) }
                } else if exercise.progressionPolicy != nil { throw WorkoutAIContractError.policy(exercise.name) }
                if let gym, let implement = confirmedMovements[exercise.name] {
                    guard exercise.equipmentProfileID == gym.id, exercise.equipmentImplementID == implement,
                          gym.equipment(for: implement) != nil else { throw WorkoutAIContractError.equipment(exercise.name) }
                } else {
                    guard exercise.equipmentProfileID == nil, exercise.equipmentImplementID == nil,
                          gym == nil || WorkoutPlanningEligibility.isEligible(exercise.name, for: .floorOnly) else { throw WorkoutAIContractError.equipment(exercise.name) }
                }
            }
        }
        let program = WorkoutRules.mapResponseToProgram(response, userID: userID)
        for routine in program.routines {
            for index in routine.exercises.indices {
                let policy = routine.exercises[index].progressionPolicy
                if let gym, let implement = confirmedMovements[routine.exercises[index].name] {
                    routine.exercises[index].loadEquipment = gym.equipment(for: implement)
                } else if policy?.kind == .bodyweight {
                    guard ExerciseList.equipment(for: routine.exercises[index].name) == .bodyweight else { throw WorkoutAIContractError.policy(routine.exercises[index].name) }
                    routine.exercises[index].loadEquipment = StrengthEquipment(loadingMeaning: .bodyweightOnly, availableWeights: [0])
                }
                if let message = policy?.validationMessage(for: routine.exercises[index]) {
                    throw WorkoutAIContractError.policy(message)
                }
            }
        }
        try WorkoutPlanningEligibility.validate(program, daysPerWeek: daysPerWeek, equipment: equipment, maximumSessionMinutes: maximumSessionMinutes)
        return program
    }
}
