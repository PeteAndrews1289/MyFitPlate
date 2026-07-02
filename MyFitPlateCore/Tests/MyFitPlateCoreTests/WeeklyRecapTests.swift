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
        calorieGoal: Double? = 2200
    ) -> WeeklyRecap {
        WeeklyRecapBuilder.build(
            weekEnding: weekEnding,
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: sessionLogs,
            priorSessionLogs: priorSessionLogs,
            weightHistory: weightHistory,
            calorieGoal: calorieGoal
        )
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
}
