import XCTest
@testable import MyFitPlateCore

final class WeekInMotionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var weekEnding: Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 12,
            hour: 20
        ).date!
    }

    private func day(_ daysAgo: Int, hour: Int = 12) -> Date {
        let start = calendar.startOfDay(for: weekEnding)
        return calendar.date(byAdding: .day, value: -daysAgo, to: start)!
            .addingTimeInterval(Double(hour * 60 * 60))
    }

    private func foodLog(daysAgo: Int, item: FoodItem? = nil) -> DailyLog {
        let food = item ?? FoodItem(name: "Private meal", calories: 2_000, protein: 120)
        return DailyLog(date: day(daysAgo), meals: [Meal(name: "Private meal", foodItems: [food])])
    }

    private func session(daysAgo: Int, setCount: Int = 1) -> WorkoutSessionLog {
        let exercise = RoutineExercise(name: "Private movement", type: .strength, sets: [])
        let sets = (0..<setCount).map { _ in
            CompletedSet(reps: 8, weight: 100, distance: 0, durationInSeconds: 0)
        }
        return WorkoutSessionLog(
            date: day(daysAgo),
            routineID: "private-routine",
            completedExercises: [
                CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: sets)
            ]
        )
    }

    private func run(daysAgo: Int, id: String = UUID().uuidString) -> Run {
        let start = day(daysAgo, hour: 7)
        return Run(
            id: id,
            source: .recorded,
            startDate: start,
            endDate: start.addingTimeInterval(45 * 60),
            distanceMeters: 10_000,
            movingSeconds: 45 * 60,
            activeCalories: 700
        )
    }

    private func recap(
        dailyLogs: [DailyLog] = [],
        sessions: [WorkoutSessionLog] = [],
        priorSessions: [WorkoutSessionLog] = [],
        runs: [Run] = [],
        proteinGoal: Double? = 120
    ) -> WeeklyRecap {
        WeeklyRecapBuilder.build(
            weekEnding: weekEnding,
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: sessions,
            priorSessionLogs: priorSessions,
            weightHistory: [],
            runs: runs,
            calorieGoal: 2_000,
            proteinGoal: proteinGoal
        )
    }

    func testRecapBuildsSevenOrderedDayStatesFromExistingHistory() {
        let built = recap(
            dailyLogs: [foodLog(daysAgo: 6), foodLog(daysAgo: 3)],
            sessions: [session(daysAgo: 5)],
            runs: [run(daysAgo: 3)]
        )

        XCTAssertEqual(built.days.count, 7)
        XCTAssertEqual(built.days.map(\.date), built.days.map(\.date).sorted())
        XCTAssertTrue(built.days[0].nutritionLogged)
        XCTAssertEqual(built.days[1].trainingKind, .strength)
        XCTAssertEqual(built.days[3].trainingKind, .run)
        XCTAssertTrue(built.days[3].nutritionLogged)
        XCTAssertEqual(built.days[6].trainingKind, .rest)
    }

    func testTrainingCoverageGapIsTheFirstBoundedObservation() {
        let motion = WeekInMotionBuilder.build(from: recap(
            dailyLogs: [foodLog(daysAgo: 2)],
            sessions: [session(daysAgo: 1), session(daysAgo: 2)]
        ))

        XCTAssertEqual(motion.observation.title, "Training-day coverage")
        XCTAssertEqual(motion.observation.kind, .trainingCoverage)
        XCTAssertEqual(motion.observation.tone, .attention)
        XCTAssertTrue(motion.observation.text.contains("1 of 2"))
        XCTAssertEqual(motion.trainingCoverage, WeeklyRecapProgress(completed: 1, eligible: 2))
    }

    func testRecoveryObservationUsesOnlyCompletedTimestampedWindows() {
        let completedRun = run(daysAgo: 2, id: "recovery-run")
        let ordinaryFood = FoodItem(
            name: "Private ordinary food",
            calories: 2_000,
            protein: 120,
            timestamp: completedRun.startDate.addingTimeInterval(-4 * 60 * 60)
        )
        let motion = WeekInMotionBuilder.build(from: recap(
            dailyLogs: [foodLog(daysAgo: 2, item: ordinaryFood)],
            runs: [completedRun]
        ))

        XCTAssertEqual(motion.observation.title, "Recovery follow-through")
        XCTAssertEqual(motion.observation.kind, .recovery)
        XCTAssertEqual(
            motion.observation.text,
            "0 of 1 assessed runs had both recovery targets logged."
        )
        XCTAssertTrue(motion.recoverySummary.hasPrefix("0 of 1 assessed runs"))
        XCTAssertTrue(motion.observation.basis.contains("timestamped food"))
        XCTAssertEqual(motion.recoveryProgress, WeeklyRecapProgress(completed: 0, eligible: 1))
    }

    func testTrustObservationDoesNotExposeFoodOrRoutineNames() {
        let estimated = FoodItem(
            name: "Secret family recipe",
            calories: 2_000,
            protein: 120,
            sourceMetadata: .aiEstimate(.aiText, sourceName: "Private source")
        )
        let motion = WeekInMotionBuilder.build(from: recap(
            dailyLogs: [foodLog(daysAgo: 1, item: estimated)],
            sessions: [session(daysAgo: 1)]
        ))
        let publishedCopy = [
            motion.headline,
            motion.trainingSummary,
            motion.fuelSummary,
            motion.recoverySummary,
            motion.trustSummary,
            motion.observation.text,
            motion.observation.basis
        ].joined(separator: " ")

        XCTAssertEqual(motion.observation.title, "Trust coverage")
        XCTAssertEqual(motion.observation.kind, .trust)
        XCTAssertFalse(publishedCopy.contains("Secret family recipe"))
        XCTAssertFalse(publishedCopy.contains("Private movement"))
        XCTAssertFalse(publishedCopy.contains("Private source"))
    }

    func testPendingRecoveryIsUnscoredRatherThanCalledAFailure() {
        let end = weekEnding.addingTimeInterval(-10 * 60)
        let activeRun = Run(
            id: "pending",
            source: .recorded,
            startDate: end.addingTimeInterval(-30 * 60),
            endDate: end,
            distanceMeters: 10_000,
            movingSeconds: 30 * 60,
            activeCalories: 700
        )
        let motion = WeekInMotionBuilder.build(from: recap(
            dailyLogs: [foodLog(daysAgo: 0)],
            runs: [activeRun]
        ))

        XCTAssertEqual(motion.recoveryProgress.eligible, 0)
        XCTAssertTrue(motion.recoverySummary.contains("unscored"))
        XCTAssertFalse(motion.recoverySummary.lowercased().contains("missed"))
    }

    func testQuietWeekRemainsHonestAndScoreless() {
        let motion = WeekInMotionBuilder.build(from: recap(proteinGoal: nil))

        XCTAssertEqual(motion.days.count, 7)
        XCTAssertEqual(motion.observation.title, "Quiet week")
        XCTAssertEqual(motion.observation.kind, .quiet)
        XCTAssertEqual(motion.observation.tone, .neutral)
        XCTAssertFalse(motion.headline.lowercased().contains("score"))
        XCTAssertEqual(motion.diaryCoverage, WeeklyRecapProgress(completed: 0, eligible: 7))
    }
}
