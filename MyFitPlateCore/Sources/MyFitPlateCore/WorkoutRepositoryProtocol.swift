import Foundation

public protocol WorkoutRepositoryProtocol: Sendable {
    func workoutSyncState(userID: String) -> WorkoutSyncState
    func retryPendingWorkouts(userID: String)
    func discardPendingWorkouts(userID: String) throws
    func fetchWorkoutSessionLog(userID: String, sessionID: String) async throws -> WorkoutSessionLog
    func fetchSessionLogs(userID: String, routineIDs: [String]) async throws -> [WorkoutSessionLog]
    func fetchRecentSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog]
    func fetchExportSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog]

    func addProgramsSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutProgram], Error>) -> Void) -> Any
    func addRoutinesSnapshotListener(userID: String, onUpdate: @escaping (Result<[WorkoutRoutine], Error>) -> Void) -> Any
    func addProgramLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void) -> Any
    func addRoutineLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutRoutine>, Error>) -> Void) -> Any
    func removeListener(_ handle: Any)

    func saveProgram(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram
    func enqueueProgramProgress(userID: String, command: WorkoutProgramProgressCommand, locallyVerifiedLogs: [WorkoutSessionLog]) async throws -> WorkoutProgram
    func pendingProgramProgress(userID: String, programID: String) throws -> [WorkoutProgramProgressCommand]
    func resolveProgramProgress(userID: String, command: WorkoutProgramProgressCommand, cancelPending: Bool) async throws -> WorkoutProgramProgressResolution
    func commitProgramEdit(userID: String, command: WorkoutProgramEditCommand) async throws -> WorkoutProgram?
    func resolveProgramEdit(userID: String, command: WorkoutProgramEditCommand, cancelPending: Bool) async throws -> WorkoutProgramEditResolution
    func saveProgramArchive(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram
    func commitProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock, protectedSlots: Set<Int>) async throws -> WorkoutProgram?
    func resolveProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock, cancelPending: Bool) async throws -> WorkoutBlockResolution?
    func fetchLegacyMigrations(userID: String, programID: String) async throws -> [WorkoutLegacyMigrationRecord]
    func commitMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, protectedSlots: Set<Int>) async throws -> WorkoutProgram?
    func resolveMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, cancelPending: Bool) async throws -> WorkoutMigrationRollbackResolution
    func createProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand) async throws -> WorkoutProgram?
    func resolveProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand, cancelPending: Bool) async throws -> WorkoutProgramSuccessorResolution
    func deleteProgram(userID: String, programID: String) async throws

    func saveRoutine(userID: String, routine: WorkoutRoutine) async throws
    func deleteRoutine(userID: String, routineID: String) async throws

    func saveWorkoutSessionLog(userID: String, log: WorkoutSessionLog) async throws
    func commitWorkoutCorrection(userID: String, expected: WorkoutSessionLog, updated: WorkoutSessionLog) async throws
    func fetchHistory(userID: String, exerciseName: String) async throws -> [WorkoutSessionLog]
    func fetchPreviousPerformance(userID: String, exerciseName: String) async throws -> CompletedExercise?

    // Analytics
    func saveWorkoutInsights(userID: String, sessionID: String, insights: [[String: Any]]) async throws
    func fetchWorkoutHistory(userID: String, limit: Int) async throws -> [WorkoutSessionLog]
    func fetchWorkoutHistoryPage(userID: String, cursor: WorkoutHistoryCursor?, pageSize: Int) async throws -> WorkoutHistoryPage
    func fetchWorkoutHistory(userID: String, routineID: String, limit: Int) async throws -> [WorkoutSessionLog]
}

public extension WorkoutRepositoryProtocol {
    func fetchLegacyMigrations(userID: String, programID: String) async throws -> [WorkoutLegacyMigrationRecord] { throw WorkoutMigrationError.unavailable }
    func commitMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, protectedSlots: Set<Int>) async throws -> WorkoutProgram? { throw WorkoutMigrationError.unavailable }
    func resolveMigrationRollback(userID: String, command: WorkoutMigrationRollbackCommand, cancelPending: Bool) async throws -> WorkoutMigrationRollbackResolution { throw WorkoutMigrationError.unavailable }
    func enqueueProgramProgress(userID: String, command: WorkoutProgramProgressCommand, locallyVerifiedLogs: [WorkoutSessionLog]) async throws -> WorkoutProgram { throw WorkoutBlockError.unavailable }
    func pendingProgramProgress(userID: String, programID: String) throws -> [WorkoutProgramProgressCommand] { [] }
    func resolveProgramProgress(userID: String, command: WorkoutProgramProgressCommand, cancelPending: Bool) async throws -> WorkoutProgramProgressResolution { throw WorkoutBlockError.unavailable }

    func commitProgramEdit(userID: String, command: WorkoutProgramEditCommand) async throws -> WorkoutProgram? { throw WorkoutBlockError.unavailable }
    func resolveProgramEdit(userID: String, command: WorkoutProgramEditCommand, cancelPending: Bool) async throws -> WorkoutProgramEditResolution { throw WorkoutBlockError.unavailable }

    func saveProgramArchive(userID: String, program: WorkoutProgram) async throws -> WorkoutProgram {
        throw WorkoutLibraryEditError.changed
    }
    func createProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand) async throws -> WorkoutProgram? {
        throw WorkoutSuccessorError.unavailable
    }
    func resolveProgramSuccessor(userID: String, command: WorkoutProgramSuccessorCommand, cancelPending: Bool) async throws -> WorkoutProgramSuccessorResolution {
        throw WorkoutSuccessorError.unavailable
    }
    func commitProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock, protectedSlots: Set<Int>) async throws -> WorkoutProgram? {
        throw WorkoutBlockError.unavailable
    }
    func resolveProgramBlock(userID: String, expected: WorkoutProgram, block: WorkoutProgramBlock, cancelPending: Bool) async throws -> WorkoutBlockResolution? {
        throw WorkoutBlockError.unavailable
    }
    func commitWorkoutCorrection(userID: String, expected: WorkoutSessionLog, updated: WorkoutSessionLog) async throws {
        throw WorkoutCorrectionError.historyUnavailable
    }
    func fetchExportSessionLogs(userID: String, sinceDays: Int) async throws -> [WorkoutSessionLog] {
        try await fetchRecentSessionLogs(userID: userID, sinceDays: sinceDays)
    }
    func addProgramLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutProgram>, Error>) -> Void) -> Any {
        addProgramsSnapshotListener(userID: userID) { onUpdate($0.map { WorkoutLibrarySnapshot(values: $0) }) }
    }
    func addRoutineLibraryListener(userID: String, onUpdate: @escaping (Result<WorkoutLibrarySnapshot<WorkoutRoutine>, Error>) -> Void) -> Any {
        addRoutinesSnapshotListener(userID: userID) { onUpdate($0.map { WorkoutLibrarySnapshot(values: $0) }) }
    }
    func workoutSyncState(userID: String) -> WorkoutSyncState { .synced }
    func retryPendingWorkouts(userID: String) {}
    func discardPendingWorkouts(userID: String) throws {}
}
