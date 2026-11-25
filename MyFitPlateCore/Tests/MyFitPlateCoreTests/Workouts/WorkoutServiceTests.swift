import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutServiceTests: XCTestCase {
    var service: WorkoutService!
    var mockRepo: MockWorkoutRepository!
    var mockCrash: MockCrashManager!
    var mockAuth: MockAuthService!
    var defaults: UserDefaults!
    var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "WorkoutServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        mockRepo = MockWorkoutRepository()
        DIContainer.shared.workoutRepository = mockRepo
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        DIContainer.shared.authService = mockAuth
        mockCrash = MockCrashManager()
        DIContainer.shared.crashManager = mockCrash
        ToastManager.shared.toast = nil

        service = WorkoutService(defaults: defaults)
    }

    // MARK: - Failure surfacing (silent write failures once froze program progress)

    func testPartialLibraryDoesNotReplaceUnreadablePreferredProgramWithAnotherPlan() {
        let selected = WorkoutProgram(id: "preferred", userID: "user_123", name: "PHUL", currentProgressIndex: 35)
        let other = WorkoutProgram(id: "other", userID: "user_123", name: "Another plan")
        service.setActiveProgram(selected)
        var receive: ((Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void)?
        mockRepo.onProgramLibraryListenerAdded = { _, callback in receive = callback }
        service.fetchRoutinesAndPrograms()
        receive?(.success(WorkoutLibrarySnapshot(values: [other], unreadableIDs: ["preferred"])))
        XCTAssertNil(service.activeProgram)
        XCTAssertEqual(service.userPrograms.count, 1)
        XCTAssertNotNil(service.loadErrorMessage)
        XCTAssertEqual(defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")), "preferred")
        receive?(.success(WorkoutLibrarySnapshot(values: [other, selected])))
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 35)
        XCTAssertNil(service.loadErrorMessage)
    }

    func testOfflineSubsetDoesNotChangeThePreferredPlanAndLateAccountUpdateIsIgnored() {
        let selected = WorkoutProgram(id: "preferred", userID: "user_123", name: "PHUL")
        let other = WorkoutProgram(id: "other", userID: "user_123", name: "Other")
        service.setActiveProgram(selected)
        var receive: ((Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void)?
        mockRepo.onProgramLibraryListenerAdded = { _, callback in receive = callback }
        service.fetchRoutinesAndPrograms()
        receive?(.success(WorkoutLibrarySnapshot(values: [other], isFromCache: true)))
        XCTAssertNil(service.activeProgram)
        mockAuth.currentUserID = "another-account"
        receive?(.success(WorkoutLibrarySnapshot(values: [selected])))
        XCTAssertNil(service.activeProgram)
        XCTAssertEqual(service.userPrograms.first?.id, "other")
    }

    func testSaveProgramFailureRecordsNonFatalAndToasts() async {
        mockRepo.saveProgramError = NSError(domain: "test", code: 7)
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "P", dateCreated: Date(), routines: [])

        let saved = await service.saveProgram(program)

        XCTAssertNil(saved)
        XCTAssertEqual(mockCrash.recordedErrors.count, 1)
        XCTAssertEqual(mockCrash.recordedErrors.first?.userInfo["operation"] as? String, "save_program")
        XCTAssertNotNil(ToastManager.shared.toast, "A failed program save must be surfaced to the user")
    }

    func testSaveSessionLogFailureRecordsNonFatalAndToasts() async {
        mockRepo.saveWorkoutSessionLogError = NSError(domain: "test", code: 8)
        let log = WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])

        let accepted = await service.saveWorkoutSessionLog(log)
        XCTAssertFalse(accepted, "Completion must remain open when history cannot accept the write")

        XCTAssertEqual(mockCrash.recordedErrors.count, 1)
        XCTAssertEqual(mockCrash.recordedErrors.first?.userInfo["operation"] as? String, "save_workout_session_log")
        XCTAssertNotNil(ToastManager.shared.toast)
    }

    func testSaveProgramSuccessRecordsNoFailure() async {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "P", dateCreated: Date(), routines: [])

        let saved = await service.saveProgram(program)

        XCTAssertNotNil(saved)
        XCTAssertTrue(mockCrash.recordedErrors.isEmpty)
        XCTAssertNil(ToastManager.shared.toast)
    }

    func testStalePreBlockRoutineEditCannotReplaceActiveAuthoredRotation() async throws {
        let routine = WorkoutRoutine(id: "phul-upper", userID: "user_123", name: "Upper", dateCreated: Date(),
            exercises: [RoutineExercise(id: "bench", name: "Bench press", sets: [ExerciseSet(id: "set", target: "8-12")])])
        let legacy = WorkoutProgram(id: "phul", userID: "user_123", name: "PHUL", routines: [routine],
            daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39, skippedIndices: [2, 9, 20])
        var canonical = legacy
        canonical.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: legacy)
        service.userPrograms = [canonical]
        service.activeProgram = canonical
        var stale = legacy
        stale.routines[0] = try XCTUnwrap(routine.deepCopy())
        stale.routines[0].exercises[0].sets[0].target = "1 rep"

        let result = await service.saveProgram(stale)

        XCTAssertNil(result)
        XCTAssertEqual(service.activeProgram?.trainingBlock?.revisionID, canonical.trainingBlock?.revisionID)
        XCTAssertEqual(service.activeProgram?.routines[0].exercises[0].sets[0].target, "8-12")
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 39)
        XCTAssertEqual(service.activeProgram?.skippedIndices, [2, 9, 20])
        XCTAssertEqual(service.userPrograms.count, 1)
        XCTAssertEqual(mockCrash.recordedErrors.count, 1)
        XCTAssertNotNil(ToastManager.shared.toast)
    }

    func testOrdinaryMetadataSaveRetainsCanonicalBlockBeforeListenerRefresh() async throws {
        let routine = WorkoutRoutine(id: "phul-upper", userID: "user_123", name: "Upper", dateCreated: Date(),
            exercises: [RoutineExercise(id: "bench", name: "Bench press", sets: [ExerciseSet(id: "set", target: "8-12")])])
        let legacy = WorkoutProgram(id: "phul", userID: "user_123", name: "PHUL", routines: [routine],
            daysOfWeek: [2, 3, 5, 6], currentProgressIndex: 39, skippedIndices: [2, 9, 20])
        var canonical = legacy
        canonical.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: legacy)
        service.userPrograms = [canonical]
        service.activeProgram = canonical
        var metadataOnly = legacy
        metadataOnly.name = "PHUL gym plan"
        metadataOnly.currentProgressIndex = 40

        let result = await service.saveProgram(metadataOnly)

        XCTAssertEqual(result?.name, "PHUL gym plan")
        XCTAssertEqual(result?.trainingBlock?.revisionID, canonical.trainingBlock?.revisionID)
        XCTAssertEqual(service.activeProgram?.trainingBlock?.revisionID, canonical.trainingBlock?.revisionID)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 40)
        XCTAssertTrue(mockCrash.recordedErrors.isEmpty)
    }

    override func tearDown() {
        service = nil
        mockRepo = nil
        mockAuth = nil
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testFetchWorkoutSessionLogSuccess() async {
        let expectedLog = WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])
        mockRepo.mockFetchSessionLogResult = .success(expectedLog)

        let result = await service.fetchWorkoutSessionLog(workoutID: "w1", sessionID: "s1")
        switch result {
        case .success(let log):
            XCTAssertEqual(log.id, "log1")
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testFetchWorkoutSessionLogError() async {
        struct DummyError: Error {}
        mockRepo.mockFetchSessionLogResult = .failure(DummyError())

        let result = await service.fetchWorkoutSessionLog(workoutID: "w1", sessionID: "s1")
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure:
            XCTAssertTrue(true)
        }
    }

    func testFetchSessionLogsForProgram() async {
        let routine1 = WorkoutRoutine(id: "r1", userID: "user_123", name: "Routine 1", dateCreated: Date(), exercises: [])
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [routine1])
        
        let expectedLogs = [
            WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])
        ]
        // fetchSessionLogs(for:) now pulls by date and keeps logs that belong to the program
        // (here via routine-ID match), so drifted routine IDs can't hide completed workouts.
        mockRepo.mockFetchRecentSessionLogsResult = expectedLogs

        let logs = await service.fetchSessionLogs(for: program)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.id, "log1")
    }

    func testFetchSessionLogsForProgramDropsLogsThatDoNotBelong() async {
        let routine1 = WorkoutRoutine(id: "r1", userID: "user_123", name: "Upper", dateCreated: Date(),
                                      exercises: [RoutineExercise(name: "Bench Press", type: .strength, sets: [])])
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [routine1])

        // One belongs (matching routine ID); one is an unrelated workout with a different ID and
        // no overlapping exercises — it must be filtered out.
        mockRepo.mockFetchRecentSessionLogsResult = [
            WorkoutSessionLog(id: "mine", date: Date(), routineID: "r1", completedExercises: []),
            WorkoutSessionLog(id: "other", date: Date(), routineID: "zzz", completedExercises: [
                CompletedExercise(exerciseName: "Treadmill Run",
                                  exercise: RoutineExercise(name: "Treadmill Run", type: .cardio, sets: []), sets: [])
            ])
        ]

        let logs = await service.fetchSessionLogs(for: program)
        XCTAssertEqual(logs.map(\.id), ["mine"])
    }

    func testFetchRecentSessionLogs() async {
        let expectedLogs = [
            WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])
        ]
        mockRepo.mockFetchRecentSessionLogsResult = expectedLogs

        let logs = await service.fetchRecentSessionLogs(sinceDays: 7)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.id, "log1")
    }

    func testFetchRecentSessionLogsResultPreservesReadFailure() async {
        mockRepo.fetchRecentSessionLogsError = NSError(domain: "test", code: 19)

        let result = await service.fetchRecentSessionLogsResult(sinceDays: 7)

        guard case .failure = result else {
            return XCTFail("Reports must be able to distinguish a failed read from an empty history")
        }
        XCTAssertEqual(mockCrash.recordedErrors.count, 1)
    }

    func testSetActiveProgram() {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        service.setActiveProgram(program)
        
        XCTAssertEqual(service.activeProgram?.id, "p1")
        XCTAssertEqual(
            defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")),
            "p1"
        )
    }

    func testPartialOfflineCacheDoesNotReplacePreferredProgram() {
        let preferred = WorkoutProgram(id: "preferred", userID: "user_123", name: "Preferred")
        let cached = WorkoutProgram(id: "cached", userID: "user_123", name: "Cached")
        service.setActiveProgram(preferred)
        var receive: ((Result<[WorkoutProgram], Error>) -> Void)?
        mockRepo.onProgramsSnapshotListenerAdded = { _, callback in receive = callback }
        service.fetchRoutinesAndPrograms()
        receive?(.success([]))
        receive?(.success([cached]))
        XCTAssertEqual(defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")), "preferred")
        receive?(.success([cached, preferred]))
        XCTAssertEqual(service.activeProgram?.id, "preferred")
    }

    func testRetryingFailedRefreshKeepsTheActiveProgramAndItsProgress() {
        let program = WorkoutProgram(id: "original", userID: "user_123", name: "PHUL", currentProgressIndex: 35)
        var receive: ((Result<[WorkoutProgram], Error>) -> Void)?
        mockRepo.onProgramsSnapshotListenerAdded = { _, callback in receive = callback }
        service.fetchRoutinesAndPrograms()
        receive?(.success([program]))
        service.setActiveProgram(program)
        receive?(.failure(CocoaError(.coderValueNotFound)))

        service.retryPendingSaves()

        XCTAssertEqual(service.activeProgram?.id, "original")
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 35)
        XCTAssertEqual(service.userPrograms.map(\.id), ["original"])
        XCTAssertTrue(service.hasLoadedPrograms)
        XCTAssertTrue(service.isLoadingPrograms)
        receive?(.success([program]))
        XCTAssertFalse(service.isLoadingPrograms)
        XCTAssertNil(service.loadErrorMessage)
    }

    func testFailedInitialProgramReadIsNotPresentedAsAnEmptyLibrary() {
        var receive: ((Result<[WorkoutProgram], Error>) -> Void)?
        mockRepo.onProgramsSnapshotListenerAdded = { _, callback in receive = callback }
        service.fetchRoutinesAndPrograms()
        XCTAssertTrue(service.isLoadingPrograms)
        XCTAssertFalse(service.hasLoadedPrograms)
        receive?(.failure(CocoaError(.coderValueNotFound)))
        XCTAssertFalse(service.isLoadingPrograms)
        XCTAssertFalse(service.hasLoadedPrograms)
        XCTAssertNotNil(service.loadErrorMessage)
        receive?(.success([]))
        XCTAssertTrue(service.hasLoadedPrograms)
        XCTAssertNil(service.loadErrorMessage)
    }

    func testSaveProgram() async {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        mockRepo.mockSaveProgramResult = program
        
        let saved = await service.saveProgram(program)
        XCTAssertEqual(saved?.id, "p1")
    }

    func testSkipToIndex() async {
        let routine1 = WorkoutRoutine(id: "r1", userID: "user_123", name: "Routine 1", dateCreated: Date(), exercises: [])
        let routine2 = WorkoutRoutine(id: "r2", userID: "user_123", name: "Routine 2", dateCreated: Date(), exercises: [])
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [routine1, routine2])
        
        mockRepo.mockSaveProgramResult = program
        let updated = await service.skipToIndex(1, in: program)
        
        XCTAssertNotNil(updated)
    }

    func testClearActiveProgram() {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        service.setActiveProgram(program)
        service.clearActiveProgram()

        XCTAssertNil(service.activeProgram)
        XCTAssertNil(defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")))
        XCTAssertTrue(defaults.bool(forKey: WorkoutService.activeProgramClearedStorageKey(for: "user_123")))
    }

    func testClearedActiveProgramDoesNotAutoRestoreFirstSavedProgram() {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        service.clearActiveProgram()
        mockRepo.onProgramsSnapshotListenerAdded = { _, onUpdate in
            onUpdate(.success([program]))
        }

        service.fetchRoutinesAndPrograms()

        XCTAssertEqual(service.userPrograms.map(\.id), ["p1"])
        XCTAssertNil(service.activeProgram)
    }

    func testActiveProgramPreferenceIsScopedByAccount() {
        let firstProgram = WorkoutProgram(id: "first", userID: "user_123", name: "First", dateCreated: Date(), routines: [])
        service.setActiveProgram(firstProgram)

        mockAuth.currentUserID = "user_456"
        let secondProgram = WorkoutProgram(id: "second", userID: "user_456", name: "Second", dateCreated: Date(), routines: [])
        service.setActiveProgram(secondProgram)

        XCTAssertEqual(
            defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")),
            "first"
        )
        XCTAssertEqual(
            defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_456")),
            "second"
        )
    }

    func testLateSnapshotFromPreviousAccountIsIgnored() {
        var programCallbacks: [String: (Result<[WorkoutProgram], Error>) -> Void] = [:]
        var routineCallbacks: [String: (Result<[WorkoutRoutine], Error>) -> Void] = [:]
        mockRepo.onProgramsSnapshotListenerAdded = { userID, onUpdate in
            programCallbacks[userID] = onUpdate
        }
        mockRepo.onRoutinesSnapshotListenerAdded = { userID, onUpdate in
            routineCallbacks[userID] = onUpdate
        }

        service.fetchRoutinesAndPrograms()
        mockAuth.currentUserID = "user_456"
        service.fetchRoutinesAndPrograms()

        let secondProgram = WorkoutProgram(id: "second", userID: "user_456", name: "Second", dateCreated: Date(), routines: [])
        let secondRoutine = WorkoutRoutine(id: "routine-second", userID: "user_456", name: "Second", dateCreated: Date(), exercises: [])
        programCallbacks["user_456"]?(.success([secondProgram]))
        routineCallbacks["user_456"]?(.success([secondRoutine]))

        let staleProgram = WorkoutProgram(id: "stale", userID: "user_123", name: "Stale", dateCreated: Date(), routines: [])
        let staleRoutine = WorkoutRoutine(id: "routine-stale", userID: "user_123", name: "Stale", dateCreated: Date(), exercises: [])
        programCallbacks["user_123"]?(.success([staleProgram]))
        routineCallbacks["user_123"]?(.success([staleRoutine]))

        XCTAssertEqual(service.userPrograms.map(\.id), ["second"])
        XCTAssertEqual(service.userRoutines.map(\.id), ["routine-second"])
        XCTAssertEqual(service.activeProgram?.id, "second")
    }

    func testSigningOutClearsPresentedWorkoutState() {
        service.userPrograms = [WorkoutProgram(id: "p1", userID: "user_123", name: "P", dateCreated: Date(), routines: [])]
        service.userRoutines = [WorkoutRoutine(id: "r1", userID: "user_123", name: "R", dateCreated: Date(), exercises: [])]
        service.activeProgram = service.userPrograms.first

        mockAuth.currentUserID = nil
        service.fetchRoutinesAndPrograms()

        XCTAssertTrue(service.userPrograms.isEmpty)
        XCTAssertTrue(service.userRoutines.isEmpty)
        XCTAssertNil(service.activeProgram)
    }

    func testLegacyActiveProgramPreferenceMigratesOnlyToCurrentAccount() {
        defaults.set("legacy", forKey: "activeWorkoutProgramID")
        defaults.set(false, forKey: "activeWorkoutProgramCleared")
        let legacyProgram = WorkoutProgram(id: "legacy", userID: "user_123", name: "Legacy", dateCreated: Date(), routines: [])
        mockRepo.onProgramsSnapshotListenerAdded = { _, onUpdate in
            onUpdate(.success([legacyProgram]))
        }

        service.fetchRoutinesAndPrograms()

        XCTAssertEqual(service.activeProgram?.id, "legacy")
        XCTAssertEqual(
            defaults.string(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_123")),
            "legacy"
        )
        XCTAssertNil(defaults.object(forKey: "activeWorkoutProgramID"))
        XCTAssertNil(defaults.object(forKey: "activeWorkoutProgramCleared"))
        XCTAssertNil(defaults.object(forKey: WorkoutService.activeProgramIDStorageKey(for: "user_456")))
    }

    func testSkipCurrentWorkout() async {
        let routine1 = WorkoutRoutine(id: "r1", userID: "user_123", name: "Routine 1", dateCreated: Date(), exercises: [])
        let routine2 = WorkoutRoutine(id: "r2", userID: "user_123", name: "Routine 2", dateCreated: Date(), exercises: [])
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [routine1, routine2])
        
        mockRepo.mockSaveProgramResult = program
        let updated = await service.skipCurrentWorkout(in: program)
        XCTAssertNotNil(updated)
    }

    func testDeleteProgram() async {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        let otherProgram = WorkoutProgram(id: "p2", userID: "user_123", name: "Program 2", dateCreated: Date(), routines: [])
        service.userPrograms = [program, otherProgram]
        service.setActiveProgram(program)
        let result = await service.deleteProgram(program)
        
        XCTAssertEqual(result, .deleted)
        XCTAssertNil(service.activeProgram)
        XCTAssertEqual(service.userPrograms.map(\.id), ["p2"])
        XCTAssertTrue(mockRepo.deletedProgramIDs.contains("p1"))
    }

    func testDeleteProgramResolvesStaleActiveProgramByName() async {
        let savedProgram = WorkoutProgram(id: "saved_id", userID: "user_123", name: "PHAT", dateCreated: Date(), routines: [])
        let staleProgram = WorkoutProgram(id: nil, userID: "user_123", name: "PHAT", dateCreated: savedProgram.dateCreated, routines: [])
        service.userPrograms = [savedProgram]
        service.activeProgram = staleProgram

        let result = await service.deleteProgram(staleProgram)

        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(mockRepo.deletedProgramIDs, ["saved_id"])
        XCTAssertNil(service.activeProgram)
        XCTAssertTrue(service.userPrograms.isEmpty)
    }

    func testDeleteProgramWithoutSavedRecordClearsStaleActiveProgramLocally() async {
        let staleProgram = WorkoutProgram(id: nil, userID: "user_123", name: "PHAT", dateCreated: Date(), routines: [])
        service.activeProgram = staleProgram
        service.userPrograms = []

        let result = await service.deleteProgram(staleProgram)

        XCTAssertEqual(result, .clearedLocalOnly)
        XCTAssertTrue(mockRepo.deletedProgramIDs.isEmpty)
        XCTAssertNil(service.activeProgram)
        XCTAssertTrue(defaults.bool(forKey: WorkoutService.activeProgramClearedStorageKey(for: "user_123")))
    }

    func testDeleteProgramReportsRepositoryFailureAndKeepsLocalState() async {
        struct DeleteFailure: LocalizedError {
            var errorDescription: String? { "permission denied" }
        }
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        service.userPrograms = [program]
        service.setActiveProgram(program)
        mockRepo.deleteProgramError = DeleteFailure()

        let result = await service.deleteProgram(program)

        XCTAssertEqual(result, .failed("permission denied"))
        XCTAssertEqual(service.activeProgram?.id, "p1")
        XCTAssertEqual(service.userPrograms.map(\.id), ["p1"])
    }

    func testSaveRoutine() async throws {
        let routine = WorkoutRoutine(id: "r1", userID: "user_123", name: "Routine 1", dateCreated: Date(), exercises: [])
        try await service.saveRoutine(routine)
        XCTAssertTrue(mockRepo.savedRoutines.contains(where: { $0.id == "r1" }))
    }

    func testDeleteRoutine() async {
        let routine = WorkoutRoutine(id: "r1", userID: "user_123", name: "Routine 1", dateCreated: Date(), exercises: [])
        service.deleteRoutine(routine)
        
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(mockRepo.deletedRoutineIDs.contains("r1"))
    }

    func testSaveWorkoutSessionLog() async {
        let log = WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])
        await service.saveWorkoutSessionLog(log)
        XCTAssertTrue(mockRepo.savedSessionLogs.contains(where: { $0.id == "log1" }))
    }

    func testFetchHistory() async {
        let log = WorkoutSessionLog(id: "log1", date: Date(), routineID: "r1", completedExercises: [])
        mockRepo.mockFetchHistoryResult = [log]
        
        let history = await service.fetchHistory(for: "Squat")
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, "log1")
    }

    func testFetchPreviousPerformance() async {
        let routineExercise = RoutineExercise(id: "re1", name: "Squat", type: .strength, sets: [])
        let exercise = CompletedExercise(id: "ce1", exerciseName: "Squat", exercise: routineExercise, sets: [])
        mockRepo.mockFetchPreviousPerformanceResult = exercise
        
        let prev = await service.fetchPreviousPerformance(for: "Squat")
        XCTAssertEqual(prev?.id, "ce1")
    }

    func testFetchRoutinesAndProgramsAndDetach() {
        let p1 = WorkoutProgram(id: "p1", userID: "user_123", name: "P1", dateCreated: Date(), routines: [])
        let r1 = WorkoutRoutine(id: "r1", userID: "user_123", name: "R1", dateCreated: Date(), exercises: [])

        var pCallback: ((Result<[WorkoutProgram], Error>) -> Void)?
        mockRepo.onProgramsSnapshotListenerAdded = { _, onUpdate in
            pCallback = onUpdate
        }
        
        var rCallback: ((Result<[WorkoutRoutine], Error>) -> Void)?
        mockRepo.onRoutinesSnapshotListenerAdded = { _, onUpdate in
            rCallback = onUpdate
        }
        
        service.fetchRoutinesAndPrograms()
        
        pCallback?(.success([p1]))
        rCallback?(.success([r1]))
        
        XCTAssertEqual(service.userPrograms.count, 1)
        XCTAssertEqual(service.userPrograms.first?.id, "p1")
        XCTAssertEqual(service.userRoutines.count, 1)
        XCTAssertEqual(service.userRoutines.first?.id, "r1")
        
        service.detachListener()
        XCTAssertEqual(mockRepo.removeListenerCalledCount, 2)
    }

    func testSelectPreBuiltProgram() async {
        let p1 = WorkoutProgram(id: "p1", userID: "prebuilt", name: "P1", dateCreated: Date(), routines: [])
        let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_799_712_000))
        
        let selected = await service.selectPreBuiltProgram(p1, startDate: startDate)
        XCTAssertNotNil(selected)
        XCTAssertEqual(service.activeProgram?.id, selected?.id)
        XCTAssertEqual(selected?.startDate, startDate)
    }

    func testGenerateAIWorkoutPlanSuccess() async {
        let mockAI = MockAIService()
        let jsonResponse = """
        {
            "schemaVersion": 2,
            "programName": "AI Plan",
            "routines": [
                {
                    "name": "Day 1",
                    "exercises": [
                        {
                            "name": "Bodyweight Squat",
                            "movementID": "mfp.exercise.bodyweight-squat",
                            "variantID": "standard-v1",
                            "restSeconds": 60,
                            "progressionPolicy": {"version": 1, "kind": "bodyweight", "incrementPounds": 5},
                            "type": "Strength",
                            "sets": [{"target": "10", "prescription": {"schemaVersion": 1, "kind": "repetitions", "lowerBound": 10}}],
                            "alternatives": []
                        }
                    ]
                }
            ]
        }
        """
        mockAI.mockResult = .success(jsonResponse)
        DIContainer.shared.aiService = mockAI
        
        let goalSettings = GoalSettings()
        goalSettings.gender = "Male"
        goalSettings.height = 180
        goalSettings.weight = 80
        goalSettings.goal = "Maintain Weight"
        goalSettings.activityLevel = 1.55
        
        let result = await service.generateAIWorkoutPlan(
            goal: "muscle",
            daysPerWeek: 3,
            fitnessLevel: "beginner",
            equipment: "gym",
            details: "No details",
            goalSettings: goalSettings
        )
        
        switch result {
        case .success(let program):
            XCTAssertEqual(program.name, "AI Plan")
            XCTAssertEqual(program.routines.count, 1)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testGenerateAIWorkoutPlanDecodingError() async {
        let mockAI = MockAIService()
        mockAI.mockResult = .success("invalid json")
        DIContainer.shared.aiService = mockAI
        
        let goalSettings = GoalSettings()
        goalSettings.gender = "Male"
        goalSettings.height = 180
        goalSettings.weight = 80
        goalSettings.goal = "Maintain Weight"
        goalSettings.activityLevel = 1.55
        
        let result = await service.generateAIWorkoutPlan(
            goal: "muscle",
            daysPerWeek: 3,
            fitnessLevel: "beginner",
            equipment: "gym",
            details: "No details",
            goalSettings: goalSettings
        )
        
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .decodingError = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected decoding error")
            }
        }
    }

    // MARK: - Exact program/slot completion acknowledgment

    private func completionProgram() -> WorkoutProgram {
        let routine = WorkoutRoutine(id: "bound-routine", userID: "user_123", name: "Upper",
                                     dateCreated: Date(timeIntervalSince1970: 1_700_000_000))
        return WorkoutProgram(id: "bound-program", userID: "user_123", name: "PHUL",
                              dateCreated: routine.dateCreated, routines: [routine], daysOfWeek: [2],
                              currentProgressIndex: 0)
    }

    private func boundCompletion(slot: Int = 0, programID: String = "bound-program") -> WorkoutSessionLog {
        WorkoutSessionLog(id: "bound-session-\(slot)", date: Date(), routineID: "bound-routine", completedExercises: [],
                          programContext: WorkoutProgramSessionContext(programID: programID, slotIndex: slot))
    }

    func testProgramCompletionRetryAdvancesCapturedSlotOnlyOnce() async {
        let program = completionProgram()
        service.userPrograms = [program]
        service.setActiveProgram(program)
        let completion = boundCompletion()
        mockRepo.mockFetchRecentSessionLogsResult = [completion, completion]
        let accepted = await service.recordProgramCompletion(completion)
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 1)
        let replayed = await service.recordProgramCompletion(completion)
        XCTAssertTrue(replayed)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 1)
    }

    func testEarlyCompletionAcknowledgesHistoryWithoutSkippingCurrentSlot() async {
        let program = completionProgram()
        service.userPrograms = [program]
        service.setActiveProgram(program)
        let early = boundCompletion(slot: 2)
        mockRepo.mockFetchRecentSessionLogsResult = [early]
        let accepted = await service.recordProgramCompletion(early)
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 0)
    }

    func testProgramSaveFailureRetainsProgressForCompletionRetry() async {
        let program = completionProgram()
        service.userPrograms = [program]
        service.setActiveProgram(program)
        mockRepo.saveProgramError = NSError(domain: "save", code: 1)
        let completion = boundCompletion()
        let failed = await service.recordProgramCompletion(completion)
        XCTAssertFalse(failed)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 0)
        mockRepo.saveProgramError = nil
        let retried = await service.recordProgramCompletion(completion)
        XCTAssertTrue(retried)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 1)
    }

    func testHistoryFailureCannotGuessProgressFromOnlyLatestCompletion() async {
        let program = completionProgram()
        service.userPrograms = [program]
        service.setActiveProgram(program)
        mockRepo.fetchRecentSessionLogsError = NSError(domain: "read", code: 1)
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertFalse(accepted)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 0)
    }

    func testCapturedProgramCompletionCannotAdvanceAnotherActiveProgram() async {
        let original = completionProgram()
        var other = original
        other.id = "other-program"
        other.currentProgressIndex = 7
        service.userPrograms = [original, other]
        service.setActiveProgram(other)
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.userPrograms.first { $0.id == original.id }?.currentProgressIndex, 1)
        XCTAssertEqual(service.activeProgram?.id, other.id)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 7)
    }

    func testUnknownProgramCompletionWaitsForLibraryInsteadOfAssumingDeletion() async {
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertFalse(accepted)
        XCTAssertNil(service.activeProgram)
    }

    func testMissingProgramInCachedSubsetCannotClearCompletionRecovery() async {
        mockRepo.onProgramLibraryListenerAdded = { _, receive in
            receive(.success(WorkoutLibrarySnapshot(values: [], isFromCache: true)))
        }
        service.fetchRoutinesAndPrograms()
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertFalse(accepted)
    }

    func testConfirmedDeletedProgramDoesNotTrapSavedWorkout() async {
        mockRepo.onProgramLibraryListenerAdded = { _, receive in
            receive(.success(WorkoutLibrarySnapshot(values: [], isFromCache: false)))
        }
        service.fetchRoutinesAndPrograms()
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertTrue(accepted)
    }

    func testKnownForeignProgramIsNotMistakenForDeletedProgram() async {
        mockRepo.onProgramLibraryListenerAdded = { _, receive in
            receive(.success(WorkoutLibrarySnapshot(values: [], isFromCache: false)))
        }
        service.fetchRoutinesAndPrograms()
        var foreign = completionProgram()
        foreign.userID = "another-account"
        service.userPrograms = [foreign]
        let accepted = await service.recordProgramCompletion(boundCompletion())
        XCTAssertFalse(accepted)
        XCTAssertEqual(service.userPrograms.first?.currentProgressIndex, 0)
    }

    func testLifetimeHistoryWindowIncludesEarlierReceiptsAfterReschedule() {
        var program = completionProgram()
        program.dateCreated = Calendar.current.date(byAdding: .day, value: -600, to: Date())!
        program.startDate = Date()
        XCTAssertGreaterThanOrEqual(WorkoutService.sessionLogWindowDays(for: program), 613)
        program.startDate = nil
        XCTAssertGreaterThanOrEqual(WorkoutService.sessionLogWindowDays(for: program), 613)
    }

    func testLegacyCompletionDoesNotInventCurrentProgramContext() async {
        let program = completionProgram()
        service.userPrograms = [program]
        service.setActiveProgram(program)
        let unassigned = WorkoutSessionLog(id: "legacy", date: Date(), routineID: "bound-routine", completedExercises: [])
        let accepted = await service.recordProgramCompletion(unassigned)
        XCTAssertTrue(accepted)
        XCTAssertEqual(service.activeProgram?.currentProgressIndex, 0)
    }

    func testWorkoutServiceErrorDescriptions() {
        XCTAssertEqual(WorkoutServiceError.userNotLoggedIn.errorDescription, "You must be logged in to perform this action.")
        struct DummyError: Error {}
        XCTAssertEqual(WorkoutServiceError.networkError(DummyError()).errorDescription, "Could not connect to the server. Please check your internet connection.")
        XCTAssertEqual(WorkoutServiceError.decodingError(DummyError()).errorDescription, "There was an issue processing the response from the server.")
        XCTAssertEqual(WorkoutServiceError.apiError("Some error").errorDescription, "Some error")
    }
}
