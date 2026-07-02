import XCTest
@testable import MyFitPlateCore

final class CommunityBarcodeRulesTests: XCTestCase {

    private func cleanFood(name: String = "Protein Bar") -> FoodItem {
        FoodItem(
            name: name,
            calories: 210,
            protein: 20,
            carbs: 22,
            fats: 7,
            servingSize: "1 bar",
            servingWeight: 60
        )
    }

    // MARK: - Contribution gate

    func testEligibleWhenFlagOnAndDataClean() {
        XCTAssertTrue(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(), barcode: "0123456789012", flagEnabled: true
        ))
    }

    func testFlagOffBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(), barcode: "0123456789012", flagEnabled: false
        ))
    }

    func testEmptyBarcodeBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(), barcode: "  ", flagEnabled: true
        ))
    }

    func testSanitySuspiciousFoodNeverPools() {
        // Macros with zero calories - the sanity checker flags it, so it must not spread.
        var bad = cleanFood()
        bad.calories = 0
        XCTAssertTrue(FoodDataSanity.isSuspicious(bad))
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            bad, barcode: "0123456789012", flagEnabled: true
        ))
    }

    func testOverlongOrEmptyNameBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(name: String(repeating: "x", count: 141)),
            barcode: "0123456789012",
            flagEnabled: true
        ))
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(name: "   "), barcode: "0123456789012", flagEnabled: true
        ))
    }

    func testOutOfRangeNutritionBlocksContribution() {
        var absurd = cleanFood()
        absurd.calories = 6000
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            absurd, barcode: "0123456789012", flagEnabled: true
        ))
    }

    // MARK: - Community item builder

    func testCommunityFoodItemCarriesCommunityIdentity() {
        let item = CommunityBarcodeRules.communityFoodItem(
            name: "Oat Milk",
            calories: 120,
            protein: 3,
            carbs: 16,
            fats: 5,
            fiber: 2,
            servingSize: "1 cup",
            servingWeight: 240,
            barcode: "012-345 6789012"
        )

        XCTAssertEqual(item.id, "community_0123456789012")
        XCTAssertEqual(item.sourceMetadata?.barcode, "0123456789012")
        XCTAssertTrue(CommunityBarcodeRules.isCommunityMatch(item.sourceMetadata))
    }

    func testCommunityFoodItemDefaultsPlaceholderServing() {
        let item = CommunityBarcodeRules.communityFoodItem(
            name: "Mystery", calories: 100, protein: 1, carbs: 2, fats: 3,
            fiber: nil, servingSize: "", servingWeight: 0, barcode: "111"
        )
        XCTAssertEqual(item.servingSize, "1 serving")
        XCTAssertEqual(item.servingWeight, 1.0)
    }

    func testCommunityDescriptorReadsAsCommunityMatch() {
        let item = CommunityBarcodeRules.communityFoodItem(
            name: "Oat Milk", calories: 120, protein: 3, carbs: 16, fats: 5,
            fiber: nil, servingSize: "1 cup", servingWeight: 240, barcode: "0123456789012"
        )
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)
        XCTAssertEqual(descriptor.sourceKey, "community_barcode")
        XCTAssertEqual(descriptor.title, "Community Match")
        XCTAssertEqual(descriptor.confidence, "Community Verified")
    }
}
