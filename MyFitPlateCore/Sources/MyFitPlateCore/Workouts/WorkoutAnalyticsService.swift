import Foundation
import Combine
// MARK: - Data Models for Analytics

public struct WorkoutAnalytics {
    public let totalVolume: Double
    public let personalRecords: [String: String]
    public let aiInsights: [WorkoutAnalysisInsight]

    public init(totalVolume: Double, personalRecords: [String: String], aiInsights: [WorkoutAnalysisInsight]) {
        self.totalVolume = totalVolume
        self.personalRecords = personalRecords
        self.aiInsights = aiInsights
    }
}

public struct WorkoutAnalysisInsight: Codable, Identifiable, Hashable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let category: String

    private enum CodingKeys: String, CodingKey {
        case title, message, category
    }
}

private struct AIWorkoutInsightResponse: Decodable {
    public let insights: [WorkoutAnalysisInsight]
}

// MARK: - New Analytics Models
public struct ExerciseTrendPoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let value: Double // Max Weight or Volume
}

public struct WorkoutComparison: Equatable {
    public let volumeDiffPercent: Double
    public let durationDiffPercent: Double
    public let previousDate: Date?
    public let durationIsMeasured: Bool

    public var isPR: Bool {
        volumeDiffPercent > 0 && previousDate != nil
    }
}

public struct MuscleSplitPoint: Identifiable {
    public let id = UUID()
    public let muscleName: String
    /// Number of working sets for this muscle group. Set count (not lbs of volume) keeps the
    /// chart readable — otherwise heavy compound lifts make back/legs dwarf everything else.
    public let setCount: Double
}

// MARK: - Service Class

@MainActor
public class WorkoutAnalyticsService: ObservableObject {
    public init() {}
    @Published public private(set) var historyCoverageMessage: String?
    private let workoutService = WorkoutService()

    // MARK: - Core Analytics Calculation (Existing Logic)

