import XCTest
@testable import MyFitPlateCore

final class USDAFoodAPIServiceTests: XCTestCase {
    private struct Criteria: Decodable {
        let query: String
        let requireAllWords: Bool
        let dataType: [String]
        let pageSize: Int
    }

    private static func criteria(_ request: URLRequest) throws -> Criteria {
        try JSONDecoder().decode(Criteria.self, from: XCTUnwrap(request.httpBody))
    }

    func testSearchRequiresEveryTypedTermBeforeBoundedResultsAreRanked() throws {
        let request = try XCTUnwrap(USDAFoodRequestBuilder.searchRequest(query: " Fairlife 2% milk ", apiKey: "test-key"))
        let criteria = try Self.criteria(request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(criteria.query, "Fairlife 2% milk")
        XCTAssertTrue(criteria.requireAllWords)
        XCTAssertEqual(criteria.pageSize, 20)
        XCTAssertEqual(criteria.dataType, ["Branded", "Foundation", "SR Legacy", "Survey (FNDDS)"])
    }

    func testSearchBoundsInputAndDoesNotAllowQueryParameterInjection() throws {
        let request = try XCTUnwrap(USDAFoodRequestBuilder.searchRequest(query: "milk&requireAllWords=false", apiKey: "test-key"))
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items, [URLQueryItem(name: "api_key", value: "test-key")])
        let criteria = try Self.criteria(request)
        XCTAssertTrue(criteria.requireAllWords)
        XCTAssertEqual(criteria.query, "milk&requireAllWords=false")
        let long = try XCTUnwrap(USDAFoodRequestBuilder.searchRequest(query: String(repeating: "x", count: 500), apiKey: "test-key"))
        XCTAssertEqual(try Self.criteria(long).query.count, 160)
        XCTAssertNil(USDAFoodRequestBuilder.searchRequest(query: " \n ", apiKey: "test-key"))
    }

