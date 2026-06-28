import XCTest
@testable import MyFitPlate

final class RoutineEditorViewModelTests: XCTestCase {

    func testViewModelInitialization() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "Leg Day", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        XCTAssertEqual(vm.routineName, "Leg Day")
        XCTAssertTrue(vm.canSave)
        XCTAssertEqual(vm.exercises.count, 0)
    }

    func testCanSaveReturnsFalseWhenNameIsEmpty() {
        let routine = WorkoutRoutine(id: "123", userID: "user", name: "", dateCreated: Date(), exercises: [])
        let vm = RoutineEditorViewModel(routine: routine) { _ in }

        XCTAssertFalse(vm.canSave)

        vm.routineName = "   "
        XCTAssertFalse(vm.canSave)

        vm.routineName = "New Name"
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
}
