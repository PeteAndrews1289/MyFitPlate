import XCTest
@testable import MyFitPlateCore

final class MealPlanningSupportRulesTests: XCTestCase {
    func testNormalizedPreferencesTrimSortAndDeduplicateCustomValue() {
        let values = MealPlanningPreferenceRules.normalizedItems(
            selected: [" Rice ", "Chicken", "chicken"],
            custom: "  Couscous  "
        )

        XCTAssertEqual(values, ["Chicken", "Couscous", "Rice"])
    }

    func testCuisineSelectionKeepsAnyExclusive() {
        XCTAssertEqual(
            MealPlanningPreferenceRules.toggledCuisine("Italian", in: ["Any"]),
            ["Italian"]
        )
        XCTAssertEqual(
            MealPlanningPreferenceRules.toggledCuisine("Any", in: ["Italian", "Mexican"]),
            ["Any"]
        )
        XCTAssertEqual(MealPlanningPreferenceRules.normalizedCuisines([]), ["Any"])
    }

    func testPantryMatchingUsesPhraseBoundaries() {
        XCTAssertTrue(
            MealSuggestionReviewRules.ingredientUsesPantry(
                "1 cup plain Greek yogurt",
                pantryNames: ["Greek yogurt"]
            )
        )
        XCTAssertFalse(
            MealSuggestionReviewRules.ingredientUsesPantry(
                "Champagne vinaigrette",
                pantryNames: ["ham"]
            )
        )
    }

    func testReviewSummariesHandleInvalidNumbers() {
        XCTAssertEqual(MealSuggestionReviewRules.safeValue(.nan), 0)
        XCTAssertNil(MealSuggestionReviewRules.safeTarget(.infinity))
        XCTAssertEqual(
            MealSuggestionReviewRules.fitSummary(calories: .nan, remainingCalories: .infinity),
            "Review the estimate and adjust portions before logging."
        )
    }

    func testInstructionStepsStripNumberingAndBlankLines() {
        XCTAssertEqual(
            MealSuggestionReviewRules.instructionSteps("1. Mix ingredients\n\n2) Cook until warm"),
            ["Mix ingredients", "Cook until warm"]
        )
    }

    func testTimerUsesEndDateAndSafeDisplay() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let end = now.addingTimeInterval(125.2)

        XCTAssertEqual(MealPrepTimerRules.clampedMinutes(0), 1)
        XCTAssertEqual(MealPrepTimerRules.clampedMinutes(500), 120)
        XCTAssertEqual(MealPrepTimerRules.remaining(until: end, now: now), 125.2, accuracy: 0.001)
        XCTAssertEqual(MealPrepTimerRules.display(125.2), "02:06")
        XCTAssertEqual(MealPrepTimerRules.display(.nan), "00:00")
    }

    func testQuantityUnitsPluralizeWordsButPreserveAbbreviations() {
        XCTAssertEqual(MealPrepQuantityRules.displayUnit("cup", quantity: 2), "cups")
        XCTAssertEqual(MealPrepQuantityRules.displayUnit("cup", quantity: 1), "cup")
        XCTAssertEqual(MealPrepQuantityRules.displayUnit("tbsp", quantity: 2), "tbsp")
        XCTAssertEqual(MealPrepQuantityRules.displayUnit("item", quantity: .nan), "items")
    }
}
