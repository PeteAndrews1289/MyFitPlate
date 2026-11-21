import XCTest
@testable import MyFitPlateCore

final class FoodLoggingDraftTests: XCTestCase {
    func testDraftRetainsDestinationEntryIdentityAndAllNutrientsAcrossRestart() throws {
        var draft = FoodLoggingDraft(date: Date(timeIntervalSince1970: 1_700_000_000), mealName: "Lunch")
        let food = FoodItem(id: "database-id", name: "Oats", calories: 200, protein: 8, servingSize: "1 cup", calcium: 100,
                            quantityValue: 1, servingUnit: "cup")
        draft.entries = [FoodLoggingDraft.Entry(food: food)]
        draft.entries[0].multiplier = 1.5
        draft.isSubmitted = true
        let restored = try JSONDecoder().decode(FoodLoggingDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.id, draft.id)
        XCTAssertEqual(restored.date, draft.date)
        XCTAssertEqual(restored.mealName, "Lunch")
        XCTAssertEqual(restored.foods.first?.id, draft.foods.first?.id)
        XCTAssertNotEqual(restored.foods.first?.id, food.id)
        XCTAssertEqual(restored.foods.first?.calcium, 150)
        XCTAssertEqual(restored.foods.first?.quantityValue, 1.5)
        XCTAssertEqual(restored.calories, 300)
        XCTAssertTrue(restored.isSubmitted)
    }
}
