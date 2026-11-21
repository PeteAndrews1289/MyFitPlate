import XCTest
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class FoodSearchPipelineTests: XCTestCase {
    private typealias Provider = FoodSearchResultCache.Provider
    private var priorAuth: AuthServiceProtocol?
    private var auth: MockAuthService!
    private var model: FoodSearchViewModel!
    private var probe: ProviderProbe!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        priorAuth = DIContainer.shared.authService
        auth = MockAuthService()
        auth.currentUserID = "wave4-search-\(UUID().uuidString)"
        DIContainer.shared.authService = auth
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        probe = ProviderProbe()
        let providerProbe = probe!
        model = FoodSearchViewModel(draftStore: EditorDraftStore(directory: directory), searchLoader: { provider, query in
            await providerProbe.load(provider, query: query)
        })
        model.fetchData()
    }

    override func tearDown() {
        model.searchText = ""
        probe.finishAll()
        model = nil; probe = nil
        DIContainer.shared.authService = priorAuth
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testReturningQueryPublishesImmediatelyWithoutRepeatingProviders() async throws {
        model.searchText = "greek yogurt"
        model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        probe.finishAll(food: product("fresh"))
        try await waitUntil { !self.model.isLoading }
        XCTAssertEqual(model.searchPresentation.brandedMatches.first?.id, "fresh")
        model.searchText = ""
        model.searchText = "  GREEK   YOGURT "
        XCTAssertFalse(model.isLoading, "A fresh return query must not incur another debounce or spinner")
        XCTAssertEqual(model.searchResults.first?.id, "fresh")
        model.submitSearch()
        await Task.yield()
        XCTAssertEqual(probe.calls.count, 5, "Expanded successful responses are reusable too")
        XCTAssertEqual(model.searchResults.first?.calories, 100)
    }

    func testChangingPrintedSizeReusesCatalogCandidatesAndKeepsSupplementQuerySpecific() async throws {
        let base = "Chobani vanilla yogurt"
        model.searchText = base
        model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        let foods = [("small", "5.3 oz"), ("large", "32 oz")].map { id, serving in
            FoodItem(id: id, name: "Vanilla Yogurt", calories: 100, servingSize: serving)
                .withDatabaseSource(.usda, sourceName: "USDA", brandName: "Chobani")
        }
        probe.finish(provider: .usda, query: base, result: .success(foods))
        probe.finishAll()
        try await waitUntil { !self.model.isLoading }

        model.searchText = base + " 5.3oz"
        XCTAssertEqual(model.searchPresentation.brandedMatches.map(\.id), ["small"])
        model.searchText = base + " 32 oz"
        XCTAssertEqual(model.searchPresentation.brandedMatches.map(\.id), ["large"])
        model.submitSearch()
        try await waitUntil { self.probe.calls.count == 6 }
        XCTAssertEqual(probe.calls.last?.provider, .supplements)
        XCTAssertEqual(probe.calls.last?.query, base + " 32 oz")
        probe.finishAll()
    }

    func testExplicitSearchAddsOptionalProvidersWithoutRestartingBaseRequestsOrClearingRows() async throws {
        model.searchText = "greek yogurt"
        try await waitUntil { self.probe.calls.count == 3 }
        probe.finish(provider: .fatSecret, query: "greek yogurt", result: .success([product("brand")]))
        try await waitUntil { !self.model.searchResults.isEmpty }
        model.submitSearch()
        XCTAssertEqual(model.searchResults.first?.id, "brand")
        model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        XCTAssertEqual(probe.calls.filter { $0.provider == .fatSecret }.count, 1)
        XCTAssertEqual(probe.calls.filter { $0.provider == .usda }.count, 1)
        XCTAssertEqual(probe.calls.filter { $0.provider == .healthCanada }.count, 1)
        probe.finish(provider: .usda, query: "greek yogurt", result: .success([]))
        probe.finish(provider: .healthCanada, query: "greek yogurt", result: .success([]))
        try await waitUntil { !self.model.searchPresentation.brandedMatches.isEmpty }
        XCTAssertTrue(model.isLoading, "Brand priority should not wait for the supplement source")
        probe.finishAll()
        try await waitUntil { !self.model.isLoading }
    }

    func testRetryOnlyRestartsFailedProvidersAndDoesNotCacheFailureAsAnEmptySuccess() async throws {
        model.searchText = "greek yogurt"
        model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        probe.finish(provider: .usda, query: "greek yogurt", result: .failure(ProbeError.unavailable))
        probe.finishAll(food: product("brand"))
        try await waitUntil { !self.model.isLoading }
        XCTAssertNotNil(model.searchCoverageMessage)
        model.retrySearchSources()
        model.retrySearchSources()
        try await waitUntil { self.probe.calls.count == 6 }
        XCTAssertEqual(probe.calls.last?.provider, .usda)
        XCTAssertEqual(model.searchResults.first?.id, "brand")
        probe.finishAll()
        try await waitUntil { !self.model.isLoading }
        XCTAssertNil(model.searchErrorMessage)
        XCTAssertNil(model.searchCoverageMessage)
        model.searchText = ""
        model.searchText = "greek yogurt"
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(probe.calls.count, 6)
    }

    func testRetryWhileTypingKeepsAvailableRowsAndRetriesOnlyTheMissingPrimarySource() async throws {
        model.searchText = "greek yogurt"
        try await waitUntil { self.probe.calls.count == 3 }
        probe.finish(provider: .healthCanada, query: "greek yogurt", result: .failure(ProbeError.unavailable))
        probe.finishAll(food: product("available"))
        try await waitUntil { !self.model.isLoading }
        model.retrySearchSources()
        try await waitUntil { self.probe.calls.count == 4 }
        XCTAssertEqual(probe.calls.last?.provider, .healthCanada)
        XCTAssertEqual(model.searchResults.first?.id, "available")
        probe.finishAll()
        try await waitUntil { !self.model.isLoading }
        XCTAssertNil(model.searchCoverageMessage)
    }

    func testSameQueryOldGenerationCannotReplaceNewerResultsOrPoisonItsCache() async throws {
        model.searchText = "greek yogurt"; model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        model.searchText = "apple"; model.submitSearch()
        try await waitUntil { self.probe.calls.count == 10 }
        model.searchText = "greek yogurt"; model.submitSearch()
        try await waitUntil { self.probe.calls.count == 15 }
        probe.finish(indices: Array(0..<10), food: product("stale"))
        await Task.yield()
        XCTAssertTrue(model.searchResults.isEmpty)
        probe.finish(indices: Array(10..<15), food: product("current"))
        try await waitUntil { !self.model.isLoading }
        XCTAssertEqual(model.searchResults.map(\.id), ["current"])
        model.searchText = ""; model.searchText = "greek yogurt"
        XCTAssertEqual(model.searchResults.map(\.id), ["current"])
        XCTAssertFalse(model.isLoading)
    }

    func testAccountChangeClearsCatalogCacheAndRejectsPreviousAccountCompletion() async throws {
        model.searchText = "greek yogurt"; model.submitSearch()
        try await waitUntil { self.probe.calls.count == 5 }
        probe.finish(provider: .fatSecret, query: "greek yogurt", result: .success([product("old-account")]))
        try await waitUntil { !self.model.searchResults.isEmpty }
        auth.currentUserID = "wave4-search-new-\(UUID().uuidString)"
        model.fetchData()
        XCTAssertEqual(model.searchText, "")
        XCTAssertTrue(model.searchResults.isEmpty)
        model.searchText = "greek yogurt"; model.submitSearch()
        try await waitUntil { self.probe.calls.count == 10 }
        probe.finish(indices: Array(0..<5), food: product("late-old"))
        await Task.yield()
        XCTAssertTrue(model.searchResults.isEmpty)
        probe.finish(indices: Array(5..<10), food: product("new-account"))
        try await waitUntil { !self.model.isLoading }
        XCTAssertEqual(model.searchResults.map(\.id), ["new-account"])
    }

    func testLocalRankingRefreshesWhenSavedOrRecentFoodChanges() {
        model.searchText = "apple"
        model.savedFoods = [FoodItem(id: "saved", name: "Apple", calories: 52)]
        XCTAssertEqual(model.trustedSearchResults.first?.calories, 52)
        model.savedFoods = [FoodItem(id: "saved", name: "Apple", calories: 80)]
        XCTAssertEqual(model.trustedSearchResults.first?.calories, 80)
        model.savedFoods = []
        model.recentFoods = [FoodItem(id: "recent", name: "Apples", calories: 60)]
        XCTAssertEqual(model.trustedSearchResults.map(\.id), ["recent"])
        model.recentFoods = []
        XCTAssertTrue(model.trustedSearchResults.isEmpty)
    }

    private func product(_ id: String) -> FoodItem {
        FoodItem(id: id, name: "Chobani Greek Yogurt", calories: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", brandName: "Chobani")
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(condition(), "Provider state did not settle")
    }

    private enum ProbeError: Error { case unavailable }

    @MainActor
    private final class ProviderProbe {
        struct Call {
            let provider: Provider
            let query: String
            var completion: CheckedContinuation<Result<[FoodItem], Error>, Never>?
        }
        var calls: [Call] = []

        func load(_ provider: Provider, query: String) async -> Result<[FoodItem], Error> {
            await withCheckedContinuation { continuation in
                calls.append(Call(provider: provider, query: query, completion: continuation))
            }
        }

        func finish(provider: Provider, query: String, result: Result<[FoodItem], Error>) {
            guard let index = calls.firstIndex(where: { $0.provider == provider && $0.query == query && $0.completion != nil }) else { return }
            let completion = calls[index].completion
            calls[index].completion = nil
            completion?.resume(returning: result)
        }

        func finish(indices: [Int], food: FoodItem? = nil) {
            for index in indices where calls.indices.contains(index) {
                let completion = calls[index].completion
                calls[index].completion = nil
                let foods = calls[index].provider == .fatSecret ? food.map { [$0] } ?? [] : []
                completion?.resume(returning: .success(foods))
            }
        }

        func finishAll(food: FoodItem? = nil) { finish(indices: Array(calls.indices), food: food) }
    }
}
