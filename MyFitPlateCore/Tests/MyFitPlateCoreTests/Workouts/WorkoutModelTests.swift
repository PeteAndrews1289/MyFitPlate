import XCTest
@testable import MyFitPlateCore

final class WorkoutModelTests: XCTestCase {
    // Older installed versions stored targets on each set, before the exercise-level
    // targetSets/targetReps fields existed. Keep this fixture independent of today's encoder.
    private let legacyExerciseJSON = """
    {
      "id": "legacy-exercise", "name": "Bench Press", "type": "Strength",
      "restTimeInSeconds": 120, "notes": "Keep my original targets",
      "sets": [
        {"id": "set-1", "isCompleted": true, "isWarmup": false, "target": "6-8",
         "reps": 8, "weight": 135, "distance": 0, "durationInSeconds": 0},
        {"id": "set-2", "isCompleted": false, "isWarmup": false, "target": "6-8",
         "reps": 6, "weight": 130, "distance": 0, "durationInSeconds": 0}
      ]
    }
    """

    func testLegacyProgramPreservesProgressAndInfersTargetsFromItsSavedSets() throws {
        let json = """
        {
          "id": "original-program", "userID": "owner", "name": "PHUL",
          "dateCreated": 700000000, "startDate": 700000000,
          "daysOfWeek": [2, 3, 5, 6], "currentProgressIndex": 12, "skippedIndices": [2],
          "routines": [
            {"id": "original-routine", "userID": "owner", "name": "Upper Power",
             "dateCreated": 700000000, "exercises": [\(legacyExerciseJSON)]}
          ]
        }
        """
        let program = try JSONDecoder().decode(WorkoutProgram.self, from: Data(json.utf8))
        XCTAssertEqual(program.id, "original-program")
        XCTAssertEqual(program.currentProgressIndex, 12)
        XCTAssertEqual(program.skippedIndices, [2])
        XCTAssertEqual(program.routines[0].id, "original-routine")
        let exercise = program.routines[0].exercises[0]
        XCTAssertEqual(exercise.id, "legacy-exercise")
        XCTAssertEqual(exercise.targetSets, 2)
        XCTAssertEqual(exercise.targetReps, "6-8")
        XCTAssertEqual(exercise.sets.map(\.weight), [135, 130])
        XCTAssertEqual(exercise.sets.map(\.isCompleted), [true, false])
        XCTAssertEqual(exercise.notes, "Keep my original targets")
        let restored = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(program))
        XCTAssertEqual(restored.currentProgressIndex, 12)
        XCTAssertEqual(restored.routines[0].exercises[0].sets.map(\.id), ["set-1", "set-2"])
    }

    func testLegacyWorkoutHistoryDecodesTheEmbeddedExerciseWithoutNewTargets() throws {
        let json = """
        {"id": "old-session", "date": 700000000, "routineID": "original-routine",
         "completedExercises": [
           {"id": "completed", "exerciseName": "Bench Press", "exercise": \(legacyExerciseJSON),
            "sets": [{"id": "completed-set", "reps": 8, "weight": 135}]}
         ]}
        """
        let session = try JSONDecoder().decode(WorkoutSessionLog.self, from: Data(json.utf8))
        XCTAssertEqual(session.routineID, "original-routine")
        XCTAssertEqual(session.completedExercises[0].exercise.targetSets, 2)
        XCTAssertEqual(session.completedExercises[0].sets[0].weight, 135)
    }

    func testExistingExerciseTargetsArePreservedAndMalformedTargetsStillFail() throws {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacyExerciseJSON.utf8)) as? [String: Any])
        fields["targetSets"] = 4
        fields["targetReps"] = "10-12"
        let exercise = try JSONDecoder().decode(RoutineExercise.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertEqual(exercise.targetSets, 4)
        XCTAssertEqual(exercise.targetReps, "10-12")
        fields["targetSets"] = "invalid"
        XCTAssertThrowsError(try JSONDecoder().decode(RoutineExercise.self, from: JSONSerialization.data(withJSONObject: fields)))
    }

    func testOldestStrengthRoutinesGetStableIdentitiesWithoutLosingSetValues() throws {
        var exercise = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacyExerciseJSON.utf8)) as? [String: Any])
        exercise.removeValue(forKey: "type")
        exercise["sets"] = try XCTUnwrap(exercise["sets"] as? [[String: Any]]).map { savedSet in
            var set = savedSet
            set.removeValue(forKey: "distance")
            set.removeValue(forKey: "durationInSeconds")
            return set
        }
        let routine: [String: Any] = [
            "userID": "owner", "name": "Legacy strength", "dateCreated": 700000000,
            "exercises": [exercise]
        ]
        let data = try JSONSerialization.data(withJSONObject: [routine, routine])
        let firstRead = try JSONDecoder().decode([WorkoutRoutine].self, from: data)
        let secondRead = try JSONDecoder().decode([WorkoutRoutine].self, from: data)
        XCTAssertEqual(firstRead.map(\.id), secondRead.map(\.id))
        XCTAssertNotEqual(firstRead[0].id, firstRead[1].id)
        XCTAssertEqual(firstRead[0].exercises[0].type, .strength)
        XCTAssertEqual(firstRead[0].exercises[0].sets.map(\.weight), [135, 130])
        XCTAssertEqual(firstRead[0].exercises[0].sets.map(\.distance), [0, 0])
        XCTAssertEqual(firstRead[0].exercises[0].sets.map(\.durationInSeconds), [0, 0])
        XCTAssertEqual(firstRead[0].exercises[0].restTimeInSeconds, 120)
        let roundTrip = try JSONDecoder().decode([WorkoutRoutine].self, from: JSONEncoder().encode(firstRead))
        XCTAssertEqual(roundTrip.map(\.id), firstRead.map(\.id))
    }

    func testLegacyExerciseWithoutAnySetsUsesTheExistingEditorDefaults() throws {
        var exercise = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacyExerciseJSON.utf8)) as? [String: Any])
        exercise["sets"] = []
        let decoded = try JSONDecoder().decode(RoutineExercise.self, from: JSONSerialization.data(withJSONObject: exercise))
        XCTAssertEqual(decoded.targetSets, 3)
        XCTAssertEqual(decoded.targetReps, "8-12")
        XCTAssertTrue(decoded.sets.isEmpty)
    }

    func testEarliestStandaloneRoutineUsesDefaultsForLaterRestAndWarmupFields() throws {
        let json = """
        {"id": "old-routine", "userID": "owner", "name": "Early saved routine",
         "dateCreated": 700000000, "exercises": [
           {"id": "old-exercise", "name": "Row", "sets": [
             {"id": "old-set", "isCompleted": true, "reps": 10, "weight": 75}
           ]}
         ]}
        """
        let routine = try JSONDecoder().decode(WorkoutRoutine.self, from: Data(json.utf8))
        let exercise = try XCTUnwrap(routine.exercises.first)
        XCTAssertEqual(exercise.restTimeInSeconds, 60)
        XCTAssertEqual(exercise.sets.first?.isWarmup, false)
        XCTAssertEqual(exercise.sets.first?.resolvedSetType, .normal)
        XCTAssertEqual(exercise.sets.first?.isCompleted, true)
        XCTAssertEqual(exercise.sets.first?.reps, 10)
        XCTAssertEqual(exercise.sets.first?.weight, 75)
        let restored = try JSONDecoder().decode(WorkoutRoutine.self, from: JSONEncoder().encode(routine))
        XCTAssertEqual(restored.id, "old-routine")
        XCTAssertEqual(restored.exercises.first?.sets.first?.id, "old-set")
    }

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
