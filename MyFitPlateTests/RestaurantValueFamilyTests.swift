import MyFitPlateCore
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class RestaurantValueFamilyTests: XCTestCase {
    func testManualAYCEDraftBuildsLocallyPricedUserEntry() throws {
        let draft = AYCEPlateDraft(
            id: "manual-test",
            name: "  Salmon hand roll  ",
            unit: "roll",
            calories: "210",
            protein: "12",
            carbs: "24",
            fats: "7",
            restaurantPrice: "$8.50",
            homeCost: "2.75"
        )

        let item = try XCTUnwrap(
            draft.reviewedItem(cuisine: .sushi, isAIEstimated: false)
        )

        XCTAssertEqual(item.name, "Salmon hand roll")
        XCTAssertEqual(item.restaurantPrice, 8.50, accuracy: 0.001)
        XCTAssertEqual(item.homeCost, 2.75, accuracy: 0.001)
        XCTAssertFalse(item.isAIEstimated)
        XCTAssertTrue(item.isLocallyPriced)
    }

    func testAYCEDraftRejectsInvalidManualValues() {
        let blankName = AYCEPlateDraft(
            name: "   ",
            calories: "200",
            protein: "10",
            carbs: "20",
            fats: "8",
            restaurantPrice: "9",
            homeCost: "3"
        )
        let negativeNutrition = AYCEPlateDraft(
            name: "Rice bowl",
            calories: "-1",
            protein: "10",
            carbs: "20",
            fats: "8",
            restaurantPrice: "9",
            homeCost: "3"
        )
        let nonfinitePrice = AYCEPlateDraft(
            name: "Rice bowl",
            calories: "200",
            protein: "10",
            carbs: "20",
            fats: "8",
            restaurantPrice: "nan",
            homeCost: "3"
        )

        XCTAssertNil(blankName.reviewedItem(cuisine: .sushi, isAIEstimated: false))
        XCTAssertNil(negativeNutrition.reviewedItem(cuisine: .sushi, isAIEstimated: false))
        XCTAssertNil(nonfinitePrice.reviewedItem(cuisine: .sushi, isAIEstimated: false))
    }

    func testAYCEDraftPreservesGroupedCaloriesAndDecimalCommaPrices() throws {
        let draft = AYCEPlateDraft(
            name: "Shared platter",
            calories: "1,000",
            protein: "42",
            carbs: "110",
            fats: "38",
            restaurantPrice: "18,50",
            homeCost: "6,25"
        )

        let item = try XCTUnwrap(
            draft.reviewedItem(cuisine: .sushi, isAIEstimated: false)
        )

        XCTAssertEqual(item.calories, 1_000)
        XCTAssertEqual(item.restaurantPrice, 18.50, accuracy: 0.001)
        XCTAssertEqual(item.homeCost, 6.25, accuracy: 0.001)
    }

    func testLatestMenuScanOwnsAsyncResult() async throws {
        let analyzer = MenuAnalyzerStub()
        let viewModel = RestaurantValueRadarViewModel(
            imageModel: analyzer,
            selectedCity: AYCECityIndex.national
        )

        viewModel.analyzeMenuImage(UIImage())
        viewModel.analyzeMenuImage(UIImage())
        XCTAssertEqual(analyzer.pendingCount, 2)

        analyzer.complete(
            request: 0,
            with: .success([scannedItem(id: "stale", name: "Stale dish", price: 10)])
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.isAnalyzing)
        XCTAssertTrue(viewModel.items.isEmpty)

        analyzer.complete(
            request: 1,
            with: .success([scannedItem(id: "latest", name: "Latest dish", price: 12)])
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(viewModel.items.map(\.id), ["latest"])
        XCTAssertEqual(viewModel.items.first?.adjustedPrice, 12)
        XCTAssertTrue(viewModel.items.first?.canLog == true)
    }

    private func scannedItem(id: String, name: String, price: Double) -> ScannedMenuValueItem {
        ScannedMenuValueItem(
            food: FoodItem(
                id: id,
                name: name,
                calories: 420,
                protein: 36,
                carbs: 30,
                fats: 16,
                servingSize: "1 entree"
            ),
            listedPrice: price
        )
    }
}

private final class MenuAnalyzerStub: RestaurantMenuAnalyzing {
    private var completions: [
        (Result<[ScannedMenuValueItem], Error>) -> Void
    ] = []

    var pendingCount: Int { completions.count }

    func estimateMenuItemsWithListedPrices(
        image: UIImage,
        completion: @escaping (Result<[ScannedMenuValueItem], Error>) -> Void
    ) {
        completions.append(completion)
    }

    func complete(
        request: Int,
        with result: Result<[ScannedMenuValueItem], Error>
    ) {
        completions[request](result)
    }
}
