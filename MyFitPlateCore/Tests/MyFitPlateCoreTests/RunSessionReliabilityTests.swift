import XCTest
@testable import MyFitPlateCore

final class RunSessionReliabilityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)
    private let metersPerDegree = 6_371_000.0 * .pi / 180

    private func fix(_ seconds: Double, meters: Double) -> RunLocationFix {
        RunLocationFix(latitude: 40 + meters / metersPerDegree, longitude: -74,
                       horizontalAccuracy: 5, timestamp: start.addingTimeInterval(seconds))
    }

    func testActiveClockIncludesGPSWaitAndTailButExcludesEveryExplicitPause() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        XCTAssertEqual(session.activeElapsedSeconds(at: start.addingTimeInterval(20)), 20)
        session.ingest(fix(20, meters: 0))
        session.ingest(fix(30, meters: 30))
        session.ingest(fix(40, meters: 60))
        session.pause(at: start.addingTimeInterval(45))
        XCTAssertEqual(session.activeElapsedSeconds(at: start.addingTimeInterval(100)), 45)
        XCTAssertFalse(session.ingest(fix(80, meters: 500)))
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertFalse(session.ingest(fix(90, meters: 700)), "Queued points from the paused period are stale")
        XCTAssertTrue(session.ingest(fix(105, meters: 1_000)))
        XCTAssertTrue(session.ingest(fix(115, meters: 1_030)))
        let run = try XCTUnwrap(session.finish(at: start.addingTimeInterval(120)))
        XCTAssertEqual(run.distanceMeters, 90, accuracy: 0.001)
        XCTAssertEqual(run.movingSeconds, 65, accuracy: 0.001)
        XCTAssertEqual(run.splits.first?.seconds ?? 0, 65, accuracy: 0.001)
        XCTAssertEqual(session.activeElapsedSeconds(at: start.addingTimeInterval(1_000)), 65,
                       "Finished clocks remain frozen")
        XCTAssertEqual(run.id, session.id)
    }

    func testLongGPSOutageCannotCreateAnImpossiblePaceOrStaleLiveReading() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        session.ingest(fix(0, meters: 0))
        session.ingest(fix(300, meters: 500))
        XCTAssertEqual(session.movingSeconds, 300)
        XCTAssertEqual(session.averagePaceSecondsPerKm ?? 0, 600, accuracy: 0.001)
        XCTAssertNil(session.currentPaceSecondsPerKm(at: start.addingTimeInterval(300)))
        session.ingest(fix(305, meters: 515))
        session.ingest(fix(315, meters: 545))
        XCTAssertEqual(session.currentPaceSecondsPerKm(at: start.addingTimeInterval(315)) ?? 0,
                       1_000 / 3, accuracy: 0.001)
        XCTAssertNil(session.currentPaceSecondsPerKm(at: start.addingTimeInterval(331)))
        let run = try XCTUnwrap(session.finish(at: start.addingTimeInterval(340)))
        XCTAssertEqual(run.movingSeconds, 340)
        XCTAssertEqual(run.splits.first?.seconds, 340)
    }

    func testInvalidCoordinatesDatesAndOldFixesDoNotPoisonTheNextAnchor() {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        for point in [
            RunLocationFix(latitude: .nan, longitude: -74, horizontalAccuracy: 5, timestamp: start),
            RunLocationFix(latitude: 91, longitude: -74, horizontalAccuracy: 5, timestamp: start),
            RunLocationFix(latitude: 40, longitude: 181, horizontalAccuracy: 5, timestamp: start),
            RunLocationFix(latitude: 40, longitude: -74, horizontalAccuracy: .infinity, timestamp: start),
            RunLocationFix(latitude: 40, longitude: -74, horizontalAccuracy: 5,
                           timestamp: Date(timeIntervalSince1970: .infinity)),
            fix(-10, meters: 0)
        ] {
            XCTAssertFalse(session.ingest(point))
        }
        XCTAssertEqual(session.routePointCount, 0)
        XCTAssertTrue(session.ingest(fix(0, meters: 0)))
        XCTAssertTrue(session.ingest(fix(10, meters: 30)))
        XCTAssertFalse(session.ingest(fix(5, meters: 1_000)))
        XCTAssertFalse(session.ingest(fix(10, meters: 1_000)))
        XCTAssertEqual(session.lastAcceptedFixTimestamp, start.addingTimeInterval(10))
        XCTAssertTrue(session.ingest(fix(20, meters: 60)))
        XCTAssertEqual(session.distanceMeters, 60, accuracy: 0.001)
        XCTAssertEqual(session.routePointCount, 3)
    }

    func testPauseClearsPaceAndRejectsBackwardLifecycleDates() {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        session.ingest(fix(0, meters: 0))
        session.ingest(fix(10, meters: 30))
        XCTAssertNotNil(session.currentPaceSecondsPerKm)
        session.pause(at: start.addingTimeInterval(9))
        XCTAssertEqual(session.state, .running)
        session.pause(at: start.addingTimeInterval(11))
        XCTAssertNil(session.currentPaceSecondsPerKm)
        session.resume(at: start.addingTimeInterval(10))
        XCTAssertEqual(session.state, .paused)
        session.resume(at: start.addingTimeInterval(100))
        XCTAssertNil(session.currentPaceSecondsPerKm)
        XCTAssertFalse(session.ingest(fix(99, meters: 300)))
        XCTAssertNil(session.finish(at: start.addingTimeInterval(90)))
        XCTAssertEqual(session.state, .running)
    }

    func testCoordinateFreeSnapshotRestoresPausedWithExactSplitTailAndStableRunIdentity() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run-stable")
        session.start(at: start)
        session.ingest(fix(0, meters: 0))
        session.ingest(fix(300, meters: 1_000))
        session.ingest(fix(330, meters: 1_100))
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(340)))
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("latitude"))
        let decoded = try JSONDecoder().decode(RunSession.Snapshot.self, from: data)
        XCTAssertEqual(snapshot, decoded)
        let restored = try XCTUnwrap(RunSession(snapshot: decoded, at: start.addingTimeInterval(1_000)))
        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.activeElapsedSeconds(at: start.addingTimeInterval(1_100)), 340)
        XCTAssertEqual(restored.routePointCount, 0)
        XCTAssertNil(restored.lastAcceptedFixTimestamp)
        XCTAssertNil(restored.currentPaceSecondsPerKm)
        XCTAssertEqual(restored.completedSplits, snapshot.completedSplits)
        restored.resume(at: start.addingTimeInterval(1_100))
        restored.ingest(fix(1_110, meters: 30_000))
        restored.ingest(fix(1_140, meters: 30_100))
        let run = try XCTUnwrap(restored.finish(at: start.addingTimeInterval(1_150)))
        XCTAssertEqual(run.id, "run-stable")
        XCTAssertEqual(run.distanceMeters, 1_200, accuracy: 0.001)
        XCTAssertEqual(run.movingSeconds, 390, accuracy: 0.001)
        XCTAssertEqual(run.splits.count, 2)
        XCTAssertEqual(run.splits[0].seconds, 300, accuracy: 0.001)
        XCTAssertEqual(run.splits[1].seconds, 90, accuracy: 0.001)
    }

    func testRecoveredRunCanFinishWithoutRevivingTimeOrClaimingAnUnsavedRoute() throws {
        let session = RunSession(metric: false, timeAccounting: .activeElapsed)
        session.start(at: start)
        session.ingest(fix(0, meters: 0))
        session.ingest(fix(60, meters: 180))
        session.pause(at: start.addingTimeInterval(65))
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(100)))
        let restored = try XCTUnwrap(RunSession(snapshot: snapshot, at: start.addingTimeInterval(500)))
        let run = try XCTUnwrap(restored.finish(at: start.addingTimeInterval(600)))
        XCTAssertEqual(restored.splitDistanceMeters, RunFormat.metersPerMile)
        XCTAssertEqual(run.movingSeconds, 65)
        XCTAssertEqual(run.id, session.id)
        XCTAssertFalse(run.hasRoute)
        XCTAssertNil(restored.snapshot(at: start.addingTimeInterval(700)))
    }

    func testMalformedCheckpointCannotInventDistanceOrActiveTime() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        session.ingest(fix(0, meters: 0))
        session.ingest(fix(60, meters: 180))
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(60)))
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["distanceMeters"] = 10_000
        let wrongDistance = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(RunSession(snapshot: wrongDistance, at: start.addingTimeInterval(100)))
        object["distanceMeters"] = snapshot.distanceMeters
        object["activeElapsedSeconds"] = 120
        let wrongTime = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(RunSession(snapshot: wrongTime, at: start.addingTimeInterval(100)))
        XCTAssertNil(RunSession(snapshot: snapshot, at: start.addingTimeInterval(59)))
    }

    func testManualRunAndFormattingRejectNonfiniteAndUnboundedInputsWithoutIntegerConversion() {
        for value in [Double.infinity, -.infinity, .nan, .greatestFiniteMagnitude] {
            XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: value,
                                                           movingSeconds: 600, metric: true))
            XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 2_000,
                                                           movingSeconds: value, metric: true))
            XCTAssertTrue(ManualRunEntryRules.splits(distanceMeters: value, movingSeconds: 600, metric: true).isEmpty)
            XCTAssertEqual(RunFormat.durationText(seconds: value), "—")
            XCTAssertEqual(RunFormat.paceDiffText(secondsPerKmDiff: value, metric: false), "")
        }
        XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 500_001,
                                                       movingSeconds: 600, metric: true))
        XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 2_000,
                                                       movingSeconds: 172_801, metric: true))
        XCTAssertNotNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 500_000,
                                                          movingSeconds: 172_800, metric: false))
        XCTAssertEqual(RunFormat.durationText(seconds: 3_661), "1:01:01")
    }
}
