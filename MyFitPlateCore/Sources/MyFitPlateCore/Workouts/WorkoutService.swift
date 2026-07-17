import CryptoKit
import Foundation
public enum WorkoutServiceError: Error, LocalizedError {
    case userNotLoggedIn
    case networkError(Error)
    case firestoreError(Error)
    case decodingError(Error)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .userNotLoggedIn:
            return "You must be logged in to perform this action."
        case .networkError:
            return "Could not connect to the server. Please check your internet connection."
        case .firestoreError(let error):
            return "An error occurred with the database: \(error.localizedDescription)"
        case .decodingError:
            return "There was an issue processing the response from the server."
        case .apiError(let message):
            return message
        }
    }
}

public enum ProgramDeletionResult: Equatable {
    case deleted
    case clearedLocalOnly
    case userNotLoggedIn
    case missingProgramID
    case failed(String)

    public var didDelete: Bool {
        self == .deleted || self == .clearedLocalOnly
    }

    public var userMessage: String {
        switch self {
        case .deleted:
            return "Program deleted. Workout history was kept."
        case .clearedLocalOnly:
            return "Cleared the stuck active program. No saved cloud program was found to delete."
        case .userNotLoggedIn:
            return "Could not delete the program because you are not signed in."
        case .missingProgramID:
            return "Could not find the saved program record to delete."
        case .failed(let message):
            return "Could not delete the program: \(message)"
        }
    }
}

@MainActor
public class WorkoutService: ObservableObject, WorkoutServicing {
    @Published public var userRoutines: [WorkoutRoutine] = []
    @Published public var userPrograms: [WorkoutProgram] = []
    @Published public var preBuiltPrograms: [WorkoutProgram] = []
    @Published public var activeProgram: WorkoutProgram? {
        didSet {
            // // AnalyticsManager.setUserProperty(activeProgram != nil ? "true" : "false", for: .hasActiveProgram)
        }
    }

