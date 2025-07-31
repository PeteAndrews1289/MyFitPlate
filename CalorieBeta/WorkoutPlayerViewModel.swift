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

    func startTimers() {
        totalWorkoutTimer.start()
    }

    func stopTimers() {
        restTimer.stop()
        totalWorkoutTimer.stop()
    }

    func loadPreviousPerformance() {
        Task {
            for exercise in routine.exercises {
                if let performance = await workoutService.fetchPreviousPerformance(for: exercise.name) {
                    previousPerformance[exercise.name] = performance
                }
            }
        }
    }

    func moveExercise(from source: IndexSet, to destination: Int) {
        routine.exercises.move(fromOffsets: source, toOffset: destination)
    }

    func logAllCompletedExercises() {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        let completedExercisesForLog = routine.exercises.compactMap { exercise -> CompletedExercise? in
            let completedSets = exercise.sets.filter { $0.isCompleted }.map {
                CompletedSet(reps: $0.reps, weight: $0.weight, distance: $0.distance, durationInSeconds: $0.durationInSeconds)
            }
            return completedSets.isEmpty ? nil : CompletedExercise(exerciseName: exercise.name, sets: completedSets)
        }

        if !completedExercisesForLog.isEmpty {
            let sessionLog = WorkoutSessionLog(
                date: Timestamp(date: Date()),
                routineID: routine.id,
                completedExercises: completedExercisesForLog
            )
            Task {
                await workoutService.saveWorkoutSessionLog(sessionLog)
            }
        }

        for exercise in routine.exercises {
            let completedSets = exercise.sets.filter { $0.isCompleted }
            if completedSets.isEmpty { continue }

            let totalCaloriesBurned = completedSets.reduce(0.0) { partialResult, set in
                let bodyweightKg = goalSettings.weight * 0.453592
                return partialResult + (5.0 * 3.5 * bodyweightKg) / 200
            }

            if totalCaloriesBurned > 0 {
                let loggedExercise = LoggedExercise(
                    name: exercise.name,
                    durationMinutes: nil,
                    caloriesBurned: totalCaloriesBurned,
                    date: Date(),
                    source: "routine"
                )
                dailyLogService.addExerciseToLog(for: userID, exercise: loggedExercise)
            }
        }
    }

    func saveRoutine() async {
        try? await workoutService.saveRoutine(routine)
    }
}

