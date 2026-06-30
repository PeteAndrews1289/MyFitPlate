import XCTest
@testable import MyFitPlateCore

final class OpenFoodFactsAPIServiceTests: XCTestCase {
    
    func testParsingValidJSON() throws {
        let json = """
        {
            "status": 1,
            "product": {
                "code": "1234567890",
                "product_name": "Test Food",
                "serving_size": "50g",
                "nutriments": {
                    "energy-kcal_100g": 200,
                    "proteins_100g": 10.5,
                    "carbohydrates_100g": 30.0,
                    "fat_100g": 5.0,
                    "saturated-fat_100g": 1.5,
                    "fiber_100g": 4.0,
                    "sodium_100g": 0.5,
                    "potassium_100g": 2.0,
                    "calcium_100g": 0.1,
                    "vitamin-c_100g": 0.05
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let food = try OpenFoodFactsParser.foodItem(from: data)
        XCTAssertNotNil(food)
        
        let item = food!
        XCTAssertEqual(item.id, "off_1234567890")
        XCTAssertEqual(item.name, "Test Food")
        XCTAssertEqual(item.servingSize, "50g")
        XCTAssertEqual(item.servingWeight, 100.0)
        XCTAssertEqual(item.calories, 200.0)
        XCTAssertEqual(item.protein, 10.5)
        XCTAssertEqual(item.carbs, 30.0)
        XCTAssertEqual(item.fats, 5.0)
        XCTAssertEqual(item.saturatedFat, 1.5)
        XCTAssertEqual(item.fiber, 4.0)
        
        // Converted values (g -> mg)
        XCTAssertEqual(item.sodium ?? 0, 500.0, accuracy: 0.1) // 0.5g = 500mg
        XCTAssertEqual(item.calcium ?? 0, 100.0, accuracy: 0.1) // 0.1g = 100mg
        XCTAssertEqual(item.potassium ?? 0, 2.0, accuracy: 0.1)
        XCTAssertEqual(item.vitaminC ?? 0, 50.0, accuracy: 0.1) // 0.05g = 50mg
    }
    
    func testParsingMissingProduct() throws {
        let json = """
        {
            "status": 0,
            "product": null
        }
        """
        let data = json.data(using: .utf8)!
        let food = try OpenFoodFactsParser.foodItem(from: data)
        XCTAssertNil(food)
    }
    
    func testParsingDefaultValues() throws {
        let json = """
        {
            "status": 1,
            "product": {
                "code": "9876",
                "nutriments": {}
            }
        }
        """
        let data = json.data(using: .utf8)!
        let food = try OpenFoodFactsParser.foodItem(from: data)
        XCTAssertNotNil(food)
        
        let item = food!
        XCTAssertEqual(item.name, "Unknown Product")
        XCTAssertEqual(item.servingSize, "100g")
        XCTAssertEqual(item.calories, 0)
        XCTAssertEqual(item.protein, 0)
        XCTAssertEqual(item.carbs, 0)
        XCTAssertEqual(item.fats, 0)
    }
}
