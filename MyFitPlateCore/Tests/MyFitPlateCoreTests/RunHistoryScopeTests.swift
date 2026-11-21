import XCTest
@testable import MyFitPlateCore

final class RunHistoryScopeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "America/New_York")!
        value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4; return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
    private func run(_ id: String, at date: Date, source: Run.Source = .recorded, indoor: Bool = false) -> Run {
        Run(id: id, source: source, startDate: date, endDate: date.addingTimeInterval(600), distanceMeters: 1_000, movingSeconds: 600, isIndoor: indoor)
    }
    func testAllAvailableHasNoAgeOrCountCapAndCombinedFiltersDoNotChangeSource() {
        let originals = (0..<85).map { run("old-\($0)", at: date(2024, 2, 1).addingTimeInterval(Double($0) * 86400)) }
            + [run("watch", at: date(2026, 11, 4), source: .imported(appName: "Garmin Connect")), run("indoor", at: date(2026, 11, 4), indoor: true)]
        var scope = RunHistoryScope()
        XCTAssertEqual(scope.filtered(originals).count, 87)
        scope.environment = .outdoor; scope.source = "Garmin Connect"; scope.query = "garmin 2026-11-04"
        XCTAssertEqual(scope.filtered(originals, calendar: calendar).map(\.id), ["watch"])
        scope.query = "treadmill"; XCTAssertTrue(scope.filtered(originals, calendar: calendar).isEmpty)
        XCTAssertEqual(originals.count, 87)
    }
    func testSelectedWeekUsesCalendarIntervalAcrossYearBoundaryAndDST() throws {
        var scope = RunHistoryScope(selectedWeek: date(2026, 1, 1)); scope.period = .week
        let interval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: scope.selectedWeek))
        let runs = [run("start", at: interval.start), run("end", at: interval.end), run("before", at: interval.start.addingTimeInterval(-1))]
        XCTAssertEqual(scope.filtered(runs, calendar: calendar).map(\.id), ["start"])
        scope.selectedWeek = date(2026, 3, 8)
        let dst = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: scope.selectedWeek))
        XCTAssertNotEqual(dst.duration, 7 * 86400)
        XCTAssertEqual(scope.filtered([run("last", at: dst.end.addingTimeInterval(-1)), run("next", at: dst.end)], calendar: calendar).map(\.id), ["last"])
    }
    func testMonthAndSourceOptionsAreExplicitAndStable() {
        var scope = RunHistoryScope(); scope.period = .month
        let runs = [run("last-month", at: date(2026, 10, 31)), run("now", at: date(2026, 11, 1)), run("next-month", at: date(2026, 12, 1))]
        XCTAssertEqual(scope.filtered(runs, now: date(2026, 11, 4), calendar: calendar).map(\.id), ["now"])
        XCTAssertEqual(RunHistoryScope.sources(in: runs), ["MyFitPlate"])
    }
}
