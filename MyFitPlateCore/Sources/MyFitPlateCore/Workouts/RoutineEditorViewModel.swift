import Combine
import SwiftUI

public final class RoutineEditorViewModel: ObservableObject {
    private var sourceRoutine: WorkoutRoutine
    private let onSaveCallback: (WorkoutRoutine) -> Void

    @Published public var routineName: String
    @Published public var routineNotes: String
    @Published public var exercises: [RoutineExercise]
    @Published public var showingExercisePicker = false
    @Published public var exerciseToEdit: RoutineExercise?

    public var canSave: Bool {
        validationMessage == nil
    }

    public var validationMessage: String? {
        if routineName.trimmed.isEmpty { return "Name this routine before saving." }
        if exercises.isEmpty { return "Add at least one exercise before saving." }
        if exercises.contains(where: { $0.name.trimmed.isEmpty || $0.sets.isEmpty }) {
            return "Each exercise needs a name and at least one set."
        }
        return nil
    }

    public var hasChanges: Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(draft)) != (try? encoder.encode(sourceRoutine))
    }

    public var draft: WorkoutRoutine {
        WorkoutRoutine(
            id: sourceRoutine.id, userID: sourceRoutine.userID, name: routineName.trimmed,
            dateCreated: sourceRoutine.dateCreated, exercises: exercises,
            notes: routineNotes.trimmed.isEmpty ? nil : routineNotes.trimmed
        )
    }

    public var checkpoint: RoutineEditorDraft {
        RoutineEditorDraft(routine: draft, baseline: sourceRoutine)
    }

    public func restore(_ checkpoint: RoutineEditorDraft) {
        sourceRoutine = checkpoint.baseline.deepCopy() ?? checkpoint.baseline
        routineName = checkpoint.routine.name
        routineNotes = checkpoint.routine.notes ?? ""
        exercises = checkpoint.routine.exercises
    }

    public var totalSetCount: Int {
        exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
    }

    public var estimatedMinutes: Int {
        let activeSeconds = totalSetCount * 55
        let restSeconds = exercises.reduce(0) { partial, exercise in
            let sets = max(exercise.sets.count, exercise.targetSets)
            return partial + max(sets - 1, 0) * max(exercise.restTimeInSeconds, 0)
        }
        guard totalSetCount > 0 else { return 0 }
        return max(5, Int(ceil(Double(activeSeconds + restSeconds) / 60.0)))
    }

    public init(routine: WorkoutRoutine, onSave: @escaping (WorkoutRoutine) -> Void) {
        self.sourceRoutine = routine.deepCopy() ?? routine
        self.routineName = routine.name
        self.routineNotes = routine.notes ?? ""
        self.exercises = routine.exercises
        self.onSaveCallback = onSave
    }

    public func saveRoutine() {
        onSaveCallback(draft)
    }

    public func applyTemplate(_ template: RoutineEditorTemplate) {
        if routineName.trimmed.isEmpty || routineName == "New Routine" {
            routineName = template.name
        }
        exercises.append(contentsOf: template.exercises.map(makeExercise))
        HapticManager.instance.feedback(.medium)
    }

    public func addExercise(from draft: ExercisePickerDraft) {
        var exercise = makeExercise(name: draft.name, category: draft.category, type: draft.type)
        exercise.movementIdentity = draft.movementIdentity ?? WorkoutMovementCatalog.identity(for: draft.name)
        exercises.append(exercise)
        HapticManager.instance.feedback(.light)
    }

    public func duplicateExercise(_ exercise: RoutineExercise) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        var copy = exercise
        copy.id = UUID().uuidString
        copy.groupPlan = nil; copy.supersetGroupID = nil
        copy.sets = copy.sets.map { set in
            var newSet = set
            newSet.id = UUID().uuidString
            newSet.isCompleted = false
            newSet.reps = 0
            newSet.weight = 0
            newSet.distance = 0
            newSet.durationInSeconds = 0
            return newSet
        }
        exercises.insert(copy, at: index + 1)
    }

    public func deleteExercise(_ exercise: RoutineExercise) {
        exercises.removeAll { $0.id == exercise.id }
        exercises = WorkoutExerciseGroupRules.repairing(exercises)
    }

    public func moveExercise(_ exercise: RoutineExercise, direction: RoutineMoveDirection) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = max(index - 1, 0)
        case .down:
            targetIndex = min(index + 1, exercises.count - 1)
        }
        guard targetIndex != index else { return }
        exercises.move(fromOffsets: IndexSet(integer: index), toOffset: targetIndex > index ? targetIndex + 1 : targetIndex)
    }

    public func moveExercise(id: String, to destinationID: String) {
        guard let source = exercises.firstIndex(where: { $0.id == id }),
              let destination = exercises.firstIndex(where: { $0.id == destinationID }), source != destination else { return }
        exercises.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
    }

    public func updateExercise(_ updatedExercise: RoutineExercise) {
        if let index = exercises.firstIndex(where: { $0.id == updatedExercise.id }) {
            exercises[index] = updatedExercise
        }
    }

    private func makeExercise(_ spec: RoutineEditorExerciseSpec) -> RoutineExercise {
        makeExercise(name: spec.name, category: spec.category, type: spec.type)
    }

    private func makeExercise(name: String, category: String?, type: ExerciseType) -> RoutineExercise {
        let defaults = RoutineEditorDefaults.defaults(for: type)
        let setTarget = RoutineEditorDefaults.setTarget(for: type, target: defaults.target)
        var exercise = RoutineExercise(
            name: name,
            type: type,
            sets: (0..<defaults.sets).map { _ in ExerciseSet(target: setTarget) },
            restTimeInSeconds: defaults.rest,
            targetSets: defaults.sets,
            targetReps: defaults.target
        )
        exercise.movementIdentity = WorkoutMovementCatalog.identity(for: name)
        return exercise
    }
}
