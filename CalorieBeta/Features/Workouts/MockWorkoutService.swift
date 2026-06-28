import Foundation

@MainActor
class MockWorkoutService: WorkoutServicing {
    var userRoutines: [WorkoutRoutine] = []
    var userPrograms: [WorkoutProgram] = []
    var preBuiltPrograms: [WorkoutProgram] = []
    var activeProgram: WorkoutProgram? = nil
    
    func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error> {
        return .failure(NSError(domain: "MockError", code: 404, userInfo: nil))
    }
    
    func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog] {
        return []
    }
    
    func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog] {
        return []
    }
    
    func fetchRoutinesAndPrograms() {
        // Mock implementation
    }
    
    func setActiveProgram(_ program: WorkoutProgram) {
        self.activeProgram = program
    }
    
    @discardableResult
    func saveProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    @discardableResult
    func skipToIndex(_ targetIndex: Int, in program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    @discardableResult
    func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
    
    func deleteProgram(_ program: WorkoutProgram) {
        // Mock implementation
    }
    
    func saveRoutine(_ routine: WorkoutRoutine) async throws {
        // Mock implementation
    }
    
    func deleteRoutine(_ routine: WorkoutRoutine) {
        // Mock implementation
    }
    
    func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        // Mock implementation
    }
    
    func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        return []
    }
    
    func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        return nil
    }
    
    func selectPreBuiltProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        return program
    }
}
