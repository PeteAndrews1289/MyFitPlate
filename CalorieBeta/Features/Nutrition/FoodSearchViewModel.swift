import SwiftUI
import Combine
import MyFitPlateCore

@MainActor
class FoodSearchViewModel: ObservableObject {
    private static let unavailableMessage = String(
        localized: "We couldn't reach the food databases. Your saved and recent foods still work."
    )

    @Published var searchText = ""
    @Published var selectedMeal: String
    
    @Published var searchResults: [FoodItem] = []
    @Published var supplementResults: [FoodItem] = []
    @Published var isLoading = false
    @Published var searchErrorMessage: String?
    @Published var searchCoverageMessage: String?
    @Published var activeSearchQuery = ""
    @Published var quickLoggedFoodIDs: Set<String> = []
    @Published var loggingFoodIDs: Set<String> = []
    @Published var isRepeating = false
    @Published var lastLogMessage: String?
    @Published var lastLogSucceeded = false
    @Published var recentSearches: [String] = []
    @Published var canRetryLog = false
    private var quickLogQueue: QuickFoodLogQueue?
    private var lastUndoID: UUID?
    private let defaults: UserDefaults
    private let draftStore: EditorDraftStore
    @Published var isBuildingMeal = false {
        didSet {
            if isBuildingMeal, let mealDraft { selectedMeal = mealDraft.mealName }
        }
    }
    @Published private(set) var mealDraft: FoodLoggingDraft?
    @Published private(set) var draftMessage: String?
    @Published private(set) var isSavingDraft = false
    private var didLoadMealDraft = false
    private var unreadableMealDraft = false
    private let mealDraftScope = "food-logging-meal"

    var selectedFoodIDs: Set<String> {
        isBuildingMeal ? Set(mealDraft?.entries.map(\.sourceID) ?? []) : quickLoggedFoodIDs
    }

    var canUndoQuickLog: Bool {
        lastUndoID != nil && lastUndoID == dailyLogService?.undoChangeID
    }

    var usualFoods: [FoodItem] {
        let foods = FoodSearchRanking.repeatSuggestions(recommended: recommendedFoods, saved: savedFoods, recent: recentFoods)
        guard let loadedUserID, loadedUserID == DIContainer.shared.authService.currentUserID else { return foods }
        let memory = FoodServingPreferences(defaults: defaults)
        return FoodSearchRanking.repeatSuggestions(recommended: foods.map { memory.preferred($0, userID: loadedUserID) }, saved: [], recent: [])
    }

    func resetUsualServings() {
        guard let loadedUserID, loadedUserID == DIContainer.shared.authService.currentUserID else { return }
        FoodServingPreferences(defaults: defaults).clear(userID: loadedUserID)
        objectWillChange.send()
    }

