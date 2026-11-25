import XCTest
@testable import MyFitPlateCore

final class WeightTrendProjectionTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "America/New_York")!; return value }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! }
    private func sample(_ day: Int, pounds: Double, id: String? = nil, hourOffset: Int = 0) -> AdaptiveWeightEvidence {
        .init(id: id ?? "day-\(day)", date: calendar.date(byAdding: .day, value: day, to: start)!.addingTimeInterval(Double(hourOffset) * 3_600), pounds: pounds)
    }

    func testElapsedCivilDaysNotSampleCountDetermineRateAcrossDSTAndIrregularGaps() throws {
        let dense = (0...21).map { sample($0, pounds: 180 - Double($0) * 0.1) }
        let sparse = [0, 1, 4, 7, 8, 14, 21].map { dense[$0] }
        let full = WeightTrendRules.project(dense, calendar: calendar), irregular = WeightTrendRules.project(sparse, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(full.ratePerDay), -0.1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(irregular.ratePerDay), -0.1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(full.change), try XCTUnwrap(irregular.change), accuracy: 0.000001)
        XCTAssertEqual(full.spanDays, 22)
        XCTAssertEqual(full.measuredDays, 22); XCTAssertEqual(irregular.measuredDays, 7)
    }

    func testRepeatedMeasurementsOnOneDayCannotIncreaseThatDaysTrendWeight() throws {
        let base = [sample(0, pounds: 180), sample(7, pounds: 179), sample(14, pounds: 178)]
        let extra = base + (0..<20).map { sample(7, pounds: 179, id: "duplicate-\($0)") }
        let original = WeightTrendRules.project(base, calendar: calendar), repeated = WeightTrendRules.project(extra, calendar: calendar)
        XCTAssertEqual(repeated, original)
        XCTAssertNil(WeightTrendRules.project([sample(0, pounds: 180), sample(0, pounds: 180, id: "same-day")], calendar: calendar).ratePerDay)
    }

    func testSpikeDoesNotReplaceRobustDirectionAndLongGapsAreSeparateSegments() throws {
        var values = (0...14).map { sample($0, pounds: 180 - Double($0) * 0.1) }
        values[7] = sample(7, pounds: 190)
        let trend = WeightTrendRules.project(values, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(trend.ratePerDay), -0.1, accuracy: 0.000001)
        let gap = WeightTrendRules.project([sample(0, pounds: 180), sample(1, pounds: 180), sample(15, pounds: 179), sample(16, pounds: 179)], calendar: calendar)
        XCTAssertEqual(gap.points.map(\.segment), [0, 0, 1, 1])
        XCTAssertTrue(gap.description.contains("unconnected"))
    }

    func testSharedShadowSlopesMatchExistingElapsedDayFormulaExactly() {
        let values = [sample(0, pounds: 180), sample(4, pounds: 183), sample(8, pounds: 179), sample(21, pounds: 177)]
        let rawSlopes: [Double] = [(179.0 - 180.0) / 8.0, (177.0 - 180.0) / 21.0, (177.0 - 183.0) / 17.0, (177.0 - 179.0) / 13.0]
        let expected = rawSlopes.sorted()
        XCTAssertEqual(WeightTrendRules.sortedSlopes(values, calendar: calendar), expected)
    }

    func testLargeHistoryIsBoundedAndKeepsAllMeasurementDaysAndUnknownsHonest() {
        let values = (0..<2_000).map { sample($0, pounds: 180) }
        let trend = WeightTrendRules.project(values, calendar: calendar)
        XCTAssertEqual(trend.points.count, 2_000); XCTAssertEqual(trend.sampledDays, 181)
        XCTAssertLessThanOrEqual(WeightTrendRules.sortedSlopes(values, calendar: calendar).count, 181 * 180 / 2)
        let invalid = WeightTrendRules.project([sample(0, pounds: .nan), sample(1, pounds: -1)], calendar: calendar)
        XCTAssertTrue(invalid.points.isEmpty); XCTAssertNil(invalid.ratePerDay)
    }
}
