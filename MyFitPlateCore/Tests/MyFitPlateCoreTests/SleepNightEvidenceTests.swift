import HealthKit
import XCTest
@testable import MyFitPlateCore

final class SleepNightEvidenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func sample(_ start: String, _ end: String, _ type: HKCategoryValueSleepAnalysis) -> HKCategorySample {
        HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, value: type.rawValue,
                         start: date(start), end: date(end))
    }
    func testConflictingStagesBecomeUnspecifiedWithoutDoubleCountingTotal() throws {
        let samples = [sample("2026-11-03T22:00:00-05:00", "2026-11-04T06:00:00-05:00", .inBed),
                       sample("2026-11-03T23:00:00-05:00", "2026-11-04T05:00:00-05:00", .asleepUnspecified),
                       sample("2026-11-03T23:00:00-05:00", "2026-11-04T03:00:00-05:00", .asleepCore),
                       sample("2026-11-04T02:00:00-05:00", "2026-11-04T04:00:00-05:00", .asleepREM)]
        let night = try XCTUnwrap(SleepNightEvidence.normalize(samples, now: date("2026-11-04T12:00:00-05:00"), calendar: calendar).first)
        XCTAssertEqual(night.timeAsleep, 6 * 3600)
        XCTAssertEqual(night.timeCore, 3 * 3600)
        XCTAssertEqual(night.timeREM, 3600)
        XCTAssertEqual(night.conflictingStageDuration, 3600)
        XCTAssertEqual(night.timeUnspecified, 2 * 3600)
        XCTAssertEqual(night.timeCore + night.timeDeep + night.timeREM + night.timeUnspecified, night.timeAsleep)
        XCTAssertEqual(night.sourceSampleIDs.count, 4)
    }
    func testFallBackUsesElapsedDurationAndDuplicateSampleIsIdempotent() throws {
        let record = sample("2026-10-31T23:00:00-04:00", "2026-11-01T07:00:00-05:00", .asleepUnspecified)
        let one = SleepNightEvidence.normalize([record], now: date("2026-11-02T12:00:00Z"), calendar: calendar)
        let duplicate = SleepNightEvidence.normalize([record, record], now: date("2026-11-02T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(one, duplicate)
        XCTAssertEqual(try XCTUnwrap(one.first).timeAsleep, 9 * 3600)
        XCTAssertEqual(one.first?.timeInBed, 0, "No in-bed evidence must not be invented from envelope")
    }
    func testBoundarySplitPreservesActualTotalAcrossDistinctNights() {
        let sample = sample("2026-11-03T17:30:00-05:00", "2026-11-03T19:30:00-05:00", .asleepUnspecified)
        let nights = SleepNightEvidence.normalize([sample], now: date("2026-11-04T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights.reduce(0) { $0 + $1.timeAsleep }, 2 * 3600)
        XCTAssertEqual(Set(nights.map(\.id)).count, 2)
    }
    func testDaytimeEpisodeRemainsVisibleButGapDoesNotBecomeSleep() throws {
        let records = [sample("2026-11-03T23:00:00-05:00", "2026-11-04T06:00:00-05:00", .asleepCore),
                       sample("2026-11-04T13:00:00-05:00", "2026-11-04T13:30:00-05:00", .asleepUnspecified)]
        let night = try XCTUnwrap(SleepNightEvidence.normalize(records, now: date("2026-11-04T20:00:00Z"), calendar: calendar).first)
        XCTAssertEqual(night.episodes.count, 2); XCTAssertEqual(night.daytimeEpisodeCount, 1)
        XCTAssertEqual(night.timeAsleep, 7.5 * 3600)
    }
    func testFutureAndInBedOnlySamplesDoNotInventNights() {
        let now = date("2026-11-04T12:00:00-05:00")
        let records = [sample("2026-11-03T22:00:00-05:00", "2026-11-04T06:00:00-05:00", .inBed),
                       sample("2026-11-04T23:00:00-05:00", "2026-11-05T06:00:00-05:00", .asleepCore)]
        XCTAssertTrue(SleepNightEvidence.normalize(records, now: now, calendar: calendar).isEmpty)
    }
    @MainActor
    func testDuplicateDecodedCacheIsRejectedWithoutRewritingItsBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = EditorDraftStore(directory: directory)
        let store = SleepHistoryStore(store: drafts)
        let record = sample("2026-11-03T23:00:00-05:00", "2026-11-04T06:00:00-05:00", .asleepCore)
        let night = try XCTUnwrap(SleepNightEvidence.normalize([record], now: date("2026-11-05T12:00:00Z"), calendar: calendar).first)
        let value = SleepHistorySnapshot(ownerID: "owner", startDay: night.night, endDay: night.night,
            timeZoneIdentifier: calendar.timeZone.identifier, nights: [night, night])
        XCTAssertThrowsError(try store.save(value, currentUserID: "owner"))
        let scope = "sleep-history-v1:\(night.night.timeIntervalSince1970):\(night.night.timeIntervalSince1970):\(calendar.timeZone.identifier)"
        try drafts.save(value, userID: "owner", scope: scope)
        XCTAssertThrowsError(try store.load(userID: "owner", start: night.night, end: night.night, zone: calendar.timeZone.identifier))
        XCTAssertEqual(try drafts.load(SleepHistorySnapshot.self, userID: "owner", scope: scope)?.value, value)
    }
    @MainActor
    func testCacheKeepsExactOwnerAndRangeAndRejectsCrossAccountOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SleepHistoryStore(store: EditorDraftStore(directory: directory))
        let day = calendar.startOfDay(for: date("2026-11-03T22:00:00-05:00"))
        let value = SleepHistorySnapshot(ownerID: "owner", startDay: day, endDay: day,
            timeZoneIdentifier: calendar.timeZone.identifier, nights: [])
        try store.save(value, currentUserID: "owner")
        XCTAssertThrowsError(try store.save(value, currentUserID: "other"))
        XCTAssertEqual(try store.load(userID: "owner", start: day, end: day, zone: calendar.timeZone.identifier), value)
        XCTAssertNil(try store.load(userID: "other", start: day, end: day, zone: calendar.timeZone.identifier))
        XCTAssertNil(try store.load(userID: "owner", start: day, end: day.addingTimeInterval(86400), zone: calendar.timeZone.identifier))
    }
}
