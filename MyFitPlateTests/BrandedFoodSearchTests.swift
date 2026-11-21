import XCTest
@testable import MyFitPlate
import MyFitPlateCore

@MainActor
final class BrandedFoodSearchTests: XCTestCase {
    /// Opt-in read-only check of the ordinary submitted search, including provider failures.
    func testLiveProductVariantsWhenRequested() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MFP_LIVE_BRANDS"] == "1")
        let queries = [
            ("Chobani vanilla greek yogurt", ["chobani", "vanilla", "greek", "yogurt"]),
            ("Chobani strawberry greek yog", ["chobani", "strawberry", "greek", "yogurt"]),
            ("Fairlife chocolate milk", ["fairlife", "chocolate", "milk"]),
            ("Oikos triple zero van", ["oikos", "triple", "zero", "vanilla"]),
            ("Chobani vanilla greek yogurt 5.3 oz", ["chobani", "vanilla", "greek", "yogurt", "5.3", "oz"]),
            ("Fage total 2% greek yogurt", ["fage", "total", "2%", "greek", "yogurt"]),
            ("Quaker old fashioned oats 42 oz", ["quaker", "old", "fashioned", "oats", "42", "oz"]),
            ("Fairlife chocolate milk 52 fl oz", ["fairlife", "chocolate", "milk", "52", "oz"]),
            ("Fage strawberry greek yogurt 5.3 oz", ["fage", "strawberry", "greek", "yogurt", "5.3", "oz"])
        ]
        // Public USDA package codes declared before the run. A family-name match
        // alone cannot pass any of these three exact-package checks.
        let packages = ["Quaker old fashioned oats 42 oz": ["00030000010402", "00030000432938"],
                        "Fairlife chocolate milk 52 fl oz": ["00856312002795"],
                        "Fage strawberry greek yogurt 5.3 oz": ["00689544081463"]]
        let suite = "brand-benchmark-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let priorCloud = DIContainer.shared.cloudFunctionService
        DIContainer.shared.cloudFunctionService = FirebaseCloudFunctionService()
        defer { DIContainer.shared.cloudFunctionService = priorCloud }
        let catalogs = FoodSearchViewModel(defaults: defaults)
        var statuses: [String: String] = [:]
        let loader: FoodSearchViewModel.SearchLoader = { provider, query in
            let result = await catalogs.loadSearchProvider(provider, query: query)
            switch result {
            case .success(let foods): statuses[String(describing: provider)] = String(foods.count)
            case .failure: statuses[String(describing: provider)] = "unavailable"
            }
            return result
        }
        for (query, expected) in queries {
            let model = FoodSearchViewModel(defaults: defaults, searchLoader: loader)
            statuses.removeAll()
            let start = Date()
            model.searchText = query
            model.submitSearch()
            var firstMatchMS: Int?
            var rank: Int?
            repeat {
                let presentation = model.searchPresentation
                let visible = presentation.brandedMatches + presentation.otherRemoteMatches
                rank = visible.prefix(5).firstIndex { food in
                    let title = food.name.lowercased()
                    let identity = title + " " + (food.sourceMetadata?.brandName?.lowercased() ?? "")
                    let description = identity + " " + food.servingSize.lowercased()
                    if let targets = packages[query] {
                        guard let barcode = food.sourceMetadata?.barcode else { return false }
                        let codes = Set(BarcodeCorrectionRules.lookupCandidates(for: barcode))
                        return targets.contains { !codes.isDisjoint(with: BarcodeCorrectionRules.lookupCandidates(for: $0)) }
                    }
                    return expected.allSatisfy { description.contains($0) }
                }.map { $0 + 1 }
                if rank != nil && firstMatchMS == nil { firstMatchMS = Int(-start.timeIntervalSinceNow * 1000) }
                if !model.isLoading { break }
                try await Task.sleep(for: .milliseconds(100))
            } while -start.timeIntervalSinceNow < 30
            print("LIVE_BRAND query=\(query) rank=\(rank.map(String.init) ?? "miss") first_ms=\(firstMatchMS.map(String.init) ?? "none") settled=\(!model.isLoading) partial=\(model.searchCoverageMessage != nil || model.searchErrorMessage != nil) count=\(model.searchResults.count) sources=\(statuses)")
            model.searchText = ""
            let wait = max(0, 7 + start.timeIntervalSinceNow)
            try await Task.sleep(for: .seconds(wait))
        }
    }

    func testProviderArrivalOrderPublishesBrandFirstAfterCompletionAndKeepsGenericFallback() {
        let viewModel = FoodSearchViewModel()
        viewModel.activeSearchQuery = "yogurt"
        let generic = FoodItem(id: "generic", name: "Greek Yogurt", calories: 100)
        let branded = FoodItem(id: "brand", name: "Chobani Greek Yogurt", calories: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", brandName: "Chobani")
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [1: [generic]], providersComplete: false)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["generic"])
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [0: [branded], 1: [generic]], providersComplete: false)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["generic", "brand"])
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [0: [branded], 1: [generic]], providersComplete: true)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["brand", "generic"])
        XCTAssertEqual(viewModel.searchResults[1].calories, 100)
    }

    func testOldProviderCompletionCannotReplaceNewQueryResults() {
        let viewModel = FoodSearchViewModel()
        viewModel.activeSearchQuery = "apple"
        let apple = FoodItem(id: "apple", name: "Apple", calories: 52)
        viewModel.publishRemoteSearchBatches(query: "apple", batches: [1: [apple]], providersComplete: true)
        let yogurt = FoodItem(id: "brand", name: "Chobani Greek Yogurt", calories: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", brandName: "Chobani")
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [0: [yogurt]], providersComplete: true)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["apple"])
    }

    func testVisibleSectionsPutRemoteProductAheadOfGenericPersonalHistory() {
        let viewModel = FoodSearchViewModel()
        viewModel.searchText = "yogurt"
        defer { viewModel.searchText = "" }
        let generic = FoodItem(id: "usual-generic", name: "Greek Yogurt, Nonfat", calories: 100)
            .withDatabaseSource(.usda, sourceName: "USDA")
        let branded = FoodItem(id: "brand", name: "Chobani Greek Yogurt", calories: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", brandName: "Chobani")
        viewModel.savedFoods = [generic]
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [0: [branded]], providersComplete: false)
        XCTAssertTrue(viewModel.searchPresentation.brandedMatches.isEmpty)
        XCTAssertEqual(viewModel.searchPresentation.otherPersonalMatches.map(\.id), ["usual-generic"])
        viewModel.publishRemoteSearchBatches(query: "yogurt", batches: [0: [branded]], providersComplete: true)
        viewModel.isLoading = false
        XCTAssertEqual(viewModel.searchPresentation.brandedMatches.map(\.id), ["brand"])
        XCTAssertEqual(viewModel.searchPresentation.otherPersonalMatches.map(\.id), ["usual-generic"])
        XCTAssertEqual(viewModel.savedFoods.first?.calories, 100)
    }

    func testExactManualFoodRemainsAboveProviderBrandInVisibleSections() {
        let viewModel = FoodSearchViewModel()
        viewModel.searchText = "yogurt"
        defer { viewModel.searchText = "" }
        let personal = FoodItem(id: "manual", name: "Yogurt", calories: 123)
            .withSourceMetadata(.userEntered())
        let product = FoodItem(id: "brand", name: "Chobani Greek Yogurt", calories: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", brandName: "Chobani")
        viewModel.savedFoods = [personal]
        viewModel.searchResults = [product]
        viewModel.isLoading = false
        XCTAssertEqual(viewModel.searchPresentation.exactPersonalMatches.map(\.id), ["manual"])
        XCTAssertEqual(viewModel.searchPresentation.brandedMatches.map(\.id), ["brand"])
    }
}
