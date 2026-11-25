import XCTest
@testable import MyFitPlateCore

final class RecoveryStateTests: XCTestCase {
    func testWaterInboxPreservesCaptureDateAndDeduplicatesRedelivery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = WaterEntryInbox(directory: directory)
        let beforeMidnight = Date(timeIntervalSince1970: 1_790_000_000)
        let entry = PendingWaterEntry(accountScope: "account-a", ounces: 8, capturedAt: beforeMidnight)
        try inbox.enqueue(entry)
        try inbox.enqueue(entry)
        let reopened = WaterEntryInbox(directory: directory)
        XCTAssertEqual(try reopened.pending(accountScope: "account-a"), [entry])
        XCTAssertTrue(try reopened.pending(accountScope: "account-b").isEmpty)
        try reopened.acknowledge(entry)
        XCTAssertTrue(try inbox.pending(accountScope: "account-a").isEmpty)
    }

    func testQuizProgressExpiresAndDoesNotLeakAcrossAccounts() {
        let suite = "recovery-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let store = OnboardingQuizProgressStore(userID: "a", defaults: defaults)
        let progress = OnboardingQuizProgress(step: 3, answers: ["age": "31", "goal": "Lose"], metric: true)
        store.save(progress, now: date)
        XCTAssertEqual(store.load(now: date), progress)
        XCTAssertNil(OnboardingQuizProgressStore(userID: "b", defaults: defaults).load(now: date))
        XCTAssertNil(store.load(now: date.addingTimeInterval(OnboardingDraftStore.draftLifetime + 1)))
        XCTAssertNil(store.load(now: date))
    }

    func testAccountProgressDoesNotInheritInstallationMilestones() {
        let suite = "progress-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "activation_funnel_first_food_logged")
        let store = AccountProgressStore(defaults: defaults)
        store.record(ActivationFunnel.firstFoodLogged, userID: "a")
        XCTAssertNotNil(store.date(ActivationFunnel.firstFoodLogged, userID: "a"))
        XCTAssertNil(store.date(ActivationFunnel.firstFoodLogged, userID: "b"))
        XCTAssertNil(store.date(ActivationFunnel.firstFoodLogged, userID: nil))
    }

    func testLateSearchSourceKeepsVisibleRowsInPlace() {
        let first = FoodItem(id: "first", name: "Apple", calories: 50, protein: 0, carbs: 12, fats: 0)
        var improved = first
        improved.calories = 52
        let later = FoodItem(id: "later", name: "Pear", calories: 60, protein: 0, carbs: 14, fats: 0)
        let result = FoodSearchRanking.preservingVisibleOrder(previous: [first], updated: [later, improved])
        XCTAssertEqual(result.map(\.id), ["first", "later"])
        XCTAssertEqual(result[0].calories, 52)
    }
}
