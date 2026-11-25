import Foundation
import Combine
import HealthKit


@MainActor
public class InsightsService: ObservableObject {
    @Published public var currentInsights: [UserInsight] = []
    @Published public private(set) var insightReports: [SavedInsightReport] = []
    @Published public private(set) var insightHistoryNotice: String?
    private var requestedInsightWindow: (start: Date, end: Date)?
    private var requestedInsightGoals: InsightsRules.GoalSnapshot?
    private var lastWeeklyInsightWindowDays: Int?
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
    private var coachingLogs: [DailyLog] = []
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

        healthKitViewModel.$sleepSamples.map { _ in () }
            .merge(with: healthKitViewModel.$hrvHistorySamples.map { _ in () })
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.generateDailySmartInsight()
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
        insightReports = []
        insightHistoryNotice = nil
        requestedInsightWindow = nil
        requestedInsightGoals = nil
        lastWeeklyInsightWindowDays = nil
        if let userID {
            do { insightReports = try InsightReportStore().reports(userID: userID) } catch { insightHistoryNotice = "Saved insight reports could not be opened. Their files are kept on this device." }
        }
        smartSuggestion = nil
        currentCoachingPlan = nil
        coachingLogs = []
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

    public func generateSingleMealSuggestion(pantryItems: [String] = [], avoiding: [String] = [], alternative: MealSuggestionAlternativeReason? = nil, day: DiaryDayContext? = nil) async -> MealSuggestion? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        activateCurrentAccountIfNeeded(userID)
        let constraints = goalSettings.effectiveMealConstraintProfile
        do { try constraints?.validate() } catch { return nil }
        let requestID = UUID()
        suggestionRequestID = requestID
        self.isGeneratingSuggestion = true
        defer {
            if suggestionRequestID == requestID {
                isGeneratingSuggestion = false
            }
        }
        
        guard let initialBudget = await budgetForMealSuggestion(on: day, userID: userID),
              initialBudget.isValid, initialBudget.calories > 0 else { return nil }
        let remainingCalories = initialBudget.calories, remainingProtein = initialBudget.protein
        let remainingCarbs = initialBudget.carbs, remainingFats = initialBudget.fats
        let capturedDayID = dailyLogService.currentDailyLog?.id
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
        guard let responseString = await fetchAIResponse(prompt: prompt + "\n" + (constraints?.prompt ?? "") + "\n" + (alternative?.instruction ?? "")) else {
            return nil
        }
        guard isActiveAccount(userID), suggestionRequestID == requestID else { return nil }
        guard let jsonData = InsightsRules.extractJSONPayload(responseString).data(using: .utf8) else {
            return nil
        }

