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
        
        let phase = CycleTrackingRules.determinePhase(
            cycleDay: dayNumber,
            typicalPeriodLength: cycleSettings.typicalPeriodLength,
            typicalCycleLength: cycleSettings.typicalCycleLength
        )
        self.cycleDay = CycleDay(date: today, cycleDayNumber: dayNumber, phase: phase)
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
        let currentCycleDayNum = cycleDay?.cycleDayNumber ?? 1
        let goalString = goalSettings.goal
        isLoadingInsight = true
        
        Task {
            let recentLogsResult = await dailyLogService?.fetchDailyHistory(for: DIContainer.shared.authService.currentUserID ?? "", startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()), endDate: Date())
            var logs: [DailyLog] = []
            if let recentLogs = recentLogsResult, case .success(let fetchedLogs) = recentLogs {
                logs = fetchedLogs
            }

            let prompt = CycleTrackingRules.createAIInsightPrompt(
                cycleDayNumber: currentCycleDayNum,
                phase: currentPhase,
                goal: goalString,
                recentLogs: logs
            )
            
            let response = await fetchAIResponse(prompt: prompt)
            
            self.isLoadingInsight = false
            if let responseDataString = response {
                do {
                    self.aiInsight = try CycleTrackingRules.parseAIInsightResponse(responseDataString)
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
