import XCTest
@testable import MyFitPlateCore

final class MealPlannerDestinationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_800_000)

    func testRequestResolvesOnlyItsExactMealOnItsOriginalDay() throws {
        let meal = PlannedMeal(id: "dinner", mealType: "Dinner")
        let destination = MealPlannerDestination(userID: "owner", date: now, meal: meal, now: now)
        let day = MealPlanDay(id: "day", date: now, meals: [meal])
        XCTAssertEqual(try destination.reviewedMeal(in: day, currentUserID: "owner", now: now)?.id, "dinner")
        let otherDay = MealPlanDay(id: "older", date: now.addingTimeInterval(-86_400), meals: [meal])
        XCTAssertThrowsError(try destination.reviewedMeal(in: otherDay, currentUserID: "owner", now: now))
        XCTAssertThrowsError(try destination.reviewedMeal(in: day, currentUserID: "other", now: now))
    }

    func testChangedOrDeletedMealIsNotSilentlySubstituted() {
        var meal = PlannedMeal(id: "dinner", mealType: "Dinner", portionMultiplier: 1)
        let destination = MealPlannerDestination(userID: "owner", date: now, meal: meal, now: now)
        meal.portionMultiplier = 2
        XCTAssertThrowsError(try destination.reviewedMeal(in: .init(id: "day", date: now, meals: [meal]), currentUserID: "owner", now: now))
        XCTAssertThrowsError(try destination.reviewedMeal(in: .init(id: "day", date: now, meals: []), currentUserID: "owner", now: now))
    }

    func testExpiredAndFutureDatedEvidenceCannotOpenAReview() {
        let destination = MealPlannerDestination(userID: "owner", date: now, now: now)
        XCTAssertFalse(destination.isAvailable(to: "owner", now: now.addingTimeInterval(1_801)))
        XCTAssertFalse(destination.isAvailable(to: "owner", now: now.addingTimeInterval(-60)))
        XCTAssertFalse(destination.isAvailable(to: nil, now: now))
        XCTAssertFalse(MealPlannerDestination(userID: "", date: now, now: now).isAvailable(to: "", now: now))
    }

    func testWholeDayShortcutDoesNotInventAMealOrRequireAnExistingPlan() throws {
        let destination = MealPlannerDestination(userID: "owner", date: now, now: now)
        XCTAssertNil(try destination.reviewedMeal(in: nil, currentUserID: "owner", now: now))
    }
}
