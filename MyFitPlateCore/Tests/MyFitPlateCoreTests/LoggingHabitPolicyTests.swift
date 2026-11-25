import XCTest
@testable import MyFitPlateCore

final class LoggingHabitPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = .gmt; return value
    }
    private func date(_ day: Int) -> Date { calendar.date(from: .init(year: 2026, month: 11, day: day))! }
    private func log(_ day: Int, status: NutritionDayStatus? = nil, entry: Bool = true) -> DailyLog {
        let food = FoodItem(id: "food-\(day)", name: "Rice", calories: 100, protein: 2, carbs: 20, fats: 1)
        return .init(id: "2026-11-\(String(format: "%02d", day))", date: date(day), meals: entry ? [.init(name: "Dinner", foodItems: [food])] : [], nutritionDayStatus: status)
    }
    private func preferences(_ rule: LoggingHabitPreferences.Rule = .anyEntry) -> LoggingHabitPreferences {
        var value = LoggingHabitPreferences(); value.reviewed = true; value.rule = rule; return value
    }
    func testInitialMissConsumesTheOnlyGraceAndSecondSeparatedMissEndsChain() {
        let days = [date(1), date(2), date(4), date(6)]
        let value = LoggingHabitRules.streak(loggedDays: days, today: date(8), calendar: calendar)
        XCTAssertEqual(value.count, 1)
        XCTAssertEqual(value.qualifyingDates, [date(6)])
        XCTAssertEqual(value.graceDates, [date(7)])
        XCTAssertEqual(LoggingStreak.currentStreak(loggedDays: days, today: date(8), calendar: calendar), 2, "Legacy intentionally retains its deployed definition")
    }
    func testUnloggedTodayDoesNotConsumeGraceButASecondPriorMissDoes() {
        let value = LoggingHabitRules.streak(loggedDays: [date(2), date(4), date(5), date(7)], today: date(8), calendar: calendar)
        XCTAssertEqual(value.count, 3)
        XCTAssertEqual(value.graceDates, [date(6)])
        XCTAssertFalse(value.graceDates.contains(date(8)))
    }
    func testTwoConsecutiveMissingDaysDoNotManufactureBridge() {
        let value = LoggingHabitRules.streak(loggedDays: [date(1), date(2)], today: date(5), calendar: calendar)
        XCTAssertEqual(value.count, 0); XCTAssertTrue(value.graceDates.isEmpty)
    }
    func testCalendarMarksTheIncludedEarlierGraceAndDoesNotLosePartialEvidence() {
        let logs = [log(2, status: .complete), log(3, status: .partial), log(4, status: .complete), log(5, status: .complete)]
        let summary = LoggingHabitRules.make(logs: logs, preferences: preferences(.reviewedComplete), today: date(6), from: date(1), calendar: calendar)
        XCTAssertEqual(summary.count, 3)
        let partial = summary.days.first { $0.date == date(3) }
        XCTAssertEqual(partial?.state, .partial)
        XCTAssertEqual(partial?.isGraceDay, true)
        XCTAssertEqual(partial?.qualifiesForRule, false)
        XCTAssertEqual(summary.days.filter(\.isGraceDay).count, 1)
        XCTAssertEqual(summary.days.last?.state, .open)
    }
    func testUnreviewedPreferenceKeepsLegacyUntilExplicitReview() {
        let logs = [log(1), log(2), log(4), log(6)]
        let before = LoggingHabitRules.make(logs: logs, preferences: .init(), today: date(8), from: date(1), calendar: calendar)
        let after = LoggingHabitRules.make(logs: logs, preferences: preferences(), today: date(8), from: date(1), calendar: calendar)
        XCTAssertEqual(before.count, 2); XCTAssertEqual(after.count, 1)
    }
    func testAnyEntryAndReviewedCompleteCalendarQualificationAgreeWithCount() {
        let logs = [log(1, status: .partial), log(2, status: .complete, entry: false), log(3, status: .complete)]
        let entry = LoggingHabitRules.make(logs: logs, preferences: preferences(), today: date(3), from: date(1), calendar: calendar)
        let reviewed = LoggingHabitRules.make(logs: logs, preferences: preferences(.reviewedComplete), today: date(3), from: date(1), calendar: calendar)
        XCTAssertEqual(entry.count, 2); XCTAssertEqual(reviewed.count, 2)
        XCTAssertEqual(entry.days.map(\.qualifiesForRule), [true, false, true])
        XCTAssertEqual(reviewed.days.map(\.qualifiesForRule), [false, true, true])
        XCTAssertEqual(entry.days[1].state, .complete, "Evidence stays fully reviewed even when no-entry rule excludes it")
        XCTAssertTrue(entry.days[1].isGraceDay)
    }
    func testCanonicalCivilDayDoesNotMoveToYesterdayAfterTravel() throws {
        var newYork = calendar; newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var losAngeles = calendar; losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let original = try XCTUnwrap(newYork.date(from: .init(year: 2026, month: 11, day: 2)))
        var saved = log(2); saved.date = original
        let now = try XCTUnwrap(losAngeles.date(from: .init(year: 2026, month: 11, day: 3)))
        let first = try XCTUnwrap(losAngeles.date(from: .init(year: 2026, month: 11, day: 1)))
        let snapshot = try PlanFingerprint.make(saved)
        let summary = LoggingHabitRules.make(logs: [saved], preferences: preferences(), today: now, from: first, calendar: losAngeles)
        XCTAssertEqual(summary.days.map(\.qualifiesForRule), [false, true, false])
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(try PlanFingerprint.make(saved), snapshot)
    }
    func testDuplicateCivilDayUsesLastSnapshotAndFutureCivilDayIsExcluded() {
        let summary = LoggingHabitRules.make(logs: [log(1), log(1, entry: false), log(2), log(5)], preferences: preferences(), today: date(3), from: date(1), calendar: calendar)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.days.map(\.qualifiesForRule), [false, true, false])
    }
    func testPausedCalendarKeepsEvidenceButNoGraceOrBoundaryClaim() {
        var paused = preferences(); paused.paused = true
        let value = LoggingHabitRules.make(logs: [log(1), log(3)], preferences: paused, today: date(4), from: date(1), calendar: calendar)
        XCTAssertEqual(value.count, 0); XCTAssertFalse(value.reachedHistoryBoundary)
        XCTAssertFalse(value.days.contains(where: \.isGraceDay))
        XCTAssertEqual(value.days.filter(\.qualifiesForRule).count, 2)
    }
    func testBoundaryOnlyMarkedWhenCurrentChainReachesFirstLoadedDay() {
        let value = LoggingHabitRules.make(logs: [log(1), log(2), log(4)], preferences: preferences(), today: date(5), from: date(1), calendar: calendar)
        XCTAssertTrue(value.reachedHistoryBoundary); XCTAssertEqual(value.count, 3)
        let stopped = LoggingHabitRules.make(logs: [log(1), log(4)], preferences: preferences(), today: date(5), from: date(1), calendar: calendar)
        XCTAssertFalse(stopped.reachedHistoryBoundary); XCTAssertEqual(stopped.count, 1)
    }
}
