import Foundation
import XCTest
@testable import MyFitPlateCore

private class SearchOutcomeURLProtocol: URLProtocol {
    static var response: Result<(Int, Data), Error> = .failure(URLError(.timedOut))
    static var requests: [URLRequest] = []
    private static let requestLock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestLock.withLock { Self.requests.append(request) }
        switch Self.response {
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .success(let (status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class FoodProviderSearchOutcomeTests: XCTestCase {
    func testRetailScanKeepsTheCatalogBrandAndPrintedVolumeWithNutritionPer100Grams() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchOutcomeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cloud = DIContainer.shared.cloudFunctionService
        DIContainer.shared.cloudFunctionService = MockCloudFunctionService()
        defer { DIContainer.shared.cloudFunctionService = cloud }
        let label = """
        {"status":0,"foods":[{"fdcId":42,"description":"Chocolate Milk","brandName":"Fairlife","dataType":"Branded",
        "gtinUpc":"00856312002795","servingSize":240,"servingSizeUnit":"MLT","foodNutrients":[{"nutrientNumber":"208","value":50}]}]}
        """
        SearchOutcomeURLProtocol.requests = []
        SearchOutcomeURLProtocol.response = .success((200, Data(label.utf8)))
        let scanner = BarcodeFoodLookupService(usdaService: USDAFoodAPIService(apiKey: "test", session: session),
                                              openFoodFactsService: OpenFoodFactsAPIService(session: session), correctionStore: nil)
        let lookup = await scanner.lookup("0856312002795")
        let result = try XCTUnwrap(lookup)
        XCTAssertEqual(result.source, "usda_barcode")
        XCTAssertEqual(result.matchedBarcode, "00856312002795")
        XCTAssertEqual(result.item.sourceMetadata?.barcode, "0856312002795")
        XCTAssertEqual(result.item.sourceMetadata?.brandName, "Fairlife")
        XCTAssertEqual(result.item.sourceMetadata?.labeledServing, "240 ml")
        XCTAssertEqual(result.item.servingSize, "100 g")
        XCTAssertEqual(result.item.calories, 50)
        XCTAssertEqual(SearchOutcomeURLProtocol.requests.filter { $0.url?.path == "/fdc/v1/foods/search" }.count, 1)
    }

    func testUSDATextRequestIncludesBrandedWithoutAnotherNetworkRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchOutcomeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        SearchOutcomeURLProtocol.requests = []
        SearchOutcomeURLProtocol.response = .success((200, Data(#"{"foods":[{"fdcId":1,"description":"Yogurt","brandName":"Fage","foodNutrients":[]}]}"#.utf8)))
        let result = await USDAFoodAPIService(apiKey: "synthetic-test-key", session: session).searchFoodsResult(query: "yogurt")
        XCTAssertEqual(try result.get().first?.sourceMetadata?.brandName, "Fage")
        XCTAssertEqual(SearchOutcomeURLProtocol.requests.count, 1)
        let request = try XCTUnwrap(SearchOutcomeURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/fdc/v1/foods/search")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testHTTPNetworkAndDecodeFailuresCannotBecomeSuccessfulEmptyUSDAOrOFFSearches() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchOutcomeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let usda = USDAFoodAPIService(apiKey: "synthetic-test-key", session: session)
        let off = OpenFoodFactsAPIService(session: session)
        let failures: [Result<(Int, Data), Error>] = [
            .failure(URLError(.notConnectedToInternet)), .success((503, Data("{}".utf8))),
            .success((200, Data("not-json".utf8))), .success((200, Data("{}".utf8)))
        ]
        for failure in failures {
            SearchOutcomeURLProtocol.response = failure
            if case .success = await usda.searchFoodsResult(query: "rice") { XCTFail("USDA rejected request must remain a failure") }
            if case .success = await off.searchFoodsResult(query: "rice") { XCTFail("OFF rejected request must remain a failure") }
        }
        SearchOutcomeURLProtocol.response = .success((200, Data(#"{"foods":[]}"#.utf8)))
        let emptyUSDA = await usda.searchFoodsResult(query: "rice")
        XCTAssertEqual(try? emptyUSDA.get().count, 0)
        SearchOutcomeURLProtocol.response = .success((200, Data(#"{"products":[]}"#.utf8)))
        let emptyOFF = await off.searchFoodsResult(query: "rice")
        XCTAssertEqual(try? emptyOFF.get().count, 0)
    }

    func testRejectedReferenceAndSupplementCloudSearchesRemainFailuresButEmptySuccessIsValid() async {
        let previousFlags = DIContainer.shared.featureFlagService
        DIContainer.shared.featureFlagService = FeatureFlagService(localOverrides: [.healthCanadaFoodSearch: true, .nihSupplementLabels: true])
        defer { DIContainer.shared.featureFlagService = previousFlags }
        let cloud = MockCloudFunctionService()
        let canada = HealthCanadaFoodAPIService(cloudFunctionService: cloud)
        let supplements = NIHDietarySupplementAPIService(cloudFunctionService: cloud)
        cloud.mockCallFunctionResult = .failure(URLError(.timedOut))
        if case .success = await canada.searchFoodsResult(query: "rice") { XCTFail("Reference outage is not no matches") }
        if case .success = await supplements.searchSupplementsResult(query: "vitamin") { XCTFail("Supplement outage is not no matches") }
        cloud.mockCallFunctionResult = .success(["unexpected": "payload"])
        if case .success = await canada.searchFoodsResult(query: "rice") { XCTFail("Reference decode rejection must remain failure") }
        if case .success = await supplements.searchSupplementsResult(query: "vitamin") { XCTFail("Supplement decode rejection must remain failure") }
        cloud.mockCallFunctionResult = .success([])
        let emptyCanada = await canada.searchFoodsResult(query: "rice")
        let emptySupplements = await supplements.searchSupplementsResult(query: "vitamin")
        XCTAssertEqual(try? emptyCanada.get().count, 0)
        XCTAssertEqual(try? emptySupplements.get().count, 0)
    }
}
