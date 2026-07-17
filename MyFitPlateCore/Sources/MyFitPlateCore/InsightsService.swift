import Foundation
import Combine
import HealthKit


@MainActor
public class InsightsService: ObservableObject {
    @Published public var currentInsights: [UserInsight] = []
    @Published public var smartSuggestion: UserInsight? = nil
    @Published public var currentCoachingPlan: AdaptiveCoachingPlan?
    @Published public var currentRunRecoveryPrompt: RunRecoveryTarget? = nil
    @Published public var isLoadingInsights: Bool = false
    @Published public var isGeneratingSuggestion: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
    private var activeAccountID: String?
    private var analysisRequestID: UUID?
    private var suggestionRequestID: UUID?
    private var cancellables = Set<AnyCancellable>()

    private var lastWeeklyInsightFetch: Date?
    public struct NotificationContext {
        public let gender: String
        public let phase: MenstrualPhase?
        public let wellnessScore: Int?
        public let sleepScore: Int?
        public let caloriesRemaining: Double
        public let proteinRemaining: Double
        public let daysSinceLastWorkout: Int
        public let lastWorkoutName: String?
        public let stepsToday: Double
        public let activeEnergyToday: Double
        
        public init(gender: String, phase: MenstrualPhase?, wellnessScore: Int?, sleepScore: Int?, caloriesRemaining: Double, proteinRemaining: Double, daysSinceLastWorkout: Int, lastWorkoutName: String?, stepsToday: Double, activeEnergyToday: Double) {
            self.gender = gender
            self.phase = phase
            self.wellnessScore = wellnessScore
            self.sleepScore = sleepScore
            self.caloriesRemaining = caloriesRemaining
            self.proteinRemaining = proteinRemaining
            self.daysSinceLastWorkout = daysSinceLastWorkout
            self.lastWorkoutName = lastWorkoutName
            self.stepsToday = stepsToday
            self.activeEnergyToday = activeEnergyToday
        }
    }

