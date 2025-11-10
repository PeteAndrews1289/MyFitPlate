
import Foundation
import FirebaseFirestore
import FirebaseAuth

// This struct holds the calculated analytics for a user's workouts over a period.
struct WorkoutAnalytics {
    let totalVolume: Double
    let personalRecords: [String: String]
}

// This service is responsible for calculating advanced workout statistics.
@MainActor
class WorkoutAnalyticsService {
    private let workoutService = WorkoutService()

    func calculateAnalytics(for logs: [DailyLog]) async -> WorkoutAnalytics {
        var totalVolume: Double = 0
        var personalRecords: [String: (weight: Double, reps: Int)] = [:]

        // We need to fetch the detailed session logs for each workout logged in the period.
        let allLoggedExercises = logs.flatMap { $0.exercises ?? [] }
        
        for loggedExercise in allLoggedExercises {
            // Ensure the logged exercise is from a routine to have a session log.
            guard let workoutID = loggedExercise.workoutID, let sessionID = loggedExercise.sessionID else { continue }
            
            let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)
            
            if case .success(let sessionLog) = sessionResult {
                for completedExercise in sessionLog.completedExercises {
                    for set in completedExercise.sets {
                        let volume = set.weight * Double(set.reps)
                        totalVolume += volume
                        
                        let exerciseName = completedExercise.exercise.name
                        if let currentPR = personalRecords[exerciseName] {
                            // A simple check for a new personal record (heaviest weight for any reps).
                            if set.weight > currentPR.weight {
                                personalRecords[exerciseName] = (weight: set.weight, reps: set.reps)
                            }
                        } else {
                            personalRecords[exerciseName] = (weight: set.weight, reps: set.reps)
                        }
                    }
                }
            }
        }
        
        // Format the personal records into readable strings.
        let prStrings = personalRecords.mapValues { String(format: "%.1f lbs x %d reps", $0.weight, $0.reps) }
        
        return WorkoutAnalytics(totalVolume: totalVolume, personalRecords: prStrings)
    }
}
