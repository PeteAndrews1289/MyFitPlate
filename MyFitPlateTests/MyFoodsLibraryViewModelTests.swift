import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class MyFoodsLibraryViewModelTests: XCTestCase {
    private var repository: MockNutritionRepository!
    private var store: CustomFoodStore!

    override func setUp() {
        super.setUp()
        let auth = MockAuthService()
        auth.currentUserID = "library-user"
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repository
        store = CustomFoodStore()
    }

    func testEditUpdatesVisibleCopyOnlyAfterPersistenceSucceeds() {
        let original = food(id: "food", name: "Original")
        let edited = food(id: "food", name: "Edited")
        let model = MyFoodsLibraryViewModel(
            initialFoods: [original],
            startsLoading: false
        )
        let completion = expectation(description: "edit")

        model.saveEditedFood(edited, using: store) { success in
            XCTAssertTrue(success)
            completion.fulfill()
        }

        XCTAssertEqual(model.savedFoods.first?.name, "Original")
        wait(for: [completion], timeout: 2)
        XCTAssertEqual(model.savedFoods.first?.name, "Edited")
        XCTAssertEqual(repository.savedCustomFoods.first?.id, original.id)
    }

    func testFailedDeleteKeepsVisibleCopy() {
        repository.customFoodError = URLError(.notConnectedToInternet)
        let item = food(id: "food", name: "Saved")
        let model = MyFoodsLibraryViewModel(
            initialFoods: [item],
            startsLoading: false
        )
        let completion = expectation(description: "delete")

        model.deleteFood(item, using: store) { success in
            XCTAssertFalse(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(model.savedFoods.map(\.id), [item.id])
    }

    func testBarcodeRemovalKeepsFoodAndUpdatesAssociation() {
        let item = food(id: "food", name: "Saved", barcode: "0044000087579")
        let model = MyFoodsLibraryViewModel(
            initialFoods: [item],
            startsLoading: false
        )
        let completion = expectation(description: "barcode")

        model.removeBarcodeAssociation(from: item, using: store) { success in
            XCTAssertTrue(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(model.savedFoods.count, 1)
        XCTAssertNil(model.savedFoods.first?.sourceMetadata?.barcode)
        XCTAssertEqual(repository.barcodeRemovedCustomFoodIDs, [item.id])
    }

    func testMergeRemovesOnlyDuplicateCopiesAfterAtomicSuccess() throws {
        let keeper = food(id: "a", name: "Saved")
        let duplicate = food(id: "b", name: " saved ")
        let distinct = food(id: "c", name: "Distinct")
        let model = MyFoodsLibraryViewModel(
            initialFoods: [duplicate, distinct, keeper],
            startsLoading: false
        )
        let group = try XCTUnwrap(model.duplicateGroups.first)
        let completion = expectation(description: "merge")

        model.mergeDuplicates(group, using: store) { success in
            XCTAssertTrue(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
        XCTAssertEqual(Set(model.savedFoods.map(\.id)), Set([group.keeper.id, distinct.id]))
        XCTAssertEqual(repository.mergedCustomFoodOperations.count, 1)
    }

    private func food(
        id: String,
        name: String,
        barcode: String? = nil
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            calories: 180,
            protein: 20,
            carbs: 16,
            fats: 4,
            saturatedFat: 1,
            fiber: 3,
            servingSize: "1 serving (100 g)",
            servingWeight: 100,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                sourceID: id,
                barcode: barcode,
                matchedFoodID: id
            )
        )
    }
}
