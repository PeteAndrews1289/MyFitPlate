import XCTest
@testable import MyFitPlateCore

final class FoodSourceAgreementTests: XCTestCase {

    private func food(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        servingWeight: Double
    ) -> FoodItem {
        FoodItem(
            name: "Test",
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            servingWeight: servingWeight
        )
    }

    // MARK: - agrees(_:_:)

    func testIdenticalNutritionAtDifferentServingSizesAgrees() {
        // Same product: one database reports per 100g, the other a 30g portion.
        let per100 = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
        let per30 = food(calories: 114, protein: 2.4, carbs: 21, fats: 1.8, servingWeight: 30)
        XCTAssertTrue(FoodSourceAgreement.agrees(per100, per30))
    }

    func testSmallRoundingDifferencesStillAgree() {
        let a = food(calories: 250, protein: 10, carbs: 30, fats: 9, servingWeight: 100)
        let b = food(calories: 262, protein: 11, carbs: 31.5, fats: 9.8, servingWeight: 100)
        XCTAssertTrue(FoodSourceAgreement.agrees(a, b))
    }

    func testCalorieDisagreementFails() {
        let a = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let b = food(calories: 320, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        XCTAssertFalse(FoodSourceAgreement.agrees(a, b))
    }

    func testSingleMacroDisagreementFails() {
        let a = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let b = food(calories: 200, protein: 22, carbs: 20, fats: 8, servingWeight: 100)
        XCTAssertFalse(FoodSourceAgreement.agrees(a, b))
    }

    func testPlaceholderServingWeightNeverAgrees() {
        // servingWeight 1.0 is the unknown-weight placeholder; per-100g scaling
        // would fabricate absurd values, so comparison must refuse.
        let known = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let unknown = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 1)
        XCTAssertFalse(FoodSourceAgreement.agrees(known, unknown))
    }

    func testZeroMacroFoodsAgreeWithinAbsoluteTolerance() {
        // Diet soda from two databases: zeros everywhere.
        let a = food(calories: 0, protein: 0, carbs: 0, fats: 0, servingWeight: 355)
        let b = food(calories: 1, protein: 0, carbs: 0.3, fats: 0, servingWeight: 355)
        XCTAssertTrue(FoodSourceAgreement.agrees(a, b))
    }

    func testAgreementEvidenceSurvivesPureServingRescale() {
        let per100 = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
        let per30 = food(calories: 114, protein: 2.4, carbs: 21, fats: 1.8, servingWeight: 30)
        XCTAssertTrue(FoodSourceAgreement.preservesAgreementEvidence(per30, per100))
    }

    func testAgreementEvidenceDoesNotSurviveBroadToleranceNutritionEdit() {
        let original = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let edited = food(calories: 220, protein: 11, carbs: 22, fats: 8.5, servingWeight: 100)

        XCTAssertTrue(FoodSourceAgreement.agrees(original, edited))
        XCTAssertFalse(FoodSourceAgreement.preservesAgreementEvidence(edited, original))
    }

