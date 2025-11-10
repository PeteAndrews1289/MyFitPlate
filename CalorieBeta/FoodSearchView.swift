import SwiftUI
import FirebaseAuth

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @State private var searchText = ""
    @State private var selectedMeal: String = "Breakfast"
    private let foodTypes = ["Breakfast", "Lunch", "Dinner", "Snacks"]
    
    @State private var showingAddFoodManually = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingAskMaia = false
    
    @State private var searchResults: [FoodItem] = []
    @State private var isLoading = false
    @State private var debounceTimer: Timer?
    @State private var selectedFoodItem: FoodItem? = nil
    
    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var scanError: (Bool, String) = (false, "")
    
    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()
    
    @State private var recentFoods: [FoodItem] = []
    @State private var recommendedFoods: [FoodItem] = []
    
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Search for a food...", text: $searchText)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .onChange(of: searchText) { newValue in
                                handleSearchQueryChange(newValue)
                            }
                    }
                    .padding(.horizontal)
                    
                    if onFoodItemSelected == nil {
                        HStack(spacing: 12) {
                            actionButton(title: "Log with Camera", icon: "camera.fill") { showingImagePicker = true }
                            actionButton(title: "Scan Barcode", icon: "barcode.viewfinder") { showingBarcodeScanner = true }
                            actionButton(title: "Ask Maia!", icon: "person.fill.questionmark") { showingAskMaia = true }
                        }
                        .padding()

                        Picker("Log to", selection: $selectedMeal) {
                            ForEach(foodTypes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }

                    List {
                        if isSearching {
                            if isLoading {
                                ProgressView()
                            } else if searchResults.isEmpty {
                                Text("No results found for \"\(searchText)\"")
                            } else {
                                SearchResultsSection(results: searchResults, onSelect: handleSelection)
                            }
                        } else {
                            RecommendedSection(foods: recommendedFoods, onSelect: handleSelection)
                            RecentSection(foods: $recentFoods, onDelete: deleteRecent, onSelect: handleSelection)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                .navigationTitle(onFoodItemSelected == nil ? "Log Food" : "Select Ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    if onFoodItemSelected == nil {
                        ToolbarItem(placement: .primaryAction) { Button("Manual") { showingAddFoodManually = true } }
                    }
                }
                .onAppear(perform: fetchData)
                .onChange(of: selectedMeal) { _ in
                    fetchRecommendedFoods()
                }
                .sheet(isPresented: $showingAddFoodManually) {
                    AddFoodView(isPresented: $showingAddFoodManually, onFoodLogged: { food, meal in
                        Task {
                            await dailyLogService.logFoodItem(food, mealType: meal)
                            onFoodItemLogged?()
                        }
                    })
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView { barcode in
                        self.showingBarcodeScanner = false
                        self.isSearchingAfterScan = true
                        foodAPIService.fetchFoodByBarcode(barcode: barcode) { result in
                            self.isSearchingAfterScan = false
                            switch result {
                            case .success(let foodItem):
                                self.scannedFoodItem = foodItem
                            case .failure(let error):
                                self.scanError = (true, "Could not find a food for this barcode. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingImage = true
                        imageModel.estimateNutritionFromImage(image: image) { result in
                            self.isProcessingImage = false
                            switch result {
                            case .success(let foodItems):
                                self.estimatedFoodItemsWrapper = IdentifiableFoodItems(items: foodItems)
                            case .failure(let error):
                                self.scanError = (true, "Could not analyze the image. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAskMaia) { AIChatbotView(selectedTab: .constant(1)) }
                .sheet(item: $selectedFoodItem) { foodItem in
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "search_result",
                        onLogUpdated: {
                            selectedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $scannedFoodItem) { foodItem in
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "barcode_scan",
                        onLogUpdated: {
                            self.scannedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                     AISummaryView(estimatedItems: .constant(wrapper.items))
                }
                .alert("Scan Error", isPresented: $scanError.0) { Button("OK") { } } message: { Text(scanError.1) }
                
                if isProcessingImage || isSearchingAfterScan {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView(isProcessingImage ? "Analyzing Image..." : "Searching Barcode...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                }
            }
        }
    }
    
    private func handleSelection(food: FoodItem) {
        if let selectionHandler = onFoodItemSelected {
            isSearchingAfterScan = true
            foodAPIService.fetchFoodDetails(foodId: food.id) { result in
                isSearchingAfterScan = false
                switch result {
                case .success(let (detailedFood, _)):
                    selectionHandler(detailedFood)
                case .failure(let error):
                    print("Error fetching details: \(error)")
                }
            }
        } else {
            self.selectedFoodItem = food
        }
    }
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 55)
            .padding(.horizontal, 5)
            .padding(.vertical, 10)
            .background(Color.brandPrimary)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }

    private func handleSearchQueryChange(_ newValue: String) {
        debounceTimer?.invalidate()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoading = false
            return
        }
        isLoading = true
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            searchByQuery(query: trimmed)
        }
    }

    private func searchByQuery(query: String) {
        foodAPIService.fetchFoodByQuery(query: query) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let foodItems):
                    self.searchResults = foodItems
                case .failure:
                    self.searchResults = []
                }
            }
        }
    }
    
    private func fetchData() {
        fetchRecents()
        fetchRecommendedFoods()
    }
    
    private func fetchRecents() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchRecentFoodItems(for: userID) { result in
            if case .success(let items) = result {
                self.recentFoods = items
            }
        }
    }
    
    private func fetchRecommendedFoods() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchRecommendedFoods(for: userID, mealName: selectedMeal) { result in
            if case .success(let items) = result {
                self.recommendedFoods = items
            }
        }
    }
    
    private func deleteRecent(at offsets: IndexSet) {
        recentFoods.remove(atOffsets: offsets)
    }
}

private struct SearchResultsSection: View {
    let results: [FoodItem]
    let onSelect: (FoodItem) -> Void

    var body: some View {
        Section(header: Text("Search Results")) {
            ForEach(results) { food in
                Button(action: { onSelect(food) }) {
                    HStack(spacing: 15) {
                        Text(FoodEmojiMapper.getEmoji(for: food.name)).font(.title)
                        VStack(alignment: .leading) {
                            Text(food.name)
                            Text(food.servingSize).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }
}

private struct RecommendedSection: View {
    let foods: [FoodItem]
    let onSelect: (FoodItem) -> Void

    var body: some View {
        Section(header: Text("Recommended")) {
            ForEach(foods) { food in
                Button(action: { onSelect(food) }) {
                    HStack(spacing: 15) {
                        Text(FoodEmojiMapper.getEmoji(for: food.name)).font(.title)
                        VStack(alignment: .leading) {
                            Text(food.name)
                            Text("\(Int(food.calories)) cal").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }
}

private struct RecentSection: View {
    @Binding var foods: [FoodItem]
    let onDelete: (IndexSet) -> Void
    let onSelect: (FoodItem) -> Void

    var body: some View {
        Section(header: Text("Recent")) {
            ForEach(foods) { food in
                Button(action: { onSelect(food) }) {
                    HStack {
                        Text(FoodEmojiMapper.getEmoji(for: food.name)).font(.title)
                        VStack(alignment: .leading) {
                            Text(food.name)
                            Text("\(Int(food.calories)) cal").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .foregroundColor(.primary)
                }
            }
            .onDelete(perform: onDelete)
        }
    }
}
