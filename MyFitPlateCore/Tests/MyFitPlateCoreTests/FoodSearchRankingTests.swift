import XCTest
@testable import MyFitPlateCore

final class FoodSearchRankingTests: XCTestCase {
    func testRepeatSuggestionsPreferMealHistoryAndKeepDifferentPortions() {
        let usual = FoodItem(id: "usual", name: "Greek yogurt", calories: 140, servingSize: "1 cup", servingWeight: 180)
        var copy = usual
        copy.id = "recent-copy"
        var bigger = usual.scalingNutritionAndServing(by: 2)
        bigger.id = "bigger"
        bigger.servingSize = "2 cups"
        let saved = FoodItem(id: "saved", name: "Oats", calories: 200)
        let result = FoodSearchRanking.repeatSuggestions(recommended: [usual], saved: [saved], recent: [copy, bigger])
        XCTAssertEqual(result.map(\.id), ["usual", "saved", "bigger"])
    }

    func testTrustedLocalMatchesPreferSavedUserEditedFoods() {
        let saved = FoodItem(
            id: "saved",
            name: "Greek Yogurt Bowl",
            calories: 320,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
        let recent = FoodItem(
            id: "recent",
            name: "Plain Greek Yogurt",
            calories: 160,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recent,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "Recent"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "greek yogurt",
            savedFoods: [saved],
            recentFoods: [recent]
        )

        XCTAssertEqual(matches.map(\.id), ["saved", "recent"])
    }

    func testTrustedLocalMatchesDeduplicateSavedAndRecentFoods() {
        let food = FoodItem(id: "same", name: "Protein Bar", calories: 210)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "protein",
            savedFoods: [food],
            recentFoods: [food]
        )

        XCTAssertEqual(matches.map(\.id), ["same"])
    }

