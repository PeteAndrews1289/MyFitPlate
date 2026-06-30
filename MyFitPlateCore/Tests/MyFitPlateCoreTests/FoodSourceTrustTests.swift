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
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: editedItem.sourceMetadata!).confidence, "User Edited")
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
}
