#if DEBUG
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
    
    public private(set) var reconcileProgramProgressCallCount = 0
    public func reconcileProgramProgress(in program: WorkoutProgram, knownLogs: [WorkoutSessionLog]) async -> WorkoutProgram? {
        reconcileProgramProgressCallCount += 1
        let latest = userPrograms.first { $0.id == program.id } ?? (activeProgram?.id == program.id ? activeProgram : nil) ?? program
        let linked = WorkoutRules.sessionLogsBySlot(in: latest, sessionLogs: knownLogs)
        guard let sessionID = linked[max(latest.currentProgressIndex ?? 0, 0)]?.id else { return latest }
        do {
            let command = try WorkoutProgramProgressCommand(program: latest, kind: .completion, sessionID: sessionID,
                proofSessionIDs: linked.values.compactMap(\.id))
            let result = try command.applying(to: latest, verifiedLogs: Array(linked.values))
            if activeProgram?.id == result.id { activeProgram = result }
            if let index = userPrograms.firstIndex(where: { $0.id == result.id }) { userPrograms[index] = result }
            return result
        } catch { return nil }
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
    
    @discardableResult
    public func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async -> Bool {
        return true
        // Mock implementation
    }
    
    public func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        return []
    }
    
    public func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        return nil
    }
    
    public func selectPreBuiltProgram(_ program: WorkoutProgram, startDate: Date) async -> WorkoutProgram? {
        var selectedProgram = program
        selectedProgram.startDate = startDate
        return selectedProgram
    }
}
#endif
