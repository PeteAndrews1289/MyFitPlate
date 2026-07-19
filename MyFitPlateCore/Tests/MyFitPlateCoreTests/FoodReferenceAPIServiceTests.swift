import XCTest
@testable import MyFitPlateCore

final class FoodReferenceAPIServiceTests: XCTestCase {
    func testHealthCanadaParserPreservesBroadMicronutrientsAndProvenance() throws {
        let json = """
        [
          {
            "id": "cnf_841",
            "name": "Chicken, broiler, breast, skinless, boneless, meat, raw",
            "servingSize": "100 g",
            "servingWeight": 100,
            "nutrients": {
              "calories": 120,
              "protein": 22.5,
              "carbs": 0,
              "fat": 2.6,
              "sodium": 45,
              "potassium": 334,
              "vitaminB12": 0.2,
              "copper": 55,
              "vitaminC": 0
            },
            "datasetRelease": "2026-05-14",
            "recordUpdatedAt": "2015-11-03",
            "foodSourceCode": 0,
            "foodSourceSummary": "Based on unchanged USDA composition data",
            "micronutrientCount": 5
          }
        ]
        """
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let food = try XCTUnwrap(
            HealthCanadaFoodParser.foodItems(from: Data(json.utf8), observedAt: observedAt).first
        )

        XCTAssertEqual(food.id, "cnf_841")
        XCTAssertEqual(food.servingWeight, 100)
        XCTAssertEqual(food.potassium, 334)
        XCTAssertEqual(food.copper, 55)
        XCTAssertNotNil(food.vitaminC, "A reported zero must remain distinct from missing data")
        XCTAssertEqual(food.vitaminC, 0)
        XCTAssertEqual(food.sourceMetadata?.sourceType, .healthCanadaCNF)
        XCTAssertEqual(food.sourceMetadata?.effectiveEvidenceLineage, .governmentCompilation)
        XCTAssertEqual(food.sourceMetadata?.sourceObservedAt, observedAt)
        XCTAssertNotNil(food.sourceMetadata?.sourceUpdatedAt)
        XCTAssertTrue(food.sourceMetadata?.notes?.contains("unchanged USDA") == true)
    }

    func testNIHParserUsesLabelServingWithoutInventingGramWeight() throws {
        let json = """
        {
          "id": "dsld_42",
          "name": "Example Daily Multi",
          "servingSize": "2 Capsules",
          "quantityValue": 2,
          "servingUnit": "Capsules",
          "barcode": "012345678905",
          "entryDate": "2026-05-01",
          "productType": "Multi-Vitamin and Mineral (MVM)",
          "micronutrientCount": 4,
          "nutrients": {
            "vitaminD": 20,
            "vitaminC": 60,
            "copper": 2000,
            "folate": 400
          }
        }
        """
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let supplement = try NIHDietarySupplementParser.foodItem(
            from: Data(json.utf8),
            observedAt: observedAt
        )

        XCTAssertEqual(supplement.id, "dsld_42")
        XCTAssertEqual(supplement.servingSize, "2 Capsules")
        XCTAssertEqual(supplement.servingWeight, 0)
        XCTAssertEqual(supplement.quantityValue, 1)
        XCTAssertEqual(supplement.servingUnit, "serving")
        XCTAssertEqual(supplement.vitaminD, 20)
        XCTAssertEqual(supplement.copper, 2000)
        XCTAssertEqual(supplement.sourceMetadata?.sourceType, .nihDSLD)
        XCTAssertEqual(supplement.sourceMetadata?.effectiveEvidenceLineage, .manufacturerLabel)
        XCTAssertNil(supplement.sourceMetadata?.sourceUpdatedAt, "DSLD entry date is not a formulation update")
        XCTAssertTrue(supplement.sourceMetadata?.notes?.contains("not laboratory verification") == true)

        let descriptor = FoodSourceClassifier.descriptor(for: supplement.sourceMetadata!)
        let evaluation = FoodTrustEvaluation.evaluate(
            item: supplement,
            descriptor: descriptor,
            metadata: supplement.sourceMetadata
        )
        XCTAssertFalse(evaluation.reasons.contains { $0.contains("Serving weight is unavailable") })

        let passport = FoodTrustPassport.evaluate(
            item: supplement,
            descriptor: descriptor,
            metadata: supplement.sourceMetadata
        )
        let serving = try XCTUnwrap(passport.scopes.first { $0.field == .serving })
        XCTAssertEqual(serving.state, .sourceReported)
        XCTAssertTrue(serving.detail.contains("2 Capsules"))
        XCTAssertEqual(passport.detailedNutrientCount, 4)
    }

    func testSourceClassifierRecognizesReferenceAndSupplementIDs() {
        XCTAssertEqual(
            FoodSourceClassifier.descriptor(forFoodID: "cnf_101")?.sourceKey,
            "health_canada_cnf"
        )
        XCTAssertEqual(
            FoodSourceClassifier.descriptor(forFoodID: "dsld_202")?.sourceKey,
            "nih_dsld"
        )
    }
}
