import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class ScreenshotDemoDataTests: XCTestCase {
    func testCustomProductPageAliasesResolveToStableScreens() {
        let aliases = [
            "cpp-trust": "trust",
            "cpp-logging": "food-search",
            "cpp-dining": "builder",
            "cpp-strength": "train",
            "cpp-running": "runs",
            "cpp-weight": "reports",
            "cpp-meal-plan": "meal-plan"
        ]

        for (alias, expected) in aliases {
            XCTAssertEqual(ScreenshotDemoData.canonicalScreenName(alias), expected)
        }
    }

    func testRunningFixtureIsUsefulWithoutHealthKit() {
        let runs = ScreenshotDemoData.runningDemoRuns

        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(Set(runs.map(\.id)).count, runs.count)
        XCTAssertTrue(runs.allSatisfy { $0.distanceMeters >= 5_000 })
        XCTAssertTrue(runs.allSatisfy { !$0.splits.isEmpty })
        XCTAssertTrue(runs.allSatisfy(\.hasRoute))
    }

    func testLivingDayFoodTransitionTargetsPersistedMealNode() {
        let mealID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let food = FoodItem(id: "logged-food", name: "Chicken bowl", calories: 520)
        let meal = Meal(id: mealID, name: "Lunch", foodItems: [food])
        let createdAt = Date(timeIntervalSince1970: 100)

        let transition = LivingDayTransition.foodLogged(food, meal: meal, createdAt: createdAt)

        XCTAssertEqual(transition.kind, .foodLogged)
        XCTAssertEqual(transition.eventID, "meal:\(mealID.uuidString)")
        XCTAssertEqual(transition.title, "Added to Lunch")
        XCTAssertEqual(transition.detail, "Chicken bowl")
        XCTAssertTrue(transition.isRecent(at: createdAt.addingTimeInterval(8)))
        XCTAssertFalse(transition.isRecent(at: createdAt.addingTimeInterval(8.01)))
    }
}
