import Foundation
import Combine

public final class MockWorkoutRepository: WorkoutRepositoryProtocol, @unchecked Sendable {
    public var mockFetchSessionLogResult: Result<WorkoutSessionLog, Error>?
    public var mockFetchSessionLogsResult: [WorkoutSessionLog] = []
    public var mockFetchRecentSessionLogsResult: [WorkoutSessionLog] = []
    public var mockSaveProgramResult: WorkoutProgram?
    public var savedRoutines: [WorkoutRoutine] = []
    public var savedSessionLogs: [WorkoutSessionLog] = []
    public var savedInsights: [[String: Any]] = []

    public var mockFetchHistoryResult: [WorkoutSessionLog] = []
    public var mockFetchPreviousPerformanceResult: CompletedExercise?

    public init() {}
    public func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog {
        if let result = mockFetchSessionLogResult {
            switch result {
            case .success(let log): return log
            case .failure(let error): throw error
            }
        }
        fatalError("No mock result set")
    }
    public func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog] { return mockFetchSessionLogsResult }
    public func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] { return mockFetchRecentSessionLogsResult }
    public var onProgramsSnapshotListenerAdded: ((String, @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Void)?
    public func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any {
        onProgramsSnapshotListenerAdded?(userID, onUpdate)
        return UUID()
    }
    public var onRoutinesSnapshotListenerAdded: ((String, @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Void)?
    public func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any {
        onRoutinesSnapshotListenerAdded?(userID, onUpdate)
        return UUID()
    }
    public var removeListenerCalledCount = 0
    public func removeListener(_ handle: Any) {
        removeListenerCalledCount += 1
    }
    public func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram { return mockSaveProgramResult ?? program }
    
    public var deletedProgramIDs: [String] = []
    public func deleteProgram(userID: String, programID: String) async throws {
        deletedProgramIDs.append(programID)
    }
    
    public func saveRoutine(userID: String, routine: WorkoutRoutine) async throws {
        savedRoutines.append(routine)
    }
    
    public var deletedRoutineIDs: [String] = []
    public func deleteRoutine(userID: String, routineID: String) async throws {
        deletedRoutineIDs.append(routineID)
    }
    
    public func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws {
        savedSessionLogs.append(log)
    }
    public func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
    public func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise? { return mockFetchPreviousPerformanceResult }
    public func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws {
        savedInsights = insights
    }
    public func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
    public func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog] { return mockFetchHistoryResult }
}
