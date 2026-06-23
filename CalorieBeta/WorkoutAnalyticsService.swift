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

struct WorkoutAnalysisInsight: Codable, Identifiable, Hashable {
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

        return await generateAnalytics(for: sessionLog, userID: Auth.auth().currentUser?.uid)
    }

    func generateImmediateSessionAnalytics(for sessionLog: WorkoutSessionLog) -> WorkoutAnalytics {
        let totalVolume = calculateTotalVolume(log: sessionLog)
        return WorkoutAnalytics(
            totalVolume: totalVolume,
            personalRecords: [:],
            aiInsights: generateLocalSessionInsights(
                for: sessionLog,
                totalVolume: totalVolume,
                personalRecords: [:]
            )
        )
    }

    func generateAnalytics(for sessionLog: WorkoutSessionLog, userID: String?) async -> WorkoutAnalytics {
        let totalVolume = calculateTotalVolume(log: sessionLog)
        let personalRecords: [String: String]

        if let userID {
            personalRecords = await detectPersonalRecords(in: sessionLog, userID: userID)
        } else {
            personalRecords = [:]
        }

        let localInsights = generateLocalSessionInsights(
            for: sessionLog,
            totalVolume: totalVolume,
            personalRecords: personalRecords
        )
        let aiInsights = await generateAIWorkoutInsights(
            for: sessionLog,
            totalVolume: totalVolume,
            personalRecords: personalRecords
        )

        return WorkoutAnalytics(
            totalVolume: totalVolume,
            personalRecords: personalRecords,
            aiInsights: mergeInsights(local: localInsights, ai: aiInsights)
        )
    }

    // MARK: - Persist Insights

    func saveInsights(_ insights: [WorkoutAnalysisInsight], forSessionID sessionID: String, userID: String) async {
        guard !insights.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(insights)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            try await db.collection("users").document(userID).collection("workoutSessionLogs").document(sessionID).updateData(["aiInsights": jsonArray])
        } catch {
            AppLog.workouts.error("Failed to save workout insights: \(error.localizedDescription, privacy: .public)")
        }
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
            AppLog.workouts.error("Failed to fetch workout history: \(error.localizedDescription, privacy: .public)")
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
            AppLog.workouts.error("Failed to fetch workout trends: \(error.localizedDescription, privacy: .public)")
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
            AppLog.workouts.error("Failed to compare workouts: \(error.localizedDescription, privacy: .public)")
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

    private func generateAIWorkoutInsights(for sessionLog: WorkoutSessionLog, totalVolume: Double, personalRecords: [String: String]) async -> [WorkoutAnalysisInsight] {
        let exerciseSummary = sessionLog.completedExercises.map { completedExercise in
            let setSummary = completedExercise.sets.map { set -> String in
                switch completedExercise.exercise.type {
                case .strength:
                    return "\(String(format: "%g", set.weight)) lb x \(set.reps)"
                case .cardio:
                    let minutes = (set.durationInSeconds ?? 0) / 60
                    let distance = set.distance ?? 0
                    return distance > 0 ? "\(String(format: "%.1f", distance)) mi in \(minutes) min" : "\(minutes) min"
                case .flexibility:
                    return "\((set.durationInSeconds ?? 0)) sec"
                }
            }.joined(separator: ", ")

            return "- \(completedExercise.exerciseName): \(completedExercise.sets.count) sets (\(setSummary))"
        }.joined(separator: "\n")

        let prompt = """
        You are Maia, a precise fitness coach inside MyFitPlate. Analyze this just-completed workout and produce exactly 3 short coaching insights.

        SESSION DATA:
        - Date: \(sessionLog.date.dateValue().formatted(date: .abbreviated, time: .shortened))
        - Total volume: \(Int(totalVolume)) lb
        - Exercises:
        \(exerciseSummary)
        - Confirmed records: \(personalRecords.isEmpty ? "None confirmed from prior history." : personalRecords.map { "\($0.key): \($0.value)" }.joined(separator: ", "))

        RULES:
        - Be specific to the logged sets. Do not invent sleep, soreness, calories, or nutrition.
        - Do not call something a PR unless it appears in Confirmed records.
        - Each message should be 1-2 sentences and end with a concrete next action.
        - Use only these categories: "Performance", "Consistency", "Recovery", "Nutrition", "Mindset".

        JSON only:
        {"insights":[{"title":"...","message":"...","category":"Performance"}]}
        """

        let result = await AIService.shared.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-4o-mini",
            temperature: 0.35,
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return [] }
            do {
                let response = try JSONDecoder().decode(AIWorkoutInsightResponse.self, from: data)
                return Array(response.insights.prefix(3))
            } catch {
                AppLog.workouts.error("Failed to decode session workout insights: \(error.localizedDescription, privacy: .public)")
                return []
            }
        case .failure(let error):
            AppLog.workouts.error("Session workout insights AI request failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

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
                AppLog.workouts.error("Failed to decode workout insights: \(error.localizedDescription, privacy: .public)")
                return [WorkoutAnalysisInsight(title: "Analysis Error", message: "Could not process AI response.", category: "Mindset")]
            }
        case .failure(let error):
            AppLog.workouts.error("Workout insights AI request failed: \(error.localizedDescription, privacy: .public)")
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

    private func detectPersonalRecords(in currentLog: WorkoutSessionLog, userID: String) async -> [String: String] {
        let ref = db.collection("users").document(userID).collection("workoutSessionLogs")
            .order(by: "date", descending: true)
            .limit(to: 60)

        do {
            let snapshot = try await ref.getDocuments()
            let historicalLogs = snapshot.documents
                .compactMap { try? $0.data(as: WorkoutSessionLog.self) }
                .filter { log in
                    if let currentID = currentLog.id, log.id == currentID { return false }
                    return log.date.dateValue() < currentLog.date.dateValue()
                }

            guard !historicalLogs.isEmpty else { return [:] }

            var records: [String: String] = [:]

            for exercise in currentLog.completedExercises where exercise.exercise.type == .strength {
                guard let currentBest = bestStrengthSet(in: exercise.sets) else { continue }

                let previousBest = historicalLogs
                    .flatMap(\.completedExercises)
                    .filter { $0.exerciseName.localizedCaseInsensitiveCompare(exercise.exerciseName) == .orderedSame }
                    .compactMap { bestStrengthSet(in: $0.sets) }
                    .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }

                guard let previousBest else { continue }

                let currentScore = estimatedOneRepMax(currentBest)
                let previousScore = estimatedOneRepMax(previousBest)
                guard currentScore > previousScore * 1.005 else { continue }

                records[exercise.exerciseName] = "\(formatSet(currentBest)) (prev \(formatSet(previousBest)))"
            }

            return records
        } catch {
            AppLog.workouts.error("Failed to detect workout PRs: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private func generateLocalSessionInsights(for log: WorkoutSessionLog, totalVolume: Double, personalRecords: [String: String]) -> [WorkoutAnalysisInsight] {
        let setCount = log.completedExercises.reduce(0) { $0 + $1.sets.count }
        let strengthExercises = log.completedExercises.filter { $0.exercise.type == .strength }
        let cardioMinutes = log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + (($1.durationInSeconds ?? 0) / 60) }
        }
        var insights: [WorkoutAnalysisInsight] = []

        insights.append(
            WorkoutAnalysisInsight(
                title: "Session Banked",
                message: "You logged \(log.completedExercises.count) exercises and \(setCount) working sets. Keep the next step simple: repeat the plan or add a small progression where form stayed clean.",
                category: "Consistency"
            )
        )

        if let topExercise = strengthExercises.max(by: { exerciseVolume($0) < exerciseVolume($1) }),
           let bestSet = bestStrengthSet(in: topExercise.sets),
           exerciseVolume(topExercise) > 0 {
            insights.append(
                WorkoutAnalysisInsight(
                    title: "\(topExercise.exerciseName) Drove the Session",
                    message: "That lift contributed \(Int(exerciseVolume(topExercise))) lb of volume, with a best set of \(formatSet(bestSet)). Use that as your anchor when you plan the next session.",
                    category: "Performance"
                )
            )
        } else if cardioMinutes > 0 {
            insights.append(
                WorkoutAnalysisInsight(
                    title: "Conditioning Logged",
                    message: "You recorded \(cardioMinutes) minutes of timed work. Next time, progress one variable only: either a little more time, a little more distance, or the same work at an easier effort.",
                    category: "Performance"
                )
            )
        }

        if !personalRecords.isEmpty {
            insights.append(
                WorkoutAnalysisInsight(
                    title: "Confirmed Progress",
                    message: "You beat prior history on \(personalRecords.count) lift\(personalRecords.count == 1 ? "" : "s"). Keep the next exposure controlled instead of chasing another jump immediately.",
                    category: "Performance"
                )
            )
        }

        if setCount >= 12 || totalVolume >= 10_000 {
            insights.append(
                WorkoutAnalysisInsight(
                    title: "Recovery Has Leverage",
                    message: "This was enough work to make recovery matter. Prioritize protein, fluids, and an easy warm-up next session before deciding whether to increase load.",
                    category: "Recovery"
                )
            )
        } else {
            insights.append(
                WorkoutAnalysisInsight(
                    title: "Room to Build",
                    message: "The session was compact, which is useful for consistency. If you felt strong, add one set to the main lift or make the next workout slightly denser.",
                    category: "Mindset"
                )
            )
        }

        return Array(insights.prefix(4))
    }

    private func mergeInsights(local: [WorkoutAnalysisInsight], ai: [WorkoutAnalysisInsight]) -> [WorkoutAnalysisInsight] {
        guard !ai.isEmpty else { return local }

        let combined = Array(local.prefix(2)) + ai
        var seenTitles = Set<String>()

        return combined.filter { insight in
            let normalizedTitle = insight.title.lowercased()
            guard !seenTitles.contains(normalizedTitle) else { return false }
            seenTitles.insert(normalizedTitle)
            return true
        }
        .prefix(5)
        .map { $0 }
    }

    private func exerciseVolume(_ exercise: CompletedExercise) -> Double {
        exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    private func bestStrengthSet(in sets: [CompletedSet]) -> CompletedSet? {
        sets
            .filter { $0.weight > 0 && $0.reps > 0 }
            .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }
    }

    private func estimatedOneRepMax(_ set: CompletedSet) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func formatSet(_ set: CompletedSet) -> String {
        "\(String(format: "%g", set.weight)) lb x \(set.reps)"
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
