import XCTest
@testable import MyFitPlateCore

final class RunPacingAnalysisTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func splits(_ seconds: [Double], distances: [Double]? = nil) -> [RunSplit] {
        seconds.enumerated().map { index, value in
            RunSplit(index: index + 1, distanceMeters: distances?[index] ?? 1_000, seconds: value)
        }
    }

    private func run(_ splits: [RunSplit], distance: Double? = nil, seconds: Double? = nil) -> Run {
        let active = seconds ?? splits.reduce(0) { $0 + $1.seconds }
        return Run(id: "same-recording", source: .recorded, startDate: start,
                   endDate: start.addingTimeInterval(active.isFinite ? max(0, active) : 1_000),
                   distanceMeters: distance ?? splits.reduce(0) { $0 + $1.distanceMeters },
                   movingSeconds: active, splits: splits, recordingID: "original-recording")
    }

    func testOddSplitCountComparesEqualDistanceRatherThanAssigningMiddleSplitToOneHalf() throws {
        let rows = splits([300, 400, 300])
        let result = try XCTUnwrap(RunPacingAnalysis.analyze(run: run(rows)))
        XCTAssertEqual(result.halfDistanceMeters, 1_500)
        XCTAssertEqual(result.firstHalfSeconds, 500)
        XCTAssertEqual(result.secondHalfSeconds, 500)
        XCTAssertEqual(result.finishDeltaSecondsPerKm, 0, accuracy: 0.0001)
        XCTAssertEqual(RunStats.negativeSplitDeltaSecondsPerKm(splits: rows), 0)
        XCTAssertFalse(RunStats.isNegativeSplit(splits: rows))
    }

    func testPartialTailContributesToHalvesButCannotBecomeBestFullSplit() throws {
        let rows = splits([400, 300, 50], distances: [1_000, 1_000, 250])
        let result = try XCTUnwrap(RunPacingAnalysis.analyze(run: run(rows)))
        XCTAssertEqual(result.coveredDistanceMeters, 2_250)
        XCTAssertEqual(result.halfDistanceMeters, 1_125)
        XCTAssertEqual(result.firstHalfSeconds, 437.5, accuracy: 0.0001)
        XCTAssertEqual(result.secondHalfSeconds, 312.5, accuracy: 0.0001)
        XCTAssertEqual(result.finishDeltaSecondsPerKm, 125 / 1.125, accuracy: 0.0001)
        XCTAssertEqual(result.splitCount, 3)
        XCTAssertEqual(result.completeSplitCount, 2)
        XCTAssertEqual(result.fastestCompleteSplitIndex, 2)
        XCTAssertEqual(result.completeSplitPaceSpreadSecondsPerKm, 100)
        XCTAssertEqual(result.source, .saved)
    }

    func testImperialSplitsAndQuarterMileTailRetainPhysicalDistanceAndTimes() throws {
        let mile = RunFormat.metersPerMile
        let rows = splits([480, 450, 90], distances: [mile, mile, mile / 4])
        let result = try XCTUnwrap(RunPacingAnalysis.analyze(run: run(rows)))
        XCTAssertEqual(result.halfDistanceMeters, mile * 1.125, accuracy: 0.0001)
        XCTAssertEqual(result.firstHalfSeconds, 536.25, accuracy: 0.0001)
        XCTAssertEqual(result.secondHalfSeconds, 483.75, accuracy: 0.0001)
        XCTAssertEqual(result.finishDeltaSecondsPerKm, 52.5 / (mile * 1.125 / 1_000), accuracy: 0.0001)
        XCTAssertEqual(result.completeSplitCount, 2)
        XCTAssertEqual(result.fastestCompleteSplitIndex, 2)
    }

    func testFasterAndSlowerHalvesUseAnExplicitConsistentDeltaSign() throws {
        let faster = splits([320, 280])
        let slower = splits([280, 320])
        XCTAssertEqual(try XCTUnwrap(RunPacingAnalysis.analyze(run: run(faster))).finishDeltaSecondsPerKm, 40)
        XCTAssertEqual(try XCTUnwrap(RunPacingAnalysis.analyze(run: run(slower))).finishDeltaSecondsPerKm, -40)
        XCTAssertTrue(RunStats.isNegativeSplit(splits: faster))
        XCTAssertFalse(RunStats.isNegativeSplit(splits: slower))
    }

    func testManualTreadmillProjectionCannotClaimMeasuredSteadinessOrBestSplit() throws {
        let treadmill = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 5_300,
                                                                       movingSeconds: 1_590, metric: true))
        XCTAssertNil(RunPacingAnalysis.analyze(run: treadmill))
        let outdoor = run(splits([300, 300]))
        XCTAssertNil(RunPacingAnalysis.analyze(run: outdoor, source: .manualEstimate))
    }

    func testElapsedRouteReplayMustMatchActiveTimeAndRetainsEstimateProvenance() throws {
        let rows = splits([600, 600])
        var paused = run(rows, seconds: 1_000)
        paused.endDate = start.addingTimeInterval(1_200)
        XCTAssertNil(RunPacingAnalysis.analyze(run: paused, splits: rows, source: .routeReplay))
        XCTAssertNil(RunPacingAnalysis.analyze(run: paused, splits: rows, source: .saved))
        let aligned = run(rows)
        let result = try XCTUnwrap(RunPacingAnalysis.analyze(run: aligned, splits: rows, source: .routeReplay))
        XCTAssertEqual(result.source, .routeReplay)
        XCTAssertEqual(result.firstHalfPaceSecondsPerKm, 600)
        XCTAssertEqual(result.secondHalfPaceSecondsPerKm, 600)
    }

    func testMissingDistanceOrTimeIsNotRescaledIntoAnInsight() {
        let rows = splits([300, 300])
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(rows, distance: 2_030)))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(rows, distance: 1_970)))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(rows, seconds: 610)))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(rows, seconds: 590)))
    }

    func testDuplicateOutOfOrderAndInvalidSplitValuesHaveNoConfidentAnalysis() {
        let original = run(splits([300, 300]))
        let good = RunSplit(index: 2, distanceMeters: 1_000, seconds: 300)
        let invalid = [
            [RunSplit(index: 0, distanceMeters: 1_000, seconds: 300), good],
            [RunSplit(index: 2, distanceMeters: 1_000, seconds: 300), good],
            [RunSplit(index: 1, distanceMeters: .nan, seconds: 300), good],
            [RunSplit(index: 1, distanceMeters: .infinity, seconds: 300), good],
            [RunSplit(index: 1, distanceMeters: 0, seconds: 300), good],
            [RunSplit(index: 1, distanceMeters: -1_000, seconds: 300), good],
            [RunSplit(index: 1, distanceMeters: 1_000, seconds: 0), good],
            [RunSplit(index: 1, distanceMeters: 1_000, seconds: -300), good],
            [RunSplit(index: 1, distanceMeters: 1_000, seconds: .infinity), good],
            [RunSplit(index: 1, distanceMeters: 1_000, seconds: .nan), good]
        ]
        for rows in invalid {
            XCTAssertNil(RunPacingAnalysis.analyze(run: original, splits: rows))
            XCTAssertNil(RunStats.negativeSplitDeltaSecondsPerKm(splits: rows))
            XCTAssertFalse(RunStats.isNegativeSplit(splits: rows))
        }
    }

    func testOnlyFinalShorterTailIsEligibleAndAnalysisHasAMeaningfulMinimum() {
        let middleTail = splits([300, 60, 300], distances: [1_000, 200, 1_000])
        let longerTail = splits([300, 360], distances: [1_000, 1_200])
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(middleTail)))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(longerTail)))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(splits([60, 60], distances: [200, 200]))))
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(splits([300]))))
        XCTAssertNotNil(RunPacingAnalysis.analyze(run: run(splits([75, 75], distances: [250, 250]))))
        let excessive = (1...4_097).map { RunSplit(index: $0, distanceMeters: 1_000, seconds: 300) }
        XCTAssertNil(RunPacingAnalysis.analyze(run: run(excessive)))
    }

    func testTiedCompleteSplitsHaveNoArbitrarySingleBestAndOneFullSplitHasNoSpread() throws {
        let tied = try XCTUnwrap(RunPacingAnalysis.analyze(run: run(splits([300, 300, 320]))))
        XCTAssertNil(tied.fastestCompleteSplitIndex)
        XCTAssertEqual(tied.completeSplitPaceSpreadSecondsPerKm, 20)
        let oneFull = try XCTUnwrap(RunPacingAnalysis.analyze(run: run(splits([300, 50], distances: [1_000, 200]))))
        XCTAssertEqual(oneFull.completeSplitCount, 1)
        XCTAssertNil(oneFull.fastestCompleteSplitIndex)
        XCTAssertNil(oneFull.completeSplitPaceSpreadSecondsPerKm)
    }

    func testInvalidRunTimingAndInconsistentCompletePauseTimelineStayUnavailable() {
        let rows = splits([300, 300])
        var value = run(rows)
        value.movingSeconds = .infinity
        XCTAssertNil(RunPacingAnalysis.analyze(run: value))
        value = run(rows)
        value.endDate = start.addingTimeInterval(-1)
        XCTAssertNil(RunPacingAnalysis.analyze(run: value))
        value = run(rows)
        value.endDate = start.addingTimeInterval(900)
        value.pauseTimeline = RunPauseTimeline(completeness: .complete, intervals: [
            RunPauseInterval(startDate: start.addingTimeInterval(100), endDate: start.addingTimeInterval(400), origin: .explicitPause)
        ])
        XCTAssertNotNil(RunPacingAnalysis.analyze(run: value))
        value.pauseTimeline = RunPauseTimeline(completeness: .complete)
        XCTAssertNil(RunPacingAnalysis.analyze(run: value))
    }
}
