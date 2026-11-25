import CoreLocation
import MyFitPlateCore
import XCTest
@testable import MyFitPlate

final class RunRecorderSavingTests: XCTestCase {
    @MainActor
    func testLocationGrantMakesTheOpenRecorderReadyWithoutStartingARun() throws {
        try withIsolatedRecorder { _, _, saver, backup, _ in
            let recorder = RunRecorderViewModel(metric: true, store: saver,
                                                completedRunStore: backup, persistsRecovery: false)
            defer { recorder.closePreparation() }
            recorder.locationService.updateAuthorization(.notDetermined)
            recorder.prepare()
            XCTAssertEqual(recorder.stage, .permission)

            let recordingID = recorder.session.id
            recorder.locationService.updateAuthorization(.authorizedWhenInUse)
            XCTAssertEqual(recorder.stage, .ready)
            XCTAssertEqual(recorder.session.id, recordingID)
            XCTAssertNil(recorder.session.startDate)

            recorder.locationService.updateAuthorization(.denied)
            XCTAssertEqual(recorder.stage, .permission)
        }
    }

    @MainActor
    func testRestoredLegacyMovingAndElapsedDraftsFinishAndRetryTheirActualMeasuredTime() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            for mode in [RunSession.TimeAccounting.moving, .elapsed] {
                let draftStore = RunRecordingDraftStore(directory: directory.appendingPathComponent(mode.rawValue))
                let source = RunSession(metric: true, timeAccounting: mode)
                source.start(at: clock.date)
                XCTAssertTrue(source.ingest(.init(latitude: 40, longitude: -74, horizontalAccuracy: 5, timestamp: clock.date)))
                XCTAssertTrue(source.ingest(.init(latitude: 40.0006, longitude: -74, horizontalAccuracy: 5, timestamp: clock.date.addingTimeInterval(10))))
                clock.date.addTimeInterval(100)
                try draftStore.save(RunRecordingDraft(session: XCTUnwrap(source.snapshot(at: clock.date)), updatedAt: clock.date), userID: ownerID)
                let recorder = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                    store: saver, completedRunStore: RunFallbackStore(directory: nil), draftStore: draftStore, persistsRecovery: true)
                recorder.audioCoachEnabled = false
                defer { recorder.discard() }
                recorder.prepare()
                XCTAssertEqual(recorder.saveReviewActiveSeconds, 10)
                XCTAssertEqual(recorder.saveReviewRequirement, .shortRecording)
                recorder.finish(weightLbs: 165)
                XCTAssertEqual(recorder.stage, .paused)
                recorder.finish(weightLbs: 165, confirmShortRecording: true)
                let original = try XCTUnwrap(saver.runs.last)
                XCTAssertEqual(original.movingSeconds, 10)
                XCTAssertEqual(original.saveReview, .shortRecording)
                saver.completeNext(with: .failed)
                XCTAssertEqual(try draftStore.load(userID: ownerID)?.pendingCompletion?.run, original)
                clock.date.addTimeInterval(600)
                let restored = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                    store: saver, completedRunStore: backup, draftStore: draftStore, persistsRecovery: true)
                restored.audioCoachEnabled = false
                defer { restored.discard() }
                restored.prepare()
                XCTAssertEqual(restored.stage, .summary(original))
                restored.retrySave(weightLbs: 220)
                XCTAssertEqual(saver.runs.last, original)
                XCTAssertEqual(saver.weights.last, 165)
                saver.completeNext(with: .saved("legacy-\(mode.rawValue)-health"))
                XCTAssertNil(try draftStore.load(userID: ownerID))
            }
        }
    }

    @MainActor
    func testHealthSuccessWithFailedLocalStorageKeepsFullPendingRunAndRecoversWithoutAnotherHealthWrite() throws {
        try exerciseHealthSuccessWithUnavailableLocalStorage(.saved("retained-health"))
    }

    @MainActor
    func testUnreadableHealthSuccessWithFailedLocalStorageKeepsFullPendingRunAndReconcilesAfterRelaunch() throws {
        try exerciseHealthSuccessWithUnavailableLocalStorage(.savedAwaitingReadAccess)
    }

    @MainActor
    func testInitialLocalFailureThenHealthAliasLocalSuccessClearsOnlyAcceptedDraftAndDoesNotResurrect() throws {
        try withIsolatedRecorder { _, clock, saver, _, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let blocked = directory.appendingPathComponent("history")
            try Data("temporarily blocked directory".utf8).write(to: blocked)
            let fallback = RunFallbackStore(directory: blocked)
            let drafts = RunRecordingDraftStore(directory: directory.appendingPathComponent("drafts"))
            let first = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: fallback, draftStore: drafts, persistsRecovery: true)
            first.audioCoachEnabled = false
            defer { first.discard() }
            first.begin(); clock.date.addTimeInterval(20); first.pause()
            first.finish(weightLbs: 165, confirmShortRecording: true)
            let run = try XCTUnwrap(saver.runs.first)
            XCTAssertFalse(fallback.containsRecording(id: run.id, for: ownerID))
            try FileManager.default.removeItem(at: blocked)
            saver.completeNext(with: .saved("first-local-health-id"))
            XCTAssertEqual(first.saveState, .appleHealth)
            XCTAssertTrue(fallback.containsRecording(id: run.id, for: ownerID))
            XCTAssertNil(try drafts.load(userID: ownerID))
            let restored = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: fallback, draftStore: drafts, persistsRecovery: true)
            restored.audioCoachEnabled = false
            defer { restored.discard() }
            restored.prepare()
            XCTAssertEqual(restored.stage, .ready)
            XCTAssertEqual(fallback.runs(since: .distantPast, for: ownerID).map(\.id), ["first-local-health-id"])
            XCTAssertEqual(saver.runs.count, 1)
        }
    }

    @MainActor
    private func exerciseHealthSuccessWithUnavailableLocalStorage(_ outcome: RunHealthSaveOutcome) throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drafts = RunRecordingDraftStore(directory: directory.appendingPathComponent("drafts"))
            let jobs = RunHealthExportJobStore(directory: directory.appendingPathComponent("jobs"))
            let routes = RunRouteArchiveStore(directory: directory.appendingPathComponent("routes"))
            let unavailable = RunFallbackStore(directory: nil)
            let first = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: unavailable, draftStore: drafts, routeStore: routes,
                persistsRecovery: true, exportJobs: jobs)
            first.audioCoachEnabled = false
            defer { first.discard() }
            first.begin(); clock.date.addTimeInterval(10)
            first.ingestHeartRate(.init(date: clock.date, bpm: 142, sourceID: "test.watch", sourceName: "Test Watch"))
            first.markLap(expectedPreviousID: nil)
            clock.date.addTimeInterval(10); first.pause()
            first.finish(weightLbs: 165, confirmShortRecording: true)
            let original = try XCTUnwrap(saver.runs.first)
            XCTAssertEqual(original.manualLaps?.count, 1)
            XCTAssertEqual(original.sensors?.heartRate.count, 1)
            saver.completeNext(with: outcome)
            XCTAssertEqual(first.saveState, .localRecoveryPending)
            XCTAssertEqual(first.saveState.localStatus, "Recording retained · save needed")
            XCTAssertEqual(first.displayedHealthStatus, outcome == .savedAwaitingReadAccess ? "Saved · awaiting read access" : "Saved")
            XCTAssertFalse(first.saveState.isSaved)
            XCTAssertEqual(try drafts.load(userID: ownerID)?.pendingCompletion?.run, original)
            clock.date.addTimeInterval(600)
            let recovered = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: unavailable, draftStore: drafts, routeStore: routes,
                persistsRecovery: true, exportJobs: jobs)
            recovered.audioCoachEnabled = false
            defer { recovered.discard() }
            recovered.prepare()
            XCTAssertEqual(recovered.stage, .summary(original))
            recovered.retrySave(weightLbs: 220)
            XCTAssertEqual(saver.runs.count, 1, "A prior Health commit must be reconciled, never rewritten")
            XCTAssertEqual(recovered.saveState, .localRecoveryPending)
            XCTAssertEqual(try drafts.load(userID: ownerID)?.pendingCompletion?.run, original)
            saver.reconciledID = "retained-health"
            let finallyWritable = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, routeStore: routes,
                persistsRecovery: true, exportJobs: jobs)
            finallyWritable.audioCoachEnabled = false
            defer { finallyWritable.discard() }
            finallyWritable.prepare(); finallyWritable.retrySave(weightLbs: 220)
            XCTAssertEqual(saver.runs.count, 1)
            XCTAssertEqual(saver.weights, [165])
            XCTAssertEqual(finallyWritable.saveState, .appleHealth)
            let saved = try XCTUnwrap(backup.runs(since: .distantPast, for: ownerID).first)
            XCTAssertEqual(saved.id, "retained-health")
            XCTAssertEqual(saved.recordingID, original.recordingID)
            XCTAssertEqual(saved.sensors, original.sensors)
            XCTAssertEqual(saved.manualLaps, original.manualLaps)
            XCTAssertEqual(saved.movingSeconds, 20)
            XCTAssertEqual(saved.saveReview, .shortRecording)
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).count, 1)
            XCTAssertNil(try drafts.load(userID: ownerID))
        }
    }

    @MainActor
    func testEmptyRecordingCannotSaveAndShortRecordingRequiresDeliberateReview() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recorder.begin()
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertTrue(saver.runs.isEmpty)
            XCTAssertTrue(backup.runs(since: .distantPast, for: ownerID).isEmpty)
            XCTAssertEqual(recorder.stage, .running)
            clock.date.addTimeInterval(20)
            recorder.pause()
            recorder.finish(weightLbs: 165)
            XCTAssertEqual(recorder.stage, .paused)
            XCTAssertTrue(saver.runs.isEmpty)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            let run = try XCTUnwrap(saver.runs.first)
            XCTAssertEqual(run.movingSeconds, 20)
            XCTAssertEqual(run.distanceMeters, 0)
            XCTAssertEqual(run.saveReview, .shortRecording)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.count, 1)
            saver.completeNext(with: .failed)
            recorder.retrySave(weightLbs: 220)
            XCTAssertEqual(saver.runs, [run, run])
            XCTAssertEqual(saver.weights, [165, 165])
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).count, 1)
            saver.completeNext(with: .saved("short-health"))
        }
    }

    @MainActor
    func testFailedShortSaveRecoversFrozenReviewedRunAndRetriesOriginalIdentityAndWeight() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drafts = RunRecordingDraftStore(directory: directory)
            let first = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: RunFallbackStore(directory: nil), draftStore: drafts, persistsRecovery: true)
            first.audioCoachEnabled = false
            defer { first.discard() }
            first.begin(); clock.date.addTimeInterval(20); first.pause()
            first.finish(weightLbs: 165, confirmShortRecording: true)
            let original = try XCTUnwrap(saver.runs.first)
            saver.completeNext(with: .failed)
            XCTAssertEqual(first.saveState, .failed)
            XCTAssertEqual(try drafts.load(userID: ownerID)?.pendingCompletion?.run, original)
            clock.date.addTimeInterval(600)
            let recovered = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            recovered.audioCoachEnabled = false
            defer { recovered.discard() }
            recovered.prepare()
            XCTAssertEqual(recovered.stage, .summary(original), "Recovery must not reopen accepted measurements as a paused timer")
            XCTAssertEqual(recovered.saveState, .failed)
            XCTAssertEqual(recovered.elapsedSeconds, 20)
            recovered.retrySave(weightLbs: 220)
            XCTAssertEqual(saver.runs, [original, original])
            XCTAssertEqual(saver.weights, [165, 165])
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).count, 1)
            saver.completeNext(with: .saved("short-health"))
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).first?.recordingID, original.recordingID)
            XCTAssertNil(try drafts.load(userID: ownerID))
        }
    }

    @MainActor
    func testUnwritableFinishReceiptKeepsRunPausedAndAllowsResumeBeforeRetry() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drafts = RunRecordingDraftStore(directory: directory)
            let recorder = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            recorder.audioCoachEnabled = false
            defer { recorder.discard() }
            recorder.begin(); clock.date.addTimeInterval(20); recorder.pause()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let originals = try files.map { ($0, try Data(contentsOf: $0)) }
            XCTAssertFalse(originals.isEmpty)
            for (url, _) in originals { try Data("unreadable finish receipt".utf8).write(to: url) }
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(recorder.stage, .paused)
            XCTAssertEqual(recorder.elapsedSeconds, 20)
            XCTAssertTrue(saver.runs.isEmpty)
            XCTAssertTrue(backup.runs(since: .distantPast, for: ownerID).isEmpty)
            for (url, bytes) in originals { try bytes.write(to: url) }
            recorder.resume(); clock.date.addTimeInterval(10); recorder.refreshAfterForeground()
            XCTAssertEqual(recorder.elapsedSeconds, 30)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.first?.movingSeconds, 30)
            XCTAssertEqual(saver.runs.count, 1)
            saver.completeNext(with: .saved("accepted-after-retry"))
        }
    }

    @MainActor
    func testMeasuredSensorsExpireDuringPauseAndStayInExactSavedRecording() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recorder.begin()
            clock.date.addTimeInterval(10)
            let first = RunHeartRateSample(date: clock.date, bpm: 142, sourceID: "test.watch", sourceName: "Test Watch")
            recorder.ingestHeartRate(first)
            recorder.ingestCadence(.init(date: clock.date, stepsPerMinute: 172))
            XCTAssertEqual(recorder.liveHeartRate, first)
            XCTAssertEqual(recorder.liveCadence?.stepsPerMinute, 172)
            recorder.pause()
            XCTAssertNil(recorder.liveHeartRate)
            XCTAssertNil(recorder.liveCadence)
            clock.date.addTimeInterval(60)
            recorder.ingestHeartRate(.init(date: clock.date, bpm: 160, sourceID: "test.watch", sourceName: "Test Watch"))
            XCTAssertEqual(recorder.sensors.heartRate, [first])
            recorder.resume()
            XCTAssertNil(recorder.liveHeartRate, "A previous segment is not a current reading")
            clock.date.addTimeInterval(10)
            let second = RunHeartRateSample(date: clock.date, bpm: 145, sourceID: "test.watch", sourceName: "Test Watch")
            recorder.ingestHeartRate(second)
            clock.date.addTimeInterval(31)
            XCTAssertNil(recorder.liveHeartRate, "A dropout stays unavailable")
            clock.date.addTimeInterval(20)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.first?.sensors?.heartRate, [first, second])
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).first?.sensors, saver.runs.first?.sensors)
        }
    }

    @MainActor
    func testExactlyOneActiveMinuteWithoutGPSPreservesZeroDistanceAndRecordingIdentity() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recorder.begin()
            let recordingID = recorder.session.id
            clock.date.addTimeInterval(60)
            recorder.pause()
            XCTAssertEqual(recorder.elapsedSeconds, 60)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.count, 1)
            guard let recorded = saver.runs.first else { return XCTFail("The timed recording must reach the save pipeline") }
            XCTAssertEqual(recorded.id, recordingID)
            XCTAssertEqual(recorded.recordingID, recordingID)
            XCTAssertEqual(recorded.movingSeconds, 60)
            XCTAssertEqual(recorded.endDate.timeIntervalSince(recorded.startDate), 60)
            XCTAssertEqual(recorded.distanceMeters, 0, "Missing GPS must not invent distance")
            XCTAssertFalse(recorded.hasRoute)
            XCTAssertTrue(recorded.splits.isEmpty)
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID), [localCopy(recorded)])
            XCTAssertTrue(backup.containsRecording(id: recordingID, for: ownerID))

            saver.completeNext(with: .saved("zero-distance-health-id"))
            let saved = backup.runs(since: .distantPast, for: ownerID)
            XCTAssertEqual(saved.count, 1)
            XCTAssertEqual(saved.first?.id, "zero-distance-health-id")
            XCTAssertEqual(saved.first?.recordingID, recordingID)
            XCTAssertEqual(saved.first?.movingSeconds, 60)
            XCTAssertEqual(saved.first?.distanceMeters, 0)
            XCTAssertEqual(saved.first?.hasRoute, false)
            XCTAssertTrue(saved.first?.splits.isEmpty == true)
            XCTAssertTrue(backup.containsRecording(id: recordingID, for: ownerID))
            XCTAssertEqual(recorder.saveState, .appleHealth)
        }
    }

    @MainActor
    func testFailedHealthExportKeepsExactPausesAndRetryReusesTheSameRecording() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recordPausedRun(recorder, clock: clock)
            recorder.finish(weightLbs: 165)
            XCTAssertEqual(saver.runs.count, 1)
            XCTAssertEqual(recorder.saveState, .syncingLocal)
            let recorded = saver.runs[0]
            XCTAssertEqual(recorded.movingSeconds, 90)
            XCTAssertEqual(recorded.endDate.timeIntervalSince(recorded.startDate), 135)
            XCTAssertEqual(recorded.pauseTimeline?.summary(startDate: recorded.startDate,
                endDate: recorded.endDate, activeSeconds: recorded.movingSeconds)?.explicitPauseSeconds, 45)
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).first, localCopy(recorded))

            saver.completeNext(with: .failed)
            XCTAssertEqual(recorder.saveState, .localOnly)
            recorder.retrySave(weightLbs: 165)
            recorder.retrySave(weightLbs: 165)
            XCTAssertEqual(saver.runs.count, 2, "An in-flight Health retry must not create another attempt")
            XCTAssertEqual(saver.runs[1], recorded, "Retry preserves identity, timestamps, splits and the actual pauses")
            saver.completeNext(with: .saved("confirmed-health-id"))
            XCTAssertEqual(recorder.saveState, .appleHealth)
            let history = backup.runs(since: .distantPast, for: ownerID)
            XCTAssertEqual(history.count, 1)
            XCTAssertEqual(history.first?.id, "confirmed-health-id")
            XCTAssertEqual(history.first?.pauseTimeline, recorded.pauseTimeline)
            XCTAssertTrue(backup.containsRecording(id: recorded.id, for: ownerID))
            if case .summary(let run) = recorder.stage {
                XCTAssertEqual(run.id, "confirmed-health-id")
                XCTAssertEqual(run.pauseTimeline, recorded.pauseTimeline)
            } else { XCTFail("A saved run must stay reviewable") }
        }
    }

    @MainActor
    func testSavedButUnreadableHealthResultCannotBeRetriedAsANewWorkout() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recordPausedRun(recorder, clock: clock)
            recorder.finish(weightLbs: 165)
            let recorded = saver.runs[0]
            saver.completeNext(with: .savedAwaitingReadAccess)
            XCTAssertEqual(recorder.saveState, .healthConfirmationPending)
            XCTAssertTrue(recorder.saveState.isSaved)
            recorder.retrySave(weightLbs: 165)
            XCTAssertEqual(saver.runs.count, 1, "Health already saved the workout; lack of a readable UUID is not a failed save")
            let local = backup.runs(since: .distantPast, for: ownerID)
            XCTAssertEqual(local.count, 1)
            XCTAssertEqual(local.first?.id, recorded.id, "A pending confirmation must not invent a Health UUID")
            XCTAssertEqual(local.first?.pauseTimeline, recorded.pauseTimeline)
        }
    }

    @MainActor
    func testLateHealthCompletionUsesTheOriginalAccountAndCannotRetryAsAnotherUser() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            recordPausedRun(recorder, clock: clock)
            recorder.finish(weightLbs: 165)
            let recorded = saver.runs[0]
            (DIContainer.shared.authService as? MockAuthService)?.currentUserID = "another-test-account"
            saver.completeNext(with: .failed)
            recorder.retrySave(weightLbs: 165)
            XCTAssertEqual(saver.runs.count, 1)
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).first?.pauseTimeline, recorded.pauseTimeline)
            XCTAssertTrue(backup.runs(since: .distantPast, for: "another-test-account").isEmpty)
        }
    }

    @MainActor
    func testRecoveredRouteExportsEarlierAndNewSegmentsWithoutDuplicateMetrics() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let drafts = RunRecordingDraftStore(directory: directory.appendingPathComponent("drafts"))
            let routes = RunRouteArchiveStore(directory: directory.appendingPathComponent("routes"), now: { clock.date })
            let plan = RunWorkoutPlan.builtinTemplates(metric: true)[0]
            let scheduled = RunScheduledContext(commitment: TrainingRunCommitment(id: "planned-session", date: clock.date, plan: plan))
            let first = RunRecorderViewModel(metric: true, workoutPlan: plan, currentDate: { clock.date }, recordsLocation: false,
                                            store: saver, completedRunStore: backup, draftStore: drafts,
                                            routeStore: routes, persistsRecovery: true, scheduledContext: scheduled)
            first.audioCoachEnabled = false
            defer { first.discard(); try? FileManager.default.removeItem(at: directory) }
            first.begin()
            first.ingest(location(at: clock.date, latitude: 40))
            clock.date.addTimeInterval(5)
            first.ingest(location(at: clock.date, latitude: 40.0001))
            first.checkpointForBackground()
            let savedDistance = first.distanceMeters
            clock.date.addTimeInterval(300)
            let recovered = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                                                store: saver, completedRunStore: backup, draftStore: drafts,
                                                routeStore: routes, persistsRecovery: true)
            recovered.audioCoachEnabled = false
            defer { recovered.discard() }
            recovered.prepare()
            XCTAssertEqual(recovered.stage, .paused)
            XCTAssertTrue(recovered.recoveredRecording)
            XCTAssertEqual(recovered.session.id, first.session.id)
            XCTAssertEqual(recovered.recordedRouteSegments.map(\.count), [2])
            XCTAssertEqual(recovered.elapsedSeconds, 5)
            recovered.resume()
            recovered.ingest(location(at: clock.date, latitude: 41))
            XCTAssertEqual(recovered.distanceMeters, savedDistance)
            clock.date.addTimeInterval(5)
            recovered.ingest(location(at: clock.date, latitude: 41.0001))
            recovered.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.count, 1)
            XCTAssertEqual(saver.runs[0].movingSeconds, 10)
            XCTAssertEqual(saver.runs[0].recordingID, first.session.id)
            XCTAssertEqual(saver.runs[0].scheduledContext, scheduled, "Recovery retains the exact reviewed calendar prescription")
            XCTAssertEqual(saver.runs[0].reidentified(as: "health-alias").scheduledContext, scheduled)
            XCTAssertEqual(saver.runs[0].routeSegmentStarts?.count, 2)
            XCTAssertEqual(saver.locations[0].count, 4)
            XCTAssertEqual(recovered.recordedRouteSegments.map(\.count), [2, 2])
            XCTAssertLessThan(saver.runs[0].distanceMeters, 25)
            XCTAssertNil(try drafts.load(userID: ownerID))
            XCTAssertEqual(try routes.load(recordingID: first.session.id, userID: ownerID)?.segments.map(\.count), [2, 2])
            saver.completeNext(with: .savedAwaitingReadAccess)
            recovered.retrySave(weightLbs: 165)
            XCTAssertEqual(saver.runs.count, 1)
            XCTAssertEqual(backup.runs(since: .distantPast, for: ownerID).count, 1)
        }
    }

    @MainActor
    func testCorruptSeparateStepLibraryCannotLoseAcceptedReceiptOrRewriteItsBytes() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let suite = "RunStepReceiptNative.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.run_workout_results", userID: ownerID))
            let corrupt = Data("preserve original result data".utf8)
            defaults.set(corrupt, forKey: key)
            let results = RunWorkoutResultStore(userDefaults: defaults, authService: DIContainer.shared.authService)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let drafts = RunRecordingDraftStore(directory: directory)
            let recorder = RunRecorderViewModel(metric: true, workoutPlan: RunWorkoutPlan.builtinTemplates(metric: true)[0],
                currentDate: { clock.date }, recordsLocation: false, store: saver, completedRunStore: backup,
                draftStore: drafts, persistsRecovery: true, workoutResultStore: results)
            recorder.audioCoachEnabled = false
            recorder.begin()
            clock.date.addTimeInterval(90)
            recorder.finish(weightLbs: 165, confirmShortRecording: true)
            let accepted = try XCTUnwrap(backup.runs(since: .distantPast, for: ownerID).first)
            let receipt = try XCTUnwrap(accepted.workoutResult)
            XCTAssertEqual(receipt.steps.first?.elapsedSeconds, 90)
            XCTAssertEqual(receipt, recorder.finishedWorkoutResult)
            XCTAssertEqual(defaults.data(forKey: key), corrupt)
            XCTAssertNil(try drafts.load(userID: ownerID), "Run and exact receipt are committed together before recovery cleanup")
            saver.completeNext(with: .saved("health-alias"))
            let renamed = try XCTUnwrap(backup.runs(since: .distantPast, for: ownerID).first)
            XCTAssertEqual(renamed.workoutResult?.runID, "health-alias")
            XCTAssertEqual(renamed.workoutResult?.steps, receipt.steps)
            XCTAssertEqual(defaults.data(forKey: key), corrupt, "Alias migration cannot delete or overwrite the unreadable original library")
            recorder.retryWorkoutReceipt()
            XCTAssertEqual(saver.runs.count, 1, "Step-receipt repair must not export another Health workout")
            XCTAssertNil(recorder.workoutReceiptMessage)
        }
    }

    @MainActor
    func testRetryFreezesAcceptedShoeEvenAfterDefaultChanges() throws {
        try withIsolatedRecorder { recorder, clock, saver, backup, ownerID in
            let gear = RunningShoeStore()
            let original = RunningShoe(id: "original-pair", name: "Original", brand: "QA", isDefault: true)
            let later = RunningShoe(id: "later-pair", name: "Later", brand: "QA")
            gear.addShoe(original); gear.addShoe(later)
            recordPausedRun(recorder, clock: clock)
            recorder.finish(weightLbs: 165)
            XCTAssertEqual(saver.runs.first?.shoeID, original.id)
            saver.completeNext(with: .failed)
            gear.setDefaultShoe(id: later.id)
            recorder.retrySave(weightLbs: 165)
            XCTAssertEqual(saver.runs.last?.shoeID, original.id)
            saver.completeNext(with: .saved("shoe-health-alias"))
            let accepted = try XCTUnwrap(backup.runs(since: .distantPast, for: ownerID).first)
            XCTAssertEqual(accepted.shoeID, original.id)
            XCTAssertEqual(gear.explicitShoeID(for: accepted), original.id)
            XCTAssertEqual(gear.defaultShoe()?.id, later.id)
        }
    }

    @MainActor
    private func recordPausedRun(_ recorder: RunRecorderViewModel, clock: Clock) {
        recorder.begin()
        recorder.ingest(location(at: clock.date, latitude: 40))
        clock.date.addTimeInterval(60)
        recorder.ingest(location(at: clock.date, latitude: 40.0018))
        recorder.pause()
        clock.date.addTimeInterval(45)
        recorder.resume()
        clock.date.addTimeInterval(30)
    }

    private func location(at date: Date, latitude: Double) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -74), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
    }

    private func localCopy(_ run: Run) -> Run {
        var copy = run
        copy.hasRoute = false
        return copy
    }

    @MainActor
    func testGoalRevisionRequiresDurableCheckpointAndRestoresOriginalPlusReviewedTarget() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let drafts = RunRecordingDraftStore(directory: directory)
            let step = RunWorkoutStep(id: "goal", kind: .hard, title: "Run", goal: .duration(seconds: 600))
            let plan = RunWorkoutPlan(id: "goal-plan", name: "Ten minute run", subtitle: "Time goal", steps: [step])
            let first = RunRecorderViewModel(metric: true, workoutPlan: plan, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            first.audioCoachEnabled = false
            defer { first.discard(); try? FileManager.default.removeItem(at: directory) }
            first.begin()
            clock.date.addTimeInterval(60)
            first.pause()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let copies = try files.map { ($0, try Data(contentsOf: $0)) }
            XCTAssertFalse(copies.isEmpty)
            for (file, _) in copies { try Data("unreadable checkpoint".utf8).write(to: file) }
            XCTAssertNotNil(first.reviseGoal(step: step, goal: .duration(seconds: 900), operationID: "reviewed-change"))
            XCTAssertEqual(first.workoutProgress?.currentStep?.goal, .duration(seconds: 600))
            for (file, data) in copies { try data.write(to: file) }
            XCTAssertNil(first.reviseGoal(step: step, goal: .duration(seconds: 900), operationID: "reviewed-change"))
            let checkpoint = try XCTUnwrap(drafts.load(userID: ownerID))
            XCTAssertEqual(checkpoint.workout?.plan, plan)
            XCTAssertEqual(checkpoint.workout?.goalRevisions?.count, 1)
            clock.date.addTimeInterval(300)
            let restored = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            restored.audioCoachEnabled = false
            defer { restored.discard() }
            restored.prepare()
            XCTAssertEqual(restored.stage, .paused)
            XCTAssertEqual(restored.elapsedSeconds, 60)
            XCTAssertEqual(restored.workoutPlan, plan)
            XCTAssertEqual(restored.workoutProgress?.currentStep?.goal, .duration(seconds: 900))
            XCTAssertEqual(restored.workoutProgress?.remainingSeconds, 840)
            XCTAssertTrue(saver.runs.isEmpty)
        }
    }

    @MainActor
    func testManualLapRequiresDurableCheckpointAndRecoveryDoesNotAdvanceWorkout() throws {
        try withIsolatedRecorder { _, clock, saver, backup, ownerID in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let drafts = RunRecordingDraftStore(directory: directory)
            let step = RunWorkoutStep(id: "prescribed", kind: .hard, title: "Keep running", goal: .duration(seconds: 600))
            let plan = RunWorkoutPlan(id: "lap-plan", name: "Lap boundaries", subtitle: "Separate from steps", steps: [step])
            let first = RunRecorderViewModel(metric: true, workoutPlan: plan, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            first.audioCoachEnabled = false
            defer { first.discard(); try? FileManager.default.removeItem(at: directory) }
            first.begin(); clock.date.addTimeInterval(30)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let copies = try files.map { ($0, try Data(contentsOf: $0)) }
            XCTAssertFalse(copies.isEmpty)
            for (file, _) in copies { try Data("unreadable checkpoint".utf8).write(to: file) }
            first.markLap(expectedPreviousID: nil, operationID: "lap-command")
            XCTAssertTrue(first.session.manualLaps.isEmpty)
            XCTAssertEqual(first.workoutProgress?.currentStep?.id, step.id)
            for (file, data) in copies { try data.write(to: file) }
            first.markLap(expectedPreviousID: nil, operationID: "lap-command")
            first.markLap(expectedPreviousID: nil, operationID: "lap-command")
            XCTAssertEqual(first.session.manualLaps.count, 1)
            XCTAssertEqual(first.session.manualLaps.first?.activeElapsedSeconds, 30)
            XCTAssertEqual(first.workoutProgress?.currentStep?.id, step.id)
            let checkpoint = try XCTUnwrap(drafts.load(userID: ownerID))
            XCTAssertEqual(checkpoint.session.manualLaps, first.session.manualLaps)
            clock.date.addTimeInterval(300)
            let restored = RunRecorderViewModel(metric: true, currentDate: { clock.date }, recordsLocation: false,
                store: saver, completedRunStore: backup, draftStore: drafts, persistsRecovery: true)
            restored.audioCoachEnabled = false
            defer { restored.discard() }
            restored.prepare()
            XCTAssertEqual(restored.stage, .paused)
            XCTAssertEqual(restored.session.manualLaps, first.session.manualLaps)
            XCTAssertEqual(restored.workoutProgress?.currentStep?.id, step.id)
            restored.resume(); clock.date.addTimeInterval(30)
            restored.markLap(expectedPreviousID: "lap-command", operationID: "second-lap")
            XCTAssertEqual(restored.session.manualLaps.last?.activeElapsedSeconds, 60)
            XCTAssertEqual(restored.workoutProgress?.currentStep?.id, step.id)
            restored.finish(weightLbs: 165, confirmShortRecording: true)
            XCTAssertEqual(saver.runs.first?.manualLaps?.count, 2)
            XCTAssertEqual(saver.runs.first?.movingSeconds, 60)
        }
    }

    @MainActor
    private func withIsolatedRecorder(_ body: (RunRecorderViewModel, Clock, Saver, RunFallbackStore, String) throws -> Void) throws {
        let oldAuth = DIContainer.shared.authService
        let oldAnalytics = DIContainer.shared.analyticsManager
        let defaults = UserDefaults.standard
        let originalActivation = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("activation_funnel_") }
        let oldAudio = defaults.object(forKey: "runAudioCoachEnabled")
        let legacyPrefixes = ["myfitplate.running_shoes", "myfitplate.running_shoe_tags", "myfitplate.run_workout_results"]
        let oldLegacy = legacyPrefixes.compactMap { key in defaults.object(forKey: key).map { (key, $0) } }
        let ownerID = "run-pause-export-test-" + UUID().uuidString
        let auth = MockAuthService()
        auth.currentUserID = ownerID
        DIContainer.shared.authService = auth
        DIContainer.shared.analyticsManager = nil
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = RunFallbackStore(directory: directory)
        let clock = Clock()
        let saver = Saver()
        let recorder = RunRecorderViewModel(metric: true, currentDate: { clock.date },
                                            recordsLocation: false, store: saver, completedRunStore: backup)
        recorder.audioCoachEnabled = false
        defer {
            recorder.discard()
            DIContainer.shared.authService = oldAuth
            DIContainer.shared.analyticsManager = oldAnalytics
            if let oldAudio { defaults.set(oldAudio, forKey: "runAudioCoachEnabled") } else { defaults.removeObject(forKey: "runAudioCoachEnabled") }
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("activation_funnel_") { defaults.removeObject(forKey: key) }
            for (key, value) in originalActivation { defaults.set(value, forKey: key) }
            for prefix in legacyPrefixes {
                if let key = AccountScopedStorageKey.make(prefix: prefix, userID: ownerID) { defaults.removeObject(forKey: key) }
                defaults.removeObject(forKey: prefix)
            }
            for (key, value) in oldLegacy { defaults.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: directory)
        }
        try body(recorder, clock, saver, backup, ownerID)
    }

    private final class Clock { var date = Date(timeIntervalSince1970: 100_000) }

    private final class Saver: RunHealthSaving {
        private(set) var runs: [Run] = []
        private(set) var weights: [Double] = []
        private(set) var locations: [[CLLocation]] = []
        private var callbacks: [(RunHealthSaveOutcome) -> Void] = []
        var reconciledID: String?
        func saveWithOutcome(run: Run, locations: [CLLocation], weightLbs: Double, completion: @escaping (RunHealthSaveOutcome) -> Void) {
            runs.append(run)
            weights.append(weightLbs)
            self.locations.append(locations)
            callbacks.append(completion)
        }
        func reconcileRecording(recordingID: String, completion: @escaping (String?) -> Void) { completion(reconciledID) }
        func completeNext(with outcome: RunHealthSaveOutcome) { callbacks.removeFirst()(outcome) }
    }
}