    public func calculateAnalytics(for logs: [DailyLog], program: WorkoutProgram?) async -> WorkoutAnalytics {
        var totalVolume: Double = 0
        var personalRecords: [String: (weight: Double, reps: Int)] = [:]
        var recordContexts: [String: RoutineExercise] = [:]
        var ambiguousRecords = Set<String>()

        let allLoggedExercises = logs.flatMap { $0.exercises ?? [] }

        for loggedExercise in allLoggedExercises {
            guard let workoutID = loggedExercise.workoutID, let sessionID = loggedExercise.sessionID else { continue }

            let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)

            if case .success(let sessionLog) = sessionResult {
                for completedExercise in sessionLog.completedExercises {
                    let exerciseName = completedExercise.exerciseName
                    let identity = normalizedExerciseName(exerciseName)
                    if completedExercise.exercise.loadEquipment?.isValid == false {
                        ambiguousRecords.insert(identity)
                    }
                    if let previous = recordContexts[identity] {
                        if !StrengthEquipment.historyCompatible(current: completedExercise.exercise.loadEquipment,
                                                                previous: previous.loadEquipment) {
                            ambiguousRecords.insert(identity)
                        }
                    } else {
                        recordContexts[identity] = completedExercise.exercise
                    }
                    for set in WorkoutSetMath.workingSets(in: completedExercise) where completedExercise.exercise.type == .strength && completedExercise.exercise.loadEquipment?.loadingMeaning != .assistance && completedExercise.exercise.loadEquipment?.loadingMeaning != .bodyweightOnly {
                        let volume = set.weight * Double(set.reps)
                        totalVolume += volume

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

        let prStrings = personalRecords.filter { !ambiguousRecords.contains(normalizedExerciseName($0.key)) }
            .mapValues { String(format: "%.1f lbs x %d reps", $0.weight, $0.reps) }
        let aiInsights = await generateAIWorkoutInsights(for: logs, program: program, analytics: (totalVolume, prStrings))

        return WorkoutAnalytics(totalVolume: totalVolume, personalRecords: prStrings, aiInsights: aiInsights)
    }

    public func generateInsightsForPastSession(sessionID: String, workoutName: String, userID: String) async -> [WorkoutAnalysisInsight] {
        let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: "unknown", sessionID: sessionID)
        guard case .success(let sessionLog) = sessionResult else { return [] }

        return await generateAIWorkoutInsights(for: sessionLog, totalVolume: calculateTotalVolume(log: sessionLog), personalRecords: [:])
    }

    public func generateAnalyticsForPastSession(sessionID: String, workoutName: String, date: Date) async -> WorkoutAnalytics? {
        let sessionResult = await workoutService.fetchWorkoutSessionLog(workoutID: "unknown", sessionID: sessionID)
        guard case .success(let sessionLog) = sessionResult else { return nil }

        return await generateAnalytics(for: sessionLog, userID: DIContainer.shared.authService.currentUserID)
    }

    public func generateImmediateSessionAnalytics(for sessionLog: WorkoutSessionLog) -> WorkoutAnalytics {
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

    public func generateAnalytics(for sessionLog: WorkoutSessionLog, userID: String?) async -> WorkoutAnalytics {
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

    public func saveInsights(_ insights: [WorkoutAnalysisInsight], forSessionID sessionID: String, userID: String) async {
        guard !insights.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(insights)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            try await DIContainer.shared.workoutRepository.saveWorkoutInsights(userID: userID, sessionID: sessionID, insights: jsonArray)
        } catch {
            AppLog.workouts.error("Failed to save workout insights: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - New: History & Trends Features

    /// Fetches a paginated list of past workout logs for the History View
    public func fetchWorkoutHistory(userID: String, limit: Int = 20) async -> [WorkoutSessionLog] {
        do {
            return try await DIContainer.shared.workoutRepository.fetchWorkoutHistory(userID: userID, limit: limit)
        } catch {
            AppLog.workouts.error("Failed to fetch workout history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches historical performance for a specific exercise to plot charts
    public func fetchTrends(for exerciseName: String, userID: String) async -> [ExerciseTrendPoint] {
        await fetchTrends(for: RoutineExercise(name: exerciseName), userID: userID)
    }

    /// Complete dated history is paged before comparing compatible setups.
    public func fetchTrends(for exercise: RoutineExercise, userID: String) async -> [ExerciseTrendPoint] {
        guard exercise.loadEquipment?.loadingMeaning != .assistance, exercise.loadEquipment?.loadingMeaning != .bodyweightOnly else { return [] }
        do {
            let logs = try await completeHistory(userID: userID)
            guard DIContainer.shared.authService.currentUserID == userID else { return [] }
            return logs.reversed().compactMap { log in
                let matches = log.completedExercises.filter {
                    WorkoutSetMath.normalizedName($0.exerciseName) == WorkoutSetMath.normalizedName(exercise.name)
                }
                guard matches.allSatisfy({ StrengthEquipment.historyCompatible(current: exercise.loadEquipment, previous: $0.exercise.loadEquipment) }) else { return nil }
                let maximum = matches.flatMap { WorkoutSetMath.workingSets(in: $0) }.map(\.weight).max() ?? 0
                guard maximum.isFinite, maximum > 0 else { return nil }
                return ExerciseTrendPoint(date: log.date, value: maximum)
            }
        } catch {
            AppLog.workouts.error("Failed to fetch workout trends: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Compares a current session against the last time this Routine ID was logged
    public func compareAgainstPrevious(currentLog: WorkoutSessionLog, userID: String) async -> WorkoutComparison? {
        let routineID = currentLog.routineID
        do {
            let logs = try await completeHistory(userID: userID).filter { $0.routineID == routineID }

            guard let previousLog = logs.filter({ (currentLog.id == nil || $0.id != currentLog.id) && $0.date < currentLog.date }).max(by: { $0.date < $1.date }) else { return nil }
            // A raw volume delta cannot establish progress after the meaning of a load
            // or machine changes. Preserve recorded volumes, but omit that comparison.
            guard currentLog.completedExercises.count == previousLog.completedExercises.count else { return nil }
            for exercise in currentLog.completedExercises {
                guard exercise.exercise.loadEquipment?.isValid != false,
                      exercise.exercise.loadEquipment?.loadingMeaning != .assistance,
                      let previous = previousLog.completedExercises.first(where: { WorkoutSetMath.compatible(exercise, $0) }),
                      WorkoutSetMath.prescriptionCompatible(exercise.exercise, previous.exercise),
                      WorkoutSetMath.workingSets(in: exercise).count == WorkoutSetMath.workingSets(in: previous).count else { return nil }
            }
            let currentVolume = calculateTotalVolume(log: currentLog)
            let previousVolume = calculateTotalVolume(log: previousLog)
            let measured = currentLog.elapsedSeconds.map { $0.isFinite && $0 > 0 } == true
                && previousLog.elapsedSeconds.map { $0.isFinite && $0 > 0 } == true
            let currentDuration = measured ? currentLog.elapsedSeconds ?? 0 : 0
            let previousDuration = measured ? previousLog.elapsedSeconds ?? 0 : 0

            let volDiff = previousVolume > 0 ? (currentVolume - previousVolume) / previousVolume : 0.0
            let durDiff = previousDuration > 0 ? (Double(currentDuration) - Double(previousDuration)) / Double(previousDuration) : 0.0

            return WorkoutComparison(volumeDiffPercent: volDiff, durationDiffPercent: durDiff, previousDate: previousLog.date, durationIsMeasured: measured)
        } catch {
            AppLog.workouts.error("Failed to compare workouts: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // Calculates volume distribution by muscle group
    public func calculateMuscleSplit(log: WorkoutSessionLog) -> [MuscleSplitPoint] {
        var distribution: [String: Double] = [:]

        for exercise in log.completedExercises {
            let muscle = guessMuscleGroup(exerciseName: exercise.exerciseName)
            distribution[muscle, default: 0] += Double(WorkoutSetMath.workingSets(in: exercise).count)
        }

        return distribution.map { MuscleSplitPoint(muscleName: $0.key, setCount: $0.value) }
            .sorted { $0.setCount > $1.setCount }
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
        - Date: \(sessionLog.date.formatted(date: .abbreviated, time: .shortened))
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

        let result = await DIContainer.shared.aiService.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-6-astra",
            temperature: 0.35,
            responseFormat: ["type": "json_object"], requestKind: .coaching
        )

        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return [] }
            do {
                let response = try JSONDecoder().decode(AIWorkoutInsightResponse.self, from: data)
                return Array(response.insights.prefix(3))
            } catch {
                AppLog.workouts.error("Failed to decode session workout insights: \(error.localizedDescription, privacy: .public)")
                AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_session_training_insights")
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

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            model: "gpt-6-astra",
            responseFormat: ["type": "json_object"], requestKind: .coaching
        )

        switch result {
        case .success(let jsonString):
            guard let data = jsonString.data(using: .utf8) else { return [] }
            do {
                let response = try JSONDecoder().decode(AIWorkoutInsightResponse.self, from: data)
                return response.insights
            } catch {
                AppLog.workouts.error("Failed to decode workout insights: \(error.localizedDescription, privacy: .public)")
                AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_training_insights")
                return [WorkoutAnalysisInsight(title: "Analysis Error", message: "Could not process AI response.", category: "Mindset")]
            }
        case .failure(let error):
            AppLog.workouts.error("Workout insights AI request failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func completeHistory(userID: String) async throws -> [WorkoutSessionLog] {
        do {
            let all = try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: userID)
            let now = Date()
            let logs = all.filter { $0.date.timeIntervalSinceReferenceDate.isFinite && $0.date <= now }
            guard DIContainer.shared.authService.currentUserID == userID else { throw WorkoutHistoryReadError.accountChanged }
            let excluded = all.count - logs.count
            historyCoverageMessage = "\(logs.count) eligible dated sessions checked. Comparisons use compatible working sets; refresh after new or corrected workouts."
                + (excluded > 0 ? " \(excluded) future-dated records remain in History for review and are excluded here." : "")
            return logs
        } catch {
            if DIContainer.shared.authService.currentUserID == userID {
                historyCoverageMessage = "Complete history could not be confirmed. Loaded session totals are still shown; all-history comparisons are unavailable until refresh."
            }
            throw error
        }
    }

    // MARK: - Helpers

    private func calculateTotalVolume(log: WorkoutSessionLog) -> Double {
        WorkoutSetMath.volume(log)
    }

    private func calculateEstimatedDuration(log: WorkoutSessionLog) -> Int {
        let totalSets = log.completedExercises.reduce(0) { $0 + $1.sets.count }
        return totalSets * 120
    }

    private func detectPersonalRecords(in currentLog: WorkoutSessionLog, userID: String) async -> [String: String] {
        do {
            let historicalLogs = try await completeHistory(userID: userID)
                .filter { log in
                    if let currentID = currentLog.id, log.id == currentID { return false }
                    return log.date < currentLog.date
                }

            guard !historicalLogs.isEmpty else { return [:] }

            var records: [String: String] = [:]
            let currentGroups = Dictionary(grouping: currentLog.completedExercises) { normalizedExerciseName($0.exerciseName) }
            let ambiguousNames = Set(currentGroups.filter { entry in
                guard let first = entry.value.first else { return false }
                return entry.value.contains { !StrengthEquipment.historyCompatible(current: first.exercise.loadEquipment,
                                                                                   previous: $0.exercise.loadEquipment) }
            }.keys)

            for exercise in currentLog.completedExercises where exercise.exercise.type == .strength {
                guard !ambiguousNames.contains(normalizedExerciseName(exercise.exerciseName)) else { continue }
                guard let currentBest = WorkoutSetMath.bestSet(exercise) else { continue }

                let previousBest = historicalLogs
                    .flatMap(\.completedExercises)
                    .filter { normalizedExerciseName($0.exerciseName) == normalizedExerciseName(exercise.exerciseName)
                        && StrengthEquipment.historyCompatible(current: exercise.exercise.loadEquipment,
                                                               previous: $0.exercise.loadEquipment) }
                    .compactMap(WorkoutSetMath.bestSet)
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

    private func normalizedExerciseName(_ name: String) -> String {
        name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
    }

    private func generateLocalSessionInsights(for log: WorkoutSessionLog, totalVolume: Double, personalRecords: [String: String]) -> [WorkoutAnalysisInsight] {
        let setCount = WorkoutSetMath.workingSetCount(log)
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
        WorkoutSetMath.volume(exercise)
    }

    private func bestStrengthSet(in sets: [CompletedSet]) -> CompletedSet? {
        sets
            .filter { $0.isWorkingSet && $0.weight.isFinite && $0.weight > 0 && $0.reps > 0 }
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
        // Check leg-specific terms FIRST so "calf raise", "leg press", and "leg curl" don't fall
        // through to the generic "raise"/"press"/"curl" rules and get mislabeled (e.g. a calf
        // raise being counted as Shoulders).
        if lower.contains("squat") || lower.contains("leg") || lower.contains("lunge")
            || lower.contains("quad") || lower.contains("calf") || lower.contains("calve")
            || lower.contains("hamstring") || lower.contains("glute") || lower.contains("hip thrust") {
            return "Legs"
        }
        if lower.contains("bench") || lower.contains("push") || lower.contains("fly")
            || lower.contains("chest") || lower.contains("pec") {
            return "Chest"
        }
        if lower.contains("curl") || lower.contains("tricep") || lower.contains("bicep") {
            return "Arms"
        }
        if lower.contains("crunch") || lower.contains("plank") || lower.contains("oblique")
            || lower.contains("abs") || lower.contains("core") {
            return "Core"
        }
        if lower.contains("press") || lower.contains("raise") || lower.contains("shoulder")
            || lower.contains("delt") || lower.contains("shrug") {
            return "Shoulders"
        }
        if lower.contains("deadlift") || lower.contains("row") || lower.contains("pull")
            || lower.contains("lat") || lower.contains("back") {
            return "Back"
        }
        return "Other"
    }
}
