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
        XCTAssertEqual(score.displayTitle, "Nutrition Score")
        XCTAssertNil(score.recoveryScore)
    }

    func testOneRecoverySignalIsScoredWithoutInventingTheOther() {
        let score = service.calculateWellnessScore(
            mealScore: nil,
            lastNightSleepScore: nil,
            restingHeartRate: 62,
            hrv: nil
        )

        XCTAssertEqual(score.recoveryScore, 70)
        XCTAssertEqual(score.overallScore, 70)
        XCTAssertEqual(score.availableComponentCount, 1)
    }

    func testAvailableComponentsKeepDocumentedWeights() {
        let score = service.calculateWellnessScore(
            mealScore: mealScore(overall: 90),
            lastNightSleepScore: 80,
            restingHeartRate: 62,
            hrv: 55
        )

        XCTAssertEqual(score.recoveryScore, 75)
        XCTAssertEqual(score.overallScore, 83)
        XCTAssertEqual(score.availableComponentCount, 3)
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
