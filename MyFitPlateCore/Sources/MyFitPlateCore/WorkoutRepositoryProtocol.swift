import Foundation

public protocol WorkoutRepositoryProtocol: Sendable {
    func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog
    func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog]
    func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog]
    
    func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any
    func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any
    func removeListener(_ handle: Any)
    
    func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram
    func deleteProgram(userID: String, programID: String) async throws
    
    func saveRoutine(userID: String, routine: WorkoutRoutine) async throws
    func deleteRoutine(userID: String, routineID: String) async throws
    
    func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws
    func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog]
    func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise?
    
    // Analytics
    func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws
    func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog]
    func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog]
}