    public init(dailyLogService: DailyLogService, goalSettings: GoalSettings, healthKitViewModel: HealthKitViewModel) {
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

    public func activateAccount(_ userID: String?) {
        guard activeAccountID != userID else { return }
        analysisTask?.cancel()
        analysisTask = nil
        analysisRequestID = nil
        suggestionRequestID = nil
        activeAccountID = userID
        currentInsights = []
        smartSuggestion = nil
        currentCoachingPlan = nil
        currentRunRecoveryPrompt = nil
        isLoadingInsights = false
        isGeneratingSuggestion = false
        lastWeeklyInsightFetch = nil
    }

    private func isActiveAccount(_ userID: String) -> Bool {
        activeAccountID == userID && DIContainer.shared.authService.currentUserID == userID
    }

    private func activateCurrentAccountIfNeeded(_ userID: String) {
        guard activeAccountID != userID else { return }
        activateAccount(userID)
    }

    public func generateSingleMealSuggestion(pantryItems: [String] = [], avoiding: [String] = []) async -> MealSuggestion? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        activateCurrentAccountIfNeeded(userID)
        let requestID = UUID()
        suggestionRequestID = requestID
        self.isGeneratingSuggestion = true
        defer {
            if suggestionRequestID == requestID {
                isGeneratingSuggestion = false
            }
        }
        
        let remainingCalories = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingProtein = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        let remainingCarbs = max(0, goalSettings.carbs - (dailyLogService.currentDailyLog?.totalMacros().carbs ?? 0))
        let remainingFats = max(0, goalSettings.fats - (dailyLogService.currentDailyLog?.totalMacros().fats ?? 0))
        
        let mealType = InsightsRules.determineMealType(for: Date())
        let proteinPrefs = goalSettings.suggestionProteins.isEmpty ? "any" : goalSettings.suggestionProteins.joined(separator: ", ")
        let carbPrefs = goalSettings.suggestionCarbs.isEmpty ? "any" : goalSettings.suggestionCarbs.joined(separator: ", ")
        let veggiePrefs = goalSettings.suggestionVeggies.isEmpty ? "any" : goalSettings.suggestionVeggies.joined(separator: ", ")
        let cuisinePrefs = (goalSettings.suggestionCuisines.isEmpty || goalSettings.suggestionCuisines.contains("Any")) ? "any" : goalSettings.suggestionCuisines.joined(separator: ", ")

        let prompt = InsightsRules.createMealSuggestionPrompt(
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            remainingCarbs: remainingCarbs,
            remainingFats: remainingFats,
            mealType: mealType,
            proteinPrefs: proteinPrefs,
            carbPrefs: carbPrefs,
            veggiePrefs: veggiePrefs,
            cuisinePrefs: cuisinePrefs,
            pantryItems: pantryItems,
            avoiding: avoiding
        )
        guard let responseString = await fetchAIResponse(prompt: prompt) else {
            return nil
        }
        guard isActiveAccount(userID), suggestionRequestID == requestID else { return nil }
        guard let jsonData = InsightsRules.extractJSONPayload(responseString).data(using: .utf8) else {
            return nil
        }

        do {
            let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: jsonData)
            return suggestion
        } catch {
            // This decode failing silently is exactly how the feature shipped dead —
            // leave a non-fatal trail with the reason.
            AppLog.ai.error("Meal suggestion decode failed: \(error.localizedDescription, privacy: .public)")
            AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_meal_suggestion")
            return nil
        }
    }

    public func generateTrainingFuelSuggestion(
        target: TrainingFuelTarget,
        pantryItems: [String] = []
    ) async -> MealSuggestion? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        activateCurrentAccountIfNeeded(userID)
        let requestID = UUID()
        suggestionRequestID = requestID
        isGeneratingSuggestion = true
        defer {
            if suggestionRequestID == requestID {
                isGeneratingSuggestion = false
            }
        }

        let initialBudget = currentTrainingFuelBudget()
        guard [
            initialBudget.calories,
            initialBudget.protein,
            initialBudget.carbs,
            initialBudget.fat
        ].allSatisfy(\.isFinite),
              initialBudget.calories >= 60 else { return nil }
        let prompt = InsightsRules.createTrainingFuelSuggestionPrompt(
            target: target,
            dailyRemainingCalories: initialBudget.calories,
            dailyRemainingFat: initialBudget.fat,
            proteinPrefs: goalSettings.suggestionProteins.isEmpty
                ? "any"
                : goalSettings.suggestionProteins.joined(separator: ", "),
            carbPrefs: goalSettings.suggestionCarbs.isEmpty
                ? "any"
                : goalSettings.suggestionCarbs.joined(separator: ", "),
            pantryItems: pantryItems
        )
        guard let responseString = await fetchAIResponse(prompt: prompt),
              let jsonData = InsightsRules.extractJSONPayload(responseString).data(using: .utf8) else {
            return nil
        }
        guard isActiveAccount(userID), suggestionRequestID == requestID else { return nil }

        do {
            let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: jsonData)
            let liveBudget = currentTrainingFuelBudget()
            guard InsightsRules.trainingFuelSuggestionFitsBudget(
                suggestion,
                target: target,
                dailyRemainingCalories: liveBudget.calories,
                dailyRemainingProtein: liveBudget.protein,
                dailyRemainingCarbs: liveBudget.carbs,
                dailyRemainingFat: liveBudget.fat
            ) else {
                AppLog.ai.error("Training fuel suggestion failed deterministic budget validation")
                return nil
            }
            return suggestion
        } catch {
            AppLog.ai.error("Training fuel suggestion decode failed: \(error.localizedDescription, privacy: .public)")
            AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_training_fuel_suggestion")
            return nil
        }
    }

    private func currentTrainingFuelBudget() -> (
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) {
        let macros = dailyLogService.currentDailyLog?.totalMacros() ?? (protein: 0, fats: 0, carbs: 0)
        return (
            calories: max(
                0,
                (goalSettings.calories ?? 0) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0)
            ),
            protein: max(0, goalSettings.protein - macros.protein),
            carbs: max(0, goalSettings.carbs - macros.carbs),
            fat: max(0, goalSettings.fats - macros.fats)
        )
    }

    public func generateDailySmartInsight() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            smartSuggestion = nil
            currentCoachingPlan = nil
            return
        }
        activateCurrentAccountIfNeeded(userID)
        let hour = Calendar.current.component(.hour, from: Date())
        let log = dailyLogService.currentDailyLog
        let isToday = log.map { Calendar.current.isDateInToday($0.date) } ?? false

        self.smartSuggestion = InsightsRules.determineSmartSuggestion(
            log: log,
            isToday: isToday,
            hour: hour,
            proteinGoal: goalSettings.protein
        )
        self.currentCoachingPlan = InsightsRules.adaptiveCoachingPlan(
            today: log,
            recentLogs: log.map { [$0] } ?? [],
            sleepHours: self.healthKitViewModel?.sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) / 3600 } ?? [],
            hrvAverage: self.healthKitViewModel?.hrvAverage,
            goals: goalSnapshot(),
            now: Date()
        )
    }

    public func generateAndFetchInsights(
        forLastDays days: Int = 7,
        requestConsentIfNeeded: Bool = false
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        activateCurrentAccountIfNeeded(userID)
        guard !isLoadingInsights else { return }

        let hasAIConsent = AIDataConsentStore.shared.hasCurrentConsent(for: userID)
        let mayShareHealthData = AIDataConsentStore.shared.allowsHealthData(for: userID)
        if requestConsentIfNeeded && !hasAIConsent {
            NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
        }

        if let lastFetch = lastWeeklyInsightFetch, !currentInsights.isEmpty, Calendar.current.isDateInToday(lastFetch) {
            return
        }

        let sleepData = self.healthKitViewModel?.sleepSamples ?? []
        let requestID = UUID()

        isLoadingInsights = true
        analysisTask?.cancel()
        analysisRequestID = requestID

        analysisTask = Task {
            let endDate = Calendar.current.startOfDay(for: Date())
            guard let startDate = Calendar.current.date(byAdding: .day, value: -(days), to: endDate) else {
                self.handleInsightsError(
                    message: "Could not calculate date range for insights.",
                    userID: userID,
                    requestID: requestID
                )
                return
            }

            let result = await self.fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)

            guard !Task.isCancelled,
                  self.isActiveAccount(userID),
                  self.analysisRequestID == requestID else { return }

            switch result {
            case .success(let logs):
                self.currentCoachingPlan = InsightsRules.adaptiveCoachingPlan(
                    today: logs.first { Calendar.current.isDateInToday($0.date) },
                    recentLogs: logs,
                    sleepHours: sleepData.map { $0.endDate.timeIntervalSince($0.startDate) / 3600 },
                    hrvAverage: self.healthKitViewModel?.hrvAverage,
                    goals: self.goalSnapshot(),
                    now: Date()
                )

                if logs.count < 3 {
                    let noDataInsight = [UserInsight(title: "More Data Needed", message: "Log consistently for a few more days to unlock your personalized weekly insights!", category: .nutritionGeneral, priority: 100)]
                    self.handleInsightsResult(insights: noDataInsight, error: nil, userID: userID, requestID: requestID)
                    return
                }

                let aiInsights: [UserInsight]
                if hasAIConsent {
                    aiInsights = await self.generateAIInsights(
                        for: logs,
                        sleepSamples: sleepData,
                        goals: self.goalSettings,
                        allowsHealthData: mayShareHealthData,
                        retryCount: 1
                    )
                } else {
                    aiInsights = self.generateLocalInsights(
                        from: logs,
                        sleepSamples: sleepData,
                        goals: self.goalSettings
                    )
                }

                guard !Task.isCancelled,
                      self.isActiveAccount(userID),
                      self.analysisRequestID == requestID else { return }
                self.handleInsightsResult(
                    insights: aiInsights,
                    error: aiInsights.isEmpty ? "Could not generate insights at this time." : nil,
                    userID: userID,
                    requestID: requestID
                )

            case .failure(let error):
                self.handleInsightsError(
                    message: "Could not analyze data: \(error.localizedDescription)",
                    userID: userID,
                    requestID: requestID
                )
            }
        }
    }

    // MARK: - Smart Notification Logic (Fixed "700k Days" Bug)
    public func generateSmartNotification(context: NotificationContext) async -> (title: String, body: String)? {
        guard let userID = DIContainer.shared.authService.currentUserID,
              AIDataConsentStore.shared.hasCurrentConsent(for: userID) else { return nil }

        let hour = Calendar.current.component(.hour, from: Date())
        let mayShareHealthData = allowsHealthDataInAIRequests
        let plan = InsightsRules.notificationPlan(
            for: InsightsRules.NotificationSignals(
                gender: context.gender,
                phase: context.phase,
                wellnessScore: mayShareHealthData ? context.wellnessScore : nil,
                sleepScore: mayShareHealthData ? context.sleepScore : nil,
                caloriesRemaining: context.caloriesRemaining,
                proteinRemaining: context.proteinRemaining,
                daysSinceLastWorkout: context.daysSinceLastWorkout,
                lastWorkoutName: context.lastWorkoutName,
                stepsToday: mayShareHealthData ? context.stepsToday : 0,
                activeEnergyToday: mayShareHealthData ? context.activeEnergyToday : 0
            ),
            hour: hour
        )

        let prompt = InsightsRules.createSmartNotificationPrompt(plan: plan, gender: context.gender)

        guard let responseString = await fetchAIResponse(prompt: prompt),
              let data = responseString.data(using: .utf8) else { return nil }
        guard isActiveAccount(userID) else { return nil }

        struct NotificationResponse: Decodable {
            let title: String
            let body: String
        }

        do {
            let decoded = try JSONDecoder().decode(NotificationResponse.self, from: data)
            return (decoded.title, decoded.body)
        } catch {
            AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_smart_notification")
            return nil
        }
    }

    /// NOT WIRED UP — no caller schedules this (scheduleDailyBriefingNotification is itself
    /// uncalled). ⚠️ LANDMINE: `wellnessScoreSummary` and `todaysWorkout` below are HARDCODED
    /// placeholders. Do NOT schedule the daily briefing without first feeding them the real
    /// wellness score (HealthKitViewModel.sleepSummary.lastNightScore) and today's program
    /// day (WorkoutService.activeProgram) — otherwise every briefing tells the user "Good
    /// Recovery" and "Leg Day" regardless of reality. This is the fill-my-macros trap:
    /// orphan code that looks done but lies. Test its output path before wiring it.
    public func generateDailyBriefing(
        for userID: String,
        wellnessScoreSummary: String,
        todaysWorkout: String
    ) async -> (title: String, body: String)? {
        guard isActiveAccount(userID) else { return nil }
        let prompt = InsightsRules.createDailyBriefingPrompt(
            wellnessScoreSummary: wellnessScoreSummary,
            todaysWorkout: todaysWorkout
        )

        guard let response = await fetchAIResponse(prompt: prompt),
              let data = response.data(using: .utf8) else { return nil }
        guard isActiveAccount(userID) else { return nil }

        struct BriefingResponse: Decodable {
            let title: String
            let body: String
        }

        do {
            let decoded = try JSONDecoder().decode(BriefingResponse.self, from: data)
            return (title: decoded.title, body: decoded.body)
        } catch {
            AppLog.ai.error("Failed to decode daily briefing: \(error.localizedDescription, privacy: .public)")
            AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_daily_briefing")
            return nil
        }
    }

    private func handleInsightsResult(
        insights: [UserInsight],
        error: String?,
        userID: String,
        requestID: UUID
    ) {
        guard isActiveAccount(userID), analysisRequestID == requestID else { return }
        self.isLoadingInsights = false
        if let errorMessage = error {
            self.currentInsights = [UserInsight(title: "Insight Error", message: errorMessage, category: .nutritionGeneral)]
        } else {
            self.currentInsights = insights
            self.lastWeeklyInsightFetch = Date()
        }
    }

    private func generateAIInsights(
        for logs: [DailyLog],
        sleepSamples: [HKCategorySample],
        goals: GoalSettings,
        allowsHealthData: Bool,
        retryCount: Int
    ) async -> [UserInsight] {
        let healthDataForAI = allowsHealthData ? sleepSamples : []
        let prompt = createAIPrompt(logs: logs, sleepSamples: healthDataForAI, goals: goals)

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
            AIResponseTelemetry.recordDecodeFailure(
                error,
                operation: "decode_generated_insights",
                willRetry: retryCount > 0
            )
            if retryCount > 0 {
                AppLog.ai.info("Retrying insights generation.")
                return await generateAIInsights(
                    for: logs,
                    sleepSamples: sleepSamples,
                    goals: goals,
                    allowsHealthData: allowsHealthData,
                    retryCount: retryCount - 1
                )
            }
            return generateLocalInsights(from: logs, sleepSamples: sleepSamples, goals: goals)
        }
    }

    private func generateLocalInsights(from logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> [UserInsight] {
        let sleepHours = sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) / 3600 }
        return InsightsRules.localInsights(
            from: logs,
            sleepHours: sleepHours,
            goals: goalSnapshot(from: goals)
        )
    }

    private func goalSnapshot(from goals: GoalSettings? = nil) -> InsightsRules.GoalSnapshot {
        let goals = goals ?? goalSettings
        return InsightsRules.GoalSnapshot(
            calories: goals.calories ?? 0,
            protein: goals.protein,
            weightGoal: goals.goal
        )
    }

    private var allowsHealthDataInAIRequests: Bool {
        guard let userID = DIContainer.shared.authService.currentUserID else { return false }
        return AIDataConsentStore.shared.allowsHealthData(for: userID)
    }

    private var hasCurrentAIConsent: Bool {
        guard let userID = DIContainer.shared.authService.currentUserID else { return false }
        return AIDataConsentStore.shared.hasCurrentConsent(for: userID)
    }

    private func createAIPrompt(logs: [DailyLog], sleepSamples: [HKCategorySample], goals: GoalSettings) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE"

        let dailyNutritionSummary = logs.map { log -> String in
            let day = dateFormatter.string(from: log.date)
            let macros = log.totalMacros()
            let fiber = log.micronutrientCoverage(for: .fiber).hasReportedData
                ? "\(Int(log.totalMicronutrient(.fiber)))g"
                : "not reported"
            let sodium = log.micronutrientCoverage(for: .sodium).hasReportedData
                ? "\(Int(log.totalMicronutrient(.sodium)))mg"
                : "not reported"
            return "- \(day): Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g, Fiber: \(fiber), Sodium: \(sodium)"
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

        return InsightsRules.createAIPrompt(
            dailyNutritionSummary: dailyNutritionSummary,
            dailyWorkoutSummary: dailyWorkoutSummary,
            sleepSummaryString: sleepSummaryString,
            journalSummary: journalSummary,
            userGoals: userGoals
        )
    }

    private func fetchAIResponse(prompt: String) async -> String? {
        let result = await DIContainer.shared.aiService.performRequest(
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

    private func handleInsightsError(message: String?, userID: String, requestID: UUID) {
        guard isActiveAccount(userID), analysisRequestID == requestID else { return }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        self.isLoadingInsights = false
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate)
    }

    // MARK: - Maia Operator Logic
    public func processOperatorMessage(message: String, context: String) async -> MaiaOperatorResponse? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        activateCurrentAccountIfNeeded(userID)
        let prompt = InsightsRules.createOperatorPrompt(message: message, context: context)

        guard let responseString = await fetchAIResponse(prompt: prompt),
              let data = responseString.data(using: .utf8) else {
            return nil
        }
        guard isActiveAccount(userID) else { return nil }

        do {
            let decoded = try JSONDecoder().decode(MaiaOperatorResponse.self, from: data)
            return decoded
        } catch {
            AppLog.ai.error("Failed to decode operator response: \(error.localizedDescription, privacy: .public)")
            AIResponseTelemetry.recordDecodeFailure(error, operation: "decode_operator_response")
            return nil
        }
    }

    public func executeOperatorActions(_ actions: [MaiaOperatorAction], userID: String) async {
        guard isActiveAccount(userID) else { return }
        for action in actions {
            guard isActiveAccount(userID) else { return }
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
        return InsightsRules.determineMealType(for: date)
    }

    public func evaluateRunRecoveryPrompt(recentRun: Run?, weightLbs: Double = 165.0) {
        guard let run = recentRun else {
            self.currentRunRecoveryPrompt = nil
            return
        }
        if let target = RunRecoveryRules.calculateTarget(for: run, weightLbs: weightLbs), !target.isExpired {
            self.currentRunRecoveryPrompt = target
        } else {
            self.currentRunRecoveryPrompt = nil
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