    var previousDayLabel: String {
        guard let previous = yesterdaysSourceDay else { return "Previous day" }
        if previous.calendar.isDateInYesterday(previous.displayDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = previous.calendar; formatter.timeZone = previous.timeZone; formatter.dateStyle = .medium
        return formatter.string(from: previous.displayDate)
    }
    
    @Published var savedFoods: [FoodItem] = [] { didSet { localSearchRevision &+= 1 } }
    @Published var recentFoods: [FoodItem] = [] { didSet { localSearchRevision &+= 1 } }
    @Published var recommendedFoods: [FoodItem] = []
    
    @Published var yesterdaysMealItems: [FoodItem] = []
    @Published var yesterdaysLog: DailyLog?
    @Published private(set) var yesterdaysSourceDay: DiaryDayContext?
    @Published private(set) var yesterdaysDestinationDay: DiaryDayContext?
    @Published var isFetchingYesterday = false

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var yesterdaysDayItems: [FoodItem] {
        yesterdaysLog?.meals.flatMap(\.foodItems) ?? []
    }

    var hasYesterdayFoods: Bool {
        !yesterdaysMealItems.isEmpty || !yesterdaysDayItems.isEmpty
    }

    var trustedSearchResults: [FoodItem] {
        let query = FoodSearchResultCache.queryKey(searchText)
        if let cachedLocalMatches, cachedLocalMatches.query == query,
           cachedLocalMatches.revision == localSearchRevision { return cachedLocalMatches.foods }
        let matches = FoodSearchRanking.trustedLocalMatches(query: searchText, savedFoods: savedFoods, recentFoods: recentFoods)
        cachedLocalMatches = (query, localSearchRevision, matches)
        return matches
    }

    var searchPresentation: FoodSearchRanking.SearchPresentation {
        FoodSearchRanking.searchPresentation(query: searchText, trustedMatches: trustedSearchResults,
            remoteMatches: searchResults, providersComplete: hasCompletedPrimarySearch || !isLoading)
    }

    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()
    private let healthCanadaService = HealthCanadaFoodAPIService()
    private let supplementService = NIHDietarySupplementAPIService()
    private let openFoodFactsService = OpenFoodFactsAPIService()
    private var cancellables = Set<AnyCancellable>()
    private var dailyLogService: DailyLogService?
    typealias SearchProvider = FoodSearchResultCache.Provider
    typealias SearchLoader = @MainActor (SearchProvider, String) async -> Result<[FoodItem], Error>
    private let searchLoader: SearchLoader?
    private var searchTask: Task<Void, Never>?
    private var providerTasks: [SearchProvider: Task<Void, Never>] = [:]
    private var searchGeneration = UUID()
    private var searchOwnerID: String?
    private var searchCache = FoodSearchResultCache()
    private var activeProviderBatches: [SearchProvider: [FoodItem]] = [:]
    private var requestedProviders = Set<SearchProvider>()
    private var failedProviders = Set<SearchProvider>()
    private var hasCompletedPrimarySearch = false
    private var localSearchRevision: UInt = 0
    private var cachedLocalMatches: (query: String, revision: UInt, foods: [FoodItem])?
    private var loadedUserID: String?
    private var savedFoodsRequestID: UUID?
    private var recentFoodsRequestID: UUID?
    private var recommendedFoodsRequestID: UUID?
    private var yesterdayRequestID: UUID?
    private var repeatFeedbackID: UUID?

    private let trainingFuelTarget: TrainingFuelTarget?

    init(selectedMeal: String? = nil, defaults: UserDefaults = .standard, draftStore: EditorDraftStore = EditorDraftStore(), trainingFuelTarget: TrainingFuelTarget? = nil, searchLoader: SearchLoader? = nil) {
        self.searchLoader = searchLoader
        self.trainingFuelTarget = trainingFuelTarget
        self.selectedMeal = selectedMeal ?? Self.defaultMealName()
        self.defaults = defaults
        self.draftStore = draftStore
        setupSearchDebounce()
    }

    func setup(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    // MARK: - Search Pipeline

    private func setupSearchDebounce() {
        $searchText
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .sink { [weak self] query in
                self?.handleSearchQueryChange(query)
            }
            .store(in: &cancellables)
    }

    func handleSearchQueryChange(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        beginSearchQuery(trimmed)
        guard trimmed.count >= 2 else { return }
        requestedProviders = SearchProvider.primary
        updateSearchProgress()
        guard isLoading else { return }
        let generation = searchGeneration
        // Personal and still-fresh catalog results publish immediately. Only new remote
        // requests wait for typing to settle.
        searchTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self, self.searchGeneration == generation else { return }
            self.searchByQuery(query: trimmed, includeOpenFoodFacts: false)
        }
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        if query != activeSearchQuery || searchOwnerID != DIContainer.shared.authService.currentUserID {
            beginSearchQuery(query)
        }
        searchTask?.cancel()
        activeProviderBatches = cachedBatches(for: query)
        rememberSearch(query)
        searchByQuery(query: query, includeOpenFoodFacts: true)
    }

    func retrySearchSources() {
        guard !isLoading, !failedProviders.isEmpty, !activeSearchQuery.isEmpty,
              searchOwnerID == DIContainer.shared.authService.currentUserID else { return }
        searchByQuery(query: activeSearchQuery, includeOpenFoodFacts: requestedProviders.contains(.openFoodFacts))
    }

    private func beginSearchQuery(_ query: String) {
        cancelSearchRequests()
        let owner = DIContainer.shared.authService.currentUserID
        if owner != searchOwnerID { searchCache.removeAll() }
        searchOwnerID = owner
        activeSearchQuery = query.count >= 2 ? query : ""
        searchResults = []
        supplementResults = []
        isLoading = false
        searchErrorMessage = nil
        searchCoverageMessage = nil
        hasCompletedPrimarySearch = false
        requestedProviders = []
        failedProviders = []
        activeProviderBatches = query.count >= 2 ? cachedBatches(for: query) : [:]
    }

    private func cancelSearchRequests() {
        searchGeneration = UUID()
        searchTask?.cancel()
        searchTask = nil
        providerTasks.values.forEach { $0.cancel() }
        providerTasks = [:]
    }

    func selectRecentSearch(_ query: String) {
        searchText = query
        submitSearch()
    }

    func clearRecentSearches() {
        recentSearches = []
        if let key = recentSearchKey { defaults.removeObject(forKey: key) }
    }

    private var recentSearchKey: String? {
        AccountScopedStorageKey.make(prefix: "food-searches", userID: loadedUserID)
    }

    private func rememberSearch(_ query: String) {
        guard let key = recentSearchKey, query.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(String(query.prefix(100)), at: 0)
        recentSearches = Array(recentSearches.prefix(5))
        defaults.set(recentSearches, forKey: key)
    }

    private func providerQuery(_ query: String, for provider: SearchProvider) -> String {
        provider == .supplements ? query : FoodSearchRanking.catalogQuery(query)
    }

    /// Food catalogs return the whole product family. A different printed size
    /// can reuse those candidates; the visible ranking still applies the full query.
    private func cachedBatches(for query: String) -> [SearchProvider: [FoodItem]] {
        let family = FoodSearchRanking.catalogQuery(query)
        var batches = searchCache.batches(for: family)
        if family != query {
            batches[.supplements] = searchCache.batches(for: query)[.supplements]
        }
        return batches
    }

    private func searchByQuery(query: String, includeOpenFoodFacts: Bool) {
        let providers = includeOpenFoodFacts ? Set(SearchProvider.allCases) : SearchProvider.primary
        requestedProviders.formUnion(providers)
        if requestedProviders.isSubset(of: Set(activeProviderBatches.keys)) {
            updateSearchProgress()
            return
        }
        #if DEBUG
        let arguments = searchLoader == nil ? ProcessInfo.processInfo.arguments : []
        if arguments.contains("-ui-testing-search-failure") {
            searchTask?.cancel()
            searchResults = []
            supplementResults = []
            isLoading = false
            searchErrorMessage = Self.unavailableMessage
            searchCoverageMessage = nil
            return
        }
        if arguments.contains("-ui-testing-specialist-sources") {
            searchTask?.cancel()
            searchResults = [Self.healthCanadaTestFood]
            supplementResults = [Self.nihSupplementTestFood]
            isLoading = false
            searchErrorMessage = nil
            searchCoverageMessage = nil
            return
        }
        if arguments.contains("-ui-testing-branded-food-search") {
            searchBrandedFixture(query: query)
            return
        }
        if arguments.contains("-ui-testing") {
            searchTask?.cancel()
            searchResults = [
                FoodItem(
                    id: "ui-test-apple",
                    name: "Test Kitchen Apple",
                    calories: 52,
                    protein: 0.3,
                    carbs: 14,
                    fats: 0.2,
                    servingSize: "100 g",
                    servingWeight: 100
                ).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "ui-test-apple")
            ]
            supplementResults = []
            isLoading = false
            searchErrorMessage = nil
            searchCoverageMessage = nil
            return
        }
        #endif

        // Reuse completed and in-flight base providers when Search adds the explicit-only
        // sources. A repeated submit cannot clear useful rows or launch the same provider twice.
        let generation = searchGeneration
        let owner = searchOwnerID
        for provider in providers where activeProviderBatches[provider] == nil && providerTasks[provider] == nil {
            failedProviders.remove(provider)
            providerTasks[provider] = Task { @MainActor [weak self] in
                guard let self else { return }
                let lookup = self.providerQuery(query, for: provider)
                let result = await self.loadSearchProvider(provider, query: lookup)
                guard !Task.isCancelled, self.searchGeneration == generation,
                      self.activeSearchQuery == query,
                      self.searchOwnerID == owner,
                      DIContainer.shared.authService.currentUserID == owner else { return }
                self.providerTasks[provider] = nil
                switch result {
                case .success(let foods):
                    self.activeProviderBatches[provider] = foods
                    self.searchCache.store(foods, for: self.providerQuery(query, for: provider), provider: provider)
                case .failure:
                    self.failedProviders.insert(provider)
                }
                self.updateSearchProgress()
            }
        }
        updateSearchProgress()
    }

