import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutServiceTests: XCTestCase {
    var service: WorkoutService!
    var mockRepo: MockWorkoutRepository!
    var mockCrash: MockCrashManager!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "activeWorkoutProgramID")
        UserDefaults.standard.removeObject(forKey: "activeWorkoutProgramCleared")
        mockRepo = MockWorkoutRepository()
        DIContainer.shared.workoutRepository = mockRepo
        let mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        DIContainer.shared.authService = mockAuth
        mockCrash = MockCrashManager()
        DIContainer.shared.crashManager = mockCrash
        ToastManager.shared.toast = nil

        service = WorkoutService()
    }

    // MARK: - Failure surfacing (silent write failures once froze program progress)

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

        await service.saveWorkoutSessionLog(log)

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

    override func tearDown() {
        service = nil
        mockRepo = nil
        UserDefaults.standard.removeObject(forKey: "activeWorkoutProgramID")
        UserDefaults.standard.removeObject(forKey: "activeWorkoutProgramCleared")
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

    func testSetActiveProgram() {
        let program = WorkoutProgram(id: "p1", userID: "user_123", name: "Program 1", dateCreated: Date(), routines: [])
        service.setActiveProgram(program)
        
        XCTAssertEqual(service.activeProgram?.id, "p1")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "activeWorkoutProgramID"), "p1")
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
        XCTAssertNil(UserDefaults.standard.string(forKey: "activeWorkoutProgramID"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "activeWorkoutProgramCleared"))
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
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "activeWorkoutProgramCleared"))
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
        mockRepo.onProgramsSnapshotListenerAdded = { userID, onUpdate in
            pCallback = onUpdate
        }
        
        var rCallback: ((Result<[WorkoutRoutine], Error>) -> Void)?
        mockRepo.onRoutinesSnapshotListenerAdded = { userID, onUpdate in
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
        mockRepo.mockSaveProgramResult = p1
        
        let selected = await service.selectPreBuiltProgram(p1)
        XCTAssertNotNil(selected)
        XCTAssertEqual(service.activeProgram?.id, selected?.id)
    }

    func testGenerateAIWorkoutPlanSuccess() async {
        let mockAI = MockAIService()
        let jsonResponse = """
        {
            "programName": "AI Plan",
            "routines": [
                {
                    "name": "Day 1",
                    "exercises": [
                        {
                            "name": "Squat",
                            "type": "Strength",
                            "sets": [{"target": "10"}],
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

    func testWorkoutServiceErrorDescriptions() {
        XCTAssertEqual(WorkoutServiceError.userNotLoggedIn.errorDescription, "You must be logged in to perform this action.")
        struct DummyError: Error {}
        XCTAssertEqual(WorkoutServiceError.networkError(DummyError()).errorDescription, "Could not connect to the server. Please check your internet connection.")
        XCTAssertEqual(WorkoutServiceError.decodingError(DummyError()).errorDescription, "There was an issue processing the response from the server.")
        XCTAssertEqual(WorkoutServiceError.apiError("Some error").errorDescription, "Some error")
    }
}
