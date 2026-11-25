import HealthKit
import XCTest
@testable import MyFitPlateCore

final class RecoveryEvidenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_792_411_200) // A fixed midday boundary.

    func testStagesOverlapAndInBedRecordsProduceNightTotals() throws {
        let end = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
        let start = end.addingTimeInterval(-7 * 3600)
        let stages = (0..<14).map { index in
            sample(start: start.addingTimeInterval(Double(index) * 1800), hours: 0.5, value: .asleepCore)
        }
        let inBed = sample(start: start.addingTimeInterval(-3600), hours: 9, value: .inBed)
        let duplicate = sample(start: start, hours: 7, value: .asleepUnspecified)
        let awake = sample(start: end, hours: 0.5, value: .awake)
        let nights = SleepEvidenceRules.hoursByNight(from: stages + [inBed, duplicate, awake], now: now, calendar: calendar)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(try XCTUnwrap(nights.values.first), 7, accuracy: 0.001)
    }

    func testEveningAndMorningStagesBelongToSameNightAndFutureIsExcluded() throws {
        let morning = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: now)!
        let samples = [sample(start: morning.addingTimeInterval(-4 * 3600), hours: 4, value: .asleepCore),
                       sample(start: morning, hours: 4, value: .asleepREM),
                       sample(start: now.addingTimeInterval(86_400), hours: 8, value: .asleepCore)]
        let nights = SleepEvidenceRules.hoursByNight(from: samples, now: now, calendar: calendar)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(try XCTUnwrap(nights.values.first), 8, accuracy: 0.001)
    }

    func testSparseOrStaleSleepCannotSteerRecovery() {
        let sparse = RecoveryEvidence(sleepAverageHours: 4, sleepNightCount: 1, sleepUpdatedAt: now, now: now)
        let stale = RecoveryEvidence(sleepAverageHours: 4, sleepNightCount: 6,
                                     sleepUpdatedAt: now.addingTimeInterval(-37 * 3600), now: now)
        let invalid = RecoveryEvidence(sleepAverageHours: .nan, sleepNightCount: 6, sleepUpdatedAt: now, now: now)
        XCTAssertEqual(sparse.sleepHoursForGuidance, 0)
        XCTAssertEqual(stale.sleepHoursForGuidance, 0)
        XCTAssertNil(invalid.sleepAverageHours)
    }

    func testPersonalBaselineDoesNotPenalizeNaturallyLowHRV() {
        let evidence = context(baseline: 22, recent: 22)
        XCTAssertEqual(evidence.hrvComparison, .withinUsual)
        XCTAssertEqual(evidence.hrvBaselineDays, 21)
        XCTAssertEqual(evidence.hrvRecentDays, 7)
    }

    func testRelativeDropMattersEvenWhenAbsoluteHRVIsHigh() {
        XCTAssertEqual(context(baseline: 100, recent: 70).hrvComparison, .belowUsual)
        XCTAssertEqual(context(baseline: 22, recent: 35).hrvComparison, .aboveUsual)
    }

    func testManyReadingsOnOneDayCannotSatisfyBaselineRequirement() {
        let readings = (0..<100).map { _ in RecoveryEvidence.HRVReading(date: now, milliseconds: 40) }
        let evidence = RecoveryEvidence(hrvReadings: readings, now: now, calendar: calendar)
        XCTAssertEqual(evidence.hrvComparison, .buildingBaseline)
        XCTAssertEqual(evidence.hrvRecentDays, 1)
    }

    func testDaysAreEquallyWeightedAndInvalidAndFutureReadingsAreIgnored() throws {
        var readings = history(baseline: 50, recent: 50)
        readings += (0..<100).map { _ in .init(date: now, milliseconds: 50) }
        readings += [.init(date: now.addingTimeInterval(86_400), milliseconds: 500),
                     .init(date: now, milliseconds: .nan), .init(date: now, milliseconds: -10)]
        let evidence = RecoveryEvidence(hrvReadings: readings, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(evidence.hrvRecentAverage), 50, accuracy: 0.001)
        XCTAssertEqual(evidence.hrvComparison, .withinUsual)
    }

    func testOldOrMissingReadingsNeverImplyReadiness() {
        let old = history(baseline: 60, recent: 30).filter { $0.date < now.addingTimeInterval(-48 * 3600) }
        XCTAssertEqual(RecoveryEvidence(hrvReadings: old, now: now, calendar: calendar).hrvComparison, .stale)
        XCTAssertEqual(RecoveryEvidence.unavailable.hrvComparison, .unavailable)
    }

    @MainActor
    func testHealthKitCoachingUsesWholeNightsRatherThanStageDurations() {
        let model = HealthKitViewModel(manager: MockHealthKitManager())
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!
        model.sleepSamples = (0..<3).flatMap { day in
            let end = calendar.date(byAdding: .day, value: -day, to: morning)!
            return (0..<14).map { stage in
                sample(start: end.addingTimeInterval(Double(stage - 14) * 1800), hours: 0.5, value: .asleepCore)
            }
        }
        let evidence = model.coachingRecoveryEvidence(now: now, calendar: calendar)
        XCTAssertEqual(evidence.sleepNightCount, 3)
        XCTAssertEqual(evidence.sleepHoursForGuidance, 7, accuracy: 0.001)
    }

    private func sample(start: Date, hours: Double, value: HKCategoryValueSleepAnalysis) -> HKCategorySample {
        HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, value: value.rawValue,
                         start: start, end: start.addingTimeInterval(hours * 3600))
    }

    private func context(baseline: Double, recent: Double) -> RecoveryEvidence {
        RecoveryEvidence(hrvReadings: history(baseline: baseline, recent: recent), now: now, calendar: calendar)
    }

    private func history(baseline: Double, recent: Double) -> [RecoveryEvidence.HRVReading] {
        (0..<28).map { day in
            .init(date: calendar.date(byAdding: .day, value: -day, to: now)!, milliseconds: day < 7 ? recent : baseline)
        }
    }
}
