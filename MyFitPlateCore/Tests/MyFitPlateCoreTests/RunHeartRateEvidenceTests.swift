import XCTest
@testable import MyFitPlateCore

final class RunHeartRateEvidenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func sample(_ offset: Double, bpm: Double = 150, source: String = "watch") -> RunHeartRateSample {
        RunHeartRateSample(date: start.addingTimeInterval(offset), bpm: bpm, sourceID: source, sourceName: source)
    }
    private func recordedRun() -> Run {
        Run(id: "run", source: .recorded, startDate: start, endDate: start.addingTimeInterval(120), distanceMeters: 500, movingSeconds: 120)
    }

    func testGapsConflictingSamplesSourceChangesAndOutsideWindowCannotFillCoverage() {
        let samples = [sample(-5), sample(0), sample(10), sample(20, source: "strap"), sample(30, source: "strap"),
                       sample(40), sample(40, bpm: 170, source: "other"), sample(50), sample(60, bpm: .nan),
                       sample(70), sample(115), sample(120), sample(125)]
        let coverage = RunHeartRateEvidence.coverage(samples: samples, run: recordedRun(), settings: .estimated(age: 30))
        XCTAssertEqual(coverage.coveredSeconds, 25)
        XCTAssertEqual(coverage.zoneSeconds.reduce(0, +), 25)
        XCTAssertEqual(coverage.averageBPM, 150)
        XCTAssertEqual(coverage.sourceNames, ["strap", "watch"])
    }

    func testKnownPauseIsExcludedAndTwoMethodsProduceDifferentHonestZoneTimes() {
        var run = recordedRun()
        run.movingSeconds = 110
        run.pauseTimeline = RunPauseTimeline(completeness: .complete,
            intervals: [RunPauseInterval(startDate: start.addingTimeInterval(5), endDate: start.addingTimeInterval(15), origin: .explicitPause)])
        let samples = [sample(0), sample(10), sample(20), sample(30)]
        let estimate = RunHeartRateEvidence.coverage(samples: samples, run: run, settings: .estimated(age: 30))
        let entered = RunHeartRateEvidence.coverage(samples: samples, run: run, settings: .init(method: .enteredMaximum, maximumBPM: 170))
        XCTAssertEqual(estimate.coveredSeconds, 20)
        XCTAssertEqual(entered.coveredSeconds, 20)
        XCTAssertEqual(estimate.zoneSeconds[2], 20)
        XCTAssertEqual(entered.zoneSeconds[3], 20)
        XCTAssertNil(RunHeartRateEvidence.coverage(samples: [sample(0)], run: run, settings: .estimated(age: 30)).averageBPM)
    }

    func testSettingsAndHistoricalMethodRemainScopedAndRecalculationKeepsFirstReview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunHeartRateZoneStore(directory: directory)
        let estimated = RunHeartRateZoneSettings.estimated(age: 30)
        let entered = RunHeartRateZoneSettings(method: .enteredMaximum, maximumBPM: 175)
        _ = try store.review(runID: "run", settings: estimated, userID: "a", now: start)
        try store.saveSettings(entered, userID: "a")
        let review = try store.review(runID: "run", settings: entered, userID: "a", now: start.addingTimeInterval(10))
        XCTAssertEqual(review.originalMethod, estimated)
        XCTAssertEqual(review.originalReviewedAt, start)
        XCTAssertEqual(review.displayedMethod, entered)
        XCTAssertEqual(try store.settings(userID: "a", age: 40), entered)
        XCTAssertEqual(try store.settings(userID: "b", age: 40), .estimated(age: 40))
        XCTAssertThrowsError(try store.saveSettings(.init(method: .enteredMaximum, maximumBPM: .infinity), userID: "a"))
        XCTAssertEqual(try store.settings(userID: "a", age: 40), entered)
    }
}
