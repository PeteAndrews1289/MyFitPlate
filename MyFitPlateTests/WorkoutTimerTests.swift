import XCTest
import Combine
import MyFitPlateCore
import MyFitPlateShared
@testable import MyFitPlate

final class WorkoutTimerTests: XCTestCase {
    private let timerUserID = "workout-timer-tests"
    private var timerStorageKey: String {
        AccountScopedStorageKey.make(
            prefix: "totalWorkoutTimer_testRoutine",
            userID: timerUserID
        )!
    }

    override func setUpWithError() throws {
        // Clear UserDefaults state for tests
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
        UserDefaults.standard.removeObject(forKey: timerStorageKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "totalWorkoutTimer_testRoutine")
        UserDefaults.standard.removeObject(forKey: timerStorageKey)
    }

    @MainActor
    func testTotalWorkoutTimer_Formatting() throws {
        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        
        // Given
        timer.totalTimeElapsed = 45
        XCTAssertEqual(timer.formattedTime(), "00:45")
        
        timer.totalTimeElapsed = 65
        XCTAssertEqual(timer.formattedTime(), "01:05")
        
        timer.totalTimeElapsed = 3665
        XCTAssertEqual(timer.formattedTime(), "1:01:05")
    }
    
    @MainActor
    func testTotalWorkoutTimer_StatePersistence() async throws {
        let timer1 = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        timer1.start()
        
        try await Task.sleep(nanoseconds: 1_200_000_000)
        
        // Given timer1 has started and saved state in UserDefaults
        XCTAssertTrue(timer1.totalTimeElapsed >= 1.0)
        
        // When timer2 is initialized with same routineId
        let timer2 = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        
        // Then it should load the state and resume
        XCTAssertTrue(timer2.totalTimeElapsed >= 1.0)
        
        timer1.stop()
        timer2.stop()
    }

    @MainActor
    func testTotalWorkoutTimer_DiscardsAbandonedWorkoutState() throws {
        let key = timerStorageKey
        UserDefaults.standard.set(
            Date().addingTimeInterval(-(TotalWorkoutTimer.maximumRestorableDuration + 60)),
            forKey: key
        )

        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)

        XCTAssertEqual(timer.totalTimeElapsed, 0)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    @MainActor
    func testTotalWorkoutTimer_DiscardsFutureStartTime() throws {
        let key = timerStorageKey
        UserDefaults.standard.set(Date().addingTimeInterval(60), forKey: key)

        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)

        XCTAssertEqual(timer.totalTimeElapsed, 0)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    @MainActor
    func testActivityClockUsesRecoveredElapsedInsteadOfRestartingOrIncludingPausedTime() throws {
        let historicalStart = Date().addingTimeInterval(-3_600)
        UserDefaults.standard.set(historicalStart, forKey: timerStorageKey)
        let timer = TotalWorkoutTimer(routineId: "testRoutine", userID: timerUserID)
        defer { timer.stop() }
        XCTAssertEqual(timer.activityStartTime, historicalStart)

        // A resumed draft has its own saved active duration. Its old wall-clock
        // start must not add time paused outside the player or reset it to zero.
        timer.pause()
        let beforeResume = Date()
        timer.resume(elapsed: 1_420)
        let afterResume = Date()
        XCTAssertEqual(timer.totalTimeElapsed, 1_420)
        XCTAssertGreaterThanOrEqual(timer.activityStartTime, beforeResume.addingTimeInterval(-1_420))
        XCTAssertLessThanOrEqual(timer.activityStartTime, afterResume.addingTimeInterval(-1_420))
        XCTAssertNotEqual(timer.activityStartTime, historicalStart)
    }
    
    @MainActor
    func testRestTimer_StartsAndStops() throws {
        let restTimer = RestTimer()
        
        // Given
        XCTAssertEqual(restTimer.timeRemaining, 0)
        
        // When
        restTimer.start(duration: 60, routineName: "Test Routine")
        
        // Then
        // Rest is measured from a deadline, so the first reading includes the
        // small amount of time spent starting it rather than resetting to 60.
        XCTAssertGreaterThan(restTimer.timeRemaining, 59)
        XCTAssertLessThanOrEqual(restTimer.timeRemaining, 60)
        
        // Stop
        restTimer.stop()
        XCTAssertEqual(restTimer.timeRemaining, 0)
    }

