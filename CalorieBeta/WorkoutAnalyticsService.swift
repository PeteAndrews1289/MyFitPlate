import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

// MARK: - Data Models for Analytics

struct WorkoutAnalytics {
    let totalVolume: Double
    let personalRecords: [String: String]
    let aiInsights: [WorkoutAnalysisInsight]
}

struct WorkoutAnalysisInsight: Decodable, Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
    let category: String

    private enum CodingKeys: String, CodingKey {
        case title, message, category
    }
}

private struct AIWorkoutInsightResponse: Decodable {
    let insights: [WorkoutAnalysisInsight]
}

// MARK: - New Analytics Models
struct ExerciseTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double // Max Weight or Volume
}

struct WorkoutComparison {
    let volumeDiffPercent: Double
    let durationDiffPercent: Double
    let previousDate: Date?
}

struct MuscleSplitPoint: Identifiable {
    let id = UUID()
    let muscleName: String
    let volume: Double
}

// MARK: - Service Class

@MainActor
class WorkoutAnalyticsService: ObservableObject {
    private let workoutService = WorkoutService()
    private let db = Firestore.firestore()
    
    // MARK: - Core Analytics Calculation (Existing Logic)

    func calculateAnalytics(for logs: [DailyLog], program: WorkoutProgram?) async -> WorkoutAnalytics {
        var totalVolume: Double = 0
        var personalRecords: [String: (weight: Double, reps: Int)] = [:]

        let allLoggedExercises = logs.flatMap { $0.exercises ?? [] }

        for loggedExercise in allLoggedExercises {
            guard let workoutID = loggedExercise.workoutID, let sessionID = loggedExercise.sessionID else { continue }

            let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)

            if case .success(let sessionLog) = sessionResult {
                for completedExercise in sessionLog.completedExercises {
                    for set in completedExercise.sets {
                        let volume = set.weight * Double(set.reps)
                        totalVolume += volume

                        let exerciseName = completedExercise.exerciseName
                        
                        if let currentPR = personalRecords[exerciseName] {
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

        let prStrings = personalRecords.mapValues { String(format: "%.1f lbs x %d reps", $0.weight, $0.reps) }
        let aiInsights = await generateAIWorkoutInsights(for: logs, program: program, analytics: (totalVolume, prStrings))

        return WorkoutAnalytics(totalVolume: totalVolume, personalRecords: prStrings, aiInsights: aiInsights)
    }
    
    func generateAnalyticsForPastSession(sessionID: String, workoutName: String, date: Date) async -> WorkoutAnalytics? {
        let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: "unknown", sessionID: sessionID)
        guard case .success(let sessionLog) = sessionResult else { return nil }
        
        let tempLoggedExercise = LoggedExercise(
            id: UUID().uuidString, name: workoutName, durationMinutes: 0, caloriesBurned: 0, date: date, source: "routine", workoutID: sessionLog.routineID, sessionID: sessionLog.id
        )
        let tempLog = DailyLog(id: "temp", date: date, meals: [], exercises: [tempLoggedExercise])
        
        return await calculateAnalytics(for: [tempLog], program: nil)
    }

    // MARK: - New: History & Trends Features
    
    /// Fetches a paginated list of past workout logs for the History View
    func fetchWorkoutHistory(userID: String, limit: Int = 20) async -> [WorkoutSessionLog] {
        let ref = db.collection("users").document(userID).collection("workoutSessionLogs")
            .order(by: "date", descending: true)
            .limit(to: limit)
        
        do {
            let snapshot = try await ref.getDocuments()
            return snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
        } catch {
            print("❌ Error fetching workout history: \(error)")
            return []
        }
    }

    /// Fetches historical performance for a specific exercise to plot charts
    func fetchTrends(for exerciseName: String, userID: String) async -> [ExerciseTrendPoint] {
        // Query recent logs to find this exercise
        let ref = db.collection("users").document(userID).collection("workoutSessionLogs")
            .order(by: "date", descending: true)
            .limit(to: 30)
            
        do {
            let snapshot = try await ref.getDocuments()
            let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
            
            var points: [ExerciseTrendPoint] = []
            
            // Process logs in reverse (oldest to newest for the chart)
            for log in logs.reversed() {
                if let completedExercise = log.completedExercises.first(where: { $0.exerciseName == exerciseName }) {
                    // Calculate "Max Weight Used" as the metric for the chart
                    let maxWeight = completedExercise.sets.map { $0.weight }.max() ?? 0
                    if maxWeight > 0 {
                        points.append(ExerciseTrendPoint(date: log.date.dateValue(), value: maxWeight))
                    }
                }
            }
            return points
        } catch {
            print("❌ Error fetching trends: \(error)")
            return []
        }
    }

    /// Compares a current session against the last time this Routine ID was logged
    func compareAgainstPrevious(currentLog: WorkoutSessionLog, userID: String) async -> WorkoutComparison? {
        let ref = db.collection("users").document(userID).collection("workoutSessionLogs")
            .whereField("routineID", isEqualTo: currentLog.routineID)
            .order(by: "date", descending: true)
            .limit(to: 2) // [0] is current, [1] is previous
            
        do {
            let snapshot = try await ref.getDocuments()
            let logs = snapshot.documents.compactMap { try? $0.data(as: WorkoutSessionLog.self) }
            
            guard logs.count >= 2 else { return nil }
            
            let previousLog = logs[1]
            let currentVolume = calculateTotalVolume(log: currentLog)
            let previousVolume = calculateTotalVolume(log: previousLog)
            let currentDuration = calculateEstimatedDuration(log: currentLog)
            let previousDuration = calculateEstimatedDuration(log: previousLog)
            
            let volDiff = previousVolume > 0 ? (currentVolume - previousVolume) / previousVolume : 0.0
            let durDiff = previousDuration > 0 ? (Double(currentDuration) - Double(previousDuration)) / Double(previousDuration) : 0.0
            
            return WorkoutComparison(volumeDiffPercent: volDiff, durationDiffPercent: durDiff, previousDate: previousLog.date.dateValue())
        } catch {
            print("❌ Error comparing workouts: \(error)")
            return nil
        }
    }
    
    // Calculates volume distribution by muscle group
    func calculateMuscleSplit(log: WorkoutSessionLog) -> [MuscleSplitPoint] {
        var distribution: [String: Double] = [:]
        
        for exercise in log.completedExercises {
            let muscle = guessMuscleGroup(exerciseName: exercise.exerciseName)
            let vol = exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            distribution[muscle, default: 0] += vol
        }
        
        return distribution.map { MuscleSplitPoint(muscleName: $0.key, volume: $0.value) }
            .sorted { $0.volume > $1.volume }
    }

    // MARK: - AI Insights Generation

    private func generateAIWorkoutInsights(for logs: [DailyLog], program: WorkoutProgram?, analytics: (totalVolume: Double, prs: [String: String])) async -> [WorkoutAnalysisInsight] {
        let workoutSummary = logs.flatMap { $0.exercises ?? [] }
            .map { "On \(($0.date).formatted(date: .abbreviated, time: .omitted)), user did \($0.name) for \($0.durationMinutes ?? 0) mins, burning \(Int($0.caloriesBurned)) calories." }
            .joined(separator: "\n")

        let nutritionSummary = logs.map {
            "On \(($0.date).formatted(date: .abbreviated, time: .omitted)), user ate \(Int($0.totalCalories())) calories, with \(Int($0.totalMacros().protein))g protein."
        }.joined(separator: "\n")

        let prompt = """
        You are Maia, an expert fitness and nutrition coach. Analyze this workout data and generate **exactly 8 high-quality, actionable insights**.

        **User Data:**
        - Program: \(program?.name ?? "None")
        - Volume: \(Int(analytics.totalVolume)) lbs
        - New PRs: \(analytics.prs.isEmpty ? "None" : analytics.prs.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
        - Workouts:
        \(workoutSummary.isEmpty ? "No recent workouts." : workoutSummary)
        - Nutrition:
        \(nutritionSummary.isEmpty ? "No nutrition logged." : nutritionSummary)

        **Output Format:**
        JSON object with root key "insights" (array of objects).
        Each object: "title", "message", "category".
        Categories: "Performance", "Consistency", "Recovery", "Nutrition", "Mindset".
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await AIService.shared.performRequest(
            messages: messages,
            model: "gpt-4o-mini",
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return [] }
            do {
                let response = try JSONDecoder().decode(AIWorkoutInsightResponse.self, from: data)
                return response.insights
            } catch {
                print("❌ Error decoding insights: \(error)")
                return [WorkoutAnalysisInsight(title: "Analysis Error", message: "Could not process AI response.", category: "Mindset")]
            }
        case .failure(let error):
            print("❌ AI Error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers
    
    private func calculateTotalVolume(log: WorkoutSessionLog) -> Double {
        return log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { setSum, set in
                setSum + (set.weight * Double(set.reps))
            }
        }
    }
    
    private func calculateEstimatedDuration(log: WorkoutSessionLog) -> Int {
        let totalSets = log.completedExercises.reduce(0) { $0 + $1.sets.count }
        return totalSets * 120
    }
    
    private func guessMuscleGroup(exerciseName: String) -> String {
        let lower = exerciseName.lowercased()
        if lower.contains("bench") || lower.contains("push") || lower.contains("fly") || lower.contains("chest") { return "Chest" }
        if lower.contains("squat") || lower.contains("leg") || lower.contains("lunge") || lower.contains("quad") { return "Legs" }
        if lower.contains("deadlift") || lower.contains("row") || lower.contains("pull") || lower.contains("lat") { return "Back" }
        if lower.contains("curl") || lower.contains("tricep") || lower.contains("bicep") { return "Arms" }
        if lower.contains("press") || lower.contains("raise") || lower.contains("shoulder") { return "Shoulders" }
        return "Other"
    }
}
