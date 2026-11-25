import XCTest
@testable import MyFitPlateCore

final class RunCompletionPreservationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSensorsRejectStaleFutureDuplicateAndPreviousResumeReadings() throws {
        var value = RunSensorCheckpoint(recordingID: "run")
        let sample = RunHeartRateSample(date: start.addingTimeInterval(5), bpm: 140, sourceID: "watch", sourceName: "Watch")
        XCTAssertFalse(value.append(sample, after: start.addingTimeInterval(6), now: start.addingTimeInterval(10)))
        XCTAssertFalse(value.append(sample, after: start, now: start.addingTimeInterval(4)))
        XCTAssertTrue(value.append(sample, after: start, now: start.addingTimeInterval(10)))
        XCTAssertFalse(value.append(sample, after: start, now: start.addingTimeInterval(10)))
        XCTAssertEqual(value.latestHeartRate(at: start.addingTimeInterval(20), after: start), sample)
        XCTAssertNil(value.latestHeartRate(at: start.addingTimeInterval(36), after: start))
        XCTAssertNil(value.latestHeartRate(at: start.addingTimeInterval(20), after: start.addingTimeInterval(6)))
        XCTAssertFalse(value.append(RunHeartRateSample(date: start.addingTimeInterval(10), bpm: .nan, sourceID: "watch", sourceName: "Watch"), after: start, now: start.addingTimeInterval(10)))
        XCTAssertTrue(value.append(RunCadenceSample(date: start.addingTimeInterval(10), stepsPerMinute: 170), after: start, now: start.addingTimeInterval(10)))
        XCTAssertNil(value.latestCadence(at: start.addingTimeInterval(21), after: start))
        XCTAssertFalse(value.isValid(recordingID: "other", startDate: start, endDate: start.addingTimeInterval(30)))
    }

    func testSensorCheckpointRestoresWithMatchingSessionAndIsNotLiveAfterRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "run")
        session.start(at: start)
        let now = start.addingTimeInterval(20)
        let sensors = RunSensorCheckpoint(recordingID: "run", heartRate: [.init(date: start.addingTimeInterval(10), bpm: 140, sourceID: "watch", sourceName: "Watch")], cadence: [.init(date: start.addingTimeInterval(10), stepsPerMinute: 170)])
        let draft = RunRecordingDraft(session: try XCTUnwrap(session.snapshot(at: now)), updatedAt: now, sensors: sensors)
        try store.save(draft, userID: "a")
        let restored = try XCTUnwrap(RunRecordingDraftStore(directory: directory).load(userID: "a"))
        XCTAssertEqual(restored.sensors, sensors)
        XCTAssertNil(restored.sensors?.latestHeartRate(at: start.addingTimeInterval(200), after: start.addingTimeInterval(200)))
        XCTAssertNil(try store.load(userID: "b"))
        let dropped = RunRecordingDraft(session: draft.session, updatedAt: now)
        XCTAssertThrowsError(try store.save(dropped, userID: "a"))
        let mismatched = RunRecordingDraft(session: draft.session, updatedAt: now, sensors: .init(recordingID: "another"))
        XCTAssertThrowsError(try store.save(mismatched, userID: "a"))
        XCTAssertEqual(try store.load(userID: "a"), restored)
    }

    func testCompletedSensorEvidenceSurvivesHealthIdentityAndFallbackRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sensors = RunSensorCheckpoint(recordingID: "run", heartRate: [.init(date: start.addingTimeInterval(10), bpm: 140, sourceID: "watch", sourceName: "Watch")])
        let run = Run(id: "run", source: .recorded, startDate: start, endDate: start.addingTimeInterval(30), distanceMeters: 100, movingSeconds: 30, recordingID: "run", sensors: sensors)
        let store = RunFallbackStore(directory: directory)
        XCTAssertTrue(store.save(run, for: "a"))
        XCTAssertTrue(store.reidentify(id: "run", as: "health", for: "a"))
        let saved = try XCTUnwrap(RunFallbackStore(directory: directory).runs(since: start, for: "a").first)
        XCTAssertEqual(saved.sensors, sensors)
        XCTAssertEqual(saved.recordingID, "run")
        XCTAssertEqual(saved.id, "health")
    }

    func testFavoritesKeepExactPlanAndArchiveAndFenceAccount() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = MockAuthService(); auth.currentUserID = "a"
        let store = RunWorkoutPlanStore(userDefaults: defaults, authService: auth)
        let plan = RunWorkoutPlan(id: "exact", name: "Exact seconds", subtitle: "", steps: [.init(id: "work", kind: .hard, title: "Work", goal: .duration(seconds: 75))])
        try store.setFavorite(plan, favorite: true, userID: "a")
        try store.setFavorite(plan, favorite: true, userID: "a")
        XCTAssertEqual(store.customPlans, [plan])
        XCTAssertEqual(RunWorkoutPlanStore(userDefaults: defaults, authService: auth).favoritePlans, [plan])
        var changed = plan; changed.name = "Changed"
        XCTAssertThrowsError(try store.setFavorite(changed, favorite: true, userID: "a"))
        auth.currentUserID = "b"
        XCTAssertTrue(store.favoritePlans.isEmpty)
        XCTAssertThrowsError(try store.setFavorite(plan, favorite: false, userID: "a"))
        auth.currentUserID = "a"
        store.deletePlan(id: plan.id)
        XCTAssertTrue(store.favoritePlans.isEmpty)
        XCTAssertEqual(store.revisions(forPlanID: plan.id).first?.plan, plan)
    }

    func testResultRetainsFullOriginalPlanWhenRunStopsEarlyAndLegacyDecodes() throws {
        let plan = RunWorkoutPlan.tempoStarterForCompletionTest()
        let tracker = RunWorkoutTracker(plan: plan)
        let result = try XCTUnwrap(tracker.result(runID: "r", completedAt: start, elapsedSeconds: 15, distanceMeters: 10))
        XCTAssertEqual(result.planSnapshot, plan)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        json.removeValue(forKey: "planSnapshot")
        let legacy = try JSONDecoder().decode(RunWorkoutResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.planSnapshot)
        XCTAssertEqual(legacy.steps, result.steps)
    }

    func testPermanentImportedExclusionHasNoUndoOrReimportButOtherAccountIsUnaffected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunReviewStore(drafts: EditorDraftStore(directory: directory))
        let run = Run(id: "external", source: .imported(appName: "Watch"), startDate: start, endDate: start.addingTimeInterval(60), distanceMeters: 100, movingSeconds: 60)
        let note = try store.commit(store.review(run: run, mutation: .annotate(note: "Wet track"), userID: "a"), currentUserID: "a")
        XCTAssertEqual(try store.projecting([run], userID: "a").first?.reviewAnnotation?.note, "Wet track")
        XCTAssertEqual(try store.originalEvidence(for: run, userID: "a"), run)
        let deletion = try store.commit(store.review(run: run, mutation: .excludeImportPermanently, userID: "a"), currentUserID: "a")
        let restarted = RunReviewStore(drafts: EditorDraftStore(directory: directory))
        XCTAssertTrue(try restarted.projecting([run], userID: "a", includeHidden: true).isEmpty)
        XCTAssertThrowsError(try restarted.undo(deletion, currentUserID: "a"))
        XCTAssertThrowsError(try restarted.undo(note, currentUserID: "a"))
        XCTAssertThrowsError(try restarted.review(run: run, mutation: .restoreOriginal, userID: "a"))
        XCTAssertEqual(try restarted.projecting([run], userID: "b"), [run])
        XCTAssertEqual(try restarted.commit(deletion.review, currentUserID: "a"), deletion)
    }

    func testPauseCorrectionCannotCommitWithoutConfirmedDiaryAndKeepsRawEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunReviewStore(drafts: EditorDraftStore(directory: directory))
        let run = Run(id: "r", source: .recorded, startDate: start, endDate: start.addingTimeInterval(100), distanceMeters: 500, movingSeconds: 100, pauseTimeline: .init(completeness: .complete, intervals: []))
        let timeline = RunPauseTimeline(completeness: .complete, intervals: [.init(startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(30), origin: .explicitPause)])
        let review = try store.review(run: run, mutation: .correctPauses(timeline: timeline, reason: "Missed pause"), userID: "a")
        XCTAssertThrowsError(try store.commit(review, currentUserID: "a"))
        XCTAssertThrowsError(try store.commit(review, currentUserID: "a", diaryAccepted: true))
        XCTAssertEqual(try store.projecting([run], userID: "a"), [run])
    }
}
private extension RunWorkoutPlan {
    static func tempoStarterForCompletionTest() -> RunWorkoutPlan { builtinTemplates(metric: true)[2] }
}
