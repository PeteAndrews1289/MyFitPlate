import Foundation

public enum CycleTrackingRules {
    
    public static func determinePhase(cycleDay: Int, typicalPeriodLength: Int, typicalCycleLength: Int) -> MenstrualPhase {
        let periodEnd = typicalPeriodLength
        let ovulationStart = (typicalCycleLength / 2) - 2
        let ovulationEnd = (typicalCycleLength / 2) + 2

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
    
    public static func createAIInsightPrompt(cycleDayNumber: Int, phase: MenstrualPhase, goal: String, recentLogs: [DailyLog]) -> String {
        var logSummary = "No recent activity logged."
        if !recentLogs.isEmpty {
            logSummary = recentLogs.map { log in
                let macros = log.totalMacros()
                return "Date: \(log.date.formatted(date: .abbreviated, time: .omitted)), Cals: \(Int(log.totalCalories())), P: \(Int(macros.protein))g, C: \(Int(macros.carbs))g, F: \(Int(macros.fats))g"
            }.joined(separator: "\n")
        }

        return """
        You are an elite female physiology and performance coach for the MyFitPlate app.
        The user is on Day \(cycleDayNumber) of their cycle, in the \(phase.rawValue) phase.
        Their primary goal is to \(goal) weight.
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
    }
    
    public static func parseAIInsightResponse(_ jsonString: String) throws -> AIInsight {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "CycleTrackingRules", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid string encoding"])
        }
        return try JSONDecoder().decode(AIInsight.self, from: data)
    }
}
