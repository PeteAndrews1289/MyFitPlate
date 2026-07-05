import XCTest
@testable import MyFitPlateCore

/// Meters of northward travel per degree of latitude under the engine's earth radius.
private let metersPerLatDegree = 6_371_000.0 * .pi / 180

final class RunSessionTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    /// One fix per second heading due north at a steady speed — a clean synthetic GPS track.
    private func steadyFixes(seconds: Int, metersPerSecond: Double, startingAt date: Date, fromLat lat: Double = 40.0) -> [RunLocationFix] {
        (0...seconds).map { tick in
            RunLocationFix(
                latitude: lat + (Double(tick) * metersPerSecond) / metersPerLatDegree,
                longitude: -74.0,
                horizontalAccuracy: 5,
                timestamp: date.addingTimeInterval(Double(tick))
            )
        }
    }

    private func runningSession(metric: Bool = true) -> RunSession {
        let session = RunSession(metric: metric)
        session.start(at: start)
        return session
    }

    func testSteadyRunAccumulatesDistanceAndCutsSplitAtKilometer() {
        let session = runningSession()
        // 5:00 /km pace = 3.3333 m/s; 330 seconds ≈ 1.1 km.
        for fix in steadyFixes(seconds: 330, metersPerSecond: 10.0 / 3, startingAt: start) {
            session.ingest(fix)
        }

        XCTAssertEqual(session.distanceMeters, 1100, accuracy: 12)
        XCTAssertEqual(session.movingSeconds, 330, accuracy: 0.01)
        XCTAssertEqual(session.completedSplits.count, 1)
        XCTAssertEqual(session.completedSplits[0].index, 1)
        XCTAssertEqual(session.completedSplits[0].distanceMeters, 1000, accuracy: 0.01)
        XCTAssertEqual(session.completedSplits[0].seconds, 300, accuracy: 4, "The km boundary falls at ~5:00 and the crossing segment's time is apportioned")
        XCTAssertEqual(session.averagePaceSecondsPerKm ?? 0, 300, accuracy: 4)
    }

    func testImperialSessionCutsSplitAtOneMile() {
        let session = runningSession(metric: false)
        for fix in steadyFixes(seconds: 500, metersPerSecond: 10.0 / 3, startingAt: start) {
            session.ingest(fix)
        }
        XCTAssertEqual(session.completedSplits.count, 1)
        XCTAssertEqual(session.completedSplits[0].distanceMeters, RunFormat.metersPerMile, accuracy: 0.01)
    }

    func testInaccurateAndInvalidFixesAreDropped() {
        let session = runningSession()
        let good = steadyFixes(seconds: 10, metersPerSecond: 3, startingAt: start)
        for fix in good { session.ingest(fix) }
        let baseline = session.distanceMeters

        session.ingest(RunLocationFix(latitude: 41, longitude: -74, horizontalAccuracy: 80, timestamp: start.addingTimeInterval(11)))
        session.ingest(RunLocationFix(latitude: 41, longitude: -74, horizontalAccuracy: -1, timestamp: start.addingTimeInterval(12)))

        XCTAssertEqual(session.distanceMeters, baseline, "Fixes worse than the accuracy cutoff must not move the odometer")
    }

    func testTeleportIsRejectedButBecomesTheNewAnchor() {
        let session = runningSession()
        for fix in steadyFixes(seconds: 10, metersPerSecond: 3, startingAt: start) { session.ingest(fix) }
        let baseline = session.distanceMeters

        // 1 km in one second — impossible on foot.
        let teleport = RunLocationFix(
            latitude: 40 + 1000 / metersPerLatDegree + (30.0 / metersPerLatDegree),
            longitude: -74,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(11)
        )
        session.ingest(teleport)
        XCTAssertEqual(session.distanceMeters, baseline, accuracy: 0.5, "The jump itself adds nothing")

        // Continuing from the teleported position accrues normally again.
        session.ingest(RunLocationFix(
            latitude: teleport.latitude + 3 / metersPerLatDegree,
            longitude: -74,
            horizontalAccuracy: 5,
            timestamp: start.addingTimeInterval(12)
        ))
        XCTAssertEqual(session.distanceMeters, baseline + 3, accuracy: 0.5)
    }

    func testPauseFreezesEverythingAndResumeReAnchors() {
        let session = runningSession()
        for fix in steadyFixes(seconds: 60, metersPerSecond: 3, startingAt: start) { session.ingest(fix) }
        let frozenDistance = session.distanceMeters
        let frozenTime = session.movingSeconds

        session.pause(at: start.addingTimeInterval(61))
        for fix in steadyFixes(seconds: 30, metersPerSecond: 3, startingAt: start.addingTimeInterval(62), fromLat: 40.01) {
            session.ingest(fix)
        }
        XCTAssertEqual(session.distanceMeters, frozenDistance)
        XCTAssertEqual(session.movingSeconds, frozenTime)

        session.resume(at: start.addingTimeInterval(100))
        let resumed = steadyFixes(seconds: 10, metersPerSecond: 3, startingAt: start.addingTimeInterval(100), fromLat: 40.02)
        for fix in resumed { session.ingest(fix) }

        XCTAssertEqual(session.distanceMeters, frozenDistance + 30, accuracy: 1,
                       "First post-resume fix re-anchors (no distance); the rest accrue — the walk during the pause never counts")
    }

    func testFinishKeepsThePartialSplitAndBuildsTheRun() throws {
        let session = runningSession()
        for fix in steadyFixes(seconds: 150, metersPerSecond: 10.0 / 3, startingAt: start) { session.ingest(fix) }

        let run = try XCTUnwrap(session.finish(at: start.addingTimeInterval(151)))
        XCTAssertEqual(run.source, .recorded)
        XCTAssertEqual(run.distanceMeters, 500, accuracy: 6)
        XCTAssertEqual(run.splits.count, 1, "The unfinished tail is preserved as a partial split")
        XCTAssertEqual(run.splits[0].distanceMeters, 500, accuracy: 6)
        XCTAssertTrue(run.hasRoute)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNil(session.finish(), "Double-finish returns nothing")
    }

    func testCurrentPaceReflectsTheLastMinute() {
        let session = runningSession()
        for fix in steadyFixes(seconds: 90, metersPerSecond: 10.0 / 3, startingAt: start) { session.ingest(fix) }
        XCTAssertEqual(session.currentPaceSecondsPerKm ?? 0, 300, accuracy: 8, "Steady 3.33 m/s reads as ~5:00 /km")
    }

    func testIngestBeforeStartDoesNothing() {
        let session = RunSession(metric: true)
        session.ingest(RunLocationFix(latitude: 40, longitude: -74, horizontalAccuracy: 5, timestamp: start))
        XCTAssertEqual(session.distanceMeters, 0)
        XCTAssertEqual(session.routePointCount, 0)
    }
}