    func testTrustedLocalMatchesFindBarcodeCorrectionsByDigits() {
        let food = FoodItem(
            id: "barcode-food",
            name: "Saved Cereal",
            calories: 180,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                barcode: "00 123456"
            )
        )

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "123456",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertEqual(matches.first?.id, "barcode-food")
    }

    func testTrustedLocalMatchesIgnoreUnrelatedFoods() {
        let food = FoodItem(id: "banana", name: "Banana", calories: 105)

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "chicken",
            savedFoods: [food],
            recentFoods: []
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testLocalMatchesRespectFoodWordsAndSeparatelyReportedBrands() {
        let pineapple = FoodItem(id: "pineapple", name: "Pineapple", calories: 50)
        let apples = FoodItem(id: "apple", name: "Apples", calories: 52)
        XCTAssertEqual(FoodSearchRanking.trustedLocalMatches(query: "apple", savedFoods: [pineapple, apples], recentFoods: []).map(\.id), ["apple"])
        let yogurt = brandedFood(id: "fage", name: "Greek Yogurt", brand: "Fage")
        XCTAssertEqual(FoodSearchRanking.trustedLocalMatches(query: "fage greek yog", savedFoods: [yogurt], recentFoods: []).map(\.id), ["fage"])
    }

    func testVisibleOrderRefreshKeepsFirstUpdatedIdentityAndNewRows() {
        let old = FoodItem(id: "same", name: "Old preview", calories: 10)
        let refreshed = FoodItem(id: "same", name: "Updated preview", calories: 20)
        let duplicate = FoodItem(id: "same", name: "Later duplicate", calories: 30)
        let new = FoodItem(id: "new", name: "New", calories: 40)
        let result = FoodSearchRanking.preservingVisibleOrder(previous: [old], updated: [new, refreshed, duplicate])
        XCTAssertEqual(result.map(\.id), ["same", "new"])
        XCTAssertEqual(result.first?.calories, 20)
    }

    func testTrustedLocalMatchesDemoteNutritionThatNeedsCorrection() {
        let broken = FoodItem(
            id: "broken",
            name: "Protein Bowl",
            calories: 0,
            protein: 40,
            carbs: 40,
            fats: 10,
            servingWeight: 50,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .custom,
                confidence: .userVerified,
                reviewStatus: .userEdited,
                sourceName: "My Foods"
            )
        )
        let clean = FoodItem(
            id: "clean",
            name: "Protein Bowl",
            calories: 420,
            protein: 40,
            carbs: 40,
            fats: 11,
            servingWeight: 300
        ).withDatabaseSource(.usda, sourceName: "USDA FoodData Central")

        let matches = FoodSearchRanking.trustedLocalMatches(
            query: "protein bowl",
            savedFoods: [broken, clean],
            recentFoods: []
        )

        XCTAssertEqual(matches.map(\.id), ["clean", "broken"])
    }

    // MARK: - Search-source merging

    func testMergedResultsAppendDistinctUSDAAfterFatSecret() {
        let fatSecret = [
            FoodItem(id: "111", name: "Chicken Breast", calories: 165),
            FoodItem(id: "222", name: "Brand X Chicken Strips", calories: 210)
        ]
        let usda = [
            FoodItem(id: "usda_1", name: "Chicken Breast", calories: 165),
            FoodItem(id: "usda_2", name: "Chicken Thigh", calories: 209)
        ]

        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: fatSecret, usda: usda)

        XCTAssertEqual(merged.map(\.id), ["111", "222", "usda_2"], "Name collisions defer to FatSecret; distinct USDA appends")
    }

    func testMergedResultsPreferRicherExactNameCollision() {
        let fatSecret = [FoodItem(id: "111", name: "Banana Raw", calories: 89)]
        let usda = [FoodItem(
            id: "usda_1",
            name: "Banana Raw",
            calories: 89,
            calcium: 5,
            potassium: 358,
            vitaminC: 8.7
        )]

        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: fatSecret, usda: usda)

        XCTAssertEqual(merged.map(\.id), ["usda_1"])
        XCTAssertEqual(merged.first?.reportedMicronutrientCount, 3)
    }

    func testMergedResultsCapUSDAAdditions() {
        let usda = (0..<20).map { FoodItem(id: "usda_\($0)", name: "Food \($0)", calories: 100) }
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [], usda: usda, usdaLimit: 8)
        XCTAssertEqual(merged.count, 8)
    }

    func testMergedResultsIncludeOpenFoodFacts() {
        let fatSecret = [FoodItem(id: "fs_1", name: "Chicken Breast", calories: 165)]
        let usda = [FoodItem(id: "usda_1", name: "Chicken Thigh", calories: 209)]
        let off = [
            FoodItem(id: "off_1", name: "Chicken Breast", calories: 160), // duplicate name ignored
            FoodItem(id: "off_2", name: "Skyr Yogurt", calories: 120)
        ]

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: fatSecret,
            usda: usda,
            openFoodFacts: off
        )
        XCTAssertEqual(merged.map(\.id), ["fs_1", "usda_1", "off_2"])
    }

    func testMergedResultsIncludeHealthCanadaAndPreferItsRicherExactMatch() {
        let fatSecret = [FoodItem(id: "111", name: "Lentils Cooked", calories: 116)]
        let canada = [FoodItem(
            id: "cnf_1",
            name: "Lentils Cooked",
            calories: 116,
            protein: 9,
            carbs: 20,
            fats: 0.4,
            servingSize: "100 g",
            servingWeight: 100,
            iron: 3.3,
            potassium: 369,
            folate: 181,
            magnesium: 36
        )]

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: fatSecret,
            usda: [],
            healthCanada: canada
        )

        XCTAssertEqual(merged.map(\.id), ["cnf_1"])
        XCTAssertEqual(merged.first?.reportedMicronutrientCount, 4)
    }

    func testMergedResultsAttachHealthCanadaAgreementForGenericSearch() {
        let fatSecret = [
            FoodItem(
                id: "111",
                name: "Chicken Breast",
                calories: 165,
                protein: 31,
                carbs: 0,
                fats: 3.6,
                servingSize: "100 g",
                servingWeight: 100
            ).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "111")
        ]
        let canada = [
            FoodItem(
                id: "cnf_1",
                name: "Chicken, breast, meat only, roasted",
                calories: 165,
                protein: 31.02,
                carbs: 0,
                fats: 3.57,
                servingSize: "100 g",
                servingWeight: 100,
                potassium: 256,
                selenium: 27.6
            ).withDatabaseSource(
                .healthCanadaCNF,
                sourceName: "Health Canada CNF",
                sourceID: "cnf_1"
            )
        ]

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: fatSecret,
            usda: [],
            healthCanada: canada,
            query: "chicken breast"
        )

        XCTAssertEqual(
            merged.first?.sourceMetadata?.validatedCrossVerifiedBy,
            ["Health Canada CNF"]
        )
    }

    func testMergedResultsDoNotAttachAgreementForDifferentSearchIntent() {
        let chicken = FoodItem(
            id: "111",
            name: "Chicken Breast",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "111")
        let turkey = FoodItem(
            id: "cnf_2",
            name: "Turkey Breast",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: "cnf_2"
        )

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: [chicken],
            usda: [],
            healthCanada: [turkey],
            query: "chicken breast"
        )

        XCTAssertTrue(merged.first?.sourceMetadata?.validatedCrossVerifiedBy.isEmpty ?? true)
    }

    func testBroadSingleTokenSearchDoesNotCrossVerifyDifferentCuts() {
        let breast = FoodItem(
            id: "breast",
            name: "Chicken Breast",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "breast")
        let thigh = FoodItem(
            id: "thigh",
            name: "Chicken Thigh",
            calories: 165,
            protein: 31,
            carbs: 0,
            fats: 3.6,
            servingSize: "100 g",
            servingWeight: 100
        ).withDatabaseSource(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: "thigh"
        )

        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: [breast],
            usda: [],
            healthCanada: [thigh],
            query: "chicken"
        )

        XCTAssertTrue(merged.first?.sourceMetadata?.validatedCrossVerifiedBy.isEmpty ?? true)
    }

    func testRankedRemoteMatchesPreferPlainQueryBeforeIngredientMatches() {
        let foods = [
            FoodItem(id: "1", name: "Croissants, Apple", calories: 260),
            FoodItem(id: "2", name: "Apples, Raw, With Skin", calories: 52),
            FoodItem(id: "3", name: "Strudel, Apple", calories: 310)
        ]

        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "apple", foods: foods)

        XCTAssertEqual(ranked.first?.id, "2")
    }

    func testRelevantBrandedProductsPrecedeExactGenericFood() {
        let generic = FoodItem(id: "generic", name: "Greek yogurt", calories: 100)
        let branded = brandedFood(id: "brand", name: "Chobani Plain Greek Yogurt", brand: "Chobani")
        let unrelated = brandedFood(id: "unrelated", name: "Chobani Oat Milk", brand: "Chobani")
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: "greek yogurt", foods: [generic, unrelated, branded])
        XCTAssertEqual(ranked.map(\.id), ["brand", "generic", "unrelated"])
    }

    func testBrandPriorityDoesNotOverrideCompleteQueryOrSubstringIntent() {
        let generic = FoodItem(id: "apple", name: "Apples, raw", calories: 52)
        let pineapple = brandedFood(id: "pineapple", name: "Dole Pineapple", brand: "Dole")
        XCTAssertEqual(FoodSearchRanking.rankedRemoteMatches(query: "apple", foods: [pineapple, generic]).first?.id, "apple")
        let chicken = FoodItem(id: "breast", name: "Chicken breast", calories: 165)
        let nuggets = brandedFood(id: "nuggets", name: "Brand Chicken Nuggets", brand: "Brand")
        XCTAssertEqual(FoodSearchRanking.rankedRemoteMatches(query: "chicken breast", foods: [nuggets, chicken]).first?.id, "breast")
    }

    func testBrandQueryAndIncompleteLastTokenRemainSearchable() {
        let food = brandedFood(id: "chobani", name: "Plain Greek Yogurt", brand: "Chobani")
        let generic = FoodItem(id: "generic", name: "Greek Yogurt", calories: 100)
        XCTAssertEqual(FoodSearchRanking.rankedRemoteMatches(query: "chobani greek yog", foods: [generic, food]).first?.id, "chobani")
        XCTAssertEqual(FoodSearchRanking.rankedRemoteMatches(query: "greek yog", foods: [generic, food]).first?.id, "chobani")
    }

    func testMissingBrandPlaceholdersNeverReceiveProductPriority() {
        for placeholder in ["", "  ", "Generic", "UNBRANDED", "No Brand", "N/A", "Unknown", "Not specified"] {
            XCTAssertNil(FoodSearchRanking.reportedBrandName(placeholder))
            XCTAssertEqual(FoodSearchRanking.productDisplayName("Apple", brandName: placeholder), "Apple")
        }
        XCTAssertEqual(FoodSearchRanking.reportedBrandName("  Chobani  "), "Chobani")
        XCTAssertEqual(FoodSearchRanking.productDisplayName("Chobani Greek Yogurt", brandName: "chobani"), "Chobani Greek Yogurt")
    }

    func testRemoteBrandPriorityDoesNotChangeIntentionalPersonalMatches() {
        let personal = FoodItem(id: "personal", name: "Greek yogurt", calories: 100)
            .withSourceMetadata(.userEntered(sourceName: "My Foods"))
        let branded = brandedFood(id: "brand", name: "Chobani Greek Yogurt", brand: "Chobani")
        XCTAssertEqual(FoodSearchRanking.trustedLocalMatches(query: "greek yogurt", savedFoods: [personal], recentFoods: [branded]).first?.id, "personal")
    }

    func testEarlyGenericArrivalCannotRemainPinnedAboveLateBrandAfterCompletion() {
        let generic = FoodItem(id: "generic", name: "Greek Yogurt", calories: 100)
        let branded = brandedFood(id: "brand", name: "Chobani Greek Yogurt", brand: "Chobani")
        let first = FoodSearchRanking.publishingRemoteMatches(query: "greek yogurt", previous: [], updated: [generic], providersComplete: false)
        let updated = FoodSearchRanking.mergedSearchResults(fatSecret: [branded], usda: [generic], query: "greek yogurt")
        let loading = FoodSearchRanking.publishingRemoteMatches(query: "greek yogurt", previous: first, updated: updated, providersComplete: false)
        XCTAssertEqual(loading.map(\.id), ["generic", "brand"], "Loading must not shuffle existing rows on each arrival")
        let finished = FoodSearchRanking.publishingRemoteMatches(query: "greek yogurt", previous: loading, updated: updated, providersComplete: true)
        let oppositeArrival = FoodSearchRanking.publishingRemoteMatches(query: "greek yogurt", previous: [branded], updated: updated, providersComplete: true)
        XCTAssertEqual(finished.map(\.id), ["brand", "generic"])
        XCTAssertEqual(finished.map(\.id), oppositeArrival.map(\.id), "Final order is independent of provider timing")
    }

    func testBrandHomonymsAndGenericRecordsRemainSeparateDuringMerge() {
        let first = brandedFood(id: "first", name: "Greek Yogurt", brand: "Chobani")
        var generic = FoodItem(id: "generic", name: "Greek Yogurt", calories: 100)
        generic.sodium = 100; generic.potassium = 300
        let second = brandedFood(id: "second", name: "Greek Yogurt", brand: "Fage")
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [first], usda: [generic, second], query: "greek yogurt")
        XCTAssertEqual(merged.map(\.id), ["first", "generic", "second"])
        XCTAssertNil(merged.first?.sodium, "Generic micronutrients cannot replace a product's identity or nutrition")
        XCTAssertTrue(merged.first?.sourceMetadata?.validatedCrossVerifiedBy.isEmpty ?? true)
    }

    func testAgreementRequiresMatchingBrandedProductIdentity() {
        let first = brandedFood(id: "first", name: "Chobani Plain Greek Yogurt", brand: "Chobani")
        let same = brandedFood(id: "same", name: first.name, brand: "Chobani", source: .usda)
        let differentBrand = brandedFood(id: "other", name: first.name, brand: "Other", source: .openFoodFacts)
        let differentProduct = brandedFood(id: "variant", name: "Chobani Nonfat Greek Yogurt", brand: "Chobani", source: .usda)
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [first], usda: [same, differentProduct], openFoodFacts: [differentBrand], query: "greek yogurt")
        XCTAssertEqual(merged.first?.sourceMetadata?.validatedCrossVerifiedBy, ["USDA"])
    }

    func testBrandMetadataIsAdditiveAndLegacyValuesDecodeWithoutIt() throws {
        let old = FoodSourceMetadata.database(.fatSecret, sourceName: "FatSecret", sourceID: "123")
        let data = try JSONEncoder().encode(old)
        XCTAssertNil((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["brandName"], "Nil branding must not add a field to legacy payloads")
        let decoded = try JSONDecoder().decode(FoodSourceMetadata.self, from: data)
        XCTAssertNil(decoded.brandName)
        var branded = old; branded.brandName = "Chobani"
        XCTAssertEqual(try JSONDecoder().decode(FoodSourceMetadata.self, from: JSONEncoder().encode(branded)).brandName, "Chobani")
    }

    func testSameBrandNameCannotMergeOrCorroborateDifferentBarcodedProducts() {
        var first = brandedFood(id: "first", name: "Brand Greek Yogurt", brand: "Brand")
        first.sourceMetadata?.barcode = "012345678905"
        var second = brandedFood(id: "second", name: first.name, brand: "Brand", source: .usda)
        second.sourceMetadata?.barcode = "036000291452"
        second.sodium = 80
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [first], usda: [second], query: "greek yogurt")
        XCTAssertEqual(merged.map(\.id), ["first", "second"])
        XCTAssertNil(merged.first?.sodium)
        XCTAssertTrue(merged.first?.sourceMetadata?.validatedCrossVerifiedBy.isEmpty ?? true)
    }

    func testVisiblePresentationPromotesBrandsAboveGenericCatalogHistory() {
        let generic = FoodItem(id: "history", name: "Greek Yogurt, Nonfat", calories: 100)
            .withDatabaseSource(.usda, sourceName: "USDA")
        let branded = brandedFood(id: "chobani", name: "Chobani Greek Yogurt", brand: "Chobani")
        let remoteGeneric = FoodItem(id: "remote", name: "Yogurt", calories: 100)
        let sections = FoodSearchRanking.searchPresentation(query: "yogurt", trustedMatches: [generic],
            remoteMatches: [branded, remoteGeneric], providersComplete: true)
        XCTAssertTrue(sections.exactPersonalMatches.isEmpty)
        XCTAssertEqual(sections.brandedMatches.map(\.id), ["chobani"])
        XCTAssertEqual(sections.otherPersonalMatches.map(\.id), ["history"])
        XCTAssertEqual(sections.otherRemoteMatches.map(\.id), ["remote"])
        XCTAssertEqual(generic.name, "Greek Yogurt, Nonfat", "Presentation cannot rewrite saved history")
    }

    func testVisiblePresentationProtectsExactIntentionalPersonalFoodsButNotImportedGenerics() {
        let manual = FoodItem(id: "manual", name: "Yogurt", calories: 200)
            .withSourceMetadata(.userEntered())
        let recipe = FoodItem(id: "recipe", name: "Yogurt", calories: 300)
            .withDatabaseSource(.recipe, sourceName: "Recipe")
        let custom = FoodItem(id: "custom", name: "Yogurt", calories: 250)
            .withSourceMetadata(FoodSourceMetadata(sourceType: .custom, confidence: .userVerified, reviewStatus: .userConfirmed))
        let savedGeneric = FoodItem(id: "saved-generic", name: "Yogurt", calories: 100)
            .withSourceMetadata(FoodSourceMetadata(sourceType: .custom, originSourceType: .usda,
                confidence: .verified, reviewStatus: .userConfirmed))
        let edited = FoodItem(id: "edited", name: "Yogurt", calories: 123)
            .withSourceMetadata(FoodSourceMetadata(sourceType: .custom, originSourceType: .usda,
                confidence: .userVerified, reviewStatus: .userEdited))
        let branded = brandedFood(id: "brand", name: "Fage Yogurt", brand: "Fage")
        let sections = FoodSearchRanking.searchPresentation(query: "Yogurt", trustedMatches: [manual, recipe, custom, savedGeneric, edited],
            remoteMatches: [branded], providersComplete: true)
        XCTAssertEqual(sections.exactPersonalMatches.map(\.id), ["manual", "recipe", "custom", "edited"])
        XCTAssertEqual(sections.brandedMatches.map(\.id), ["brand"])
        XCTAssertEqual(sections.otherPersonalMatches.map(\.id), ["saved-generic"])
    }

    func testVisiblePresentationUsesWholeQueryWordsBeforeBrandPriority() {
        let apple = FoodItem(id: "apple", name: "Apple", calories: 52)
        let pineapple = brandedFood(id: "pineapple", name: "Dole Pineapple", brand: "Dole")
        let applewood = brandedFood(id: "bacon", name: "Brand Applewood Bacon", brand: "Brand")
        let weak = FoodSearchRanking.searchPresentation(query: "apple", trustedMatches: [apple],
            remoteMatches: [pineapple, applewood], providersComplete: true)
        XCTAssertTrue(weak.brandedMatches.isEmpty)
        XCTAssertEqual(weak.otherPersonalMatches.first?.id, "apple")
        let product = brandedFood(id: "motts", name: "Mott’s Apples", brand: "Mott’s")
        let strong = FoodSearchRanking.searchPresentation(query: "apple", trustedMatches: [apple],
            remoteMatches: [product, pineapple, applewood], providersComplete: true)
        XCTAssertEqual(strong.brandedMatches.map(\.id), ["motts"], "Extra brand/descriptors cannot demote a complete food-word match")
        XCTAssertEqual(strong.otherRemoteMatches.map(\.id), ["bacon"], "A typed prefix may match applewood, but never pineapple")
    }

    func testVisibleMatchesRespectBrandPercentagePreparationAndUnrelatedProviderResults() {
        let two = brandedFood(id: "two", name: "Total 2% Greek Yoghurt", brand: "FAGE")
        let twenty = brandedFood(id: "twenty", name: "Total 20% Greek yogurt", brand: "FAGE")
        let pineapple = brandedFood(id: "pineapple", name: "Pineapple", brand: "Dole")
        for settled in [false, true] {
            func matches(_ query: String, _ foods: [FoodItem]) -> [String] {
                let shown = FoodSearchRanking.searchPresentation(query: query, trustedMatches: [], remoteMatches: foods, providersComplete: settled)
                return (shown.brandedMatches + shown.otherRemoteMatches).map(\.id)
            }
            XCTAssertEqual(matches("fagé 2", [twenty, two, pineapple]), ["two"])
            XCTAssertEqual(matches("yogurt", [two, twenty, pineapple]), ["two", "twenty"])
            let raw = FoodItem(id: "raw", name: "Chicken breast, uncooked")
            let roasted = FoodItem(id: "roasted", name: "Roasted chicken breast")
            XCTAssertEqual(matches("raw chicken", [raw, roasted]), ["raw"])
            XCTAssertEqual(matches("cooked chicken", [raw, roasted]), ["roasted"])
        }
    }

    func testProviderPortionQueriesAndSingleBrandTyposStillFindTheCorrectProduct() {
        let chobani = brandedFood(id: "chobani", name: "Plain Greek Yogurt", brand: "Chobani")
        let quest = brandedFood(id: "quest", name: "Chocolate Brownie Protein Bar", brand: "Quest")
        let lays = brandedFood(id: "lays", name: "Classic Potato Chips", brand: "Lay’s")
        let other = brandedFood(id: "other", name: "Pineapple", brand: "Dole")
        for (query, expected) in [("1 cup of Chobani plain greek yogurt", "chobani"),
                                  ("Chobnai plain greek yogurt", "chobani"),
                                  ("Qest chocolate brownie protein bar", "quest"),
                                  ("28 g Lays classic potato chips", "lays")] {
            let visible = FoodSearchRanking.searchPresentation(query: query, trustedMatches: [],
                remoteMatches: [other, chobani, quest, lays], providersComplete: true)
            XCTAssertEqual(visible.brandedMatches.map(\.id), [expected], query)
            XCTAssertTrue(visible.otherRemoteMatches.isEmpty, query)
        }
    }

    func testVisiblePresentationKeepsLoadingSectionsStableAndPromotesOnlyWhenSettled() {
        let generic = FoodItem(id: "generic", name: "Greek Yogurt", calories: 100)
        let product = brandedFood(id: "brand", name: "Chobani Greek Yogurt", brand: "Chobani")
        let loading = FoodSearchRanking.searchPresentation(query: "greek yog", trustedMatches: [generic],
            remoteMatches: [product], providersComplete: false)
        XCTAssertTrue(loading.brandedMatches.isEmpty)
        XCTAssertEqual(loading.otherPersonalMatches.map(\.id), ["generic"])
        XCTAssertEqual(loading.otherRemoteMatches.map(\.id), ["brand"])
        let settled = FoodSearchRanking.searchPresentation(query: "greek yog", trustedMatches: [generic],
            remoteMatches: [product], providersComplete: true)
        XCTAssertEqual(settled.brandedMatches.map(\.id), ["brand"])
    }

    func testVisiblePresentationDoesNotDuplicateSameProductAcrossSections() {
        let product = brandedFood(id: "brand", name: "Chobani Greek Yogurt", brand: "Chobani")
        let sections = FoodSearchRanking.searchPresentation(query: "yogurt", trustedMatches: [product],
            remoteMatches: [product], providersComplete: true)
        XCTAssertEqual(sections.brandedMatches.map(\.id), ["brand"])
        XCTAssertTrue(sections.otherPersonalMatches.isEmpty)
        XCTAssertTrue(sections.otherRemoteMatches.isEmpty)
    }

    func testPrintedSizeAndFlavorSurviveMergedCatalogCapsAndHomonyms() {
        func yogurt(_ id: String, _ flavor: String, _ serving: String) -> FoodItem {
            FoodItem(id: id, name: flavor + " Greek Yogurt", calories: 90, servingSize: serving)
                .withDatabaseSource(.usda, sourceName: "USDA", brandName: "Chobani")
        }
        let small = yogurt("small", "Vanilla", "1 container (5.3 oz)")
        let bulk = yogurt("bulk", "Vanilla", "32 oz")
        let strawberry = yogurt("berry", "Strawberry", "5.3 ounces")
        let query = "Chobani vanilla greek yog 5.3oz"
        XCTAssertEqual(FoodSearchRanking.catalogQuery(query), "Chobani vanilla greek yog")
        let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [bulk], usda: [strawberry, small], query: query, usdaLimit: 1)
        let ranked = FoodSearchRanking.rankedRemoteMatches(query: query, foods: merged)
        XCTAssertEqual(FoodSearchRanking.searchPresentation(query: query, trustedMatches: [], remoteMatches: ranked, providersComplete: true).brandedMatches.map(\.id), ["small"])
        XCTAssertTrue(FoodSearchRanking.trustedLocalMatches(query: "Chobani vanilla 3 oz", savedFoods: [small], recentFoods: []).isEmpty)
        XCTAssertEqual(FoodSearchRanking.catalogQuery("100 g plain yogurt"), "100 g plain yogurt")
    }

    private func brandedFood(id: String, name: String, brand: String, source: FoodSourceType = .fatSecret) -> FoodItem {
        let sourceName: String
        switch source {
        case .usda: sourceName = "USDA FoodData Central"
        case .openFoodFacts: sourceName = "Open Food Facts"
        default: sourceName = "FatSecret"
        }
        return FoodItem(id: id, name: name, calories: 100, protein: 10, carbs: 10, fats: 2, servingSize: "100 g", servingWeight: 100)
            .withDatabaseSource(source, sourceName: sourceName, sourceID: id, brandName: brand)
    }

    // MARK: - Quick-log hydration

    private var fatSecretPreview: FoodItem {
        // What mapSearchResultToFoodItem produces: numeric id, macros from the description
        // string, no micronutrients.
        FoodItem(id: "12345", name: "Oatmeal", calories: 150, protein: 5, carbs: 27, fats: 3, servingSize: "1 cup")
    }

    func testNeedsHydrationOnlyForMicrolessFatSecretIDs() {
        XCTAssertTrue(FoodSearchRanking.needsNutritionHydration(fatSecretPreview))

        var withMicros = fatSecretPreview
        withMicros.potassium = 140
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(withMicros))

        let usdaItem = FoodItem(id: "usda_999", name: "Oats", calories: 150)
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(usdaItem), "USDA ids never hydrate via FatSecret")

        let customItem = FoodItem(id: UUID().uuidString, name: "My Oats", calories: 150)
        XCTAssertFalse(FoodSearchRanking.needsNutritionHydration(customItem))
    }

    func testHydratedQuickLogPrefersServingMatchingThePreview() {
        let base = FoodItem(id: "12345", name: "Oatmeal", calories: 379, protein: 13, carbs: 67, fats: 6.5,
                            servingSize: "100 g", servingWeight: 100, potassium: 429, sodium: 2)
        let cupServing = ServingSizeOption(
            description: "1 cup", servingWeightGrams: 40,
            calories: 150, protein: 5.2, carbs: 27, fats: 2.6,
            potassium: 172, sodium: 1
        )
        let hundredGrams = ServingSizeOption(
            description: "100 g", servingWeightGrams: 100,
            calories: 379, protein: 13, carbs: 67, fats: 6.5,
            potassium: 429, sodium: 2
        )

        let hydrated = FoodSearchRanking.hydratedQuickLogItem(
            preview: fatSecretPreview,
            detailBase: base,
            availableServings: [hundredGrams, cupServing]
        )

        XCTAssertEqual(hydrated.servingSize, "1 cup", "The serving the search row previewed wins")
        XCTAssertEqual(hydrated.calories, 150, accuracy: 0.001)
        XCTAssertEqual(hydrated.potassium ?? 0, 172, accuracy: 0.001, "Micros ride along at the matched serving")
    }

    func testHydratedQuickLogFallsBackToDetailBase() {
        let base = FoodItem(id: "12345", name: "Oatmeal", calories: 379, servingSize: "100 g",
                            servingWeight: 100, potassium: 429)
        var preview = fatSecretPreview
        preview.servingSize = "Tap to see details"

        let hydrated = FoodSearchRanking.hydratedQuickLogItem(
            preview: preview,
            detailBase: base,
            availableServings: []
        )

        XCTAssertEqual(hydrated.servingSize, "100 g")
        XCTAssertEqual(hydrated.potassium ?? 0, 429, accuracy: 0.001)
    }
}
