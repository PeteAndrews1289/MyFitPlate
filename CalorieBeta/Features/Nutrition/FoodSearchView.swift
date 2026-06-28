import SwiftUI
import FirebaseAuth

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    @StateObject private var viewModel = FoodSearchViewModel()

    @State private var showingAddFoodManually = false
    @State private var showingQuickAddMacros = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingMenuImagePicker = false
    @State private var showingAITextLog = false

    @State private var selectedFoodItem: FoodItem? = nil
    @State private var selectedFoodSource: String = "search_result"

    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    @State private var estimatedMenuWrapper: IdentifiableFoodItems? = nil
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()
    private let imageModel = MLImageModel()

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mainActionContent
                        searchOrSavedContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(onFoodItemSelected == nil ? "Log Food" : "Select Ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .onAppear {
                    viewModel.setup(dailyLogService: dailyLogService)
                    viewModel.fetchData()
                }
                .onChange(of: viewModel.selectedMeal) { _, _ in
                    if let userID = Auth.auth().currentUser?.uid {
                        viewModel.fetchRecommendedFoods(userID: userID)
                        viewModel.fetchYesterdayMeal(userID: userID)
                    }
                }
                .sheet(isPresented: $showingAddFoodManually) {
                    AddFoodView(
                        initialFoodItem: FoodItem(id: UUID().uuidString, name: "", calories: 0, protein: 0, carbs: 0, fats: 0, servingSize: "", servingWeight: 0),
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "manual_add",
                        targetMealName: viewModel.selectedMeal,
                        onLogUpdated: {
                            showingAddFoodManually = false
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(isPresented: $showingQuickAddMacros) {
                    QuickAddMacrosView(
                        selectedMealType: viewModel.selectedMeal,
                        targetDate: dailyLogService.activelyViewedDate
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView { barcode in
                        self.showingBarcodeScanner = false
                        self.isSearchingAfterScan = true
                        AnalyticsManager.log(.barcodeScanned)
                        Task { @MainActor in
                            if let item = await withCheckedContinuation({ cont in
                                foodAPIService.fetchFoodByBarcode(barcode: barcode) { cont.resume(returning: try? $0.get()) }
                            }) {
                                self.isSearchingAfterScan = false
                                self.scannedFoodItem = item
                                return
                            }
                            if let item = await usdaService.lookupBarcode(barcode) {
                                self.isSearchingAfterScan = false
                                self.scannedFoodItem = item
                                return
                            }
                            self.isSearchingAfterScan = false
                            self.scanError = (true, "No food found for this barcode.")
                        }
                    }
                }
                .imageSourceDialog(isPresented: $showingImagePicker) { image in
                    self.isProcessingImage = true
                    AnalyticsManager.aiFeatureUsed(.mealPhoto)
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
                .sheet(isPresented: $showingMenuImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingImage = true
                        AnalyticsManager.aiFeatureUsed(.menuPhoto)
                        imageModel.estimateMenuFromImage(image: image) { result in
                            self.isProcessingImage = false
                            switch result {
                            case .success(let foodItems):
                                self.estimatedMenuWrapper = IdentifiableFoodItems(items: foodItems)
                            case .failure(let error):
                                self.scanError = (true, "Could not analyze the menu. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAITextLog) { AITextLogView() }
                .sheet(item: $selectedFoodItem) { foodItem in
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: selectedFoodSource,
                        targetMealName: viewModel.selectedMeal,
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
                        source: foodItem.id.hasPrefix("usda_") ? "usda_barcode" : "barcode_result",
                        targetMealName: viewModel.selectedMeal,
                        onLogUpdated: {
                            self.scannedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                     AISummaryView(estimatedItems: .constant(wrapper.items))
                }
                .sheet(item: $estimatedMenuWrapper) { wrapper in
                     AIMenuSelectionView(estimatedItems: .constant(wrapper.items))
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

    @ViewBuilder
    private var smartHistoryContent: some View {
        if onFoodItemSelected == nil && !viewModel.isSearching && !viewModel.recommendedFoods.isEmpty {
            FoodHorizontalScroller(
                title: "Smart History",
                subtitle: "Based on \(viewModel.selectedMeal) and past logging.",
                foods: viewModel.recommendedFoods,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
            )
        }
    }

    @ViewBuilder
    private var searchHeaderContent: some View {
        FoodSearchHeader(
            searchText: $viewModel.searchText,
            placeholder: onFoodItemSelected == nil ? "Search foods, meals, brands..." : "Search ingredients...",
            onClear: {
                viewModel.searchText = ""
                viewModel.handleSearchQueryChange("")
            },
            onSubmit: hideKeyboard
        )
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.handleSearchQueryChange(newValue)
        }
    }

    @ViewBuilder
    private var compactMealPickerContent: some View {
        if onFoodItemSelected == nil && viewModel.isSearching {
            FoodSearchCompactMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])
        }
    }

    @ViewBuilder
    private var actionGridContent: some View {
        if onFoodItemSelected == nil && !viewModel.isSearching {
            FoodSearchActionGrid(
                manualAction: { showingAddFoodManually = true },
                quickAddAction: { showingQuickAddMacros = true },
                cameraAction: { showingImagePicker = true },
                menuAction: { showingMenuImagePicker = true },
                barcodeAction: { showingBarcodeScanner = true },
                textAction: { showingAITextLog = true }
            )

            FoodSearchMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])

            if viewModel.hasYesterdayFoods {
                YesterdayLogActions(
                    selectedMeal: viewModel.selectedMeal,
                    mealItemCount: viewModel.yesterdaysMealItems.count,
                    mealCalories: viewModel.yesterdaysMealItems.reduce(0.0) { $0 + $1.calories },
                    dayItemCount: viewModel.yesterdaysDayItems.count,
                    dayCalories: viewModel.yesterdaysDayItems.reduce(0.0) { $0 + $1.calories },
                    onLogMeal: { viewModel.logYesterdayMeal() },
                    onLogDay: { viewModel.logYesterdayDay() }
                )
            }
        }
    }

    @ViewBuilder
    private var mainActionContent: some View {
        smartHistoryContent
        searchHeaderContent
        compactMealPickerContent
        actionGridContent
    }

    @ViewBuilder
    private var searchingStateContent: some View {
        if viewModel.isLoading {
            FoodSearchLoadingState(query: viewModel.searchText)
        } else if let searchErrorMessage = viewModel.searchErrorMessage {
            FoodSearchEmptyState(
                icon: "wifi.exclamationmark",
                title: "Search could not load",
                message: searchErrorMessage
            )
        } else if viewModel.searchResults.isEmpty {
            FoodSearchEmptyState(
                icon: "magnifyingglass",
                title: "No foods found",
                message: "Try a simpler search like \"chicken breast\", or add it manually."
            )
        } else {
            FoodPickerSection(
                title: "Search Results",
                subtitle: "Tap a food to review servings before logging to \(viewModel.selectedMeal).",
                foods: viewModel.searchResults,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "search_result") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
                onDelete: nil
            )
        }
    }

    @ViewBuilder
    private var savedAndRecentFoodsContent: some View {
        FoodHorizontalScroller(
            title: "My Foods",
            subtitle: "Saved foods with your usual serving.",
            foods: viewModel.savedFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No saved foods yet",
            emptyMessage: "Star foods from detail screens and they will appear here.",
            onSelect: { handleSelection(food: $0, source: "custom_food") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
        )

        FoodHorizontalScroller(
            title: "Recent Foods",
            subtitle: "Your fastest path for repeat meals.",
            foods: viewModel.recentFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No recent foods",
            emptyMessage: "Foods you log will appear here for one-tap reuse.",
            onSelect: { handleSelection(food: $0, source: "recent_tap") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
        )
    }

    @ViewBuilder
    private var searchOrSavedContent: some View {
        if viewModel.isSearching {
            searchingStateContent
        } else {
            savedAndRecentFoodsContent
        }
    }

    private func handleSelection(food: FoodItem, source: String) {
        if let selectionHandler = onFoodItemSelected {
            guard source == "search_result", isLikelyFoodAPIID(food.id) else {
                selectionHandler(food)
                return
            }

            isSearchingAfterScan = true
            foodAPIService.fetchFoodDetails(foodId: food.id) { result in
                DispatchQueue.main.async {
                    isSearchingAfterScan = false
                    switch result {
                    case .success(let (detailedFood, _)):
                        selectionHandler(detailedFood)
                    case .failure(let error):
                        AppLog.data.error("Failed to fetch food details: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } else {
            selectedFoodSource = source
            self.selectedFoodItem = food
        }
    }

    private func isLikelyFoodAPIID(_ id: String) -> Bool {
        id.count < 20 && !id.contains("-")
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func deleteRecent(food: FoodItem) {
        viewModel.recentFoods.removeAll { $0.id == food.id }
    }
}

