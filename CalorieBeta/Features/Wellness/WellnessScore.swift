import Foundation
import SwiftUI

// MARK: - Wellness Score Model

/// This struct defines the data model for the overall Wellness Score.
/// It holds the final calculated scores and a summary message.
struct WellnessScore {
    // The main score, calculated from the other three components.
    let overallScore: Int
    
    // The score for yesterday's nutrition (from MealScore).
    let nutritionScore: Int
    
    // The score for the most recent night of sleep, if Apple Health has sleep samples available.
    let sleepScore: Int?
    
    // The score for physical recovery (RHR, HRV).
    let recoveryScore: Int?
    
    // A user-facing message based on the overall score (e.g., "Primed for a great day!").
    let summary: String
    
    // A color that corresponds to the score (e.g., green for good, red for bad).
    let color: Color

    /// A static "zero" state for when no data is available to display.
    static let zero = WellnessScore(overallScore: 0, nutritionScore: 0, sleepScore: nil, recoveryScore: nil, summary: "Log meals or connect Apple Health to build your score.", color: .gray)

    var availableComponentCount: Int {
        [nutritionScore > 0, sleepScore != nil, recoveryScore != nil].filter { $0 }.count
    }

    var isNutritionOnly: Bool {
        nutritionScore > 0 && sleepScore == nil && recoveryScore == nil
    }

    var displayTitle: String {
        isNutritionOnly ? "Nutrition Score" : "Wellness Score"
    }

    var displayMetricLabel: String {
        isNutritionOnly ? "nutrition score" : "wellness score"
    }

    var scopeDescription: String {
        switch availableComponentCount {
        case 0:
            return "Nutrition, sleep, and recovery will appear as data becomes available."
        case 1 where isNutritionOnly:
            return "Based on yesterday's nutrition. Connect Apple Health to add sleep and recovery."
        case 1:
            return "Based on the available Apple Health signal. Log nutrition to add more context."
        case 2:
            return "Based on two available signals; missing data is not estimated."
        default:
            return "Nutrition, sleep, and recovery in one read."
        }
    }
}

// MARK: - Wellness Score Service

/// This class contains the business logic for calculating the WellnessScore.
/// It takes data from nutrition, sleep, and recovery to create a single, weighted score.
class WellnessScoreService {

    /**
     Calculates the overall Wellness Score based on inputs from nutrition, sleep, and HealthKit.
     - Parameters:
        - mealScore: The `MealScore` object from *yesterday's* logs.
        - lastNightSleepScore: The comprehensive sleep score (0-100) from the *most recent* night.
        - restingHeartRate: The latest RHR value from HealthKit.
        - hrv: The latest Heart Rate Variability (HRV) value from HealthKit.
     - Returns: A calculated `WellnessScore` object.
     */
    func calculateWellnessScore(
        mealScore: MealScore?,
        lastNightSleepScore: Int?, // Use last night's score
        restingHeartRate: Double?,
        hrv: Double?
    ) -> WellnessScore {

        // 1. Nutrition Score (40% weight)
        // We use the `mealScore` from yesterday, defaulting to 0 if it's nil.
        let currentMealScore = mealScore ?? .noScore
        let nutritionScore = currentMealScore.overallScore

        let sleepScore = lastNightSleepScore.flatMap { $0 > 0 ? $0 : nil }

        // 3. Recovery Score (30% weight)
        // This score is calculated internally based on RHR and HRV.
        let recoveryScore = calculateRecoveryScore(restingHeartRate: restingHeartRate, hrv: hrv)

        var weightedTotal = 0.0
        var availableWeight = 0.0

        if nutritionScore > 0 {
            weightedTotal += Double(nutritionScore) * 0.40
            availableWeight += 0.40
        }

        if let sleepScore, sleepScore > 0 {
            weightedTotal += Double(sleepScore) * 0.30
            availableWeight += 0.30
        }

        if let recoveryScore {
            weightedTotal += Double(recoveryScore) * 0.30
            availableWeight += 0.30
        }

        let overallScore = availableWeight > 0 ? Int((weightedTotal / availableWeight).rounded()) : 0

        // Get the appropriate summary text and color for the final score.
        let (summary, color) = getSummaryAndColor(
            for: overallScore,
            hasNutrition: nutritionScore > 0,
            hasSleep: sleepScore != nil,
            hasRecovery: recoveryScore != nil
        )

        // Return the complete WellnessScore object.
        return WellnessScore(
            overallScore: overallScore,
            nutritionScore: nutritionScore,
            sleepScore: sleepScore,
            recoveryScore: recoveryScore,
            summary: summary,
            color: color
        )
    }

    /// Internal function to calculate a 0-100 recovery score.
    /// It gives 50 points for RHR and 50 points for HRV.
    private func calculateRecoveryScore(restingHeartRate: Double?, hrv: Double?) -> Int? {
        var componentScores: [Int] = []

        // RHR Score (Max 50 points)
        // A lower RHR is better, so it gets more points.
        if let rhr = restingHeartRate {
            switch rhr {
            case ..<50: componentScores.append(100)
            case 50..<55: componentScores.append(90)
            case 55..<60: componentScores.append(80)
            case 60..<65: componentScores.append(70)
            case 65..<70: componentScores.append(60)
            case 70..<75: componentScores.append(50)
            case 75..<80: componentScores.append(40)
            default: componentScores.append(20)
            }
        }

        // HRV Score (Max 50 points)
        // A higher HRV is better, so it gets more points.
        if let hrv = hrv {
            switch hrv {
            case 70...: componentScores.append(100)
            case 50..<70: componentScores.append(80)
            case 30..<50: componentScores.append(60)
            case 20..<30: componentScores.append(40)
            default: componentScores.append(20)
            }
        }

        guard !componentScores.isEmpty else { return nil }
        return Int((Double(componentScores.reduce(0, +)) / Double(componentScores.count)).rounded())
    }

    /// Returns a user-facing summary and a color based on the overall score.
    private func getSummaryAndColor(
        for score: Int,
        hasNutrition: Bool,
        hasSleep: Bool,
        hasRecovery: Bool
    ) -> (String, Color) {
        let availableCount = [hasNutrition, hasSleep, hasRecovery].filter { $0 }.count
        guard availableCount > 0 else {
            return ("Log meals or connect Apple Health to build your score.", .gray)
        }

        let color: Color
        switch score {
        case 90...: color = .accentPositive
        case 80..<90: color = .green
        case 70..<80: color = .yellow
        case 60..<70: color = .orange
        default: color = .red
        }

        if availableCount == 1 {
            if hasNutrition {
                return (score >= 80 ? "Yesterday's nutrition was on track." : "Yesterday's nutrition has room to improve.", color)
            }
            if hasSleep {
                return (score >= 80 ? "Your latest sleep looks restorative." : "Your latest sleep suggests taking it easier.", color)
            }
            return (score >= 80 ? "Your available recovery signal looks strong." : "Your available recovery signal suggests caution.", color)
        }

        switch score {
        case 90...: return ("Primed for a great day!", color)
        case 80..<90: return ("Feeling strong and ready.", color)
        case 70..<80: return ("Solid foundation for today.", color)
        case 60..<70: return ("A good day to focus on recovery.", color)
        default: return ("Prioritize rest and nutrition.", color)
        }
    }
}