    func testBrandedGRMServingUsesTheLabelWeightForNutrition() throws {
        let data = Data(#"{"foods":[{"fdcId":9,"description":"Old fashioned oats","brandName":"Quaker","servingSize":40,"servingSizeUnit":"GRM","householdServingFullText":"1/2 cup dry (40 g)","foodNutrients":[{"nutrientNumber":"208","value":375}]}]}"#.utf8)
        let oats = try XCTUnwrap(USDAFoodParser.foodItems(from: data).first)
        XCTAssertEqual(oats.servingSize, "1/2 cup dry (40 g)")
        XCTAssertEqual(oats.servingWeight, 40)
        XCTAssertEqual(oats.calories, 150)
    }

    func testScannedEANFindsOnlyTheMatchingPaddedPackageInOneBrandedRequest() async throws {
        var requests = 0
        let item = try await USDAFoodSearchPipeline.barcode("0856312002795", apiKey: "test", includeEquivalentCodes: true, timeout: 6) { request, _ in
            requests += 1
            let criteria = try Self.criteria(request)
            XCTAssertEqual(criteria.query, "0856312002795 856312002795 00856312002795")
            XCTAssertFalse(criteria.requireAllWords)
            XCTAssertEqual(criteria.dataType, ["Branded"])
            XCTAssertEqual(criteria.pageSize, 5)
            return Data(#"{"foods":[{"fdcId":1,"description":"Other pack","gtinUpc":"10856312002792","foodNutrients":[]},{"fdcId":2,"description":"Milk","gtinUpc":"00856312002795","foodNutrients":[]}]}"#.utf8)
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(item?.id, "usda_2")
        XCTAssertEqual(item?.sourceMetadata?.barcode, "00856312002795")
    }

    func testGroupedBarcodeMissRetriesTheScannedSpellingWithRemainingTime() async throws {
        var elapsed = 1.0
        var queries: [String] = []
        var budgets: [TimeInterval] = []
        let item = try await USDAFoodSearchPipeline.barcode("0856312002795", apiKey: "test", includeEquivalentCodes: true, timeout: 6,
                                                            now: { elapsed }) { request, budget in
            queries.append(try Self.criteria(request).query)
            budgets.append(budget)
            elapsed += 2
            if queries.count == 1 {
                return Data(#"{"foods":[{"fdcId":1,"description":"Different item","gtinUpc":"9999999999994","foodNutrients":[]}]}"#.utf8)
            }
            return Data(#"{"foods":[{"fdcId":2,"description":"Milk","gtinUpc":"0856312002795","foodNutrients":[]}]}"#.utf8)
        }
        XCTAssertEqual(queries, ["0856312002795 856312002795 00856312002795", "0856312002795"])
        XCTAssertEqual(budgets, [6, 4])
        XCTAssertEqual(item?.id, "usda_2")
    }

    func testSubsequentBarcodeRoundsAndNonzeroPackagingIndicatorsStayExact() async throws {
        for (code, includeEquivalents) in [("856312002795", false), ("10856312002792", true)] {
            var queries: [String] = []
            let item = try await USDAFoodSearchPipeline.barcode(code, apiKey: "test", includeEquivalentCodes: includeEquivalents, timeout: 6) { request, _ in
                queries.append(try Self.criteria(request).query)
                return Data(#"{"foods":[{"fdcId":1,"description":"Other pack","gtinUpc":"9999999999994","foodNutrients":[]}]}"#.utf8)
            }
            XCTAssertEqual(queries, [code])
            XCTAssertNil(item)
        }
    }

    func testSpecificNonemptySearchMakesOnlyOneRequest() async throws {
        var requests = 0
        let foods = try await USDAFoodSearchPipeline.search(query: "Fairlife milk", apiKey: "test", timeout: 6) { request, timeout in
            requests += 1
            XCTAssertTrue(try Self.criteria(request).requireAllWords)
            XCTAssertLessThanOrEqual(timeout, 6)
            return Data(#"{"foods":[{"fdcId":1,"description":"Milk","brandName":"Fairlife","foodNutrients":[]}]}"#.utf8)
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(foods.count, 1)
    }

    func testEmptySpecificSearchGetsOneBroadAttemptWithRemainingBudget() async throws {
        var elapsed = 10.0
        var attempts: [Bool] = []
        var budgets: [Double] = []
        let foods = try await USDAFoodSearchPipeline.search(query: "100 g banana raw", apiKey: "test", timeout: 6, now: { elapsed }) { request, timeout in
            let strict = try Self.criteria(request).requireAllWords
            attempts.append(strict); budgets.append(timeout)
            elapsed += 2
            return Data((strict ? #"{"foods":[]}"# : #"{"foods":[{"fdcId":2,"description":"Banana, raw","foodNutrients":[]}]}"#).utf8)
        }
        XCTAssertEqual(attempts, [true, false])
        XCTAssertEqual(budgets, [6, 4])
        XCTAssertEqual(foods.map(\.id), ["usda_2"])
    }

    func testRejectedMultiwordQueryRetriesOnlyItsFamilyWithinTheSameBudget() async throws {
        var requests: [String] = []
        let results = try await USDAFoodSearchPipeline.search(query: "Chobani vanilla greek yogurt", apiKey: "test", timeout: 6) { request, _ in
            requests.append(try Self.criteria(request).query)
            if requests.count == 1 { throw USDAFoodSearchPipeline.RequestError.rejectedQuery }
            return Data(#"{"foods":[{"fdcId":1,"description":"Vanilla Greek Yogurt","brandName":"Chobani","foodNutrients":[]}]}"#.utf8)
        }
        XCTAssertEqual(requests, ["Chobani vanilla greek yogurt", "Chobani vanilla"])
        XCTAssertEqual(results.first?.id, "usda_1")
    }

    func testProviderFailureDoesNotTriggerBroadRetry() async {
        var requests = 0
        do {
            _ = try await USDAFoodSearchPipeline.search(query: "milk", apiKey: "test", timeout: 6) { _, _ in
                requests += 1
                throw URLError(.badServerResponse)
            }
            XCTFail("Expected provider failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
        XCTAssertEqual(requests, 1)
    }

    func testExpiredBudgetPreventsSecondRequest() async {
        var elapsed = 10.0
        var requests = 0
        do {
            _ = try await USDAFoodSearchPipeline.search(query: "milk", apiKey: "test", timeout: 6, now: { elapsed }) { _, _ in
                requests += 1; elapsed += 6
                return Data(#"{"foods":[]}"#.utf8)
            }
            XCTFail("Expected exhausted deadline")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(requests, 1)
    }

    func testCancellationAfterEmptyResponsePreventsSecondRequest() async {
        let work = Task { () throws -> Int in
            var requests = 0
            do {
                _ = try await USDAFoodSearchPipeline.search(query: "milk", apiKey: "test", timeout: 6) { _, _ in
                    requests += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    return Data(#"{"foods":[]}"#.utf8)
                }
                XCTFail("Expected cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            return requests
        }
        let requests = try? await work.value
        XCTAssertEqual(requests, 1)
    }

    func testParsingValidJSON() throws {
        let json = """
        {
            "foods": [
                {
                    "fdcId": 1234,
                    "description": "APPLE, RAW, WITH SKIN",
                    "dataType": "Foundation",
                    "publishedDate": "2026-04-01",
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
        XCTAssertEqual(apple.sourceMetadata?.effectiveEvidenceLineage, .analyticalReference)
        XCTAssertNotNil(apple.sourceMetadata?.sourceUpdatedAt)
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
        XCTAssertEqual(banana.sourceMetadata?.effectiveEvidenceLineage, .analyticalReference)
    }

    func testBrandedFoodIsManufacturerLabelLineage() throws {
        let json = """
        {
            "foods": [
                {
                    "fdcId": 7001,
                    "description": "BRANDED CEREAL",
                    "dataType": "Branded",
                    "gtinUpc": "012345678905",
                    "modifiedDate": "2025-12-15",
                    "servingSize": 30,
                    "servingSizeUnit": "g",
                    "foodNutrients": [
                        { "nutrientNumber": "208", "value": 400 },
                        { "nutrientNumber": "203", "value": 10 },
                        { "nutrientNumber": "205", "value": 70 },
                        { "nutrientNumber": "204", "value": 8 }
                    ]
                }
            ]
        }
        """

        let cereal = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(json.utf8)).first)

        XCTAssertEqual(cereal.sourceMetadata?.confidence, .databaseMatch)
        XCTAssertEqual(cereal.sourceMetadata?.effectiveEvidenceLineage, .manufacturerLabel)
        XCTAssertNotNil(cereal.sourceMetadata?.sourceUpdatedAt)
    }
}
