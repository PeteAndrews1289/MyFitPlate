import Foundation
import Combine
import HealthKit


@MainActor
public class InsightsService: ObservableObject {
    @Published public var currentInsights: [UserInsight] = []
    @Published public var smartSuggestion: UserInsight? = nil
    @Published public var isLoadingInsights: Bool = false
    @Published var isGeneratingSuggestion: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
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

    // ... [generateSingleMealSuggestion, createMealSuggestionPrompt, generateDailySmartInsight remain unchanged] ...
    // (Keep existing implementations)
    public func generateSingleMealSuggestion() async -> MealSuggestion? {
        self.isGeneratingSuggestion = true
        
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
            cuisinePrefs: cuisinePrefs
        )
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

    public func generateDailySmartInsight() {
        let hour = Calendar.current.component(.hour, from: Date())
        let log = dailyLogService.currentDailyLog
        let isToday = log != nil ? Calendar.current.isDateInToday(log!.date) : false

        self.smartSuggestion = InsightsRules.determineSmartSuggestion(
            log: log,
            isToday: isToday,
            hour: hour,
            proteinGoal: goalSettings.protein
        )
    }

    public func generateAndFetchInsights(forLastDays days: Int = 7) {
        guard !isLoadingInsights else { return }

        if let lastFetch = lastWeeklyInsightFetch, !currentInsights.isEmpty, Calendar.current.isDateInToday(lastFetch) {
            return
        }

        guard let userID = DIContainer.shared.authService.currentUserID else { return }

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
    public func generateSmartNotification(context: NotificationContext) async -> (title: String, body: String)? {
        let hour = Calendar.current.component(.hour, from: Date())
        let plan = InsightsRules.notificationPlan(
            for: InsightsRules.NotificationSignals(
                gender: context.gender,
                phase: context.phase,
                wellnessScore: context.wellnessScore,
                sleepScore: context.sleepScore,
                caloriesRemaining: context.caloriesRemaining,
                proteinRemaining: context.proteinRemaining,
                daysSinceLastWorkout: context.daysSinceLastWorkout,
                lastWorkoutName: context.lastWorkoutName,
                stepsToday: context.stepsToday,
                activeEnergyToday: context.activeEnergyToday
            ),
            hour: hour
        )

        let prompt = InsightsRules.createSmartNotificationPrompt(plan: plan, gender: context.gender)

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
    public func generateDailyBriefing(for userID: String) async -> (title: String, body: String)? {
        let wellnessScoreSummary = "Good Recovery"
        let todaysWorkout = "Leg Day"

        let prompt = InsightsRules.createDailyBriefingPrompt(
            wellnessScoreSummary: wellnessScoreSummary,
            todaysWorkout: todaysWorkout
        )

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
        let sleepHours = sleepSamples.map { $0.endDate.timeIntervalSince($0.startDate) / 3600 }
        return InsightsRules.localInsights(
            from: logs,
            sleepHours: sleepHours,
            goals: InsightsRules.GoalSnapshot(
                calories: goals.calories ?? 0,
                protein: goals.protein,
                weightGoal: goals.goal
            )
        )
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

    private func handleInsightsError(message: String?, isLoading: Bool? = nil) async {
        if let isLoading = isLoading { self.isLoadingInsights = isLoading }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        self.isLoadingInsights = false
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate)
    }

    // MARK: - Maia Operator Logic
    public func processOperatorMessage(message: String, context: String) async -> MaiaOperatorResponse? {
        let prompt = InsightsRules.createOperatorPrompt(message: message, context: context)

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

    public func executeOperatorActions(_ actions: [MaiaOperatorAction], userID: String) async {
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
        return InsightsRules.determineMealType(for: date)
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
