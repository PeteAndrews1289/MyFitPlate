import XCTest
@testable import MyFitPlateCore

final class WorkoutRulesTests: XCTestCase {

    func testSkipToTargetIndex() {
        var program = WorkoutProgram(id: "prog1", userID: "user1", name: "My Program", dateCreated: Date(), routines: [])
        program.currentProgressIndex = 2
        program.skippedIndices = [0]
        
        // Skip ahead to index 5
        let updated = WorkoutRules.skip(to: 5, in: program)
        
        XCTAssertEqual(updated.currentProgressIndex, 5)
        XCTAssertEqual(updated.skippedIndices, [0, 2, 3, 4])
    }

    func testSkipToSameOrLowerIndexReturnsOriginal() {
        var program = WorkoutProgram(id: "prog1", userID: "user1", name: "My Program", dateCreated: Date(), routines: [])
        program.currentProgressIndex = 3
        program.skippedIndices = [1]
        
        let updatedLower = WorkoutRules.skip(to: 2, in: program)
        XCTAssertEqual(updatedLower.currentProgressIndex, 3)
        XCTAssertEqual(updatedLower.skippedIndices, [1])

        let updatedSame = WorkoutRules.skip(to: 3, in: program)
        XCTAssertEqual(updatedSame.currentProgressIndex, 3)
        XCTAssertEqual(updatedSame.skippedIndices, [1])
    }

    func testSkipCurrentWorkout() {
        var program = WorkoutProgram(id: "prog1", userID: "user1", name: "My Program", dateCreated: Date(), routines: [])
        program.currentProgressIndex = 0
        program.skippedIndices = []
        
        let updated1 = WorkoutRules.skipCurrentWorkout(in: program)
        XCTAssertEqual(updated1.currentProgressIndex, 1)
        XCTAssertEqual(updated1.skippedIndices, [0])
        
        let updated2 = WorkoutRules.skipCurrentWorkout(in: updated1)
        XCTAssertEqual(updated2.currentProgressIndex, 2)
        XCTAssertEqual(updated2.skippedIndices, [0, 1])
    }

    func testMapResponseToProgram() {
        let aiSet = AISet(target: "10-12 reps")
        let aiExercise = AIExercise(
            name: "Squat",
            type: ExerciseType(rawValue: "strength") ?? ExerciseType.strength,
            sets: [aiSet, aiSet],
            alternatives: ["Leg Press"]
        )
        let aiRoutine = AIRoutine(name: "Leg Day", exercises: [aiExercise])
        let response = AIProgramResponse(programName: "AI Leg Plan", routines: [aiRoutine])
        
        let program = WorkoutRules.mapResponseToProgram(response, userID: "user123")
        
        XCTAssertEqual(program.userID, "user123")
        XCTAssertEqual(program.name, "AI Leg Plan")
        XCTAssertEqual(program.routines.count, 1)
        
        let routine = program.routines[0]
        XCTAssertEqual(routine.name, "Leg Day")
        XCTAssertEqual(routine.exercises.count, 1)
        
        let exercise = routine.exercises[0]
        XCTAssertEqual(exercise.name, "Squat")
        XCTAssertEqual(exercise.type, ExerciseType.strength)
        XCTAssertEqual(exercise.alternatives, ["Leg Press"])
        XCTAssertEqual(exercise.sets.count, 2)
        XCTAssertEqual(exercise.sets[0].target, "10-12 reps")
    }

    func testGeneratePreBuiltPrograms() {
        let programs = WorkoutRules.generatePreBuiltPrograms()
        XCTAssertGreaterThan(programs.count, 0)
        
        let phat = programs.first(where: { $0.id == "prebuilt_phat" })
        XCTAssertNotNil(phat)
        XCTAssertEqual(phat?.userID, "system_prebuilt")
        XCTAssertEqual(phat?.routines.count, 5)
    }

    func testPreparePreBuiltProgramForUser() {
        let systemPrograms = WorkoutRules.generatePreBuiltPrograms()
        let original = systemPrograms.first!
        
        let userProgram = WorkoutRules.preparePreBuiltProgramForUser(original, userID: "realUser")
        
        XCTAssertNil(userProgram.id)
        XCTAssertEqual(userProgram.userID, "realUser")
        XCTAssertEqual(userProgram.currentProgressIndex, 0)
        XCTAssertEqual(userProgram.routines.count, original.routines.count)
        
        for routine in userProgram.routines {
            XCTAssertNotEqual(routine.id, "")
            XCTAssertEqual(routine.userID, "realUser")
            
            for exercise in routine.exercises {
                XCTAssertNotEqual(exercise.id, "")
                XCTAssertGreaterThan(exercise.targetSets, 0)
                for set in exercise.sets {
                    XCTAssertNotEqual(set.id, "")
                    XCTAssertFalse(set.isCompleted)
                    XCTAssertEqual(set.reps, 0)
                    XCTAssertEqual(set.weight, 0)
                }
            }
        }
    }

    func testCreateAIWorkoutPromptGeneratesExpectedString() {
        let prompt = WorkoutRules.createAIWorkoutPrompt(
            goal: "Build Muscle",
            daysPerWeek: 4,
            fitnessLevel: "Intermediate",
            equipment: "Dumbbells",
            details: "Bad shoulder",
            age: 30,
            gender: "Male",
            primaryWeightGoal: "Gain"
        )
        
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("Build Muscle"))
        XCTAssertTrue(prompt!.contains("Intermediate"))
        XCTAssertTrue(prompt!.contains("Dumbbells"))
        XCTAssertTrue(prompt!.contains("Bad shoulder"))
        XCTAssertTrue(prompt!.contains("Gain"))
    }

    func testParseAIWorkoutResponseSuccess() throws {
        let json = """
        {
          "programName": "Test Plan",
          "routines": []
        }
        """
        let result = WorkoutRules.parseAIWorkoutResponse(json)
        
        switch result {
        case .success(let response):
            XCTAssertEqual(response.programName, "Test Plan")
        default:
            XCTFail("Expected success")
        }
    }

    func testParseAIWorkoutResponseApiErrorOnRefusal() {
        let json = """
        {
          "programName": "I cannot generate a plan for you."
        }
        """
        let result = WorkoutRules.parseAIWorkoutResponse(json)
        
        switch result {
        case .apiError(let message):
            XCTAssertEqual(message, "I cannot generate a plan for you.")
        default:
            XCTFail("Expected apiError")
        }
    }
}
