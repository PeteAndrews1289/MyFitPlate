import XCTest
@testable import MyFitPlateCore

final class USDAFoodAPIServiceTests: XCTestCase {
    func testParsingValidJSON() throws {
        let json = """
        {
            "foods": [
                {
                    "fdcId": 1234,
                    "description": "APPLE, RAW, WITH SKIN",
                    "dataType": "Foundation",
                    "servingSize": 150.0,
                    "servingSizeUnit": "g",
                    "householdServingFullText": "1 large",
                    "foodNutrients": [
                        { "nutrientNumber": "208", "value": 52.0 },
                        { "nutrientNumber": "203", "value": 0.3 },
                        { "nutrientNumber": "205", "value": 14.0 },
                        { "nutrientNumber": "204", "value": 0.2 },
                        { "nutrientNumber": "291", "value": 2.4 }
                    ]
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let items = try USDAFoodParser.foodItems(from: data)
        XCTAssertEqual(items.count, 1)
        
        let apple = items[0]
        XCTAssertEqual(apple.id, "usda_1234")
        XCTAssertEqual(apple.name, "Apple")
        XCTAssertEqual(apple.servingSize, "1 large")
        XCTAssertEqual(apple.servingWeight, 150.0)
        
        // Scaled values (serving size is 150g, factor = 1.5)
        XCTAssertEqual(apple.calories, 52.0 * 1.5, accuracy: 0.1)
        XCTAssertEqual(apple.protein, 0.3 * 1.5, accuracy: 0.1)
        XCTAssertEqual(apple.carbs, 14.0 * 1.5, accuracy: 0.1)
        XCTAssertEqual(apple.fats, 0.2 * 1.5, accuracy: 0.1)
        XCTAssertEqual(apple.fiber ?? 0, 2.4 * 1.5, accuracy: 0.1)
    }

    func testParsingDefaultServing() throws {
        let json = """
        {
            "foods": [
                {
                    "fdcId": 5678,
                    "description": "MILK",
                    "foodNutrients": [
                        { "nutrientNumber": "208", "value": 42.0 }
                    ]
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let items = try USDAFoodParser.foodItems(from: data)
        XCTAssertEqual(items.count, 1)
        
        let milk = items[0]
        XCTAssertEqual(milk.id, "usda_5678")
        XCTAssertEqual(milk.name, "Milk")
        XCTAssertEqual(milk.servingSize, "100 g") // default
        XCTAssertEqual(milk.servingWeight, 100.0)
        XCTAssertEqual(milk.calories, 42.0, accuracy: 0.1)
    }
}
