import XCTest
@testable import MyFitPlateCore

final class USDAFoodParserTests: XCTestCase {
    func testFoundationGeneralEnergyIsRetainedInsteadOfBecomingZero() throws {
        // Current Foundation search responses use2047/957 without legacy208.
        let payload = #"{"foods":[{"fdcId":2257045,"description":"Almond milk, unsweetened, plain, refrigerated","dataType":"Foundation","servingSize":200,"servingSizeUnit":"g","foodNutrients":[{"nutrientId":2047,"nutrientNumber":"957","value":19.3},{"nutrientNumber":"203","value":0.66}]}]}"#
        let milk = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first)
        XCTAssertEqual(milk.calories, 38.6, accuracy: 0.0001)
        XCTAssertEqual(milk.protein, 1.32, accuracy: 0.0001)
        XCTAssertTrue(milk.sourceMetadata?.notes?.contains("general factors") == true)
    }

    func testSpecificEnergyFallbackSupportsNutrientIDWithoutLegacyNumber() throws {
        let payload = #"{"foods":[{"fdcId":1,"description":"Foundation food","foodNutrients":[{"nutrientId":2048,"value":52.5}]}]}"#
        let food = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first)
        XCTAssertEqual(food.calories, 52.5)
        XCTAssertTrue(food.sourceMetadata?.notes?.contains("specific factors") == true)
    }

    func testReportedLegacyEnergyIncludingZeroWinsOverAlternativeFactors() throws {
        for value in [0, 125] {
            let payload = "{\"foods\":[{\"fdcId\":1,\"description\":\"Reported food\",\"foodNutrients\":[{\"nutrientId\":1008,\"value\":\(value)},{\"nutrientNumber\":\"957\",\"value\":200},{\"nutrientNumber\":\"958\",\"value\":190}]}]}"
            let food = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first)
            XCTAssertEqual(food.calories, Double(value))
            XCTAssertNil(food.sourceMetadata?.notes)
        }
    }

    func testGeneralEnergyIsDefaultWhenBothAtwaterValuesAreReported() throws {
        let payload = #"{"foods":[{"fdcId":1,"description":"Foundation food","foodNutrients":[{"nutrientNumber":"957","value":200},{"nutrientNumber":"958","value":190}]}]}"#
        let food = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first)
        XCTAssertEqual(food.calories, 200)
        XCTAssertTrue(food.sourceMetadata?.notes?.contains("general factors") == true)
    }

    func testInvalidEnergyDoesNotOverrideAValidReportedFallback() throws {
        let payload = #"{"foods":[{"fdcId":1,"description":"Foundation food","foodNutrients":[{"nutrientNumber":"208","value":-1},{"nutrientNumber":"957","value":19.3}]}]}"#
        XCTAssertEqual(try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first).calories, 19.3)
    }

    func testKilojoulesAreNeverRelabeledAsKilocalories() throws {
        let payload = #"{"foods":[{"fdcId":1,"description":"Foundation food","foodNutrients":[{"nutrientId":1062,"nutrientNumber":"268","unitName":"kJ","value":418.4},{"nutrientId":1008,"nutrientNumber":"208","unitName":"kJ","value":418.4},{"nutrientId":2047,"nutrientNumber":"957","unitName":"KCAL","value":100}]}]}"#
        let food = try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first)
        XCTAssertEqual(food.calories, 100)
        XCTAssertTrue(food.sourceMetadata?.notes?.contains("general factors") == true)
        let kjOnly = #"{"foods":[{"fdcId":2,"description":"Unusable energy","foodNutrients":[{"nutrientId":1062,"nutrientNumber":"268","unitName":"kJ","value":418.4}]}]}"#
        XCTAssertEqual(try XCTUnwrap(USDAFoodParser.foodItems(from: Data(kjOnly.utf8)).first).calories, 0)
    }

    func testServingOverflowCannotPublishInfiniteEnergy() throws {
        let payload = #"{"foods":[{"fdcId":1,"description":"Malformed serving","servingSize":1e308,"servingSizeUnit":"g","householdServingFullText":"provider portion","foodNutrients":[{"nutrientNumber":"957","value":1e308}]}]}"#
        XCTAssertTrue(try XCTUnwrap(USDAFoodParser.foodItems(from: Data(payload.utf8)).first).calories.isFinite)
    }

    func testNonFiniteJSONEnergyIsRejectedBeforePublishingFood() {
        let payload = #"{"foods":[{"fdcId":1,"description":"Invalid energy","foodNutrients":[{"nutrientNumber":"957","value":1e309}]}]}"#
        XCTAssertThrowsError(try USDAFoodParser.foodItems(from: Data(payload.utf8)))
    }

    func testProductBrandNameTakesPrecedenceOverOwnerAndRemainsVisible() throws {
        let payload = #"{"foods":[{"fdcId":81,"description":"GREEK YOGURT","dataType":"Branded","brandName":"Fage","brandOwner":"Fage USA","foodNutrients":[]},{"fdcId":82,"description":"GREEK YOGURT","dataType":"Branded","brandOwner":"Chobani","foodNutrients":[]},{"fdcId":83,"description":"YOGURT","brandOwner":"Generic","foodNutrients":[]}]}"#
        let foods = try USDAFoodParser.foodItems(from: Data(payload.utf8))
        XCTAssertEqual(foods.map(\.name), ["Fage Greek Yogurt", "Chobani Greek Yogurt", "Yogurt"])
        XCTAssertEqual(foods[0].sourceMetadata?.brandName, "Fage")
        XCTAssertEqual(foods[1].sourceMetadata?.brandName, "Chobani")
        XCTAssertNil(foods[2].sourceMetadata?.brandName)
        XCTAssertEqual(foods[0].sourceMetadata?.effectiveEvidenceLineage, .manufacturerLabel)
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testScalesToServingGramsAndCleansNameAndUsesHouseholdServing() throws {
        // serving 50 g => scale 0.5; preparation qualifiers stay visible; household text wins.
        let json = """
        {
          "foods": [
            {
              "fdcId": 1102702,
              "description": "APPLE, RAW",
              "servingSize": 50,
              "servingSizeUnit": "g",
              "householdServingFullText": "1 medium",
              "foodNutrients": [
                {"nutrientNumber": "208", "value": 52},
                {"nutrientNumber": "203", "value": 0.3},
                {"nutrientNumber": "205", "value": 14},
                {"nutrientNumber": "204", "value": 0},
                {"nutrientNumber": "301", "value": 6}
              ]
            }
          ]
        }
        """
        let items = try USDAFoodParser.foodItems(from: data(json))
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(item.id, "usda_1102702")
        XCTAssertEqual(item.name, "Apple, Raw")
        XCTAssertEqual(item.calories, 26, accuracy: 0.001)     // 52 * 0.5
        XCTAssertEqual(item.protein, 0.15, accuracy: 0.001)    // 0.3 * 0.5
        XCTAssertEqual(item.carbs, 7, accuracy: 0.001)         // 14 * 0.5
        XCTAssertEqual(item.fats, 0, accuracy: 0.001)
        XCTAssertEqual(item.calcium ?? 0, 3, accuracy: 0.001)  // 6 * 0.5
        XCTAssertNil(item.saturatedFat)                        // not present -> nil
        XCTAssertEqual(item.servingSize, "1 medium")
        XCTAssertEqual(item.servingWeight, 50, accuracy: 0.001)
    }

    func testZeroValuedOptionalNutrientRemainsReportedAndUsesDefaultServing() throws {
        // No serving info => 100 g default, scale 1.0; a reported zero remains distinct from nil.
        let json = """
        {"foods": [{"fdcId": 999, "description": "Plain Thing",
          "foodNutrients": [
            {"nutrientNumber": "208", "value": 100},
            {"nutrientNumber": "301", "value": 0}
          ]}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.calories, 100, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "100 g")
        XCTAssertEqual(item.servingWeight, 100, accuracy: 0.001)
        XCTAssertNotNil(item.calcium)
        XCTAssertEqual(item.calcium, 0)
    }

    func testServingDescriptionFromSizeWhenNoHouseholdText() throws {
        let json = """
        {"foods": [{"fdcId": 1, "description": "Foo", "servingSize": 30,
          "servingSizeUnit": "g", "foodNutrients": []}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.servingSize, "30 g")
        XCTAssertEqual(item.servingWeight, 30, accuracy: 0.001)
        XCTAssertEqual(item.calories, 0, accuracy: 0.001)
    }

    func testNonGramServingUnitDoesNotScale() throws {
        // Milliliters cannot scale per-100-g nutrition without a verified density.
        let json = """
        {"foods": [{"fdcId": 2, "description": "Juice", "servingSize": 240,
          "servingSizeUnit": "ml",
          "foodNutrients": [{"nutrientNumber": "208", "value": 45}]}]}
        """
        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.calories, 45, accuracy: 0.001)   // not scaled
        XCTAssertEqual(item.servingWeight, 100, accuracy: 0.001)
        XCTAssertEqual(item.servingSize, "100 g")
        XCTAssertEqual(item.sourceMetadata?.labeledServing, "240 ml")
    }

    func testEmptyAndMultipleFoods() throws {
        XCTAssertTrue(try USDAFoodParser.foodItems(from: data(#"{"foods": []}"#)).isEmpty)
        let two = """
        {"foods": [
          {"fdcId": 1, "description": "A", "foodNutrients": []},
          {"fdcId": 2, "description": "B", "foodNutrients": []}
        ]}
        """
        XCTAssertEqual(try USDAFoodParser.foodItems(from: data(two)).count, 2)
    }

    func testBarcodeMatchRequiresReturnedGTINRatherThanFirstSearchResult() throws {
        let json = """
        {"foods": [
          {"fdcId": 1, "description": "Wrong Search Result", "gtinUpc": "9999999999994", "foodNutrients": []},
          {"fdcId": 2, "description": "Exact Product", "dataType": "Branded", "gtinUpc": "0012345678905",
           "foodNutrients": [{"nutrientNumber": "208", "value": 210}]}
        ]}
        """

        let item = try XCTUnwrap(USDAFoodParser.foodItem(
            matchingBarcode: "012345678905",
            from: data(json)
        ))

        XCTAssertEqual(item.id, "usda_2")
        XCTAssertEqual(item.sourceMetadata?.barcode, "0012345678905")
        XCTAssertEqual(item.sourceMetadata?.confidence, .databaseMatch)
    }

    func testAnalyticalUSDADataRetainsVerifiedConfidence() throws {
        let json = """
        {"foods": [{
          "fdcId": 3,
          "description": "Apple, raw",
          "dataType": "Foundation",
          "foodNutrients": [{"nutrientNumber": "208", "value": 52}]
        }]}
        """

        let item = try XCTUnwrap(try USDAFoodParser.foodItems(from: data(json)).first)
        XCTAssertEqual(item.sourceMetadata?.confidence, .verified)
    }

    func testBarcodeMatchRejectsSearchResultsWithoutMatchingGTIN() throws {
        let json = """
        {"foods": [
          {"fdcId": 1, "description": "No GTIN", "foodNutrients": []},
          {"fdcId": 2, "description": "Different Product", "gtinUpc": "9999999999994", "foodNutrients": []}
        ]}
        """

        XCTAssertNil(try USDAFoodParser.foodItem(
            matchingBarcode: "012345678905",
            from: data(json)
        ))
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try USDAFoodParser.foodItems(from: data("not json")))
    }
}