    func loadSearchProvider(_ provider: SearchProvider, query: String) async -> Result<[FoodItem], Error> {
        if let searchLoader { return await searchLoader(provider, query) }
        switch provider {
        case .fatSecret:
            return await withCheckedContinuation { continuation in
                foodAPIService.fetchFoodByQuery(query: query) { continuation.resume(returning: $0) }
            }
        case .usda: return await usdaService.searchFoodsResult(query: query)
        case .healthCanada: return await healthCanadaService.searchFoodsResult(query: query)
        case .openFoodFacts: return await openFoodFactsService.searchFoodsResult(query: query)
        case .supplements: return await supplementService.searchSupplementsResult(query: query)
        }
    }

    private func updateSearchProgress() {
        let resolved = Set(activeProviderBatches.keys).union(failedProviders)
        isLoading = !requestedProviders.isSubset(of: resolved)
        hasCompletedPrimarySearch = SearchProvider.primary.isSubset(of: resolved)
        let batches = Dictionary(uniqueKeysWithValues: activeProviderBatches.map { ($0.key.rawValue, $0.value) })
        publishRemoteSearchBatches(query: activeSearchQuery, batches: batches, providersComplete: !isLoading)
        searchErrorMessage = !isLoading && !failedProviders.isEmpty && searchResults.isEmpty && supplementResults.isEmpty
            ? Self.unavailableMessage : nil
        if isLoading {
            searchCoverageMessage = searchResults.isEmpty && supplementResults.isEmpty ? nil
                : String(localized: "Searching more food sources…")
        } else {
            searchCoverageMessage = !failedProviders.isEmpty && searchErrorMessage == nil
                ? String(localized: "Some food sources are unavailable.") : nil
        }
    }

    /// Shared by live provider completions and deterministic provider-arrival fixtures. A stale
    /// query cannot publish after the user has started another search.
    func publishRemoteSearchBatches(query: String, batches: [Int: [FoodItem]], providersComplete: Bool) {
        guard query == activeSearchQuery else { return }
        let merged = FoodSearchRanking.mergedSearchResults(
            fatSecret: batches[0] ?? [], usda: batches[1] ?? [],
            healthCanada: batches[2] ?? [], openFoodFacts: batches[3] ?? [], query: query
        )
        searchResults = FoodSearchRanking.publishingRemoteMatches(
            query: query, previous: searchResults, updated: merged, providersComplete: providersComplete
        )
        supplementResults = batches[4] ?? []
    }

