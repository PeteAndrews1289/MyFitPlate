import XCTest
@testable import MyFitPlateCore

final class CommunityBarcodeRulesTests: XCTestCase {

    private let barcode = "0123456789012"

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
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(cleanFood(), barcode: "0123456789012", flagEnabled: true).reason,
            "eligible"
        )
    }

    func testFlagOffBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(), barcode: "0123456789012", flagEnabled: false
        ))
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(cleanFood(), barcode: "0123456789012", flagEnabled: false).reason,
            "feature_flag_disabled"
        )
    }

    func testEmptyBarcodeBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(), barcode: "  ", flagEnabled: true
        ))
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(cleanFood(), barcode: "  ", flagEnabled: true).reason,
            "empty_barcode"
        )
    }

    func testNonStandardBarcodeBlocksGlobalContribution() {
        let decision = CommunityBarcodeRules.contributionDecision(
            cleanFood(),
            barcode: "12345",
            flagEnabled: true
        )
        XCTAssertFalse(decision.isEligible)
        XCTAssertEqual(decision.reason, "invalid_barcode")
    }

    func testInvalidGTINCheckDigitBlocksGlobalContribution() {
        let decision = CommunityBarcodeRules.contributionDecision(
            cleanFood(),
            barcode: "012345678901",
            flagEnabled: true
        )
        XCTAssertFalse(decision.isEligible)
        XCTAssertEqual(decision.reason, "invalid_barcode")
    }

    func testSanitySuspiciousFoodNeverPools() {
        // Macros with zero calories - the sanity checker flags it, so it must not spread.
        var bad = cleanFood()
        bad.calories = 0
        XCTAssertTrue(FoodDataSanity.isSuspicious(bad))
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            bad, barcode: "0123456789012", flagEnabled: true
        ))
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(bad, barcode: "0123456789012", flagEnabled: true).reason,
            "suspicious_food"
        )
    }

    func testOverlongOrEmptyNameBlocksContribution() {
        XCTAssertFalse(CommunityBarcodeRules.isEligibleForContribution(
            cleanFood(name: String(repeating: "x", count: 141)),
            barcode: "0123456789012",
            flagEnabled: true
        ))
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(
                cleanFood(name: String(repeating: "x", count: 141)),
                barcode: "0123456789012",
                flagEnabled: true
            ).reason,
            "invalid_name"
        )
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
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(absurd, barcode: "0123456789012", flagEnabled: true).reason,
            "calories_out_of_range"
        )
        absurd.calories = 210
        absurd.protein = 1_200
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(absurd, barcode: "0123456789012", flagEnabled: true).reason,
            "macros_out_of_range"
        )
    }

    func testMissingServingWeightAndInvalidFiberBlockContribution() {
        var missingWeight = cleanFood()
        missingWeight.servingWeight = 1
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(
                missingWeight,
                barcode: "0123456789012",
                flagEnabled: true
            ).reason,
            "serving_weight_missing"
        )

        var invalidFiber = cleanFood()
        invalidFiber.fiber = .nan
        XCTAssertEqual(
            CommunityBarcodeRules.contributionDecision(
                invalidFiber,
                barcode: "0123456789012",
                flagEnabled: true
            ).reason,
            "fiber_out_of_range"
        )
    }

    func testInformationalNutritionFindingDoesNotEnterCommunityPool() {
        var reviewFood = cleanFood()
        reviewFood.calories = 0
        reviewFood.protein = 0
        reviewFood.carbs = 20
        reviewFood.fats = 0

        let decision = CommunityBarcodeRules.contributionDecision(
            reviewFood,
            barcode: "0123456789012",
            flagEnabled: true
        )
        XCTAssertFalse(decision.isEligible)
        XCTAssertEqual(decision.reason, "nutrition_needs_review")
    }

    // MARK: - Server aggregate gate

    func testValidThreeContributorAggregateIsEligible() {
        let decision = CommunityBarcodeRules.aggregateDecision(
            aggregateEvidence(),
            expectedBarcode: barcode
        )

        XCTAssertTrue(decision.isEligible)
        XCTAssertEqual(decision.reason, "eligible_aggregate")
    }

    func testAggregateRequiresKnownModelStatusAndExactGTIN() {
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(modelVersion: "unknown"),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_model"
        )
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(status: "quarantined"),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_model"
        )
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(barcode: "00012345600012"),
                expectedBarcode: barcode
            ).reason,
            "aggregate_barcode_mismatch"
        )
    }

    func testAggregateRejectsSmallOrInconsistentContributorCounts() {
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(contributorCount: 2, agreementCount: 2, conflictCount: 0, agreementRatio: 1),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_counts"
        )
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(contributorCount: 4, agreementCount: 3, conflictCount: 0, agreementRatio: 0.75),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_counts"
        )
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(contributorCount: 251, agreementCount: 251, conflictCount: 0, agreementRatio: 1),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_counts"
        )
    }

    func testAggregateRejectsLowOrMathematicallyInconsistentRatio() {
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(contributorCount: 5, agreementCount: 3, conflictCount: 2, agreementRatio: 0.6),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_ratio"
        )
        XCTAssertEqual(
            CommunityBarcodeRules.aggregateDecision(
                aggregateEvidence(contributorCount: 4, agreementCount: 3, conflictCount: 1, agreementRatio: 0.9),
                expectedBarcode: barcode
            ).reason,
            "invalid_aggregate_ratio"
        )
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
        XCTAssertEqual(item.sourceMetadata?.confidence, .needsReview)
        XCTAssertEqual(item.sourceMetadata?.reviewStatus, .unreviewed)
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
        XCTAssertEqual(descriptor.confidence, "Community Consensus")
    }

    private func aggregateEvidence(
        schemaVersion: Int = 1,
        modelVersion: String = CommunityBarcodeRules.aggregateModelVersion,
        status: String = "published",
        barcode: String = "0123456789012",
        contributorCount: Int = 3,
        agreementCount: Int = 3,
        conflictCount: Int = 0,
        agreementRatio: Double = 1
    ) -> CommunityBarcodeAggregateEvidence {
        CommunityBarcodeAggregateEvidence(
            schemaVersion: schemaVersion,
            modelVersion: modelVersion,
            status: status,
            barcode: barcode,
            contributorCount: contributorCount,
            agreementCount: agreementCount,
            conflictCount: conflictCount,
            agreementRatio: agreementRatio
        )
    }
}
