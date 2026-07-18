import XCTest
@testable import MyFitPlateCore

final class FoodTrustCalibrationTelemetryTests: XCTestCase {
    func testContextCarriesTrustEvidenceWithoutFoodIdentityOrNutritionValues() {
        var metadata = FoodSourceMetadata.database(
            .usda,
            sourceName: "USDA",
            sourceID: "private-food-id",
            barcode: "0123456789012"
        )
        metadata.crossVerifiedBy = ["Open Food Facts"]
        let item = food(metadata: metadata)
        let descriptor = FoodSourceClassifier.descriptor(for: metadata)
        let context = FoodTrustCalibrationContext(
            item: item,
            descriptor: descriptor,
            metadata: metadata
        )

        XCTAssertEqual(context.source, "usda")
        XCTAssertEqual(context.evidenceClass, "cross_database_agreement")
        XCTAssertEqual(context.crossVerifiedCount, 1)
        XCTAssertEqual(context.servingEvidence, "comparable")
        XCTAssertEqual(context.sanityProfile, "none")
        XCTAssertEqual(context.sanityFindingCount, 0)

        let parameters = context.analyticsParameters(action: "fix_opened")
        XCTAssertEqual(parameters["action"] as? String, "fix_opened")
        XCTAssertEqual(
            parameters["trust_model_version"] as? String,
            String(FoodTrustEvaluation.modelVersion)
        )
        let encoded = parameters.values.map { String(describing: $0) }.joined(separator: "|")
        XCTAssertFalse(encoded.contains("private-food-id"))
        XCTAssertFalse(encoded.contains("0123456789012"))
        XCTAssertFalse(encoded.contains("Protein Bar"))
        XCTAssertNil(parameters["calories"])
        XCTAssertNil(parameters["protein"])
        XCTAssertNil(parameters["barcode"])
        XCTAssertNil(parameters["food_id"])
    }

    func testSpecialistSourcesRetainTheirActualEvidenceClassAndServingSemantics() {
        let canadaMetadata = FoodSourceMetadata.database(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: "cnf_1",
            evidenceLineage: .governmentCompilation
        )
        let canadaContext = FoodTrustCalibrationContext(
            item: food(metadata: canadaMetadata),
            descriptor: FoodSourceClassifier.descriptor(for: canadaMetadata),
            metadata: canadaMetadata
        )
        XCTAssertEqual(canadaContext.evidenceClass, "government_reference")
        XCTAssertEqual(canadaContext.servingEvidence, "comparable")

        let supplementMetadata = FoodSourceMetadata.database(
            .nihDSLD,
            sourceName: "NIH DSLD",
            sourceID: "dsld_1",
            evidenceLineage: .manufacturerLabel
        )
        var supplement = food(metadata: supplementMetadata)
        supplement.servingWeight = 0
        let supplementContext = FoodTrustCalibrationContext(
            item: supplement,
            descriptor: FoodSourceClassifier.descriptor(for: supplementMetadata),
            metadata: supplementMetadata
        )
        XCTAssertEqual(supplementContext.evidenceClass, "manufacturer_label")
        XCTAssertEqual(supplementContext.servingEvidence, "label_serving")
    }

    func testContextClassifiesEstimateAndWarningProfile() {
        let metadata = FoodSourceMetadata.aiEstimate(
            .aiImage,
            sourceName: "AI image"
        )
        let item = food(
            fats: 3,
            saturatedFat: 8,
            metadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(for: metadata)
        let context = FoodTrustCalibrationContext(
            item: item,
            descriptor: descriptor,
            metadata: metadata
        )

        XCTAssertEqual(context.evidenceClass, "estimate")
        XCTAssertTrue(context.requiresCorrection)
        XCTAssertTrue(context.sanityProfile.contains("saturated_fat_exceeds_total"))
        XCTAssertGreaterThan(context.sanityFindingCount, 0)
    }

    func testCorrectionScopeReportsOnlyCoarseChangedFieldGroups() {
        let original = serving()
        let corrected = ServingSizeOption(
            description: "2 bars",
            servingWeightGrams: 80,
            calories: 280,
            protein: 24,
            carbs: 31,
            fats: 9,
            saturatedFat: 3,
            fiber: 6
        )

        let scope = FoodCorrectionTelemetry.scope(
            originalName: "Protein Bar",
            originalServing: original,
            correctedName: "Chocolate Protein Bar",
            correctedServing: corrected
        )

        XCTAssertEqual(scope, "identity,serving,core_nutrition,detail_nutrition")
        XCTAssertFalse(scope.contains("280"))
        XCTAssertFalse(scope.contains("Chocolate"))
    }

    func testCorrectionScopeIgnoresFormattingOnlyTextAndTinyNumericDrift() {
        let original = serving()
        let corrected = ServingSizeOption(
            description: "  1   bar ",
            servingWeightGrams: 60.00001,
            calories: 210.00001,
            protein: 20,
            carbs: 22,
            fats: 7,
            saturatedFat: 2,
            fiber: 3
        )

        XCTAssertEqual(
            FoodCorrectionTelemetry.scope(
                originalName: "Protein Bar",
                originalServing: original,
                correctedName: " protein   bar ",
                correctedServing: corrected
            ),
            "no_material_change"
        )
    }

    func testOutcomeParametersDescribeResolutionWithoutValues() {
        let metadata = FoodSourceMetadata.aiEstimate(.aiImage, sourceName: "AI image")
        let original = food(fats: 3, saturatedFat: 8, metadata: metadata)
        let descriptor = FoodSourceClassifier.descriptor(for: metadata)
        let context = FoodTrustCalibrationContext(
            item: original,
            descriptor: descriptor,
            metadata: metadata
        )
        let corrected = food(
            fats: 8,
            saturatedFat: 2,
            metadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited
            )
        )

        let parameters = context.analyticsParameters(
            action: "correction_saved",
            correctionScope: "core_nutrition,detail_nutrition",
            resultingItem: corrected
        )

        XCTAssertEqual(parameters["resulting_sanity"] as? String, "clear")
        XCTAssertEqual(parameters["resulting_sanity_profile"] as? String, "none")
        XCTAssertEqual(parameters["resulting_sanity_finding_count"] as? Int, 0)
        XCTAssertEqual(parameters["resulting_review_status"] as? String, "userEdited")
        XCTAssertEqual(parameters["correction_scope"] as? String, "core_nutrition,detail_nutrition")
    }

    private func food(
        fats: Double = 7,
        saturatedFat: Double? = 2,
        metadata: FoodSourceMetadata
    ) -> FoodItem {
        FoodItem(
            id: "private-food-id",
            name: "Protein Bar",
            calories: 210,
            protein: 20,
            carbs: 22,
            fats: fats,
            saturatedFat: saturatedFat,
            fiber: 3,
            servingSize: "1 bar",
            servingWeight: 60,
            sourceMetadata: metadata
        )
    }

    private func serving() -> ServingSizeOption {
        ServingSizeOption(
            description: "1 bar",
            servingWeightGrams: 60,
            calories: 210,
            protein: 20,
            carbs: 22,
            fats: 7,
            saturatedFat: 2,
            fiber: 3
        )
    }
}
