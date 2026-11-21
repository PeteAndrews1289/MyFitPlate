import Foundation

public struct StrengthWarmupStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var fraction: Double
    public var reps: Int
    public var restSeconds: Int
    public init(id: String = UUID().uuidString, fraction: Double, reps: Int, restSeconds: Int) {
        self.id = id; self.fraction = fraction; self.reps = reps; self.restSeconds = restSeconds
    }
}

public struct StrengthWarmupFormula: Codable, Equatable, Sendable {
    public var steps: [StrengthWarmupStep]
    public init(steps: [StrengthWarmupStep]) { self.steps = steps }
    public static var standard: Self {
        Self(steps: [StrengthWarmupStep(fraction: 0.3, reps: 8, restSeconds: 45),
                     StrengthWarmupStep(fraction: 0.55, reps: 5, restSeconds: 60),
                     StrengthWarmupStep(fraction: 0.8, reps: 3, restSeconds: 90)])
    }
    public var isValid: Bool {
        (1...5).contains(steps.count) && Set(steps.map(\.id)).count == steps.count
            && steps.allSatisfy { $0.fraction.isFinite && (0.05...0.95).contains($0.fraction)
                && (1...20).contains($0.reps) && (15...300).contains($0.restSeconds) }
            && zip(steps, steps.dropFirst()).allSatisfy { $0.fraction < $1.fraction }
    }
}

public struct StrengthGeneratedWarmup: Codable, Equatable, Sendable {
    public let rampID: String
    public let workingWeight: Double
    public let proposedWeight: Double
    public let proposedReps: Int
    public let restSeconds: Int

    public func isUntouched(_ set: ExerciseSet) -> Bool {
        !set.isCompleted && set.resolvedSetType == .warmup
            && set.weight == proposedWeight && set.reps == proposedReps && set.target == String(proposedReps)
            && set.distance == 0 && set.durationInSeconds == 0 && set.effort == nil && set.prescription == nil
    }
}

public struct StrengthWarmupPlan {
    public let exerciseID: String
    public let baseline: String
    public let workingWeight: Double
    public let formula: StrengthWarmupFormula
    public let sets: [ExerciseSet]
    public let replacingIDs: Set<String>
    public let retainedWarmupCount: Int
}

public enum StrengthWarmupRules {
    public static func prepare(exercise: RoutineExercise, workingWeight: Double,
                               formula: StrengthWarmupFormula = .standard) throws -> StrengthWarmupPlan {
        guard exercise.type == .strength, let equipment = exercise.loadEquipment, equipment.isValid,
              equipment.loadingMeaning == .total || equipment.loadingMeaning == .perHand,
              workingWeight.isFinite, workingWeight > 0, workingWeight <= 10_000,
              equipment.contains(workingWeight) else { throw StrengthSessionToolsError.unsupportedWarmup }
        guard formula.isValid else { throw StrengthSessionToolsError.invalid }
        let removable = exercise.sets.filter { $0.generatedWarmup?.isUntouched($0) == true }
        let removableIDs = Set(removable.map(\.id))
        let retained = exercise.sets.filter { $0.resolvedSetType == .warmup && !removableIDs.contains($0.id) }
        let rampID = UUID().uuidString
        var sets: [ExerciseSet] = []
        let loads = equipment.attainableLoads.filter { $0 > 0 && $0 < workingWeight - 0.01 }
        guard let minimum = loads.first else { throw StrengthSessionToolsError.unavailable }
        for step in formula.steps {
            let desired = max(minimum, workingWeight * step.fraction)
            guard let weight = loads.last(where: { $0 <= desired + 0.01 }) else { continue }
            if sets.contains(where: { abs($0.weight - weight) < 0.01 }) { continue }
            // Logged, manual and edited preparation stays intact. Do not generate
            // another identical row; only untouched generated rows are replaced.
            if retained.contains(where: { abs($0.weight - weight) < 0.01 && $0.reps == step.reps }) { continue }
            let provenance = StrengthGeneratedWarmup(rampID: rampID, workingWeight: workingWeight,
                proposedWeight: weight, proposedReps: step.reps, restSeconds: step.restSeconds)
            sets.append(ExerciseSet(target: String(step.reps), isWarmup: true, setType: .warmup,
                                    generatedWarmup: provenance, reps: step.reps, weight: weight))
        }
        return StrengthWarmupPlan(exerciseID: exercise.id, baseline: try PlanFingerprint.make(exercise),
            workingWeight: workingWeight, formula: formula, sets: sets,
            replacingIDs: Set(removable.map(\.id)), retainedWarmupCount: retained.count)
    }

    public static func applying(_ plan: StrengthWarmupPlan, to exercise: RoutineExercise) throws -> RoutineExercise {
        guard plan.exerciseID == exercise.id, try plan.baseline == PlanFingerprint.make(exercise),
              plan.formula.isValid, !plan.sets.isEmpty else { throw StrengthSessionToolsError.changed }
        var updated = exercise
        updated.sets.removeAll { plan.replacingIDs.contains($0.id) && $0.generatedWarmup?.isUntouched($0) == true }
        let insertion = updated.sets.firstIndex(where: { $0.resolvedSetType != .warmup }) ?? updated.sets.endIndex
        updated.sets.insert(contentsOf: plan.sets, at: insertion)
        return updated
    }
}

@MainActor
public final class StrengthWarmupPreferenceStore {
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func load(userID: String) throws -> StrengthWarmupFormula? {
        guard DIContainer.shared.authService.currentUserID == userID else { throw StrengthSessionToolsError.accountChanged }
        let saved = try store.load(StrengthWarmupFormula.self, userID: userID, scope: "strength-warmup-formula")?.value
        guard saved?.isValid != false else { throw StrengthSessionToolsError.invalid }
        return saved
    }
    public func save(_ formula: StrengthWarmupFormula, userID: String) throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw StrengthSessionToolsError.accountChanged }
        guard formula.isValid else { throw StrengthSessionToolsError.invalid }
        try store.save(formula, userID: userID, scope: "strength-warmup-formula")
    }
}
