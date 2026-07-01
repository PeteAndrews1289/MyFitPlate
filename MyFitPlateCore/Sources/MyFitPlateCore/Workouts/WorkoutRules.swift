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

        func routine(_ id: String, _ name: String, _ exercises: [RoutineExercise]) -> WorkoutRoutine {
            WorkoutRoutine(id: id, userID: systemUserID, name: name, dateCreated: now, exercises: exercises)
        }

        func addProgram(_ id: String, _ name: String, routines: [WorkoutRoutine], days: [Int]) {
            programs.append(
                WorkoutProgram(
                    id: id,
                    userID: systemUserID,
                    name: name,
                    dateCreated: now,
                    routines: routines,
                    daysOfWeek: days
                )
            )
        }

        let sl5x5_A = WorkoutRoutine(id: "prebuilt_stronglifts_a", userID: systemUserID, name: "Workout A", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Leg Press", "Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Barbell Bench Press", target: "5 reps", sets: 5, alternatives: ["Dumbbell Bench Press", "Push-up"]),
            exercise("Barbell Bent-over Row", target: "5 reps", sets: 5, alternatives: ["Dumbbell Row", "Seated Cable Row"])
        ])
        let sl5x5_B = WorkoutRoutine(id: "prebuilt_stronglifts_b", userID: systemUserID, name: "Workout B", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Leg Press", "Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5 reps", sets: 5, alternatives: ["Dumbbell Shoulder Press", "Arnold Press"]),
            exercise("Deadlift (Conventional)", target: "5 reps", sets: 1, alternatives: ["Sumo Deadlift", "Romanian Deadlift (RDL)"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_stronglifts_5x5", userID: systemUserID, name: "StrongLifts 5x5", dateCreated: now, routines: [sl5x5_A, sl5x5_B], daysOfWeek: [2, 4, 6]))

        let bw_A = WorkoutRoutine(id: "prebuilt_bodyweight_a", userID: systemUserID, name: "Full Body Bodyweight A", dateCreated: now, exercises: [
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Bodyweight Squat", target: "15-20 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Plank", target: "60 sec hold", sets: 3, type: .flexibility, alternatives: ["Crunch"]),
            exercise("Walking Lunge", target: "10-12 reps / side", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Back Extension (Hyperextension)", target: "15-20 reps", sets: 3, alternatives: ["Good Mornings"])
        ])
        let bw_B = WorkoutRoutine(id: "prebuilt_bodyweight_b", userID: systemUserID, name: "Full Body Bodyweight B", dateCreated: now, exercises: [
            exercise("Burpee", target: "AMRAP in 60s", sets: 3, type: .cardio, alternatives: ["Jump Rope"]),
            exercise("Glute Bridge", target: "15-20 reps", sets: 3, alternatives: ["Barbell Hip Thrust"]),
            exercise("Leg Raise", target: "15-20 reps", sets: 3, type: .flexibility, alternatives: ["Hanging Leg Raise"]),
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Crunch", target: "15-20 reps", sets: 3, type: .flexibility, alternatives: ["Bicycle Crunch"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_beginner_bodyweight", userID: systemUserID, name: "Beginner Bodyweight", dateCreated: now, routines: [bw_A, bw_B], daysOfWeek: [2, 4, 6]))

        let dumbbellUpperA = WorkoutRoutine(id: "prebuilt_dumbbell_upper_a", userID: systemUserID, name: "Upper A - Press & Row", dateCreated: now, exercises: [
            exercise("Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Push-up", "Machine Chest Press"]),
            exercise("Dumbbell Row", target: "10-12 reps / side", sets: 4, alternatives: ["Seated Cable Row"]),
            exercise("Dumbbell Shoulder Press", target: "8-10 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Dumbbell Lateral Raise", target: "12-15 reps", sets: 3, alternatives: ["Cable Lateral Raise"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Hammer Curl"])
        ])
        let dumbbellLowerA = WorkoutRoutine(id: "prebuilt_dumbbell_lower_a", userID: systemUserID, name: "Lower A - Squat Focus", dateCreated: now, exercises: [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "10-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Romanian Deadlift", target: "8-12 reps", sets: 4, alternatives: ["Good Mornings"]),
            exercise("Reverse Lunge", target: "10 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Seated Calf Raise"]),
            exercise("Plank", target: "45-60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let dumbbellUpperB = WorkoutRoutine(id: "prebuilt_dumbbell_upper_b", userID: systemUserID, name: "Upper B - Incline & Arms", dateCreated: now, exercises: [
            exercise("Incline Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Dumbbell Row", target: "10-12 reps", sets: 4, alternatives: ["Seated Cable Row"]),
            exercise("Dumbbell Pullover", target: "10-15 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Hammer Curl", target: "10-15 reps", sets: 3, alternatives: ["Cable Curl"]),
            exercise("Overhead Triceps Extension (Dumbbell/Cable)", target: "10-15 reps", sets: 3, alternatives: ["Triceps Pushdown (Cable)"])
        ])
        let dumbbellLowerB = WorkoutRoutine(id: "prebuilt_dumbbell_lower_b", userID: systemUserID, name: "Lower B - Hinge & Carry", dateCreated: now, exercises: [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "8-10 reps", sets: 4, alternatives: ["Barbell Front Squat"]),
            exercise("Glute Bridge", target: "10-15 reps", sets: 4, alternatives: ["Barbell Hip Thrust"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 3, type: .strength, alternatives: ["Plate Pinch"]),
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
            exercise("Pull-up", target: "6-10 reps", sets: 2, alternatives: ["Lat Pulldown"]),
            exercise("Dumbbell Bench Press", target: "3-5 reps", sets: 3, alternatives: ["Barbell Bench Press"]),
            exercise("Incline Dumbbell Bench Press", target: "6-10 reps", sets: 2, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Dumbbell Shoulder Press", target: "6-10 reps", sets: 3, alternatives: ["Barbell Overhead Press (Military Press)"]),
            exercise("Barbell Curl", target: "6-10 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Skull Crusher (Lying Triceps Extension)", target: "6-10 reps", sets: 3, alternatives: ["Overhead Triceps Extension (Dumbbell/Cable)"])
        ])
        let phatLowerPower = WorkoutRoutine(id: "prebuilt_phat_lower_power", userID: systemUserID, name: "Lower Power", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "3-5 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Hack Squat", target: "6-10 reps", sets: 2, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Leg Extension", target: "6-10 reps", sets: 2, alternatives: ["Bulgarian Split Squat"]),
            exercise("Romanian Deadlift", target: "5-8 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Lying Leg Curl", target: "6-10 reps", sets: 2, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "6-10 reps", sets: 3, alternatives: ["Seated Calf Raise"]),
            exercise("Seated Calf Raise", target: "6-10 reps", sets: 2, alternatives: ["Leg Press Calf Raise"])
        ])
        let phatBackShouldersHypertrophy = WorkoutRoutine(id: "prebuilt_phat_back_shoulders", userID: systemUserID, name: "Back/Shoulders Hypertrophy", dateCreated: now, exercises: [
            exercise("Barbell Bent-over Row", target: "10-12 reps", sets: 3, alternatives: ["Pendlay Row"]),
            exercise("Pull-up", target: "10-12 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Seated Cable Row", target: "12-15 reps", sets: 2, alternatives: ["T-Bar Row"]),
            exercise("Dumbbell Pullover", target: "15-20 reps", sets: 2, alternatives: ["Lat Pulldown"]),
            exercise("Dumbbell Shoulder Press", target: "10-12 reps", sets: 3, alternatives: ["Barbell Overhead Press (Military Press)"]),
            exercise("Upright Row", target: "12-15 reps", sets: 2, alternatives: ["Cable Upright Row"]),
            exercise("Dumbbell Lateral Raise", target: "15-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"])
        ])
        let phatLowerHypertrophy = WorkoutRoutine(id: "prebuilt_phat_lower_hypertrophy", userID: systemUserID, name: "Lower Hypertrophy", dateCreated: now, exercises: [
            exercise("Barbell Back Squat", target: "10-12 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Hack Squat", target: "12-15 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Leg Extension", target: "15-20 reps", sets: 3, alternatives: ["Bulgarian Split Squat"]),
            exercise("Romanian Deadlift", target: "10-12 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Lying Leg Curl", target: "15-20 reps", sets: 2, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "15-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let phatChestArmsHypertrophy = WorkoutRoutine(id: "prebuilt_phat_chest_arms", userID: systemUserID, name: "Chest/Arms Hypertrophy", dateCreated: now, exercises: [
            exercise("Dumbbell Bench Press", target: "10-12 reps", sets: 3, alternatives: ["Barbell Bench Press"]),
            exercise("Incline Dumbbell Bench Press", target: "12-15 reps", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Cable Crossover", target: "15-20 reps", sets: 2, alternatives: ["Dumbbell Fly"]),
            exercise("Barbell Curl", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Concentration Curl", target: "12-15 reps", sets: 2, alternatives: ["Preacher Curl"]),
            exercise("Skull Crusher (Lying Triceps Extension)", target: "10-12 reps", sets: 3, alternatives: ["Overhead Triceps Extension (Dumbbell/Cable)"]),
            exercise("Triceps Pushdown (Cable)", target: "12-15 reps", sets: 2, alternatives: ["Triceps Dip"])
        ])
        programs.append(WorkoutProgram(id: "prebuilt_phat", userID: systemUserID, name: "PHAT (Power Hypertrophy Adaptive Training)", dateCreated: now, routines: [phatUpperPower, phatLowerPower, phatBackShouldersHypertrophy, phatLowerHypertrophy, phatChestArmsHypertrophy], daysOfWeek: [2, 3, 5, 6, 7]))

        let basicBeginnerA = routine("prebuilt_basic_beginner_a", "Workout A", [
            exercise("Barbell Bent-over Row", target: "5+ reps", sets: 3, alternatives: ["Dumbbell Row", "Seated Cable Row"]),
            exercise("Barbell Bench Press", target: "5+ reps", sets: 3, alternatives: ["Dumbbell Bench Press", "Machine Chest Press"]),
            exercise("Barbell Back Squat", target: "5+ reps", sets: 3, alternatives: ["Leg Press", "Goblet Squat (Dumbbell/Kettlebell)"])
        ])
        let basicBeginnerB = routine("prebuilt_basic_beginner_b", "Workout B", [
            exercise("Chin-up", target: "5+ reps", sets: 3, alternatives: ["Assisted Pull-up", "Lat Pulldown"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5+ reps", sets: 3, alternatives: ["Dumbbell Shoulder Press", "Machine Shoulder Press"]),
            exercise("Deadlift (Conventional)", target: "5+ reps", sets: 3, alternatives: ["Romanian Deadlift", "Sumo Deadlift"])
        ])
        addProgram(
            "prebuilt_basic_beginner_strength",
            "Basic Beginner Strength",
            routines: [basicBeginnerA, basicBeginnerB],
            days: [2, 4, 6]
        )

        let gzclpDay1 = routine("prebuilt_gzclp_day_1", "Day 1 - Squat Lead", [
            exercise("Barbell Back Squat", target: "3+ reps", sets: 5, alternatives: ["Leg Press"]),
            exercise("Barbell Bench Press", target: "10 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Lat Pulldown", target: "15+ reps", sets: 3, alternatives: ["Assisted Pull-up"])
        ])
        let gzclpDay2 = routine("prebuilt_gzclp_day_2", "Day 2 - Press Lead", [
            exercise("Barbell Overhead Press (Military Press)", target: "3+ reps", sets: 5, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Deadlift (Conventional)", target: "10 reps", sets: 3, alternatives: ["Romanian Deadlift"]),
            exercise("Dumbbell Row", target: "15+ reps / side", sets: 3, alternatives: ["Seated Cable Row"])
        ])
        let gzclpDay3 = routine("prebuilt_gzclp_day_3", "Day 3 - Bench Lead", [
            exercise("Barbell Bench Press", target: "3+ reps", sets: 5, alternatives: ["Dumbbell Bench Press"]),
            exercise("Barbell Back Squat", target: "10 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Lat Pulldown", target: "15+ reps", sets: 3, alternatives: ["Pull-up"])
        ])
        let gzclpDay4 = routine("prebuilt_gzclp_day_4", "Day 4 - Deadlift Lead", [
            exercise("Deadlift (Conventional)", target: "3+ reps", sets: 5, alternatives: ["Sumo Deadlift"]),
            exercise("Barbell Overhead Press (Military Press)", target: "10 reps", sets: 3, alternatives: ["Machine Shoulder Press"]),
            exercise("Dumbbell Row", target: "15+ reps / side", sets: 3, alternatives: ["T-Bar Row"])
        ])
        addProgram(
            "prebuilt_gzclp",
            "GZCLP 3-Day Rotation",
            routines: [gzclpDay1, gzclpDay2, gzclpDay3, gzclpDay4],
            days: [2, 4, 6]
        )

        let fiveThreeOneBeginnerA = routine("prebuilt_531_beginner_a", "Day 1 - Squat & Bench", [
            exercise("Barbell Back Squat", target: "5/3/1 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Barbell Bench Press", target: "5/3/1 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Dumbbell Row", target: "50 total reps", sets: 5, alternatives: ["Seated Cable Row"]),
            exercise("Push-up", target: "50 total reps", sets: 5, alternatives: ["Machine Chest Press"]),
            exercise("Hanging Knee Raise", target: "50 total reps", sets: 5, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let fiveThreeOneBeginnerB = routine("prebuilt_531_beginner_b", "Day 2 - Deadlift & Press", [
            exercise("Deadlift (Conventional)", target: "5/3/1 reps", sets: 3, alternatives: ["Romanian Deadlift"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5/3/1 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Lat Pulldown", target: "50 total reps", sets: 5, alternatives: ["Assisted Pull-up"]),
            exercise("Triceps Pushdown (Cable)", target: "50 total reps", sets: 5, alternatives: ["Bench Dip"]),
            exercise("Bulgarian Split Squat", target: "25 reps / side", sets: 5, alternatives: ["Step-up"])
        ])
        let fiveThreeOneBeginnerC = routine("prebuilt_531_beginner_c", "Day 3 - Bench & Squat", [
            exercise("Barbell Bench Press", target: "5/3/1 reps", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Barbell Back Squat", target: "5/3/1 reps", sets: 3, alternatives: ["Barbell Front Squat"]),
            exercise("Face Pull", target: "50 total reps", sets: 5, alternatives: ["Dumbbell Rear Delt Fly"]),
            exercise("Dumbbell Curl", target: "50 total reps", sets: 5, alternatives: ["Cable Curl"]),
            exercise("Plank", target: "45-60 sec", sets: 5, type: .flexibility, alternatives: ["Side Plank"])
        ])
        addProgram(
            "prebuilt_531_for_beginners",
            "5/3/1 for Beginners",
            routines: [fiveThreeOneBeginnerA, fiveThreeOneBeginnerB, fiveThreeOneBeginnerC],
            days: [2, 4, 6]
        )

        let boringButBigPress = routine("prebuilt_531_bbb_press", "Press + Back Volume", [
            exercise("Barbell Overhead Press (Military Press)", target: "5/3/1 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Barbell Overhead Press (Military Press)", target: "10 reps @ light", sets: 5, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Lat Pulldown", target: "10 reps", sets: 5, alternatives: ["Pull-up"]),
            exercise("Face Pull", target: "15-20 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"])
        ])
        let boringButBigDeadlift = routine("prebuilt_531_bbb_deadlift", "Deadlift + Core Volume", [
            exercise("Deadlift (Conventional)", target: "5/3/1 reps", sets: 3, alternatives: ["Sumo Deadlift"]),
            exercise("Romanian Deadlift", target: "10 reps @ light", sets: 5, alternatives: ["Good Mornings"]),
            exercise("Hanging Knee Raise", target: "10-15 reps", sets: 5, type: .flexibility, alternatives: ["Leg Raise"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 3, alternatives: ["Plate Pinch"])
        ])
        let boringButBigBench = routine("prebuilt_531_bbb_bench", "Bench + Back Volume", [
            exercise("Barbell Bench Press", target: "5/3/1 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Barbell Bench Press", target: "10 reps @ light", sets: 5, alternatives: ["Dumbbell Bench Press"]),
            exercise("Dumbbell Row", target: "10 reps / side", sets: 5, alternatives: ["Seated Cable Row"]),
            exercise("Triceps Pushdown (Cable)", target: "12-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        let boringButBigSquat = routine("prebuilt_531_bbb_squat", "Squat + Core Volume", [
            exercise("Barbell Back Squat", target: "5/3/1 reps", sets: 3, alternatives: ["Barbell Front Squat"]),
            exercise("Barbell Back Squat", target: "10 reps @ light", sets: 5, alternatives: ["Leg Press"]),
            exercise("Cable Crunch", target: "10-15 reps", sets: 5, type: .flexibility, alternatives: ["Crunch"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Seated Calf Raise"])
        ])
        addProgram(
            "prebuilt_531_boring_but_big",
            "5/3/1 Boring But Big",
            routines: [boringButBigPress, boringButBigDeadlift, boringButBigBench, boringButBigSquat],
            days: [2, 3, 5, 6]
        )

        let phulUpperPower = routine("prebuilt_phul_upper_power", "Upper Power", [
            exercise("Barbell Bench Press", target: "3-5 reps", sets: 4, alternatives: ["Dumbbell Bench Press"]),
            exercise("Incline Dumbbell Bench Press", target: "6-10 reps", sets: 4, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Barbell Bent-over Row", target: "3-5 reps", sets: 4, alternatives: ["Pendlay Row"]),
            exercise("Lat Pulldown", target: "6-10 reps", sets: 4, alternatives: ["Pull-up"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5-8 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Barbell Curl", target: "6-10 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Skull Crusher (Lying Triceps Extension)", target: "6-10 reps", sets: 3, alternatives: ["Triceps Pushdown (Cable)"])
        ])
        let phulLowerPower = routine("prebuilt_phul_lower_power", "Lower Power", [
            exercise("Barbell Back Squat", target: "3-5 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Deadlift (Conventional)", target: "3-5 reps", sets: 4, alternatives: ["Romanian Deadlift"]),
            exercise("Leg Press", target: "10-15 reps", sets: 4, alternatives: ["Hack Squat"]),
            exercise("Lying Leg Curl", target: "6-10 reps", sets: 4, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "6-10 reps", sets: 4, alternatives: ["Leg Press Calf Raise"])
        ])
        let phulUpperHypertrophy = routine("prebuilt_phul_upper_hypertrophy", "Upper Hypertrophy", [
            exercise("Incline Barbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Incline Dumbbell Bench Press"]),
            exercise("Dumbbell Fly", target: "8-12 reps", sets: 4, alternatives: ["Machine Fly (Pec Deck)"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Row"]),
            exercise("Dumbbell Row", target: "8-12 reps / side", sets: 4, alternatives: ["T-Bar Row"]),
            exercise("Dumbbell Lateral Raise", target: "8-12 reps", sets: 4, alternatives: ["Cable Lateral Raise"]),
            exercise("Incline Dumbbell Curl", target: "8-12 reps", sets: 4, alternatives: ["Preacher Curl"]),
            exercise("Triceps Pushdown (Cable)", target: "8-12 reps", sets: 4, alternatives: ["Overhead Triceps Extension (Dumbbell/Cable)"])
        ])
        let phulLowerHypertrophy = routine("prebuilt_phul_lower_hypertrophy", "Lower Hypertrophy", [
            exercise("Barbell Front Squat", target: "8-12 reps", sets: 4, alternatives: ["Hack Squat"]),
            exercise("Walking Lunge", target: "8-12 reps / side", sets: 4, alternatives: ["Bulgarian Split Squat"]),
            exercise("Leg Extension", target: "10-15 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Seated Leg Curl", target: "10-15 reps", sets: 4, alternatives: ["Lying Leg Curl"]),
            exercise("Seated Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Standing Calf Raise"])
        ])
        addProgram(
            "prebuilt_phul",
            "PHUL Power Hypertrophy Upper Lower",
            routines: [phulUpperPower, phulLowerPower, phulUpperHypertrophy, phulLowerHypertrophy],
            days: [2, 3, 5, 6]
        )

        let pplPushA = routine("prebuilt_beginner_ppl_push_a", "Push A", [
            exercise("Barbell Bench Press", target: "5 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Barbell Overhead Press (Military Press)", target: "8 reps", sets: 3, alternatives: ["Machine Shoulder Press"]),
            exercise("Incline Dumbbell Bench Press", target: "10 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Dumbbell Lateral Raise", target: "12-15 reps", sets: 3, alternatives: ["Cable Lateral Raise"]),
            exercise("Triceps Pushdown (Cable)", target: "10-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        let pplPullA = routine("prebuilt_beginner_ppl_pull_a", "Pull A", [
            exercise("Deadlift (Conventional)", target: "5 reps", sets: 3, alternatives: ["Romanian Deadlift"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 3, alternatives: ["Assisted Pull-up"]),
            exercise("Seated Cable Row", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Face Pull", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Cable Curl"])
        ])
        let pplLegsA = routine("prebuilt_beginner_ppl_legs_a", "Legs A", [
            exercise("Barbell Back Squat", target: "5 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Leg Press", target: "10-12 reps", sets: 3, alternatives: ["Hack Squat"]),
            exercise("Lying Leg Curl", target: "10-15 reps", sets: 3, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let pplPushB = routine("prebuilt_beginner_ppl_push_b", "Push B", [
            exercise("Incline Barbell Bench Press", target: "6-8 reps", sets: 3, alternatives: ["Incline Dumbbell Bench Press"]),
            exercise("Dumbbell Shoulder Press", target: "8-10 reps", sets: 3, alternatives: ["Machine Shoulder Press"]),
            exercise("Machine Fly (Pec Deck)", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Fly"]),
            exercise("Cable Lateral Raise", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Lateral Raise"]),
            exercise("Overhead Triceps Extension (Dumbbell/Cable)", target: "10-15 reps", sets: 3, alternatives: ["Triceps Pushdown (Cable)"])
        ])
        let pplPullB = routine("prebuilt_beginner_ppl_pull_b", "Pull B", [
            exercise("Barbell Bent-over Row", target: "6-8 reps", sets: 3, alternatives: ["T-Bar Row"]),
            exercise("Pull-up", target: "AMRAP", sets: 3, alternatives: ["Assisted Pull-up", "Lat Pulldown"]),
            exercise("Dumbbell Row", target: "10-12 reps / side", sets: 3, alternatives: ["Seated Cable Row"]),
            exercise("Dumbbell Rear Delt Fly", target: "12-15 reps", sets: 3, alternatives: ["Face Pull"]),
            exercise("Hammer Curl", target: "10-15 reps", sets: 3, alternatives: ["Cable Curl"])
        ])
        let pplLegsB = routine("prebuilt_beginner_ppl_legs_b", "Legs B", [
            exercise("Barbell Front Squat", target: "6-8 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Leg Extension", target: "12-15 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Seated Leg Curl", target: "12-15 reps", sets: 3, alternatives: ["Lying Leg Curl"]),
            exercise("Leg Press Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Standing Calf Raise"])
        ])
        addProgram(
            "prebuilt_beginner_ppl",
            "Beginner Push Pull Legs",
            routines: [pplPushA, pplPullA, pplLegsA, pplPushB, pplPullB, pplLegsB],
            days: [2, 3, 4, 5, 6, 7]
        )

        let bodyweightFoundationA = routine("prebuilt_bodyweight_foundation_a", "Foundation A", [
            exercise("Push-up", target: "8-15 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Inverted Row", target: "8-12 reps", sets: 3, alternatives: ["Assisted Pull-up"]),
            exercise("Bodyweight Squat", target: "12-20 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Glute Bridge", target: "12-20 reps", sets: 3, alternatives: ["Barbell Hip Thrust"]),
            exercise("Plank", target: "30-60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let bodyweightFoundationB = routine("prebuilt_bodyweight_foundation_b", "Foundation B", [
            exercise("Assisted Pull-up", target: "5-10 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Chest Dip", target: "6-12 reps", sets: 3, alternatives: ["Bench Dip", "Push-up"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Reverse Lunge"]),
            exercise("Back Extension (Hyperextension)", target: "12-15 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Side Plank", target: "30-45 sec / side", sets: 3, type: .flexibility, alternatives: ["Bird Dog"])
        ])
        let bodyweightFoundationC = routine("prebuilt_bodyweight_foundation_c", "Foundation C", [
            exercise("Burpee", target: "8-12 reps", sets: 3, type: .cardio, alternatives: ["Mountain Climber"]),
            exercise("Walking Lunge", target: "10-15 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Inverted Row", target: "AMRAP", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Hanging Knee Raise", target: "8-15 reps", sets: 3, type: .flexibility, alternatives: ["Leg Raise"])
        ])
        addProgram(
            "prebuilt_bodyweight_foundation",
            "Bodyweight Foundation",
            routines: [bodyweightFoundationA, bodyweightFoundationB, bodyweightFoundationC],
            days: [2, 4, 6]
        )

        let machineFullBodyA = routine("prebuilt_machine_full_body_a", "Machine Full Body A", [
            exercise("Machine Chest Press", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 3, alternatives: ["Assisted Pull-up"]),
            exercise("Leg Press", target: "10-15 reps", sets: 3, alternatives: ["Hack Squat"]),
            exercise("Seated Leg Curl", target: "10-15 reps", sets: 3, alternatives: ["Lying Leg Curl"]),
            exercise("Cable Crunch", target: "10-15 reps", sets: 3, type: .flexibility, alternatives: ["Crunch"])
        ])
        let machineFullBodyB = routine("prebuilt_machine_full_body_b", "Machine Full Body B", [
            exercise("Machine Shoulder Press", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Leg Extension", target: "10-15 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Hip Abduction (Machine)", target: "12-20 reps", sets: 3, alternatives: ["Cable Kickback"]),
            exercise("Treadmill Walk", target: "10-15 min", sets: 1, type: .cardio, alternatives: ["Elliptical"])
        ])
        let machineFullBodyC = routine("prebuilt_machine_full_body_c", "Machine Full Body C", [
            exercise("Machine Fly (Pec Deck)", target: "10-15 reps", sets: 3, alternatives: ["Cable Crossover"]),
            exercise("T-Bar Row", target: "8-12 reps", sets: 3, alternatives: ["Seated Cable Row"]),
            exercise("Hack Squat", target: "8-12 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Leg Press Calf Raise"]),
            exercise("Face Pull", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"])
        ])
        addProgram(
            "prebuilt_machine_gym_full_body",
            "Machine Gym Full Body",
            routines: [machineFullBodyA, machineFullBodyB, machineFullBodyC],
            days: [2, 4, 6]
        )

        let machinePush = routine("prebuilt_machine_ppl_push", "Machine Push", [
            exercise("Machine Chest Press", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Bench Press"]),
            exercise("Machine Shoulder Press", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Machine Fly (Pec Deck)", target: "10-15 reps", sets: 3, alternatives: ["Cable Crossover"]),
            exercise("Cable Lateral Raise", target: "12-20 reps", sets: 3, alternatives: ["Dumbbell Lateral Raise"]),
            exercise("Triceps Pushdown (Cable)", target: "10-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        let machinePull = routine("prebuilt_machine_ppl_pull", "Machine Pull", [
            exercise("Lat Pulldown", target: "8-12 reps", sets: 4, alternatives: ["Assisted Pull-up"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Row"]),
            exercise("Face Pull", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"]),
            exercise("Cable Curl", target: "10-15 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Back Extension (Hyperextension)", target: "12-15 reps", sets: 3, alternatives: ["Good Mornings"])
        ])
        let machineLegs = routine("prebuilt_machine_ppl_legs", "Machine Legs", [
            exercise("Leg Press", target: "8-12 reps", sets: 4, alternatives: ["Hack Squat"]),
            exercise("Leg Extension", target: "10-15 reps", sets: 4, alternatives: ["Bulgarian Split Squat"]),
            exercise("Seated Leg Curl", target: "10-15 reps", sets: 4, alternatives: ["Lying Leg Curl"]),
            exercise("Hip Abduction (Machine)", target: "12-20 reps", sets: 3, alternatives: ["Cable Kickback"]),
            exercise("Leg Press Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Standing Calf Raise"])
        ])
        addProgram(
            "prebuilt_machine_gym_ppl",
            "Machine Gym Push Pull Legs",
            routines: [machinePush, machinePull, machineLegs],
            days: [2, 3, 4, 5, 6, 7]
        )

        let athleticUpperMax = routine("prebuilt_athletic_upper_max", "Upper Strength", [
            exercise("Barbell Bench Press", target: "3-5 reps", sets: 4, alternatives: ["Close-Grip Bench Press"]),
            exercise("Dumbbell Row", target: "8-12 reps / side", sets: 4, alternatives: ["T-Bar Row"]),
            exercise("Dumbbell Shoulder Press", target: "8-10 reps", sets: 3, alternatives: ["Barbell Overhead Press (Military Press)"]),
            exercise("Face Pull", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 3, alternatives: ["Plate Pinch"])
        ])
        let athleticLowerDynamic = routine("prebuilt_athletic_lower_dynamic", "Lower Power", [
            exercise("Power Clean", target: "3 reps", sets: 5, alternatives: ["Hang Clean"]),
            exercise("Barbell Back Squat", target: "5 reps", sets: 4, alternatives: ["Barbell Front Squat"]),
            exercise("Romanian Deadlift", target: "6-8 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Walking Lunge", target: "8-10 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Plank", target: "45-60 sec", sets: 3, type: .flexibility, alternatives: ["Side Plank"])
        ])
        let athleticUpperRepetition = routine("prebuilt_athletic_upper_repetition", "Upper Volume", [
            exercise("Incline Dumbbell Bench Press", target: "10-15 reps", sets: 4, alternatives: ["Push-up"]),
            exercise("Pull-up", target: "AMRAP", sets: 4, alternatives: ["Assisted Pull-up"]),
            exercise("Dumbbell Lateral Raise", target: "12-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"]),
            exercise("Barbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Triceps Dip", target: "8-12 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        let athleticLowerConditioning = routine("prebuilt_athletic_lower_conditioning", "Lower Conditioning", [
            exercise("Kettlebell Swing", target: "15 reps", sets: 5, alternatives: ["Romanian Deadlift"]),
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "10-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Step-up", target: "10 reps / side", sets: 3, alternatives: ["Reverse Lunge"]),
            exercise("Rowing Machine", target: "500 m", sets: 4, type: .cardio, alternatives: ["Stationary Bike"]),
            exercise("Dead Bug", target: "8-12 reps / side", sets: 3, type: .flexibility, alternatives: ["Bird Dog"])
        ])
        addProgram(
            "prebuilt_athletic_strength_builder",
            "Athletic Strength Builder",
            routines: [athleticUpperMax, athleticLowerDynamic, athleticUpperRepetition, athleticLowerConditioning],
            days: [2, 3, 5, 6]
        )

        let gvtChestBack = routine("prebuilt_gvt_chest_back", "Chest & Back 10x10", [
            exercise("Barbell Bench Press", target: "10 reps", sets: 10, alternatives: ["Dumbbell Bench Press"]),
            exercise("Barbell Bent-over Row", target: "10 reps", sets: 10, alternatives: ["Seated Cable Row"]),
            exercise("Incline Dumbbell Fly", target: "10-12 reps", sets: 3, alternatives: ["Machine Fly (Pec Deck)"]),
            exercise("Lat Pulldown", target: "10-12 reps", sets: 3, alternatives: ["Pull-up"])
        ])
        let gvtLegsCore = routine("prebuilt_gvt_legs_core", "Legs & Core 10x10", [
            exercise("Barbell Back Squat", target: "10 reps", sets: 10, alternatives: ["Leg Press"]),
            exercise("Lying Leg Curl", target: "10 reps", sets: 10, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Seated Calf Raise"]),
            exercise("Cable Crunch", target: "10-15 reps", sets: 4, type: .flexibility, alternatives: ["Crunch"])
        ])
        let gvtShouldersArms = routine("prebuilt_gvt_shoulders_arms", "Shoulders & Arms 10x10", [
            exercise("Dumbbell Shoulder Press", target: "10 reps", sets: 10, alternatives: ["Machine Shoulder Press"]),
            exercise("Barbell Curl", target: "10 reps", sets: 10, alternatives: ["Dumbbell Curl"]),
            exercise("Skull Crusher (Lying Triceps Extension)", target: "10 reps", sets: 10, alternatives: ["Triceps Pushdown (Cable)"]),
            exercise("Dumbbell Lateral Raise", target: "12-20 reps", sets: 3, alternatives: ["Cable Lateral Raise"])
        ])
        addProgram(
            "prebuilt_german_volume_training",
            "German Volume Training",
            routines: [gvtChestBack, gvtLegsCore, gvtShouldersArms],
            days: [2, 4, 6]
        )

        let monolithA = routine("prebuilt_monolith_a", "Monolith A", [
            exercise("Barbell Back Squat", target: "5/3/1 reps", sets: 5, alternatives: ["Leg Press"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5 reps", sets: 5, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Pull-up", target: "50 total reps", sets: 5, alternatives: ["Assisted Pull-up"]),
            exercise("Barbell Curl", target: "10 reps", sets: 5, alternatives: ["Dumbbell Curl"]),
            exercise("Face Pull", target: "15-20 reps", sets: 5, alternatives: ["Dumbbell Rear Delt Fly"])
        ])
        let monolithB = routine("prebuilt_monolith_b", "Monolith B", [
            exercise("Deadlift (Conventional)", target: "5/3/1 reps", sets: 5, alternatives: ["Romanian Deadlift"]),
            exercise("Barbell Bench Press", target: "5 reps", sets: 5, alternatives: ["Dumbbell Bench Press"]),
            exercise("Dumbbell Row", target: "10 reps / side", sets: 5, alternatives: ["Seated Cable Row"]),
            exercise("Triceps Pushdown (Cable)", target: "10-15 reps", sets: 5, alternatives: ["Bench Dip"]),
            exercise("Hanging Leg Raise", target: "10-15 reps", sets: 5, type: .flexibility, alternatives: ["Leg Raise"])
        ])
        let monolithC = routine("prebuilt_monolith_c", "Monolith C", [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Barbell Front Squat"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5/3/1 reps", sets: 5, alternatives: ["Machine Shoulder Press"]),
            exercise("Chin-up", target: "50 total reps", sets: 5, alternatives: ["Lat Pulldown"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 5, alternatives: ["Plate Pinch"]),
            exercise("Brisk Walk", target: "20-30 min", sets: 1, type: .cardio, alternatives: ["Stationary Bike"])
        ])
        addProgram(
            "prebuilt_monolith_strength_size",
            "Monolith Strength & Size",
            routines: [monolithA, monolithB, monolithC],
            days: [2, 4, 6]
        )

        let gluteStrength = routine("prebuilt_glute_growth_strength", "Glute Strength", [
            exercise("Barbell Hip Thrust", target: "6-8 reps", sets: 4, alternatives: ["Glute Bridge"]),
            exercise("Barbell Back Squat", target: "6-8 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 3, alternatives: ["Good Mornings"]),
            exercise("Hip Abduction (Machine)", target: "12-20 reps", sets: 3, alternatives: ["Cable Kickback"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Seated Calf Raise"])
        ])
        let gluteUpperSupport = routine("prebuilt_glute_growth_upper", "Upper Support", [
            exercise("Dumbbell Bench Press", target: "8-12 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 3, alternatives: ["Assisted Pull-up"]),
            exercise("Dumbbell Shoulder Press", target: "8-12 reps", sets: 3, alternatives: ["Machine Shoulder Press"]),
            exercise("Seated Cable Row", target: "10-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Face Pull", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Rear Delt Fly"])
        ])
        let gluteHypertrophy = routine("prebuilt_glute_growth_hypertrophy", "Glute Hypertrophy", [
            exercise("Leg Press", target: "10-15 reps", sets: 4, alternatives: ["Hack Squat"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Cable Pull-through", target: "12-15 reps", sets: 3, alternatives: ["Glute Bridge"]),
            exercise("Cable Kickback", target: "12-20 reps / side", sets: 3, alternatives: ["Hip Abduction (Machine)"]),
            exercise("Frog Pump", target: "20-30 reps", sets: 3, alternatives: ["Glute Bridge"])
        ])
        let gluteLowerPump = routine("prebuilt_glute_growth_pump", "Lower Pump", [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "12-15 reps", sets: 4, alternatives: ["Sumo Squat"]),
            exercise("Reverse Lunge", target: "10-12 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Seated Leg Curl", target: "12-15 reps", sets: 3, alternatives: ["Lying Leg Curl"]),
            exercise("Hip Abduction (Machine)", target: "15-25 reps", sets: 4, alternatives: ["Cable Kickback"]),
            exercise("Side Plank", target: "30-45 sec / side", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        addProgram(
            "prebuilt_glute_lower_growth",
            "Glute & Lower Body Growth",
            routines: [gluteStrength, gluteUpperSupport, gluteHypertrophy, gluteLowerPump],
            days: [2, 3, 5, 6]
        )

        let busyStrengthA = routine("prebuilt_busy_strength_a", "Full Body A", [
            exercise("Barbell Back Squat", target: "5 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Barbell Bench Press", target: "5 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Dumbbell Row", target: "8-12 reps / side", sets: 3, alternatives: ["Seated Cable Row"]),
            exercise("Plank", target: "45-60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let busyStrengthB = routine("prebuilt_busy_strength_b", "Full Body B", [
            exercise("Deadlift (Conventional)", target: "5 reps", sets: 3, alternatives: ["Romanian Deadlift"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 3, alternatives: ["Pull-up"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 3, alternatives: ["Plate Pinch"])
        ])
        let busyStrengthC = routine("prebuilt_busy_strength_c", "Full Body C", [
            exercise("Barbell Front Squat", target: "5 reps", sets: 3, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Incline Dumbbell Bench Press", target: "8-10 reps", sets: 3, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 3, alternatives: ["Barbell Bent-over Row"]),
            exercise("Hanging Knee Raise", target: "8-15 reps", sets: 3, type: .flexibility, alternatives: ["Leg Raise"])
        ])
        addProgram(
            "prebuilt_busy_professional_strength",
            "Busy Professional 3-Day Strength",
            routines: [busyStrengthA, busyStrengthB, busyStrengthC],
            days: [2, 4, 6]
        )

        let upperLowerUpperA = routine("prebuilt_rotating_upper_lower_upper_a", "Upper A", [
            exercise("Barbell Bench Press", target: "5-8 reps", sets: 4, alternatives: ["Dumbbell Bench Press"]),
            exercise("Barbell Bent-over Row", target: "5-8 reps", sets: 4, alternatives: ["Dumbbell Row"]),
            exercise("Dumbbell Shoulder Press", target: "8-10 reps", sets: 3, alternatives: ["Machine Shoulder Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 3, alternatives: ["Pull-up"]),
            exercise("Triceps Pushdown (Cable)", target: "10-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        let upperLowerLower = routine("prebuilt_rotating_upper_lower_lower", "Lower", [
            exercise("Barbell Back Squat", target: "5-8 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 4, alternatives: ["Good Mornings"]),
            exercise("Walking Lunge", target: "10 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 3, alternatives: ["Seated Calf Raise"]),
            exercise("Cable Crunch", target: "10-15 reps", sets: 3, type: .flexibility, alternatives: ["Crunch"])
        ])
        let upperLowerUpperB = routine("prebuilt_rotating_upper_lower_upper_b", "Upper B", [
            exercise("Barbell Overhead Press (Military Press)", target: "5-8 reps", sets: 4, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Pull-up", target: "AMRAP", sets: 4, alternatives: ["Assisted Pull-up"]),
            exercise("Incline Dumbbell Bench Press", target: "8-12 reps", sets: 3, alternatives: ["Machine Chest Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Row"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Cable Curl"])
        ])
        let upperLowerLowerB = routine("prebuilt_rotating_upper_lower_lower_b", "Lower B", [
            exercise("Deadlift (Conventional)", target: "3-5 reps", sets: 3, alternatives: ["Romanian Deadlift"]),
            exercise("Barbell Front Squat", target: "6-8 reps", sets: 4, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Bulgarian Split Squat", target: "8-12 reps / side", sets: 3, alternatives: ["Reverse Lunge"]),
            exercise("Seated Leg Curl", target: "10-15 reps", sets: 3, alternatives: ["Lying Leg Curl"]),
            exercise("Hanging Knee Raise", target: "8-15 reps", sets: 3, type: .flexibility, alternatives: ["Leg Raise"])
        ])
        addProgram(
            "prebuilt_rotating_upper_lower_3_day",
            "Upper/Lower 3-Day Rotation",
            routines: [upperLowerUpperA, upperLowerLower, upperLowerUpperB, upperLowerLowerB],
            days: [2, 4, 6]
        )

        let fatLossStrengthA = routine("prebuilt_fat_loss_strength_a", "Strength Circuit A", [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "10-12 reps", sets: 4, alternatives: ["Leg Press"]),
            exercise("Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Push-up"]),
            exercise("Dumbbell Row", target: "10-12 reps / side", sets: 4, alternatives: ["Seated Cable Row"]),
            exercise("Kettlebell Swing", target: "15 reps", sets: 4, alternatives: ["Romanian Deadlift"]),
            exercise("Mountain Climber", target: "30-45 sec", sets: 4, type: .cardio, alternatives: ["High Knees"])
        ])
        let fatLossConditioningA = routine("prebuilt_fat_loss_conditioning_a", "Intervals", [
            exercise("Rowing Machine", target: "250 m hard", sets: 6, type: .cardio, alternatives: ["Stationary Bike"]),
            exercise("Burpee", target: "8-10 reps", sets: 5, type: .cardio, alternatives: ["High Knees"]),
            exercise("Jump Rope", target: "45 sec", sets: 5, type: .cardio, alternatives: ["Treadmill Run"]),
            exercise("Plank", target: "45 sec", sets: 4, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let fatLossStrengthB = routine("prebuilt_fat_loss_strength_b", "Strength Circuit B", [
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 4, alternatives: ["Good Mornings"]),
            exercise("Dumbbell Shoulder Press", target: "8-12 reps", sets: 4, alternatives: ["Machine Shoulder Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 4, alternatives: ["Assisted Pull-up"]),
            exercise("Reverse Lunge", target: "10 reps / side", sets: 4, alternatives: ["Walking Lunge"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 4, alternatives: ["Plate Pinch"])
        ])
        let fatLossZone2 = routine("prebuilt_fat_loss_zone_2", "Zone 2 Base", [
            exercise("Treadmill Walk", target: "25-35 min", sets: 1, type: .cardio, alternatives: ["Elliptical"]),
            exercise("Stationary Bike", target: "15-25 min", sets: 1, type: .cardio, alternatives: ["Rowing Machine"]),
            exercise("World's Greatest Stretch", target: "5 reps / side", sets: 2, type: .flexibility),
            exercise("Hip Flexor Stretch", target: "45 sec / side", sets: 2, type: .flexibility)
        ])
        addProgram(
            "prebuilt_fat_loss_strength_conditioning",
            "Fat Loss Strength + Conditioning",
            routines: [fatLossStrengthA, fatLossConditioningA, fatLossStrengthB, fatLossZone2],
            days: [2, 3, 5, 6]
        )

        let dumbbellBeginnerA = routine("prebuilt_dumbbell_beginner_a", "Dumbbell A", [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "10-12 reps", sets: 3, alternatives: ["Bodyweight Squat"]),
            exercise("Dumbbell Bench Press", target: "8-12 reps", sets: 3, alternatives: ["Push-up"]),
            exercise("Dumbbell Row", target: "10-12 reps / side", sets: 3, alternatives: ["Inverted Row"]),
            exercise("Dumbbell Shoulder Press", target: "8-12 reps", sets: 3, alternatives: ["Arnold Press"]),
            exercise("Dead Bug", target: "8-12 reps / side", sets: 3, type: .flexibility, alternatives: ["Plank"])
        ])
        let dumbbellBeginnerB = routine("prebuilt_dumbbell_beginner_b", "Dumbbell B", [
            exercise("Romanian Deadlift", target: "8-12 reps", sets: 3, alternatives: ["Glute Bridge"]),
            exercise("Incline Dumbbell Bench Press", target: "8-12 reps", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Reverse Lunge", target: "8-12 reps / side", sets: 3, alternatives: ["Step-up"]),
            exercise("Dumbbell Lateral Raise", target: "12-15 reps", sets: 3, alternatives: ["Dumbbell Front Raise"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 3, alternatives: ["Plate Pinch"])
        ])
        let dumbbellBeginnerC = routine("prebuilt_dumbbell_beginner_c", "Dumbbell C", [
            exercise("Bulgarian Split Squat", target: "8-10 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Dumbbell Pullover", target: "10-15 reps", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Push-up", target: "AMRAP", sets: 3, alternatives: ["Dumbbell Bench Press"]),
            exercise("Hammer Curl", target: "10-15 reps", sets: 3, alternatives: ["Dumbbell Curl"]),
            exercise("Overhead Triceps Extension (Dumbbell/Cable)", target: "10-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        addProgram(
            "prebuilt_beginner_dumbbell_only",
            "Beginner Dumbbell Only 3-Day",
            routines: [dumbbellBeginnerA, dumbbellBeginnerB, dumbbellBeginnerC],
            days: [2, 4, 6]
        )

        let kettlebellBodyweightA = routine("prebuilt_kb_bodyweight_a", "Swing & Push", [
            exercise("Kettlebell Swing", target: "15 reps", sets: 5, alternatives: ["Romanian Deadlift"]),
            exercise("Push-up", target: "8-15 reps", sets: 4, alternatives: ["Dumbbell Bench Press"]),
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "10-12 reps", sets: 4, alternatives: ["Bodyweight Squat"]),
            exercise("Dumbbell Row", target: "10 reps / side", sets: 4, alternatives: ["Inverted Row"]),
            exercise("Mountain Climber", target: "30 sec", sets: 4, type: .cardio, alternatives: ["High Knees"])
        ])
        let kettlebellBodyweightB = routine("prebuilt_kb_bodyweight_b", "Clean & Lunge", [
            exercise("Clean and Press", target: "5 reps / side", sets: 5, alternatives: ["Dumbbell Snatch"]),
            exercise("Reverse Lunge", target: "8-10 reps / side", sets: 4, alternatives: ["Walking Lunge"]),
            exercise("Pull-up", target: "AMRAP", sets: 4, alternatives: ["Assisted Pull-up"]),
            exercise("Glute Bridge", target: "15-20 reps", sets: 4, alternatives: ["Barbell Hip Thrust"]),
            exercise("Side Plank", target: "30-45 sec / side", sets: 3, type: .flexibility, alternatives: ["Bird Dog"])
        ])
        let kettlebellBodyweightC = routine("prebuilt_kb_bodyweight_c", "Engine Day", [
            exercise("Dumbbell Snatch", target: "6 reps / side", sets: 5, alternatives: ["Kettlebell Swing"]),
            exercise("Burpee", target: "8-10 reps", sets: 5, type: .cardio, alternatives: ["High Knees"]),
            exercise("Step-up", target: "10 reps / side", sets: 4, alternatives: ["Walking Lunge"]),
            exercise("Rowing Machine", target: "500 m", sets: 3, type: .cardio, alternatives: ["Stationary Bike"]),
            exercise("Dead Bug", target: "10 reps / side", sets: 3, type: .flexibility, alternatives: ["Plank"])
        ])
        addProgram(
            "prebuilt_kettlebell_bodyweight_conditioning",
            "Kettlebell + Bodyweight Conditioning",
            routines: [kettlebellBodyweightA, kettlebellBodyweightB, kettlebellBodyweightC],
            days: [2, 4, 6]
        )

        let zone2MobilityA = routine("prebuilt_zone2_mobility_a", "Zone 2 + Hips", [
            exercise("Brisk Walk", target: "30-40 min", sets: 1, type: .cardio, alternatives: ["Treadmill Walk"]),
            exercise("World's Greatest Stretch", target: "5 reps / side", sets: 2, type: .flexibility),
            exercise("Hip Flexor Stretch", target: "45 sec / side", sets: 2, type: .flexibility),
            exercise("Dead Bug", target: "8-12 reps / side", sets: 3, type: .flexibility)
        ])
        let zone2MobilityB = routine("prebuilt_zone2_mobility_b", "Bike + Shoulders", [
            exercise("Stationary Bike", target: "30-40 min", sets: 1, type: .cardio, alternatives: ["Elliptical"]),
            exercise("Wall Slide", target: "10-12 reps", sets: 2, type: .flexibility),
            exercise("Scapular Push-up", target: "10-12 reps", sets: 2, type: .strength),
            exercise("Thoracic Rotation", target: "8 reps / side", sets: 2, type: .flexibility)
        ])
        let zone2MobilityC = routine("prebuilt_zone2_mobility_c", "Row + Core", [
            exercise("Rowing Machine", target: "20-30 min easy", sets: 1, type: .cardio, alternatives: ["Treadmill Walk"]),
            exercise("Couch Stretch", target: "45 sec / side", sets: 2, type: .flexibility),
            exercise("Bird Dog", target: "8-12 reps / side", sets: 3, type: .flexibility),
            exercise("Child's Pose Breathing", target: "2 min", sets: 1, type: .flexibility)
        ])
        addProgram(
            "prebuilt_mobility_zone2_base",
            "Mobility + Zone 2 Base Builder",
            routines: [zone2MobilityA, zone2MobilityB, zone2MobilityC],
            days: [2, 4, 6]
        )

        let returnRampA = routine("prebuilt_return_ramp_a", "Ramp A", [
            exercise("Bodyweight Squat", target: "8-12 reps", sets: 2, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Push-up", target: "6-12 reps", sets: 2, alternatives: ["Machine Chest Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 2, alternatives: ["Dumbbell Row"]),
            exercise("Glute Bridge", target: "10-15 reps", sets: 2, alternatives: ["Barbell Hip Thrust"]),
            exercise("Brisk Walk", target: "10-15 min", sets: 1, type: .cardio, alternatives: ["Stationary Bike"])
        ])
        let returnRampB = routine("prebuilt_return_ramp_b", "Ramp B", [
            exercise("Goblet Squat (Dumbbell/Kettlebell)", target: "8-10 reps", sets: 2, alternatives: ["Leg Press"]),
            exercise("Dumbbell Shoulder Press", target: "8-10 reps", sets: 2, alternatives: ["Machine Shoulder Press"]),
            exercise("Lat Pulldown", target: "8-12 reps", sets: 2, alternatives: ["Assisted Pull-up"]),
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 2, alternatives: ["Good Mornings"]),
            exercise("Dead Bug", target: "8 reps / side", sets: 2, type: .flexibility, alternatives: ["Bird Dog"])
        ])
        let returnRampC = routine("prebuilt_return_ramp_c", "Ramp C", [
            exercise("Leg Press", target: "10-12 reps", sets: 2, alternatives: ["Bodyweight Squat"]),
            exercise("Dumbbell Bench Press", target: "8-10 reps", sets: 2, alternatives: ["Push-up"]),
            exercise("Dumbbell Row", target: "8-10 reps / side", sets: 2, alternatives: ["Seated Cable Row"]),
            exercise("Step-up", target: "8 reps / side", sets: 2, alternatives: ["Reverse Lunge"]),
            exercise("World's Greatest Stretch", target: "5 reps / side", sets: 2, type: .flexibility)
        ])
        addProgram(
            "prebuilt_return_to_training_ramp",
            "Return to Training Ramp",
            routines: [returnRampA, returnRampB, returnRampC],
            days: [2, 4, 6]
        )

        let powerbuildingUpperStrength = routine("prebuilt_powerbuilding_upper_strength", "Upper Strength", [
            exercise("Barbell Bench Press", target: "3-5 reps", sets: 4, alternatives: ["Close-Grip Bench Press"]),
            exercise("Barbell Bent-over Row", target: "5-8 reps", sets: 4, alternatives: ["Pendlay Row"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5-8 reps", sets: 3, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Pull-up", target: "AMRAP", sets: 3, alternatives: ["Lat Pulldown"]),
            exercise("Triceps Pushdown (Cable)", target: "10-15 reps", sets: 3, alternatives: ["Skull Crusher (Lying Triceps Extension)"])
        ])
        let powerbuildingLowerStrength = routine("prebuilt_powerbuilding_lower_strength", "Lower Strength", [
            exercise("Barbell Back Squat", target: "3-5 reps", sets: 4, alternatives: ["Barbell Front Squat"]),
            exercise("Deadlift (Conventional)", target: "3-5 reps", sets: 3, alternatives: ["Sumo Deadlift"]),
            exercise("Leg Press", target: "8-12 reps", sets: 3, alternatives: ["Hack Squat"]),
            exercise("Lying Leg Curl", target: "10-12 reps", sets: 3, alternatives: ["Seated Leg Curl"]),
            exercise("Standing Calf Raise", target: "12-20 reps", sets: 4, alternatives: ["Seated Calf Raise"])
        ])
        let powerbuildingUpperVolume = routine("prebuilt_powerbuilding_upper_volume", "Upper Volume", [
            exercise("Incline Dumbbell Bench Press", target: "8-12 reps", sets: 4, alternatives: ["Incline Barbell Bench Press"]),
            exercise("Seated Cable Row", target: "8-12 reps", sets: 4, alternatives: ["Dumbbell Row"]),
            exercise("Dumbbell Fly", target: "12-15 reps", sets: 3, alternatives: ["Machine Fly (Pec Deck)"]),
            exercise("Dumbbell Lateral Raise", target: "12-20 reps", sets: 4, alternatives: ["Cable Lateral Raise"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Hammer Curl"])
        ])
        let powerbuildingLowerVolume = routine("prebuilt_powerbuilding_lower_volume", "Lower Volume", [
            exercise("Barbell Front Squat", target: "8-12 reps", sets: 4, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Romanian Deadlift", target: "8-12 reps", sets: 4, alternatives: ["Good Mornings"]),
            exercise("Bulgarian Split Squat", target: "10 reps / side", sets: 3, alternatives: ["Walking Lunge"]),
            exercise("Leg Extension", target: "12-15 reps", sets: 3, alternatives: ["Leg Press"]),
            exercise("Cable Crunch", target: "10-15 reps", sets: 3, type: .flexibility, alternatives: ["Crunch"])
        ])
        addProgram(
            "prebuilt_powerbuilding_4_day",
            "Powerbuilding 4-Day",
            routines: [powerbuildingUpperStrength, powerbuildingLowerStrength, powerbuildingUpperVolume, powerbuildingLowerVolume],
            days: [2, 3, 5, 6]
        )

        let garageGymA = routine("prebuilt_garage_gym_a", "Garage A", [
            exercise("Barbell Back Squat", target: "5 reps", sets: 5, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Barbell Bench Press", target: "5 reps", sets: 5, alternatives: ["Push-up"]),
            exercise("Dumbbell Row", target: "10 reps / side", sets: 4, alternatives: ["Inverted Row"]),
            exercise("Plank", target: "45-60 sec", sets: 3, type: .flexibility, alternatives: ["Dead Bug"])
        ])
        let garageGymB = routine("prebuilt_garage_gym_b", "Garage B", [
            exercise("Deadlift (Conventional)", target: "3-5 reps", sets: 5, alternatives: ["Romanian Deadlift"]),
            exercise("Barbell Overhead Press (Military Press)", target: "5 reps", sets: 5, alternatives: ["Dumbbell Shoulder Press"]),
            exercise("Pull-up", target: "AMRAP", sets: 4, alternatives: ["Inverted Row"]),
            exercise("Farmer's Carry", target: "30-45 sec", sets: 4, alternatives: ["Plate Pinch"])
        ])
        let garageGymC = routine("prebuilt_garage_gym_c", "Garage C", [
            exercise("Barbell Front Squat", target: "5 reps", sets: 5, alternatives: ["Goblet Squat (Dumbbell/Kettlebell)"]),
            exercise("Incline Dumbbell Bench Press", target: "8-10 reps", sets: 4, alternatives: ["Dumbbell Bench Press"]),
            exercise("Romanian Deadlift", target: "8-10 reps", sets: 4, alternatives: ["Good Mornings"]),
            exercise("Dumbbell Curl", target: "10-15 reps", sets: 3, alternatives: ["Hammer Curl"]),
            exercise("Skull Crusher (Lying Triceps Extension)", target: "10-15 reps", sets: 3, alternatives: ["Bench Dip"])
        ])
        addProgram(
            "prebuilt_minimalist_garage_gym",
            "Minimalist Garage Gym 3-Day",
            routines: [garageGymA, garageGymB, garageGymC],
            days: [2, 4, 6]
        )

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