    #if DEBUG
    private func searchBrandedFixture(query: String) {
        searchTask?.cancel()
        searchResults = []; supplementResults = []
        isLoading = true; searchErrorMessage = nil
        searchCoverageMessage = String(localized: "Searching more food sources…")
        let generic = FoodItem(id: "ui-generic-yogurt", name: "Greek Yogurt", calories: 100, protein: 10, carbs: 10, fats: 2,
                               servingSize: "100 g", servingWeight: 100).withDatabaseSource(.usda, sourceName: "USDA", sourceID: "ui-generic-yogurt")
        let branded = [
            ("ui-chobani-yogurt", "Greek Yogurt", "Chobani"),
            ("ui-fage-yogurt", "Greek Yogurt", "Fage"),
            ("ui-unrelated-pineapple", "Pineapple", "Dole")
        ].map { id, name, brand in
            FoodItem(id: id, name: FoodSearchRanking.productDisplayName(name, brandName: brand), calories: 100,
                     protein: 10, carbs: 10, fats: 2, servingSize: "100 g", servingWeight: 100)
                .withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: id, brandName: brand)
        }
        let variants = [("ui-vanilla-small", "Vanilla", "5.3 oz"), ("ui-vanilla-large", "Vanilla", "32 oz"),
                        ("ui-strawberry-small", "Strawberry", "5.3 oz")].map { id, flavor, size in
            var metadata = FoodSourceMetadata.database(.usda, sourceName: "USDA", sourceID: id, brandName: "Chobani")
            metadata.labeledServing = size
            return FoodItem(id: id, name: "Greek Yogurt, " + flavor, calories: 100,
                            servingSize: "100 g", servingWeight: 100, sourceMetadata: metadata)
        }
        let usda = ProcessInfo.processInfo.arguments.contains("-ui-testing-product-sizes") ? [generic] + variants : [generic]
        searchTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, query == self.activeSearchQuery else { return }
            self.publishRemoteSearchBatches(query: query, batches: [1: usda], providersComplete: false)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, query == self.activeSearchQuery else { return }
            self.publishRemoteSearchBatches(query: query, batches: [0: branded, 1: usda], providersComplete: false)
            self.publishRemoteSearchBatches(query: query, batches: [0: branded, 1: usda], providersComplete: true)
            self.activeProviderBatches = [.fatSecret: branded, .usda: usda, .healthCanada: []]
            if self.requestedProviders.contains(.openFoodFacts) { self.activeProviderBatches[.openFoodFacts] = [] }
            if self.requestedProviders.contains(.supplements) { self.activeProviderBatches[.supplements] = [] }
            for (provider, foods) in self.activeProviderBatches {
                self.searchCache.store(foods, for: self.providerQuery(query, for: provider), provider: provider)
            }
            self.hasCompletedPrimarySearch = true
            self.isLoading = false; self.searchCoverageMessage = nil
        }
    }

    private static var healthCanadaTestFood: FoodItem {
        let item = FoodItem(
            id: "cnf_ui_4700",
            name: "Salmon, Atlantic, baked",
            calories: 206,
            protein: 22.1,
            carbs: 0,
            fats: 12.4,
            saturatedFat: 2.4,
            servingSize: "100 g",
            servingWeight: 100,
            potassium: 384,
            sodium: 61,
            vitaminD: 13.1,
            vitaminB12: 3.2,
            selenium: 41.4
        )
        var metadata = FoodSourceMetadata.database(
            .healthCanadaCNF,
            sourceName: "Health Canada CNF",
            sourceID: item.id,
            evidenceLineage: .governmentCompilation,
            sourceUpdatedAt: ISO8601DateFormatter().date(from: "2026-05-14T00:00:00Z")
        )
        metadata.notes = "Canadian Nutrient File release 2026-05-14. Food record last revised 2015-11-03."
        return item.withSourceMetadata(metadata)
    }

    private static var nihSupplementTestFood: FoodItem {
        let item = FoodItem(
            id: "dsld_ui_42",
            name: "Example Vitamin D3",
            calories: 0,
            protein: 0,
            carbs: 0,
            fats: 0,
            servingSize: "1 Softgel",
            servingWeight: 0,
            vitaminD: 25,
            quantityValue: 1,
            servingUnit: "serving"
        )
        var metadata = FoodSourceMetadata.database(
            .nihDSLD,
            sourceName: "NIH DSLD",
            sourceID: item.id,
            barcode: "012345678905",
            evidenceLineage: .manufacturerLabel
        )
        metadata.notes = "Current manufacturer supplement label record; not laboratory verification. Label serving: 1 Softgel."
        return item.withSourceMetadata(metadata)
    }
    #endif

    func fetchData() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            resetAccountData()
            return
        }
        guard prepareForAccount(userID) else { return }
        fetchSavedFoods(userID: userID)
        fetchRecents(userID: userID)
        fetchRecommendedFoods(userID: userID)
        fetchYesterdayMeal(userID: userID)
    }

    func fetchSavedFoods(userID: String) {
        guard prepareForAccount(userID) else { return }
        let requestID = UUID()
        savedFoodsRequestID = requestID
        dailyLogService?.customFoodStore.fetchMyFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.isCurrentRequest(requestID, storedRequestID: self.savedFoodsRequestID, userID: userID) else { return }
                if case .success(let items) = result {
                    self.savedFoods = items
                }
            }
        }
    }

    func fetchRecents(userID: String) {
        guard prepareForAccount(userID) else { return }
        let requestID = UUID()
        recentFoodsRequestID = requestID
        dailyLogService?.fetchRecentFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.isCurrentRequest(requestID, storedRequestID: self.recentFoodsRequestID, userID: userID) else { return }
                if case .success(let items) = result {
                    self.recentFoods = items
                }
            }
        }
    }

    func fetchRecommendedFoods(userID: String) {
        guard prepareForAccount(userID) else { return }
        let requestID = UUID()
        let mealName = selectedMeal
        recommendedFoodsRequestID = requestID
        dailyLogService?.fetchRecommendedFoods(for: userID, mealName: mealName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.selectedMeal == mealName,
                      self.isCurrentRequest(requestID, storedRequestID: self.recommendedFoodsRequestID, userID: userID) else { return }
                if case .success(let items) = result {
                    self.recommendedFoods = items
                }
            }
        }
    }

    func fetchYesterdayMeal(userID: String) {
        guard prepareForAccount(userID) else { return }
        guard let service = dailyLogService,
              let destination = service.diaryDayContext(for: userID, date: service.activelyViewedDate),
              let yesterday = destination.adding(days: -1) else { return }
        let requestID = UUID()
        let mealName = selectedMeal
        yesterdayRequestID = requestID
        isFetchingYesterday = true
        yesterdaysMealItems = []
        yesterdaysLog = nil
        yesterdaysSourceDay = nil
        yesterdaysDestinationDay = nil
        service.fetchLogInternal(for: userID, day: yesterday) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.selectedMeal == mealName,
                      service.diaryDayContext(for: userID, date: service.activelyViewedDate) == destination,
                      self.isCurrentRequest(requestID, storedRequestID: self.yesterdayRequestID, userID: userID) else { return }
                self.isFetchingYesterday = false
                switch result {
                case .success(let log):
                    guard log.id == yesterday.dayKey else { return }
                    self.yesterdaysLog = log
                    self.yesterdaysSourceDay = yesterday
                    self.yesterdaysDestinationDay = destination
                    if let meal = log.meals.first(where: { $0.name.lowercased() == mealName.lowercased() }) {
                        self.yesterdaysMealItems = meal.foodItems
                    } else {
                        self.yesterdaysMealItems = []
                    }
                case .failure:
                    self.yesterdaysLog = nil
                    self.yesterdaysMealItems = []
                }
            }
        }
    }

    func quickLog(food: FoodItem, source: String = "quick_log") {
        if isBuildingMeal { addToMealDraft(food); return }
        guard let service = dailyLogService, let queue = quickLogQueue,
              let userID = loadedUserID, DIContainer.shared.authService.currentUserID == userID,
              !loggingFoodIDs.contains(food.id), !quickLoggedFoodIDs.contains(food.id) else { return }
        let day = service.diaryDayContext(for: userID, date: service.activelyViewedDate)
        guard let pending = queue.begin(food: food, date: service.activelyViewedDate, mealName: selectedMeal, source: source,
                                        needsHydration: true, dayContext: day) else {
            lastLogSucceeded = false
            lastUndoID = nil
            lastLogMessage = queue.errorMessage
            return
        }
        performQuickLog(pending, queue: queue, service: service)
    }

    func retryQuickLog() {
        guard let queue = quickLogQueue, let pending = queue.operations.first, let service = dailyLogService else { return }
        performQuickLog(pending, queue: queue, service: service)
    }

    private func performQuickLog(_ pending: PendingQuickFoodLog, queue: QuickFoodLogQueue, service: DailyLogService) {
        guard DIContainer.shared.authService.currentUserID == queue.userID,
              !loggingFoodIDs.contains(pending.sourceFoodID), let entry = pending.draft.entries.first else { return }
        loggingFoodIDs.insert(pending.sourceFoodID)
        lastLogMessage = nil
        canRetryLog = false
        if entry.hydrationPending == true {
            resolveNutritionIfNeeded(for: entry.food) { [weak self] resolved in
                guard let self, DIContainer.shared.authService.currentUserID == queue.userID else { return }
                guard queue.hydrate(id: pending.id, food: resolved),
                      let hydrated = queue.operations.first(where: { $0.id == pending.id }) else {
                    self.loggingFoodIDs.remove(pending.sourceFoodID)
                    self.canRetryLog = true
                    self.lastLogSucceeded = false
                    self.lastUndoID = nil
                    self.lastLogMessage = queue.errorMessage ?? "Your pending food is kept. Retry to finish."
                    return
                }
                self.saveQuickLog(hydrated, queue: queue, service: service)
            }
        } else {
            saveQuickLog(pending, queue: queue, service: service)
        }
    }

    private func saveQuickLog(_ pending: PendingQuickFoodLog, queue: QuickFoodLogQueue, service: DailyLogService) {
        let previousUndoID = service.undoChangeID
        queue.save(id: pending.id, using: service) { [weak self] accepted in
            guard let self, DIContainer.shared.authService.currentUserID == queue.userID else { return }
            let finished = accepted && queue.finish(id: pending.id)
            self.loggingFoodIDs.remove(pending.sourceFoodID)
            self.canRetryLog = !queue.operations.isEmpty
            let day = Calendar.current.isDateInToday(pending.draft.date) ? "today" : pending.draft.date.formatted(date: .abbreviated, time: .omitted)
            self.showLogResult(finished, message: "Added to \(pending.draft.mealName) · \(day)")
            if finished {
                self.lastUndoID = self.newAdditionUndo(for: Set(pending.draft.entries.map(\.id)), owner: queue.userID, previous: previousUndoID)
                self.rememberSearch(self.activeSearchQuery)
                let resolved = pending.draft.entries.first?.food
                let rememberedID = resolved.map { FoodServingPreferences(defaults: self.defaults).preferred($0, userID: queue.userID).id }
                self.quickLoggedFoodIDs.insert(pending.sourceFoodID)
                if let rememberedID { self.quickLoggedFoodIDs.insert(rememberedID) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.quickLoggedFoodIDs.remove(pending.sourceFoodID)
                    if let rememberedID { self?.quickLoggedFoodIDs.remove(rememberedID) }
                }
            } else {
                self.lastLogMessage = queue.errorMessage ?? "Your pending food is kept. Retry to finish."
            }
        }
    }

    private func showLogResult(_ success: Bool, message: String) {
        lastLogSucceeded = success
        lastUndoID = success ? dailyLogService?.undoChangeID : nil
        lastLogMessage = success ? message : "Could not save this food. Try again."
        if success { HapticManager.instance.feedback(.medium) }
    }

    private func newAdditionUndo(for ids: Set<String>, owner: String, previous: UUID?) -> UUID? {
        guard let receipt = dailyLogService?.undoID(forAddedFoods: ids, userID: owner), receipt != previous else { return nil }
        return receipt
    }

    func acceptedPortion(_ checkpoint: FoodDetailSaveCheckpoint, previousUndoID: UUID?) {
        guard let owner = loadedUserID, owner == DIContainer.shared.authService.currentUserID else { return }
        lastLogSucceeded = true
        lastLogMessage = "Added to " + checkpoint.mealName + " · " + checkpoint.date.formatted(date: .abbreviated, time: .omitted)
        lastUndoID = newAdditionUndo(for: [checkpoint.entryID], owner: owner, previous: previousUndoID)
        rememberSearch(activeSearchQuery)
    }

    func undoQuickLog() {
        guard canUndoQuickLog, let receipt = lastUndoID, let service = dailyLogService, service.canUndoDiaryChange,
              let userID = DIContainer.shared.authService.currentUserID else { return }
        service.undoLastDiaryChange(for: userID) { [weak self] accepted in
            guard let self, DIContainer.shared.authService.currentUserID == userID, self.lastUndoID == receipt else { return }
            if accepted {
                self.lastLogMessage = nil
                self.quickLoggedFoodIDs = []
                self.isRepeating = false
                self.repeatFeedbackID = nil
                self.lastUndoID = nil
            } else {
                self.lastLogSucceeded = false
                self.lastLogMessage = service.undoErrorMessage ?? "Could not undo this food. Retry Undo."
            }
        }
    }

    private func prepareForAccount(_ userID: String) -> Bool {
        guard DIContainer.shared.authService.currentUserID == userID else { return false }
        guard loadedUserID != userID else { return true }

        resetAccountData()
        loadedUserID = userID
        quickLogQueue = QuickFoodLogQueue(userID: userID, store: draftStore)
        if let queue = quickLogQueue, !queue.operations.isEmpty {
            canRetryLog = true
            lastLogMessage = "An unfinished quick log is kept with its original day and meal. Retry to finish."
        }
        if let key = recentSearchKey { recentSearches = defaults.stringArray(forKey: key) ?? [] }
        restoreMealDraft()
        return true
    }

    private func isCurrentRequest(_ requestID: UUID, storedRequestID: UUID?, userID: String) -> Bool {
        storedRequestID == requestID
            && loadedUserID == userID
            && DIContainer.shared.authService.currentUserID == userID
    }

    private func resetAccountData() {
        cancelSearchRequests()
        searchCache.removeAll()
        searchOwnerID = nil
        activeProviderBatches = [:]
        requestedProviders = []
        failedProviders = []
        hasCompletedPrimarySearch = false
        searchText = ""
        activeSearchQuery = ""
        searchResults = []
        supplementResults = []
        isLoading = false
        searchErrorMessage = nil
        searchCoverageMessage = nil
        loadedUserID = nil
        savedFoodsRequestID = nil
        recentFoodsRequestID = nil
        recommendedFoodsRequestID = nil
        yesterdayRequestID = nil
        savedFoods = []
        recentFoods = []
        recommendedFoods = []
        yesterdaysMealItems = []
        yesterdaysLog = nil
        yesterdaysSourceDay = nil
        yesterdaysDestinationDay = nil
        isFetchingYesterday = false
        quickLoggedFoodIDs = []
        loggingFoodIDs = []
        isRepeating = false
        repeatFeedbackID = nil
        lastLogMessage = nil
        lastLogSucceeded = false
        lastUndoID = nil
        quickLogQueue = nil
        canRetryLog = false
        recentSearches = []
        mealDraft = nil
        draftMessage = nil
        isBuildingMeal = false
        isSavingDraft = false
        didLoadMealDraft = false
        unreadableMealDraft = false
    }

    private func restoreMealDraft() {
        guard !didLoadMealDraft, let userID = loadedUserID else { return }
        didLoadMealDraft = true
        do {
            if let saved = try draftStore.load(FoodLoggingDraft.self, userID: userID, scope: mealDraftScope) {
                mealDraft = saved.value
                isBuildingMeal = true
                draftMessage = saved.value.isSubmitted
                    ? "Finish logging your saved meal. Retrying won't add duplicates."
                    : "Restored your unfinished meal."
                retryDraftHydration()
            }
        } catch {
            unreadableMealDraft = true
            draftMessage = "Couldn't restore the previous meal draft. It has been kept on this device."
        }
    }

    /// Give an asynchronous capture a stable destination, even when it is the first selection.
    func draftForCapture() -> FoodLoggingDraft? {
        guard isBuildingMeal, !isSavingDraft, !unreadableMealDraft, let owner = loadedUserID,
              owner == DIContainer.shared.authService.currentUserID, let service = dailyLogService else { return nil }
        if let mealDraft { return mealDraft.isSubmitted ? nil : mealDraft }
        let date = service.activelyViewedDate
        let draft = FoodLoggingDraft(date: date, mealName: selectedMeal,
            dayContext: service.diaryDayContext(for: owner, date: date), trainingFuelTarget: trainingFuelTarget)
        return persistMealDraft(draft) ? draft : nil
    }

    func selectReviewedPhotoFoods(_ foods: [FoodItem], owner: String, draftID: UUID) -> Bool {
        guard isBuildingMeal, owner == loadedUserID, owner == DIContainer.shared.authService.currentUserID,
              let draft = mealDraft, draft.id == draftID, !draft.isSubmitted, !foods.isEmpty,
              !isSavingDraft, !unreadableMealDraft else { return false }
        return updateMealDraft { draft in
            // A restored photo review uses the same entry IDs after an interrupted handoff.
            for food in foods where !draft.entries.contains(where: { $0.sourceID == food.id }) {
                draft.entries.append(FoodLoggingDraft.Entry(food: food))
            }
        }
    }

    func addToMealDraft(_ food: FoodItem) {
        guard let service = dailyLogService, let userID = loadedUserID,
              DIContainer.shared.authService.currentUserID == userID, !isSavingDraft,
              !unreadableMealDraft, mealDraft?.isSubmitted != true, !loggingFoodIDs.contains(food.id),
              !(mealDraft?.entries.contains { $0.sourceID == food.id } ?? false) else { return }
        var draft = mealDraft ?? FoodLoggingDraft(date: service.activelyViewedDate, mealName: selectedMeal,
            dayContext: service.diaryDayContext(for: userID, date: service.activelyViewedDate), trainingFuelTarget: trainingFuelTarget)
        var entry = FoodLoggingDraft.Entry(food: food, sourceID: food.id)
        entry.hydrationPending = FoodSearchRanking.needsNutritionHydration(food)
        draft.entries.append(entry)
        guard persistMealDraft(draft) else { return }
        retryDraftHydration()
    }

    /// Non-API editors use a per-unit serving basis. Seed the displayed amount in
    /// this value copy so a "100 g" row opens as 100 g, without changing its nutrients.
    func portionReviewFood(_ food: FoodItem, source: String) -> FoodItem {
        guard food.quantityValue == nil else { return food }
        if ["search_result", "barcode_result", "image_result"].contains(source), FoodSearchRanking.isFatSecretID(food.id) {
            return food
        }
        var parsed = ServingNutritionCalculator.parseQuantity(from: food.servingSize)
        if parsed.quantity == 1, parsed.baseDescription == food.servingSize,
           let natural = naturalPortionMeasure(food.servingSize) {
            if let unit = food.servingUnit,
               unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                != natural.baseDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                return food
            }
            parsed = natural
        }
        guard parsed.quantity.isFinite, parsed.quantity > 0 else { return food }
        var preview = food
        preview.quantityValue = parsed.quantity
        preview.servingUnit = food.servingUnit ?? parsed.baseDescription
        return preview
    }

    private func naturalPortionMeasure(_ description: String) -> (quantity: Double, baseDescription: String)? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^((?:[0-9]+\s+)?[0-9]+/[0-9]+|[0-9]+(?:\.[0-9]+)?)\s*(?:[x×]\s*)?([A-Za-zµμ].*)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let parts = text[amountRange].split(separator: " ")
        let quantity: Double
        if let fraction = parts.last, fraction.contains("/") {
            let values = fraction.split(separator: "/").compactMap { Double($0) }
            guard values.count == 2, values[1] > 0 else { return nil }
            quantity = (parts.count == 2 ? Double(parts[0]) ?? 0 : 0) + values[0] / values[1]
        } else { quantity = Double(text[amountRange]) ?? 0 }
        guard quantity.isFinite, quantity > 0 else { return nil }
        return (quantity, String(text[unitRange]))
    }

    /// Portion review is a local proposal, not a diary write. Keep its captured owner,
    /// destination and draft identity when the review returns after other UI changes.
    @discardableResult
    func acceptReviewedMealFood(_ food: FoodItem, sourceID: String, userID: String?,
                                draftID: UUID?, date: Date, mealName: String,
                                dayContext: DiaryDayContext? = nil) -> Bool {
        guard let userID, let service = dailyLogService,
              loadedUserID == userID, DIContainer.shared.authService.currentUserID == userID,
              !isSavingDraft, !unreadableMealDraft, mealDraft?.isSubmitted != true,
              mealDraft?.id == draftID, !sourceID.isEmpty,
              !loggingFoodIDs.contains(sourceID), dayContext?.isOwned(by: userID) ?? true else { return false }
        var draft = mealDraft ?? FoodLoggingDraft(date: date, mealName: mealName,
            dayContext: dayContext ?? service.diaryDayContext(for: userID, date: date), trainingFuelTarget: trainingFuelTarget)
        if let index = draft.entries.firstIndex(where: { $0.sourceID == sourceID }) {
            draft.entries[index].food = food
            draft.entries[index].multiplier = 1
            draft.entries[index].hydrationPending = false
        } else {
            var entry = FoodLoggingDraft.Entry(food: food, sourceID: sourceID)
            entry.hydrationPending = false
            draft.entries.append(entry)
        }
        return persistMealDraft(draft)
    }

    func retryDraftHydration() {
        guard let draft = mealDraft, !draft.isSubmitted, !isSavingDraft, !unreadableMealDraft,
              let userID = loadedUserID, DIContainer.shared.authService.currentUserID == userID else { return }
        for entry in draft.entries where entry.hydrationPending == true && !loggingFoodIDs.contains(entry.sourceID) {
            loggingFoodIDs.insert(entry.sourceID)
            resolveNutritionIfNeeded(for: entry.food) { [weak self] resolved in
                guard let self, self.loadedUserID == userID, DIContainer.shared.authService.currentUserID == userID else { return }
                self.loggingFoodIDs.remove(entry.sourceID)
                guard self.mealDraft?.id == draft.id, !self.isSavingDraft, self.mealDraft?.isSubmitted != true,
                      self.mealDraft?.entries.first(where: { $0.id == entry.id })?.hydrationPending == true else { return }
                self.updateMealDraft {
                    guard let index = $0.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                    $0.entries[index].food = resolved
                    $0.entries[index].hydrationPending = false
                }
            }
        }
    }

    @discardableResult
    func updateMealDraft(_ edit: (inout FoodLoggingDraft) -> Void) -> Bool {
        guard var draft = mealDraft, !draft.isSubmitted, !isSavingDraft else { return false }
        let originalDate = draft.date
        let originalContext = draft.dayContext
        edit(&draft)
        if draft.date != originalDate {
            guard let userID = loadedUserID, DIContainer.shared.authService.currentUserID == userID,
                  let day = DiaryDayContext(userID: userID, date: Calendar.current.startOfDay(for: draft.date)), !day.isFuture() else {
                draftMessage = "Choose today or an earlier day for food you've eaten."
                return false
            }
            draft.dayContext = day
            draft.date = day.originalDate
        } else {
            // A portion/meal edit is not permission to reinterpret an older destination.
            draft.dayContext = originalContext
        }
        return persistMealDraft(draft)
    }

    private func persistMealDraft(_ draft: FoodLoggingDraft) -> Bool {
        guard !unreadableMealDraft, let userID = loadedUserID, DIContainer.shared.authService.currentUserID == userID else { return false }
        do {
            try draftStore.save(draft, userID: userID, scope: mealDraftScope)
            mealDraft = draft
            if isBuildingMeal { selectedMeal = draft.mealName }
            draftMessage = "Draft saved on this device."
            return true
        } catch {
            draftMessage = "Couldn't save the meal draft. Keep this screen open and try again."
            return false
        }
    }

    @discardableResult
    func discardMealDraft() -> Bool {
        guard !isSavingDraft, !unreadableMealDraft, mealDraft?.isSubmitted != true,
              let userID = loadedUserID, DIContainer.shared.authService.currentUserID == userID else { return false }
        do {
            try draftStore.remove(userID: userID, scope: mealDraftScope)
            mealDraft = nil
            draftMessage = nil
            return true
        } catch {
            draftMessage = "Couldn't discard the draft. Try again."
            return false
        }
    }

    func logMealDraft(completion: @escaping (Bool) -> Void) {
        guard let service = dailyLogService, var draft = mealDraft, draft.isReadyToSubmit,
              !isSavingDraft, loggingFoodIDs.isEmpty, let userID = loadedUserID,
              DIContainer.shared.authService.currentUserID == userID else { completion(false); return }
        if !draft.isSubmitted, let target = draft.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.stageFoodLink(target: target, foods: draft.foods, date: draft.date, using: service, userID: userID)
            } catch { draftMessage = error.localizedDescription; completion(false); return }
        }
        draft.isSubmitted = true
        guard persistMealDraft(draft) else { completion(false); return }
        if let target = draft.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: draft.foods, userID: userID)
            } catch { draftMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        isSavingDraft = true
        draftMessage = nil
        let previousUndoID = service.undoChangeID
        service.addMealGroupsToLog(for: userID, date: draft.date,
                                  mealGroups: [(mealName: draft.mealName, foodItems: draft.foods)],
                                  source: "meal_draft", deduplicateFoodIDs: true, dayContext: draft.dayContext) { [weak self] success in
            guard let self, self.loadedUserID == userID, DIContainer.shared.authService.currentUserID == userID else {
                completion(false)
                return
            }
            self.isSavingDraft = false
            guard success else {
                self.draftMessage = "Couldn't save this meal. Your foods are kept; try again."
                completion(false)
                return
            }
            if let target = draft.trainingFuelTarget {
                _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: draft.foods, userID: userID)
            }
            let foodLabel = draft.foods.count == 1 ? "food" : "foods"
            self.showLogResult(true, message: "\(draft.foods.count) \(foodLabel) added to \(draft.mealName) · \(draft.date.formatted(date: .abbreviated, time: .omitted))")
            self.lastUndoID = self.newAdditionUndo(for: Set(draft.entries.map(\.id)), owner: userID, previous: previousUndoID)
            do {
                try self.draftStore.remove(userID: userID, scope: self.mealDraftScope)
                self.mealDraft = nil
                self.isBuildingMeal = false
                self.draftMessage = nil
                completion(true)
            } catch {
                self.draftMessage = "Your meal was saved. Retry to clear its draft; it won't be added twice."
                completion(false)
            }
        }
    }

    /// FatSecret search rows are previews parsed from a description string — no
    /// micronutrients, zeroed fat breakdown. Hydrate from the details endpoint before
    /// logging so a quick-logged food carries the same nutrition as one logged through
    /// the detail screen. Falls back to the preview if the fetch fails.
    private func resolveNutritionIfNeeded(for food: FoodItem, completion: @escaping (FoodItem) -> Void) {
        guard FoodSearchRanking.needsNutritionHydration(food) else {
            completion(food)
            return
        }

        foodAPIService.fetchFoodDetails(foodId: food.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let details):
                    completion(FoodSearchRanking.hydratedQuickLogItem(
                        preview: food,
                        detailBase: details.foodInfo,
                        availableServings: details.availableServings
                    ))
                case .failure:
                    completion(food)
                }
            }
        }
    }

    func sourceForTrustedSearchResult(_ food: FoodItem) -> String {
        if savedFoods.contains(where: { $0.id == food.id }) {
            return "custom_food"
        }
        return "recent_tap"
    }

    func logYesterdayMeal() {
        guard let service = dailyLogService else { return }
        logRepeatedMeal(yesterdaysMealItems, mealName: selectedMeal, date: service.activelyViewedDate) { _ in }
    }

    /// UI repeat shortcuts use the same checked transfer review as the diary. The
    /// captured server snapshot and civil days remain fixed throughout that review.
    /// The older direct helpers below remain available for non-UI compatibility.
    func makePreviousDayTransfer(allMeals: Bool) throws -> DiaryTransferSession {
        guard let userID = DIContainer.shared.authService.currentUserID, loadedUserID == userID,
              let service = dailyLogService else { throw DiaryTransferError.accountChanged }
        guard !isFetchingYesterday, let source = yesterdaysSourceDay, let destination = yesterdaysDestinationDay,
              source.isOwned(by: userID), destination.isOwned(by: userID), let log = yesterdaysLog,
              log.id == source.dayKey else { throw DiaryTransferError.changed }
        guard service.diaryDayContext(for: userID, date: service.activelyViewedDate) == destination else { throw DiaryTransferError.changed }
        guard !destination.isFuture() else { throw DiaryTransferError.futureDay }
        let foodIDs = allMeals ? nil : log.meals.filter { $0.name.caseInsensitiveCompare(selectedMeal) == .orderedSame }
            .flatMap(\.foodItems).map(\.id)
        var proposal = try DiaryTransferDraft(source: source, destination: destination, sourceLog: log, mode: .copy, foodIDs: foodIDs)
        if !allMeals {
            for index in proposal.entries.indices { proposal.entries[index].destinationMealName = selectedMeal }
        }
        // Reopening a durable request must never overwrite an unfinished transfer.
        let session = DiaryTransferSession(userID: userID, draft: proposal, store: draftStore)
        guard !session.isUnreadable, session.checkpoint != nil else {
            throw NSError(domain: "FoodTransferReview", code: 1, userInfo: [NSLocalizedDescriptionKey:
                session.errorMessage ?? "The copy review couldn't be kept on this device. Nothing was added."])
        }
        return session
    }

    func logRepeatedMeal(_ foods: [FoodItem], mealName: String, date: Date, completion: @escaping (Bool) -> Void) {
        guard let service = dailyLogService, !isRepeating, !foods.isEmpty,
              let userID = DIContainer.shared.authService.currentUserID, loadedUserID == userID else {
            completion(false)
            return
        }
        isRepeating = true
        let items = foods.map { food -> FoodItem in
            var item = food
            item.id = UUID().uuidString
            item.timestamp = Date()
            return item
        }
        service.addMealToLog(for: userID, date: date, mealName: mealName, foodItems: items, source: "repeat_yesterday_meal") { [weak self] success in
            guard let self, DIContainer.shared.authService.currentUserID == userID else { completion(false); return }
            self.finishRepeating(success: success, scope: "meal", itemCount: items.count)
            self.showLogResult(success, message: "Meal added to \(mealName)")
            completion(success)
        }
    }

    func logYesterdayDay() {
        guard let service = dailyLogService, !isRepeating,
              let userID = DIContainer.shared.authService.currentUserID, loadedUserID == userID,
              let log = yesterdaysLog, !yesterdaysDayItems.isEmpty else { return }
        isRepeating = true
        let groups = log.meals.map { meal in
            (mealName: meal.name, foodItems: meal.foodItems.map { food -> FoodItem in
                var item = food
                item.id = UUID().uuidString
                item.timestamp = Date()
                return item
            })
        }
        service.addMealGroupsToLog(for: userID, date: service.activelyViewedDate, mealGroups: groups, source: "repeat_yesterday_day") { [weak self] success in
            guard let self, DIContainer.shared.authService.currentUserID == userID else { return }
            self.finishRepeating(success: success, scope: "day", itemCount: groups.reduce(0) { $0 + $1.foodItems.count })
            self.showLogResult(success, message: "Copied meals to the selected day")
        }
    }

    private func finishRepeating(success: Bool, scope: String, itemCount: Int) {
        guard success else { isRepeating = false; return }
        DIContainer.shared.analyticsManager?.logEvent("repeat_yesterday_logged", parameters: ["scope": scope, "item_count": itemCount])
        let receipt = UUID()
        repeatFeedbackID = receipt
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.repeatFeedbackID == receipt else { return }
            self.isRepeating = false
            self.repeatFeedbackID = nil
        }
    }

    static func defaultMealName(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return "Breakfast"
        case 11..<16:
            return "Lunch"
        case 16..<22:
            return "Dinner"
        default:
            return "Snacks"
        }
    }
}
