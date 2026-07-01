import Foundation

@MainActor
public protocol WorkoutServicing: AnyObject {
    var userRoutines: [WorkoutRoutine] { get set }
    var userPrograms: [WorkoutProgram] { get set }
    var preBuiltPrograms: [WorkoutProgram] { get set }
    var activeProgram: WorkoutProgram? { get set }
    
    func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error>
    func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog]
    func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog]
    
    func fetchRoutinesAndPrograms()
    func setActiveProgram(_ program: WorkoutProgram)
    func clearActiveProgram()
    
    @discardableResult
    func saveProgram(_ program: WorkoutProgram) async -> WorkoutProgram?
    
    @discardableResult
    func skipToIndex(_ targetIndex: Int, in program: WorkoutProgram) async -> WorkoutProgram?
    
    @discardableResult
    func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram?
    
    @discardableResult
    func deleteProgram(_ program: WorkoutProgram) async -> ProgramDeletionResult
    
    func saveRoutine(_ routine: WorkoutRoutine) async throws
    func deleteRoutine(_ routine: WorkoutRoutine)
    
    func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async
    
    func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog]
    func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise?
    
    func selectPreBuiltProgram(_ program: WorkoutProgram) async -> WorkoutProgram?
}
