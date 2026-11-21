import XCTest
@testable import MyFitPlateCore

final class WorkoutPlanningEligibilityTests: XCTestCase {
    private func program(_ names: [String], target: String = "8-12 reps", sets: Int = 3) -> WorkoutProgram {
        let exercises = names.map { name in
            RoutineExercise(name: name, sets: (0..<sets).map { _ in ExerciseSet(target: target) })
        }
        return WorkoutProgram(userID: "planning-user", name: "Reviewed plan", routines: [
            WorkoutRoutine(userID: "planning-user", name: "Day A", dateCreated: Date(), exercises: exercises)
        ])
    }

    func testLimitedEquipmentChecksPrimaryAndAlternativeMovementsRatherThanDiscoveryLabels() throws {
        let accepted = program(["Bodyweight Squat", "Push-up", "Walking Lunge"], target: "10 reps")
        XCTAssertNoThrow(try WorkoutPlanningEligibility.validate(accepted, daysPerWeek: 3, equipment: .floorOnly, maximumSessionMinutes: 30))
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(program(["Barbell Bench Press"]), daysPerWeek: 3, equipment: .dumbbellsAndFloor))
        XCTAssertFalse(WorkoutPlanningEligibility.isEligible("Pull-up", for: .floorOnly), "Bodyweight does not prove a pull-up bar exists")
        XCTAssertFalse(WorkoutPlanningEligibility.isEligible("Dumbbell Bench Press", for: .dumbbellsAndFloor), "A bench was not requested")
        XCTAssertTrue(WorkoutPlanningEligibility.isEligible("Dumbbell Shoulder Press", for: .dumbbellsAndFloor))
        let alternative = program(["Push-up"])
        alternative.routines[0].exercises[0].alternatives = ["Machine Chest Press"]
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(alternative, daysPerWeek: 3, equipment: .floorOnly))
    }

    func testAmbiguousUnknownAndEmptyGeneratedPlansRequireReviewInsteadOfSilentAcceptance() throws {
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(program(["Invented AI Press"]), daysPerWeek: 3, equipment: .fullGym))
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(program(["Romanian Deadlift"]), daysPerWeek: 3, equipment: .dumbbellsAndFloor))
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(program([]), daysPerWeek: 3, equipment: .fullGym))
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(program(["Push-up"]), daysPerWeek: 0, equipment: .fullGym))
    }

    func testEstimateIncludesWarmupSetupUpperRepsAndRestAndCannotPromiseMeasuredTime() throws {
        let plan = program(["Push-up"], target: "8-12 reps", sets: 3)
        let minutes = try XCTUnwrap(WorkoutPlanningEligibility.estimatedMinutes(plan.routines[0]))
        XCTAssertEqual(minutes, 11, "5min warm-up +1min setup +144s work +120s rest, rounded up")
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(plan, daysPerWeek: 3, equipment: .floorOnly, maximumSessionMinutes: 10))
        XCTAssertNoThrow(try WorkoutPlanningEligibility.validate(plan, daysPerWeek: 3, equipment: .floorOnly, maximumSessionMinutes: 15))
    }

    func testOpenEndedAndManualTargetsCannotPassATimeBudgetByGuessingSeconds() throws {
        for target in ["AMRAP", "50 total reps", "5/3/1 reps", "8 reps @ RPE 8"] {
            let plan = program(["Push-up"], target: target)
            XCTAssertNil(WorkoutPlanningEligibility.estimatedMinutes(plan.routines[0]))
            XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(plan, daysPerWeek: 3, equipment: .floorOnly, maximumSessionMinutes: 30))
        }
        XCTAssertNoThrow(try WorkoutPlanningEligibility.validate(program(["Push-up"], target: "AMRAP"), daysPerWeek: 3, equipment: .floorOnly))
    }

    func testTimedWorkIsEstimatedByItsActualPrescribedDuration() throws {
        let routine = WorkoutRoutine(userID: "planning-user", name: "Cardio", dateCreated: Date(), exercises: [
            RoutineExercise(name: "Stationary Bike", type: .cardio, sets: [ExerciseSet(target: "20 min")])
        ])
        XCTAssertEqual(WorkoutPlanningEligibility.estimatedMinutes(routine), 26)
        let plan = WorkoutProgram(userID: "planning-user", name: "Cycling", routines: [routine])
        XCTAssertThrowsError(try WorkoutPlanningEligibility.validate(plan, daysPerWeek: 3, equipment: .fullGym, maximumSessionMinutes: 20))
        XCTAssertNoThrow(try WorkoutPlanningEligibility.validate(plan, daysPerWeek: 3, equipment: .fullGym, maximumSessionMinutes: 30))
    }

    func testCatalogSummaryLabelsAmbiguousEquipmentAndManualTargetsHonestly() {
        let plan = program(["Romanian Deadlift"], target: "5/3/1 reps")
        let summary = WorkoutProgramPlanningSummary.make(plan)
        XCTAssertEqual(summary.ambiguousMovements, ["Romanian Deadlift"])
        XCTAssertEqual(summary.manualTargetSets, 3)
        XCTAssertNil(summary.maximumEstimatedMinutes)
        XCTAssertFalse(summary.equipment.contains("Dumbbell"))
    }

    func testPromptCarriesExplicitBudgetFloorEquipmentAndFeasibleExerciseCount() throws {
        let prompt = try XCTUnwrap(WorkoutRules.createAIWorkoutPrompt(goal: "Build strength", daysPerWeek: 3,
            fitnessLevel: "Beginner", equipment: "Bodyweight Only", details: "", age: 30,
            gender: "Male", primaryWeightGoal: "Maintain", maximumSessionMinutes: 30))
        XCTAssertTrue(prompt.contains("Maximum session minutes: 30"))
        XCTAssertTrue(prompt.contains("Floor-based bodyweight work only"))
        XCTAssertTrue(prompt.contains("Use 1–10 exercises"))
        XCTAssertTrue(prompt.contains("ALSO fit the equipment constraint"))
    }
}
