import XCTest
@testable import MyFitPlateCore

final class WatchQuickActionsTests: XCTestCase {
    func testRecentMealUsesLatestTimestampAndRepeatCreatesFreshIdentities() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let older = FoodItem(id: "old", name: "Oats", calories: 200, timestamp: now.addingTimeInterval(-3_600))
        let newer = FoodItem(id: "new", name: "Rice bowl", calories: 500, timestamp: now.addingTimeInterval(-60))
        let log = DailyLog(
            date: now,
            meals: [
                Meal(name: "Breakfast", foodItems: [older]),
                Meal(name: "Dinner", foodItems: [newer])
            ]
        )

        let snapshot = try XCTUnwrap(WatchQuickActionRules.recentMeal(from: log, now: now))
        XCTAssertEqual(snapshot.mealName, "Dinner")
        XCTAssertEqual(snapshot.totalCalories, 500)

        let repeatedAt = now.addingTimeInterval(120)
        let repeated = WatchQuickActionRules.itemsForLogging(from: snapshot, at: repeatedAt)
        XCTAssertEqual(repeated.count, 1)
        XCTAssertNotEqual(repeated[0].id, newer.id)
        XCTAssertEqual(repeated[0].timestamp, repeatedAt)
        XCTAssertEqual(repeated[0].name, newer.name)
    }

    func testInvalidItemsAreNotOfferedOrRepeated() {
        let invalid = FoodItem(name: "Broken", calories: .nan)
        let log = DailyLog(date: Date(), meals: [Meal(name: "Dinner", foodItems: [invalid])])

        XCTAssertNil(WatchQuickActionRules.recentMeal(from: log))
    }

    func testOversizedMealIsRefusedInsteadOfSilentlyTruncated() {
        let foods = (0...WatchQuickActionRules.maximumFoodItems).map { index in
            FoodItem(name: "Food \(index)", calories: 10)
        }
        let log = DailyLog(date: Date(), meals: [Meal(name: "Large meal", foodItems: foods)])
        let snapshot = WatchMealSnapshot(mealName: "Large meal", foodItems: foods)

        XCTAssertNil(WatchQuickActionRules.recentMeal(from: log))
        XCTAssertTrue(WatchQuickActionRules.itemsForLogging(from: snapshot).isEmpty)
    }

    func testAccountScopeIsStablePerAccountAndNeverEqualsUserID() throws {
        let defaults = try makeDefaults()
        let store = WatchAccountScopeStore(defaults: defaults, storageKey: "scopes")

        let first = store.scope(for: "private-user-a")
        XCTAssertEqual(first, store.scope(for: "private-user-a"))
        XCTAssertNotEqual(first, store.scope(for: "private-user-b"))
        XCTAssertNotEqual(first, "private-user-a")
    }

    func testInboxPersistsDeduplicatesAndWaitsForSuccess() throws {
        let defaults = try makeDefaults()
        let snapshot = WatchMealSnapshot(mealName: "Lunch", foodItems: [FoodItem(name: "Soup")])
        let request = WatchMealRepeatRequest(id: "action-1", accountScope: "scope-a", snapshot: snapshot)
        let inbox = WatchMealRepeatInbox(defaults: defaults, storageKey: "inbox")

        XCTAssertTrue(inbox.enqueue(request))
        XCTAssertFalse(inbox.enqueue(request))
        XCTAssertEqual(inbox.pendingCount, 1)
        XCTAssertEqual(inbox.nextRequest(accountScope: "scope-a"), request)

        let reloaded = WatchMealRepeatInbox(defaults: defaults, storageKey: "inbox")
        XCTAssertEqual(reloaded.nextRequest(accountScope: "scope-a"), request)
        reloaded.markHandled(id: request.id)
        XCTAssertNil(reloaded.nextRequest(accountScope: "scope-a"))
        XCTAssertFalse(reloaded.enqueue(request))
    }

    func testInboxDiscardsRequestsFromAnotherSignedInAccount() throws {
        let defaults = try makeDefaults()
        let snapshot = WatchMealSnapshot(mealName: "Meal", foodItems: [FoodItem(name: "Food")])
        let inbox = WatchMealRepeatInbox(defaults: defaults, storageKey: "inbox")
        inbox.enqueue(WatchMealRepeatRequest(id: "a", accountScope: "scope-a", snapshot: snapshot))
        inbox.enqueue(WatchMealRepeatRequest(id: "b", accountScope: "scope-b", snapshot: snapshot))

        inbox.discardRequests(exceptAccountScope: "scope-b")

        XCTAssertEqual(inbox.pendingCount, 1)
        XCTAssertNil(inbox.nextRequest(accountScope: "scope-a"))
        XCTAssertEqual(inbox.nextRequest(accountScope: "scope-b")?.id, "b")
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "WatchQuickActionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
