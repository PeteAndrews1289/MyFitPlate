import MyFitPlateShared
import XCTest

final class WorkoutActivityTimerRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testActiveRestKeepsItsOriginalDeadline() {
        let deadline = now.addingTimeInterval(45)
        let interval = WorkoutActivityTimerRules.restInterval(endingAt: deadline, now: now)
        XCTAssertEqual(interval.lowerBound, now)
        XCTAssertEqual(interval.upperBound, deadline)
    }

    func testExpiredRestRemainsAValidZeroDurationRangeWhenWidgetRebuilds() {
        let deadline = now.addingTimeInterval(-90)
        let interval = WorkoutActivityTimerRules.restInterval(endingAt: deadline, now: now)
        XCTAssertEqual(interval.lowerBound, deadline)
        XCTAssertEqual(interval.upperBound, deadline)
        XCTAssertEqual(interval.upperBound.timeIntervalSince(interval.lowerBound), 0)
    }

    func testExactDeadlineDoesNotExtendOrRestartRest() {
        let interval = WorkoutActivityTimerRules.restInterval(endingAt: now, now: now)
        XCTAssertEqual(interval.lowerBound, now)
        XCTAssertEqual(interval.upperBound, now)
    }

    func testUnusableDatesCannotCreateAnInvalidRange() {
        let badDate = Date(timeIntervalSince1970: .nan)
        let badDeadline = WorkoutActivityTimerRules.restInterval(endingAt: badDate, now: now)
        XCTAssertEqual(badDeadline.lowerBound, now)
        XCTAssertEqual(badDeadline.upperBound, now)
        let badClock = WorkoutActivityTimerRules.restInterval(endingAt: now, now: badDate)
        XCTAssertEqual(badClock.lowerBound, badClock.upperBound)
        XCTAssertTrue(badClock.lowerBound.timeIntervalSinceReferenceDate.isFinite)
    }
}
