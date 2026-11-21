import XCTest
@testable import MyFitPlateCore

final class RunRecordingDraftTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!
    private var store: RunRecordingDraftStore!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RunRecordingDraftStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
    }

    private func session(_ id: String = "active-recording") -> RunSession {
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: id)
        session.start(at: start)
        session.ingest(RunLocationFix(latitude: 40, longitude: -74, horizontalAccuracy: 5, timestamp: start))
        session.ingest(RunLocationFix(latitude: 40.0001, longitude: -74, horizontalAccuracy: 5,
                                     timestamp: start.addingTimeInterval(10)))
        return session
    }

    private func draft(_ session: RunSession, at seconds: Double = 30) throws -> RunRecordingDraft {
        let now = start.addingTimeInterval(seconds)
        return RunRecordingDraft(session: try XCTUnwrap(session.snapshot(at: now)), updatedAt: now)
    }

    func testAtomicDraftIsAccountScopedAndRestoresPausedWithoutCoordinates() throws {
        let original = try draft(session())
        try store.save(original, userID: "owner")
        let restored = try XCTUnwrap(RunRecordingDraftStore(directory: directory).load(userID: "owner"))
        XCTAssertEqual(restored, original)
        XCTAssertNil(try store.load(userID: "other"))
        let recovered = try XCTUnwrap(RunSession(snapshot: restored.session, at: start.addingTimeInterval(600)))
        XCTAssertEqual(recovered.state, .paused)
        XCTAssertEqual(recovered.distanceMeters, original.session.distanceMeters)
        XCTAssertEqual(recovered.activeElapsedSeconds(at: start.addingTimeInterval(600)), 30)
        XCTAssertEqual(recovered.routePointCount, 0)
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(restored), encoding: .utf8))
        XCTAssertFalse(text.contains("latitude"))
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertFalse(text.contains("horizontalAccuracy"))
    }

    func testStaleCheckpointAndDifferentSessionCannotReplaceCurrentRecording() throws {
        let runSession = session()
        let original = try draft(runSession)
        try store.save(original, userID: "owner")
        let later = try draft(runSession, at: 60)
        try store.save(later, userID: "owner")
        XCTAssertThrowsError(try store.save(original, userID: "owner"))
        XCTAssertThrowsError(try store.save(draft(self.session("new-run")), userID: "owner"))
        XCTAssertEqual(try store.load(userID: "owner"), later)
    }

    func testLateCompletionCannotRemoveNewRecording() throws {
        try store.save(draft(session("old")), userID: "owner")
        try store.remove(userID: "owner", sessionID: "old")
        let next = try draft(session("next"))
        try store.save(next, userID: "owner")
        XCTAssertThrowsError(try store.remove(userID: "owner", sessionID: "old"))
        XCTAssertEqual(try store.load(userID: "owner"), next)
    }

    func testUnreadableAndFutureDraftsStayIntactUntilExplicitDiscard() throws {
        let original = try draft(session())
        try store.save(original, userID: "owner")
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: url)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try store.load(userID: "owner"))
        XCTAssertThrowsError(try store.save(original, userID: "owner"))
        XCTAssertEqual(try Data(contentsOf: url), Data("corrupt".utf8))
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        future["version"] = 99
        let futureBytes = try JSONSerialization.data(withJSONObject: future)
        try futureBytes.write(to: url)
        XCTAssertThrowsError(try store.save(original, userID: "owner"))
        XCTAssertEqual(try Data(contentsOf: url), futureBytes)
        try store.remove(userID: "owner")
        XCTAssertNil(try store.load(userID: "owner"))
    }

    func testWorkoutBoundariesRestoreExactlyAndCannotExceedSessionTotals() throws {
        let runSession = session()
        let tracker = RunWorkoutTracker(plan: RunWorkoutPlan.builtinTemplates(metric: true)[0])
        _ = tracker.advance(elapsedSeconds: 20, distanceMeters: 5)
        let valid = RunRecordingDraft(session: try XCTUnwrap(runSession.snapshot(at: start.addingTimeInterval(30))),
                                      workout: tracker.snapshot(), updatedAt: start.addingTimeInterval(30))
        try store.save(valid, userID: "owner")
        XCTAssertEqual(try store.load(userID: "owner")?.workout, tracker.snapshot())
        _ = tracker.advance(elapsedSeconds: 100, distanceMeters: 100)
        let inconsistent = RunRecordingDraft(session: valid.session, workout: tracker.snapshot(), updatedAt: valid.updatedAt)
        XCTAssertThrowsError(try store.save(inconsistent, userID: "owner"))
        XCTAssertEqual(try store.load(userID: "owner"), valid)
    }

    func testUnavailableOrUnownedStorageFailsWithoutFallbackToAnotherAccount() throws {
        let draft = try draft(session())
        XCTAssertThrowsError(try RunRecordingDraftStore(directory: nil).save(draft, userID: "owner"))
        XCTAssertThrowsError(try store.save(draft, userID: "  "))
        XCTAssertThrowsError(try store.load(userID: ""))
    }
}
