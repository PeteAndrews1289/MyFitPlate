import Foundation

/// Pure logic rules and data transformations for Workout Programs, Routines, and Exercises.
public struct WorkoutRules {
    
    /// Advances the program's pointer to `targetIndex`, marking every slot in between as skipped.
    /// Returns the mutated copy of the program.
    public static func skip(to targetIndex: Int, in program: WorkoutProgram) -> WorkoutProgram {
        let current = program.currentProgressIndex ?? 0
        guard targetIndex > current else { return program }

        var updated = program
        var skipped = Set(updated.skippedIndices ?? [])
        for index in current..<targetIndex {
            skipped.insert(index)
        }
        updated.skippedIndices = skipped.sorted()
        updated.currentProgressIndex = targetIndex
        
        return updated
    }

    /// Skips just the current workout: advances the pointer by one and marks it skipped.
    public static func skipCurrentWorkout(in program: WorkoutProgram) -> WorkoutProgram {
        return skip(to: (program.currentProgressIndex ?? 0) + 1, in: program)
    }

    /// Advances the program after a completed routine. If the saved progress pointer is stale,
    /// this searches forward for the completed routine and advances past that slot.
    public static func advanceAfterCompletion(
        in program: WorkoutProgram,
        completedRoutineID: String
    ) -> WorkoutProgram {
        let total = totalSlots(in: program)
        guard total > 0 else { return program }

        let current = min(max(program.currentProgressIndex ?? 0, 0), total)
        let matchedSlot = (current..<total).first { slot in
            program.routines.indices.contains(slot % program.routines.count) &&
                program.routines[slot % program.routines.count].id == completedRoutineID
        }

        let completedSlot = matchedSlot ?? current
        let nextIndex = min(completedSlot + 1, total)
        guard nextIndex > current else { return program }

        var updated = program
        updated.currentProgressIndex = nextIndex
        return updated
    }

    /// Repairs a stale program pointer from persisted session logs. This is intentionally count
    /// based because old app versions could save the session log but miss the program advancement.
    public static func reconcileProgressFromSessionLogs(
        in program: WorkoutProgram,
        sessionLogs: [WorkoutSessionLog]
    ) -> WorkoutProgram {
        let total = totalSlots(in: program)
        guard total > 0 else { return program }

        // Count the logs that belong to this program. We match on routine ID first, then fall back
        // to an exercise-name signature so a completion still counts even when the program's routine
        // IDs changed after the log was written — otherwise ID drift silently orphans the log and
        // progress can never advance past the point where the drift happened.
        let completedLogCount = sessionLogs.filter { logBelongsToProgram($0, program: program) }.count
        guard completedLogCount > 0 else { return program }

        let current = min(max(program.currentProgressIndex ?? 0, 0), total)
        let skipped = Set(program.skippedIndices ?? [])
        var reconciledIndex = current

        while reconciledIndex < total &&
            completedSlotCount(upTo: reconciledIndex, skipped: skipped) < completedLogCount {
            reconciledIndex += 1
        }

        guard reconciledIndex > current else { return program }
        var updated = program
        updated.currentProgressIndex = reconciledIndex
        return updated
    }

    /// Whether a session log represents a completed workout for `program`. Prefers a direct routine
    /// ID match; falls back to comparing the logged exercise names against each routine so a log
    /// still counts after routine IDs are regenerated (e.g. re-adopting a pre-built program, which
    /// mints fresh IDs while keeping the same routine and exercise names).
    public static func logBelongsToProgram(_ log: WorkoutSessionLog, program: WorkoutProgram) -> Bool {
        if program.routines.contains(where: { $0.id == log.routineID }) { return true }

        let loggedNames = Set(log.completedExercises
            .map { normalizedExerciseName($0.exerciseName) }
            .filter { !$0.isEmpty })
        guard !loggedNames.isEmpty else { return false }

        return program.routines.contains { routine in
            let routineNames = Set(routine.exercises
                .map { normalizedExerciseName($0.name) }
                .filter { !$0.isEmpty })
            guard !routineNames.isEmpty else { return false }
            let overlap = loggedNames.intersection(routineNames).count
            // Half of the logged movements landing in one routine is a confident match, tolerant of
            // a swapped exercise or two mid-session.
            return Double(overlap) >= Double(loggedNames.count) * 0.5
        }
    }

    private static func normalizedExerciseName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func completedSlotCount(upTo index: Int, skipped: Set<Int>) -> Int {
        guard index > 0 else { return 0 }
        return (0..<index).filter { !skipped.contains($0) }.count
    }

    private static func totalSlots(in program: WorkoutProgram) -> Int {
        max((program.daysOfWeek?.count ?? 0) * 12, program.routines.count)
    }

    /// Prepares a fresh copy of a pre-built program for a user by resetting IDs and clearing completion states.
    public static func preparePreBuiltProgramForUser(_ program: WorkoutProgram, userID: String) -> WorkoutProgram {
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

        return userProgramCopy
    }

