import XCTest
@testable import MyFitPlateCore

final class RunSaveReviewRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testExplicitReviewThresholdsAndEmptyBoundaries() {
        for seconds in [0, -1, 0.999, .infinity, .nan] {
            XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: seconds, distanceMeters: 100), .empty)
        }
        for meters in [-1, Double.infinity, .nan] {
            XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: 60, distanceMeters: meters), .empty)
        }
        XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: 1, distanceMeters: 0), .shortRecording)
        XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: 30, distanceMeters: 200), .shortRecording)
        XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: 120, distanceMeters: 0), .shortRecording)
        XCTAssertEqual(RunSaveReviewRules.requirement(activeSeconds: 60, distanceMeters: 50), .standard)
    }

    func testManualShortRunRequiresExplicitReviewAndRetainsExactValues() throws {
        XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 20, movingSeconds: 15, metric: true))
        let run = try XCTUnwrap(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 20,
            movingSeconds: 15, metric: true, confirmShortRecording: true))
        XCTAssertEqual(run.movingSeconds, 15)
        XCTAssertEqual(run.distanceMeters, 20)
        XCTAssertEqual(run.saveReview, .shortRecording)
        XCTAssertNil(run.averagePaceSecondsPerKm)
        XCTAssertTrue(run.splits.isEmpty)
        XCTAssertEqual(run.reidentified(as: "health-id").saveReview, .shortRecording)
        XCTAssertNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 0, movingSeconds: 0,
            metric: true, confirmShortRecording: true))
        XCTAssertNotNil(ManualRunEntryRules.buildIndoorRun(startDate: start, distanceMeters: 0, movingSeconds: 1,
            metric: true, confirmShortRecording: true))
    }

    func testReviewedShortRunSurvivesLocalCommitAliasAndCodableRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunFallbackStore(directory: directory)
        let run = Run(id: "short", source: .recorded, startDate: start, endDate: start.addingTimeInterval(15),
                      distanceMeters: 0, movingSeconds: 15, recordingID: "short", saveReview: .shortRecording)
        XCTAssertTrue(store.save(run, for: "owner"))
        XCTAssertTrue(store.save(run, for: "owner"))
        XCTAssertTrue(store.reidentify(id: run.id, as: "health-id", for: "owner"))
        let saved = try XCTUnwrap(store.runs(since: .distantPast, for: "owner").first)
        XCTAssertEqual(saved, run.reidentified(as: "health-id"))
        XCTAssertEqual(try JSONDecoder().decode(Run.self, from: JSONEncoder().encode(saved)), saved)
        XCTAssertTrue(store.runs(since: .distantPast, for: "other").isEmpty)
    }

    func testEmptyRunCannotEnterNewLocalOrHealthJobSavesButLegacyDecodeRemainsReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let run = Run(id: "empty-legacy", source: .recorded, startDate: start, endDate: start,
                      distanceMeters: 0, movingSeconds: 0)
        XCTAssertTrue(RunFallbackStore.isValid(run), "Compatibility reading is separate from accepting a new recording")
        XCTAssertEqual(try JSONDecoder().decode(Run.self, from: JSONEncoder().encode(run)), run)
        XCTAssertFalse(RunFallbackStore(directory: directory).save(run, for: "owner"))
        XCTAssertThrowsError(try RunHealthExportJobStore(directory: directory).prepare(run: run, weightLbs: 165,
            expectsRoute: false, userID: "owner"))
        var invalid = run; invalid.endDate = start.addingTimeInterval(10); invalid.movingSeconds = 11
        XCTAssertFalse(RunSaveReviewRules.canSave(invalid))
    }

    func testOwnReviewedShortImportSurvivesButForeignAndPrefixLookalikeMarkersDoNot() {
        func summary(bundle: String, id: String? = "original", marker: RunSaveReview? = .shortRecording) -> ImportedWorkoutSummary {
            .init(uuid: "health", activity: .running, startDate: start, endDate: start.addingTimeInterval(20),
                  distanceMeters: 0, sourceName: "Source", sourceBundleID: bundle, durationSeconds: 20,
                  recordingID: id, saveReview: marker)
        }
        for bundle in ["MyFitPlate.CalorieBeta", "MyFitPlate.CalorieBeta.watchkitapp"] {
            let own = summary(bundle: bundle)
            XCTAssertTrue(RunImportRules.isImportableRun(own))
            XCTAssertEqual(RunImportRules.run(from: own).saveReview, .shortRecording)
            XCTAssertEqual(RunImportRules.run(from: own).recordingID, "original")
        }
        for foreign in [summary(bundle: "third.party"), summary(bundle: "MyFitPlate.fake"),
                        summary(bundle: "MyFitPlate.CalorieBeta", id: " "),
                        summary(bundle: "MyFitPlate.CalorieBeta", marker: nil)] {
            XCTAssertFalse(RunImportRules.isImportableRun(foreign))
            XCTAssertNil(RunImportRules.run(from: foreign).saveReview)
        }
    }

    func testAutomaticImportUsesActiveTimeRatherThanLongPauseAndRejectsMalformedMetrics() {
        func summary(active: Double?, meters: Double? = 20, wall: Double = 600) -> ImportedWorkoutSummary {
            .init(uuid: "watch", activity: .running, startDate: start, endDate: start.addingTimeInterval(wall),
                  distanceMeters: meters, sourceName: "Watch", sourceBundleID: "watch.app", durationSeconds: active)
        }
        XCTAssertFalse(RunImportRules.isImportableRun(summary(active: 20)))
        XCTAssertTrue(RunImportRules.isImportableRun(summary(active: 120)))
        XCTAssertTrue(RunImportRules.isImportableRun(summary(active: 20, meters: 100)))
        XCTAssertTrue(RunImportRules.isImportableRun(summary(active: nil)), "Legacy absent duration retains elapsed fallback")
        for active in [0, -1, .infinity, .nan, 601] {
            XCTAssertFalse(RunImportRules.isImportableRun(summary(active: active, meters: 100)))
        }
        for meters in [-1, Double.infinity, .nan] {
            XCTAssertFalse(RunImportRules.isImportableRun(summary(active: 120, meters: meters)))
        }
    }

    func testPendingReviewedFinishRecoversExactlyAndCannotBeReopenedOrChangedByCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunRecordingDraftStore(directory: directory)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed, id: "reviewed")
        session.start(at: start)
        let end = start.addingTimeInterval(20)
        session.pause(at: end)
        let snapshot = try XCTUnwrap(session.snapshot(at: end))
        var run = try XCTUnwrap(session.finish(at: end)); run.saveReview = .shortRecording
        let pending = RunRecordingCompletion(run: run, weightLbs: 165)
        let draft = RunRecordingDraft(session: snapshot, updatedAt: end, pendingCompletion: pending)
        try store.save(draft, userID: "owner")
        XCTAssertEqual(try RunRecordingDraftStore(directory: directory).load(userID: "owner")?.pendingCompletion, pending)
        XCTAssertThrowsError(try store.save(RunRecordingDraft(session: snapshot, updatedAt: end.addingTimeInterval(100)), userID: "owner"))
        var changed = run; changed.endDate = end.addingTimeInterval(100)
        XCTAssertThrowsError(try store.save(RunRecordingDraft(session: snapshot, updatedAt: end.addingTimeInterval(100),
            pendingCompletion: RunRecordingCompletion(run: changed, weightLbs: 165)), userID: "owner"))
        XCTAssertEqual(try store.load(userID: "owner"), draft)
    }

    func testLegacyGPSBasedTimingCanFreezeItsActualMovingTimeWithoutLosingActiveClock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in [RunSession.TimeAccounting.moving, .elapsed] {
            let session = RunSession(metric: true, timeAccounting: mode)
            session.start(at: start)
            XCTAssertTrue(session.ingest(.init(latitude: 40, longitude: -74, horizontalAccuracy: 5, timestamp: start)))
            XCTAssertTrue(session.ingest(.init(latitude: 40.0006, longitude: -74, horizontalAccuracy: 5, timestamp: start.addingTimeInterval(10))))
            let end = start.addingTimeInterval(100)
            let snapshot = try XCTUnwrap(session.snapshot(at: end))
            XCTAssertEqual(snapshot.movingSeconds, 10)
            XCTAssertEqual(snapshot.activeElapsedSeconds, 100)
            var run = try XCTUnwrap(session.finish(at: end)); run.saveReview = .shortRecording
            let pending = RunRecordingCompletion(run: run, weightLbs: 165)
            let store = RunRecordingDraftStore(directory: directory)
            let draft = RunRecordingDraft(session: snapshot, updatedAt: end, pendingCompletion: pending)
            try store.save(draft, userID: mode.rawValue)
            XCTAssertEqual(try RunRecordingDraftStore(directory: directory).load(userID: mode.rawValue), draft)
        }
    }

    func testZeroDistanceReviewedRunIsNotHiddenByOverlappingIndependentRecordingButExactAliasesMerge() {
        let reviewed = Run(id: "short-local", source: .recorded, startDate: start, endDate: start.addingTimeInterval(600),
            distanceMeters: 0, movingSeconds: 20, recordingID: "short-local", saveReview: .shortRecording)
        let watch = Run(id: "watch-independent", source: .imported(appName: "Watch"),
            startDate: start, endDate: start.addingTimeInterval(600), distanceMeters: 0, movingSeconds: 600,
            activeCalories: 100, averageHeartRate: 150)
        var manual = reviewed.reidentified(as: "manual-independent")
        manual.recordingID = manual.id; manual.isIndoor = true
        manual.movingSeconds = 30
        let independent = RunLocalHistoryRules.merging(healthRuns: [watch], localRuns: [reviewed, manual])
        XCTAssertEqual(Set(independent.map(\.id)), [reviewed.id, manual.id, watch.id])
        var healthAlias = reviewed.reidentified(as: "own-health-id")
        healthAlias.saveReview = nil
        let merged = RunLocalHistoryRules.merging(healthRuns: [watch, healthAlias], localRuns: [reviewed, manual])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.first(where: { $0.id == "own-health-id" })?.movingSeconds, 20)
        XCTAssertEqual(merged.first(where: { $0.id == "own-health-id" })?.saveReview, .shortRecording)
        XCTAssertFalse(merged.contains(where: { $0.id == "short-local" }))
    }

    func testFirstSuccessfulLocalSaveUnderHealthIDRecognizesOriginalRecordingAndRejectsStaleAppend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Run(id: "original", source: .recorded, startDate: start, endDate: start.addingTimeInterval(20),
            distanceMeters: 0, movingSeconds: 20, recordingID: "original", saveReview: .shortRecording)
        let store = RunFallbackStore(directory: directory)
        XCTAssertTrue(store.save(original.reidentified(as: "health-id"), for: "owner"))
        XCTAssertTrue(store.containsRecording(id: original.id, for: "owner"))
        XCTAssertTrue(store.containsRecording(id: "health-id", for: "owner"))
        XCTAssertTrue(store.save(original, for: "owner"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "owner").map(\.id), ["health-id"])
        XCTAssertTrue(store.reidentify(id: original.id, as: "health-id", for: "owner"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "owner").count, 1)
        XCTAssertTrue(store.reidentify(id: "health-id", as: "health-id-2", for: "owner"))
        XCTAssertFalse(store.save(original.reidentified(as: "conflicting-health-id"), for: "owner"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "owner").map(\.id), ["health-id-2"])
        XCTAssertTrue(store.containsRecording(id: "health-id", for: "owner"))
        XCTAssertTrue(store.containsRecording(id: original.id, for: "owner"))
    }
}
