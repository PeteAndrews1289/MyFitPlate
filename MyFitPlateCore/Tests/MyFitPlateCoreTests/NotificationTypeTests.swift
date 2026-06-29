import XCTest
@testable import MyFitPlateCore

final class NotificationTypeTests: XCTestCase {

    private let allTypes: [NotificationType] = [
        .dailyLogReminder(hour: 20, minute: 0),
        .hydrationNudge,
        .achievementNear(achievementName: "Streak Master", progress: "2 days"),
        .encouragement,
        .welcomeBack,
        .healthTip,
        .dailyBriefing,
        .weighInReminder
    ]

    func testIdsAreStableAndDistinct() {
        let ids = allTypes.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique")
        XCTAssertEqual(NotificationType.dailyLogReminder(hour: 7, minute: 30).id, "dailyLogReminder")
        XCTAssertEqual(NotificationType.weighInReminder.id, "weighInReminder")
        // The id must not depend on associated values.
        XCTAssertEqual(NotificationType.dailyLogReminder(hour: 1, minute: 1).id,
                       NotificationType.dailyLogReminder(hour: 23, minute: 59).id)
    }

    func testTitlesAndBodiesAreNonEmpty() {
        for type in allTypes {
            XCTAssertFalse(type.title.isEmpty, "title empty for \(type.id)")
            XCTAssertFalse(type.body().isEmpty, "body empty for \(type.id)")
        }
    }

    func testDailyLogBodyVariesWithRemainingCalories() {
        let withCals = NotificationType.dailyLogReminder(hour: 20, minute: 0).body(remainingCalories: 350)
        XCTAssertTrue(withCals.contains("350"))
        XCTAssertTrue(withCals.contains("calories left"))

        let without = NotificationType.dailyLogReminder(hour: 20, minute: 0).body()
        XCTAssertFalse(without.contains("calories left"))
        XCTAssertNotEqual(withCals, without)
    }

    func testAchievementBodyInterpolatesNameAndProgress() {
        let body = NotificationType.achievementNear(achievementName: "Streak Master", progress: "2 days").body()
        XCTAssertTrue(body.contains("Streak Master"))
        XCTAssertTrue(body.contains("2 days"))
    }

    func testRemainingCaloriesIgnoredForNonLogTypes() {
        // Passing calories to a type that doesn't use them must not change the copy.
        XCTAssertEqual(NotificationType.hydrationNudge.body(remainingCalories: 99),
                       NotificationType.hydrationNudge.body())
    }
}
