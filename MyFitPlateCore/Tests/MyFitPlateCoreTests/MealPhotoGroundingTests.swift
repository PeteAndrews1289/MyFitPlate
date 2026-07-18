import XCTest
@testable import MyFitPlateCore

final class MealPhotoGroundingTests: XCTestCase {
    func testGroundingScalesReferenceNutritionButKeepsPhotoProvenance() throws {
        let estimate = makeEstimate(
            name: "Grilled chicken breast",
            preparation: "grilled",
            grams: 150,
            calories: 260,
            protein: 45,
            carbs: 0,
            fats: 8
        )
        let reference = FoodItem(
            id: "usda_chicken",
            name: "Chicken, broilers or fryers, breast, meat only, cooked, grilled",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100,
            sodium: 74,
            vitaminB6: 0.6
        ).withDatabaseSource(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_chicken"
        )

        let outcome = try XCTUnwrap(MealPhotoGrounding.makeOutcome(
            estimate: estimate,
            candidates: [reference]
        ))

        XCTAssertTrue(outcome.usedNutrientReference)
        XCTAssertEqual(outcome.referenceSourceName, "USDA FoodData Central")
        XCTAssertEqual(outcome.item.calories, 247.5, accuracy: 0.001)
        XCTAssertEqual(outcome.item.protein, 46.5, accuracy: 0.001)
        XCTAssertEqual(outcome.item.sodium ?? 0, 111, accuracy: 0.001)
        XCTAssertEqual(outcome.item.servingWeight, 150, accuracy: 0.001)
        XCTAssertEqual(outcome.item.sourceMetadata?.sourceType, .aiImage)
        XCTAssertEqual(outcome.item.sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(outcome.item.sourceMetadata?.matchedFoodID, "usda_chicken")
        XCTAssertEqual(
            outcome.item.sourceMetadata?.nutrientReferenceEvidence?.sourceType,
            .usda
        )
    }

    func testConflictingPreparationDoesNotGroundNutrition() throws {
        let estimate = makeEstimate(
            name: "Grilled chicken breast",
            preparation: "grilled",
            grams: 150,
            calories: 260,
            protein: 45,
            carbs: 0,
            fats: 8
        )
        let rawReference = FoodItem(
            id: "raw_chicken",
            name: "Chicken breast, raw",
            calories: 120,
            protein: 23,
            carbs: 0,
            fats: 2.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(.usda, sourceName: "USDA", sourceID: "raw_chicken")

        let outcome = try XCTUnwrap(MealPhotoGrounding.makeOutcome(
            estimate: estimate,
            candidates: [rawReference]
        ))

        XCTAssertFalse(outcome.usedNutrientReference)
        XCTAssertEqual(outcome.item.calories, 260, accuracy: 0.001)
        XCTAssertNil(outcome.item.sourceMetadata?.nutrientReferenceEvidence)
        XCTAssertTrue(outcome.item.sourceMetadata?.notes?.contains("model estimate") == true)
    }

    func testLowConfidenceRequiresReviewEvenWithReferenceMatch() throws {
        let estimate = MealPhotoFoodEstimate(
            itemName: "White rice",
            preparation: "cooked",
            servingSize: "about 1 cup",
            estimatedGrams: 180,
            portionLowGrams: 140,
            portionHighGrams: 220,
            calories: 235,
            protein: 4,
            carbs: 52,
            fats: 0.5,
            confidence: 0.55,
            visibleEvidence: "A mound of white grains",
            hiddenIngredientRisks: ["oil"],
            requiresConfirmation: false,
            clarificationQuestion: "Was oil or butter added?"
        )
        let reference = FoodItem(
            id: "cnf_rice",
            name: "Rice, white, cooked",
            calories: 130,
            protein: 2.7,
            carbs: 28,
            fats: 0.3,
            servingSize: "100 g",
            servingWeight: 100,
            magnesium: 12
        ).withDatabaseSource(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: "cnf_rice"
        )

        let outcome = try XCTUnwrap(MealPhotoGrounding.makeOutcome(
            estimate: estimate,
            candidates: [reference]
        ))

        XCTAssertTrue(outcome.requiresConfirmation)
        XCTAssertEqual(outcome.item.sourceMetadata?.confidence, .needsReview)
        XCTAssertEqual(outcome.portionLowGrams, 140)
        XCTAssertEqual(outcome.portionHighGrams, 220)
        XCTAssertEqual(outcome.clarificationQuestion, "Was oil or butter added?")
    }

    func testMissingPortionForcesReviewAndDoesNotGroundReferenceNutrition() throws {
        let estimate = MealPhotoFoodEstimate(
            itemName: "Roasted potatoes",
            preparation: "roasted",
            servingSize: "estimated serving",
            estimatedGrams: nil,
            portionLowGrams: 120,
            portionHighGrams: nil,
            calories: 210,
            protein: 4,
            carbs: 35,
            fats: 7,
            confidence: 0.84,
            visibleEvidence: "Several potato pieces are visible",
            hiddenIngredientRisks: ["oil"],
            requiresConfirmation: false,
            clarificationQuestion: "Roughly how much did you eat?"
        )
        let reference = FoodItem(
            id: "usda_roasted_potatoes",
            name: "Potatoes, roasted",
            calories: 150,
            protein: 3,
            carbs: 28,
            fats: 3,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(.usda, sourceName: "USDA", sourceID: "usda_roasted_potatoes")

        let outcome = try XCTUnwrap(MealPhotoGrounding.makeOutcome(
            estimate: estimate,
            candidates: [reference]
        ))

        XCTAssertTrue(outcome.requiresConfirmation)
        XCTAssertFalse(outcome.usedNutrientReference)
        XCTAssertNil(outcome.portionLowGrams)
        XCTAssertNil(outcome.portionHighGrams)
        XCTAssertEqual(outcome.item.calories, 210, accuracy: 0.001)
        XCTAssertEqual(outcome.item.sourceMetadata?.confidence, .needsReview)
    }

    func testSpecificPreparationDoesNotMatchUnspecifiedReference() {
        let estimate = makeEstimate(
            name: "Fried chicken breast",
            preparation: "fried",
            grams: 150,
            calories: 350,
            protein: 35,
            carbs: 15,
            fats: 17
        )
        let unspecifiedReference = FoodItem(
            id: "generic_chicken",
            name: "Chicken breast",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(.usda, sourceName: "USDA", sourceID: "generic_chicken")

        XCTAssertNil(MealPhotoGrounding.bestReferenceMatch(
            for: estimate,
            candidates: [unspecifiedReference]
        ))
    }

    func testTrustPassportDoesNotCallReferenceGroundingCrossVerification() throws {
        let estimate = makeEstimate(
            name: "Apple",
            preparation: "raw",
            grams: 180,
            calories: 95,
            protein: 0.5,
            carbs: 25,
            fats: 0.3
        )
        let reference = FoodItem(
            id: "usda_apple",
            name: "Apples, raw, with skin",
            calories: 52,
            protein: 0.3,
            carbs: 14,
            fats: 0.2,
            fiber: 2.4,
            servingSize: "100 g",
            servingWeight: 100,
            potassium: 107
        ).withDatabaseSource(.usda, sourceName: "USDA FoodData Central", sourceID: "usda_apple")
        let item = try XCTUnwrap(MealPhotoGrounding.makeOutcome(
            estimate: estimate,
            candidates: [reference]
        )).item
        let descriptor = FoodSourceClassifier.descriptor(
            for: "ai_image",
            foodID: item.id,
            metadata: item.sourceMetadata
        )
        let passport = FoodTrustPassport.evaluate(
            item: item,
            descriptor: descriptor,
            metadata: item.sourceMetadata
        )

        XCTAssertEqual(passport.coreNutrition.state, FoodTrustEvidenceState.estimated)
        XCTAssertTrue(passport.coreNutrition.detail.contains("USDA FoodData Central"))
        XCTAssertFalse(item.sourceMetadata?.hasCrossDatabaseAgreement ?? true)
    }

    private func makeEstimate(
        name: String,
        preparation: String,
        grams: Double,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double
    ) -> MealPhotoFoodEstimate {
        MealPhotoFoodEstimate(
            itemName: name,
            preparation: preparation,
            servingSize: "about \(Int(grams)) g",
            estimatedGrams: grams,
            portionLowGrams: grams * 0.8,
            portionHighGrams: grams * 1.2,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            confidence: 0.82,
            visibleEvidence: "Clearly visible",
            hiddenIngredientRisks: [],
            requiresConfirmation: false,
            clarificationQuestion: nil
        )
    }
}
