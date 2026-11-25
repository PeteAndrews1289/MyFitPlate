import XCTest
import HealthKit
@testable import MyFitPlateCore

final class HealthKitCopyNutritionTests: XCTestCase {
    func testCopySamplesHaveStableDistinctOwnerFoodAndNutrientSyncIdentityWhileLegacySamplesStayUnchanged() async throws {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let food = FoodItem(id: "fresh-copy-id", name: "Rice", calories: 200, protein: 5, carbs: 40, fats: 2, timestamp: date)
        let saved: Bool = await withCheckedContinuation { continuation in
            manager.saveCopiedNutrition(for: food, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(saved)
        let first = store.savedObjects.compactMap { $0 as? HKQuantitySample }
        XCTAssertEqual(first.count, 4)
        let identifiers = try first.map { sample -> String in
            XCTAssertEqual(sample.startDate, date)
            XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber, NSNumber(value: 1))
            XCTAssertEqual(sample.metadata?["MyFitPlateTransferCopy"] as? Bool, true)
            XCTAssertEqual(sample.metadata?["MyFitPlateFoodItemID"] as? String, food.id)
            return try XCTUnwrap(sample.metadata?[HKMetadataKeySyncIdentifier] as? String)
        }
        XCTAssertEqual(Set(identifiers).count, 4)
        let replayed: Bool = await withCheckedContinuation { continuation in
            manager.saveCopiedNutrition(for: food, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(replayed)
        XCTAssertEqual(store.savedObjects.suffix(4).compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }, identifiers,
                       "The same sync identifier/version lets HealthKit discard an acknowledgement-loss replay")
        XCTAssertNotEqual(HealthKitManager.copiedNutritionSyncIdentifier(foodID: food.id, userID: "other", nutrientIdentifier: "energy"),
                          HealthKitManager.copiedNutritionSyncIdentifier(foodID: food.id, userID: "owner", nutrientIdentifier: "energy"))
        manager.saveNutrition(for: food)
        for sample in store.savedObjects.suffix(4) {
            XCTAssertNil(sample.metadata?[HKMetadataKeySyncIdentifier])
            XCTAssertNil(sample.metadata?["MyFitPlateTransferCopy"], "Legacy export semantics remain unchanged")
        }
    }

    func testMissingWritePermissionAndInvalidTimestampCannotExportOrReportSuccess() async {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store)
        let food = FoodItem(id: "fresh-id", name: "Rice", calories: 200, timestamp: Date())
        store.shareAuthorizationResult = .sharingDenied
        XCTAssertFalse(manager.canSaveCopiedNutrition(for: food))
        let denied: Bool = await withCheckedContinuation { continuation in
            manager.saveCopiedNutrition(for: food, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(denied)
        XCTAssertTrue(store.savedObjects.isEmpty)
        store.shareAuthorizationResult = .sharingAuthorized
        var invalid = food; invalid.timestamp = nil
        let invalidResult: Bool = await withCheckedContinuation { continuation in
            manager.saveCopiedNutrition(for: invalid, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(invalidResult)
        XCTAssertTrue(store.savedObjects.isEmpty)
    }

    func testUndoDeletesOnlyExactCopiedSampleMetadataAndAggregatesFailure() async throws {
        let store = MockHealthStore()
        let manager = HealthKitManager(store: store)
        let food = FoodItem(id: "fresh-copy-id", name: "Rice", calories: 200, timestamp: Date())
        let deleted: Bool = await withCheckedContinuation { continuation in
            manager.deleteCopiedNutrition(for: food, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.deletedPredicates.count, 4)
        for predicate in store.deletedPredicates {
            let parts = try XCTUnwrap(predicate as? NSCompoundPredicate).subpredicates
            XCTAssertEqual(parts.count, 3, "Deletion must require the exact sync key, copied-sample marker and fresh food ID")
        }
        store.deleteSuccess = false
        let failed: Bool = await withCheckedContinuation { continuation in
            manager.deleteCopiedNutrition(for: food, userID: "owner") { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(failed)
    }
}
