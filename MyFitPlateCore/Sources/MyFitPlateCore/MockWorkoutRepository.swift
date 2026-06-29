import Foundation
import Combine

public final class MockWorkoutRepository: WorkoutRepositoryProtocol {
    public init() {}
    public func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog { fatalError() }
    public func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog] { return [] }
    public func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] { return [] }
    public func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any { return UUID() }
    public func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any { return UUID() }
    public func removeListener(_ handle: Any) {}
    public func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram { return program }
    public func deleteProgram(userID: String, programID: String) async throws {}
    public func saveRoutine(userID: String, routine: WorkoutRoutine) async throws {}
    public func deleteRoutine(userID: String, routineID: String) async throws {}
    public func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws {}
    public func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog] { return [] }
    public func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise? { return nil }
    public func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws {}
    public func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog] { return [] }
    public func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog] { return [] }
}
