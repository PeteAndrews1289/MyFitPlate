import XCTest
@testable import MyFitPlateCore

final class WorkoutModelTests: XCTestCase {

    func testWorkoutRoutineDeepCopyCreatesIndependentRoutine() throws {
        let original = WorkoutRoutine(
            id: "routine-1",
            userID: "user-1",
            name: "Push",
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [
                RoutineExercise(
                    name: "Bench Press",
                    type: .strength,
                    sets: [ExerciseSet(isCompleted: true, target: "8 reps", reps: 8, weight: 185)],
                    notes: "Keep shoulders packed",
                    restTimeInSeconds: 120,
                    alternatives: ["Dumbbell Bench Press"],
                    targetSets: 3,
                    targetReps: "6-8"
                )
            ],
            notes: "Heavy day"
        )

        let copy = try XCTUnwrap(original.deepCopy())
        copy.name = "Copied"
        copy.exercises[0].name = "Incline Bench Press"
        copy.exercises[0].sets[0].weight = 165

        XCTAssertEqual(original.id, copy.id)
        XCTAssertEqual(original.name, "Push")
        XCTAssertEqual(original.exercises[0].name, "Bench Press")
        XCTAssertEqual(original.exercises[0].sets[0].weight, 185)
        XCTAssertEqual(copy.name, "Copied")
        XCTAssertEqual(copy.exercises[0].sets[0].weight, 165)
    }

    func testWorkoutRoutineCodableRoundTripPreservesExerciseDetails() throws {
        let routine = WorkoutRoutine(
            id: "routine-2",
            userID: "user-2",
            name: "Conditioning",
            dateCreated: Date(timeIntervalSince1970: 1_700_010_000),
            exercises: [
                RoutineExercise(
                    id: "exercise-1",
                    name: "Rowing Machine",
                    type: .cardio,
                    sets: [
                        ExerciseSet(
                            id: "set-1",
                            isCompleted: true,
                            target: "20 min",
                            previousPerformance: "18 min",
                            isWarmup: false,
                            reps: 0,
                            weight: 0,
                            distance: 2.5,
                            durationInSeconds: 1_200
                        )
                    ],
                    notes: "Steady pace",
                    restTimeInSeconds: 0,
                    alternatives: ["Bike"],
                    targetSets: 1,
                    targetReps: "20 min"
                )
            ],
            notes: "Zone 2"
        )

        let data = try JSONEncoder().encode(routine)
        let decoded = try JSONDecoder().decode(WorkoutRoutine.self, from: data)

        XCTAssertEqual(decoded.id, routine.id)
        XCTAssertEqual(decoded.name, routine.name)
        XCTAssertEqual(decoded.exercises[0].type, .cardio)
        XCTAssertEqual(decoded.exercises[0].sets[0].distance, 2.5)
        XCTAssertEqual(decoded.exercises[0].sets[0].durationInSeconds, 1_200)
        XCTAssertEqual(decoded.exercises[0].alternatives, ["Bike"])
    }

    func testRoutineEqualityAndHashingUseIdentifierOnly() {
        let first = WorkoutRoutine(id: "same", userID: "user-1", name: "A", dateCreated: Date(), exercises: [])
        let second = WorkoutRoutine(id: "same", userID: "user-2", name: "B", dateCreated: Date(), exercises: [])
        let third = WorkoutRoutine(id: "different", userID: "user-1", name: "A", dateCreated: Date(), exercises: [])

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
        XCTAssertEqual(Set([first, second, third]).count, 2)
    }

    func testRoutineEditorDefaultsInferTypesAndFormatTargets() {
        XCTAssertEqual(RoutineEditorDefaults.defaults(for: .strength).sets, 3)
        XCTAssertEqual(RoutineEditorDefaults.defaults(for: .cardio).target, "20 min")
        XCTAssertEqual(RoutineEditorDefaults.defaults(for: .flexibility).rest, 30)

        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "10"), "10 reps")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .strength, target: "AMRAP"), "AMRAP")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .cardio, target: "2 miles"), "2 miles")
        XCTAssertEqual(RoutineEditorDefaults.setTarget(for: .flexibility, target: "  "), "45 sec")

        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Jump Rope", category: nil), .cardio)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Hamstring Stretch", category: nil), .flexibility)
        XCTAssertEqual(RoutineEditorDefaults.inferredType(name: "Goblet Squat", category: "Legs"), .strength)

        XCTAssertEqual(RoutineEditorDefaults.restLabel(0), "No rest")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(45), "45s")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(120), "2m")
        XCTAssertEqual(RoutineEditorDefaults.restLabel(150), "2m 30s")
    }

    func testExercisePickerEntriesSortByCategoryThenName() {
        let entries = [
            ExercisePickerEntry(name: "Squat", category: "Legs"),
            ExercisePickerEntry(name: "Bench Press", category: "Chest"),
            ExercisePickerEntry(name: "Incline Press", category: "Chest")
        ]

        XCTAssertEqual(entries.sorted().map(\.name), ["Bench Press", "Incline Press", "Squat"])
        XCTAssertEqual(ExercisePickerEntry(name: "Bench Press", category: "Chest").id, "Chest-Bench Press")
    }

    func testStringHelpersTrimAndCollapseEmptyArrays() {
        XCTAssertEqual("  Bench Press \n".trimmed, "Bench Press")
        XCTAssertNil([String]().nilIfEmpty)
        XCTAssertEqual(["Squat"].nilIfEmpty, ["Squat"])
    }
}
