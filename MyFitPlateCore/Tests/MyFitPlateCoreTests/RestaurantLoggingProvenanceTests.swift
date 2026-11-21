import XCTest
@testable import MyFitPlateCore

final class RestaurantLoggingProvenanceTests: XCTestCase {
    func testEstimatedSourceRecognitionUsesWordsAndKeepsLegacyAIAndManualIdentifiers() {
        for source in ["ai", "AI", "ai_chat", "ai_image", "ai_bulk", "legacy-AI-text", "AIImage", "manual", "manual_add", "manualEntry"] {
            XCTAssertTrue(NutritionCalorieConsistency.isEstimatedSource(source), source)
        }
        for source in ["chain_builder", "chain_builder_components", "chain_builder_components_edit", "email", "plain_label", "retail_database", "barcode_scan", "fatsecret"] {
            XCTAssertFalse(NutritionCalorieConsistency.isEstimatedSource(source), source)
        }
    }
    func testGroupedRealCatalogFiveCaloriesStaysFiveWithoutInventingMass() throws {
        let chain = ChainRestaurantCatalog.fiveGuys
        let mushrooms = try XCTUnwrap(chain.categories.flatMap(\.ingredients).first { $0.id == "fg_mushrooms" })
        let order = chain.customMealFoodItem(from: [mushrooms.id: ChainSelectionItem(id: mushrooms.id, ingredient: mushrooms)], id: "qa-restaurant-order")
        let components = try XCTUnwrap(order.mealComposition?.components)
        let component = try XCTUnwrap(components.first)
        XCTAssertEqual(component.calories, 5)
        XCTAssertEqual(component.macroDerivedCalories, 8, "Catalog rounding/reference calories deliberately remain separate from macro arithmetic")
        XCTAssertEqual(component.servingWeight, 0, "An unmeasured free topping is not one gram")
        XCTAssertEqual(order.servingWeight, 0)
        XCTAssertFalse(PlannedMealMeasurementRules.hasKnownMass(component))
        var diary = DailyLog(date: Date(), meals: [])
        let result = DailyLogRules.addMealGroupsToLog(log: &diary,
            mealGroups: [(mealName: "Dinner", foodItems: components)], defaultSource: "chain_builder_components")
        XCTAssertEqual(result.addedItems.count, 1)
        XCTAssertEqual(diary.meals[0].foodItems[0].calories, 5)
        XCTAssertEqual(diary.meals[0].foodItems[0].servingWeight, 0)
        XCTAssertEqual(diary.meals[0].foodItems[0].sourceMetadata?.sourceType, .chainBuilder)
        XCTAssertEqual(diary.meals[0].foodItems[0].sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(diary.meals[0].foodItems[0].sourceMetadata?.sourceID, component.sourceMetadata?.sourceID)
    }
    func testCollapsedCatalogOrderAndRelativePortionKeepReferenceCaloriesAndUnknownMass() throws {
        let chain = ChainRestaurantCatalog.fiveGuys
        let mushrooms = try XCTUnwrap(chain.categories.flatMap(\.ingredients).first { $0.id == "fg_mushrooms" })
        let order = chain.customMealFoodItem(from: [mushrooms.id: ChainSelectionItem(id: mushrooms.id, ingredient: mushrooms)], id: "collapsed")
        var diary = DailyLog(date: Date(), meals: [])
        let saved = DailyLogRules.addFoodToLog(log: &diary, foodItem: order, mealName: "Lunch", source: "chain_builder")
        XCTAssertEqual(saved.calories, 5)
        let doubled = try XCTUnwrap(FoodRepeatRules.adjusting(saved, by: 2))
        XCTAssertEqual(doubled.calories, 10)
        XCTAssertEqual(doubled.mealComposition?.components.first?.calories, 10)
        XCTAssertEqual(doubled.mealComposition?.components.first?.servingWeight, 0)
    }
    func testAIAndManualNormalizationStillCorrectsMissingOrInconsistentEstimateCalories() {
        let item = FoodItem(id: "estimated", name: "Estimate", calories: 100, protein: 20, carbs: 20, fats: 10)
        XCTAssertEqual(item.normalizedForEstimatedSource("ai_image").calories, 250)
        XCTAssertEqual(item.normalizedForEstimatedSource("manual_add").calories, 250)
        XCTAssertEqual(item.normalizedForEstimatedSource("chain_builder_components").calories, 100)
        XCTAssertEqual(item.normalizedForEstimatedSource("retail_database").calories, 100)
    }
    func testChainFallbackDescriptorAndLegacyEditKeepRestaurantEstimatedLineage() {
        let source = "chain_builder_component_edit"
        let descriptor = FoodSourceClassifier.descriptor(for: source)
        XCTAssertEqual(descriptor.sourceKey, "chain_builder")
        XCTAssertTrue(descriptor.isEstimated)
        XCTAssertNotEqual(descriptor.title, "AI Estimate")
        let legacy = FoodItem(id: "legacy-chain", name: "Reference topping", calories: 5, protein: 1, carbs: 1, fats: 0)
        let edited = legacy.markedUserEdited(sourceType: .chainBuilder, originalItem: legacy)
        XCTAssertEqual(edited.sourceMetadata?.sourceType, .chainBuilder)
        XCTAssertEqual(edited.sourceMetadata?.confidence, .estimated)
        XCTAssertEqual(edited.sourceMetadata?.reviewStatus, .userEdited)
        XCTAssertEqual(FoodSourceClassifier.descriptor(for: source, metadata: edited.sourceMetadata).sourceKey, "chain_builder")
    }
    func testFallbackSourceWordsAvoidIncidentalAIAndPreserveExplicitLegacyAI() {
        for source in ["chain_builder_components", "chain builder edit", "chainBuilder"] {
            let descriptor = FoodSourceClassifier.descriptor(for: source)
            XCTAssertEqual(descriptor.sourceKey, "chain_builder", source)
            XCTAssertTrue(descriptor.isEstimated, source)
        }
        for source in ["email", "plain_label", "retail_database"] {
            XCTAssertNotEqual(FoodSourceClassifier.descriptor(for: source).sourceKey, "ai_estimate", source)
        }
        for source in ["ai_image", "AIText", "ai_menu", "image_result_edit", "pantry_vision"] {
            XCTAssertEqual(FoodSourceClassifier.descriptor(for: source).sourceKey, "ai_estimate", source)
        }
    }
    func testMainMealLabelDoesNotNormalizeCatalogReferenceAsAI() {
        let item = FoodItem(id: "catalog", name: "Reference topping", calories: 5, protein: 1, carbs: 1, fats: 0)
        var diary = DailyLog(date: Date(), meals: [])
        let result = DailyLogRules.addMealGroupsToLog(log: &diary, mealGroups: [(mealName: "Main meal", foodItems: [item])], defaultSource: "restaurant_reference")
        XCTAssertEqual(result.sourceUsed, "restaurant_reference")
        XCTAssertEqual(result.addedItems[0].calories, 5)
        XCTAssertEqual(diary.meals[0].name, "Main meal")
    }
    func testExactLegacyAIGroupStillNormalizesUnknownEstimate() {
        let item = FoodItem(id: "estimate", name: "Estimate", calories: 100, protein: 20, carbs: 20, fats: 10)
        var diary = DailyLog(date: Date(), meals: [])
        let result = DailyLogRules.addMealGroupsToLog(log: &diary, mealGroups: [(mealName: "AI Meal", foodItems: [item])], defaultSource: "legacy")
        XCTAssertEqual(result.sourceUsed, "ai_bulk")
        XCTAssertEqual(result.addedItems[0].calories, 250)
    }
    func testMixedTypedAIAndRestaurantGroupDoesNotNormalizeCatalogSibling() {
        var estimated = FoodItem(id: "estimate", name: "Photo estimate", calories: 100, protein: 20, carbs: 20, fats: 10)
        estimated.sourceMetadata = FoodSourceMetadata(sourceType: .aiImage, confidence: .estimated, reviewStatus: .unreviewed)
        var reference = FoodItem(id: "reference", name: "Catalog topping", calories: 5, protein: 1, carbs: 1, fats: 0)
        reference.sourceMetadata = FoodSourceMetadata(sourceType: .chainBuilder, confidence: .estimated, reviewStatus: .unreviewed)
        var diary = DailyLog(date: Date(), meals: [])
        let result = DailyLogRules.addMealGroupsToLog(log: &diary, mealGroups: [(mealName: "Dinner", foodItems: [estimated, reference])], defaultSource: "grouped")
        XCTAssertEqual(result.sourceUsed, "ai_bulk")
        XCTAssertEqual(result.addedItems.first { $0.id == "estimate" }?.calories, 250)
        XCTAssertEqual(result.addedItems.first { $0.id == "reference" }?.calories, 5)
        XCTAssertEqual(result.addedItems.first { $0.id == "reference" }?.sourceMetadata?.confidence, .estimated)
    }
    func testKnownReferenceMetadataOverridesLegacyAIGroupLabel() {
        let reference = FoodItem(id: "reference", name: "Catalog topping", calories: 5, protein: 1, carbs: 1, fats: 0,
            sourceMetadata: FoodSourceMetadata(sourceType: .chainBuilder, confidence: .estimated, reviewStatus: .unreviewed))
        var diary = DailyLog(date: Date(), meals: [])
        let result = DailyLogRules.addMealGroupsToLog(log: &diary, mealGroups: [(mealName: "AI Meal", foodItems: [reference])], defaultSource: "catalog")
        XCTAssertEqual(result.sourceUsed, "catalog")
        XCTAssertEqual(result.addedItems[0].calories, 5)
    }

}
