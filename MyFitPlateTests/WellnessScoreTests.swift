import SwiftUI
import XCTest
@testable import MyFitPlate

final class WellnessScoreTests: XCTestCase {
    private let service = WellnessScoreService()

    func testNoInputsDoNotInventRecoveryOrWellness() {
        let score = service.calculateWellnessScore(
            mealScore: nil,
            lastNightSleepScore: nil,
            restingHeartRate: nil,
            hrv: nil
        )

        XCTAssertEqual(score.overallScore, 0)
        XCTAssertNil(score.sleepScore)
        XCTAssertNil(score.recoveryScore)
        XCTAssertEqual(score.availableComponentCount, 0)
    }

    func testNutritionOnlyIsLabeledAsNutritionScore() {
        let score = service.calculateWellnessScore(
            mealScore: mealScore(overall: 93),
            lastNightSleepScore: nil,
            restingHeartRate: nil,
            hrv: nil
        )

        XCTAssertEqual(score.overallScore, 93)
        XCTAssertTrue(score.isNutritionOnly)
        XCTAssertEqual(score.displayTitle, "Nutrition summary")
        XCTAssertNil(score.recoveryScore)
    }

    func testRawHeartRateDoesNotInventARecoveryScore() {
        let score = service.calculateWellnessScore(
            mealScore: nil,
            lastNightSleepScore: nil,
            restingHeartRate: 62,
            hrv: nil
        )

        XCTAssertNil(score.recoveryScore)
        XCTAssertEqual(score.overallScore, 0)
        XCTAssertTrue(score.hasRecoveryReadings)
        XCTAssertEqual(score.recoveryLabel, "Recorded")
    }

    func testAvailableComponentsKeepDocumentedWeights() {
        let score = service.calculateWellnessScore(
            mealScore: mealScore(overall: 90),
            lastNightSleepScore: 80,
            restingHeartRate: 62,
            hrv: 55
        )

        XCTAssertNil(score.recoveryScore)
        XCTAssertEqual(score.overallScore, 86)
        XCTAssertEqual(score.availableComponentCount, 2)
    }

    func testHighAndLowAbsoluteHRVDoNotChangeTheScoreOrPrescribeTraining() {
        for hrv in [15.0, 55, 110] {
            let score = service.calculateWellnessScore(mealScore: mealScore(overall: 90),
                                                      lastNightSleepScore: 80, restingHeartRate: 62, hrv: hrv)
            XCTAssertEqual(score.overallScore, 86)
            XCTAssertNil(score.recoveryScore)
            XCTAssertFalse(score.summary.contains("ready"))
        }
    }

    func testValidZeroRemainsAvailableAndMissingPlaceholderIsExcluded() {
        let zero = service.calculateWellnessScore(mealScore: mealScore(overall: 0), lastNightSleepScore: 0,
            restingHeartRate: nil, hrv: nil)
        XCTAssertEqual(zero.availableComponentCount, 2)
        XCTAssertEqual(zero.sleepScore, 0)
        XCTAssertTrue(zero.hasNutrition)
        let missing = service.calculateWellnessScore(mealScore: .noScore, lastNightSleepScore: -1,
            restingHeartRate: 60, hrv: 40)
        XCTAssertEqual(missing.availableComponentCount, 0)
        XCTAssertFalse(missing.hasNutrition)
        XCTAssertTrue(missing.hasRecoveryReadings)
    }

    private func mealScore(overall: Int) -> MealScore {
        MealScore(
            grade: "A",
            summary: "Test score",
            color: .green,
            calorieScore: overall,
            macroScore: overall,
            qualityScore: overall,
            overallScore: overall,
            personalizedAISummary: "",
            improvementTips: [],
            actualCalories: 1_900,
            goalCalories: 2_000,
            actualProtein: 140,
            goalProtein: 150,
            actualCarbs: 200,
            goalCarbs: 220,
            actualFats: 60,
            goalFats: 65,
            actualFiber: 25,
            goalFiber: 25,
            actualSaturatedFat: 12,
            goalSaturatedFat: 20,
            actualSodium: 1_900,
            goalSodium: 2_300
        )
    }
}
