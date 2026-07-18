import XCTest
@testable import MyFitPlateCore

@MainActor
final class DailyLogRecentFoodStoreTests: XCTestCase {
    private var store: DailyLogRecentFoodStore!
    private var mockRepo: MockNutritionRepository!
    private var mockAuth: MockAuthService!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!
    private let userID = "recent-user"

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        mockAuth = MockAuthService()
        mockAuth.currentUserID = userID
        userDefaultsSuiteName = "DailyLogRecentFoodStoreTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        store = DailyLogRecentFoodStore(userDefaults: userDefaults)
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = mockAuth
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        store = nil
        mockRepo = nil
        mockAuth = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        super.tearDown()
    }

    private var cacheKey: String {
        AccountScopedStorageKey.make(prefix: "recentFoods", userID: userID)!
    }

    private func food(_ id: String, _ name: String) -> FoodItem {
        FoodItem(id: id, name: name, calories: 100, protein: 10, carbs: 12, fats: 3)
    }

    private func cachedFoods() throws -> [FoodItem] {
        let data = try XCTUnwrap(userDefaults.data(forKey: cacheKey))
        return try JSONDecoder().decode([FoodItem].self, from: data)
    }

    func testAddRecentFoodUpdatesLocalCacheAndPersistsStableID() async throws {
        let apple = food("1", "Apple")

        store.addRecentFood(for: userID, foodItem: apple, source: "manual")
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(try cachedFoods().map(\.name), ["Apple"])
        let saved = try XCTUnwrap(mockRepo.savedRecentFoods.first)
        XCTAssertEqual(saved.userID, userID)
        XCTAssertEqual(saved.foodItem.name, "Apple")
        XCTAssertEqual(saved.source, "manual")
        XCTAssertEqual(saved.stableID, "QXBwbGU=")
    }

    func testAddRecentFoodMovesDuplicateNameToTopAndKeepsTenItems() async throws {
        let originalFoods = (0..<11).map { food("\($0)", "Food \($0)") }
        let encoded = try JSONEncoder().encode(originalFoods)
        userDefaults.set(encoded, forKey: cacheKey)

        store.addRecentFood(for: userID, foodItem: food("new", "Food 5"), source: "manual")
        try? await Task.sleep(nanoseconds: 80_000_000)

        let cached = try cachedFoods()
        XCTAssertEqual(cached.count, 10)
        XCTAssertEqual(cached.first?.name, "Food 5")
        XCTAssertEqual(cached.filter { $0.name == "Food 5" }.count, 1)
    }

    func testAddRecentFoodSkipsEmptyUserID() async {
        store.addRecentFood(for: "", foodItem: food("1", "Apple"), source: "manual")
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(
            userDefaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("recentFoods") }
        )
        XCTAssertTrue(mockRepo.savedRecentFoods.isEmpty)
    }

    func testMockRepositoryRecordsConcurrentRecentFoodWritesSafely() async throws {
        let repository = mockRepo!
        let accountID = userID
        let foods = (0..<40).map { food("\($0)", "Food \($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, item) in foods.enumerated() {
                group.addTask {
                    try await repository.saveRecentFood(
                        userID: accountID,
                        foodItem: item,
                        source: "concurrency_test",
                        stableID: "stable-\(index)"
                    )
                }
            }
            try await group.waitForAll()
        }

        let stableIDs = Set(mockRepo.savedRecentFoods.map(\.stableID))
        XCTAssertEqual(stableIDs.count, 40)
    }

    func testFetchRecentFoodItemsRejectsEmptyUserID() {
        let finished = expectation(description: "empty user failure")

        store.fetchRecentFoodItems(for: "") { result in
            if case .failure = result {} else {
                XCTFail("expected empty user failure")
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 1.0)
    }

    func testFetchRecentFoodItemsReturnsCacheThenFreshRemoteItems() async throws {
        let cached = [food("cached", "Cached Apple")]
        userDefaults.set(try JSONEncoder().encode(cached), forKey: cacheKey)
        mockRepo.recentFoodsToReturn = [food("remote", "Remote Oats")]
        let finished = expectation(description: "cache and remote results")
        finished.expectedFulfillmentCount = 2
        var resultNames: [[String]] = []

        store.fetchRecentFoodItems(for: userID) { result in
            if case .success(let items) = result {
                resultNames.append(items.map(\.name))
            } else {
                XCTFail("expected success")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertEqual(resultNames, [["Cached Apple"], ["Remote Oats"]])
        XCTAssertEqual(try cachedFoods().map(\.name), ["Remote Oats"])
        XCTAssertEqual(mockRepo.fetchRecentFoodLimits, [10])
    }

    func testFetchRecentFoodItemsReturnsFailureWhenNoCacheAndRemoteFails() async {
        mockRepo.recentFoodError = URLError(.timedOut)
        let finished = expectation(description: "remote failure")

        store.fetchRecentFoodItems(for: userID) { result in
            if case .failure = result {} else {
                XCTFail("expected remote failure")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
    }

    func testFetchRecentFoodItemsSuppressesRemoteFailureWhenCacheAlreadySucceeded() async throws {
        userDefaults.set(try JSONEncoder().encode([food("cached", "Cached Apple")]), forKey: cacheKey)
        mockRepo.recentFoodError = URLError(.timedOut)
        let finished = expectation(description: "cache success only")
        var resultNames: [[String]] = []

        store.fetchRecentFoodItems(for: userID) { result in
            if case .success(let items) = result {
                resultNames.append(items.map(\.name))
            } else {
                XCTFail("expected cached success")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(resultNames, [["Cached Apple"]])
    }

    func testLegacyCacheMigratesToHashedKeyAndRemovesRawUserID() async throws {
        let legacyKey = "recentFoods_\(userID)"
        userDefaults.set(
            try JSONEncoder().encode([food("legacy", "Legacy Apple")]),
            forKey: legacyKey
        )
        mockRepo.recentFoodsToReturn = []
        let cachedResult = expectation(description: "legacy cache result")

        store.fetchRecentFoodItems(for: userID) { result in
            if case .success(let items) = result, items.first?.name == "Legacy Apple" {
                cachedResult.fulfill()
            }
        }

        await fulfillment(of: [cachedResult], timeout: 1.0)
        XCTAssertNil(userDefaults.data(forKey: legacyKey))
        XCTAssertNotNil(userDefaults.data(forKey: cacheKey))
        let persistedKeys = userDefaults.dictionaryRepresentation().keys.joined(separator: "|")
        XCTAssertFalse(persistedKeys.contains(userID))
    }
}
