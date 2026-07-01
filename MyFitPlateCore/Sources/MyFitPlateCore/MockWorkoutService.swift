import Foundation

@MainActor
public class MockWorkoutService: WorkoutServicing {
    public var userRoutines: [WorkoutRoutine] = []
    public var userPrograms: [WorkoutProgram] = []
    public var preBuiltPrograms: [WorkoutProgram] = []
    public var activeProgram: WorkoutProgram? = nil
    
    public func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error> {
        return .failure(NSError(domain: "MockError", code: 404, userInfo: nil))
    }
    
    public func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog] {
        return []
    }
    
    public func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog] {
        return []
    }
    
    public func fetchRoutinesAndPrograms() {
        // Mock implementation
    }
    
    public func setActiveProgram(_ program: WorkoutProgram) {
        self.activeProgram = program
    }

    public func clearActiveProgram() {
        self.activeProgram = nil
    }
    
    @discardableResult
    public func saveProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    @discardableResult
    public func skipToIndex(_ targetIndex: Int, in program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    @discardableResult
    public func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    @discardableResult
    public func deleteProgram(_ program: WorkoutProgram) async -> ProgramDeletionResult {
        activeProgram = nil
        userPrograms.removeAll { $0.id == program.id }
        return .deleted
    }
    
    public func saveRoutine(_ routine: WorkoutRoutine) async throws {
        // Mock implementation
    }
    
    public func deleteRoutine(_ routine: WorkoutRoutine) {
        // Mock implementation
    }
    
    public func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        // Mock implementation
    }
    
    public func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        return []
    }
    
    public func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        return nil
    }
    
    public func selectPreBuiltProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
}
