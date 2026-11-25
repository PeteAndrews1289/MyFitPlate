import XCTest
@testable import MyFitPlateCore

final class RoutineEditorViewModelTests: XCTestCase {

    func testIdentityBasedReorderPreservesSetPayloadAndIgnoresExternalDrop() throws {
        let first = RoutineExercise(name: "Squat", type: .strength, sets: [ExerciseSet(target: "5 reps")])
        let second = RoutineExercise(name: "Deadlift", type: .strength, sets: [ExerciseSet(target: "8 reps")])
        let third = RoutineExercise(name: "Plank", type: .flexibility, sets: [ExerciseSet(target: "30 sec")])
        let routine = WorkoutRoutine(id: "rotation", userID: "user", name: "Session", dateCreated: Date(), exercises: [first, second, third])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }
        let originalPayloads = try Dictionary(uniqueKeysWithValues: vm.exercises.map { ($0.id, try PlanFingerprint.make($0)) })
        vm.moveExercise(id: first.id, to: third.id)
        XCTAssertEqual(vm.exercises.map(\.id), [second.id, third.id, first.id])
        vm.moveExercise(id: "external-or-deleted-row", to: third.id)
        XCTAssertEqual(vm.exercises.map(\.id), [second.id, third.id, first.id])
        for exercise in vm.exercises { XCTAssertEqual(try PlanFingerprint.make(exercise), originalPayloads[exercise.id]) }
        XCTAssertEqual(routine.exercises.map(\.id), [first.id, second.id, third.id], "Reordering a draft never edits the saved routine reference")
    }

    func testViewModelInitialization() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Leg Day", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        XCTAssertEqual(vm.routineName, "Leg Day")
        XCTAssertFalse(vm.canSave, "A named but empty routine cannot be played")
        XCTAssertEqual(vm.exercises.count, 0)
    }

    func testCanSaveReturnsFalseWhenNameIsEmpty() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        XCTAssertFalse(vm.canSave)

        vm.routineName = "   "
        XCTAssertFalse(vm.canSave)

        vm.routineName = "New Name"
        XCTAssertFalse(vm.canSave)
        vm.addExercise(from: ExercisePickerDraft(name: "Squat", category: nil, type: .strength))
        XCTAssertTrue(vm.canSave)
    }

    func testApplyTemplate() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        let template = RoutineEditorTemplate.templates.first(where: { $0.name == "Push Day" })!
        vm.applyTemplate(template)

        XCTAssertEqual(vm.routineName, "Push Day")
        XCTAssertEqual(vm.exercises.count, 4)
        XCTAssertEqual(vm.exercises[0].name, "Barbell Bench Press")
        XCTAssertEqual(vm.exercises[0].type, ExerciseType.strength)
    }

    func testAddExerciseFromDraft() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        let draft = ExercisePickerDraft(name: "Running", category: "Cardio", type: .cardio)
        vm.addExercise(from: draft)

        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises[0].name, "Running")
        XCTAssertEqual(vm.exercises[0].type, ExerciseType.cardio)
        XCTAssertEqual(vm.exercises[0].targetSets, 1)
    }

    func testDuplicateExercise() {
        let ex = RoutineExercise(name: "Squat", type: .strength, sets: [ExerciseSet(target: "10 reps")], restTimeInSeconds: 60, targetSets: 1, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        XCTAssertEqual(vm.exercises.count, 1)
        vm.duplicateExercise(vm.exercises[0])

        XCTAssertEqual(vm.exercises.count, 2)
        XCTAssertEqual(vm.exercises[1].name, "Squat")
        XCTAssertNotEqual(vm.exercises[0].id, vm.exercises[1].id)
    }

    func testDeleteExercise() {
        let ex1 = RoutineExercise(name: "Squat", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let ex2 = RoutineExercise(name: "Deadlift", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex1, ex2])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        vm.deleteExercise(ex1)

        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises[0].name, "Deadlift")
    }

    func testMoveExercise() {
        let ex1 = RoutineExercise(name: "Squat", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let ex2 = RoutineExercise(name: "Deadlift", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex1, ex2])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        vm.moveExercise(ex1, direction: RoutineMoveDirection.down)

        XCTAssertEqual(vm.exercises[0].name, "Deadlift")
        XCTAssertEqual(vm.exercises[1].name, "Squat")

        vm.moveExercise(ex2, direction: RoutineMoveDirection.down)
        
        XCTAssertEqual(vm.exercises[0].name, "Squat")
        XCTAssertEqual(vm.exercises[1].name, "Deadlift")
    }

    func testUpdateExercise() {
        let ex1 = RoutineExercise(name: "Squat", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex1])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }
        
        var updated = ex1
        updated.name = "Front Squat"
        vm.updateExercise(updated)
        
        XCTAssertEqual(vm.exercises[0].name, "Front Squat")
    }

    func testSaveRoutine() {
        let ex1 = RoutineExercise(name: "Squat", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex1])
        
        var savedRoutine: WorkoutRoutine?
        let vm = RoutineEditorViewModel(routine: routine) { r in
            savedRoutine = r
        }
        
        vm.routineName = "New Name  "
        vm.routineNotes = " Notes here "
        vm.saveRoutine()
        
        XCTAssertNotNil(savedRoutine)
        XCTAssertEqual(savedRoutine?.name, "New Name")
        XCTAssertEqual(savedRoutine?.notes, "Notes here")
    }

    func testEstimatedMinutes() {
        let ex1 = RoutineExercise(name: "Squat", type: .strength, sets: [], restTimeInSeconds: 60, targetSets: 3, targetReps: "10")
        let ex2 = RoutineExercise(name: "Bench", type: .strength, sets: [], restTimeInSeconds: 90, targetSets: 4, targetReps: "10")
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Routine", dateCreated: Date(), exercises: [ex1, ex2])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }
        
        // Squat: 3 sets -> 3 * 55s active = 165s
        //        rest -> 2 * 60s = 120s
        // Bench: 4 sets -> 4 * 55s active = 220s
        //        rest -> 3 * 90s = 270s
        // Total: 165 + 120 + 220 + 270 = 775s
        // 775 / 60 = 12.91 -> 13 mins
        XCTAssertEqual(vm.estimatedMinutes, 13)
        XCTAssertEqual(vm.totalSetCount, 7)
    }
}