    /// Maps an AI response model to the domain WorkoutProgram model.
    public static func mapResponseToProgram(_ response: AIProgramResponse, userID: String) -> WorkoutProgram {
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

    /// Generates the static list of pre-built programs.
    public static func generatePreBuiltPrograms() -> [WorkoutProgram] {
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
                sets: (0..<sets).map { _ in ExerciseSet(target: target) },
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
            exercise("Lying Leg Curl", target: "6-10 reps", sets: 2, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "6-10 reps", sets: 3, alternatives: ["Seated Calf Raise"]),
            exercise("Seated Calf Raise", target: "6-10 reps", sets: 2, alternatives: ["Calf Press on Leg Press"])
        ])
        let phatBackShouldersHypertrophy = WorkoutRoutine(id: "prebuilt_phat_back_shoulders", userID: systemUserID, name: "Back/Shoulders Hypertrophy", dateCreated: now, exercises: [
            exercise("Bent-over Row", target: "10-12 reps", sets: 3, alternatives: ["Pendlay Row"]),
            exercise("Pull-Up", target: "10-12 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Seated Cable Row", target: "12-15 reps", sets: 2, alternatives: ["T-Bar Row"]),
            exercise("Dumbbell Pullover", target: "15-20 reps", sets: 2, alternatives: ["Cable Pullover"]),
            exercise("Seated Dumbbell Press", target: "10-12 reps", sets: 3, alternatives: ["Barbell Overhead Press"]),
            exercise("Upright Row", target: "12-15 reps", sets: 2, alternatives: ["Cable Upright Row"]),
            exercise("Dumbbell Lateral Raise", target: "15-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"])
        ])
        let phatLowerHypertrophy = WorkoutRoutine(id: "prebuilt_phat_lower_hypertrophy", userID: systemUserID, name: "Lower Hypertrophy", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "10-12 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Hack Squat", target: "12-15 reps", sets: 3, alternatives: ["Goblet Squat"]),
            exercise("Leg Extension", target: "15-20 reps", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Romanian Deadlift", target: "10-12 reps", sets: 3, alternatives: ["Stiff Legged Deadlift"]),
            exercise("Lying Leg Curl", target: "15-20 reps", sets: 2, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "15-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let phatChestArmsHypertrophy = WorkoutRoutine(id: "prebuilt_phat_chest_arms", userID: systemUserID, name: "Chest/Arms Hypertrophy", dateCreated: now, exercises: [
            exercise("Flat Dumbbell Press", target: "10-12 reps", sets: 3, alternatives: ["Barbell Bench Press"]),
            exercise("Incline Dumbbell Press", target: "12-15 reps", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Cable Crossover", target: "15-20 reps", sets: 2, alternatives: ["Dumbbell Flye"]),
            exercise("Barbell Curl", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Dumbbell Concentration Curl", target: "12-15 reps", sets: 2, alternatives: ["Preacher Curl"]),
            exercise("Lying Triceps Extension", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Overhead Triceps Extension"]),
            exercise("Cable Triceps Pushdown", target: "12-15 reps", sets: 2, alternatives: ["Rope Triceps Pushdown"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_phat", userID: systemUserID, name: "PHAT (Power Hypertrophy Adaptive Training)", dateCreated: now, routines: [phatUpperPower, phatLowerPower, phatBackShouldersHypertrophy, phatLowerHypertrophy, phatChestArmsHypertrophy], daysOfWeek: [2, 3, 5, 6, 7]))

        return programs
    }

    /// Generates the AI prompt for a workout plan
    public static func createAIWorkoutPrompt(
        goal: String,
        daysPerWeek: Int,
        fitnessLevel: String,
        equipment: String,
        details: String,
        age: Int,
        gender: String,
        primaryWeightGoal: String
    ) -> String? {
        let exerciseListJSON: String
        do {
            let jsonData = try JSONEncoder().encode(ExerciseList.categorizedExercises)
            exerciseListJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return nil
        }

        let detailsString = details.isEmpty ? "No additional details provided." : details

        return """
        You are an expert kinesiologist and fitness coach. Your task is to create a safe, effective, and well-structured workout program.

        **USER PROFILE:**
        - Age: \(age)
        - Gender: \(gender)
        - Primary Weight Goal: \(primaryWeightGoal) (e.g., Lose, Maintain, Gain)
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
    }

    public enum ParsedAIWorkoutResult {
        case success(AIProgramResponse)
        case decodingError(Error)
        case apiError(String)
    }

    /// Parses the string response from the AI into a structured domain result
    public static func parseAIWorkoutResponse(_ responseString: String) -> ParsedAIWorkoutResult {
        guard let jsonData = responseString.data(using: .utf8) else {
            return .decodingError(NSError(domain: "WorkoutRules", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert AI response to data."]))
        }
        
        do {
            if responseString.contains("cannot generate") || responseString.contains("unable to") {
                 struct Refusal: Codable { let programName: String }
                 if let refusal = try? JSONDecoder().decode(Refusal.self, from: jsonData) {
                     return .apiError(refusal.programName)
                 }
                 return .apiError("The AI was unable to generate a plan for this request.")
            }
            
            let decodedResponse = try JSONDecoder().decode(AIProgramResponse.self, from: jsonData)
            if decodedResponse.routines.isEmpty && decodedResponse.programName.contains("cannot") {
                return .apiError(decodedResponse.programName)
            }
            
            return .success(decodedResponse)
        } catch {
            return .decodingError(error)
        }
    }
}
