import XCTest
@testable import MyFitPlateCore

final class NutritionDayEvidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func log(_ status: NutritionDayStatus? = nil, calories: Double = 2_000, date: Date? = nil) -> DailyLog {
        DailyLog(date: date ?? now, meals: [Meal(name: "Day", foodItems: [FoodItem(name: "Meals", calories: calories)])], nutritionDayStatus: status)
    }
    func testLegacyAndUnknownDaysAreNeverInferredCompleteFromCalories() throws {
        let legacy = try JSONDecoder().decode(DailyLog.self, from: JSONEncoder().encode(log()))
        XCTAssertEqual(NutritionDayEvidence.status(of: legacy), .unknown)
        XCTAssertFalse(NutritionDayEvidence.isComplete(legacy, now: now))
        XCTAssertFalse(NutritionDayEvidence.isComplete(log(.partial, calories: 3_000), now: now))
        XCTAssertTrue(NutritionDayEvidence.isComplete(log(.complete, calories: 400), now: now))
        XCTAssertEqual(try JSONDecoder().decode(NutritionDayStatus.self, from: Data("\"future-value\"".utf8)), .unknown)
    }
    func testInvalidNutritionAndFutureDayCannotQualify() {
        for calories in [Double.nan, .infinity, -1] {
            XCTAssertFalse(NutritionDayEvidence.isComplete(log(.complete, calories: calories), now: now))
        }
        XCTAssertFalse(NutritionDayEvidence.isComplete(log(.complete, date: now.addingTimeInterval(86_400)), now: now))
        XCTAssertTrue(NutritionDayEvidence.isComplete(DailyLog(date: now, meals: [], nutritionDayStatus: .complete), now: now))
    }
    func testWindowDeduplicatesCalendarDaysAndExcludesFuture() {
        let logs = [log(.complete), log(.partial, date: now.addingTimeInterval(60)), log(.complete, date: now.addingTimeInterval(86_400))]
        let days = NutritionDayEvidence.days(logs, from: now.addingTimeInterval(-86_400), through: now.addingTimeInterval(86_400), now: now)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].nutritionDayStatus, .partial)
    }
    func testReviewMergesWithConcurrentFoodAndWaterAndSurvivesEncoding() throws {
        let base = log()
        var reviewed = base.rememberingMutationBase()
        reviewed.nutritionDayStatus = .complete
        let review = try DailyLogMutation(userID: "a", log: reviewed)
        var food = base.rememberingMutationBase()
        food.meals[0].foodItems.append(FoodItem(id: "later", name: "Snack", calories: 200))
        food.waterTracker = WaterTracker(totalOunces: 8, date: now)
        let edit = try DailyLogMutation(userID: "a", log: food)
        let merged = edit.applying(to: review.applying(to: base))
        XCTAssertEqual(merged.nutritionDayStatus, .complete)
        XCTAssertEqual(merged.meals[0].foodItems.count, 2)
        XCTAssertEqual(merged.waterTracker?.totalOunces, 8)
        XCTAssertEqual(try JSONDecoder().decode(DailyLog.self, from: JSONEncoder().encode(merged)).nutritionDayStatus, .complete)
        var undo = reviewed.rememberingMutationBase()
        undo.nutritionDayStatus = nil
        let restored = try DailyLogMutation(userID: "a", log: undo).applying(to: merged)
        XCTAssertNil(restored.nutritionDayStatus)
        XCTAssertEqual(restored.meals[0].foodItems.count, 2)
    }
    func testLocalInsightsAndAIHistoryExcludeUnreviewedIntake() {
        let entries = [log(.complete, calories: 2_000), log(.partial, calories: 999, date: now.addingTimeInterval(-86_400)),
                       log(nil, calories: 888, date: now.addingTimeInterval(-2 * 86_400))]
        let summary = NutritionDayEvidence.historicalSummary(entries, now: now)
        XCTAssertTrue(summary.contains("1 of 3 recorded days"))
        XCTAssertFalse(summary.contains("999"))
        XCTAssertFalse(summary.contains("888"))
        let insights = InsightsRules.localInsights(from: entries, sleepHours: [],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"), now: now)
        XCTAssertTrue(insights.first { $0.title == "Calorie Trend Check" }?.message.contains("close to target") == true)
        let unknown = InsightsRules.localInsights(from: [log(nil)], sleepHours: [],
            goals: InsightsRules.GoalSnapshot(calories: 2_000, protein: 150, weightGoal: "Maintain"), now: now)
        XCTAssertFalse(unknown.contains { $0.title == "Calorie Trend Check" })
    }

    func testWeeklyAveragesExcludePartialAndUnknownButKeepFoodAccuracyReview() {
        let logs = [log(.complete), log(.partial, calories: 500, date: now.addingTimeInterval(-86_400)),
                    log(nil, calories: 9_000, date: now.addingTimeInterval(-2 * 86_400))]
        let recap = WeeklyRecapBuilder.build(weekEnding: now, dailyLogs: logs, sessionLogs: [], priorSessionLogs: [],
                                            weightHistory: [], calorieGoal: 2_000, now: now)
        XCTAssertEqual(recap.averageCalories, 2_000)
        XCTAssertEqual(recap.daysLogged, 3)
        XCTAssertEqual(recap.calorieAdherence.eligible, 1)
    }

    private func travelFixture() throws -> (calendar: Calendar, now: Date, logs: [DailyLog]) {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var remote = Calendar(identifier: .gregorian)
        remote.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let now = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 13)))
        let localDay = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)))
        let remoteMidnight = try XCTUnwrap(remote.date(from: DateComponents(year: 2026, month: 11, day: 4)))
        func reviewed(_ key: String, _ date: Date, _ calories: Double, zone: TimeZone) throws -> DailyLog {
            var value = DailyLog(id: key, date: date, meals: [Meal(name: "Recorded day", foodItems: [
                FoodItem(id: "food-" + key, name: "Meals", calories: calories, protein: 120)
            ])], nutritionDayStatus: .complete)
            let context = try XCTUnwrap(DiaryDayContext(userID: "traveler", date: date, timeZone: zone, dayKey: key))
            value.nutritionDayReview = try NutritionDayReview(ownerID: "traveler", day: context, status: .complete, log: value, at: now)
            return value
        }
        return (local, now, [try reviewed("2026-11-03", localDay, 1_900, zone: local.timeZone),
                            try reviewed("2026-11-04", remoteMidnight, 2_100, zone: remote.timeZone)])
    }

    func testCanonicalCivilDaysDoNotCollapseAfterTravelOrRewriteSavedSources() throws {
        let fixture = try travelFixture(), logs = fixture.logs, calendar = fixture.calendar
        XCTAssertTrue(calendar.isDate(logs[0].date, inSameDayAs: logs[1].date), "Both original timestamps now land on November 3")
        let before = try logs.map { try PlanFingerprint.make($0) }
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: fixture.now))
        let days = NutritionDayEvidence.days(Array(logs.reversed()), from: start, through: fixture.now, now: fixture.now, calendar: calendar)
        XCTAssertEqual(days.map(\.id), ["2026-11-03", "2026-11-04"])
        XCTAssertEqual(try days.map { try PlanFingerprint.make($0) }, before, "Projections must not normalize stored timestamps or receipts")
        XCTAssertTrue(days.allSatisfy { NutritionDayEvidence.isComplete($0, now: fixture.now, calendar: calendar) })
        let summary = NutritionDayEvidence.historicalSummary(logs, now: fixture.now, calendar: calendar)
        XCTAssertTrue(summary.contains("2 of 2 recorded days"))
        XCTAssertTrue(summary.contains("- 2026-11-03: Fully logged."))
        XCTAssertTrue(summary.contains("- 2026-11-04: Fully logged."))
    }

    func testCanonicalFutureAndChangedIntakeStayExcludedAfterTravel() throws {
        let fixture = try travelFixture(), calendar = fixture.calendar
        var changed = fixture.logs[1]
        changed.meals[0].foodItems[0].calories = 9_999
        XCTAssertEqual(NutritionDayEvidence.status(of: changed), .unknown)
        XCTAssertFalse(NutritionDayEvidence.isComplete(changed, now: fixture.now, calendar: calendar))
        var future = fixture.logs[0]
        future.id = "2026-11-05"; future.nutritionDayReview = nil
        XCTAssertFalse(NutritionDayEvidence.isComplete(future, now: fixture.now, calendar: calendar), "An old timestamp must not qualify a future canonical day")
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: fixture.now))
        let days = NutritionDayEvidence.days([fixture.logs[0], changed, future], from: start, through: fixture.now, now: fixture.now, calendar: calendar)
        XCTAssertEqual(days.map(\.id), ["2026-11-03", "2026-11-04"])
        let summary = NutritionDayEvidence.historicalSummary(days, now: fixture.now, calendar: calendar)
        XCTAssertTrue(summary.contains("1 of 2 recorded days")); XCTAssertFalse(summary.contains("9999"))
        XCTAssertTrue(summary.contains("- 2026-11-04: Not reviewed; excluded from intake analysis."))
    }

    func testAdaptiveAndInsightEvidenceUseCivilDatesAndKeepExactRawFingerprint() throws {
        let fixture = try travelFixture(), calendar = fixture.calendar, logs = fixture.logs
        let expected = try logs.map { try XCTUnwrap(NutritionDayEvidence.civilDate(for: $0, calendar: calendar)) }
        let inputs = AdaptiveEstimateInputs(weightHistory: [], dailyLogs: logs, now: fixture.now, calendar: calendar)
        XCTAssertEqual(inputs.intake.map(\.date), expected)
        XCTAssertEqual(inputs.intake.compactMap(\.calories), [1_900, 2_100])
        let snapshot = try InsightEvidenceSnapshot(ownerID: "traveler", logs: logs, sleepHoursByNight: [:], calorieGoal: 2_000,
            proteinGoal: 120, start: expected[0], end: fixture.now, origin: .localRules, now: fixture.now, calendar: calendar)
        XCTAssertEqual(snapshot.days.map(\.dayKey), ["2026-11-03", "2026-11-04"])
        XCTAssertEqual(snapshot.days.map(\.date), expected)
        XCTAssertEqual(snapshot.days.map(\.sourceFingerprint), try logs.map { try PlanFingerprint.make($0) })
        var differentAnchors = logs
        for index in differentAnchors.indices { differentAnchors[index].date = expected[index] }
        XCTAssertEqual(try AdaptiveEvidenceFingerprint.make(weightHistory: [], dailyLogs: logs, now: fixture.now, calendar: calendar),
                       try AdaptiveEvidenceFingerprint.make(weightHistory: [], dailyLogs: differentAnchors, now: fixture.now, calendar: calendar),
                       "Equivalent canonical-day inputs must not change the estimate because a saved timestamp used another zone")
        XCTAssertNotEqual(snapshot.days[1].date, logs[1].date, "Evidence display day is derived; the exact original still determines sourceFingerprint")
    }

    func testWeeklyRecapKeepsBothCanonicalDaysAndChangedDayHasNoIntakeAverage() throws {
        let fixture = try travelFixture(), calendar = fixture.calendar
        var logs = fixture.logs
        logs[1].meals[0].foodItems[0].calories = 9_999
        let recap = WeeklyRecapBuilder.build(weekEnding: fixture.now, calendar: calendar, dailyLogs: logs,
            sessionLogs: [], priorSessionLogs: [], weightHistory: [], calorieGoal: 1_900, now: fixture.now)
        XCTAssertEqual(recap.daysLogged, 2)
        XCTAssertEqual(recap.averageCalories, 1_900)
        XCTAssertEqual(recap.calorieAdherence.eligible, 1)
        XCTAssertEqual(recap.days.filter(\.nutritionLogged).map { calendar.component(.day, from: $0.date) }, [3, 4])
        let samePlan = InsightsRules.adaptiveCoachingPlan(today: logs[1], recentLogs: logs,
            goals: .init(calories: 2_000, protein: 120, weightGoal: "Maintain"), now: fixture.now, calendar: calendar)
        var canonicalToday = logs[1]; canonicalToday.date = fixture.now
        let reanchoredPlan = InsightsRules.adaptiveCoachingPlan(today: canonicalToday, recentLogs: logs,
            goals: .init(calories: 2_000, protein: 120, weightGoal: "Maintain"), now: fixture.now, calendar: calendar)
        XCTAssertEqual(samePlan, reanchoredPlan, "The current diary must be selected by canonical day, not its old midnight")
    }

}
