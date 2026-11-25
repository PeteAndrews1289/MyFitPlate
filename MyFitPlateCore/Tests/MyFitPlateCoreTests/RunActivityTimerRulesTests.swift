import XCTest
import MyFitPlateShared

final class RunActivityTimerRulesTests: XCTestCase {
    private let reportedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testKilledRecorderClockHasFixedNumericCapEvenIfOSNeverMarksItStale() throws {
        let start = reportedAt.addingTimeInterval(-190.997)
        let interval = try XCTUnwrap(RunActivityTimerRules.elapsedInterval(startTime: start, reportedAt: reportedAt))
        XCTAssertEqual(interval.lowerBound, start)
        XCTAssertEqual(interval.upperBound, reportedAt.addingTimeInterval(25))
        XCTAssertEqual(interval.upperBound.timeIntervalSince(start), 215.997, accuracy: 0.001)
        XCTAssertLessThan(interval.upperBound, reportedAt.addingTimeInterval(300))
        XCTAssertEqual(RunActivityTimerRules.elapsedInterval(startTime: start, reportedAt: reportedAt), interval,
                       "Re-rendering an old snapshot must not move its cutoff forward")
    }

    func testHealthyUpdateExtendsFreshClockUsingSameActiveAnchor() throws {
        let start = reportedAt.addingTimeInterval(-60)
        let previous = try XCTUnwrap(RunActivityTimerRules.elapsedInterval(startTime: start, reportedAt: reportedAt))
        let update = reportedAt.addingTimeInterval(8)
        let next = try XCTUnwrap(RunActivityTimerRules.elapsedInterval(startTime: start, reportedAt: update))
        XCTAssertEqual(next.lowerBound, previous.lowerBound)
        XCTAssertEqual(next.upperBound.timeIntervalSince(previous.upperBound), 8)
        XCTAssertTrue(RunActivityTimerRules.isFresh(reportedAt: update, now: update.addingTimeInterval(24)))
        XCTAssertFalse(RunActivityTimerRules.isFresh(reportedAt: update, now: update.addingTimeInterval(25)))
    }

    func testLegacyOrInvalidSnapshotCannotStartAnUnboundedTimer() {
        XCTAssertNil(RunActivityTimerRules.elapsedInterval(startTime: reportedAt, reportedAt: nil))
        XCTAssertFalse(RunActivityTimerRules.isFresh(reportedAt: nil, now: reportedAt))
        let invalid = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertNil(RunActivityTimerRules.elapsedInterval(startTime: invalid, reportedAt: reportedAt))
        XCTAssertNil(RunActivityTimerRules.freshnessDeadline(reportedAt: invalid))
        XCTAssertNil(RunActivityTimerRules.elapsedInterval(startTime: reportedAt.addingTimeInterval(1), reportedAt: reportedAt))
    }

    func testStaleAndReversedClocksRequireSnapshotLabels() {
        XCTAssertTrue(RunActivityTimerRules.isFresh(reportedAt: reportedAt, now: reportedAt))
        XCTAssertFalse(RunActivityTimerRules.isFresh(reportedAt: reportedAt, now: reportedAt.addingTimeInterval(300)))
        XCTAssertFalse(RunActivityTimerRules.isFresh(reportedAt: reportedAt, now: reportedAt.addingTimeInterval(-1)))
        XCTAssertFalse(RunActivityTimerRules.isFresh(reportedAt: reportedAt, now: Date(timeIntervalSinceReferenceDate: .infinity)))
    }
}
