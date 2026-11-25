import XCTest
@testable import MyFitPlateCore

final class RunPauseTimelineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func session(_ id: String = "stable-run") -> RunSession {
        let value = RunSession(metric: true, timeAccounting: .activeElapsed, id: id)
        value.start(at: start)
        return value
    }

    private func interval(_ from: Double, _ to: Double, _ origin: RunPauseInterval.Origin = .explicitPause) -> RunPauseInterval {
        RunPauseInterval(startDate: date(from), endDate: date(to), origin: origin)
    }

    func testNewUninterruptedRecordingHasVerifiedEmptyTimelineAndOriginalIdentity() throws {
        let value = session()
        let run = try XCTUnwrap(value.finish(at: date(120)))
        let timeline = try XCTUnwrap(run.pauseTimeline)
        XCTAssertEqual(timeline.completeness, .complete)
        XCTAssertTrue(timeline.intervals.isEmpty)
        XCTAssertNil(timeline.openPause)
        XCTAssertEqual(timeline.validatedUnionIntervals(startDate: start, endDate: date(120), activeSeconds: 120), [])
        XCTAssertEqual(run.startDate, start)
        XCTAssertEqual(run.endDate, date(120))
        XCTAssertEqual(run.id, "stable-run")
        XCTAssertEqual(run.recordingID, "stable-run")
        XCTAssertEqual(run.movingSeconds, 120)
    }

    func testMultipleFractionalPausesRetainExactEventsAndReconcileActiveClock() throws {
        let value = session()
        value.pause(at: date(12.25))
        value.resume(at: date(20.75))
        value.pause(at: date(50.125))
        value.resume(at: date(55.375))
        let run = try XCTUnwrap(value.finish(at: date(80.5)))
        let timeline = try XCTUnwrap(run.pauseTimeline)
        XCTAssertEqual(timeline.intervals, [interval(12.25, 20.75), interval(50.125, 55.375)])
        XCTAssertEqual(run.movingSeconds, 66.75, accuracy: 0.0001)
        let summary = try XCTUnwrap(timeline.summary(startDate: start, endDate: run.endDate, activeSeconds: run.movingSeconds))
        XCTAssertEqual(summary.excludedSeconds, 13.75, accuracy: 0.0001)
        XCTAssertEqual(summary.explicitPauseSeconds, 13.75, accuracy: 0.0001)
        XCTAssertEqual(summary.recoveryGapSeconds, 0)
        XCTAssertEqual(value.activeElapsedSeconds(at: date(900)), 66.75, accuracy: 0.0001)
        XCTAssertNil(value.finish(at: date(900)))
    }

    func testFinishingWhilePausedClosesTheActualOpenPauseAtOriginalEnd() throws {
        let value = session()
        value.pause(at: date(30))
        let snapshot = try XCTUnwrap(value.snapshot(at: date(70)))
        XCTAssertEqual(snapshot.pauseTimeline?.openPause?.startDate, date(30))
        let run = try XCTUnwrap(value.finish(at: date(100)))
        XCTAssertEqual(run.movingSeconds, 30)
        XCTAssertEqual(run.endDate, date(100))
        XCTAssertEqual(run.pauseTimeline?.intervals, [interval(30, 100)])
        XCTAssertNil(run.pauseTimeline?.openPause)
    }

    func testRepeatedRecoveryPreservesTheFirstCheckpointGapAndEarlierExplicitPauses() throws {
        let original = session()
        original.pause(at: date(10))
        original.resume(at: date(20))
        let checkpoint = try XCTUnwrap(original.snapshot(at: date(60)))
        let first = try XCTUnwrap(RunSession(snapshot: checkpoint, at: date(500)))
        XCTAssertEqual(first.pauseTimeline.openPause?.startDate, date(60))
        XCTAssertEqual(first.pauseTimeline.openPause?.origin, .recoveryGap)
        let secondCheckpoint = try XCTUnwrap(first.snapshot(at: date(550)))
        let decoded = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONEncoder().encode(secondCheckpoint))
        let second = try XCTUnwrap(RunSession(snapshot: decoded, at: date(900)))
        XCTAssertEqual(second.pauseTimeline.openPause?.startDate, date(60))
        second.resume(at: date(1_000))
        let run = try XCTUnwrap(second.finish(at: date(1_100)))
        XCTAssertEqual(run.id, original.id)
        XCTAssertEqual(run.movingSeconds, 150)
        let timeline = try XCTUnwrap(run.pauseTimeline)
        XCTAssertEqual(timeline.completeness, .complete)
        XCTAssertEqual(timeline.intervals, [interval(10, 20), interval(60, 1_000, .recoveryGap)])
        let summary = try XCTUnwrap(timeline.summary(startDate: start, endDate: date(1_100), activeSeconds: 150))
        XCTAssertEqual(summary.explicitPauseSeconds, 10)
        XCTAssertEqual(summary.recoveryGapSeconds, 940)
        XCTAssertEqual(summary.excludedSeconds, 950)
    }

    func testAlreadyPausedRecoveryRetainsExplicitBoundaryWithoutDoubleCountingTimeAway() throws {
        let original = session()
        original.pause(at: date(60))
        let checkpoint = try XCTUnwrap(original.snapshot(at: date(100)))
        let first = try XCTUnwrap(RunSession(snapshot: checkpoint, at: date(500)))
        let later = try XCTUnwrap(first.snapshot(at: date(600)))
        let second = try XCTUnwrap(RunSession(snapshot: later, at: date(700)))
        XCTAssertEqual(second.pauseTimeline.openPause, RunPauseTimeline.OpenPause(startDate: date(60), origin: .explicitPause))
        second.resume(at: date(800))
        let run = try XCTUnwrap(second.finish(at: date(900)))
        XCTAssertEqual(run.movingSeconds, 160)
        XCTAssertEqual(run.pauseTimeline?.intervals, [interval(60, 800)])
        XCTAssertEqual(run.pauseTimeline?.summary(startDate: start, endDate: date(900), activeSeconds: 160)?.recoveryGapSeconds, 0)
    }

    func testRecoveredRecordingCanFinishPausedWithGapBeginningAtCheckpointRatherThanRestore() throws {
        let original = session()
        let checkpoint = try XCTUnwrap(original.snapshot(at: date(60)))
        let restored = try XCTUnwrap(RunSession(snapshot: checkpoint, at: date(500)))
        let run = try XCTUnwrap(restored.finish(at: date(600)))
        XCTAssertEqual(run.movingSeconds, 60)
        XCTAssertEqual(run.startDate, start)
        XCTAssertEqual(run.endDate, date(600))
        XCTAssertEqual(run.pauseTimeline?.intervals, [interval(60, 600, .recoveryGap)])
    }

    func testLegacyCheckpointKeepsUnknownEarlierPausesAndOnlyAddsKnownRecoveryGap() throws {
        let original = session()
        original.pause(at: date(10))
        original.resume(at: date(20))
        let checkpoint = try XCTUnwrap(original.snapshot(at: date(60)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
        object.removeValue(forKey: "pauseTimeline")
        let legacy = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.pauseTimeline)
        let restored = try XCTUnwrap(RunSession(snapshot: legacy, at: date(500)))
        restored.resume(at: date(600))
        let run = try XCTUnwrap(restored.finish(at: date(700)))
        let timeline = try XCTUnwrap(run.pauseTimeline)
        XCTAssertEqual(timeline.completeness, .partial)
        XCTAssertEqual(timeline.intervals, [interval(60, 600, .recoveryGap)])
        XCTAssertEqual(run.movingSeconds, 150)
        XCTAssertNotNil(timeline.validatedUnionIntervals(startDate: start, endDate: date(700), activeSeconds: 150))
        XCTAssertNil(RunPauseTimeline(completeness: .complete, intervals: timeline.intervals)
            .validatedUnionIntervals(startDate: start, endDate: date(700), activeSeconds: 150),
                     "The missing ten seconds cannot become an invented pause at the end")
    }

    func testUnionAndSummaryDoNotDoubleCountOverlapsOrLoseOriginalOrigins() throws {
        let intervals = [interval(50, 55), interval(30, 50, .recoveryGap), interval(20, 40)]
        let timeline = RunPauseTimeline(completeness: .complete, intervals: intervals)
        XCTAssertEqual(timeline.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 65),
                       [DateInterval(start: date(20), end: date(55))])
        let summary = try XCTUnwrap(timeline.summary(startDate: start, endDate: date(100), activeSeconds: 65))
        XCTAssertEqual(summary.excludedSeconds, 35)
        XCTAssertEqual(summary.explicitPauseSeconds, 25)
        XCTAssertEqual(summary.recoveryGapSeconds, 10)
        XCTAssertEqual(timeline.intervals, intervals)
        XCTAssertEqual(try JSONDecoder().decode(RunPauseTimeline.self, from: JSONEncoder().encode(timeline)), timeline)
    }

    func testInvalidIntervalsBoundsAndDurationMismatchFailWithoutManufacturingEvents() {
        let invalid = [
            RunPauseTimeline(completeness: .complete, intervals: [interval(40, 30)]),
            RunPauseTimeline(completeness: .complete, intervals: [interval(-1, 10)]),
            RunPauseTimeline(completeness: .complete, intervals: [interval(90, 101)]),
            RunPauseTimeline(completeness: .complete, intervals: [
                RunPauseInterval(startDate: Date(timeIntervalSince1970: .infinity), endDate: date(20), origin: .explicitPause)
            ]),
            RunPauseTimeline(completeness: .complete, intervals: Array(repeating: interval(10, 20), count: RunPauseTimeline.maximumIntervals + 1)),
            RunPauseTimeline(completeness: .complete, intervals: [interval(10, 20)])
        ]
        for timeline in invalid {
            XCTAssertNil(timeline.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 100))
        }
        let partial = RunPauseTimeline(completeness: .partial, intervals: [interval(10, 20)])
        XCTAssertNil(partial.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 91))
        XCTAssertNotNil(partial.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 80))
        XCTAssertNil(partial.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: .nan))
        XCTAssertNil(partial.validatedUnionIntervals(startDate: date(100), endDate: start, activeSeconds: 0))
    }

    func testOpenPauseIsOnlyValidForCheckpointsAndBadCompleteCheckpointCannotRestore() throws {
        let open = RunPauseTimeline(completeness: .complete,
                                    openPause: .init(startDate: date(70), origin: .explicitPause))
        XCTAssertNil(open.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 70))
        XCTAssertEqual(open.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 70, allowOpenPause: true),
                       [DateInterval(start: date(70), end: date(100))])
        let value = session()
        value.pause(at: date(10))
        value.resume(at: date(20))
        let checkpoint = try XCTUnwrap(value.snapshot(at: date(60)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
        object["pauseTimeline"] = ["completeness": "complete", "intervals": []] as [String: Any]
        let inconsistent = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(RunSession(snapshot: inconsistent, at: date(500)))
    }

    func testRunCodableCompatibilityAndReidentificationPreserveEveryRecordedField() throws {
        let timeline = RunPauseTimeline(completeness: .complete, intervals: [interval(10, 20)])
        let run = Run(id: "original", source: .recorded, startDate: start, endDate: date(100),
                      distanceMeters: 300, movingSeconds: 90, activeCalories: 25, averageHeartRate: 130,
                      isIndoor: false, splits: [RunSplit(index: 1, distanceMeters: 300, seconds: 90)],
                      hasRoute: true, shoeID: "shoe", pauseTimeline: timeline, recordingID: "recording-original")
        let data = try JSONEncoder().encode(run)
        XCTAssertEqual(try JSONDecoder().decode(Run.self, from: data), run)
        let reidentified = run.reidentified(as: "health-uuid")
        XCTAssertEqual(reidentified.id, "health-uuid")
        XCTAssertEqual(reidentified.recordingID, "recording-original")
        XCTAssertEqual(reidentified.reidentified(as: run.id), run)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "pauseTimeline")
        object.removeValue(forKey: "recordingID")
        let legacy = try JSONDecoder().decode(Run.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.pauseTimeline)
        XCTAssertNil(legacy.recordingID)
        XCTAssertEqual(legacy.id, run.id)
        XCTAssertEqual(legacy.movingSeconds, run.movingSeconds)
        XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 300,
                                                       movingSeconds: 100, metric: true)?.pauseTimeline)
    }

    func testGPSAccountingModesRetainKnownPausesWithoutClaimingExactActiveTimeline() throws {
        for mode in [RunSession.TimeAccounting.moving, .elapsed] {
            let value = RunSession(metric: true, timeAccounting: mode)
            value.start(at: start)
            value.pause(at: date(20))
            value.resume(at: date(50))
            let run = try XCTUnwrap(value.finish(at: date(100)))
            XCTAssertEqual(run.pauseTimeline?.completeness, .partial)
            XCTAssertEqual(run.pauseTimeline?.intervals, [interval(20, 50)])
            XCTAssertEqual(run.movingSeconds, 0)
            XCTAssertNotNil(run.pauseTimeline?.validatedUnionIntervals(startDate: start, endDate: date(100), activeSeconds: 0))
        }
    }
}
