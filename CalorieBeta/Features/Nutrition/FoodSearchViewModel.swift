import SwiftUI
import Combine

@MainActor
class FoodSearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedMeal: String = FoodSearchViewModel.defaultMealName()
    
    @Published var searchResults: [FoodItem] = []
    @Published var isLoading = false
    @Published var searchErrorMessage: String?
    @Published var activeSearchQuery = ""
    @Published var quickLoggedFoodIDs: Set<String> = []
    
    @Published var savedFoods: [FoodItem] = []
    @Published var recentFoods: [FoodItem] = []
    @Published var recommendedFoods: [FoodItem] = []
    
    @Published var yesterdaysMealItems: [FoodItem] = []
    @Published var yesterdaysLog: DailyLog?
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
        FoodSearchRanking.trustedLocalMatches(
            query: searchText,
            savedFoods: savedFoods,
            recentFoods: recentFoods
        )
    }

    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()
    private let openFoodFactsService = OpenFoodFactsAPIService()
    private var cancellables = Set<AnyCancellable>()
    private var dailyLogService: DailyLogService?
    private var searchTask: Task<Void, Never>?

    init() {
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
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.handleSearchQueryChange(query)
            }
            .store(in: &cancellables)
    }

    func handleSearchQueryChange(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            activeSearchQuery = ""
            searchResults = []
            isLoading = false
            searchErrorMessage = nil
            searchTask?.cancel()
            return
        }

        guard trimmed.count >= 2 else {
            activeSearchQuery = ""
            searchResults = []
            isLoading = false
            searchErrorMessage = nil
            return
        }

        activeSearchQuery = trimmed
        isLoading = true
        searchErrorMessage = nil
        searchByQuery(query: trimmed, includeOpenFoodFacts: false)
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        activeSearchQuery = query
        isLoading = true
        searchErrorMessage = nil
        searchByQuery(query: query, includeOpenFoodFacts: true)
    }

    private func searchByQuery(query: String, includeOpenFoodFacts: Bool) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
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
            isLoading = false
            searchErrorMessage = nil
            return
        }
        #endif

        // FatSecret and USDA support the debounced interactive search. Open Food Facts asks
        // clients not to perform search-as-you-type, so it joins only after an explicit submit.
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let usdaResults = self.usdaService.searchFoods(query: query)

            let fatSecretResult: Result<[FoodItem], Error> = await withCheckedContinuation { continuation in
                self.foodAPIService.fetchFoodByQuery(query: query) { continuation.resume(returning: $0) }
            }
            let usda = await usdaResults
            let off = includeOpenFoodFacts
                ? await self.openFoodFactsService.searchFoods(query: query)
                : []

            guard !Task.isCancelled, query == self.activeSearchQuery else { return }
            self.isLoading = false

            switch fatSecretResult {
            case .success(let foodItems):
                self.searchErrorMessage = nil
                self.searchResults = FoodSearchRanking.mergedSearchResults(
                    fatSecret: foodItems,
                    usda: usda,
                    openFoodFacts: off
                )
            case .failure(let error):
                let fallback = FoodSearchRanking.mergedSearchResults(
                    fatSecret: [],
                    usda: usda,
                    openFoodFacts: off
                )
                if fallback.isEmpty {
                    self.searchErrorMessage = "Check your connection and try again. \(error.localizedDescription)"
                    self.searchResults = []
                } else {
                    self.searchErrorMessage = nil
                    self.searchResults = fallback
                }
            }
        }
    }

    func fetchData() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        fetchSavedFoods(userID: userID)
        fetchRecents(userID: userID)
        fetchRecommendedFoods(userID: userID)
        fetchYesterdayMeal(userID: userID)
    }

    func fetchSavedFoods(userID: String) {
        dailyLogService?.customFoodStore.fetchMyFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self?.savedFoods = items
                }
            }
        }
    }

    func fetchRecents(userID: String) {
        dailyLogService?.fetchRecentFoodItems(for: userID) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self?.recentFoods = items
                }
            }
        }
    }

    func fetchRecommendedFoods(userID: String) {
        dailyLogService?.fetchRecommendedFoods(for: userID, mealName: selectedMeal) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self?.recommendedFoods = items
                }
            }
        }
    }

    func fetchYesterdayMeal(userID: String) {
        guard let service = dailyLogService else { return }
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: service.activelyViewedDate) else { return }
        isFetchingYesterday = true
        service.fetchLogInternal(for: userID, date: yesterday) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetchingYesterday = false
                switch result {
                case .success(let log):
                    self.yesterdaysLog = log
                    if let meal = log.meals.first(where: { $0.name.lowercased() == self.selectedMeal.lowercased() }) {
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
        guard let service = dailyLogService else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let sourceFoodID = food.id
        let mealName = selectedMeal
        DIContainer.shared.analyticsManager?.logEvent("quick_log_tapped", parameters: [
            "source": source,
            "meal": mealName
        ])

        quickLoggedFoodIDs.insert(sourceFoodID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            self.quickLoggedFoodIDs.remove(sourceFoodID)
        }
        HapticManager.instance.feedback(.medium)

        resolveNutritionIfNeeded(for: food) { resolved in
            var itemToLog = resolved
            itemToLog.id = UUID().uuidString
            itemToLog.timestamp = Date()
            service.addMealToLog(
                for: userID,
                date: service.activelyViewedDate,
                mealName: mealName,
                foodItems: [itemToLog],
                source: source
            )
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
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        guard !yesterdaysMealItems.isEmpty else { return }

        var itemsToLog = yesterdaysMealItems
        for i in 0..<itemsToLog.count {
            itemsToLog[i].id = UUID().uuidString
            itemsToLog[i].timestamp = Date()
        }
        service.addMealToLog(
            for: userID,
            date: service.activelyViewedDate,
            mealName: selectedMeal,
            foodItems: itemsToLog,
            source: "repeat_yesterday_meal"
        )
        DIContainer.shared.analyticsManager?.logEvent("repeat_yesterday_logged", parameters: [
            "scope": "meal",
            "meal": selectedMeal,
            "item_count": itemsToLog.count
        ])

        HapticManager.instance.feedback(.medium)
    }

    func logYesterdayDay() {
        guard let service = dailyLogService else { return }
        guard let userID = DIContainer.shared.authService.currentUserID,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: service.activelyViewedDate),
              !yesterdaysDayItems.isEmpty else {
            return
        }

        service.repeatFoods(from: yesterday, to: service.activelyViewedDate, for: userID)
        DIContainer.shared.analyticsManager?.logEvent("repeat_yesterday_logged", parameters: [
            "scope": "day",
            "item_count": yesterdaysDayItems.count
        ])
        HapticManager.instance.feedback(.medium)
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
