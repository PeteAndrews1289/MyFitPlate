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
        let current = program.currentProgressIndex ?? 0
        guard targetIndex > current else { return program }

        var updated = program
        var skipped = Set(updated.skippedIndices ?? [])
        for index in current..<targetIndex {
            skipped.insert(index)
        }
        updated.skippedIndices = skipped.sorted()
        updated.currentProgressIndex = targetIndex

        let saved = await saveProgram(updated)
        if let saved, saved.id == activeProgram?.id {
            activeProgram = saved
        }
        return saved
    }

    /// Skips just the current workout: advances the pointer by one and marks it skipped.
    @discardableResult
    public func skipCurrentWorkout(in program: WorkoutProgram) async -> WorkoutProgram? {
        await skipToIndex((program.currentProgressIndex ?? 0) + 1, in: program)
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

    /// Generates a workout plan using AI based on enhanced user input.
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
        
        let exerciseListJSON: String
        do {
            let jsonData = try JSONEncoder().encode(ExerciseList.categorizedExercises)
            exerciseListJSON = String(data: jsonData, encoding: String.Encoding.utf8) ?? "{}"
        } catch {
            return .failure(.apiError("Failed to load internal exercise list."))
        }

        let detailsString = details.isEmpty ? "No additional details provided." : details

        let prompt = """
        You are an expert kinesiologist and fitness coach. Your task is to create a safe, effective, and well-structured workout program.

        **USER PROFILE:**
        - Age: \(goalSettings.age)
        - Gender: \(goalSettings.gender)
        - Primary Weight Goal: \(goalSettings.goal) (e.g., Lose, Maintain, Gain)
        - Stated Fitness Goal: \(goal)
        - Fitness Level: \(fitnessLevel)
        - Available Equipment: \(equipment)
        - Days Per Week: \(daysPerWeek)
        - Additional Notes: \(detailsString)

        **YOUR RULES (READ CAREFULLY):**

        1.  **EXERCISE SELECTION (CRITICAL):** You MUST ONLY use exercises from the following JSON list. Do NOT invent exercises. If the user's equipment is limited (e.g., 'Bodyweight Only'), only select exercises that match that constraint (e.g., 'Push-up', 'Bodyweight Squat', 'Plank').
            ```json
            \(exerciseListJSON)
            ```

        2.  **PROGRAM STRUCTURE:** Create a logical split that matches the user's days per week.
            - 2 Days: Full Body / Full Body
            - 3 Days: Full Body (A/B/A) OR Push / Pull / Legs
            - 4 Days: Upper / Lower / Upper / Lower
            - 5 Days: Push / Pull / Legs / Upper / Lower
            - 6 Days: Push / Pull / Legs / Push / Pull / Legs
            Each routine must have a MINIMUM of 5 exercises.

        3.  **SETS & REPS:** Tailor volume to the user's level.
            - Beginner: 3 sets per exercise. Reps in 10-15 range.
            - Intermediate: 3-4 sets per exercise. Reps in 8-12 range.
            - Advanced: 4-5 sets per exercise. Use varied rep ranges (e.g., 6-10, 12-15).
            - Cardio/Flexibility: Use time (e.g., "30-60 sec", "20 min").

        4.  **ALTERNATIVES:** The "alternatives" array MUST contain 2 suitable replacement exercises *from the provided JSON list* for the same muscle group.

        5.  **SAFETY:** If the user mentions an injury (e.g., "bad knee"), avoid high-impact exercises (like 'Burpees', 'Jump Squats') and provide low-impact alternatives. Always assume "Beginner" if the fitness level is unclear.

        6.  **RESPONSE FORMAT (CRITICAL):** Your response MUST be a valid JSON object.
            - Root object keys: "programName" (string) and "routines" (array).
            - Routine object keys: "name" (string, e.g., "Push Day") and "exercises" (array).
            - Exercise object keys: "name" (string), "type" (string: "Strength", "Cardio", or "Flexibility"), "sets" (array), "alternatives" (array).
            - Set object key: "target" (string, e.g., "8-12 reps", "60 seconds").
        """

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
            guard let jsonData = responseString.data(using: String.Encoding.utf8) else {
                return .failure(.decodingError(NSError(domain: "WorkoutService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert AI response to data."])))
            }
            do {
                if responseString.contains("cannot generate") || responseString.contains("unable to") {
                     struct Refusal: Codable { let programName: String }
                     if let refusal = try? JSONDecoder().decode(Refusal.self, from: jsonData) {
                         return .failure(.apiError(refusal.programName))
                     }
                     return .failure(.apiError("The AI was unable to generate a plan for this request."))
                }
                
                let decodedResponse = try JSONDecoder().decode(AIProgramResponse.self, from: jsonData)
                if decodedResponse.routines.isEmpty && decodedResponse.programName.contains("cannot") {
                    return .failure(.apiError(decodedResponse.programName))
                }
                
                DIContainer.shared.analyticsManager?.logEvent("ai_workout_generated", parameters: [
                    "goal": goal,
                    "days_per_week": daysPerWeek,
                    "fitness_level": fitnessLevel
                ])
                
                let program = mapResponseToProgram(decodedResponse, userID: userID)
                return .success(program)
            } catch {
                AppLog.workouts.error("Failed to decode AI workout response: \(error.localizedDescription, privacy: .public)")
                return .failure(.decodingError(error))
            }
        case .failure(let error):
            return .failure(.apiError(error.localizedDescription))
        }
    }
    
    private func mapResponseToProgram(_ response: AIProgramResponse, userID: String) -> WorkoutProgram {
        let routines = response.routines.map { aiRoutine -> WorkoutRoutine in
            let exercises = aiRoutine.exercises.map { aiExercise -> RoutineExercise in
                let sets = aiExercise.sets.map { aiSet -> ExerciseSet in
                    return ExerciseSet(target: aiSet.target)
                }
                let exerciseType = ExerciseType(rawValue: aiExercise.type.rawValue) ?? .strength
                return RoutineExercise(name: aiExercise.name, type: exerciseType, sets: sets, alternatives: aiExercise.alternatives)
            }
            return WorkoutRoutine(id: UUID().uuidString, userID: userID, name: aiRoutine.name, dateCreated: Date(), exercises: exercises)
        }

        return WorkoutProgram(userID: userID, name: response.programName, dateCreated: Date(), routines: routines)
    }

    public func detachListener(){
        if let l = programListener { DIContainer.shared.workoutRepository.removeListener(l) }
        if let l = routineListener { DIContainer.shared.workoutRepository.removeListener(l) }
    }

    private func loadPreBuiltPrograms() {
        var programs: [WorkoutProgram] = []
        let systemUserID = "system_prebuilt"
        let now = Date()

        func exercise(
            _ name: String,
            target: String,
            sets: Int = 3,
            type: ExerciseType = .strength,
            alternatives: [String]? = nil
        ) -> RoutineExercise {
            RoutineExercise(
                name: name,
                type: type,
                sets: Array(repeating: ExerciseSet(target: target), count: sets),
                alternatives: alternatives,
                targetSets: sets,
                targetReps: target
            )
        }

        let sl5x5_A = WorkoutRoutine(id: "prebuilt_stronglifts_a", userID: systemUserID, name: "Workout A", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Leg Press", "Goblet Squat"]),
            exercise("Barbell Bench Press", target: "5 reps", sets: 5, alternatives: ["Dumbbell Bench Press", "Push-up"]),
            exercise("Barbell Bent-over Row", target: "5 reps", sets: 5, alternatives: ["Dumbbell Row", "Seated Cable Row"])
        ])
        let sl5x5_B = WorkoutRoutine(id: "prebuilt_stronglifts_b", userID: systemUserID, name: "Workout B", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Leg Press", "Goblet Squat"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5 reps", sets: 5, alternatives: ["Dumbbell Shoulder Press", "Arnold Press"]),
            exercise("Deadlift (Conventional)", target: "5 reps", sets: 1, alternatives: ["Sumo Deadlift", "Romanian Deadlift (RDL)"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_stronglifts_5x5", userID: systemUserID, name: "StrongLifts 5x5", dateCreated: now, routines: [sl5x5_A, sl5x5_B], daysOfWeek: [2, 4, 6]))

        let bw_A = WorkoutRoutine(id: "prebuilt_bodyweight_a", userID: systemUserID, name: "Full Body Bodyweight A", dateCreated: now, exercises: [
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Barbell Back Squat", target: "15-20 reps", sets: 3, alternatives: ["Goblet Squat"]),
            exercise("Plank", target: "60 sec hold", sets: 3, type: .flexibility, alternatives: ["Crunch"]),
            exercise("Lunge (Barbell/Dumbbell)", target: "10-12 reps / side", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Back Extension (Hyperextension)", target: "15-20 reps", sets: 3, alternatives: ["Good Mornings"])
        ])
        let bw_B = WorkoutRoutine(id: "prebuilt_bodyweight_b", userID: systemUserID, name: "Full Body Bodyweight B", dateCreated: now, exercises: [
            exercise("Burpees", target: "AMRAP in 60s", sets: 3, type: .cardio, alternatives: ["Jump Rope"]),
            exercise("Hip Thrust", target: "15-20 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Leg Raise", target: "15-20 reps", sets: 3, type: .flexibility, alternatives: ["Hanging Leg Raise"]),
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Sit-up", target: "15-20 reps", sets: 3, type: .flexibility, alternatives: ["Crunch"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_beginner_bodyweight", userID: systemUserID, name: "Beginner Bodyweight", dateCreated: now, routines: [bw_A, bw_B], daysOfWeek: [2, 4, 6]))

        let dumbbellUpperA = WorkoutRoutine(id: "prebuilt_dumbbell_upper_a", userID: systemUserID, name: "Upper A - Press & Row", dateCreated: now, exercises: [
            exercise("Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Push-up", "Machine Chest Press"]),
            exercise("One-Arm Dumbbell Row", target: "10-12 reps / side", sets: 4, alternatives: ["Seated Cable Row"]),
            exercise("Seated Dumbbell Shoulder Press", target: "8-10 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Dumbbell Lateral Raise", target: "12-15 reps", sets: 3, alternatives: ["Cable Lateral Raise"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Hammer Curl"])
        ])
        let dumbbellLowerA = WorkoutRoutine(id: "prebuilt_dumbbell_lower_a", userID: systemUserID, name: "Lower A - Squat Focus", dateCreated: now, exercises: [
            exercise("Goblet Squat", target: "10-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Dumbbell Romanian Deadlift", target: "8-12 reps", sets: 4, alternatives: ["Barbell Romanian Deadlift"]),
            exercise("Dumbbell Reverse Lunge", target: "10 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Seated Calf Raise"]),
            exercise("Plank", target: "45-60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let dumbbellUpperB = WorkoutRoutine(id: "prebuilt_dumbbell_upper_b", userID: systemUserID, name: "Upper B - Incline & Arms", dateCreated: now, exercises: [
            exercise("Incline Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Chest-Supported Dumbbell Row", target: "10-12 reps", sets: 4, alternatives: ["Machine Row"]),
            exercise("Dumbbell Pullover", target: "10-15 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Hammer Curl", target: "10-15 reps", sets: 3, alternatives: ["Cable Curl"]),
            exercise("Dumbbell Overhead Triceps Extension", target: "10-15 reps", sets: 3, alternatives: ["Cable Triceps Extension"])
        ])
        let dumbbellLowerB = WorkoutRoutine(id: "prebuilt_dumbbell_lower_b", userID: systemUserID, name: "Lower B - Hinge & Carry", dateCreated: now, exercises: [
            exercise("Dumbbell Front Squat", target: "8-10 reps", sets: 4, alternatives: ["Goblet Squat"]),
            exercise("Dumbbell Hip Thrust", target: "10-15 reps", sets: 4, alternatives: ["Barbell Hip Thrust"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Farmer Carry", target: "30-45 sec", sets: 3, type: .strength, alternatives: ["Suitcase Carry"]),
            exercise("Dead Bug", target: "8-12 reps / side", sets: 3, type: .flexibility, alternatives: ["Bird Dog"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_dumbbell_hypertrophy_4_day", userID: systemUserID, name: "Dumbbell Hypertrophy 4-Day", dateCreated: now, routines: [dumbbellUpperA, dumbbellLowerA, dumbbellUpperB, dumbbellLowerB], daysOfWeek: [2, 3, 5, 6]))

        let mobilityA = WorkoutRoutine(id: "prebuilt_mobility_a", userID: systemUserID, name: "Reset A - Hips & Spine", dateCreated: now, exercises: [
            exercise("World's Greatest Stretch", target: "5 reps / side", sets: 2, type: .flexibility),
            exercise("Hip Flexor Stretch", target: "45 sec / side", sets: 2, type: .flexibility),
            exercise("Thoracic Rotation", target: "8 reps / side", sets: 2, type: .flexibility),
            exercise("Dead Bug", target: "8-10 reps / side", sets: 3, type: .flexibility),
            exercise("Box Breathing", target: "3 min", sets: 1, type: .flexibility)
        ])
        let mobilityB = WorkoutRoutine(id: "prebuilt_mobility_b", userID: systemUserID, name: "Reset B - Shoulders & Core", dateCreated: now, exercises: [
            exercise("Wall Slide", target: "10-12 reps", sets: 2, type: .flexibility),
            exercise("Scapular Push-up", target: "10-12 reps", sets: 2, type: .strength),
            exercise("Side Plank", target: "30-45 sec / side", sets: 3, type: .flexibility),
            exercise("Bird Dog", target: "8-10 reps / side", sets: 3, type: .flexibility),
            exercise("Child's Pose Breathing", target: "2 min", sets: 1, type: .flexibility)
        ])
        let mobilityC = WorkoutRoutine(id: "prebuilt_mobility_c", userID: systemUserID, name: "Reset C - Low Impact Engine", dateCreated: now, exercises: [
            exercise("Brisk Walk", target: "10 min", sets: 1, type: .cardio, alternatives: ["Stationary Bike"]),
            exercise("Glute Bridge", target: "12-15 reps", sets: 3, type: .strength),
            exercise("Bodyweight Squat", target: "10-15 reps", sets: 3, type: .strength),
            exercise("Standing Calf Raise", target: "15-20 reps", sets: 2, type: .strength),
            exercise("Couch Stretch", target: "45 sec / side", sets: 2, type: .flexibility)
        ])
        programs.append(WorkoutProgram(id: "prebuilt_mobility_core_reset", userID: systemUserID, name: "Mobility & Core Reset", dateCreated: now, routines: [mobilityA, mobilityB, mobilityC], daysOfWeek: [2, 4, 6]))

        // Layne Norton's PHAT
        let phatUpperPower = WorkoutRoutine(id: "prebuilt_phat_upper_power", userID: systemUserID, name: "Upper Power", dateCreated: now, exercises: [
            exercise("Pendlay Row", target: "3-5 reps", sets: 3, alternatives: ["Barbell Bent-over Row"]),
            exercise("Pull-Up", target: "6-10 reps", sets: 2, alternatives: ["Lat Pulldown"]),
            exercise("Flat Dumbbell Press", target: "3-5 reps", sets: 3, alternatives: ["Barbell Bench Press"]),
            exercise("Incline Dumbbell Press", target: "6-10 reps", sets: 2, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Seated Dumbbell Shoulder Press", target: "6-10 reps", sets: 3, alternatives: ["Barbell Overhead Press"]),
            exercise("Barbell Curl", target: "6-10 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Lying Triceps Extension", target: "6-10 reps", sets: 3, alternatives: ["Dumbbell Overhead Triceps Extension"])
        ])
        let phatLowerPower = WorkoutRoutine(id: "prebuilt_phat_lower_power", userID: systemUserID, name: "Lower Power", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "3-5 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Hack Squat", target: "6-10 reps", sets: 2, alternatives: ["Goblet Squat"]),
            exercise("Leg Extension", target: "6-10 reps", sets: 2, alternatives: ["Bulgarian Split Squat"]),
            exercise("Stiff Legged Deadlift", target: "5-8 reps", sets: 3, alternatives: ["Romanian Deadlift (RDL)"]),
            exercise("Glute Ham Raise", target: "6-10 reps", sets: 2, alternatives: ["Lying Leg Curl"]),
            exercise("Standing Calf Raise", target: "6-10 reps", sets: 3, alternatives: ["Seated Calf Raise"])
        ])
        let phatBackShoulders = WorkoutRoutine(id: "prebuilt_phat_back_shoulders", userID: systemUserID, name: "Back & Shoulders Hypertrophy", dateCreated: now, exercises: [
            exercise("Pendlay Row", target: "8-12 reps", sets: 3, alternatives: ["Barbell Bent-over Row"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Seated Dumbbell Shoulder Press", target: "8-12 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Upright Row", target: "8-12 reps", sets: 2, alternatives: ["Face Pull"]),
            exercise("Dumbbell Lateral Raise", target: "12-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"])
        ])
        let phatLowerHypertrophy = WorkoutRoutine(id: "prebuilt_phat_lower_hypertrophy", userID: systemUserID, name: "Lower Hypertrophy", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "8-12 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Leg Press", target: "12-15 reps", sets: 2, alternatives: ["Hack Squat"]),
            exercise("Leg Extension", target: "15-20 reps", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Romanian Deadlift (RDL)", target: "8-12 reps", sets: 3, alternatives: ["Stiff Legged Deadlift"]),
            exercise("Lying Leg Curl", target: "12-15 reps", sets: 2, alternatives: ["Seated Leg Curl"]),
            exercise("Seated Calf Raise", target: "15-20 reps", sets: 3, alternatives: ["Standing Calf Raise"])
        ])
        let phatChestArms = WorkoutRoutine(id: "prebuilt_phat_chest_arms", userID: systemUserID, name: "Chest & Arms Hypertrophy", dateCreated: now, exercises: [
            exercise("Flat Dumbbell Press", target: "8-12 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Incline Dumbbell Press", target: "8-12 reps", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Cable Crossover", target: "15-20 reps", sets: 2, alternatives: ["Dumbbell Flyes"]),
            exercise("Preacher Curl", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Seated Triceps Extension", target: "8-12 reps", sets: 3, alternatives: ["Cable Triceps Extension"]),
            exercise("Cable Pressdown", target: "12-15 reps", sets: 2, alternatives: ["Dumbbell Kickback"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_phat", userID: systemUserID, name: "Layne Norton's PHAT", dateCreated: now, routines: [phatUpperPower, phatLowerPower, phatBackShoulders, phatLowerHypertrophy, phatChestArms], daysOfWeek: [2, 3, 5, 6, 7]))

        // Men's Aesthetic Sculpt
        let aestheticPush = WorkoutRoutine(id: "prebuilt_aesthetic_push", userID: systemUserID, name: "Push", dateCreated: now, exercises: [
            exercise("Incline Dumbbell Press", target: "8-12 reps", sets: 4, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Flat Dumbbell Press", target: "8-12 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Seated Dumbbell Shoulder Press", target: "8-12 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Dumbbell Lateral Raise", target: "15-20 reps", sets: 4, alternatives: ["Cable Lateral Raise"]),
            exercise("Dumbbell Overhead Triceps Extension", target: "10-15 reps", sets: 3, alternatives: ["Cable Triceps Extension"])
        ])
        let aestheticPull = WorkoutRoutine(id: "prebuilt_aesthetic_pull", userID: systemUserID, name: "Pull", dateCreated: now, exercises: [
            exercise("Pull-Up", target: "8-12 reps", sets: 4, alternatives: ["Lat Pulldown"]),
            exercise("Dumbbell Row", target: "8-12 reps", sets: 3, alternatives: ["Seated Cable Row"]),
            exercise("Face Pull", target: "15-20 reps", sets: 3, alternatives: ["Rear Delt Fly"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 4, alternatives: ["Hammer Curl"])
        ])
        let aestheticLegs = WorkoutRoutine(id: "prebuilt_aesthetic_legs", userID: systemUserID, name: "Legs", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "8-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Romanian Deadlift (RDL)", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Romanian Deadlift"]),
            exercise("Leg Extension", target: "12-15 reps", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Lying Leg Curl", target: "12-15 reps", sets: 3, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "15-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let aestheticUpper = WorkoutRoutine(id: "prebuilt_aesthetic_upper", userID: systemUserID, name: "Upper", dateCreated: now, exercises: [
            exercise("Incline Barbell Bench Press", target: "8-12 reps", sets: 3, alternatives: ["Incline Dumbbell Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 3, alternatives: ["Machine Row"]),
            exercise("Machine Chest Press", target: "10-15 reps", sets: 3, alternatives: ["Push-up"]),
            exercise("Cable Lateral Raise", target: "15-20 reps", sets: 3, alternatives: ["Dumbbell Lateral Raise"]),
            exercise("Cable Triceps Extension", target: "10-15 reps", sets: 3, alternatives: ["Skull Crushers"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_mens_aesthetic", userID: systemUserID, name: "Men's Aesthetic Sculpt", dateCreated: now, routines: [aestheticPush, aestheticPull, aestheticLegs, aestheticUpper], daysOfWeek: [2, 3, 5, 6]))

        // Women's Glute/Leg Focus
        let gluteFocusLegs1 = WorkoutRoutine(id: "prebuilt_glute_legs_1", userID: systemUserID, name: "Glutes & Hamstrings", dateCreated: now, exercises: [
            exercise("Barbell Hip Thrust", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Hip Thrust"]),
            exercise("Romanian Deadlift (RDL)", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Romanian Deadlift"]),
            exercise("Bulgarian Split Squat", target: "10-12 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Lying Leg Curl", target: "12-15 reps", sets: 3, alternatives: ["Seated Leg Curl"]),
            exercise("Cable Kickback", target: "15-20 reps / side", sets: 3, alternatives: ["Glute Bridge"])
        ])
        let gluteFocusUpper = WorkoutRoutine(id: "prebuilt_glute_upper", userID: systemUserID, name: "Upper Body", dateCreated: now, exercises: [
            exercise("Seated Cable Row", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Lat Pulldown", target: "10-12 reps", sets: 3, alternatives: ["Pull-Up"]),
            exercise("Dumbbell Bench Press", target: "10-12 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Dumbbell Lateral Raise", target: "15-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"]),
            exercise("Dumbbell Curl", target: "12-15 reps", sets: 3, alternatives: ["Hammer Curl"])
        ])
        let gluteFocusLegs2 = WorkoutRoutine(id: "prebuilt_glute_legs_2", userID: systemUserID, name: "Quads & Calves", dateCreated: now, exercises: [
            exercise("Goblet Squat", target: "10-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Leg Press", target: "10-15 reps", sets: 3, alternatives: ["Hack Squat"]),
            exercise("Leg Extension", target: "12-15 reps", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Walking Lunge", target: "10-12 reps / side", sets: 3, alternatives: ["Dumbbell Reverse Lunge"]),
            exercise("Standing Calf Raise", target: "15-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let gluteFocusFull = WorkoutRoutine(id: "prebuilt_glute_full", userID: systemUserID, name: "Full Body & Core", dateCreated: now, exercises: [
            exercise("Deadlift (Conventional)", target: "5-8 reps", sets: 3, alternatives: ["Sumo Deadlift"]),
            exercise("Dumbbell Overhead Press", target: "8-12 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Step-up", target: "10-12 reps / side", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Plank", target: "60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_womens_glute", userID: systemUserID, name: "Women's Glute/Leg Focus", dateCreated: now, routines: [gluteFocusLegs1, gluteFocusUpper, gluteFocusLegs2, gluteFocusFull], daysOfWeek: [2, 4, 5, 6]))

        self.preBuiltPrograms = programs
    }

    /// Copies a pre-built program and saves it as a user program
    @discardableResult
    public func selectPreBuiltProgram(_ program: WorkoutProgram) async -> WorkoutProgram? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        
        DIContainer.shared.analyticsManager?.logEvent("prebuilt_program_selected", parameters: ["program_name": program.name])

        var userProgramCopy = program
        userProgramCopy.id = nil
        userProgramCopy.userID = userID
        userProgramCopy.startDate = Date()
        userProgramCopy.daysOfWeek = program.daysOfWeek?.isEmpty == false ? program.daysOfWeek : [2, 4, 6]
        userProgramCopy.currentProgressIndex = 0
        userProgramCopy.dateCreated = Date()

        userProgramCopy.routines = userProgramCopy.routines.map { routine in
            let copiedExercises = routine.exercises.map { exercise in
                var newExercise = exercise
                newExercise.id = UUID().uuidString
                newExercise.targetSets = max(exercise.targetSets, exercise.sets.count)
                newExercise.targetReps = exercise.sets.first?.target ?? exercise.targetReps
                newExercise.sets = exercise.sets.map { set in
                    var newSet = set
                    newSet.id = UUID().uuidString
                    newSet.isCompleted = false
                    newSet.reps = 0
                    newSet.weight = 0
                    newSet.distance = 0
                    newSet.durationInSeconds = 0
                    return newSet
                }
                return newExercise
            }

            return WorkoutRoutine(
                id: UUID().uuidString,
                userID: userID,
                name: routine.name,
                dateCreated: Date(),
                exercises: copiedExercises,
                notes: routine.notes
            )
        }

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
