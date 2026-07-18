import XCTest
@testable import MyFitPlateCore

final class RestaurantValueRadarRulesTests: XCTestCase {
    func testScoresProteinValueWithPriceAndCalorieContext() throws {
        let score = try XCTUnwrap(RestaurantValueRadarRules.score(
            protein: 32,
            calories: 520,
            listedPrice: 12
        ))
        XCTAssertEqual(score.adjustedPrice, 12, accuracy: 0.001)
        XCTAssertEqual(score.proteinPerDollar, 32 / 12, accuracy: 0.001)
        XCTAssertEqual(score.proteinPer100Calories, 32 / 520 * 100, accuracy: 0.001)
        XCTAssertEqual(score.tier, .highProteinValue)
    }

    func testRegionalMultiplierChangesDisplayedValue() throws {
        let score = try XCTUnwrap(RestaurantValueRadarRules.score(
            protein: 24,
            calories: 500,
            listedPrice: 10,
            priceMultiplier: 1.2
        ))
        XCTAssertEqual(score.adjustedPrice, 12, accuracy: 0.001)
        XCTAssertEqual(score.proteinPerDollar, 2, accuracy: 0.001)
        XCTAssertEqual(score.tier, .balancedValue)
    }

    func testTierLabelsStayLiteralAndProfessional() {
        XCTAssertEqual(RestaurantValueRadarRules.Tier.highProteinValue.label, "High protein value")
        XCTAssertEqual(RestaurantValueRadarRules.Tier.balancedValue.label, "Balanced value")
        XCTAssertEqual(RestaurantValueRadarRules.Tier.lowerProteinValue.label, "Lower protein value")
    }

    func testInvalidPriceInputsAreRejected() {
        XCTAssertNil(RestaurantValueRadarRules.score(protein: 20, calories: 400, listedPrice: 0))
        XCTAssertNil(RestaurantValueRadarRules.score(protein: 20, calories: 400, listedPrice: .nan))
        XCTAssertNil(RestaurantValueRadarRules.score(protein: 20, calories: 400, listedPrice: 10, priceMultiplier: 0))
    }

    func testInvalidNutritionCannotPoisonTheScore() throws {
        let score = try XCTUnwrap(RestaurantValueRadarRules.score(
            protein: .infinity,
            calories: .nan,
            listedPrice: 10
        ))
        XCTAssertEqual(score.proteinPerDollar, 0)
        XCTAssertEqual(score.proteinPer100Calories, 0)
        XCTAssertTrue(score.adjustedPrice.isFinite)
        XCTAssertEqual(score.tier, .lowerProteinValue)
    }
}
