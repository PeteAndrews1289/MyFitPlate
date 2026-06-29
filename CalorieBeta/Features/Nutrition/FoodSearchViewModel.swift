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

    private let foodAPIService = FatSecretFoodAPIService()
    private var cancellables = Set<AnyCancellable>()
    private var dailyLogService: DailyLogService?

    init() {
        setupSearchDebounce()
    }

    func setup(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    private func setupSearchDebounce() {
        $searchText
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
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
            searchErrorMessage = nil
            isLoading = false
            return
        }
        
        activeSearchQuery = trimmed
        isLoading = true
        searchErrorMessage = nil
        searchByQuery(query: trimmed)
    }

    private func searchByQuery(query: String) {
        foodAPIService.fetchFoodByQuery(query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, query == self.activeSearchQuery else { return }
                self.isLoading = false
                switch result {
                case .success(let foodItems):
                    self.searchErrorMessage = nil
                    self.searchResults = foodItems
                case .failure(let error):
                    self.searchErrorMessage = "Check your connection and try again. \(error.localizedDescription)"
                    self.searchResults = []
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

    func quickLog(food: FoodItem) {
        guard let service = dailyLogService else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let sourceFoodID = food.id
        var itemToLog = food
        itemToLog.id = UUID().uuidString
        itemToLog.timestamp = Date()
        service.addMealToLog(
            for: userID,
            date: service.activelyViewedDate,
            mealName: selectedMeal,
            foodItems: [itemToLog],
            source: "quick_log"
        )
        quickLoggedFoodIDs.insert(sourceFoodID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            self.quickLoggedFoodIDs.remove(sourceFoodID)
        }
        HapticManager.instance.feedback(.medium)
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
