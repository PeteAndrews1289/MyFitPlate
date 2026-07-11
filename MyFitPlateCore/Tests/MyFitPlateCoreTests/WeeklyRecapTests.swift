import XCTest
@testable import MyFitPlateCore

final class WeeklyRecapTests: XCTestCase {

    private let calendar = Calendar.current
    private let weekEnding = Date()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: weekEnding))!
            .addingTimeInterval(12 * 60 * 60)
    }

    private func foodLog(daysAgo: Int, calories: Double, protein: Double) -> DailyLog {
        let item = FoodItem(name: "Meal", calories: calories, protein: protein, servingWeight: 100)
        return DailyLog(date: day(daysAgo), meals: [Meal(name: "Lunch", foodItems: [item])])
    }

    private func session(daysAgo: Int, exercise: String, weight: Double, reps: Int) -> WorkoutSessionLog {
        let routineExercise = RoutineExercise(name: exercise, type: .strength, sets: [])
        let completed = CompletedExercise(
            exerciseName: exercise,
            exercise: routineExercise,
            sets: [CompletedSet(reps: reps, weight: weight, distance: 0, durationInSeconds: 0)]
        )
        return WorkoutSessionLog(date: day(daysAgo), routineID: "r1", completedExercises: [completed])
    }

    private func build(
        dailyLogs: [DailyLog] = [],
        sessionLogs: [WorkoutSessionLog] = [],
        priorSessionLogs: [WorkoutSessionLog] = [],
        weightHistory: [(id: String, date: Date, weight: Double)] = [],
        runs: [Run] = [],
        calorieGoal: Double? = 2200,
        proteinGoal: Double? = nil,
        heartRateZoneSeconds: [Double]? = nil,
        runWorkoutResults: [RunWorkoutResult] = [],
        shoes: [RunningShoe] = []
    ) -> WeeklyRecap {
        WeeklyRecapBuilder.build(
            weekEnding: weekEnding,
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: sessionLogs,
            priorSessionLogs: priorSessionLogs,
            weightHistory: weightHistory,
            runs: runs,
            calorieGoal: calorieGoal,
            proteinGoal: proteinGoal,
            heartRateZoneSeconds: heartRateZoneSeconds,
            runWorkoutResults: runWorkoutResults,
            shoes: shoes
        )
    }

    private func runEntry(daysAgo: Int, meters: Double, id: String = UUID().uuidString) -> Run {
        Run(
            id: id,
            source: .imported(appName: "Garmin Connect"),
            startDate: day(daysAgo),
            endDate: day(daysAgo).addingTimeInterval(1800),
            distanceMeters: meters,
            movingSeconds: 1800
        )
    }

    // MARK: - Running

    func testRunsInsideTheWindowAreSummed() {
        let recap = build(runs: [
            runEntry(daysAgo: 1, meters: 5000),
            runEntry(daysAgo: 4, meters: 8000),
            runEntry(daysAgo: 9, meters: 12_000)   // before the window — excluded
        ])
        XCTAssertEqual(recap.runCount, 2)
        XCTAssertEqual(recap.runMeters, 13_000, accuracy: 0.01)
    }

    func testRunningAloneCountsAsActivity() {
        let recap = build(runs: [runEntry(daysAgo: 2, meters: 5000)])
        XCTAssertTrue(recap.hasAnyActivity, "A running-only week is not a quiet week")

        let quiet = build()
        XCTAssertFalse(quiet.hasAnyActivity)
        XCTAssertEqual(quiet.runCount, 0)
    }

    // MARK: - Nutrition

    func testDaysLoggedAndAveragesOverLoggedDaysOnly() {
        let recap = build(dailyLogs: [
            foodLog(daysAgo: 0, calories: 2000, protein: 150),
            foodLog(daysAgo: 1, calories: 2400, protein: 170),
            DailyLog(date: day(2), meals: [])
        ])

        XCTAssertEqual(recap.daysLogged, 2)
        XCTAssertEqual(recap.averageCalories!, 2200, accuracy: 0.01)
        XCTAssertEqual(recap.averageProtein!, 160, accuracy: 0.01)
    }

    func testDuplicateLogsOnSameDayCountOnce() {
        let recap = build(dailyLogs: [
            foodLog(daysAgo: 0, calories: 2000, protein: 150),
            foodLog(daysAgo: 0, calories: 9999, protein: 999)
        ])
        XCTAssertEqual(recap.daysLogged, 1)
        XCTAssertEqual(recap.averageCalories!, 2000, accuracy: 0.01)
    }

    func testLogsOutsideWindowAreIgnored() {
        let recap = build(dailyLogs: [foodLog(daysAgo: 10, calories: 2000, protein: 150)])
        XCTAssertEqual(recap.daysLogged, 0)
        XCTAssertNil(recap.averageCalories)
        XCTAssertFalse(recap.hasAnyActivity)
    }

    // MARK: - Training

    func testWorkoutCountAndVolume() {
        let recap = build(sessionLogs: [
            session(daysAgo: 1, exercise: "Bench Press", weight: 185, reps: 5),
            session(daysAgo: 3, exercise: "Squat", weight: 225, reps: 5)
        ])

        XCTAssertEqual(recap.workoutsCompleted, 2)
        XCTAssertEqual(recap.totalVolume, 185 * 5 + 225 * 5, accuracy: 0.01)
    }

    func testPersonalRecordDetectedAgainstPriorBest() {
        let recap = build(
            sessionLogs: [session(daysAgo: 1, exercise: "Bench Press", weight: 200, reps: 5)],
            priorSessionLogs: [session(daysAgo: 30, exercise: "Bench Press", weight: 185, reps: 5)]
        )
        XCTAssertEqual(recap.personalRecords, 1)
    }

    func testNoRecordWhenBelowPriorBestOrNoHistory() {
        // Below prior best: no PR.
        let below = build(
            sessionLogs: [session(daysAgo: 1, exercise: "Bench Press", weight: 165, reps: 5)],
            priorSessionLogs: [session(daysAgo: 30, exercise: "Bench Press", weight: 185, reps: 5)]
        )
        XCTAssertEqual(below.personalRecords, 0)

        // First-ever attempt: not a record.
        let firstTime = build(sessionLogs: [session(daysAgo: 1, exercise: "Deadlift", weight: 315, reps: 3)])
        XCTAssertEqual(firstTime.personalRecords, 0)
    }

    // MARK: - Weight

    func testWeightChangeAgainstPreWeekBaseline() {
        let recap = build(weightHistory: [
            (id: "a", date: day(10), weight: 190.0),
            (id: "b", date: day(1), weight: 187.5)
        ])
        XCTAssertEqual(recap.weightChange!, -2.5, accuracy: 0.01)
    }

    func testWeightChangeWithinWindowWhenNoBaseline() {
        let recap = build(weightHistory: [
            (id: "a", date: day(5), weight: 190.0),
            (id: "b", date: day(0), weight: 189.0)
        ])
        XCTAssertEqual(recap.weightChange!, -1.0, accuracy: 0.01)
    }

    func testWeightChangeNilWithSingleEntry() {
        let recap = build(weightHistory: [(id: "a", date: day(2), weight: 190.0)])
        XCTAssertNil(recap.weightChange)
    }

    // MARK: - 1RM helper

    func testEstimatedOneRepMaxEpley() {
        XCTAssertEqual(WeeklyRecapBuilder.estimatedOneRepMax(weight: 200, reps: 5), 200 * (1 + 5.0 / 30.0), accuracy: 0.001)
        XCTAssertEqual(WeeklyRecapBuilder.estimatedOneRepMax(weight: 0, reps: 5), 0)
        XCTAssertEqual(WeeklyRecapBuilder.estimatedOneRepMax(weight: 200, reps: 0), 0)
    }

    // MARK: - Unified Training and Fuel report

    func testNutritionAdherenceTrainingCoverageAndTrustUseExplicitDenominators() {
        let unreviewed = FoodItem(
            name: "Estimated lunch",
            calories: 2_000,
            protein: 100,
            sourceMetadata: .aiEstimate(.aiText, sourceName: "Test")
        )
        let reviewed = FoodItem(
            name: "Reviewed dinner",
            calories: 2_500,
            protein: 80,
            sourceMetadata: .aiEstimate(.aiText, sourceName: "Test")
        ).markedUserConfirmed(sourceType: .aiText)
        let logs = [
            DailyLog(date: day(0), meals: [Meal(name: "Lunch", foodItems: [unreviewed])]),
            DailyLog(date: day(1), meals: [Meal(name: "Dinner", foodItems: [reviewed])])
        ]
        let strength = session(daysAgo: 0, exercise: "Bench Press", weight: 100, reps: 5)
        let run = runEntry(daysAgo: 1, meters: 5_000)

        let recap = build(
            dailyLogs: logs,
            sessionLogs: [strength],
            runs: [run],
            calorieGoal: 2_000,
            proteinGoal: 100
        )

        XCTAssertEqual(recap.calorieAdherence, WeeklyRecapProgress(completed: 1, eligible: 2))
        XCTAssertEqual(recap.proteinAdherence, WeeklyRecapProgress(completed: 1, eligible: 2))
        XCTAssertEqual(recap.trustReview, WeeklyRecapProgress(completed: 1, eligible: 2))
        XCTAssertEqual(recap.trainingDays, 2)
        XCTAssertEqual(recap.trainingDaysLogged, 2)
        XCTAssertTrue(recap.story.headline.contains("2 days"))
    }

    func testStrengthSummaryExcludesWarmupsAndComparesEffortToPriorWeek() throws {
        func effortSession(daysAgo: Int, workingSets: Int, rpe: Double) -> WorkoutSessionLog {
            let sets = [CompletedSet(reps: 5, weight: 500, setType: .warmup, effort: .init(scale: .rpe, value: 10))] +
                (0..<workingSets).map { _ in
                    CompletedSet(reps: 8, weight: 100, setType: .normal, effort: .init(scale: .rpe, value: rpe))
                }
            let exercise = CompletedExercise(
                exerciseName: "Squat",
                exercise: RoutineExercise(name: "Squat", type: .strength, sets: []),
                sets: sets
            )
            return WorkoutSessionLog(date: day(daysAgo), routineID: "strength", completedExercises: [exercise])
        }

        let recap = build(
            dailyLogs: [foodLog(daysAgo: 1, calories: 2_000, protein: 110)],
            sessionLogs: [effortSession(daysAgo: 1, workingSets: 8, rpe: 8.5)],
            priorSessionLogs: [effortSession(daysAgo: 8, workingSets: 8, rpe: 7.5)],
            calorieGoal: 2_000,
            proteinGoal: 100
        )

        XCTAssertEqual(recap.workingSetCount, 8)
        XCTAssertEqual(recap.totalVolume, 6_400, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.averageEffortRPE), 8.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.priorAverageEffortRPE), 7.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.effortChange), 1.0, accuracy: 0.001)
        XCTAssertEqual(recap.demandingStrengthDays, 1)
        XCTAssertEqual(recap.demandingStrengthFuelAdherence, WeeklyRecapProgress(completed: 1, eligible: 1))
    }

    func testRunningSummaryCombinesPriorMileageRecordsRoutesZonesGuidanceAndShoes() throws {
        let shoe = RunningShoe(
            id: "shoe-1",
            name: "Daily Trainer",
            brand: "Test",
            initialMeters: 90_000,
            maxMeters: 100_000,
            isDefault: true
        )
        var prior = runEntry(daysAgo: 8, meters: 5_000, id: "prior")
        prior.movingSeconds = 1_800
        prior.shoeID = shoe.id

        var current = runEntry(daysAgo: 1, meters: 5_000, id: "current")
        current.movingSeconds = 1_500
        current.hasRoute = true
        current.shoeID = shoe.id

        let step = RunWorkoutStep(id: "work", kind: .hard, title: "Work", goal: .duration(seconds: 60))
        let result = RunWorkoutResult(
            runID: current.id,
            planID: "plan",
            planName: "Intervals",
            completedAt: current.endDate,
            steps: [
                RunWorkoutStepResult(
                    stepIndex: 0,
                    step: step,
                    startedAtElapsedSeconds: 0,
                    endedAtElapsedSeconds: 60,
                    startedAtDistanceMeters: 0,
                    endedAtDistanceMeters: 200,
                    isComplete: true
                ),
                RunWorkoutStepResult(
                    stepIndex: 1,
                    step: step,
                    startedAtElapsedSeconds: 60,
                    endedAtElapsedSeconds: 90,
                    startedAtDistanceMeters: 200,
                    endedAtDistanceMeters: 300,
                    isComplete: false
                )
            ]
        )

        let recap = build(
            runs: [prior, current],
            heartRateZoneSeconds: [60, 120, 180, 240, 300],
            runWorkoutResults: [result],
            shoes: [shoe]
        )

        XCTAssertEqual(recap.runCount, 1)
        XCTAssertEqual(recap.runMeters, 5_000, accuracy: 0.001)
        XCTAssertEqual(recap.priorRunMeters, 5_000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.averageRunPaceSecondsPerKm), 300, accuracy: 0.001)
        XCTAssertEqual(recap.paceRecordCount, 1)
        XCTAssertGreaterThanOrEqual(recap.runRecordCount, 1)
        XCTAssertEqual(recap.routeRunCount, 1)
        XCTAssertEqual(recap.outdoorRunCount, 1)
        XCTAssertEqual(recap.heartRateZoneSeconds, [60, 120, 180, 240, 300])
        XCTAssertEqual(recap.guidedRunCount, 1)
        XCTAssertEqual(recap.guidedCompletedSteps, 1)
        XCTAssertEqual(recap.guidedRecordedSteps, 2)
        XCTAssertEqual(try XCTUnwrap(recap.shoeContext).wearFraction, 1.0, accuracy: 0.001)
        XCTAssertTrue(try XCTUnwrap(recap.shoeContext).isWornOut)
    }

    func testRouteCoverageOnlyCountsOutdoorRuns() {
        var outdoor = runEntry(daysAgo: 1, meters: 5_000, id: "outdoor")
        outdoor.isIndoor = false
        outdoor.hasRoute = false

        var indoor = runEntry(daysAgo: 2, meters: 5_000, id: "indoor")
        indoor.isIndoor = true
        indoor.hasRoute = true

        let recap = build(runs: [outdoor, indoor])

        XCTAssertEqual(recap.outdoorRunCount, 1)
        XCTAssertEqual(recap.routeRunCount, 0)
    }

    func testRecoveryFuelOnlyCreditsTimestampedFoodInsideTheRecoveryWindow() {
        var run = runEntry(daysAgo: 1, meters: 10_000, id: "recovery-run")
        run.activeCalories = 700
        let inside = FoodItem(
            name: "Recovery meal",
            calories: 500,
            protein: 45,
            carbs: 90,
            timestamp: run.endDate.addingTimeInterval(20 * 60)
        )
        let untimed = FoodItem(name: "Untimed food", calories: 500, protein: 45, carbs: 90)
        let log = DailyLog(date: day(1), meals: [Meal(name: "Dinner", foodItems: [inside, untimed])])

        let recap = build(dailyLogs: [log], runs: [run])

        XCTAssertEqual(recap.recoveryFuelLoggedRuns, 1)
        XCTAssertEqual(recap.recoveryFuelAdherence, WeeklyRecapProgress(completed: 1, eligible: 1))

        let noTimestamp = build(
            dailyLogs: [DailyLog(date: day(1), meals: [Meal(name: "Dinner", foodItems: [untimed])])],
            runs: [run]
        )
        XCTAssertEqual(noTimestamp.recoveryFuelLoggedRuns, 0)
        XCTAssertEqual(noTimestamp.recoveryFuelAdherence, WeeklyRecapProgress(completed: 0, eligible: 1))
    }

    func testRecoveryWindowRemainsPendingUntilItCanBeAssessed() {
        let end = weekEnding.addingTimeInterval(-10 * 60)
        var run = Run(
            id: "active-recovery",
            source: .recorded,
            startDate: end.addingTimeInterval(-30 * 60),
            endDate: end,
            distanceMeters: 10_000,
            movingSeconds: 30 * 60
        )
        run.activeCalories = 700

        let pending = build(runs: [run])
        XCTAssertEqual(pending.recoveryFuelPendingRuns, 1)
        XCTAssertEqual(pending.recoveryFuelAdherence, WeeklyRecapProgress(completed: 0, eligible: 0))

        let recoveryFood = FoodItem(
            name: "Recovery",
            calories: 600,
            protein: 45,
            carbs: 100,
            timestamp: end.addingTimeInterval(5 * 60)
        )
        let completed = build(
            dailyLogs: [DailyLog(date: weekEnding, meals: [Meal(name: "Recovery", foodItems: [recoveryFood])])],
            runs: [run]
        )
        XCTAssertEqual(completed.recoveryFuelPendingRuns, 0)
        XCTAssertEqual(completed.recoveryFuelAdherence, WeeklyRecapProgress(completed: 1, eligible: 1))
    }

    func testSmoothedWeightChangeUsesPriorBaselineAndDampensNoise() throws {
        let history = [
            (id: "baseline", date: day(8), weight: 180.0),
            (id: "spike", date: day(5), weight: 190.0),
            (id: "settled", date: day(0), weight: 179.0)
        ]
        let recap = build(weightHistory: history)

        XCTAssertEqual(try XCTUnwrap(recap.weightChange), -1.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(recap.smoothedWeightChange), 2.0, accuracy: 0.001)
        XCTAssertNotEqual(recap.smoothedWeightChange, recap.weightChange)
    }

    func testSparseAndInvalidDataStayUnavailableInsteadOfBecomingFailures() {
        let recap = build(
            dailyLogs: [foodLog(daysAgo: 0, calories: .nan, protein: .infinity)],
            runs: [runEntry(daysAgo: 0, meters: .nan)],
            calorieGoal: .nan,
            proteinGoal: -1,
            heartRateZoneSeconds: [.nan, -1, 0, 0, 0]
        )

        XCTAssertEqual(recap.daysLogged, 1)
        XCTAssertNil(recap.averageCalories)
        XCTAssertNil(recap.averageProtein)
        XCTAssertEqual(recap.calorieAdherence.eligible, 0)
        XCTAssertEqual(recap.proteinAdherence.eligible, 0)
        XCTAssertNil(recap.heartRateZoneSeconds)
        XCTAssertEqual(recap.runMeters, 0)
        XCTAssertNil(recap.averageRunPaceSecondsPerKm)
    }

    func testInvalidNutritionAndHeartRateAreExcludedFromAssessableDenominators() {
        let invalid = foodLog(daysAgo: 0, calories: .nan, protein: .infinity)
        let valid = foodLog(daysAgo: 1, calories: 2_000, protein: 100)
        let recap = build(
            dailyLogs: [invalid, valid],
            calorieGoal: 2_000,
            proteinGoal: 100,
            heartRateZoneSeconds: [60, 120, .nan, 240, 300]
        )

        XCTAssertEqual(recap.daysLogged, 2)
        XCTAssertEqual(recap.averageCalories, 2_000)
        XCTAssertEqual(recap.averageProtein, 100)
        XCTAssertEqual(recap.calorieAdherence, WeeklyRecapProgress(completed: 1, eligible: 1))
        XCTAssertEqual(recap.proteinAdherence, WeeklyRecapProgress(completed: 1, eligible: 1))
        XCTAssertNil(recap.heartRateZoneSeconds)
    }

    func testEmptyDuplicateDoesNotHideLaterFoodOnTheSameDay() {
        let recap = build(dailyLogs: [
            DailyLog(date: day(0).addingTimeInterval(-60), meals: []),
            foodLog(daysAgo: 0, calories: 2_000, protein: 100)
        ])
        XCTAssertEqual(recap.daysLogged, 1)
        XCTAssertEqual(recap.averageCalories, 2_000)
    }

    func testCSVExportsAggregatesWithoutPrivateSourceDetails() {
        let secretFood = FoodItem(name: "Private family recipe", calories: 2_000, protein: 120)
        let privateRoutine = session(daysAgo: 0, exercise: "Private rehab movement", weight: 50, reps: 10)
        let recap = build(
            dailyLogs: [DailyLog(date: day(0), meals: [Meal(name: "Private meal", foodItems: [secretFood])])],
            sessionLogs: [privateRoutine],
            calorieGoal: 2_000,
            proteinGoal: 120
        )

        let csv = WeeklyRecapCSVExporter.csvString(for: recap, metric: false)

        XCTAssertTrue(csv.contains("Category,Metric,Value,Unit,Notes"))
        XCTAssertTrue(csv.contains("Working sets"))
        XCTAssertTrue(csv.contains("Warmups excluded"))
        XCTAssertFalse(csv.contains("Private family recipe"))
        XCTAssertFalse(csv.contains("Private rehab movement"))
        XCTAssertFalse(csv.lowercased().contains("latitude"))
        XCTAssertFalse(csv.lowercased().contains("account id"))
    }
}
