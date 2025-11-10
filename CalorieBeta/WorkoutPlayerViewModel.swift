import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class WorkoutPlayerViewModel: ObservableObject {
    @Published var routine: WorkoutRoutine
    @Published var restTimer: RestTimer
    @Published var totalWorkoutTimer: TotalWorkoutTimer
    @Published var previousPerformance: [String: CompletedExercise] = [:]

    private let workoutService: WorkoutService
    private let goalSettings: GoalSettings
    private let dailyLogService: DailyLogService

    init(routine: WorkoutRoutine, workoutService: WorkoutService, goalSettings: GoalSettings, dailyLogService: DailyLogService) {
        self.routine = routine
        self.workoutService = workoutService
        self.goalSettings = goalSettings
        self.dailyLogService = dailyLogService
        self.restTimer = RestTimer()
        self.totalWorkoutTimer = TotalWorkoutTimer(routineId: routine.id)
    }

    // Start workout timers
    func startTimers() {
        totalWorkoutTimer.start()
    }

    // Stop workout timers
    func stopTimers() {
        restTimer.stop()
        totalWorkoutTimer.stop()
    }

    // Load previous performance data for exercises in the routine
    func loadPreviousPerformance() {
        Task {
            for exercise in routine.exercises {
                if let performance = await workoutService.fetchPreviousPerformance(for: exercise.name) {
                    previousPerformance[exercise.name] = performance
                }
            }
        }
    }

    // Reorder exercises within the routine
    func moveExercise(from source: IndexSet, to destination: Int) {
        routine.exercises.move(fromOffsets: source, toOffset: destination)
    }

    // Log completed exercises to Firestore and DailyLogService
    func logAllCompletedExercises() {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        let completedExercisesForLog = routine.exercises.compactMap { exercise -> CompletedExercise? in
            let completedSets = exercise.sets.filter { $0.isCompleted }.map {
                CompletedSet(reps: $0.reps, weight: $0.weight, distance: $0.distance, durationInSeconds: $0.durationInSeconds)
            }
            // Ensure non-empty sets and pass the exercise object
            return completedSets.isEmpty ? nil : CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: completedSets) // Corrected line
        }

        let newSessionID = UUID().uuidString

        // Save session log if exercises were completed
        if !completedExercisesForLog.isEmpty {
            let sessionLog = WorkoutSessionLog(
                id: newSessionID, // Assign ID for potential reference
                date: Timestamp(date: Date()),
                routineID: routine.id,
                completedExercises: completedExercisesForLog
            )
            Task {
                await workoutService.saveWorkoutSessionLog(sessionLog)
                // Assuming achievementService is accessible or passed in
                // achievementService.checkWorkoutCountAchievements(userID: userID)
            }
        }

        // Log exercises with calculated calories burned to daily log
        for exercise in routine.exercises {
            let completedSets = exercise.sets.filter { $0.isCompleted }
            if completedSets.isEmpty { continue }

            // Simple MET-based calorie calculation (adjust MET value as needed per exercise type)
            let metValue: Double = 5.0 // Example MET value for general strength training
            let bodyweightKg = goalSettings.weight * 0.453592 // Convert lbs to kg
            // Estimate duration based on sets (e.g., 1 minute per set) - refine this logic if possible
            let estimatedDurationMinutes = Double(completedSets.count) * 1.0
            let totalCaloriesBurned = (metValue * 3.5 * bodyweightKg) / 200.0 * estimatedDurationMinutes


            if totalCaloriesBurned > 0 {
                let loggedExercise = LoggedExercise(
                    name: exercise.name,
                    durationMinutes: Int(estimatedDurationMinutes), // Log estimated duration
                    caloriesBurned: totalCaloriesBurned,
                    date: Date(),
                    source: "routine",
                    workoutID: routine.id, // Link back to the routine
                    sessionID: newSessionID // Link back to the specific session
                )
                dailyLogService.addExerciseToLog(for: userID, exercise: loggedExercise)
            }
        }
    }

    // Save the current state of the routine
    func saveRoutine() async {
        try? await workoutService.saveRoutine(routine)
    }
}
