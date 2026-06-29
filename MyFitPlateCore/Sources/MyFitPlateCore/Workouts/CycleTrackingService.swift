import Foundation
import HealthKit
@MainActor
public class CycleTrackingService: ObservableObject {
    @Published public var cycleDay: CycleDay?
    @Published public var cycleSettings = CycleSettings() {
        didSet {
            saveCycleSettings()
            calculateCurrentCycleDay()
        }
    }
    @Published public var aiInsight: AIInsight?
    @Published public var isLoadingInsight = false

    private let healthKitManager = HealthKitManager.shared
    private var lastPeriodStartDate: Date? {
        didSet {
            UserDefaults.standard.set(lastPeriodStartDate, forKey: "lastPeriodStartDate")
        }
    }

    private var goalSettings: GoalSettings?
    private var dailyLogService: DailyLogService?

    public init() {
        loadCycleSettings()
        calculateCurrentCycleDay()
    }

    public func setupDependencies(goalSettings: GoalSettings, dailyLogService: DailyLogService) {
        self.goalSettings = goalSettings
        self.dailyLogService = dailyLogService
    }

    public func logPeriodStart() {
        lastPeriodStartDate = Calendar.current.startOfDay(for: Date())
        calculateCurrentCycleDay()
        fetchAIInsight()
    }

    public func clearLastPeriodStart() {
        lastPeriodStartDate = nil
        calculateCurrentCycleDay()
        fetchAIInsight()
    }

    public func calculateCurrentCycleDay() {
        guard let startDate = lastPeriodStartDate else {
            self.cycleDay = nil
            return
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        let components = Calendar.current.dateComponents([.day], from: startDate, to: today)
        let dayNumber = (components.day ?? 0) + 1
        
        let phase = determinePhase(cycleDay: dayNumber)
        self.cycleDay = CycleDay(date: today, cycleDayNumber: dayNumber, phase: phase)
    }

    private func determinePhase(cycleDay: Int) -> MenstrualPhase {
        let periodEnd = cycleSettings.typicalPeriodLength
        let ovulationStart = (cycleSettings.typicalCycleLength / 2) - 2
        let ovulationEnd = (cycleSettings.typicalCycleLength / 2) + 2

        if cycleDay <= periodEnd {
            return .menstrual
        } else if cycleDay > periodEnd && cycleDay < ovulationStart {
            return .follicular
        } else if cycleDay >= ovulationStart && cycleDay <= ovulationEnd {
            return .ovulatory
        } else {
            return .luteal
        }
    }
    
    private func saveCycleSettings() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(cycleSettings) {
            UserDefaults.standard.set(encoded, forKey: "cycleSettings")
        }
    }
    
    private func loadCycleSettings() {
        if let data = UserDefaults.standard.data(forKey: "cycleSettings") {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(CycleSettings.self, from: data) {
                self.cycleSettings = decoded
            }
        }
        self.lastPeriodStartDate = UserDefaults.standard.object(forKey: "lastPeriodStartDate") as? Date
    }

    public func fetchAIInsight() {
        guard let currentPhase = cycleDay?.phase, let goalSettings = goalSettings else { return }
        isLoadingInsight = true
        
        Task {
            let recentLogsResult = await dailyLogService?.fetchDailyHistory(for: DIContainer.shared.authService.currentUserID ?? "", startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()), endDate: Date())
            var logSummary = "No recent activity logged."
            if let recentLogs = recentLogsResult, case .success(let logs) = recentLogs, !logs.isEmpty {
                logSummary = logs.map { log in
                    let macros = log.totalMacros()
                    return "Date: \(log.date.formatted(date: .abbreviated, time: .omitted)), Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g"
                }.joined(separator: "\n")
            }

            let prompt = """
            You are an elite female physiology and performance coach for the MyFitPlate app.
            The user is on Day \(cycleDay?.cycleDayNumber ?? 1) of their cycle, in the \(currentPhase.rawValue) phase.
            Their primary goal is to \(goalSettings.goal) weight.
            Their recent activity:\n\(logSummary)
            
            Your response MUST be a valid JSON object. Do not include any other text.
            The JSON object must have these exact keys: "phaseTitle", "phaseDescription", "trainingFocus", "hormonalState", "energyLevel", "nutritionTip", "symptomTip".
            - "phaseTitle": A short, empowering title for this phase (e.g., "Your Power Phase").
            - "phaseDescription": A detailed, scientific-yet-accessible description of what's happening in her body.
            - "trainingFocus": An object with "title" and "description" keys for workout advice.
            - "hormonalState": A summary of key hormone levels (e.g., "Peak Estrogen, Rising Progesterone").
            - "energyLevel": A simple descriptor (e.g., "Peak", "High", "Moderate", "Low").
            - "nutritionTip": A specific, actionable nutrition tip for this phase, referencing her recent logs if possible.
            - "symptomTip": A helpful tip for managing common symptoms of this phase.
            """
            let response = await fetchAIResponse(prompt: prompt)
            
            self.isLoadingInsight = false
            if let responseData = response?.data(using: .utf8) {
                do {
                    self.aiInsight = try JSONDecoder().decode(AIInsight.self, from: responseData)
                } catch {
                    AppLog.app.error("Error decoding cycle AI insight: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        let result = await DIContainer.shared.aiService.performRequest(
            messages: [["role": "user", "content": prompt]],
            model: "gpt-4o-mini",
            maxTokens: 800,
            temperature: 0.6,
            responseFormat: ["type": "json_object"]
        )

        switch result {
        case .success(let content):
            return content
        case .failure(let error):
            AppLog.app.error("Cycle AI fetch error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
