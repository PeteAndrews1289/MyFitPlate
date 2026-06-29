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
}
