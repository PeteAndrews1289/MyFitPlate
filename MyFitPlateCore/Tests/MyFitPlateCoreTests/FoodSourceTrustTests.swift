import XCTest
@testable import MyFitPlateCore

final class FoodSourceTrustTests: XCTestCase {
    func testClassifiesBarcodeSources() {
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "usda_barcode", foodID: "usda_123").title, "USDA")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "open_food_facts_barcode", foodID: "off_123").title, "Open Food Facts")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "barcode_result", foodID: "12345").title, "Food Database")
    }

    func testClassifiesEstimatedSourcesAsNeedsReview() {
        let descriptor = FoodSourceClassifier.descriptor(for: "ai_menu")

        XCTAssertEqual(descriptor.title, "AI Estimate")
        XCTAssertEqual(descriptor.confidence, "Needs Review")
        XCTAssertTrue(descriptor.isEstimated)
    }

    func testFoodIDOnlyClassifierIgnoresCustomIDs() {
        XCTAssertEqual(FoodSourceClassifier.descriptor(forFoodID: "usda_abc")?.sourceKey, "usda")
        XCTAssertEqual(FoodSourceClassifier.descriptor(forFoodID: "off_abc")?.sourceKey, "open_food_facts")
        XCTAssertEqual(FoodSourceClassifier.descriptor(forFoodID: "12345")?.sourceKey, "fatsecret")
        XCTAssertNil(FoodSourceClassifier.descriptor(forFoodID: UUID().uuidString))
    }

    // The string-based fallback branches drive the trust badge whenever an entry carries no
    // structured metadata (everything logged before 2.2, plus quick paths that skip it).
    func testStringFallbackClassifiesUserHistorySources() {
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "quick_log").sourceKey, "recent")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "recent_foods").sourceKey, "recent")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "recipe_builder").sourceKey, "planned")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "meal_plan_generated").sourceKey, "planned")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "manual_entry").sourceKey, "manual")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "custom_food").sourceKey, "manual")
    }

    func testStringFallbackClassifiesDatabaseSourcesWithoutIDs() {
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "usda_search").sourceKey, "usda")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "open_food_facts").sourceKey, "open_food_facts")
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: "fatsecret_search").sourceKey, "fatsecret")

        let usdaByID = FoodSourceClassifier.descriptor(for: "search", foodID: "usda_999")
        XCTAssertEqual(usdaByID.sourceKey, "usda")
        let offByID = FoodSourceClassifier.descriptor(for: "search", foodID: "off_999")
        XCTAssertEqual(offByID.sourceKey, "open_food_facts")
    }

    func testStringFallbackClassifiesAllAIShapes() {
        for source in ["image_scan", "menu_scan", "pantry_vision"] {
            let descriptor = FoodSourceClassifier.descriptor(for: source)
            XCTAssertEqual(descriptor.sourceKey, "ai_estimate", "\(source) should read as an AI estimate")
            XCTAssertTrue(descriptor.isEstimated)
        }
    }

    func testUnknownSourceFallsBackToNeutralReviewDescriptor() {
        let descriptor = FoodSourceClassifier.descriptor(for: "some_future_source", foodID: UUID().uuidString)
        XCTAssertEqual(descriptor.sourceKey, "unknown")
        XCTAssertEqual(descriptor.confidence, "Review")
        XCTAssertFalse(descriptor.isEstimated)
    }

    func testMetadataDescriptorPrefersStructuredSource() {
        let metadata = FoodSourceMetadata.database(
            .openFoodFacts,
            sourceName: "Open Food Facts",
            sourceID: "off_123",
            barcode: "123"
        )

        let descriptor = FoodSourceClassifier.descriptor(
            for: "barcode_result",
            foodID: "not-a-database-id",
            metadata: metadata
        )

        XCTAssertEqual(descriptor.sourceKey, "open_food_facts")
        XCTAssertEqual(descriptor.title, "Open Food Facts")
        XCTAssertEqual(descriptor.confidence, "Database Match")
    }

    func testAIMetadataReflectsReviewState() {
        let unreviewedItem = FoodItem(name: "Chicken bowl")
            .withAIEstimateSource(.aiImage, sourceName: "Maia Vision")

        XCTAssertEqual(unreviewedItem.sourceMetadata?.reviewStatus, .unreviewed)
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: unreviewedItem.sourceMetadata!).confidence, "Needs Review")

        let editedItem = unreviewedItem.markedUserEdited(sourceType: .aiImage)

        XCTAssertEqual(editedItem.sourceMetadata?.reviewStatus, .userEdited)
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: editedItem.sourceMetadata!).confidence, "Edited by You")
    }

    func testEditedAIEstimateStoresCorrectionSnapshot() {
        let original = FoodItem(
            name: "Pasta",
            calories: 300,
            protein: 10,
            carbs: 40,
            fats: 8,
            servingSize: "1 bowl",
            servingWeight: 0
        ).withAIEstimateSource(.aiImage, sourceName: "Maia Vision")

        let corrected = FoodItem(
            id: original.id,
            name: "Pasta",
            calories: 520,
            protein: 18,
            carbs: 70,
            fats: 18,
            servingSize: "1 large bowl",
            servingWeight: 0,
            sourceMetadata: original.sourceMetadata
        ).markedUserEdited(sourceType: .aiImage, originalItem: original)

        XCTAssertEqual(corrected.sourceMetadata?.originalEstimate?.calories, 300)
        XCTAssertEqual(corrected.sourceMetadata?.userCorrection?.calories, 520)
        XCTAssertEqual(corrected.sourceMetadata?.userCorrection?.servingSize, "1 large bowl")
    }

    func testFoodSourceMetadataCodableRoundTrip() throws {
        let original = FoodItem(
            id: "food-1",
            name: "Greek Yogurt",
            sourceMetadata: .database(
                .fatSecret,
                sourceName: "FatSecret",
                sourceID: "123",
                barcode: "000123"
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FoodItem.self, from: data)

        XCTAssertEqual(decoded.sourceMetadata?.sourceType, .fatSecret)
        XCTAssertEqual(decoded.sourceMetadata?.barcode, "000123")
        XCTAssertEqual(decoded.sourceMetadata?.reviewStatus, .notRequired)
    }

    func testSavedCustomFoodPreservesBarcodeAndCorrectionSnapshot() {
        let original = FoodItem(
            id: "fatsecret-1",
            name: "Protein Bar",
            calories: 220,
            protein: 18,
            carbs: 22,
            fats: 8,
            servingSize: "1 bar",
            servingWeight: 60
        ).withDatabaseSource(
            .fatSecret,
            sourceName: "FatSecret",
            sourceID: "fatsecret-1",
            barcode: " 0 12345 "
        )

        let corrected = FoodItem(
            id: "custom-1",
            name: "Protein Bar",
            calories: 250,
            protein: 20,
            carbs: 24,
            fats: 9,
            servingSize: "1 package",
            servingWeight: 65,
            sourceMetadata: original.sourceMetadata
        ).savedAsCustomFood(originalItem: original)

        XCTAssertEqual(corrected.sourceMetadata?.sourceType, .custom)
        XCTAssertEqual(corrected.sourceMetadata?.confidence, .userVerified)
        XCTAssertEqual(corrected.sourceMetadata?.reviewStatus, .userEdited)
        XCTAssertEqual(corrected.sourceMetadata?.barcode, "012345")
        XCTAssertEqual(corrected.sourceMetadata?.originalEstimate?.calories, 220)
        XCTAssertEqual(corrected.sourceMetadata?.userCorrection?.calories, 250)
    }

    func testBarcodeCorrectionRulesPreferUserEditedSavedFoods() {
        let barcode = "000777"
        let confirmed = FoodItem(
            id: "confirmed",
            name: "Confirmed Bar",
            calories: 210,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: barcode
            )
        )
        let edited = FoodItem(
            id: "edited",
            name: "Edited Bar",
            calories: 240,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods",
                barcode: " 000 777 "
            )
        )

        let match = BarcodeCorrectionRules.bestCorrectedFood(in: [confirmed, edited], barcode: barcode)

        XCTAssertEqual(match?.id, "edited")
        XCTAssertEqual(match?.sourceMetadata?.sourceType, .custom)
        XCTAssertEqual(match?.sourceMetadata?.barcode, barcode)
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: match!.sourceMetadata!).title, "My Foods Match")
    }

    func testBarcodeLookupCandidatesBridgeUPCAAndEAN13() {
        XCTAssertEqual(
            BarcodeCorrectionRules.lookupCandidates(for: "012345678905"),
            ["012345678905", "0012345678905", "00012345678905"]
        )
        XCTAssertEqual(
            BarcodeCorrectionRules.lookupCandidates(for: "0012345678905"),
            ["0012345678905", "012345678905", "00012345678905"]
        )
    }

    func testBarcodeLookupCandidatesOnlyBridgeZeroPaddedGTIN14() {
        XCTAssertEqual(
            BarcodeCorrectionRules.lookupCandidates(for: "00012345678905"),
            ["00012345678905", "0012345678905", "012345678905"]
        )
        XCTAssertEqual(
            BarcodeCorrectionRules.lookupCandidates(for: "10012345678902"),
            ["10012345678902"],
            "A non-zero GTIN-14 indicator identifies a packaging level, not a zero-padded retail code."
        )
    }

    func testGTINValidationRejectsBadCheckDigits() {
        XCTAssertTrue(BarcodeCorrectionRules.isValidGTIN("012345678905"))
        XCTAssertTrue(BarcodeCorrectionRules.isValidGTIN("0012345678905"))
        XCTAssertFalse(BarcodeCorrectionRules.isValidGTIN("012345678901"))
        XCTAssertFalse(BarcodeCorrectionRules.isValidGTIN("12345"))
    }

    func testBarcodeNormalizationProducesASCIIWithoutDroppingLeadingZeros() {
        XCTAssertEqual(
            BarcodeCorrectionRules.normalizedBarcode(" ٠١٢-٣٤٥ ٦٧٨٩٠٥ "),
            "012345678905"
        )
        XCTAssertTrue(BarcodeCorrectionRules.isValidGTIN(" ٠١٢-٣٤٥ ٦٧٨٩٠٥ "))
    }

    func testBarcodeCorrectionsMatchRelatedVariants() {
        let saved = FoodItem(
            id: "ean-saved",
            name: "Saved EAN",
            calories: 120,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "0012345678905"
            )
        )

        XCTAssertTrue(BarcodeCorrectionRules.matches(saved, barcode: "012345678905"))
        let match = BarcodeCorrectionRules.bestCorrectedFood(in: [saved], barcode: "012345678905")
        XCTAssertEqual(match?.sourceMetadata?.barcode, "012345678905")
    }

    func testFoodTrustEvaluationRewardsCrossVerifiedDatabaseFoods() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let item = FoodItem(
            name: "Protein Bar",
            calories: 220,
            protein: 20,
            carbs: 22,
            fats: 8,
            servingSize: "1 bar",
            servingWeight: 60,
            sourceMetadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(for: metadata)

        let evaluation = FoodTrustEvaluation.evaluate(item: item, descriptor: descriptor, metadata: metadata)

        XCTAssertEqual(evaluation.level, .excellent)
        XCTAssertEqual(evaluation.label, "Excellent trust")
        XCTAssertTrue(evaluation.reasons.contains("Calories and macros matched another database"))
        XCTAssertGreaterThanOrEqual(evaluation.score, 90)
        XCTAssertFalse(evaluation.requiresCorrection)
    }

    func testTrustModelSourceMatrixStaysConservativeAndDeterministic() {
        func item(metadata: FoodSourceMetadata?) -> FoodItem {
            FoodItem(
                name: "Chicken Breast",
                calories: 165,
                protein: 31,
                carbs: 0,
                fats: 3.6,
                servingWeight: 100,
                sourceMetadata: metadata
            )
        }

        let cases: [(String, FoodItem, Int, FoodTrustEvaluation.Level)] = [
            (
                "USDA",
                item(metadata: .database(.usda, sourceName: "USDA FoodData Central", sourceID: "1")),
                86,
                .strong
            ),
            (
                "FatSecret",
                item(metadata: .database(.fatSecret, sourceName: "FatSecret", sourceID: "2")),
                74,
                .review
            ),
            (
                "Open Food Facts",
                item(metadata: .database(.openFoodFacts, sourceName: "Open Food Facts", sourceID: "3")),
                68,
                .review
            ),
            (
                "Manual",
                item(metadata: .userEntered(sourceName: "My Foods")),
                74,
                .review
            ),
            (
                "Private barcode",
                item(metadata: FoodSourceMetadata(
                    sourceType: .custom,
                    confidence: .userVerified,
                    reviewStatus: .userConfirmed,
                    sourceName: "My Foods",
                    barcode: "012345678905"
                )),
                88,
                .strong
            ),
            (
                "Chain estimate",
                item(metadata: .aiEstimate(.chainBuilder, sourceName: "Chain Builder")),
                50,
                .low
            ),
            (
                "AI estimate",
                item(metadata: .aiEstimate(.aiImage, sourceName: "Maia Vision")),
                42,
                .low
            ),
            (
                "Unknown",
                item(metadata: FoodSourceMetadata(
                    sourceType: .unknown,
                    confidence: .needsReview,
                    reviewStatus: .unreviewed
                )),
                55,
                .review
            )
        ]

        for (name, food, expectedScore, expectedLevel) in cases {
            let descriptor = FoodSourceClassifier.descriptor(
                for: "test",
                foodID: food.id,
                metadata: food.sourceMetadata
            )
            let evaluation = FoodTrustEvaluation.evaluate(
                item: food,
                descriptor: descriptor,
                metadata: food.sourceMetadata
            )
            XCTAssertEqual(evaluation.score, expectedScore, name)
            XCTAssertEqual(evaluation.level, expectedLevel, name)
        }
    }

    func testExcellentTrustRequiresIndependentDatabaseAgreement() {
        let item = FoodItem(
            name: "Chicken Breast",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingWeight: 100
        ).withDatabaseSource(.usda, sourceName: "USDA FoodData Central")
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .strong)
        XCTAssertLessThanOrEqual(evaluation.score, 89)
    }

    func testManualFoodCannotForgeExcellentTrustWithCrossVerificationStrings() {
        var metadata = FoodSourceMetadata.userEntered(sourceName: "My Foods")
        metadata.crossVerifiedBy = ["USDA", "Open Food Facts"]
        let item = FoodItem(
            name: "My Oats",
            calories: 200,
            protein: 10,
            carbs: 32,
            fats: 4,
            servingWeight: 100,
            sourceMetadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(for: metadata)

        let evaluation = FoodTrustEvaluation.evaluate(item: item, descriptor: descriptor, metadata: metadata)

        XCTAssertEqual(evaluation.level, .review)
        XCTAssertEqual(evaluation.label, "Reviewed entry")
        XCTAssertLessThanOrEqual(evaluation.score, 74)
        XCTAssertFalse(evaluation.reasons.contains("Calories and macros matched another database"))
    }

    func testReviewedManualEntryDoesNotBecomeStrongWithoutIndependentEvidence() {
        let item = FoodItem(
            name: "My Oats",
            calories: 200,
            protein: 10,
            carbs: 32,
            fats: 4,
            servingWeight: 100,
            sourceMetadata: .userEntered(sourceName: "My Foods")
        )
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .review)
        XCTAssertEqual(evaluation.label, "Reviewed entry")
        XCTAssertNil(evaluation.action)
        XCTAssertEqual(evaluation.score, 74)
    }

    func testSelfReferentialDatabaseVerificationIsIgnored() {
        var metadata = FoodSourceMetadata.database(.usda, sourceName: "USDA FoodData Central", sourceID: "1")
        metadata.crossVerifiedBy = ["USDA"]
        let item = FoodItem(
            name: "Apple",
            calories: 52,
            protein: 0.3,
            carbs: 14,
            fats: 0.2,
            servingWeight: 100,
            sourceMetadata: metadata
        )

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: FoodSourceClassifier.descriptor(for: metadata),
            metadata: metadata
        )

        XCTAssertEqual(evaluation.level, .strong)
        XCTAssertTrue(metadata.validatedCrossVerifiedBy.isEmpty)
    }

    func testUnreviewedEstimateIsLowConfidenceButNotBrokenData() {
        let item = FoodItem(
            name: "Estimated Snack",
            calories: 165,
            protein: 10,
            carbs: 20,
            fats: 5,
            servingWeight: 100
        ).withAIEstimateSource(.aiImage, sourceName: "Maia Vision")
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .low)
        XCTAssertEqual(evaluation.label, "Review estimate")
        XCTAssertEqual(evaluation.action, "Review estimate")
        XCTAssertFalse(evaluation.requiresCorrection)
    }

    func testReviewedEstimateAcknowledgesCompletedReviewWithoutClaimingVerification() {
        let item = FoodItem(
            name: "Estimated Snack",
            calories: 165,
            protein: 10,
            carbs: 20,
            fats: 5,
            servingWeight: 100
        )
            .withAIEstimateSource(.aiImage, sourceName: "Maia Vision")
            .markedUserEdited(sourceType: .aiImage)
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .review)
        XCTAssertEqual(evaluation.label, "Reviewed estimate")
        XCTAssertNil(evaluation.action)
        XCTAssertLessThanOrEqual(evaluation.score, 74)
        XCTAssertFalse(evaluation.requiresCorrection)
    }

    func testReviewedEstimateWithUnknownWeightOffersSpecificImprovement() {
        let item = FoodItem(
            name: "Estimated Bowl",
            calories: 420,
            protein: 25,
            carbs: 45,
            fats: 16,
            servingWeight: 0
        )
            .withAIEstimateSource(.aiMenu, sourceName: "Maia Menu")
            .markedUserConfirmed(sourceType: .aiMenu)
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .low)
        XCTAssertEqual(evaluation.label, "Reviewed estimate")
        XCTAssertEqual(evaluation.action, "Improve estimate")
        XCTAssertFalse(evaluation.requiresCorrection)
    }

    func testFoodTrustEvaluationDropsSuspiciousDataToCorrectionState() {
        let item = FoodItem(
            name: "Broken Food",
            calories: 0,
            protein: 40,
            carbs: 40,
            fats: 10,
            servingSize: "1 serving",
            servingWeight: 50
        ).withDatabaseSource(.fatSecret, sourceName: "FatSecret")
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(item: item, descriptor: descriptor, metadata: item.sourceMetadata)

        XCTAssertEqual(evaluation.level, .low)
        XCTAssertEqual(evaluation.action, "Fix data")
        XCTAssertTrue(evaluation.requiresCorrection)
        XCTAssertEqual(evaluation.reasonDetails.first?.kind, .correction)
        XCTAssertTrue(evaluation.reasons.contains("Nutrition checks found a value to fix"))
    }

    func testCommunityMatchStaysInReviewTier() {
        let item = CommunityBarcodeRules.communityFoodItem(
            name: "Protein Bar",
            calories: 210,
            protein: 20,
            carbs: 22,
            fats: 7,
            fiber: 3,
            servingSize: "1 bar",
            servingWeight: 60,
            barcode: "0123456789012"
        )
        let descriptor = FoodSourceClassifier.descriptor(for: item.sourceMetadata!)

        let evaluation = FoodTrustEvaluation.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(evaluation.level, .review)
        XCTAssertLessThanOrEqual(evaluation.score, 74)
        XCTAssertFalse(evaluation.requiresCorrection)
    }

    func testSavingAsCustomFoodClearsDatabaseAgreementEvidence() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let original = FoodItem(
            name: "Cereal",
            calories: 180,
            protein: 5,
            carbs: 36,
            fats: 2,
            servingWeight: 55,
            sourceMetadata: metadata
        )

        let saved = original.savedAsCustomFood(originalItem: original)

        XCTAssertNil(saved.sourceMetadata?.crossVerifiedBy)
        XCTAssertFalse(saved.sourceMetadata?.hasIndependentCrossVerification == true)
    }

    func testNutritionEditClearsAgreementEvidenceEvenWhenDatabasesWouldStillTolerateIt() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let original = FoodItem(
            id: "123",
            name: "Cereal",
            calories: 200,
            protein: 10,
            carbs: 20,
            fats: 8,
            servingWeight: 100,
            sourceMetadata: metadata
        )
        let edited = FoodItem(
            id: original.id,
            name: original.name,
            calories: 220,
            protein: 11,
            carbs: 22,
            fats: 8.5,
            servingWeight: 100,
            sourceMetadata: metadata
        ).markedUserEdited(originalItem: original)

        XCTAssertNil(edited.sourceMetadata?.crossVerifiedBy)
        XCTAssertFalse(edited.sourceMetadata?.hasIndependentCrossVerification == true)
    }

    func testServingRescaleKeepsAgreementEvidence() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let original = FoodItem(
            id: "123",
            name: "Cereal",
            calories: 200,
            protein: 10,
            carbs: 20,
            fats: 8,
            servingWeight: 100,
            sourceMetadata: metadata
        )
        let scaled = FoodItem(
            id: original.id,
            name: original.name,
            calories: 60,
            protein: 3,
            carbs: 6,
            fats: 2.4,
            servingWeight: 30,
            sourceMetadata: metadata
        ).markedUserEdited(originalItem: original)

        XCTAssertEqual(scaled.sourceMetadata?.validatedCrossVerifiedBy, ["USDA"])
    }

    func testMaterialServingSelectionClearsAgreementEvidenceWhenConfirmed() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let original = FoodItem(
            id: "123",
            name: "Cereal",
            calories: 200,
            protein: 10,
            carbs: 20,
            fats: 8,
            servingWeight: 100,
            sourceMetadata: metadata
        )
        let differentServing = FoodItem(
            id: original.id,
            name: original.name,
            calories: 250,
            protein: 10,
            carbs: 20,
            fats: 8,
            servingWeight: 100,
            sourceMetadata: metadata
        ).markedUserConfirmed(originalItem: original)

        XCTAssertNil(differentServing.sourceMetadata?.crossVerifiedBy)
        XCTAssertEqual(differentServing.sourceMetadata?.reviewStatus, .userConfirmed)
    }

    func testProportionalServingSelectionKeepsAgreementEvidenceWhenConfirmed() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let original = FoodItem(
            id: "123",
            name: "Cereal",
            calories: 200,
            protein: 10,
            carbs: 20,
            fats: 8,
            servingWeight: 100,
            sourceMetadata: metadata
        )
        let scaledServing = FoodItem(
            id: original.id,
            name: original.name,
            calories: 60,
            protein: 3,
            carbs: 6,
            fats: 2.4,
            servingWeight: 30,
            sourceMetadata: metadata
        ).markedUserConfirmed(originalItem: original)

        XCTAssertEqual(scaledServing.sourceMetadata?.validatedCrossVerifiedBy, ["USDA"])
        XCTAssertEqual(scaledServing.sourceMetadata?.reviewStatus, .userConfirmed)
    }

    func testBarcodeLookupOutcomeSuccessIsPrivacySafeAndTrustAware() {
        var metadata = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        metadata.crossVerifiedBy = ["USDA"]
        let item = FoodItem(
            id: "123",
            name: "Protein Bar",
            calories: 220,
            protein: 20,
            carbs: 22,
            fats: 8,
            servingSize: "1 bar",
            servingWeight: 60,
            sourceMetadata: metadata
        )
        let lookup = BarcodeFoodLookupResult(
            item: item,
            source: "barcode_result",
            scannedBarcode: "012345678905",
            matchedBarcode: "0012345678905",
            candidateCount: 3
        )

        let outcome = BarcodeLookupOutcome.success(lookup, durationMilliseconds: 1_840)
        let params = outcome.analyticsParameters

        XCTAssertEqual(outcome.result, "hit")
        XCTAssertTrue(outcome.usedRelatedBarcode)
        XCTAssertEqual(params["source"] as? String, "barcode_result")
        XCTAssertEqual(params["scanned_length"] as? Int, 12)
        XCTAssertEqual(params["matched_length"] as? Int, 13)
        XCTAssertEqual(params["candidate_count"] as? Int, 3)
        XCTAssertEqual(params["cross_verified_count"] as? Int, 1)
        XCTAssertEqual(params["trust_level"] as? String, FoodTrustEvaluation.Level.excellent.rawValue)
        XCTAssertEqual(params["trust_model_version"] as? String, String(FoodTrustEvaluation.modelVersion))
        XCTAssertEqual(params["duration_ms"] as? Int, 1_840)
        XCTAssertEqual(params["duration_bucket"] as? String, "1s_to_2s")
        XCTAssertNil(params["barcode"], "Do not log the raw product barcode.")
    }

    func testBarcodeLookupOutcomeMissLogsOnlyShapeNotRawBarcode() {
        let outcome = BarcodeLookupOutcome.miss(
            barcode: "0 12345 67890 5",
            durationMilliseconds: 6_200
        )
        let params = outcome.analyticsParameters

        XCTAssertEqual(outcome.result, "miss")
        XCTAssertEqual(params["source"] as? String, "none")
        XCTAssertEqual(params["scanned_length"] as? Int, 12)
        XCTAssertEqual(params["candidate_count"] as? Int, 3)
        XCTAssertEqual(params["duration_ms"] as? Int, 6_200)
        XCTAssertEqual(params["duration_bucket"] as? String, "over_4s")
        XCTAssertNil(params["trust_score"])
        XCTAssertNil(params["barcode"], "Miss telemetry should still avoid raw barcode values.")
    }

    func testBarcodeRecoveryOutcomeSelectionIsPrivacySafe() {
        let outcome = BarcodeRecoveryOutcome.selected(action: "create_food", barcode: "0 12345 67890 5")
        let params = outcome.analyticsParameters

        XCTAssertEqual(outcome.action, "create_food")
        XCTAssertEqual(params["scanned_length"] as? Int, 12)
        XCTAssertEqual(params["candidate_count"] as? Int, 3)
        XCTAssertNil(params["barcode"], "Recovery telemetry should avoid raw barcode values.")
        XCTAssertNil(params["trust_score"])
    }

    func testBarcodeRecoveryOutcomeManualFoodCreatedIncludesTrustWithoutRawBarcode() {
        let food = FoodItem(
            id: "manual-1",
            name: "Manual Protein Bar",
            calories: 240,
            protein: 20,
            carbs: 24,
            fats: 8,
            servingSize: "1 bar",
            servingWeight: 60,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "0 12345 67890 5"
            )
        )

        let outcome = BarcodeRecoveryOutcome.manualFoodCreated(food)
        let params = outcome.analyticsParameters

        XCTAssertEqual(params["action"] as? String, "manual_food_created")
        XCTAssertEqual(params["scanned_length"] as? Int, 12)
        XCTAssertEqual(params["trust_level"] as? String, FoodTrustEvaluation.Level.strong.rawValue)
        XCTAssertEqual(params["trust_model_version"] as? String, String(FoodTrustEvaluation.modelVersion))
        XCTAssertNotNil(params["trust_score"])
        XCTAssertNil(params["barcode"], "Created-food telemetry should avoid raw barcode values.")
    }

    @MainActor
    func testBarcodeLookupReturnsSavedCorrectionBeforeExternalSources() async {
        let analytics = MockAnalyticsManager()
        DIContainer.shared.analyticsManager = analytics
        let correctedFood = FoodItem(
            id: "corrected",
            name: "Saved Cereal",
            calories: 180,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "123456"
            )
        )
        let service = BarcodeFoodLookupService(correctionStore: StaticBarcodeCorrectionStore(food: correctedFood))

        let result = await service.lookup("123456")

        XCTAssertEqual(result?.source, "custom_barcode")
        XCTAssertEqual(result?.item.id, "corrected")
        XCTAssertEqual(result?.item.sourceMetadata?.sourceType, .custom)
        let events = analytics.loggedEvents.filter { $0.name == BarcodeLookupOutcome.eventName }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.parameters?["result"] as? String, "hit")
        XCTAssertNotNil(events.first?.parameters?["duration_ms"])
    }
}

private struct StaticBarcodeCorrectionStore: BarcodeCorrectionStoreProtocol {
    let food: FoodItem?

    func correctedFood(for barcode: String) async -> FoodItem? {
        food
    }
}
