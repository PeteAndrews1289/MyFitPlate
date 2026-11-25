import XCTest
@testable import MyFitPlateCore

final class RunManualLapTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testLapIsIdempotentDoesNotPauseOrChangeAutomaticSplitsAndRejectsStalePreviousBoundary() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "recording")
        session.start(at: start)
        let first = try XCTUnwrap(session.proposedManualLap(operationID: "lap-1", expectedPreviousID: nil, at: start.addingTimeInterval(30)))
        XCTAssertTrue(session.acceptManualLap(first, expectedPreviousID: nil))
        XCTAssertTrue(session.acceptManualLap(first, expectedPreviousID: nil))
        XCTAssertEqual(session.manualLaps.count, 1)
        XCTAssertEqual(session.state, .running)
        XCTAssertTrue(session.completedSplits.isEmpty)
        XCTAssertNil(session.proposedManualLap(operationID: "late-tap", expectedPreviousID: nil, at: start.addingTimeInterval(40)))
        session.pause(at: start.addingTimeInterval(50))
        XCTAssertNil(session.proposedManualLap(operationID: "paused", expectedPreviousID: first.id, at: start.addingTimeInterval(60)))
    }

    func testLapSurvivesDurableRecoveryExcludesAwayTimeAndKeepsSameHealthAliasReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "recording")
        session.start(at: start)
        let first = try XCTUnwrap(session.proposedManualLap(operationID: "one", expectedPreviousID: nil, at: start.addingTimeInterval(30)))
        XCTAssertTrue(session.acceptManualLap(first, expectedPreviousID: nil))
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(40)))
        try store.save(RunRecordingDraft(session: snapshot, updatedAt: snapshot.recordedAt), userID: "owner")
        let restored = try XCTUnwrap(RunSession(snapshot: XCTUnwrap(store.load(userID: "owner")).session, at: start.addingTimeInterval(400)))
        XCTAssertEqual(restored.manualLaps, [first]); XCTAssertEqual(restored.state, .paused)
        restored.resume(at: start.addingTimeInterval(500))
        let second = try XCTUnwrap(restored.proposedManualLap(operationID: "two", expectedPreviousID: first.id, at: start.addingTimeInterval(520)))
        XCTAssertEqual(second.activeElapsedSeconds, 60)
        XCTAssertTrue(restored.acceptManualLap(second, expectedPreviousID: first.id))
        let run = try XCTUnwrap(restored.finish(at: start.addingTimeInterval(530)))
        XCTAssertEqual(run.manualLaps, [first, second]); XCTAssertEqual(run.movingSeconds, 70)
        let alias = run.reidentified(as: "health-uuid")
        XCTAssertEqual(alias.manualLaps, run.manualLaps)
        XCTAssertEqual(RunLocalHistoryRules.merging(healthRuns: [alias], localRuns: [run]).first?.manualLaps, run.manualLaps)
        let csv = RunSummaryExport.csv(run: alias)
        XCTAssertTrue(csv.contains("Manual lap 2 active time\",\"30.0"))
        XCTAssertFalse(csv.contains("health-uuid")); XCTAssertFalse(csv.contains("recording"))
    }

    func testLegacySnapshotAndRunDecodeWithoutLapsAndCorruptLapCannotRecover() throws {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        let snapshot = try XCTUnwrap(session.snapshot(at: start.addingTimeInterval(20)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "manualLaps")
        let legacy = try JSONDecoder().decode(RunSession.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNotNil(RunSession(snapshot: legacy, at: start.addingTimeInterval(25)))
        var corrupt = snapshot
        corrupt.manualLaps = [RunManualLap(id: "bad", recordingID: snapshot.id, index: 1, timestamp: start.addingTimeInterval(10), activeElapsedSeconds: 30, distanceMeters: 0)]
        XCTAssertNil(RunSession(snapshot: corrupt, at: start.addingTimeInterval(25)))
        let run = try XCTUnwrap(session.finish(at: start.addingTimeInterval(30)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        object.removeValue(forKey: "manualLaps")
        XCTAssertNil(try JSONDecoder().decode(Run.self, from: JSONSerialization.data(withJSONObject: object)).manualLaps)
    }
}
