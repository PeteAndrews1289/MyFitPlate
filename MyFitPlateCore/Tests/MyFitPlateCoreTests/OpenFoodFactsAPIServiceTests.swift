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
                "last_modified_t": 1764547200,
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
        XCTAssertEqual(item.servingWeight, 50.0)
        XCTAssertEqual(item.calories, 100.0)
        XCTAssertEqual(item.protein, 5.25)
        XCTAssertEqual(item.carbs, 15.0)
        XCTAssertEqual(item.fats, 2.5)
        XCTAssertEqual(item.saturatedFat, 0.75)
        XCTAssertEqual(item.fiber, 2.0)
        
        // Converted values (g -> mg)
        XCTAssertEqual(item.sodium ?? 0, 250.0, accuracy: 0.1)
        XCTAssertEqual(item.calcium ?? 0, 50.0, accuracy: 0.1)
        XCTAssertEqual(item.potassium ?? 0, 1000.0, accuracy: 0.1)
        XCTAssertEqual(item.vitaminC ?? 0, 25.0, accuracy: 0.1)
        XCTAssertEqual(item.sourceMetadata?.effectiveEvidenceLineage, .publicDatabase)
        XCTAssertEqual(
            item.sourceMetadata?.sourceUpdatedAt,
            Date(timeIntervalSince1970: 1_764_547_200)
        )
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
        XCTAssertNil(food, "products without usable nutrition must not appear as zero-calorie foods")
    }

    func testParsingSearchResponse() throws {
        let json = """
        {
            "count": 2,
            "products": [
                {
                    "code": "1111",
                    "product_name": "Greek Yogurt Plain",
                    "serving_size": "170g",
                    "nutriments": {
                        "energy-kcal_100g": 59,
                        "proteins_100g": 10.0,
                        "carbohydrates_100g": 3.6,
                        "fat_100g": 0.4
                    }
                },
                {
                    "code": "2222",
                    "product_name": "   ",
                    "nutriments": {}
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let results = try OpenFoodFactsParser.searchFoods(from: data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "Greek Yogurt Plain")
        XCTAssertEqual(results[0].servingWeight, 170)
        XCTAssertEqual(results[0].calories, 100.3, accuracy: 0.001)
        XCTAssertEqual(results[0].protein, 17, accuracy: 0.001)
        XCTAssertEqual(results[0].sourceMetadata?.sourceType, .openFoodFacts)
    }

    func testPerServingValuesWinWhenProvided() throws {
        let json = """
        {
            "status": 1,
            "product": {
                "code": "3333",
                "product_name": "Protein Drink",
                "serving_size": "1 bottle (330ml)",
                "serving_quantity": 330,
                "nutriments": {
                    "energy-kcal_100g": 50,
                    "energy-kcal_serving": 165,
                    "proteins_100g": 3,
                    "proteins_serving": 10
                }
            }
        }
        """

        let food = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: Data(json.utf8)))

        XCTAssertEqual(food.servingWeight, 330)
        XCTAssertEqual(food.calories, 165)
        XCTAssertEqual(food.protein, 10)
    }

    func testServingWeightParsesGramsInsideAHouseholdDescription() throws {
        let json = """
        {
            "status": 1,
            "product": {
                "code": "4444",
                "product_name": "Snack Bar",
                "serving_size": "1 bar (30 g)",
                "nutriments": {
                    "energy-kcal_100g": 400,
                    "proteins_100g": 20
                }
            }
        }
        """

        let food = try XCTUnwrap(OpenFoodFactsParser.foodItem(from: Data(json.utf8)))

        XCTAssertEqual(food.servingWeight, 30)
        XCTAssertEqual(food.calories, 120)
        XCTAssertEqual(food.protein, 6)
    }
}
