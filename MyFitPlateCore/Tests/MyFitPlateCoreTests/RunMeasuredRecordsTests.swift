import XCTest
@testable import MyFitPlateCore

final class RunMeasuredRecordsTests: XCTestCase {
    func testBestFiveKilometersUsesExactContiguousFullSplitsAndSupportingIdentity() {
        let run = recording(times: [400, 300, 290, 280, 270, 260, 250])
        let summary = RunMeasuredRecords.summarize([run, run.reidentified(as: "health")])
        XCTAssertEqual(summary.eligibleRuns, 1)
        let five = summary.records.first { $0.distanceMeters == 5_000 }
        XCTAssertEqual(five?.seconds, 1_350)
        XCTAssertEqual(five?.firstSplit, 3)
        XCTAssertEqual(five?.lastSplit, 7)
        XCTAssertEqual(five?.recordingID, "recording")
        XCTAssertNil(summary.records.first { $0.distanceMeters == 10_000 })
        XCTAssertNil(summary.records.first { $0.distanceMeters == RunFormat.metersPerMile })
    }

    func testUncertainOrNoncontinuousEvidenceCannotClaimMeasuredRecord() {
        let valid = recording(times: [300, 300])
        var imported = valid; imported.source = .imported(appName: "Watch")
        var treadmill = valid; treadmill.isIndoor = true
        var unknown = valid; unknown.pauseTimeline = nil
        var broken = valid; broken.routeSegmentStarts = [valid.startDate, valid.startDate.addingTimeInterval(10)]
        var invalid = valid; invalid.splits[0] = RunSplit(index: 1, distanceMeters: 1_000, seconds: .nan)
        for run in [imported, treadmill, unknown, broken, invalid] {
            XCTAssertTrue(RunMeasuredRecords.summarize([run]).records.isEmpty)
        }
    }

    func testMileRecordsNeverScaleIntoFiveKAndPartialTailCannotWin() {
        var run = recording(times: [400, 390], unit: RunFormat.metersPerMile)
        run.splits.append(RunSplit(index: 3, distanceMeters: 100, seconds: 10))
        run.distanceMeters += 100; run.movingSeconds += 10; run.endDate = run.endDate.addingTimeInterval(10)
        let summary = RunMeasuredRecords.summarize([run])
        XCTAssertEqual(summary.records.count, 1)
        XCTAssertEqual(summary.records.first?.distanceMeters, RunFormat.metersPerMile)
        XCTAssertEqual(summary.records.first?.seconds, 390)
        XCTAssertEqual(summary.records.first?.firstSplit, 2)
    }

    private func recording(times: [Double], unit: Double = 1_000) -> Run {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let total = times.reduce(0, +)
        return Run(id: "recording", source: .recorded, startDate: start, endDate: start.addingTimeInterval(total),
            distanceMeters: Double(times.count) * unit, movingSeconds: total,
            splits: times.enumerated().map { RunSplit(index: $0.offset + 1, distanceMeters: unit, seconds: $0.element) },
            pauseTimeline: RunPauseTimeline(completeness: .complete), recordingID: "recording", routeSegmentStarts: [start])
    }
}

extension RunMeasuredRecordsTests {
    func testSimilarDistanceDoesNotMixIntervalsWithUnstructuredRuns() {
        var current = recording(times: [300, 300, 300, 300, 300])
        let step = RunWorkoutStep(id: "work", kind: .hard, title: "Intervals", goal: .duration(seconds: 60))
        current.workoutResult = RunWorkoutResult(runID: current.id, planID: "one", planName: "Intervals", completedAt: current.endDate,
            steps: [RunWorkoutStepResult(stepIndex: 0, step: step, startedAtElapsedSeconds: 0, endedAtElapsedSeconds: 60,
                startedAtDistanceMeters: 0, endedAtDistanceMeters: 200, isComplete: true)])
        var matching = current.reidentified(as: "prior")
        matching.recordingID = "prior"
        matching.movingSeconds = 1_600
        var unstructured = current.reidentified(as: "easy")
        unstructured.recordingID = "easy"
        unstructured.workoutResult = nil
        var different = current.reidentified(as: "different")
        different.recordingID = "different"
        different.workoutResult?.steps[0].step.goal = .distance(meters: 400)
        let comparison = RunStats.ghostPaceComparison(for: current, against: [matching, unstructured, different])
        XCTAssertEqual(comparison?.matchingRunsCount, 1)
        XCTAssertEqual(comparison?.averagePaceSecondsPerKm, 320)
    }
}
