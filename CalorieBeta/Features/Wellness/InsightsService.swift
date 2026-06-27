import Foundation
import Combine
import FirebaseAuth
import HealthKit
@MainActor
class InsightsService: ObservableObject {
    @Published var currentInsights: [UserInsight] = []
    @Published var smartSuggestion: UserInsight? = nil
    @Published var isLoadingInsights: Bool = false
    @Published var isGeneratingSuggestion: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()

    private var lastWeeklyInsightFetch: Date?
    struct NotificationContext {
        let gender: String
        let phase: MenstrualPhase?
        let wellnessScore: Int?
        let sleepScore: Int?
        let caloriesRemaining: Double
        let proteinRemaining: Double
        let daysSinceLastWorkout: Int
        let lastWorkoutName: String?
        let stepsToday: Double
        let activeEnergyToday: Double
    }

    init(dailyLogService: DailyLogService, goalSettings: GoalSettings, healthKitViewModel: HealthKitViewModel) {
        self.dailyLogService = dailyLogService
        self.goalSettings = goalSettings
        self.healthKitViewModel = healthKitViewModel

        healthKitViewModel.$sleepSamples
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.generateAndFetchInsights()
            }
            .store(in: &cancellables)
    }

    // ... [generateSingleMealSuggestion, createMealSuggestionPrompt, generateDailySmartInsight remain unchanged] ...
    // (Keep existing implementations)
    func generateSingleMealSuggestion() async -> MealSuggestion? {
        self.isGeneratingSuggestion = true
        let prompt = createMealSuggestionPrompt()
        guard let responseString = await fetchAIResponse(prompt: prompt) else {
            self.isGeneratingSuggestion = false
            return nil
        }
        guard let jsonData = responseString.data(using: .utf8) else {
            self.isGeneratingSuggestion = false
            return nil
        }
        let suggestion = try? JSONDecoder().decode(MealSuggestion.self, from: jsonData)
        self.isGeneratingSuggestion = false
        return suggestion
    }

    private func createMealSuggestionPrompt() -> String {
        let remainingCalories = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingProtein = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        let remainingCarbs = max(0, goalSettings.carbs - (dailyLogService.currentDailyLog?.totalMacros().carbs ?? 0))
        let remainingFats = max(0, goalSettings.fats - (dailyLogService.currentDailyLog?.totalMacros().fats ?? 0))

        let hour = Calendar.current.component(.hour, from: Date())
        let mealType: String
        switch hour {
            case 4..<11: mealType = "breakfast"
            case 11..<16: mealType = "lunch"
            case 16..<21: mealType = "dinner"
            default: mealType = "snack"
        }

        let proteinPrefs = goalSettings.suggestionProteins.isEmpty ? "any" : goalSettings.suggestionProteins.joined(separator: ", ")
        let carbPrefs = goalSettings.suggestionCarbs.isEmpty ? "any" : goalSettings.suggestionCarbs.joined(separator: ", ")
        let veggiePrefs = goalSettings.suggestionVeggies.isEmpty ? "any" : goalSettings.suggestionVeggies.joined(separator: ", ")
        let cuisinePrefs = (goalSettings.suggestionCuisines.isEmpty || goalSettings.suggestionCuisines.contains("Any")) ? "any" : goalSettings.suggestionCuisines.joined(separator: ", ")

        return """
        You are Maia, a helpful nutrition coach. The user needs a suggestion for their next meal, which is likely \(mealType).

        Their remaining goals for today are:
        - Calories: \(Int(remainingCalories))
        - Protein: \(Int(remainingProtein))g
        - Carbs: \(Int(remainingCarbs))g
        - Fats: \(Int(remainingFats))g

        User Preferences:
        - Proteins: \(proteinPrefs)
        - Carbs: \(carbPrefs)
        - Veggies: \(veggiePrefs)
        - Cuisines: \(cuisinePrefs)

        RULES:
        1. Generate a single, simple, healthy meal idea that fits the user's remaining nutritional targets AND their preferences.
        2. **Prioritize Variety**: Do NOT suggest common items like 'quinoa' or 'chicken breast' unless they are explicitly listed in the user's preferences. Use a diverse range of ingredients.
        3. Your response MUST be a valid JSON object. Do not include any other text.
        4. The JSON object must have these exact keys: "mealName" (string), "calories" (number), "protein" (number), "carbs" (number), "fats" (number), "ingredients" (an array of strings), "instructions" (a single string with newlines).
        """
    }

    func generateDailySmartInsight() {
        guard let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date) else {
            self.smartSuggestion = UserInsight(
                title: "Welcome!",
                message: "Start logging your meals and workouts to receive personalized tips here.",
                category: .smartSuggestion, priority: 1)
            return
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let loggedFoods = log.meals.flatMap { $0.foodItems }

        if let lastWorkout = log.exercises?.last(where: { $0.caloriesBurned > 150 }) {
            let workoutEndTime = lastWorkout.date.addingTimeInterval(Double(lastWorkout.durationMinutes ?? 30) * 60)
            if Date().timeIntervalSince(workoutEndTime) < (2 * 60 * 60) {
                self.smartSuggestion = UserInsight(title: "Post-Workout Refuel", message: "Great work on your recent \(lastWorkout.name.lowercased())! A snack with protein and carbs can help with recovery.", category: .smartSuggestion, priority: 100)
                return
            }
        }

        if hour >= 19 {
            let proteinRemaining = (goalSettings.protein) - log.totalMacros().protein
            if proteinRemaining > 15 && proteinRemaining < 50 {
                self.smartSuggestion = UserInsight(title: "Hit Your Protein Goal", message: String(format: "You're just %.0fg of protein away from your goal. A Greek yogurt or protein shake could be a great choice!", proteinRemaining), category: .smartSuggestion, priority: 90)
                return
            }
        }

        if hour >= 12 && hour < 15 && !log.meals.contains(where: { $0.name == "Lunch" }) {
            self.smartSuggestion = UserInsight(title: "Lunch Time!", message: "Don't forget to log your lunch to stay on track with your goals for the day.", category: .smartSuggestion, priority: 80)
            return
        }

        if hour >= 18 && hour < 21 && !log.meals.contains(where: { $0.name == "Dinner" }) {
            self.smartSuggestion = UserInsight(title: "Time for Dinner?", message: "Remember to log your dinner to get a complete picture of your day's nutrition.", category: .smartSuggestion, priority: 80)
            return
        }

        if !loggedFoods.isEmpty {
            self.smartSuggestion = UserInsight(title: "Keep Up the Great Work!", message: "Consistency is the key to reaching your goals. You're doing great today!", category: .smartSuggestion, priority: 5)
            return
        }

        self.smartSuggestion = UserInsight(title: "Have a Great Day!", message: "Log your first meal or workout to get personalized tips and insights.", category: .smartSuggestion, priority: 1)
    }

    func generateAndFetchInsights(forLastDays days: Int = 7) {
        guard !isLoadingInsights else { return }

        if let lastFetch = lastWeeklyInsightFetch, !currentInsights.isEmpty, Calendar.current.isDateInToday(lastFetch) {
            return
        }

        guard let userID = Auth.auth().currentUser?.uid else { return }

        let sleepData = self.healthKitViewModel?.sleepSamples ?? []

        isLoadingInsights = true
        analysisTask?.cancel()

        analysisTask = Task {
            let endDate = Calendar.current.startOfDay(for: Date())
            guard let startDate = Calendar.current.date(byAdding: .day, value: -(days), to: endDate) else {
                await self.handleInsightsError(message: "Could not calculate date range for insights.")
                return
            }

            let result = await self.fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)

            if Task.isCancelled {
                await self.handleInsightsError(message: nil, isLoading: false)
                return
            }

            switch result {
            case .success(let logs):
                if logs.count < 3 {
                    let noDataInsight = [UserInsight(title: "More Data Needed", message: "Log consistently for a few more days to unlock your personalized weekly insights!", category: .nutritionGeneral, priority: 100)]
                    self.handleInsightsResult(insights: noDataInsight, error: nil)
                    return
                }

                let aiInsights = await self.generateAIInsights(for: logs, sleepSamples: sleepData, goals: self.goalSettings, retryCount: 1)

                self.handleInsightsResult(insights: aiInsights, error: aiInsights.isEmpty ? "Could not generate AI insights at this time." : nil)

            case .failure(let error):
                await self.handleInsightsError(message: "Could not analyze data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Smart Notification Logic (Fixed "700k Days" Bug)
    func generateSmartNotification(context: NotificationContext) async -> (title: String, body: String)? {

        // --- STEP 1: SELECT THE STRATEGY ---
        var strategy = "General Motivation"
        var tone = "Encouraging"
        var dataFocus = "User's general health goals"

        // Hook 1: Extreme Recovery (High or Low)
        if let score = context.wellnessScore {
            if score < 50 {
                strategy = "Recovery Warning"
                tone = "Gentle, protective, authoritative."
                dataFocus = "Wellness Score is low (\(score)). Advise rest or hydration."
            } else if score > 90 {
                strategy = "Peak Performance"
                tone = "Hype man, high energy, challenging."
                dataFocus = "Wellness Score is peak (\(score)). Challenge them to hit a Personal Record."
            }
        }

        if strategy == "General Motivation", let sleepScore = context.sleepScore {
            if sleepScore < 55 {
                strategy = "Sleep Recovery"
                tone = "Gentle, practical, protective."
                dataFocus = "Last sleep score is low (\(sleepScore)). Suggest lighter training, hydration, and a protein-forward meal."
            } else if sleepScore > 85 {
                strategy = "Rested Momentum"
                tone = "Confident, upbeat, practical."
                dataFocus = "Last sleep score is strong (\(sleepScore)). Encourage using the good recovery window well."
            }
        }

        // Hook 2: Cycle Phase
        if strategy == "General Motivation", let phase = context.phase {
            strategy = "Cycle Syncing"
            dataFocus = "User is in \(phase.rawValue) phase."
            switch phase {
            case .follicular, .ovulatory:
                tone = "Energetic, push them to work hard."
            case .luteal, .menstrual:
                tone = "Nurturing, validate their low energy."
            }
        }

        // Hook 3: Nutrition Gap
        if strategy == "General Motivation" {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 17 && context.caloriesRemaining > 400 {
                strategy = "Dinner Suggestion"
                tone = "Helpful, solution-oriented."
                dataFocus = "User has \(Int(context.caloriesRemaining)) calories and \(Int(context.proteinRemaining))g protein left. Suggest a meal type."
            }
        }

        // Hook 4: Workout Lapse (BUG FIX HERE)
        // Only trigger if days > 2 AND less than ~365 (to filter out default distantPast dates)
        if strategy == "General Motivation" && context.daysSinceLastWorkout > 2 && context.daysSinceLastWorkout < 400 {
            strategy = "Re-engagement"
            tone = context.gender == "Male" ? "Direct, challenge-oriented, 'tough love'." : "Encouraging, reminder of goals."
            dataFocus = "User hasn't worked out in \(context.daysSinceLastWorkout) days. Their last workout was \(context.lastWorkoutName ?? "unknown"). Get them back in."
        }

        // Hook 5: HealthKit Movement (Steps)
        if strategy == "General Motivation" {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 18 && context.stepsToday < 4000 {
                strategy = "Step Goal Warning"
                tone = "Playful, energetic."
                dataFocus = "User only has \(Int(context.stepsToday)) steps today and it's getting late. Nudge them to take a walk."
            } else if context.stepsToday > 10000 {
                strategy = "Step Goal Celebration"
                tone = "Celebratory, impressed."
                dataFocus = "User hit a massive \(Int(context.stepsToday)) steps today. Praise their passive movement."
            }
        }

        // --- STEP 2: CRAFT THE PROMPT ---
        let prompt = """
        You are Maia, an advanced AI fitness coach. Write a push notification for a \(context.gender) user.

        **CURRENT STRATEGY:** \(strategy)
        **TONE:** \(tone)
        **DATA CONTEXT:** \(dataFocus)

        **RULES:**
        1. Be witty, short, and punchy.
        2. Do NOT be generic (e.g., "Keep going!"). Be specific to the data provided.
        3. Max length: Title (25 chars), Body (90 chars).
        4. Return ONLY a valid JSON object with keys "title" and "body".
        """

        // --- STEP 3: CALL AI (Reusing existing infrastructure) ---
        guard let responseString = await fetchAIResponse(prompt: prompt),
              let data = responseString.data(using: .utf8) else { return nil }

        struct NotificationResponse: Decodable {
            let title: String
            let body: String
        }

        do {
            let decoded = try JSONDecoder().decode(NotificationResponse.self, from: data)
            return (decoded.title, decoded.body)
        } catch {
            return nil
        }
    }

    // ... [generateDailyBriefing and other methods remain unchanged] ...
    // (Keep existing implementations)
    func generateDailyBriefing(for userID: String) async -> (title: String, body: String)? {
        let wellnessScoreSummary = "Good Recovery"
        let todaysWorkout = "Leg Day"

        let prompt = """
        You are Maia, an encouraging fitness coach. Create a short, motivational "Daily Briefing" push notification.

        Yesterday's Wellness Score resulted in a summary of: "\(wellnessScoreSummary)".
        Today's planned workout is: "\(todaysWorkout)".

        RULES:
        1.  The title should be 4-5 words.
        2.  The body should be 1-2 short, encouraging sentences.
        3.  Combine the user's recovery status with their plan for the day.
        4.  Return ONLY a valid JSON object with keys "title" and "body".
        """

        guard let response = await fetchAIResponse(prompt: prompt),
              let data = response.data(using: .utf8) else { return nil }

        struct BriefingResponse: Decodable {
            let title: String
            let body: String
        }

        guard let decoded = try? JSONDecoder().decode(BriefingResponse.self, from: data) else { return nil }
        return (title: decoded.title, body: decoded.body)
    }

    private func handleInsightsResult(insights: [UserInsight], error: String?) {
        self.isLoadingInsights = false
        if let errorMessage = error {
            self.currentInsights = [UserInsight(title: "Insight Error", message: errorMessage, category: .nutritionGeneral)]
        } else {
            self.currentInsights = insights
            self.lastWeeklyInsightFetch = Date()
        }
    }

    private func generateAIInsights(for logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings, retryCount: Int) async -> [UserInsight] {
        let prompt = createAIPrompt(logs: logs, sleepSamples: sleepSamples, goals: goals)

        guard let responseString = await fetchAIResponse(prompt: prompt) else {
            return generateLocalInsights(from: logs, sleepSamples: sleepSamples, goals: goals)
        }
        guard let jsonData = responseString.data(using: .utf8) else {
            return generateLocalInsights(from: logs, sleepSamples: sleepSamples, goals: goals)
        }

        do {
            let insightsResponse = try JSONDecoder().decode([String: [UserInsight]].self, from: jsonData)
            return insightsResponse["insights"] ?? []
        } catch {
            AppLog.ai.error("Failed to decode generated insights: \(error.localizedDescription, privacy: .public)")
            if retryCount > 0 {
                AppLog.ai.info("Retrying insights generation.")
                return await generateAIInsights(for: logs, sleepSamples: sleepSamples, goals: goals, retryCount: retryCount - 1)
            }
            return generateLocalInsights(from: logs, sleepSamples: sleepSamples, goals: goals)
        }
    }

    private func generateLocalInsights(from logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> [UserInsight] {
        let loggedDays = logs.filter { !$0.meals.isEmpty || ($0.exercises?.isEmpty == false) || $0.waterTracker != nil }.count
        let proteinGoal = max(goals.protein, 1)
        let calorieGoal = max(goals.calories ?? 0, 1)
        let averageCalories = logs.isEmpty ? 0 : logs.reduce(0) { $0 + $1.totalCalories() } / Double(logs.count)
        let averageProtein = logs.isEmpty ? 0 : logs.reduce(0) { $0 + $1.totalMacros().protein } / Double(logs.count)
        let workoutCount = logs.reduce(0) { $0 + ($1.exercises?.count ?? 0) }
        let hydrationLogs = logs.compactMap(\.waterTracker)
        let averageHydration = hydrationLogs.isEmpty ? 0 : hydrationLogs.reduce(0) { $0 + $1.totalOunces } / Double(hydrationLogs.count)
        let sleepHours = sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) / 3600 }
        let averageSleep = sleepHours.isEmpty ? 0 : sleepHours.reduce(0, +) / Double(sleepHours.count)

        var insights: [UserInsight] = [
            UserInsight(
                title: "Your Logging Base Is Building",
                message: "You logged useful data on \(loggedDays) day\(loggedDays == 1 ? "" : "s") in this window. That gives Maia enough signal to start spotting patterns instead of guessing.",
                category: .positiveReinforcement,
                priority: 100,
                sourceData: "\(loggedDays) logged days across \(logs.count) days analyzed"
            )
        ]

        if averageProtein > 0 {
            let proteinGap = proteinGoal - averageProtein
            insights.append(
                UserInsight(
                    title: proteinGap <= 0 ? "Protein Is Carrying Well" : "Protein Is the Easiest Lever",
                    message: proteinGap <= 0
                        ? "Your average protein is at or above target. Keep distributing it across meals so recovery does not depend on one huge serving."
                        : "You are averaging about \(Int(max(proteinGap, 0)))g under your protein target. A repeatable protein add-on at breakfast or post-workout would close most of that gap.",
                    category: .macroBalance,
                    priority: 90,
                    sourceData: "Average protein: \(Int(averageProtein))g, target: \(Int(proteinGoal))g"
                )
            )
        }

        if workoutCount > 0 {
            insights.append(
                UserInsight(
                    title: "Training and Nutrition Are Connected",
                    message: "You logged \(workoutCount) workout entr\(workoutCount == 1 ? "y" : "ies"). On training days, check protein and fluids first; those are the simplest recovery wins.",
                    category: .exerciseSynergy,
                    priority: 85,
                    sourceData: "\(workoutCount) workout entries in analyzed logs"
                )
            )
        }

        if averageCalories > 0 {
            let calorieDifference = averageCalories - calorieGoal
            insights.append(
                UserInsight(
                    title: "Calorie Trend Check",
                    message: abs(calorieDifference) < 150
                        ? "Your average calories are close to target. Keep the meal structure steady before making big changes."
                        : "Your average calories are \(Int(abs(calorieDifference))) kcal \(calorieDifference > 0 ? "above" : "below") target. Adjust one recurring meal first instead of changing the whole day.",
                    category: .nutritionGeneral,
                    priority: 75,
                    sourceData: "Average calories: \(Int(averageCalories)), target: \(Int(calorieGoal))"
                )
            )
        }

        if averageHydration > 0 {
            insights.append(
                UserInsight(
                    title: "Hydration Signal",
                    message: "You averaged \(Int(averageHydration)) oz on days with water logs. Make the first bottle early; it raises the floor for the whole day.",
                    category: .hydration,
                    priority: 70,
                    sourceData: "Average logged water: \(Int(averageHydration)) oz"
                )
            )
        }

        if averageSleep > 0 {
            insights.append(
                UserInsight(
                    title: "Sleep Context Matters",
                    message: "Your available sleep data averages \(String(format: "%.1f", averageSleep)) hours. Use lower-sleep days as a cue to keep training volume conservative.",
                    category: .sleep,
                    priority: 65,
                    sourceData: "Average sleep from HealthKit samples: \(String(format: "%.1f", averageSleep)) hours"
                )
            )
        }

        return Array(insights.prefix(5))
    }

    private func createAIPrompt(logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"

        let dailyNutritionSummary = logs.map { log -> String in
            let day = dateFormatter.string(from: log.date)
            let macros = log.totalMacros()
            let micros = log.totalMicronutrients()
            return "- \(day): Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g, Fiber: \(Int(micros.fiber))g, Sodium: \(Int(micros.sodium))mg"
        }.joined(separator: "\n")

        let dailyWorkoutSummary = logs.compactMap { log -> String? in
            guard let exercises = log.exercises, !exercises.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let totalBurn = exercises.reduce(0) { $0 + $1.caloriesBurned }
            let exerciseNames = exercises.map { $0.name }.joined(separator: ", ")
            return "- \(day): Burned \(Int(totalBurn)) calories from \(exerciseNames)."
        }.joined(separator: "\n")

        let sleepSummaryByDay = Dictionary(grouping: sleepSamples) {
            Calendar.current.startOfDay(for: $0.startDate)
        }.mapValues { samples -> TimeInterval in
            samples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        }

        let sleepSummaryString = sleepSummaryByDay.keys.sorted().map { date -> String in
            let day = dateFormatter.string(from: date)
            let hours = (sleepSummaryByDay[date] ?? 0) / 3600
            return "- \(day): \(String(format: "%.1f", hours)) hours"
        }.joined(separator: "\n")

        let journalSummary = logs.compactMap { log -> String? in
            guard let entries = log.journalEntries, !entries.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let entrySummaries = entries.map { "\($0.category): \($0.text)" }.joined(separator: "; ")
            return "- \(day): \(entrySummaries)"
        }.joined(separator: "\n")

        let userGoals = """
        User's Goals:
        - Calorie Target: \(Int(goals.calories ?? 0)) kcal
        - Protein Target: \(Int(goals.protein))g
        - Fiber Target: 25g
        - Sodium Limit: 2300mg
        - Weight Goal: \(goals.goal)
        """

        return """
        You are Maia, an expert fitness and nutrition coach. Your tone is encouraging, insightful, and actionable. Analyze the following user data and generate 7 personalized insights.

        RULES:
        1.  Your response MUST be a valid JSON object with a single root key "insights".
        2.  Each insight object must have keys: "title", "message", "category", "priority", and "sourceData".
        3.  **Source Data (CRITICAL):** For each insight, the "sourceData" key must contain a concise, human-readable string of the specific data points you used. For example, "Wednesday Sleep: 6.1 hours, Thursday Calories: 1950 kcal".
        4.  **Holistic Insight (CRITICAL):** Generate at least two insights that connect workout data to nutrition OR sleep data. Example: "On Wednesday you had a tough leg day, and followed it up with 8 hours of sleep. This is fantastic for muscle recovery."
        5.  **Be Specific & Actionable:** Instead of "Eat more protein," say "Your protein intake on Wednesday was 30g below your goal. Adding a serving of Greek yogurt to your breakfast can help close that gap."
        6.  **Positive Reinforcement:** ALWAYS start with at least one positive insight highlighting something the user did well.
        7.  **Fitness Insight Requirement:** If the user has logged exercise, you MUST include at least one fitness-related insight.
        8.  **CATEGORIZE CORRECTLY:** For each insight, you MUST assign a 'category' from this exact list: [\(UserInsight.InsightCategory.allCases.map { $0.rawValue }.joined(separator: ", "))].

        DATA TO ANALYZE:
        \(userGoals)

        Daily Nutrition Summary (with Food Quality metrics):
        \(dailyNutritionSummary)

        Daily Workout Summary:
        \(dailyWorkoutSummary.isEmpty ? "No workouts logged this period." : dailyWorkoutSummary)

        Daily Sleep Summary:
        \(sleepSummaryString.isEmpty ? "No sleep data available." : sleepSummaryString)

        Daily Journal Summary:
        \(journalSummary.isEmpty ? "No journal entries logged this period." : journalSummary)

        JSON-ONLY RESPONSE:
        """
    }

    private func fetchAIResponse(prompt: String) async -> String? {
        let result = await AIService.shared.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-4o-mini",
            temperature: 0.7,
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let content):
            return content
        case .failure(let error):
            AppLog.ai.error("Insights AI request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func handleInsightsError(message: String?, isLoading: Bool? = nil) async {
        if let isLoading = isLoading { self.isLoadingInsights = isLoading }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        self.isLoadingInsights = false
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate)
    }

    // MARK: - Maia Operator Logic
    func processOperatorMessage(message: String, context: String) async -> MaiaOperatorResponse? {
        let prompt = """
        You are Maia, an AI fitness coach and operator. The user wants you to perform an action.
        Determine the intent and extract parameters.

        Available action types:
        1. "log_food": If the user wants to log a food/meal. Provide "foodName", "calories", "protein", "carbs", "fats". Estimate nutrition realistically.
        2. "adjust_goal": If the user wants to change a goal. Provide "target" (calories, protein, carbs, fats) and "value" (number).

        User's message: "\(message)"
        Additional Context: \(context)

        Respond ONLY with a valid JSON object matching this schema:
        {
          "reply": "Friendly response acknowledging the action",
          "actions": [
            {
              "actionType": "log_food",
              "foodName": "Apple",
              "calories": 95,
              "protein": 0.5,
              "carbs": 25,
              "fats": 0.3
            }
          ]
        }
        """

        guard let responseString = await fetchAIResponse(prompt: prompt),
              let data = responseString.data(using: .utf8) else {
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(MaiaOperatorResponse.self, from: data)
            return decoded
        } catch {
            AppLog.ai.error("Failed to decode operator response: \\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func executeOperatorActions(_ actions: [MaiaOperatorAction], userID: String) async {
        for action in actions {
            switch action.actionType {
            case "log_food":
                guard let name = action.foodName, let cals = action.calories else { continue }
                let item = FoodItem(
                    id: UUID().uuidString,
                    name: name,
                    calories: cals,
                    protein: action.protein ?? 0,
                    carbs: action.carbs ?? 0,
                    fats: action.fats ?? 0,
                    servingSize: "1 serving",
                    servingWeight: 0.0
                )
                let mealName = determineMealType(for: Date())
                await dailyLogService.logFoodItem(item, mealType: mealName)

            case "adjust_goal":
                guard let target = action.target, let value = action.value else { continue }
                switch target.lowercased() {
                case "calories":
                    goalSettings.calories = value
                case "protein":
                    goalSettings.protein = value
                case "carbs":
                    goalSettings.carbs = value
                case "fats":
                    goalSettings.fats = value
                default:
                    break
                }

            default:
                break
            }
        }
    }

    private func determineMealType(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return "Breakfast"
        case 11..<16: return "Lunch"
        case 16..<21: return "Dinner"
        default: return "Snack"
        }
    }
}

// MARK: - Maia Operator Foundation
public struct MaiaOperatorAction: Codable, Equatable {
    public let actionType: String // "log_food", "adjust_goal"

    // For log_food
    public let foodName: String?
    public let calories: Double?
    public let protein: Double?
    public let carbs: Double?
    public let fats: Double?

    // For adjust_goal
    public let target: String? // "protein", "calories", "carbs", "fats"
    public let value: Double?
}

public struct MaiaOperatorResponse: Codable {
    public let reply: String
    public let actions: [MaiaOperatorAction]
}
