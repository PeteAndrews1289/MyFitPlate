import XCTest
@testable import MyFitPlateCore

final class FatSecretFoodAPIServiceTests: XCTestCase {
    
    // MARK: - Decoding Tests
    func testDecodeFatSecretResponse() throws {
        let json = """
        {
            "foods": {
                "food": [
                    {
                        "food_id": "123",
                        "food_name": "Apple",
                        "brand_name": "Generic",
                        "food_description": "Per 100g - Calories: 52kcal | Fat: 0.17g | Carbs: 13.81g | Protein: 0.26g"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(FatSecretResponse.self, from: json)
        XCTAssertEqual(response.foods?.food?.count, 1)
        XCTAssertEqual(response.foods?.food?.first?.foodID, "123")
        XCTAssertEqual(response.foods?.food?.first?.foodName, "Apple")
        XCTAssertEqual(response.foods?.food?.first?.brandName, "Generic")
    }
    
    func testDecodeFatSecretFoodResponse() throws {
        let json = """
        {
            "food": {
                "food_id": "456",
                "food_name": "Banana",
                "brand_name": "Chiquita",
                "servings": {
                    "serving": [
                        {
                            "calories": "89",
                            "protein": "1.09",
                            "carbohydrate": "22.84",
                            "fat": "0.33",
                            "fiber": "2.6"
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(FatSecretFoodResponse.self, from: json)
        XCTAssertEqual(response.food?.foodID, "456")
        XCTAssertEqual(response.food?.foodName, "Banana")
        XCTAssertEqual(response.food?.brandName, "Chiquita")
        
        let serving = response.food?.servings.serving.first
        XCTAssertNotNil(serving)
        XCTAssertEqual(serving?.parsedNutrient(.calories), 89.0)
        XCTAssertEqual(serving?.parsedNutrient(.protein), 1.09)
        XCTAssertEqual(serving?.parsedNutrient(.carbohydrate), 22.84)
        XCTAssertEqual(serving?.parsedNutrient(.fat), 0.33)
        XCTAssertEqual(serving?.parsedNutrient(.fiber), 2.6)
    }
    
    func testDecodeFatSecretServingsSingleItem() throws {
        let json = """
        {
            "serving": {
                "calories": "100"
            }
        }
        """.data(using: .utf8)!
        
        let servings = try JSONDecoder().decode(FatSecretServings.self, from: json)
        XCTAssertEqual(servings.serving.count, 1)
        XCTAssertEqual(servings.serving.first?.parsedNutrient(.calories), 100.0)
    }
    
    func testDecodeFatSecretServingsArray() throws {
        let json = """
        {
            "serving": [
                { "calories": "100" },
                { "calories": "200" }
            ]
        }
        """.data(using: .utf8)!
        
        let servings = try JSONDecoder().decode(FatSecretServings.self, from: json)
        XCTAssertEqual(servings.serving.count, 2)
        XCTAssertEqual(servings.serving.first?.parsedNutrient(.calories), 100.0)
        XCTAssertEqual(servings.serving.last?.parsedNutrient(.calories), 200.0)
    }
    
    func testParseDouble() throws {
        let json = """
        {
            "serving": {
                "calories": " 123.45 ",
                "protein": "N/A",
                "fat": "<0.1",
                "carbohydrate": ">5.0"
            }
        }
        """.data(using: .utf8)!
        let servings = try JSONDecoder().decode(FatSecretServings.self, from: json)
        let serving = servings.serving.first!
        XCTAssertEqual(serving.parsedNutrient(.calories), 123.45)
        XCTAssertEqual(serving.parsedNutrient(.protein), 0.0)
        XCTAssertEqual(serving.parsedNutrient(.fat), 0.1)
        XCTAssertEqual(serving.parsedNutrient(.carbohydrate), 5.0)
    }
    
    // MARK: - API Fetch Tests
    @MainActor
    func testFetchFoodByQuerySuccess() {
        let mockCloud = MockCloudFunctionService()
        DIContainer.shared.cloudFunctionService = mockCloud
        
        let jsonDict: [String: Any] = [
            "foods": [
                "food": [
                    [
                        "food_id": "123",
                        "food_name": "Apple",
                        "brand_name": "Generic",
                        "food_description": "Per 100g - Calories: 52kcal | Fat: 0.17g | Carbs: 13.81g | Protein: 0.26g"
                    ]
                ]
            ]
        ]
        mockCloud.mockCallFunctionResult = .success(jsonDict)
        
        let service = FatSecretFoodAPIService()
        let expectation = XCTestExpectation(description: "Fetch food by query")
        
        service.fetchFoodByQuery(query: "Apple") { result in
            switch result {
            case .success(let items):
                XCTAssertEqual(items.count, 1)
                XCTAssertEqual(items.first?.id, "123")
                XCTAssertEqual(items.first?.name, "Generic Apple")
                XCTAssertEqual(items.first?.calories, 52.0)
                XCTAssertEqual(items.first?.fats, 0.17)
                XCTAssertEqual(items.first?.carbs, 13.81)
                XCTAssertEqual(items.first?.protein, 0.26)
            case .failure(let error):
                XCTFail("Expected success, got error \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    @MainActor
    func testFetchFoodDetailsSuccess() {
        let mockCloud = MockCloudFunctionService()
        DIContainer.shared.cloudFunctionService = mockCloud
        
        let jsonDict: [String: Any] = [
            "food": [
                "food_id": "456",
                "food_name": "Banana",
                "brand_name": "Chiquita",
                "servings": [
                    "serving": [
                        [
                            "calories": "89",
                            "protein": "1.09",
                            "carbohydrate": "22.84",
                            "fat": "0.33",
                            "fiber": "2.6",
                            "metric_serving_amount": "118",
                            "metric_serving_unit": "g"
                        ]
                    ]
                ]
            ]
        ]
        mockCloud.mockCallFunctionResult = .success(jsonDict)
        
        let service = FatSecretFoodAPIService()
        let expectation = XCTestExpectation(description: "Fetch food details")
        
        service.fetchFoodDetails(foodId: "456") { result in
            switch result {
            case .success(let data):
                XCTAssertEqual(data.foodInfo.id, "456")
                XCTAssertEqual(data.foodInfo.name, "Chiquita Banana")
                XCTAssertEqual(data.foodInfo.calories, 89.0)
                XCTAssertEqual(data.foodInfo.servingWeight, 118.0)
                XCTAssertEqual(data.availableServings.count, 1)
            case .failure(let error):
                XCTFail("Expected success, got error \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    @MainActor
    func testCallProxyFailure() {
        let mockCloud = MockCloudFunctionService()
        DIContainer.shared.cloudFunctionService = mockCloud
        
        mockCloud.mockCallFunctionResult = .failure(NSError(domain: "test", code: -1))
        
        let service = FatSecretFoodAPIService()
        let expectation = XCTestExpectation(description: "Fetch food failure")
        
        service.fetchFoodByQuery(query: "Apple") { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}
