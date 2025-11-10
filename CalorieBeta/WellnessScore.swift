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
    
    // The score for the most recent night of sleep.
    let sleepScore: Int // Store the last night's comprehensive score
    
    // The score for physical recovery (RHR, HRV).
    let recoveryScore: Int
    
    // A user-facing message based on the overall score (e.g., "Primed for a great day!").
    let summary: String
    
    // A color that corresponds to the score (e.g., green for good, red for bad).
    let color: Color

    /// A static "zero" state for when no data is available to display.
    static let zero = WellnessScore(overallScore: 0, nutritionScore: 0, sleepScore: 0, recoveryScore: 0, summary: "Log your day to see your score.", color: .gray)
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

        // 2. Sleep Score (30% weight)
        // We use the `lastNightSleepScore` passed in, defaulting to 0 if nil.
        let sleepScore = lastNightSleepScore ?? 0 // Use 0 if nil

        // 3. Recovery Score (30% weight)
        // This score is calculated internally based on RHR and HRV.
        let recoveryScore = calculateRecoveryScore(restingHeartRate: restingHeartRate, hrv: hrv)

        // 4. Overall Weighted Score
        // The final score is a weighted average of the three components.
        let overallScore = Int(
            (Double(nutritionScore) * 0.40) +
            (Double(sleepScore) * 0.30) +
            (Double(recoveryScore) * 0.30)
        )

        // Get the appropriate summary text and color for the final score.
        let (summary, color) = getSummaryAndColor(for: overallScore)

        // Return the complete WellnessScore object.
        return WellnessScore(
            overallScore: overallScore,
            nutritionScore: nutritionScore,
            sleepScore: sleepScore, // Store last night's comprehensive score
            recoveryScore: recoveryScore,
            summary: summary,
            color: color
        )
    }

    /// Internal function to calculate a 0-100 recovery score.
    /// It gives 50 points for RHR and 50 points for HRV.
    private func calculateRecoveryScore(restingHeartRate: Double?, hrv: Double?) -> Int {
        var score = 0

        // RHR Score (Max 50 points)
        // A lower RHR is better, so it gets more points.
        if let rhr = restingHeartRate {
            switch rhr {
            case ..<50: score += 50; case 50..<55: score += 45; case 55..<60: score += 40
            case 60..<65: score += 35; case 65..<70: score += 30; case 70..<75: score += 25
            case 75..<80: score += 20; default: score += 10
            }
        } else { score += 25 } // Give an average score (25/50) if no RHR data is available.

        // HRV Score (Max 50 points)
        // A higher HRV is better, so it gets more points.
        if let hrv = hrv {
            switch hrv {
            case 70...: score += 50; case 50..<70: score += 40; case 30..<50: score += 30
            case 20..<30: score += 20; default: score += 10
            }
        } else { score += 25 } // Give an average score (25/50) if no HRV data is available.

        // Ensure the total score doesn't exceed 100.
        return min(100, score)
    }

    /// Returns a user-facing summary and a color based on the overall score.
    private func getSummaryAndColor(for score: Int) -> (String, Color) {
        switch score {
        case 90...: return ("Primed for a great day!", .accentPositive)
        case 80..<90: return ("Feeling strong and ready.", .green)
        case 70..<80: return ("Solid foundation for today.", .yellow)
        case 60..<70: return ("A good day to focus on recovery.", .orange)
        default: return ("Prioritize rest and nutrition.", .red)
        }
    }
}
