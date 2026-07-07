import XCTest
@testable import MyFitPlateCore

final class TodayFuelPlanRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 7, day: 7, hour: 14).date!
    }

    private let goals = TodayFuelPlanGoals(calories: 2_000, protein: 160, carbs: 250, fats: 70)

    func testOverTargetDayPrioritizesNeutralReviewOverRecoveryFuel() {
        let target = recoveryTarget(timestamp: now.addingTimeInterval(-10 * 60))
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 2_125, protein: 145, carbs: 250, fats: 70),
            goals: goals,
            runRecoveryTarget: target,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .overTargetReview)
        XCTAssertEqual(plan.action, .reviewDay)
        XCTAssertLessThan(plan.remainingCalories, 0)
        XCTAssertNil(plan.targetProteinGrams)
        XCTAssertNil(plan.targetCarbGrams)
        XCTAssertTrue(plan.detail.contains("do not treat extra exercise as a reset button"))
    }

    func testRunRecoveryStaysInsideRemainingCalorieBudget() throws {
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_850, protein: 120, carbs: 220, fats: 60),
            goals: goals,
            runRecoveryTarget: recoveryTarget(timestamp: now.addingTimeInterval(-15 * 60)),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .runRecovery)
        XCTAssertEqual(plan.action, .openRecoverySearch)
        XCTAssertEqual(plan.remainingCalories, 150, accuracy: 0.001)
        XCTAssertEqual(plan.targetProteinGrams, 16)
        XCTAssertEqual(plan.targetCarbGrams, 21)
        XCTAssertEqual(plan.targetWaterOunces, 20)

        let protein = try XCTUnwrap(plan.targetProteinGrams)
        let carbs = try XCTUnwrap(plan.targetCarbGrams)
        XCTAssertLessThanOrEqual(Double(protein * 4 + carbs * 4), plan.remainingCalories)
    }

    func testWorkoutDayBuildsRecoveryMealWhenBudgetAllows() {
        let workout = LoggedExercise(name: "Strength", durationMinutes: 50, caloriesBurned: 320, date: now)
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_200, protein: 80, carbs: 120, fats: 45, exercises: [workout]),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .workoutRecovery)
        XCTAssertEqual(plan.action, .fillMacros)
        XCTAssertEqual(plan.statusLabel, "Training")
        XCTAssertNotNil(plan.targetProteinGrams)
        XCTAssertNotNil(plan.targetCarbGrams)
    }

    func testProteinGapCreatesCatchUpPlan() {
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_300, protein: 80, carbs: 160, fats: 50),
            goals: goals,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .proteinCatchUp)
        XCTAssertEqual(plan.action, .fillMacros)
        XCTAssertEqual(plan.statusLabel, "Protein")
        XCTAssertEqual(plan.targetProteinGrams, 36)
    }

    func testEveningWithRoomPlansDinner() {
        let evening = DateComponents(calendar: calendar, year: 2026, month: 7, day: 7, hour: 18).date!
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_400, protein: 150, carbs: 220, fats: 50),
            goals: goals,
            now: evening,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .planDinner)
        XCTAssertEqual(plan.action, .fillMacros)
        XCTAssertEqual(plan.statusLabel, "Dinner")
    }

    func testSteadyDayHasNoActionWhenNoSpecificNeedIsPresent() {
        let morning = DateComponents(calendar: calendar, year: 2026, month: 7, day: 7, hour: 10).date!
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_550, protein: 145, carbs: 225, fats: 55),
            goals: goals,
            now: morning,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .steadyDay)
        XCTAssertEqual(plan.action, .none)
        XCTAssertEqual(plan.statusLabel, "Steady")
    }

    func testExpiredRunRecoveryFallsBackToNextBestTarget() {
        let expiredTarget = recoveryTarget(timestamp: now.addingTimeInterval(-60 * 60))
        let plan = TodayFuelPlanRules.makePlan(
            today: log(calories: 1_300, protein: 80, carbs: 160, fats: 50),
            goals: goals,
            runRecoveryTarget: expiredTarget,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .proteinCatchUp)
        XCTAssertEqual(plan.action, .fillMacros)
    }

    func testWorkoutCompletionPlanForcesRecoveryBranchBeforeExerciseLogRefreshes() {
        let plan = TodayFuelPlanRules.makeWorkoutCompletionPlan(
            today: log(calories: 1_200, protein: 80, carbs: 120, fats: 45),
            goals: goals,
            sessionLog: sessionLog(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .workoutRecovery)
        XCTAssertEqual(plan.action, .fillMacros)
        XCTAssertEqual(plan.statusLabel, "Training")
    }

    func testWorkoutCompletionPlanStillUsesNeutralReviewWhenOverTarget() {
        let plan = TodayFuelPlanRules.makeWorkoutCompletionPlan(
            today: log(calories: 2_050, protein: 165, carbs: 250, fats: 75),
            goals: goals,
            sessionLog: sessionLog(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.kind, .overTargetReview)
        XCTAssertEqual(plan.action, .reviewDay)
    }

    private func log(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        exercises: [LoggedExercise] = []
    ) -> DailyLog {
        DailyLog(
            date: calendar.startOfDay(for: now),
            meals: [
                Meal(
                    name: "Logged",
                    foodItems: [
                        FoodItem(name: "Logged food", calories: calories, protein: protein, carbs: carbs, fats: fats)
                    ]
                )
            ],
            exercises: exercises
        )
    }

    private func recoveryTarget(timestamp: Date) -> RunRecoveryTarget {
        RunRecoveryTarget(
            targetCarbGrams: 80,
            targetProteinGrams: 40,
            rehydrateMilliLiters: 600,
            windowMinutes: 45,
            runDistanceMeters: 8_000,
            activeCalories: 500,
            runID: "run-1",
            timestamp: timestamp
        )
    }

    private func sessionLog() -> WorkoutSessionLog {
        WorkoutSessionLog(
            id: "session-1",
            date: now,
            routineID: "routine-1",
            completedExercises: [
                CompletedExercise(
                    exerciseName: "Squat",
                    exercise: RoutineExercise(name: "Squat", type: .strength),
                    sets: [
                        CompletedSet(reps: 8, weight: 185),
                        CompletedSet(reps: 8, weight: 185),
                        CompletedSet(reps: 8, weight: 185)
                    ]
                )
            ]
        )
    }
}
