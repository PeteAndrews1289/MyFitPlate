import XCTest
@testable import MyFitPlateCore

final class RunRouteRecoveryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!

    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func fix(_ seconds: Double, latitude: Double = 40) -> RunLocationFix {
        RunLocationFix(latitude: latitude, longitude: -74, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(seconds))
    }

    private func accept(_ fix: RunLocationFix, session: RunSession, route: inout RunRouteRecording) {
        if session.ingest(fix) { route.append(fix, startsNewSegment: session.lastIngestStartedSegment) }
    }

    func testAtomicRecoveryKeepsEarlierRouteButNeverReplaysDistanceAcrossInterruption() throws {
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run")
        var route = RunRouteRecording(recordingID: session.id)
        session.start(at: start)
        accept(fix(0), session: session, route: &route)
        accept(fix(10, latitude: 40.0002), session: session, route: &route)
        let checkpoint = start.addingTimeInterval(12)
        try store.save(RunRecordingDraft(session: XCTUnwrap(session.snapshot(at: checkpoint)), updatedAt: checkpoint, route: route), userID: "owner")
        let loaded = try XCTUnwrap(store.load(userID: "owner"))
        let restored = try XCTUnwrap(RunSession(snapshot: loaded.session, at: start.addingTimeInterval(300)))
        var recoveredRoute = try XCTUnwrap(loaded.route)
        XCTAssertEqual(recoveredRoute.segments, route.segments)
        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.distanceMeters, session.distanceMeters)
        restored.resume(at: start.addingTimeInterval(300))
        accept(fix(300, latitude: 41), session: restored, route: &recoveredRoute)
        XCTAssertEqual(restored.distanceMeters, session.distanceMeters, "A distant first fix anchors a new segment; it is never a connecting leg")
        accept(fix(310, latitude: 41.0002), session: restored, route: &recoveredRoute)
        XCTAssertEqual(recoveredRoute.segments.map(\.count), [2, 2])
        XCTAssertEqual(recoveredRoute.acceptedSequence, 4)
        XCTAssertLessThan(restored.distanceMeters, 50)
        XCTAssertEqual(restored.activeElapsedSeconds(at: start.addingTimeInterval(310)), 22)
        let final = try XCTUnwrap(restored.finish(at: start.addingTimeInterval(310)))
        XCTAssertEqual(final.pauseTimeline?.summary(startDate: start, endDate: final.endDate, activeSeconds: final.movingSeconds)?.recoveryGapSeconds, 288)
    }

    func testPausedRecoveryAndRejectedTeleportKeepSeparateSegments() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run")
        var route = RunRouteRecording(recordingID: session.id)
        session.start(at: start)
        accept(fix(0), session: session, route: &route)
        accept(fix(1, latitude: 40.00001), session: session, route: &route)
        accept(fix(2, latitude: 45), session: session, route: &route)
        accept(fix(3, latitude: 40.00002), session: session, route: &route)
        accept(fix(4, latitude: 40.00003), session: session, route: &route)
        session.pause(at: start.addingTimeInterval(5))
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(20)))
        let restored = try XCTUnwrap(RunSession(snapshot: snapshot, at: start.addingTimeInterval(100)))
        restored.resume(at: start.addingTimeInterval(110))
        accept(fix(110, latitude: 40.001), session: restored, route: &route)
        accept(fix(111, latitude: 40.00101), session: restored, route: &route)
        XCTAssertEqual(route.segments.map(\.count), [2, 2, 2])
        XCTAssertEqual(route.acceptedSequence, 6)
        XCTAssertFalse(route.segments.flatMap { $0 }.contains { $0.latitude == 45 })
        let run = try XCTUnwrap(restored.finish(at: start.addingTimeInterval(112)))
        XCTAssertEqual(run.movingSeconds, 7)
        XCTAssertEqual(run.pauseTimeline?.intervals.first?.origin, .explicitPause)
    }

    func testTruncatedOrTamperedNewCheckpointSalvagesMatchingPreviousTotalsAndRoute() throws {
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run")
        var route = RunRouteRecording(recordingID: session.id)
        session.start(at: start)
        accept(fix(0), session: session, route: &route)
        accept(fix(5, latitude: 40.0001), session: session, route: &route)
        let first = RunRecordingDraft(session: try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(5))), updatedAt: start.addingTimeInterval(5), route: route)
        try store.save(first, userID: "owner")
        accept(fix(10, latitude: 40.0002), session: session, route: &route)
        let next = RunRecordingDraft(session: try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(10))), updatedAt: start.addingTimeInterval(10), route: route)
        try store.save(next, userID: "owner")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
        let valid = try Data(contentsOf: file)
        try valid.prefix(valid.count / 2).write(to: file)
        let salvaged = try XCTUnwrap(store.load(userID: "owner"))
        XCTAssertTrue(salvaged.recoveredPreviousCheckpoint)
        XCTAssertEqual(salvaged.session, first.session)
        XCTAssertEqual(salvaged.route, first.route)
        XCTAssertNil(try store.load(userID: "different-owner"))
        try valid.write(to: file)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        json["checksum"] = "tampered"
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertEqual(try store.load(userID: "owner")?.session, first.session)
        try store.remove(userID: "owner", sessionID: "run")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testLegacyDraftStaysReadableAndFutureVersionCannotBeRolledBack() throws {
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run")
        session.start(at: start)
        let snapshot = try XCTUnwrap(session.snapshot(at: start))
        try store.save(RunRecordingDraft(session: snapshot, updatedAt: start), userID: "owner")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["version"] = 1
        json.removeValue(forKey: "checksum")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertNil(try store.load(userID: "owner")?.route)
        try store.save(RunRecordingDraft(session: snapshot, updatedAt: start), userID: "owner")
        json["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: json)
        try future.write(to: file)
        XCTAssertThrowsError(try store.load(userID: "owner"))
        XCTAssertThrowsError(try store.save(RunRecordingDraft(session: snapshot, updatedAt: start), userID: "owner"))
        XCTAssertEqual(try Data(contentsOf: file), future)
    }

    func testRouteCacheIsAccountScopedProtectedBoundedAndExplicitlyRemovable() throws {
        let cache = RunRouteArchiveStore(directory: directory, now: { self.start.addingTimeInterval(40) })
        for index in 0..<22 {
            var route = RunRouteRecording(recordingID: "run-\(index)")
            route.append(fix(Double(index)), startsNewSegment: true)
            route.append(fix(Double(index + 1), latitude: 40.00001), startsNewSegment: false)
            let run = Run(id: route.recordingID, source: .recorded, startDate: start,
                          endDate: start.addingTimeInterval(Double(index + 2)), distanceMeters: 1, movingSeconds: 1)
            try cache.save(route, run: run, userID: "owner")
        }
        XCTAssertNil(try cache.load(recordingID: "run-0", userID: "owner"))
        XCTAssertNotNil(try cache.load(recordingID: "run-21", userID: "owner"))
        XCTAssertNil(try cache.load(recordingID: "run-21", userID: "another-owner"))
        let account = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: account, includingPropertiesForKeys: nil).count, 20)
        XCTAssertEqual(try account.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let expired = RunRouteArchiveStore(directory: directory, now: { self.start.addingTimeInterval(RunRouteArchiveStore.retentionSeconds + 100) })
        XCTAssertNil(try expired.load(recordingID: "run-21", userID: "owner"))
        try cache.removeAccountData(userID: "owner")
        XCTAssertFalse(FileManager.default.fileExists(atPath: account.path))
    }

    func testStorageBoundStopsCaptureWithoutConnectingOmittedCoordinates() throws {
        var route = RunRouteRecording(recordingID: "bounded")
        for index in 0...RunRouteRecording.maximumPoints {
            route.append(fix(Double(index)), startsNewSegment: false)
        }
        XCTAssertEqual(route.pointCount, RunRouteRecording.maximumPoints)
        XCTAssertTrue(route.isTruncated)
        route.append(fix(50_000), startsNewSegment: true)
        XCTAssertEqual(route.segments.count, 1)
        XCTAssertTrue(route.isValid(startDate: start, endDate: start.addingTimeInterval(50_000)))
    }
}
