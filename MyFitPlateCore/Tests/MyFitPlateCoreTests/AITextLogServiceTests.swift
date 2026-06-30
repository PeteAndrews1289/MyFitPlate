import XCTest
@testable import MyFitPlateCore

@MainActor
final class AITextLogServiceTests: XCTestCase {
    
    private var mockAI: MockAIService!
    private var service: AITextLogService!
    
    override func setUp() {
        super.setUp()
        mockAI = MockAIService()
        DIContainer.shared.aiService = mockAI
        service = AITextLogService()
    }
    
    func testEstimateNutritionSuccess() async {
        let jsonResponse = """
        {
            "foods": [
                {
                    "itemName": "Salmon",
                    "servingSize": "6 oz",
                    "calories": 340,
                    "protein": 34,
                    "carbs": 0,
                    "fats": 22,
                    "fiber": 0,
                    "calcium": 25,
                    "iron": 1,
                    "potassium": 970,
                    "sodium": 100,
                    "vitaminA": 50,
                    "vitaminC": 0,
                    "vitaminD": 12,
                    "vitaminB12": 4.5,
                    "folate": 25
                }
            ]
        }
        """
        mockAI.mockResult = .success(jsonResponse)
        
        let result = await service.estimateNutrition(from: "6 oz salmon")
        
        switch result {
        case .success(let items):
            XCTAssertEqual(items.count, 1)
            let item = items[0]
            XCTAssertEqual(item.name, "Salmon")
            XCTAssertEqual(item.servingSize, "6 oz")
            XCTAssertEqual(item.calories, 340)
            XCTAssertEqual(item.protein, 34)
            XCTAssertEqual(item.calcium, 25)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
    
    func testEstimateNutritionAPIError() async {
        mockAI.mockResult = .failure(AIError.apiError("Timeout"))
        
        let result = await service.estimateNutrition(from: "apple")
        
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .apiError(let msg) = error {
                XCTAssertEqual(msg, "AI Error: Timeout")
                XCTAssertEqual(error.errorDescription, "An error occurred with the AI service: AI Error: Timeout")
            } else {
                XCTFail("Expected apiError")
            }
        }
    }
    
    func testEstimateNutritionParsingError() async {
        mockAI.mockResult = .success("invalid json")
        
        let result = await service.estimateNutrition(from: "apple")
        
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .parsingError = error {
                // success
            } else {
                XCTFail("Expected parsingError")
            }
        }
    }
    
    func testNetworkErrorDescription() {
        let error = AITextLogError.networkError(NSError(domain: "", code: 0, userInfo: nil))
        XCTAssertEqual(error.errorDescription, "A network error occurred. Please check your connection and try again.")
        
        let parseError = AITextLogError.parsingError("Bad JSON")
        XCTAssertEqual(parseError.errorDescription, "The AI response could not be understood. Details: Bad JSON")
    }
}