    private var routineListener: Any?
    private var programListener: Any?
    private var listenerUserID: String?
    private let defaults: UserDefaults
    private static let legacyActiveProgramIDKey = "activeWorkoutProgramID"
    private static let legacyActiveProgramClearedKey = "activeWorkoutProgramCleared"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPreBuiltPrograms()
    }

    // MARK: - Failure reporting

    /// Every data-layer failure in this service used to vanish into os.log only — a silently
    /// failing program write once froze progression for weeks with zero telemetry (v2.1).
    /// This funnel records a Crashlytics non-fatal for every failure, and tells the user via
    /// the global toast when the loss is theirs (an unsaved workout or program change).
    private func reportFailure(_ error: Error, operation: String, userMessage: String? = nil) {
        AppLog.workouts.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        DIContainer.shared.crashManager?.record(error: error, additionalUserInfo: ["operation": operation])
        if let userMessage {
            ToastManager.shared.showToast(message: userMessage)
        }
    }

    // MARK: - Fetching & Saving
    
    public func fetchWorkoutSessionLog(workoutID: String, sessionID: String) async -> Result<WorkoutSessionLog, Error> {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .failure(WorkoutServiceError.userNotLoggedIn)
        }
        do {
            let sessionLog = try await DIContainer.shared.workoutRepository.fetchWorkoutSessionLog(userID: userID, sessionID: sessionID)
            return .success(sessionLog)
        } catch {
            return .failure(error)
        }
    }
    
    public func fetchSessionLogs(for program: WorkoutProgram) async -> [WorkoutSessionLog] {
        guard let userID = DIContainer.shared.authService.currentUserID else { return [] }
        // Fetch by date across the program's lifetime rather than by routine ID. A log's routineID
        // can drift out of sync with the program (IDs regenerate when a pre-built program is
        // re-adopted), which would hide completed workouts from progression entirely. We then keep
        // only the logs that belong to this program (routine-ID match or exercise-name signature).
        let windowDays = Self.sessionLogWindowDays(for: program)
        do {
            let recent = try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(userID: userID, sinceDays: windowDays)
            return recent.filter { WorkoutRules.logBelongsToProgram($0, program: program) }
        } catch {
            reportFailure(error, operation: "fetch_session_logs")
            return []
        }
    }

    /// How far back to pull history when reconciling a program's progress: its full lifetime plus a
    /// buffer, with a sane floor for brand-new programs.
    static func sessionLogWindowDays(for program: WorkoutProgram) -> Int {
        guard let start = program.startDate else { return 400 }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(elapsed + 14, 120)
    }

    /// Fetches completed session logs from the last `days` days (used by the muscle recovery map,
    /// which needs the real per-exercise names rather than the routine summary in the daily log).
    public func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog] {
        switch await fetchRecentSessionLogsResult(sinceDays: days) {
        case .success(let logs):
            return logs
        case .failure:
            return []
        }
    }

    /// Result-preserving variant for reports that must distinguish an empty history from a
    /// failed read instead of quietly presenting a data outage as zero training.
    public func fetchRecentSessionLogsResult(sinceDays days: Int) async -> Result<[WorkoutSessionLog], Error> {
        guard let userID = DIContainer.shared.authService.currentUserID else { return .success([]) }
        do {
            let logs = try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(
                userID: userID,
                sinceDays: days
            )
            guard DIContainer.shared.authService.currentUserID == userID else {
                return .failure(CancellationError())
            }
            return .success(logs)
        } catch {
            reportFailure(error, operation: "fetch_recent_session_logs")
            return .failure(error)
        }
    }

    public func fetchRoutinesAndPrograms() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            resetAccountState()
            return
        }
        if listenerUserID == userID, routineListener != nil, programListener != nil {
            return
        }

        if let pListener = programListener { DIContainer.shared.workoutRepository.removeListener(pListener) }
        if let rListener = routineListener { DIContainer.shared.workoutRepository.removeListener(rListener) }
        programListener = nil
        routineListener = nil
        listenerUserID = userID
        userPrograms = []
        userRoutines = []
        activeProgram = nil
        migrateLegacyActiveProgramStorageIfNeeded(for: userID)

        self.programListener = DIContainer.shared.workoutRepository.addProgramsSnapshotListener(userID: userID) { [weak self] result in
            guard let self,
                  self.listenerUserID == userID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            switch result {
            case .success(let programs):
                self.userPrograms = programs
                self.restoreActiveProgram(for: userID)
            case .failure(let error):
                self.reportFailure(error, operation: "programs_snapshot_listener")
            }
        }

        self.routineListener = DIContainer.shared.workoutRepository.addRoutinesSnapshotListener(userID: userID) { [weak self] result in
            guard let self,
                  self.listenerUserID == userID,
                  DIContainer.shared.authService.currentUserID == userID else { return }
            switch result {
            case .success(let routines):
                self.userRoutines = routines
            case .failure(let error):
                self.reportFailure(error, operation: "routines_snapshot_listener")
            }
        }
    }

    deinit {
        let pListener = programListener
        let rListener = routineListener

        Task { @MainActor in
            if let pListener { DIContainer.shared.workoutRepository.removeListener(pListener) }
            if let rListener { DIContainer.shared.workoutRepository.removeListener(rListener) }
        }
    }

    public func setActiveProgram(_ program: WorkoutProgram) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        activeProgram = program
        defaults.set(false, forKey: Self.activeProgramClearedStorageKey(for: userID))
        if let programID = program.id {
            defaults.set(programID, forKey: Self.activeProgramIDStorageKey(for: userID))
        }
    }

    public func clearActiveProgram() {
        activeProgram = nil
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        defaults.removeObject(forKey: Self.activeProgramIDStorageKey(for: userID))
        defaults.set(true, forKey: Self.activeProgramClearedStorageKey(for: userID))
    }

    @discardableResult
    public func saveProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        
        do {
            let savedProgram = try await DIContainer.shared.workoutRepository.saveProgram(userID: userID, program: program)
            
            if program.id == nil {
                DIContainer.shared.analyticsManager?.logEvent("program_created", parameters: nil)
            }
            return savedProgram
        } catch {
            reportFailure(
                error,
                operation: "save_program",
                userMessage: "Couldn't save your program changes. Please try again."
            )
            return nil
        }
    }

    /// Advances the program's pointer to `targetIndex`, marking every slot in between as skipped.
    /// Skipping never writes a session log, daily-log entry, or HealthKit sample, so it can't
    /// collide with the Apple Health strength-dedup logic. Updates `activeProgram` and persists.
    @discardableResult
    public func skipToIndex(_ targetIndex: Int, in program: WorkoutProgram) async -> WorkoutProgram? {
        let updated = WorkoutRules.skip(to: targetIndex, in: program)
        if updated.currentProgressIndex == program.currentProgressIndex { return program }

        let saved = await saveProgram(updated)
        if let saved, saved.id == activeProgram?.id {
            activeProgram = saved
        }
        return saved
    }

    /// Skips just the current workout: advances the pointer by one and marks it skipped.
    @discardableResult
    public func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram? {
        let updated = WorkoutRules.skipCurrentWorkout(in: program)
        let saved = await saveProgram(updated)
        if let saved, saved.id == activeProgram?.id {
            activeProgram = saved
        }
        return saved
    }

    @discardableResult
    public func deleteProgram(_ program: WorkoutProgram) async -> ProgramDeletionResult {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .userNotLoggedIn
        }
        guard let programID = resolvedProgramID(for: program) else {
            clearActiveProgram()
            return .clearedLocalOnly
        }

        do {
            try await DIContainer.shared.workoutRepository.deleteProgram(userID: userID, programID: programID)
            removeDeletedProgramFromLocalState(programID: programID, fallbackName: program.name)
            return .deleted
        } catch {
            // No toast here: the ProgramDeletionResult carries the user-facing message.
            reportFailure(error, operation: "delete_program")
            return .failed(error.localizedDescription)
        }
    }

    public func saveRoutine(_ routine: WorkoutRoutine) async throws {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            throw WorkoutServiceError.userNotLoggedIn
        }
        
        do {
            try await DIContainer.shared.workoutRepository.saveRoutine(userID: userID, routine: routine)
        } catch {
            throw WorkoutServiceError.firestoreError(error)
        }
    }

    public func deleteRoutine(_ routine: WorkoutRoutine) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        
        Task {
            do {
                try await DIContainer.shared.workoutRepository.deleteRoutine(userID: userID, routineID: routine.id)
            } catch {
                reportFailure(
                    error,
                    operation: "delete_routine",
                    userMessage: "Couldn't delete the routine. Please try again."
                )
            }
        }
    }

    public func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        do {
            try await DIContainer.shared.workoutRepository.saveWorkoutSessionLog(userID: userID, log: log)
        } catch {
            reportFailure(
                error,
                operation: "save_workout_session_log",
                userMessage: "Couldn't save your workout to history. Check your connection."
            )
        }
    }

    public func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        guard let userID = DIContainer.shared.authService.currentUserID else { return [] }

        do {
            return try await DIContainer.shared.workoutRepository.fetchHistory(userID: userID, exerciseName: exerciseName)
        } catch {
            reportFailure(error, operation: "fetch_exercise_history")
            return []
        }
    }

    public func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        do {
             return try await DIContainer.shared.workoutRepository.fetchPreviousPerformance(userID: userID, exerciseName: exerciseName)
        } catch {
            reportFailure(error, operation: "fetch_previous_performance")
            return nil
        }
    }

    // MARK: - AI Workout Generation (Refactored)

    public func generateAIWorkoutPlan(
        goal: String,
        daysPerWeek: Int,
        fitnessLevel: String,
        equipment: String,
        details: String,
        goalSettings: GoalSettings
    ) async -> Result<WorkoutProgram, WorkoutServiceError> {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            return .failure(.userNotLoggedIn)
        }
        
        guard let prompt = WorkoutRules.createAIWorkoutPrompt(
            goal: goal,
            daysPerWeek: daysPerWeek,
            fitnessLevel: fitnessLevel,
            equipment: equipment,
            details: details,
            age: goalSettings.age,
            gender: goalSettings.gender,
            primaryWeightGoal: goalSettings.goal
        ) else {
            return .failure(.apiError("Failed to load internal exercise list."))
        }

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]
        
        // Use shared AIService
        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            model: "gpt-4o-mini",
            maxTokens: 4000,
            temperature: 0.7,
            responseFormat: ["type": "json_object"],
            retryCount: 1
        )

        switch result {
        case .success(let responseString):
            let parseResult = WorkoutRules.parseAIWorkoutResponse(responseString)
            switch parseResult {
            case .success(let decodedResponse):
                DIContainer.shared.analyticsManager?.logEvent("ai_workout_generated", parameters: [
                    "goal": goal,
                    "days_per_week": daysPerWeek,
                    "fitness_level": fitnessLevel
                ])
                
                let program = WorkoutRules.mapResponseToProgram(decodedResponse, userID: userID)
                return .success(program)
            case .apiError(let message):
                return .failure(.apiError(message))
            case .decodingError(let error):
                AppLog.workouts.error("AI workout decode failed: \(error.localizedDescription, privacy: .public)")
                AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_ai_workout_response")
                return .failure(.decodingError(error))
            }
        case .failure(let error):
            return .failure(.apiError(error.localizedDescription))
        }
    }

    public func detachListener() {
        if let l = programListener { DIContainer.shared.workoutRepository.removeListener(l) }
        if let l = routineListener { DIContainer.shared.workoutRepository.removeListener(l) }
        programListener = nil
        routineListener = nil
    }

    private func loadPreBuiltPrograms() {
        self.preBuiltPrograms = WorkoutRules.generatePreBuiltPrograms()
    }

    /// Copies a pre-built program and saves it as a user program
    @discardableResult
    public func selectPreBuiltProgram(_ program: WorkoutProgram, startDate: Date = Date()) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        
        DIContainer.shared.analyticsManager?.logEvent("prebuilt_program_selected", parameters: ["program_name": program.name])

        let userProgramCopy = WorkoutRules.preparePreBuiltProgramForUser(
            program,
            userID: userID,
            startDate: startDate
        )

        let savedProgram = await saveProgram(userProgramCopy)
        if let savedProgram {
            setActiveProgram(savedProgram)
        }
        return savedProgram
    }

    private func restoreActiveProgram(for userID: String) {
        guard listenerUserID == userID,
              DIContainer.shared.authService.currentUserID == userID else { return }
        let programIDKey = Self.activeProgramIDStorageKey(for: userID)
        let clearedKey = Self.activeProgramClearedStorageKey(for: userID)

        guard !userPrograms.isEmpty else {
            activeProgram = nil
            defaults.removeObject(forKey: programIDKey)
            return
        }

        if defaults.bool(forKey: clearedKey) {
            activeProgram = nil
            return
        }

        if let savedActiveProgramID = defaults.string(forKey: programIDKey),
           let savedActiveProgram = userPrograms.first(where: { $0.id == savedActiveProgramID }) {
            activeProgram = savedActiveProgram
            return
        }

        if let currentActiveProgramID = activeProgram?.id,
           let currentActiveProgram = userPrograms.first(where: { $0.id == currentActiveProgramID }) {
            activeProgram = currentActiveProgram
            return
        }

        activeProgram = userPrograms.first
        if let firstProgramID = activeProgram?.id {
            defaults.set(firstProgramID, forKey: programIDKey)
        }
    }

    private func resetAccountState() {
        detachListener()
        listenerUserID = nil
        userPrograms = []
        userRoutines = []
        activeProgram = nil
    }

    private func migrateLegacyActiveProgramStorageIfNeeded(for userID: String) {
        let programIDKey = Self.activeProgramIDStorageKey(for: userID)
        let clearedKey = Self.activeProgramClearedStorageKey(for: userID)

        if defaults.object(forKey: programIDKey) == nil,
           let legacyProgramID = defaults.string(forKey: Self.legacyActiveProgramIDKey) {
            defaults.set(legacyProgramID, forKey: programIDKey)
        }
        if defaults.object(forKey: clearedKey) == nil,
           defaults.object(forKey: Self.legacyActiveProgramClearedKey) != nil {
            defaults.set(defaults.bool(forKey: Self.legacyActiveProgramClearedKey), forKey: clearedKey)
        }

        defaults.removeObject(forKey: Self.legacyActiveProgramIDKey)
        defaults.removeObject(forKey: Self.legacyActiveProgramClearedKey)
    }

    static func activeProgramIDStorageKey(for userID: String) -> String {
        "active_workout_program_id_\(accountDigest(userID))"
    }

    static func activeProgramClearedStorageKey(for userID: String) -> String {
        "active_workout_program_cleared_\(accountDigest(userID))"
    }

    private static func accountDigest(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func resolvedProgramID(for program: WorkoutProgram) -> String? {
        if let programID = program.id,
           userPrograms.contains(where: { $0.id == programID }) {
            return programID
        }

        if let activeProgramID = activeProgram?.id,
           activeProgram?.name == program.name,
           userPrograms.contains(where: { $0.id == activeProgramID }) {
            return activeProgramID
        }

        if let matchingProgram = userPrograms.first(where: { savedProgram in
            savedProgram.name == program.name && Calendar.current.isDate(savedProgram.dateCreated, equalTo: program.dateCreated, toGranularity: .second)
        }) {
            return matchingProgram.id
        }

        return userPrograms.first(where: { $0.name == program.name })?.id ?? program.id
    }

    private func removeDeletedProgramFromLocalState(programID: String, fallbackName: String) {
        userPrograms.removeAll { savedProgram in
            if let savedProgramID = savedProgram.id {
                return savedProgramID == programID
            }
            return savedProgram.name == fallbackName
        }

        if activeProgram?.id == programID || activeProgram?.name == fallbackName {
            clearActiveProgram()
        }
    }
}

// Helpers
public struct AIProgramResponse: Codable {
    public let programName: String
    public let routines: [AIRoutine]
}
public struct AIRoutine: Codable {
    public let name: String
    public let exercises: [AIExercise]
}
public struct AIExercise: Codable {
    public let name: String
    public let type: ExerciseType
    public let sets: [AISet]
    public let alternatives: [String]?
}
public struct AISet: Codable {
    public let target: String
}

// Missing Extension for Array Chunking
public extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
