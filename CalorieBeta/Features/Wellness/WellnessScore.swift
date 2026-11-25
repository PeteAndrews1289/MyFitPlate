import Foundation
import SwiftUI

// MARK: - Wellness Score Model

/// This struct defines the data model for the overall Wellness Score.
/// It holds the final calculated scores and a summary message.
struct WellnessScore {
    // A summary of available nutrition and sleep records.
    let overallScore: Int
    
    // The score for yesterday's nutrition (from MealScore).
    let nutritionScore: Int
    
    // The score for the most recent night of sleep, if Apple Health has sleep samples available.
    let sleepScore: Int?
    
    // Retained for compatibility with older report fixtures. Raw cardiac readings no longer produce a score.
    let recoveryScore: Int?

    var recoveryLabel: String { hasRecoveryReadings ? "Recorded" : "No data" }
    var recoveryExplanation: String {
        hasRecoveryReadings
            ? "Heart-rate readings are available. HRV and resting heart rate vary by person and are not converted into a readiness score."
            : "No heart-rate readings are available. Recovery is not estimated from missing data."
    }
    
    // A user-facing message based on the overall score (e.g., "Your recorded nutrition and sleep are consistent.").
    let summary: String
    
    // A color that corresponds to the score (e.g., green for good, red for bad).
    let color: Color
    var hasRecoveryReadings = false
    var nutritionIsAvailable: Bool?
    var hasNutrition: Bool { nutritionIsAvailable ?? (nutritionScore > 0) }
    var methodDescription: String { "Recorded-habits method v1: nutrition weight 40 and sleep weight 30, normalized over available components only. Heart-rate readings contribute no points. These weights describe an app heuristic, not validated readiness." }

    /// A static "zero" state for when no data is available to display.
    static let zero = WellnessScore(overallScore: 0, nutritionScore: 0, sleepScore: nil, recoveryScore: nil, summary: "Fully logged food days and readable sleep records appear here when available.", color: .gray)

    var availableComponentCount: Int {
        [hasNutrition, sleepScore != nil].filter { $0 }.count
    }

    var isNutritionOnly: Bool {
        hasNutrition && sleepScore == nil
    }

    var displayTitle: String {
        isNutritionOnly ? "Nutrition summary" : "Recorded habits"
    }

    var displayMetricLabel: String {
        isNutritionOnly ? "nutrition summary" : "recorded habits"
    }

    var scopeDescription: String {
        switch availableComponentCount {
        case 0:
            return "Nutrition and sleep contribute to this score when available. Recovery readings are shown separately."
        case 1 where isNutritionOnly:
            return "Based on yesterday's nutrition. Apple Health can add sleep context; heart-rate readings are shown separately."
        case 1:
            return "Based on the available Apple Health signal. Log nutrition to add more context."
        case 2:
            return "Based on two available signals; missing data is not estimated."
        default:
            return "A summary of recorded habits, not a measure of readiness for training."
        }
    }
}

// MARK: - Wellness Score Service

/// This class contains the business logic for calculating the WellnessScore.
/// It summarizes nutrition and sleep; cardiac readings are context only.
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
        let nutritionScore = min(100, max(0, currentMealScore.overallScore))
        let hasNutrition = mealScore != nil && currentMealScore.grade != "N/A"

        let sleepScore = lastNightSleepScore.flatMap { (0...100).contains($0) ? $0 : nil }

        // Absolute RHR/HRV cannot establish personal readiness. Show the presence of readings
        // separately; never turn these values into recovery points or training instructions.
        let recoveryScore: Int? = nil
        let hasRecoveryReadings = [restingHeartRate, hrv].compactMap { $0 }.contains { $0.isFinite && $0 > 0 }

        var weightedTotal = 0.0
        var availableWeight = 0.0

        if hasNutrition {
            weightedTotal += Double(nutritionScore) * 0.40
            availableWeight += 0.40
        }

        if let sleepScore {
            weightedTotal += Double(sleepScore) * 0.30
            availableWeight += 0.30
        }

        let overallScore = availableWeight > 0 ? Int((weightedTotal / availableWeight).rounded()) : 0

        // Get the appropriate summary text and color for the final score.
        let (summary, color) = getSummaryAndColor(
            for: overallScore,
            hasNutrition: hasNutrition,
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
            color: color,
            hasRecoveryReadings: hasRecoveryReadings, nutritionIsAvailable: hasNutrition
        )
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
            return ("Fully logged food days and readable sleep records appear here when available.", .gray)
        }

        let color: Color
        switch score {
        case 90...: color = .accentPositive
        case 80..<90: color = AppPalette.positive
        case 70..<80: color = AppPalette.achievement
        case 60..<70: color = AppPalette.caution
        default: color = AppPalette.critical
        }

        if availableCount == 1 {
            if hasNutrition {
                return ("Yesterday’s fully logged food day is available to review.", color)
            }
            if hasSleep {
                return ("Recent sleep records are available. Nutrition is unavailable until a food day is fully logged.", color)
            }
            return ("Heart-rate readings are context only.", color)
        }

        return ("Review yesterday’s food evidence and recent sleep separately below.", color)
    }
}
