import XCTest
@testable import MyFitPlateCore

/// Regression for the fiber bug Peter caught on the Mission Carb Balance Burrito:
/// the trust checker double-counted fiber as extra serving mass and used total (not net)
/// carbs for the Atwater calorie check, so a legitimate high-fiber food got flagged.
final class FoodFiberSanityTests: XCTestCase {

    // 110 cal, 10p / 32c / 6f, 26g fiber, 70g serving — the exact reported entry.
    private func carbBalanceBurrito() -> FoodItem {
        FoodItem(
            name: "Mission Carb Balance Burrito",
            calories: 110, protein: 10, carbs: 32, fats: 6,
            fiber: 26, servingWeight: 70
        )
    }

    func testCaloriesUseNetCarbsWhenFiberIsKnown() {
        // 10*4 + (32-26)*4 + 6*9 = 40 + 24 + 54 = 118, close to the labeled 110.
        let cals = NutritionCalorieConsistency.macroDerivedCalories(protein: 10, carbs: 32, fats: 6, fiber: 26)
        XCTAssertEqual(cals, 118, accuracy: 0.001)
    }

    func testCaloriesWithoutFiberAreUnchanged() {
        // Back-compat: omitting fiber keeps the original total-carb Atwater estimate.
        let cals = NutritionCalorieConsistency.macroDerivedCalories(protein: 10, carbs: 32, fats: 6)
        XCTAssertEqual(cals, 222, accuracy: 0.001)
    }

    func testHighFiberBurritoIsNotFlagged() {
        let findings = FoodDataSanity.findings(for: carbBalanceBurrito())
        XCTAssertFalse(findings.contains { $0.id == "calories_undercount" },
                       "Net-carb calories (~118) are close to the labeled 110 — no calorie flag")
        XCTAssertFalse(findings.contains { $0.id == "macros_exceed_serving_weight" },
                       "48g of macros fit a 70g serving; fiber (part of carbs) must not be added on top")
        XCTAssertFalse(FoodDataSanity.isSuspicious(carbBalanceBurrito()))
    }

    func testDayLevelConsistencyDiscountsFiber() {
        let log = DailyLog(date: Date(), meals: [Meal(name: "Lunch", foodItems: [carbBalanceBurrito()])])
        XCTAssertEqual(log.totalFiber(), 26, accuracy: 0.001)
        XCTAssertFalse(log.calorieConsistencyStatus().hasMeaningfulMismatch)
    }

    // MARK: - The real defects it's meant to catch must still fire

    func testGenuineMassOverflowStillFlags() {
        let impossible = FoodItem(name: "Impossible", calories: 400, protein: 30, carbs: 80, fats: 20, servingWeight: 50)
        XCTAssertTrue(FoodDataSanity.findings(for: impossible).contains { $0.id == "macros_exceed_serving_weight" })
    }

    func testGenuineCalorieUndercountStillFlags() {
        // Low fiber, calories far below what the macros imply — still a real flag.
        let undercount = FoodItem(name: "Undercount", calories: 100, protein: 20, carbs: 40, fats: 15, fiber: 2, servingWeight: 100)
        XCTAssertTrue(FoodDataSanity.findings(for: undercount).contains { $0.id == "calories_undercount" })
    }
}
