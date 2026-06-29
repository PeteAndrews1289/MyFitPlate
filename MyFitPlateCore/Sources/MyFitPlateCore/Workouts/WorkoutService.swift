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
    private let activeProgramIDKey = "activeWorkoutProgramID"

    public init() {
        loadPreBuiltPrograms()
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
        let routineIDs = program.routines.map { $0.id }
        do {
            return try await DIContainer.shared.workoutRepository.fetchSessionLogs(userID: userID, routineIDs: routineIDs)
        } catch {
            AppLog.workouts.error("Failed to fetch session logs: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches completed session logs from the last `days` days (used by the muscle recovery map,
    /// which needs the real per-exercise names rather than the routine summary in the daily log).
    public func fetchRecentSessionLogs(sinceDays days: Int) async -> [WorkoutSessionLog] {
        guard let userID = DIContainer.shared.authService.currentUserID else { return [] }
        do {
            return try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(userID: userID, sinceDays: days)
        } catch {
            AppLog.workouts.error("Failed to fetch recent session logs: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func fetchRoutinesAndPrograms() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        if listenerUserID == userID, routineListener != nil, programListener != nil {
            return
        }

        if let pListener = programListener { DIContainer.shared.workoutRepository.removeListener(pListener) }
        if let rListener = routineListener { DIContainer.shared.workoutRepository.removeListener(rListener) }
        listenerUserID = userID

        self.programListener = DIContainer.shared.workoutRepository.addProgramsSnapshotListener(userID: userID) { [weak self] result in
            switch result {
            case .success(let programs):
                self?.userPrograms = programs
                self?.restoreActiveProgram()
            case .failure(let error):
                AppLog.workouts.error("Failed to fetch user programs: \(error.localizedDescription, privacy: .public)")
            }
        }

        self.routineListener = DIContainer.shared.workoutRepository.addRoutinesSnapshotListener(userID: userID) { [weak self] result in
            switch result {
            case .success(let routines):
                self?.userRoutines = routines
            case .failure(let error):
                AppLog.workouts.error("Failed to fetch user routines: \(error.localizedDescription, privacy: .public)")
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
        activeProgram = program
        if let programID = program.id {
            UserDefaults.standard.set(programID, forKey: activeProgramIDKey)
        }
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
            AppLog.workouts.error("Failed to save workout program: \(error.localizedDescription, privacy: .public)")
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

    public func deleteProgram(_ program: WorkoutProgram) {
        guard let userID = DIContainer.shared.authService.currentUserID, let programID = program.id else { return }
        if activeProgram?.id == programID {
            activeProgram = nil
            UserDefaults.standard.removeObject(forKey: activeProgramIDKey)
        }
        
        Task {
            do {
                try await DIContainer.shared.workoutRepository.deleteProgram(userID: userID, programID: programID)
            } catch {
                AppLog.workouts.error("Failed to delete workout program: \(error.localizedDescription, privacy: .public)")
            }
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
                AppLog.workouts.error("Failed to delete workout routine: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func saveWorkoutSessionLog(_ log: WorkoutSessionLog) async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        do {
            try await DIContainer.shared.workoutRepository.saveWorkoutSessionLog(userID: userID, log: log)
        } catch {
            AppLog.workouts.error("Failed to save workout session log: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func fetchHistory(for exerciseName: String) async -> [WorkoutSessionLog] {
        guard let userID = DIContainer.shared.authService.currentUserID else { return [] }

        do {
            return try await DIContainer.shared.workoutRepository.fetchHistory(userID: userID, exerciseName: exerciseName)
        } catch {
            AppLog.workouts.error("Failed to fetch exercise history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func fetchPreviousPerformance(for exerciseName: String) async -> CompletedExercise? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        do {
             return try await DIContainer.shared.workoutRepository.fetchPreviousPerformance(userID: userID, exerciseName: exerciseName)
        } catch {
            AppLog.workouts.error("Failed to fetch previous performance for \(exerciseName, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                AppLog.workouts.error("Failed to decode AI workout response: \(error.localizedDescription, privacy: .public)")
                return .failure(.decodingError(error))
            }
        case .failure(let error):
            return .failure(.apiError(error.localizedDescription))
        }
    }

    public func detachListener(){
        if let l = programListener { DIContainer.shared.workoutRepository.removeListener(l) }
        if let l = routineListener { DIContainer.shared.workoutRepository.removeListener(l) }
    }

    private func loadPreBuiltPrograms() {
        self.preBuiltPrograms = WorkoutRules.generatePreBuiltPrograms()
    }

    /// Copies a pre-built program and saves it as a user program
    @discardableResult
    public func selectPreBuiltProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        
        DIContainer.shared.analyticsManager?.logEvent("prebuilt_program_selected", parameters: ["program_name": program.name])

        let userProgramCopy = WorkoutRules.preparePreBuiltProgramForUser(program, userID: userID)

        let savedProgram = await saveProgram(userProgramCopy)
        if let savedProgram {
            setActiveProgram(savedProgram)
        }
        return savedProgram
    }

    private func restoreActiveProgram() {
        guard !userPrograms.isEmpty else {
            activeProgram = nil
            UserDefaults.standard.removeObject(forKey: activeProgramIDKey)
            return
        }

        if let savedActiveProgramID = UserDefaults.standard.string(forKey: activeProgramIDKey),
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
            UserDefaults.standard.set(firstProgramID, forKey: activeProgramIDKey)
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
