import XCTest
@testable import MyFitPlateCore

@MainActor
final class CustomFoodStoreTests: XCTestCase {
    private var mockRepo: MockNutritionRepository!
    private var store: CustomFoodStore!

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        store = CustomFoodStore()
    }

    private func food(_ id: String, _ name: String) -> FoodItem {
        FoodItem(id: id, name: name, calories: 100, protein: 20, carbs: 20, fats: 20)
    }

    private func barcodeFood(
        _ id: String,
        barcode: String,
        calories: Double = 100,
        saturatedFat: Double? = nil,
        reviewStatus: FoodReviewStatus = .userConfirmed
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: "Barcode Food",
            calories: calories,
            protein: 10,
            carbs: 15,
            fats: 5,
            saturatedFat: saturatedFat,
            servingSize: "1 package",
            servingWeight: 50,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: reviewStatus,
                sourceName: "My Foods",
                sourceID: id,
                barcode: barcode,
                matchedFoodID: id
            )
        )
    }

    func testSaveSuccessRecordsItemAndReportsTrue() {
        let exp = expectation(description: "save")
        store.saveCustomFood(for: "u1", foodItem: food("1", "Apple")) { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(mockRepo.savedCustomFoods.map { $0.name }, ["Apple"])
    }

    func testSaveFailureReportsFalseAndRecordsNothing() {
        mockRepo.customFoodError = URLError(.notConnectedToInternet)
        let exp = expectation(description: "save fail")
        store.saveCustomFood(for: "u1", foodItem: food("1", "Apple")) { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(mockRepo.savedCustomFoods.isEmpty)
    }

    func testBarcodeCorrectionReusesExistingIdentityAndClearsOptionalNutrients() throws {
        let barcode = "012345678905"
        mockRepo.customFoodsToReturn = [
            barcodeFood("existing", barcode: barcode, saturatedFat: 9)
        ]
        let correction = barcodeFood(
            "new-random-id",
            barcode: barcode,
            calories: 120,
            saturatedFat: nil,
            reviewStatus: .userEdited
        )
        let exp = expectation(description: "barcode correction")
        var persisted: FoodItem?

        store.saveBarcodeCorrection(for: "u1", foodItem: correction) { result in
            persisted = try? result.get()
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        let saved = try XCTUnwrap(persisted)
        XCTAssertEqual(saved.id, "existing")
        XCTAssertEqual(saved.sourceMetadata?.sourceID, "existing")
        XCTAssertEqual(saved.calories, 120)
        XCTAssertNil(saved.saturatedFat)
        XCTAssertEqual(mockRepo.replacedCustomFoodOperations.count, 1)
        XCTAssertNil(mockRepo.replacedCustomFoodOperations.first?.foodItem.saturatedFat)
        XCTAssertTrue(mockRepo.replacedCustomFoodOperations.first?.removing.isEmpty == true)
    }

    func testBarcodeCorrectionCollapsesAllOtherMatchingEntries() throws {
        let barcode = "012345678905"
        let confirmed = barcodeFood("confirmed", barcode: barcode)
        let edited = barcodeFood(
            "edited",
            barcode: "0012345678905",
            calories: 130,
            reviewStatus: .userEdited
        )
        mockRepo.customFoodsToReturn = [confirmed, edited]
        let correction = barcodeFood("incoming", barcode: barcode, calories: 140)
        let exp = expectation(description: "deduplicate barcode correction")
        var persisted: FoodItem?

        store.saveBarcodeCorrection(for: "u1", foodItem: correction) { result in
            persisted = try? result.get()
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        XCTAssertEqual(try XCTUnwrap(persisted).id, "edited")
        XCTAssertEqual(mockRepo.replacedCustomFoodOperations.count, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(mockRepo.replacedCustomFoodOperations.first).removing),
            Set(["confirmed"])
        )
    }

    func testNewEquivalentBarcodeCorrectionsUseTheSameStableIdentity() throws {
        let upc = barcodeFood("first-random", barcode: "012345678905")
        let ean = barcodeFood("second-random", barcode: "0012345678905")
        let firstExp = expectation(description: "save UPC correction")
        let secondExp = expectation(description: "save EAN correction")
        var firstSaved: FoodItem?
        var secondSaved: FoodItem?

        store.saveBarcodeCorrection(for: "u1", foodItem: upc) { result in
            firstSaved = try? result.get()
            firstExp.fulfill()
        }
        store.saveBarcodeCorrection(for: "u1", foodItem: ean) { result in
            secondSaved = try? result.get()
            secondExp.fulfill()
        }

        wait(for: [firstExp, secondExp], timeout: 2)
        let firstID = try XCTUnwrap(firstSaved).id
        XCTAssertEqual(firstID, try XCTUnwrap(secondSaved).id)
        XCTAssertTrue(firstID.hasPrefix("barcode-"))
    }

    func testBarcodeCorrectionDoesNotWriteWhenExistingLibraryCannotLoad() {
        mockRepo.customFoodError = URLError(.notConnectedToInternet)
        let correction = barcodeFood("incoming", barcode: "012345678905")
        let exp = expectation(description: "barcode fetch failure")

        store.saveBarcodeCorrection(for: "u1", foodItem: correction) { result in
            if case .success = result {
                XCTFail("Expected the correction to fail closed")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        XCTAssertTrue(mockRepo.savedCustomFoods.isEmpty)
        XCTAssertTrue(mockRepo.replacedCustomFoodOperations.isEmpty)
    }

    func testDeleteSuccessRecordsIDAndReportsTrue() {
        let exp = expectation(description: "delete")
        store.deleteCustomFood(for: "u1", foodItemID: "abc") { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(mockRepo.deletedCustomFoodIDs, ["abc"])
    }

    func testDeleteFailureReportsFalse() {
        mockRepo.customFoodError = URLError(.timedOut)
        let exp = expectation(description: "delete fail")
        store.deleteCustomFood(for: "u1", foodItemID: "abc") { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testFetchReturnsSeededItemsInOrder() {
        mockRepo.customFoodsToReturn = [food("1", "Apple"), food("2", "Banana")]
        let exp = expectation(description: "fetch")
        store.fetchMyFoodItems(for: "u1") { result in
            switch result {
            case .success(let items): XCTAssertEqual(items.map { $0.name }, ["Apple", "Banana"])
            case .failure: XCTFail("expected success")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testFetchPropagatesError() {
        mockRepo.customFoodError = URLError(.timedOut)
        let exp = expectation(description: "fetch fail")
        store.fetchMyFoodItems(for: "u1") { result in
            if case .failure = result {} else { XCTFail("expected failure") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    func testRemoveBarcodeAssociationRecordsIDAndReportsTrue() {
        let exp = expectation(description: "remove barcode")
        store.removeBarcodeAssociation(for: "u1", foodItemID: "barcode-food") { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(mockRepo.barcodeRemovedCustomFoodIDs, ["barcode-food"])
    }

    func testRemoveBarcodeAssociationFailsClosed() {
        mockRepo.customFoodError = URLError(.timedOut)
        let exp = expectation(description: "remove barcode fail")
        store.removeBarcodeAssociation(for: "u1", foodItemID: "barcode-food") { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(mockRepo.barcodeRemovedCustomFoodIDs.isEmpty)
    }

    func testMergeRecordsKeeperAndDuplicateIDs() {
        let exp = expectation(description: "merge")
        store.mergeCustomFoods(
            for: "u1",
            keepingFoodID: "keeper",
            removingFoodIDs: ["duplicate-a", "duplicate-b"]
        ) { ok in
            XCTAssertTrue(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(mockRepo.mergedCustomFoodOperations.count, 1)
        XCTAssertEqual(mockRepo.mergedCustomFoodOperations.first?.keeping, "keeper")
        XCTAssertEqual(
            mockRepo.mergedCustomFoodOperations.first?.removing,
            ["duplicate-a", "duplicate-b"]
        )
    }

    func testMergeFailsClosed() {
        mockRepo.customFoodError = URLError(.notConnectedToInternet)
        let exp = expectation(description: "merge fail")
        store.mergeCustomFoods(
            for: "u1",
            keepingFoodID: "keeper",
            removingFoodIDs: ["duplicate"]
        ) { ok in
            XCTAssertFalse(ok)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(mockRepo.mergedCustomFoodOperations.isEmpty)
    }
}
