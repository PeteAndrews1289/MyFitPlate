import Foundation
import HealthKit
import FirebaseAuth

class CycleTrackingService: ObservableObject {
    @Published var cycleDay: CycleDay?
    @Published var cycleSettings = CycleSettings() {
        didSet {
            saveCycleSettings()
            calculateCurrentCycleDay()
        }
    }
    @Published var aiInsight: AIInsight?
    @Published var isLoadingInsight = false

    private let healthKitManager = HealthKitManager.shared
    private let apiKey = getAPIKey()
    private var lastPeriodStartDate: Date? {
        didSet {
            UserDefaults.standard.set(lastPeriodStartDate, forKey: "lastPeriodStartDate")
        }
    }

    private var goalSettings: GoalSettings?
    private var dailyLogService: DailyLogService?

    init() {
        loadCycleSettings()
        calculateCurrentCycleDay()
    }

    func setupDependencies(goalSettings: GoalSettings, dailyLogService: DailyLogService) {
        self.goalSettings = goalSettings
        self.dailyLogService = dailyLogService
    }

    func logPeriodStart() {
        lastPeriodStartDate = Calendar.current.startOfDay(for: Date())
        calculateCurrentCycleDay()
        fetchAIInsight()
    }

    func clearLastPeriodStart() {
        lastPeriodStartDate = nil
        calculateCurrentCycleDay()
        fetchAIInsight()
    }

    func calculateCurrentCycleDay() {
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

    func fetchAIInsight() {
        guard let currentPhase = cycleDay?.phase, let goalSettings = goalSettings else { return }
        isLoadingInsight = true
        
        Task {
            let recentLogsResult = await dailyLogService?.fetchDailyHistory(for: Auth.auth().currentUser?.uid ?? "", startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()), endDate: Date())
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
            
            DispatchQueue.main.async {
                self.isLoadingInsight = false
                if let responseData = response?.data(using: .utf8) {
                    do {
                        self.aiInsight = try JSONDecoder().decode(AIInsight.self, from: responseData)
                    } catch {
                        print("Error decoding AI insight: \(error)")
                    }
                }
            }
        }
    }
    
    private func fetchAIResponse(prompt: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": 800,
            "temperature": 0.6
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
        } catch {
            print("AI fetch error: \(error.localizedDescription)")
        }
        return nil
    }
}