        do {
            let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: jsonData).withGeneratedEvidence()
            guard let budget = await budgetForMealSuggestion(on: day, userID: userID), suggestionRequestID == requestID,
                  day != nil || dailyLogService.currentDailyLog?.id == capturedDayID,
                  goalSettings.effectiveMealConstraintProfile == constraints,
                  !MealConstraintRules.report(candidate: suggestion.constraintCandidate, profile: constraints).isBlocked,
                  MealSuggestionFeasibilityRules.fitsGeneration(suggestion, remaining: .init(calories: budget.calories, protein: budget.protein, carbs: budget.carbs, fats: budget.fats)),
                  alternative != .vegetarian || !MealConstraintRules.report(candidate: suggestion.constraintCandidate,
                      profile: MealConstraintProfile(diet: .vegetarian)).isBlocked else { return nil }
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
        pantryItems: [String] = [],
        alternative: MealSuggestionAlternativeReason? = nil
    ) async -> MealSuggestion? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        activateCurrentAccountIfNeeded(userID)
        let constraints = goalSettings.effectiveMealConstraintProfile
        do { try constraints?.validate() } catch { return nil }
        let requestID = UUID()
        suggestionRequestID = requestID
        isGeneratingSuggestion = true
        defer {
            if suggestionRequestID == requestID {
                isGeneratingSuggestion = false
            }
        }

        let capturedDay = target.context.flatMap { context in
            context.day.date(calendar: context.calendar).flatMap { DiaryDayContext(userID: context.ownerID, date: $0, timeZone: context.calendar.timeZone) }
        }
        guard let initialBudget = await budgetForMealSuggestion(on: capturedDay, userID: userID) else { return nil }
        guard [
            initialBudget.calories,
            initialBudget.protein,
            initialBudget.carbs,
            initialBudget.fats
        ].allSatisfy(\.isFinite),
              initialBudget.calories >= 60 else { return nil }
        let prompt = InsightsRules.createTrainingFuelSuggestionPrompt(
            target: target,
            dailyRemainingCalories: initialBudget.calories,
            dailyRemainingFat: initialBudget.fats,
            proteinPrefs: goalSettings.suggestionProteins.isEmpty
                ? "any"
                : goalSettings.suggestionProteins.joined(separator: ", "),
            carbPrefs: goalSettings.suggestionCarbs.isEmpty
                ? "any"
                : goalSettings.suggestionCarbs.joined(separator: ", "),
            pantryItems: pantryItems
        )
        guard let responseString = await fetchAIResponse(prompt: prompt + "\n" + (constraints?.prompt ?? "") + "\n" + (alternative?.instruction ?? "")),
              let jsonData = InsightsRules.extractJSONPayload(responseString).data(using: .utf8) else {
            return nil
        }
        guard isActiveAccount(userID), suggestionRequestID == requestID else { return nil }

        do {
            let suggestion = try JSONDecoder().decode(MealSuggestion.self, from: jsonData).withGeneratedEvidence()
            guard goalSettings.effectiveMealConstraintProfile == constraints,
                  !MealConstraintRules.report(candidate: suggestion.constraintCandidate, profile: constraints).isBlocked else { return nil }
            guard let liveBudget = await budgetForMealSuggestion(on: capturedDay, userID: userID), suggestionRequestID == requestID else { return nil }
            guard alternative != .vegetarian || !MealConstraintRules.report(candidate: suggestion.constraintCandidate,
                profile: MealConstraintProfile(diet: .vegetarian)).isBlocked else { return nil }
            guard InsightsRules.trainingFuelSuggestionFitsBudget(
                suggestion,
                target: target,
                dailyRemainingCalories: liveBudget.calories,
                dailyRemainingProtein: liveBudget.protein,
                dailyRemainingCarbs: liveBudget.carbs,
                dailyRemainingFat: liveBudget.fats
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

    private func budgetForMealSuggestion(on day: DiaryDayContext?, userID: String) async -> MealSuggestionBudget? {
        guard isActiveAccount(userID) else { return nil }
        guard let day else {
            let value = currentTrainingFuelBudget()
            return .init(calories: value.calories, protein: value.protein, carbs: value.carbs, fats: value.fat)
        }
        guard day.isOwned(by: userID) else { return nil }
        let result: Result<DailyLog, Error> = await withCheckedContinuation { continuation in
            dailyLogService.fetchLogInternal(for: userID, day: day) { continuation.resume(returning: $0) }
        }
        guard isActiveAccount(userID), case .success(let log) = result, log.id == day.dayKey else { return nil }
        return MealSuggestionBudget(calories: goalSettings.calories ?? 0, protein: goalSettings.protein,
            carbs: goalSettings.carbs, fats: goalSettings.fats).subtracting(log)
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
            recentLogs: coachingLogs.filter { cached in
                !Calendar.current.isDate(cached.date, inSameDayAs: log?.date ?? .distantPast)
            } + (log.map { [$0] } ?? []),
            recovery: self.healthKitViewModel?.coachingRecoveryEvidence() ?? .unavailable,
            goals: goalSnapshot(),
            now: Date()
        )
    }

    public func generateAndFetchInsights(
        forLastDays days: Int = 7,
        requestConsentIfNeeded: Bool = false,
        forceRefresh: Bool = false
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        activateCurrentAccountIfNeeded(userID)
        guard !isLoadingInsights else { return }

        let hasAIConsent = AIDataConsentStore.shared.hasCurrentConsent(for: userID)
        let mayShareHealthData = AIDataConsentStore.shared.allowsHealthData(for: userID)
        if requestConsentIfNeeded && !hasAIConsent {
            NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
        }

        if !forceRefresh, insightHistoryNotice == nil, lastWeeklyInsightWindowDays == max(1, min(90, days)),
           let lastFetch = lastWeeklyInsightFetch, !currentInsights.isEmpty, Calendar.current.isDateInToday(lastFetch) {
            return
        }

        let sleepData = self.healthKitViewModel?.sleepSamples ?? []
        requestedInsightGoals = goalSnapshot()
        let requestID = UUID()

        isLoadingInsights = true
        analysisTask?.cancel()
        analysisRequestID = requestID

        analysisTask = Task {
            let endDate = Calendar.current.startOfDay(for: Date())
            guard let startDate = Calendar.current.date(byAdding: .day, value: -(max(1, min(90, days)) - 1), to: endDate) else {
                self.handleInsightsError(
                    message: "Could not calculate date range for insights.",
                    userID: userID,
                    requestID: requestID
                )
                return
            }

            requestedInsightWindow = (startDate, endDate)
            let result = await self.fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)

            guard !Task.isCancelled,
                  self.isActiveAccount(userID),
                  self.analysisRequestID == requestID else { return }

            switch result {
            case .success(let logs):
                self.coachingLogs = logs
                self.currentCoachingPlan = InsightsRules.adaptiveCoachingPlan(
                    today: logs.first { Calendar.current.isDateInToday($0.date) },
                    recentLogs: logs,
                    recovery: self.healthKitViewModel?.coachingRecoveryEvidence() ?? .unavailable,
                    goals: self.goalSnapshot(),
                    now: Date()
                )

                if logs.count < 3 {
                    let noDataInsight = [UserInsight(title: "More Data Needed", message: "Log consistently for a few more days to unlock your personalized weekly insights!", category: .nutritionGeneral, priority: 100)]
                    self.handleInsightsResult(insights: self.attachInsightEvidence(noDataInsight, logs: logs, sleepSamples: [], origin: .localRules), error: nil, userID: userID, requestID: requestID)
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
            if let window = requestedInsightWindow {
                lastWeeklyInsightWindowDays = (Calendar.current.dateComponents([.day], from: window.start, to: window.end).day ?? 0) + 1
            }
            if let evidence = insights.first?.evidence {
                do {
                    try InsightReportStore().record(.init(evidence: evidence, insights: insights), currentUserID: userID)
                    insightReports = try InsightReportStore().reports(userID: userID)
                    insightHistoryNotice = nil
                } catch {
                    insightHistoryNotice = "This report is visible, but its history could not be saved on this device. Refresh to retry."
                }
            }
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
            return attachInsightEvidence(insightsResponse["insights"] ?? [], logs: logs,
                sleepSamples: healthDataForAI, origin: .aiInterpretation)
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
        let start = requestedInsightWindow?.start ?? Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        let end = requestedInsightWindow?.end ?? Date()
        let sleepByNight = SleepEvidenceRules.hoursByNight(from: sleepSamples).filter { $0.key >= start && $0.key <= end }
        let values = InsightsRules.localInsights(from: logs, sleepHours: Array(sleepByNight.values), goals: requestedInsightGoals ?? goalSnapshot(from: goals))
        return attachInsightEvidence(values, logs: logs, sleepSamples: sleepSamples, origin: .localRules)
    }

    private func attachInsightEvidence(_ insights: [UserInsight], logs: [DailyLog],
                                       sleepSamples: [HKCategorySample], origin: InsightEvidenceSnapshot.Origin) -> [UserInsight] {
        guard let ownerID = activeAccountID, isActiveAccount(ownerID) else { return [] }
        let now = Date()
        let start = requestedInsightWindow?.start ?? Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now
        let end = requestedInsightWindow?.end ?? now
        do {
            let evidence = try InsightEvidenceSnapshot(ownerID: ownerID, logs: logs,
                sleepHoursByNight: SleepEvidenceRules.hoursByNight(from: sleepSamples),
                calorieGoal: requestedInsightGoals?.calories ?? goalSettings.calories ?? 0,
                proteinGoal: requestedInsightGoals?.protein ?? goalSettings.protein,
                start: start, end: end, origin: origin, now: now)
            return insights.map { $0.attaching(evidence) }
        } catch {
            insightHistoryNotice = "Input evidence could not be recorded. These observations are not saved as verified reports."
            return insights.map { value in var copy = value; copy.evidence = nil; return copy }
        }
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

        let dailyNutritionSummary = NutritionDayEvidence.historicalSummary(logs)

        let dailyWorkoutSummary = logs.compactMap { log -> String? in
            guard let exercises = log.exercises, !exercises.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let totalBurn = exercises.reduce(0) { $0 + $1.caloriesBurned }
            let exerciseNames = exercises.map { $0.name }.joined(separator: ", ")
            return "- \(day): Burned \(Int(totalBurn)) calories from \(exerciseNames)."
        }.joined(separator: "\n")

        let sleepHoursByNight = SleepEvidenceRules.hoursByNight(from: sleepSamples).filter { date, _ in
            guard let window = requestedInsightWindow else { return true }
            let day = Calendar.current.startOfDay(for: date)
            return day >= window.start && day <= window.end
        }
        let sleepSummaryString = sleepHoursByNight.keys.sorted().map { date -> String in
            let day = dateFormatter.string(from: date)
            let hours = sleepHoursByNight[date] ?? 0
            return "- Night beginning \(day): \(String(format: "%.1f", hours)) hours asleep"
        }.joined(separator: "\n")

        let journalSummary = logs.compactMap { log -> String? in
            guard let entries = log.journalEntries, !entries.isEmpty else { return nil }
            let day = dateFormatter.string(from: log.date)
            let entrySummaries = entries.map { "\($0.category): \($0.text)" }.joined(separator: "; ")
            return "- \(day): \(entrySummaries)"
        }.joined(separator: "\n")

        let capturedGoals = requestedInsightGoals ?? goalSnapshot(from: goals)
        let userGoals = """
        User's Goals:
        - Calorie Target: \(Int(capturedGoals.calories)) kcal
        - Protein Target: \(Int(capturedGoals.protein))g
        - Fiber Target: 25g
        - Sodium Limit: 2300mg
        - Weight Goal: \(capturedGoals.weightGoal)
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
            model: "gpt-6-astra",
            temperature: 0.7,
            responseFormat: ["type": "json_object"], requestKind: .coaching
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
