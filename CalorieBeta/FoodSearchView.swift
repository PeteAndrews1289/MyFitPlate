import SwiftUI
import FirebaseAuth

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: () -> Void
    var initialSearchQuery: String?
    var searchContext: String

    @State private var searchQuery: String = ""
    @State private var searchResults: [FoodItem] = []
    @State private var recentFoodItems: [FoodItem] = []
    @State private var myFoodItems: [FoodItem] = []
    @State private var selectedFoodItem: FoodItem? = nil
    @State private var isLoading = false
    @State private var showingAddFoodManually = false
    @State private var errorState: (isShowing: Bool, message: String) = (false, "")
    @State private var showingBarcodeScanner = false
    @State private var debounceTimer: Timer?
    
    @Environment(\.dismiss) private var dismiss
    private let foodAPIService = FatSecretFoodAPIService()
    @EnvironmentObject var dailyLogService: DailyLogService
    
    enum SearchCategory: String, CaseIterable {
        case search = "Search"
        case recents = "Recents"
        case myFoods = "My Foods"
    }
    @State private var selectedCategory: SearchCategory = .search

    var body: some View {
        NavigationView {
            VStack {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(SearchCategory.allCases, id: \.self) { category in
                        Text(category.rawValue)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                switch selectedCategory {
                case .search:
                    searchSection
                case .recents:
                    recentsSection
                case .myFoods:
                    myFoodsSection
                }
            }
            .navigationTitle("Add Food")
            .navigationBarItems(leading: Button("Cancel") { dismiss() })
            .sheet(isPresented: $showingAddFoodManually) {
                AddFoodView { newFood in
                    if let userID = Auth.auth().currentUser?.uid {
                        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: newFood, source: "manual_creation_from_search")
                    }
                    onFoodItemLogged()
                }
            }
            .sheet(item: $selectedFoodItem) { foodItem in
                NavigationView {
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "search_result",
                        onLogUpdated: { onFoodItemLogged() }
                    )
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView { barcode in
                    self.showingBarcodeScanner = false
                    searchByBarcode(barcode: barcode)
                }
            }
            .alert("Search Error", isPresented: $errorState.isShowing) {
                Button("OK") { }
            } message: {
                Text(errorState.message)
            }
            .onAppear(perform: setupView)
        }
    }

    private var searchSection: some View {
        VStack {
            HStack {
                TextField("Search for food...", text: $searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.default)
                    .onChange(of: searchQuery) { newValue in
                        handleSearchQueryChange(newValue)
                    }
                Button(action: { showingBarcodeScanner = true }) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title2)
                }
                Button(action: searchByQuery) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                }
            }
            .padding()

            if isLoading {
                ProgressView()
                Spacer()
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 15) {
                    Text("No results found for '\(searchQuery)'")
                        .foregroundColor(.gray)
                    Button("Add Food Manually") {
                        showingAddFoodManually = true
                    }
                }
                .padding(.top, 50)
                Spacer()
            } else {
                List(searchResults) { foodItem in
                    Button(action: {
                        self.selectedFoodItem = foodItem
                    }) {
                        VStack(alignment: .leading) {
                            Text(foodItem.name)
                                .fontWeight(.medium)
                            Text(foodItem.servingSize)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }
    
    private var recentsSection: some View {
        VStack {
            if isLoading {
                ProgressView()
            } else if recentFoodItems.isEmpty {
                Text("No recent foods logged.")
                    .foregroundColor(.gray)
                    .padding(.top, 50)
                Spacer()
            } else {
                List(recentFoodItems) { foodItem in
                    Button(action: {
                        self.selectedFoodItem = foodItem
                    }) {
                        VStack(alignment: .leading) {
                            Text(foodItem.name)
                                .fontWeight(.medium)
                            Text(foodItem.servingSize)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }
    
    private var myFoodsSection: some View {
        VStack {
            if isLoading {
                ProgressView()
            } else if myFoodItems.isEmpty {
                Text("You haven't saved any custom foods yet.")
                    .foregroundColor(.gray)
                    .padding(.top, 50)
                Text("Tap the star icon on a food's detail page to save it here.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                List(myFoodItems) { foodItem in
                    Button(action: {
                        self.selectedFoodItem = foodItem
                    }) {
                        VStack(alignment: .leading) {
                            Text(foodItem.name)
                                .fontWeight(.medium)
                            Text(foodItem.servingSize)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }
    
    private func setupView() {
        if let query = initialSearchQuery, !query.isEmpty {
            self.searchQuery = query
            searchByQuery()
        }
        fetchRecentFoods()
        fetchMyFoods()
    }
    
    private func handleSearchQueryChange(_ newValue: String) {
        debounceTimer?.invalidate()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoading = false
            return
        }
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            self.searchByQuery()
        }
    }
    
    private func searchByBarcode(barcode: String) {
        isLoading = true
        foodAPIService.fetchFoodByBarcode(barcode: barcode) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let foodItem):
                    self.searchResults = [foodItem]
                    self.selectedFoodItem = foodItem
                case .failure(let error):
                    self.errorState = (true, "Could not find a food for barcode \(barcode). Error: \(error.localizedDescription)")
                    self.searchResults = []
                }
            }
        }
    }
    
    private func searchByQuery() {
        guard !searchQuery.isEmpty else { return }
        isLoading = true
        foodAPIService.fetchFoodByQuery(query: searchQuery) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let foodItems):
                    self.searchResults = foodItems
                case .failure(let error):
                    self.errorState = (true, "Food search failed. Please try again. Error: \(error.localizedDescription)")
                    self.searchResults = []
                }
            }
        }
    }
    
    private func fetchRecentFoods() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        dailyLogService.fetchRecentFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    self.recentFoodItems = items
                case .failure(_):
                    self.recentFoodItems = []
                }
            }
        }
    }
    
    private func fetchMyFoods() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        dailyLogService.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    self.myFoodItems = items
                case .failure(_):
                    self.myFoodItems = []
                }
            }
        }
    }
}