final class RunEnergyTests: XCTestCase {

    func testFlatRunEstimateMatchesTheStandardFormula() {
        // 5 km at 165 lbs (74.8 kg): 5 × 74.8 × 1.036 ≈ 388 kcal.
        XCTAssertEqual(RunEnergy.estimateKcal(distanceMeters: 5000, weightLbs: 165), 387.7, accuracy: 1)
    }

    func testDegenerateInputsProduceZero() {
        XCTAssertEqual(RunEnergy.estimateKcal(distanceMeters: 0, weightLbs: 165), 0)
        XCTAssertEqual(RunEnergy.estimateKcal(distanceMeters: 5000, weightLbs: 0), 0)
    }
}

final class RunFormatTests: XCTestCase {

    func testDistanceTextInBothUnitSystems() {
        XCTAssertEqual(RunFormat.distanceText(meters: 5020, metric: true), "5.02 km")
        XCTAssertEqual(RunFormat.distanceText(meters: 12_100, metric: true), "12.1 km")
        XCTAssertEqual(RunFormat.distanceText(meters: 5000, metric: false), "3.11 mi")
        XCTAssertEqual(RunFormat.distanceText(meters: 21_097.5, metric: false), "13.1 mi")
    }

    func testPaceTextInBothUnitSystems() {
        XCTAssertEqual(RunFormat.paceText(secondsPerKm: 300, metric: true), "5:00 /km")
        XCTAssertEqual(RunFormat.paceText(secondsPerKm: 300, metric: false), "8:03 /mi")
        XCTAssertNil(RunFormat.paceText(secondsPerKm: nil, metric: true))
        XCTAssertNil(RunFormat.paceText(secondsPerKm: 0, metric: true))
        XCTAssertNil(RunFormat.paceText(secondsPerKm: 60 * 60, metric: true), "An hour per km is not a pace worth showing")
    }

