import XCTest
@testable import MyFitPlateCore

final class FoodSearchRankingTests: XCTestCase {
    func testTrustedLocalMatchesPreferSavedUserEditedFoods() {
        let saved = FoodItem(
            id: "saved",
            name: "Greek Yogurt Bowl",
            calories: 320,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
        let recent = FoodItem(
            id: "recent",
            name: "Plain Greek Yogurt",
            calories: 160,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recent,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "Recent"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "greek yogurt",
            savedFoods: [saved],
            recentFoods: [recent]
        )

        XCTAssertEqual(matches.map(\.id), ["saved", "recent"])
    }

    func testTrustedLocalMatchesDeduplicateSavedAndRecentFoods() {
        let food = FoodItem(id: "same", name: "Protein Bar", calories: 210)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "protein",
            savedFoods: [food],
            recentFoods: [food]
        )

        XCTAssertEqual(matches.map(\.id), ["same"])
    }

    func testTrustedLocalMatchesFindBarcodeCorrectionsByDigits() {
        let food = FoodItem(
            id: "barcode-food",
            name: "Saved Cereal",
            calories: 180,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "00 123456"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "123456",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertEqual(matches.first?.id, "barcode-food")
    }

    func testTrustedLocalMatchesIgnoreUnrelatedFoods() {
        let food = FoodItem(id: "banana", name: "Banana", calories: 105)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "chicken",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertTrue(matches.isEmpty)
    }
}
