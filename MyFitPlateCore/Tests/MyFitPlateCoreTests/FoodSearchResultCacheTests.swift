import XCTest
@testable import MyFitPlateCore

final class FoodSearchResultCacheTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let milk = FoodItem(id: "milk", name: "Milk 2%", calories: 120)

    func testProviderBatchesExpireIndependentlyAndSuccessfulEmptyIsReusable() {
        var cache = FoodSearchResultCache(lifetime: 10)
        cache.store([milk], for: "milk", provider: .fatSecret, now: start)
        cache.store([], for: "milk", provider: .usda, now: start.addingTimeInterval(5))
        let first = cache.batches(for: "milk", now: start.addingTimeInterval(9))
        XCTAssertEqual(first[.fatSecret]?.map(\.id), ["milk"])
        XCTAssertNotNil(first[.usda])
        XCTAssertNil(first[.openFoodFacts], "Unrequested or failed sources are never an empty success")
        let later = cache.batches(for: "milk", now: start.addingTimeInterval(10))
        XCTAssertNil(later[.fatSecret])
        XCTAssertNotNil(later[.usda])
        XCTAssertTrue(cache.batches(for: "milk", now: start.addingTimeInterval(15)).isEmpty)
    }

    func testQueryEquivalenceRetainsProductQualifiers() {
        var cache = FoodSearchResultCache()
        cache.store([milk], for: "Milk  2%", provider: .fatSecret, now: start)
        XCTAssertEqual(cache.batches(for: "  MILK\n2% ", now: start)[.fatSecret]?.first?.id, "milk")
        XCTAssertTrue(cache.batches(for: "milk 2", now: start).isEmpty)
        XCTAssertTrue(cache.batches(for: "milk", now: start).isEmpty)
        XCTAssertNotEqual(FoodSearchResultCache.queryKey("sugar-free"), FoodSearchResultCache.queryKey("sugar free"))
    }

    func testLeastRecentlyUsedQueryEvictsAsAWholeAndClearRemovesAll() {
        var cache = FoodSearchResultCache(capacity: 2)
        cache.store([milk], for: "milk", provider: .fatSecret, now: start)
        cache.store([], for: "milk", provider: .usda, now: start)
        cache.store([], for: "apple", provider: .usda, now: start)
        _ = cache.batches(for: "milk", now: start)
        cache.store([], for: "rice", provider: .usda, now: start)
        XCTAssertTrue(cache.batches(for: "apple", now: start).isEmpty)
        XCTAssertEqual(cache.batches(for: "milk", now: start).count, 2)
        cache.removeAll()
        XCTAssertTrue(cache.batches(for: "milk", now: start).isEmpty)
        XCTAssertTrue(cache.batches(for: "rice", now: start).isEmpty)
    }

    func testClockReversalDoesNotReuseFutureResponse() {
        var cache = FoodSearchResultCache()
        cache.store([milk], for: "milk", provider: .fatSecret, now: start)
        XCTAssertTrue(cache.batches(for: "milk", now: start.addingTimeInterval(-1)).isEmpty)
    }

    func testZeroCapacityOrLifetimeNeverCachesResponses() {
        for (capacity, lifetime) in [(0, 300.0), (12, 0.0)] {
            var cache = FoodSearchResultCache(lifetime: lifetime, capacity: capacity)
            cache.store([milk], for: "milk", provider: .fatSecret, now: start)
            XCTAssertTrue(cache.batches(for: "milk", now: start).isEmpty)
        }
    }
}
