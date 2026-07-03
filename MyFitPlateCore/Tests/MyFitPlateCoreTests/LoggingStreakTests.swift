import XCTest
@testable import MyFitPlateCore

final class LoggingStreakTests: XCTestCase {

    private let calendar = Calendar.current
    private let today = Date()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today))!
            .addingTimeInterval(10 * 60 * 60)
    }

    private func streak(_ offsets: [Int]) -> Int {
        LoggingStreak.currentStreak(loggedDays: offsets.map(day), today: today, calendar: calendar)
    }

    func testUnbrokenRunCountsAllDays() {
        XCTAssertEqual(streak([0, 1, 2, 3, 4]), 5)
    }

    func testUnloggedTodayDoesNotPunishAMorningOpen() {
        XCTAssertEqual(streak([1, 2, 3]), 3)
    }

    func testSingleMissedDayBendsButDoesNotBreak() {
        // Logged today, missed yesterday, logged the two days before: 3 logged days survive.
        XCTAssertEqual(streak([0, 2, 3]), 3)
    }

    func testTwoConsecutiveMissesBreakTheStreak() {
        // Today logged, but the two days before are empty — streak restarts at 1.
        XCTAssertEqual(streak([0, 3, 4]), 1)
    }

    func testGraceUsedOnlyOnce() {
        // Two separate single-day gaps: the second gap ends the walk.
        // Logged: 0, gap 1, logged 2, gap 3, logged 4 -> counts 0 and 2 only.
        XCTAssertEqual(streak([0, 2, 4]), 2)
    }

    func testStreakSurvivesUnloggedTodayViaGraceDay() {
        // Nothing today or yesterday, but a run before that: grace reaches back once.
        XCTAssertEqual(streak([2, 3, 4]), 3)
        XCTAssertTrue(LoggingStreak.isOnGraceDay(loggedDays: [2, 3, 4].map(day), today: today, calendar: calendar))
    }

    func testThreeDayGapIsDead() {
        XCTAssertEqual(streak([3, 4, 5]), 0)
    }

    func testEmptyHistory() {
        XCTAssertEqual(streak([]), 0)
        XCTAssertFalse(LoggingStreak.isOnGraceDay(loggedDays: [], today: today, calendar: calendar))
    }

    func testNotOnGraceDayWhenTodayLogged() {
        XCTAssertFalse(LoggingStreak.isOnGraceDay(loggedDays: [0, 1].map(day), today: today, calendar: calendar))
    }
}
