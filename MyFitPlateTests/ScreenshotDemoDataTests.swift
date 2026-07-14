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

    func testGroceryFixtureCoversARealShoppingRun() {
        let nutrition = MockNutritionRepository()
        let workout = MockWorkoutRepository()
        let settings = MockSettingsRepository()

        ScreenshotDemoData.configureRepositories(
            nutrition: nutrition,
            workout: workout,
            settings: settings
        )

        let items = nutrition.mockFetchGroceryListResult
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertEqual(items.filter(\.isCompleted).count, 2)
        XCTAssertTrue(items.allSatisfy {
            GroceryListBuilder.standardCategories.contains($0.category)
        })
        XCTAssertTrue(items.contains { $0.source == "manual" })
        XCTAssertTrue(items.contains { $0.category == "Meat & Seafood" })
        XCTAssertTrue(items.contains { $0.category == "Pantry & Oils" })
    }

    func testAITextFixtureSupportsEditableReview() {
        let items = ScreenshotDemoData.aiTextDemoFoods

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertTrue(items.allSatisfy { $0.sourceMetadata?.sourceType == .aiText })
        XCTAssertTrue(items.allSatisfy { $0.sourceMetadata?.reviewStatus == .unreviewed })
        XCTAssertTrue(items.allSatisfy { !$0.servingSize.isEmpty })
        XCTAssertEqual(items.reduce(0) { $0 + $1.calories }, 870, accuracy: 0.01)
    }

    func testAchievementFixtureStartsAtAStableProgressState() {
        let repository = MockAchievementRepository()

        ScreenshotDemoData.configureAchievementRepository(repository)

        XCTAssertEqual(repository.mockUserProfile?.points, 780)
        XCTAssertEqual(repository.mockUserProfile?.level, 4)
        XCTAssertEqual(repository.mockUserStatuses?.filter(\.isUnlocked).count, 4)
        XCTAssertEqual(repository.mockChallenges?.count, 3)
        XCTAssertEqual(repository.mockChallenges?.filter(\.isCompleted).count, 1)
        XCTAssertEqual(repository.mockActiveChallenges.count, 3)
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