    @MainActor
    func testRestAdjustmentsPreserveDeadlineAndSetAssociationAcrossRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skips = WorkoutRestSkipStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: skips, currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "set-1")
        let identity = try XCTUnwrap(timer.state?.id)
        now = start.addingTimeInterval(20)
        timer.adjust(by: 30)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(90))
        XCTAssertEqual(timer.timeRemaining, 70)
        timer.adjust(by: -15)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(75))
        XCTAssertEqual(timer.timeRemaining, 55)
        XCTAssertEqual(timer.state?.id, identity)

        let recovered = RestTimer(skipStore: skips, currentDate: { now })
        defer { recovered.stop() }
        recovered.restore(try XCTUnwrap(timer.state))
        XCTAssertEqual(recovered.deadline, start.addingTimeInterval(75))
        XCTAssertEqual(recovered.timeRemaining, 55)
        XCTAssertEqual(recovered.state?.exerciseID, "bench")
        XCTAssertEqual(recovered.state?.setID, "set-1")
    }

    @MainActor
    func testRestRestoreAcceptsAdjustedDeadlineForTheSameRestIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper")
        let original = try XCTUnwrap(timer.state)
        timer.restore(try XCTUnwrap(original.adjusted(by: 30, at: now)))
        timer.refresh()
        XCTAssertEqual(timer.state?.id, original.id)
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(90))
        XCTAssertEqual(timer.timeRemaining, 90)
    }

    @MainActor
    func testAdjustCannotReviveSkippedRestOrStopANewerRest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let skips = WorkoutRestSkipStore(directory: directory)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: skips, currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper")
        let skipped = try XCTUnwrap(timer.state?.id)
        XCTAssertTrue(skips.request(restID: skipped, now: now))
        timer.adjust(by: 30)
        XCTAssertNil(timer.state)

        timer.start(duration: 60, routineName: "Upper")
        let next = try XCTUnwrap(timer.state?.id)
        XCTAssertNotEqual(next, skipped)
        XCTAssertTrue(skips.request(restID: skipped, now: now))
        timer.refresh()
        XCTAssertEqual(timer.state?.id, next)
        now = now.addingTimeInterval(61)
        timer.adjust(by: 30)
        XCTAssertNil(timer.state, "Extending a finished rest must not restart it")
    }

    @MainActor
    func testShorteningToZeroStopsRestAndPartialSecondsDisplayInFull() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper")
        now = start.addingTimeInterval(0.05)
        timer.refresh()
        XCTAssertEqual(timer.formattedTime(), "01:00")
        now = start.addingTimeInterval(45.1)
        timer.adjust(by: -15)
        XCTAssertNil(timer.state)
        XCTAssertEqual(timer.timeRemaining, 0)
        XCTAssertEqual(timer.formattedTime(), "00:00")
    }

    @MainActor
    func testNonfiniteAdjustmentsLeaveActiveRestUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper")
        let original = timer.state
        for invalid in [Double.nan, .infinity, -.infinity] { timer.adjust(by: invalid) }
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.timeRemaining, 60)
    }

    @MainActor
    func testStaleRestControlsAndRecoveryCannotChangeTheNextRest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "set-1")
        let first = try XCTUnwrap(timer.state)
        timer.skip(restID: first.id)
        XCTAssertEqual(timer.completion?.outcome, .skipped)
        timer.start(duration: 90, routineName: "Upper", exerciseID: "bench", setID: "set-2")
        let next = try XCTUnwrap(timer.state)

        timer.adjust(by: 30, for: first.id)
        timer.skip(restID: first.id)
        timer.restore(first)

        XCTAssertEqual(timer.state, next)
        XCTAssertEqual(timer.timeRemaining, 90)
        XCTAssertNil(timer.completion)
        XCTAssertNil(timer.errorMessage)
        XCTAssertEqual(timer.state?.setID, "set-2")
    }

    @MainActor
    func testRejectedSkipAndShortenKeepTheOriginalRunningRest() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: nil), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "set-1")
        let original = try XCTUnwrap(timer.state)

        timer.skip(restID: original.id)
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.timeRemaining, 60)
        XCTAssertNotNil(timer.errorMessage)
        XCTAssertNil(timer.completion, "A failed receipt cannot show accepted Skip")

        timer.adjust(by: -120, for: original.id)
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.deadline, original.deadline)
        XCTAssertNotNil(timer.errorMessage)
        XCTAssertNil(timer.completion)
    }

    @MainActor
    func testRecoveredRestKeepsItsDeadlineAndExpiredRecoveryDoesNotRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start.addingTimeInterval(37)
        let saved = try XCTUnwrap(WorkoutRestState(duration: 120, routineName: "Upper", exerciseID: "bench", setID: "set-1", now: start))
        let timer = RestTimer(skipStore: store, currentDate: { now })
        timer.restore(saved)
        XCTAssertTrue(timer.isRecovered)
        XCTAssertEqual(timer.timeRemaining, 83)
        timer.adjust(by: 30, for: saved.id)
        let adjusted = try XCTUnwrap(timer.state)
        XCTAssertTrue(timer.isRecovered)
        XCTAssertEqual(adjusted.id, saved.id)
        XCTAssertEqual(adjusted.deadline, start.addingTimeInterval(150))
        timer.suspendUpdates()

        now = start.addingTimeInterval(200)
        let reopened = RestTimer(skipStore: store, currentDate: { now })
        reopened.restore(adjusted)
        XCTAssertNil(reopened.state)
        XCTAssertEqual(reopened.timeRemaining, 0)
        XCTAssertEqual(reopened.completion?.id, saved.id)
        XCTAssertEqual(reopened.completion?.outcome, .elapsed)
        XCTAssertEqual(reopened.completion?.wasRecovered, true)
        reopened.adjust(by: 30, for: saved.id)
        XCTAssertNil(reopened.state, "An expired recovered rest must not become another duration")
        timer.stop()
        reopened.stop()
    }

    @MainActor
    func testClockReversalDoesNotClaimThatTheRestCompleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = try XCTUnwrap(WorkoutRestState(duration: 60, routineName: "Upper", now: start))
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { start.addingTimeInterval(-1) })
        defer { timer.stop() }
        timer.restore(saved)
        XCTAssertNil(timer.state)
        XCTAssertEqual(timer.completion?.outcome, .unavailable)
        XCTAssertEqual(timer.timeRemaining, 0)
    }

    @MainActor
    func testElapsedStatusClearsForTheNextRestAndDismissDoesNotAlterActiveTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", setID: "set-1")
        now = now.addingTimeInterval(61)
        timer.refresh()
        XCTAssertNil(timer.state)
        XCTAssertEqual(timer.completion?.outcome, .elapsed)
        timer.start(duration: 90, routineName: "Upper", setID: "set-2")
        let active = try XCTUnwrap(timer.state)
        XCTAssertNil(timer.completion)
        XCTAssertFalse(timer.isRecovered)
        timer.dismissCompletion()
        XCTAssertEqual(timer.state, active)
        XCTAssertEqual(timer.timeRemaining, 90)
    }

    @MainActor
    func testForegroundRefreshResumesTicksWithoutRestartingTheSavedRest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "set-1")
        let original = try XCTUnwrap(timer.state)
        timer.suspendUpdates()
        now = start.addingTimeInterval(20)
        timer.refresh()
        XCTAssertEqual(timer.timeRemaining, 40)

        let tick = expectation(description: "rest ticks after foreground refresh")
        let observation = timer.$timeRemaining.dropFirst().filter { $0 == 35 }.prefix(1)
            .sink { _ in tick.fulfill() }
        defer { observation.cancel() }
        now = start.addingTimeInterval(25)
        await fulfillment(of: [tick], timeout: 3)

        XCTAssertEqual(timer.timeRemaining, 35)
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(60))
    }

    @MainActor
    func testQueuedTickCannotReactivateSuspendedRestButForegroundRefreshCan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "set-1")
        let original = try XCTUnwrap(timer.state)
        timer.suspendUpdates()

        now = start.addingTimeInterval(20)
        timer.receiveScheduledTick()
        XCTAssertEqual(timer.timeRemaining, 60, "A callback queued before suspension must stay inactive")
        XCTAssertEqual(timer.state, original)

        timer.refresh()
        XCTAssertEqual(timer.timeRemaining, 40)
        now = start.addingTimeInterval(30)
        timer.receiveScheduledTick()
        XCTAssertEqual(timer.timeRemaining, 30, "Scheduled delivery resumes only after explicit foreground refresh")
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(60))
    }

    @MainActor
    func testCompletingNextSetEarlyStartsItsOwnFullRestAndRejectsOldActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 120, routineName: "PHUL Upper", exerciseID: "bench", setID: "first")
        let original = try XCTUnwrap(timer.state)
        now = start.addingTimeInterval(35)
        timer.startAfterCompletedSet(duration: 90, routineName: "PHUL Upper", exerciseID: "bench", setID: "second")
        let next = try XCTUnwrap(timer.state)

        XCTAssertNotEqual(next.id, original.id)
        XCTAssertEqual(next.setID, "second")
        XCTAssertEqual(next.exerciseID, "bench")
        XCTAssertEqual(next.routineName, "PHUL Upper")
        XCTAssertEqual(next.deadline, now.addingTimeInterval(90))
        XCTAssertEqual(timer.timeRemaining, 90)
        XCTAssertTrue(store.wasRequested(restID: original.id, now: now))
        XCTAssertFalse(store.wasRequested(restID: next.id, now: now))

        timer.skip(restID: original.id)
        timer.adjust(by: 30, for: original.id)
        timer.restore(original)
        timer.startAfterCompletedSet(duration: 120, routineName: "PHUL Upper", exerciseID: "bench", setID: "first")
        XCTAssertEqual(timer.state, next, "Old controls, recovery and duplicate callbacks cannot replace the new set's rest")
    }

    @MainActor
    func testDuplicateCompletedSetCannotExtendOrRestartItsExpiredRest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        var completions: [WorkoutRestCompletion] = []
        let observation = timer.$completion.compactMap { $0 }.sink { completions.append($0) }
        defer { observation.cancel() }
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        let original = try XCTUnwrap(timer.state)
        now = start.addingTimeInterval(20)
        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "bench", setID: "first")
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.timeRemaining, 40)

        now = start.addingTimeInterval(60)
        timer.refresh()
        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "bench", setID: "first")
        timer.receiveScheduledTick()
        timer.refresh()
        XCTAssertNil(timer.state)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.outcome, .elapsed)
        XCTAssertEqual(completions.first?.id, original.id)
    }

    @MainActor
    func testDeliberateSetReopenAllowsFreshRestWithoutResettingAnotherSet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        let original = try XCTUnwrap(timer.state)
        XCTAssertTrue(timer.cancelRestForReopenedSet("unrelated"))
        XCTAssertEqual(timer.state, original)

        now = start.addingTimeInterval(20)
        XCTAssertTrue(timer.cancelRestForReopenedSet("first"))
        XCTAssertNil(timer.state)
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        let corrected = try XCTUnwrap(timer.state)
        XCTAssertNotEqual(corrected.id, original.id)
        XCTAssertEqual(corrected.deadline, now.addingTimeInterval(60))
        timer.skip(restID: original.id)
        XCTAssertEqual(timer.state, corrected)
    }

    @MainActor
    func testInvalidNextSetRestCannotEndTheExistingRest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        let original = try XCTUnwrap(timer.state)
        for duration in [-1, .infinity, .nan, WorkoutRestState.maximumDuration + 1] {
            timer.startAfterCompletedSet(duration: duration, routineName: "Upper", exerciseID: "bench", setID: "second")
            XCTAssertEqual(timer.state, original)
            XCTAssertFalse(store.wasRequested(restID: original.id, now: now))
        }
        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "bench", setID: "second")
        XCTAssertEqual(timer.state?.setID, "second", "Rejected requests must not consume a future set's start identity")
    }

    @MainActor
    func testFailedRestReplacementAndReopenKeepTheOriginalTimerAndError() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: nil), currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        let original = try XCTUnwrap(timer.state)
        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "bench", setID: "second")
        XCTAssertEqual(timer.state, original)
        XCTAssertEqual(timer.timeRemaining, 60)
        XCTAssertNotNil(timer.errorMessage)
        XCTAssertNil(timer.completion)
        XCTAssertFalse(timer.cancelRestForReopenedSet("first"))
        XCTAssertEqual(timer.state, original)
        timer.startAfterCompletedSet(duration: 120, routineName: "Upper", exerciseID: "bench", setID: "first")
        XCTAssertEqual(timer.state, original, "Failed cancellation cannot let a duplicate completion silently restart the timer")
    }

    @MainActor
    func testRestoredExpiredAndSkippedSetCannotRestartFromARepeatedCallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = try XCTUnwrap(WorkoutRestState(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first", now: start))
        let now = start.addingTimeInterval(90)
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.restore(saved)
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first")
        XCTAssertNil(timer.state)
        XCTAssertEqual(timer.completion?.outcome, .elapsed)

        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "second")
        let second = try XCTUnwrap(timer.state)
        timer.skip(restID: second.id)
        timer.dismissCompletion()
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "second")
        XCTAssertNil(timer.state)
        XCTAssertNil(timer.completion)
    }

    @MainActor
    func testManualStartDoesNotReplaceActiveRestButAnAcceptedSetDoes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: WorkoutRestSkipStore(directory: directory), currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench")
        let manual = try XCTUnwrap(timer.state)
        timer.start(duration: 120, routineName: "Upper", exerciseID: "row")
        XCTAssertEqual(timer.state, manual)
        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "row", setID: "first-row")
        XCTAssertNotEqual(timer.state?.id, manual.id)
        XCTAssertEqual(timer.state?.exerciseID, "row")
        XCTAssertEqual(timer.timeRemaining, 90)
    }

    @MainActor
    func testZeroRestTransitionEndsPreviousRestAndCannotCancelLaterRestOnReplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 120, routineName: "Upper", exerciseID: "row", setID: "previous-round")
        let previous = try XCTUnwrap(timer.state)
        now = start.addingTimeInterval(25)
        timer.startAfterCompletedSet(duration: 0, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        XCTAssertNil(timer.state)
        XCTAssertEqual(timer.timeRemaining, 0)
        XCTAssertNil(timer.completion, "No-rest group transitions must not invent a completed or skipped rest message")
        XCTAssertTrue(store.wasRequested(restID: previous.id, now: now))

        timer.startAfterCompletedSet(duration: 90, routineName: "Upper", exerciseID: "row", setID: "last-partner")
        let next = try XCTUnwrap(timer.state)
        timer.startAfterCompletedSet(duration: 0, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        timer.skip(restID: previous.id)
        XCTAssertEqual(timer.state, next)
        XCTAssertEqual(timer.deadline, now.addingTimeInterval(90))
        XCTAssertFalse(store.wasRequested(restID: next.id, now: now))
    }

    @MainActor
    func testZeroRestTransitionAlsoEndsManualRestWithoutFabricatingCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkoutRestSkipStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.start(duration: 60, routineName: "Upper", exerciseID: "bench")
        let manual = try XCTUnwrap(timer.state)
        XCTAssertNil(manual.setID)
        timer.startAfterCompletedSet(duration: 0, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        XCTAssertNil(timer.state)
        XCTAssertNil(timer.completion)
        XCTAssertTrue(store.wasRequested(restID: manual.id, now: now))
        XCTAssertTrue(timer.cancelRestForReopenedSet("first-partner"))
        timer.startAfterCompletedSet(duration: 60, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        XCTAssertEqual(timer.state?.setID, "first-partner", "Explicit reopen permits a new deliberate outcome for the set")
    }

    @MainActor
    func testFailedZeroRestCancellationPreservesTimerAndRetryDoesNotConsumeSetIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let receiptDirectory = directory.appendingPathComponent("receipts")
        try Data("temporarily blocked".utf8).write(to: receiptDirectory)
        let store = WorkoutRestSkipStore(directory: receiptDirectory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = RestTimer(skipStore: store, currentDate: { now })
        defer { timer.stop() }
        timer.startAfterCompletedSet(duration: 120, routineName: "Upper", exerciseID: "row", setID: "previous-round")
        let previous = try XCTUnwrap(timer.state)
        timer.startAfterCompletedSet(duration: 0, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        XCTAssertEqual(timer.state, previous)
        XCTAssertEqual(timer.timeRemaining, 120)
        XCTAssertNotNil(timer.errorMessage)
        XCTAssertNil(timer.completion)
        XCTAssertFalse(store.wasRequested(restID: previous.id, now: now))

        try FileManager.default.removeItem(at: receiptDirectory)
        timer.startAfterCompletedSet(duration: 0, routineName: "Upper", exerciseID: "bench", setID: "first-partner")
        XCTAssertNil(timer.state)
        XCTAssertNil(timer.completion)
        XCTAssertNil(timer.errorMessage)
        XCTAssertTrue(store.wasRequested(restID: previous.id, now: now))
    }
}
