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
        XCTAssertEqual(apple.name, "Apple, Raw, With Skin")
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

    func testMicronutrientUnitsAndReportedZerosArePreserved() throws {
        let json = """
        {
            "foods": [
                {
                    "fdcId": 9012,
                    "description": "BANANA, RAW",
                    "dataType": "SR Legacy",
                    "servingSize": 200.0,
                    "servingSizeUnit": "g",
                    "foodNutrients": [
                        { "nutrientNumber": "208", "value": 89.0 },
                        { "nutrientNumber": "203", "value": 1.1 },
                        { "nutrientNumber": "205", "value": 22.8 },
                        { "nutrientNumber": "204", "value": 0.3 },
                        { "nutrientNumber": "307", "value": 0.0 },
                        { "nutrientNumber": "318", "value": 64.0 },
                        { "nutrientNumber": "320", "value": 3.0 },
                        { "nutrientNumber": "312", "value": 0.078 }
                    ]
                }
            ]
        }
        """

        let banana = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(json.utf8)).first)

        XCTAssertEqual(banana.vitaminA, 6, "Vitamin A uses mcg RAE nutrient 320, not IU nutrient 318")
        XCTAssertEqual(banana.copper, 156, "Copper converts USDA mg to the app's mcg unit")
        XCTAssertNotNil(banana.sodium, "A reported zero is different from an unreported nutrient")
        XCTAssertEqual(banana.sodium, 0)
    }
}
