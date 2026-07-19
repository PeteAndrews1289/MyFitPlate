import CryptoKit
import Foundation
import HealthKit
@MainActor
public class CycleTrackingService: ObservableObject {
    @Published public var cycleDay: CycleDay?
    @Published public var cycleSettings = CycleSettings() {
        didSet {
            guard !isRestoringAccount else { return }
            saveCycleSettings()
            calculateCurrentCycleDay()
        }
    }
    @Published public var aiInsight: AIInsight?
    @Published public var isLoadingInsight = false

    private let healthKitManager = HealthKitManager.shared
    private var lastPeriodStartDate: Date? {
        didSet {
            guard !isRestoringAccount, let activeUserID else { return }
            let key = Self.periodStartStorageKey(for: activeUserID)
            if let lastPeriodStartDate {
                defaults.set(lastPeriodStartDate, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private let defaults: UserDefaults
    private var activeUserID: String?
    private var isRestoringAccount = false
    private var insightTask: Task<Void, Never>?
    private var goalSettings: GoalSettings?
    private var dailyLogService: DailyLogService?

    public init(
        userID: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        activateAccount(userID)
    }

    public func setupDependencies(goalSettings: GoalSettings, dailyLogService: DailyLogService) {
        self.goalSettings = goalSettings
        self.dailyLogService = dailyLogService
    }

    public func activateAccount(_ userID: String?) {
        guard activeUserID != userID else {
            calculateCurrentCycleDay()
            return
        }

        isRestoringAccount = true
        insightTask?.cancel()
        insightTask = nil
        activeUserID = userID
        aiInsight = nil
        cycleDay = nil
        cycleSettings = CycleSettings()
        lastPeriodStartDate = nil

        if let userID, !userID.isEmpty {
            migrateLegacyStorageIfNeeded(for: userID)
            loadCycleSettings(for: userID)
        }

        isRestoringAccount = false
        calculateCurrentCycleDay()
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
        guard let activeUserID else { return }
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(cycleSettings) {
            defaults.set(encoded, forKey: Self.settingsStorageKey(for: activeUserID))
        }
    }
    
    private func loadCycleSettings(for userID: String) {
        if let data = defaults.data(forKey: Self.settingsStorageKey(for: userID)) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(CycleSettings.self, from: data) {
                self.cycleSettings = decoded
            }
        }
        self.lastPeriodStartDate = defaults.object(forKey: Self.periodStartStorageKey(for: userID)) as? Date
    }

    private func migrateLegacyStorageIfNeeded(for userID: String) {
        let settingsKey = Self.settingsStorageKey(for: userID)
        let periodKey = Self.periodStartStorageKey(for: userID)
        if defaults.data(forKey: settingsKey) == nil,
           let legacySettings = defaults.data(forKey: "cycleSettings") {
            defaults.set(legacySettings, forKey: settingsKey)
        }
        if defaults.object(forKey: periodKey) == nil,
           let legacyPeriodStart = defaults.object(forKey: "lastPeriodStartDate") as? Date {
            defaults.set(legacyPeriodStart, forKey: periodKey)
        }
        defaults.removeObject(forKey: "cycleSettings")
        defaults.removeObject(forKey: "lastPeriodStartDate")
    }

    static func settingsStorageKey(for userID: String) -> String {
        "cycle_settings_\(accountDigest(userID))"
    }

    static func periodStartStorageKey(for userID: String) -> String {
        "cycle_period_start_\(accountDigest(userID))"
    }

    private static func accountDigest(_ userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func fetchAIInsight(requestConsentIfNeeded: Bool = false) {
        guard let currentPhase = cycleDay?.phase, let goalSettings = goalSettings else { return }
        guard let userID = DIContainer.shared.authService.currentUserID,
              userID == activeUserID,
              AIDataConsentStore.shared.hasCurrentConsent(for: userID) else {
            aiInsight = nil
            isLoadingInsight = false
            if requestConsentIfNeeded {
                NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            }
            return
        }
        let currentCycleDayNum = cycleDay?.cycleDayNumber ?? 1
        let goalString = goalSettings.goal
        isLoadingInsight = true

        insightTask?.cancel()
        insightTask = Task {
            let recentLogsResult = await dailyLogService?.fetchDailyHistory(for: userID, startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()), endDate: Date())
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

            guard !Task.isCancelled, activeUserID == userID else { return }
            self.isLoadingInsight = false
            self.insightTask = nil
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