    func testNonFiniteOrNegativeNutritionNeverAgrees() {
        let valid = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let nonFinite = food(calories: .nan, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
        let negative = food(calories: 200, protein: -10, carbs: 20, fats: 8, servingWeight: 100)

        XCTAssertFalse(FoodSourceAgreement.agrees(valid, nonFinite))
        XCTAssertFalse(FoodSourceAgreement.agrees(nonFinite, nonFinite))
        XCTAssertFalse(FoodSourceAgreement.agrees(valid, negative))
    }

    // MARK: - agreeingSourceNames

    func testAgreeingSourceNamesFiltersMissesAndDisagreements() {
        let primary = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
        let agreeing = food(calories: 375, protein: 8.2, carbs: 69, fats: 6.1, servingWeight: 100)
        let disagreeing = food(calories: 150, protein: 2, carbs: 30, fats: 1, servingWeight: 100)

        let names = FoodSourceAgreement.agreeingSourceNames(
            primary: primary,
            candidates: [
                ("USDA", agreeing),
                ("Open Food Facts", disagreeing),
                ("Missing", nil)
            ]
        )
        XCTAssertEqual(names, ["USDA"])
    }

    // MARK: - Metadata plumbing

    func testWithCrossVerificationAttachesSources() {
        let item = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", barcode: "0123456789")
        let verified = item.withCrossVerification(["USDA"])
        XCTAssertEqual(verified.sourceMetadata?.crossVerifiedBy, ["USDA"])
        XCTAssertEqual(verified.sourceMetadata?.validatedCrossVerificationEvidence.count, 1)
        XCTAssertEqual(
            verified.sourceMetadata?.validatedCrossVerificationEvidence.first?.lineage,
            .manufacturerLabel
        )
    }

    func testAgreeingEvidencePreservesCandidateLineageAndDates() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let primary = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret")
        var candidateMetadata = FoodSourceMetadata.database(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_10",
            evidenceLineage: .manufacturerLabel,
            sourceUpdatedAt: updatedAt
        )
        candidateMetadata.confidence = .databaseMatch
        let candidate = food(calories: 375, protein: 8.2, carbs: 69, fats: 6.1, servingWeight: 100)
            .withSourceMetadata(candidateMetadata)

        let evidence = FoodSourceAgreement.agreeingEvidence(
            primary: primary,
            candidates: [("USDA", candidate)]
        )

        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence.first?.sourceName, "USDA")
        XCTAssertEqual(evidence.first?.lineage, .manufacturerLabel)
        XCTAssertEqual(evidence.first?.sourceUpdatedAt, updatedAt)
    }

    func testStructuredEvidenceRemainsValidWithoutLegacyNameArray() {
        var metadata = FoodSourceMetadata.database(
            .fatSecret,
            sourceName: "FatSecret",
            sourceID: "fatsecret_10"
        )
        metadata.crossVerificationEvidence = [
            FoodVerificationEvidence(
                sourceName: "USDA",
                sourceType: .usda,
                lineage: .manufacturerLabel,
                sourceID: "usda_10"
            )
        ]

        XCTAssertEqual(metadata.validatedCrossVerificationEvidence.map(\.sourceName), ["USDA"])
        XCTAssertTrue(metadata.hasCrossDatabaseAgreement)
    }

    func testCrossVerificationRejectsSelfReferencesDuplicatesAndUnknownSources() {
        let item = food(calories: 380, protein: 8, carbs: 70, fats: 6, servingWeight: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret")

        let verified = item.withCrossVerification([
            " FatSecret ", "USDA FoodData Central", "usda", "", "Some Blog",
            "Not USDA", "Open_Food_Facts"
        ])

        XCTAssertEqual(verified.sourceMetadata?.crossVerifiedBy, ["USDA", "Open Food Facts"])
        XCTAssertEqual(verified.sourceMetadata?.validatedCrossVerifiedBy, ["USDA", "Open Food Facts"])
    }

    func testCustomFoodCannotClaimIndependentCrossVerification() {
        var metadata = FoodSourceMetadata.userEntered(sourceName: "My Foods")
        metadata.sourceType = .custom
        metadata.crossVerifiedBy = ["USDA"]

        XCTAssertTrue(metadata.validatedCrossVerifiedBy.isEmpty)

        let item = food(calories: 200, protein: 10, carbs: 20, fats: 8, servingWeight: 100)
            .withSourceMetadata(metadata)
            .withCrossVerification(["USDA"])
        XCTAssertNil(item.sourceMetadata?.crossVerifiedBy)
    }

    func testWithCrossVerificationIsNoOpWhenEmptyOrNoMetadata() {
        let bare = food(calories: 100, protein: 5, carbs: 10, fats: 3, servingWeight: 100)
        XCTAssertNil(bare.withCrossVerification(["USDA"]).sourceMetadata)

        let sourced = bare.withDatabaseSource(.fatSecret, sourceName: "FatSecret")
        XCTAssertNil(sourced.withCrossVerification([]).sourceMetadata?.crossVerifiedBy)
    }

    func testMetadataCodableRoundTripPreservesCrossVerification() throws {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA", "Open Food Facts"]

        let decoded = try JSONDecoder().decode(
            FoodSourceMetadata.self,
            from: JSONEncoder().encode(metadata)
        )
        XCTAssertEqual(decoded.crossVerifiedBy, ["USDA", "Open Food Facts"])
        XCTAssertEqual(decoded.sourceObservedAt, metadata.sourceObservedAt)
    }

    func testLegacyMetadataWithoutFieldDecodes() throws {
        let legacyJSON = """
        {"sourceType":"fatSecret","confidence":"databaseMatch","reviewStatus":"notRequired"}
        """
        let decoded = try JSONDecoder().decode(FoodSourceMetadata.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.crossVerifiedBy)
    }

    // MARK: - Descriptor surfacing

    func testDescriptorShowsCrossVerifiedConfidenceWithoutRepeatingEvidenceInDetail() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]

        let descriptor = FoodSourceClassifier.descriptor(for: metadata)
        XCTAssertEqual(descriptor.confidence, "Cross-Verified")
        XCTAssertEqual(descriptor.detail, "Matched from a packaged-food database.")
    }

    func testUserEditedBeatsCrossVerifiedInConfidenceText() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        metadata.reviewStatus = .userEdited

        let descriptor = FoodSourceClassifier.descriptor(for: metadata)
        XCTAssertEqual(descriptor.confidence, "Edited by You")
    }
}