    func testDurationText() {
        XCTAssertEqual(RunFormat.durationText(seconds: 65), "1:05")
        XCTAssertEqual(RunFormat.durationText(seconds: 3661), "1:01:01")
        XCTAssertEqual(RunFormat.durationText(seconds: 0), "0:00")
    }
}

final class RunImportRulesTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_750_010_000)

    private func garminRun(distance: Double = 5000, hasRoute: Bool = false, hr: Double? = 152) -> ImportedWorkoutSummary {
        ImportedWorkoutSummary(
            uuid: UUID().uuidString,
            activity: .running,
            startDate: noon,
            endDate: noon.addingTimeInterval(1500),
            distanceMeters: distance,
            activeCalories: 380,
            averageHeartRate: hr,
            sourceName: "Garmin Connect",
            sourceBundleID: "com.garmin.connect.mobile",
            hasRoute: hasRoute
        )
    }

    func testGarminWorkoutMapsToAnImportedRun() {
        let run = RunImportRules.run(from: garminRun())
        XCTAssertEqual(run.source, .imported(appName: "Garmin Connect"))
        XCTAssertEqual(run.source.displayName, "Garmin Connect")
        XCTAssertEqual(run.distanceMeters, 5000)
        XCTAssertEqual(run.movingSeconds, 1500)
        XCTAssertEqual(run.averageHeartRate, 152)
    }

    func testOwnRecordingsComeBackAsRecordedRuns() {
        let own = ImportedWorkoutSummary(
            uuid: "x", activity: .running,
            startDate: noon, endDate: noon.addingTimeInterval(1500),
            distanceMeters: 5000,
            sourceName: "MyFitPlate", sourceBundleID: "MyFitPlate.CalorieBeta"
        )
        XCTAssertTrue(RunImportRules.isImportableRun(own))
        XCTAssertEqual(RunImportRules.run(from: own).source, .recorded)
        XCTAssertEqual(RunImportRules.run(from: own).source.displayName, "MyFitPlate")
        XCTAssertTrue(RunImportRules.isImportableRun(garminRun()))
    }

    func testOnlyRunningActivitiesQualify() {
        for activity in [ImportedWorkoutSummary.Activity.walking, .hiking, .cycling, .other] {
            let workout = ImportedWorkoutSummary(
                uuid: "x", activity: activity,
                startDate: noon, endDate: noon.addingTimeInterval(3600),
                distanceMeters: 8000,
                sourceName: "Garmin Connect", sourceBundleID: "com.garmin.connect.mobile"
            )
            XCTAssertFalse(RunImportRules.isImportableRun(workout), "\(activity) must not enter run stats")
        }
    }

    func testFalseStartsAreDroppedButTreadmillsKept() {
        let falseStart = ImportedWorkoutSummary(
            uuid: "x", activity: .running,
            startDate: noon, endDate: noon.addingTimeInterval(45),
            distanceMeters: 20,
            sourceName: "Apple Watch", sourceBundleID: "com.apple.health"
        )
        XCTAssertFalse(RunImportRules.isImportableRun(falseStart))

        let treadmill = ImportedWorkoutSummary(
            uuid: "y", activity: .running,
            startDate: noon, endDate: noon.addingTimeInterval(1800),
            distanceMeters: 4200,
            sourceName: "Polar Flow", sourceBundleID: "fi.polar.polarflow",
            isIndoor: true
        )
        XCTAssertTrue(RunImportRules.isImportableRun(treadmill))
    }

    func testParallelWatchesCollapseToTheRicherRecording() {
        // Same physical run: Apple Watch (route + HR) and Garmin (HR only), distances 4% apart.
        let appleWatch = Run(
            id: "aw", source: .imported(appName: "Apple Watch"),
            startDate: noon, endDate: noon.addingTimeInterval(1500),
            distanceMeters: 5000, movingSeconds: 1500,
            averageHeartRate: 150, hasRoute: true
        )
        let garmin = Run(
            id: "g", source: .imported(appName: "Garmin Connect"),
            startDate: noon.addingTimeInterval(20), endDate: noon.addingTimeInterval(1520),
            distanceMeters: 5200, movingSeconds: 1500,
            averageHeartRate: 149
        )

        let kept = RunImportRules.deduplicated([garmin, appleWatch])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.id, "aw", "Route + heart rate beats heart rate alone")
    }

    func testSeparateRunsOnTheSameDaySurvive() {
        let morning = Run(
            id: "m", source: .imported(appName: "Garmin Connect"),
            startDate: noon.addingTimeInterval(-6 * 3600), endDate: noon.addingTimeInterval(-6 * 3600 + 1800),
            distanceMeters: 6000, movingSeconds: 1800
        )
        let evening = Run(
            id: "e", source: .imported(appName: "Garmin Connect"),
            startDate: noon.addingTimeInterval(6 * 3600), endDate: noon.addingTimeInterval(6 * 3600 + 1800),
            distanceMeters: 6000, movingSeconds: 1800
        )
        XCTAssertEqual(RunImportRules.deduplicated([morning, evening]).count, 2)
    }

    func testDeduplicatedRunsReturnNewestFirst() {
        let oldest = Run(
            id: "old", source: .imported(appName: "Garmin Connect"),
            startDate: noon.addingTimeInterval(-7_200), endDate: noon.addingTimeInterval(-5_400),
            distanceMeters: 5000, movingSeconds: 1800
        )
        let newest = Run(
            id: "new", source: .recorded,
            startDate: noon, endDate: noon.addingTimeInterval(1_500),
            distanceMeters: 5000, movingSeconds: 1500
        )

        XCTAssertEqual(RunImportRules.deduplicated([oldest, newest]).map(\.id), ["new", "old"])
    }

    func testOverlappingButDifferentDistancesAreNotMerged() {
        // Overlapping windows but 30% distance disagreement — likely a watch left running.
        let a = Run(id: "a", source: .imported(appName: "Apple Watch"),
                    startDate: noon, endDate: noon.addingTimeInterval(3000),
                    distanceMeters: 5000, movingSeconds: 3000)
        let b = Run(id: "b", source: .imported(appName: "Garmin Connect"),
                    startDate: noon, endDate: noon.addingTimeInterval(3000),
                    distanceMeters: 6500, movingSeconds: 3000)
        XCTAssertEqual(RunImportRules.deduplicated([a, b]).count, 2)
    }
}

final class RunRecorderRulesTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_750_200_000)
    private var end: Date { start.addingTimeInterval(1800) }

    func testWatchRecordingTheSameWindowTriggersTheGuard() {
        let watch = (start: start.addingTimeInterval(-30), end: end.addingTimeInterval(60), isOwn: false)
        XCTAssertTrue(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: [watch]),
                      "A parallel watch recording must suppress our energy/distance samples")
    }

    func testOwnWorkoutsNeverTriggerTheGuard() {
        let ours = (start: start, end: end, isOwn: true)
        XCTAssertFalse(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: [ours]))
    }

    func testBriefBrushesAndAdjacentWorkoutsDoNotTrigger() {
        let brush = (start: end.addingTimeInterval(-45), end: end.addingTimeInterval(600), isOwn: false)
        XCTAssertFalse(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: [brush]),
                       "45 seconds of overlap is a coincidence, not a parallel recording")

        let earlier = (start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(-60), isOwn: false)
        XCTAssertFalse(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: [earlier]))
        XCTAssertFalse(RunRecorderRules.hasExternalOverlap(runStart: start, runEnd: end, workouts: []))
    }
}
