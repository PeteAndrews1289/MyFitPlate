import SwiftUI
import MyFitPlateCore

enum FoodSearchInitialPresentation {
    case none
    case chainBuilder
}

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String
    var trainingFuelTarget: TrainingFuelTarget?

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    @StateObject private var viewModel: FoodSearchViewModel
    @StateObject private var voiceLoggingService = VoiceLoggingService(engine: SpeechCaptureEngine())

    @State private var showingAddFoodManually = false
    @State private var showingQuickAddMacros = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingMenuImagePicker = false
    @State private var showingAITextLog = false
    @State private var showingValueRadar = false
    @State private var showingChainBuilder = false
    @State private var showingMyFoodsLibrary = false

    @State private var selectedFoodItem: FoodItem?
    @State private var selectedFoodSource: String = "search_result"

    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems?
    @State private var scannedBarcodeItemsWrapper: IdentifiableFoodItems?
    @State private var estimatedMenuWrapper: IdentifiableFoodItems?
    @State private var scannedFoodItem: FoodItem?
    @State private var scannedFoodSource: String = "barcode_result"
    @State private var pendingManualBarcode: String?
    @State private var showingBarcodeRecovery = false
    @State private var barcodeRecoveryMessage = ""
    @State private var barcodeRecoveryResolved = false
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    private let barcodeLookupService = BarcodeFoodLookupService()
    private let imageModel = MLImageModel()

    init(
        dailyLog: Binding<DailyLog?>,
        onFoodItemLogged: (() -> Void)? = nil,
        onFoodItemSelected: ((FoodItem) -> Void)? = nil,
        searchContext: String,
        initialPresentation: FoodSearchInitialPresentation = .none,
        trainingFuelTarget: TrainingFuelTarget? = nil
    ) {
        _dailyLog = dailyLog
        self.onFoodItemLogged = onFoodItemLogged
        self.onFoodItemSelected = onFoodItemSelected
        self.searchContext = searchContext
        self.trainingFuelTarget = trainingFuelTarget

        #if DEBUG
        let screenshotScreen = ScreenshotDemoData.requestedScreen
        _viewModel = StateObject(
            wrappedValue: FoodSearchViewModel(
                selectedMeal: ScreenshotDemoMode.isEnabled ? "Dinner" : nil
            )
        )
        _showingChainBuilder = State(
            initialValue: initialPresentation == .chainBuilder || screenshotScreen == "builder"
        )
        _showingAddFoodManually = State(initialValue: screenshotScreen == "add-food")
        _showingMyFoodsLibrary = State(initialValue: screenshotScreen == "my-foods")
        _selectedFoodItem = State(
            initialValue: screenshotScreen == "trust" ? ScreenshotDemoData.trustDemoFood : nil
        )
        #else
        _viewModel = StateObject(wrappedValue: FoodSearchViewModel())
        _showingChainBuilder = State(initialValue: initialPresentation == .chainBuilder)
        #endif
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        if let trainingFuelTarget {
                            TrainingFuelTargetContextView(target: trainingFuelTarget)
                        }
                        mainActionContent
                        searchOrSavedContent
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.section)
                }
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(onFoodItemSelected == nil ? "Log food" : "Select ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    if onFoodItemSelected == nil {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingMyFoodsLibrary = true
                            } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Manage My Foods")
                        }
                    }
                }
                .onAppear {
                    viewModel.setup(dailyLogService: dailyLogService)
                    viewModel.fetchData()
                }
                .onChange(of: viewModel.selectedMeal) { _, _ in
                    if let userID = DIContainer.shared.authService.currentUserID {
                        viewModel.fetchRecommendedFoods(userID: userID)
                        viewModel.fetchYesterdayMeal(userID: userID)
                    }
                }
                .sheet(isPresented: $showingAddFoodManually, onDismiss: { pendingManualBarcode = nil }) {
                    NavigationStack {
                        AddFoodView(
                            initialFoodItem: manualFoodSeed(),
                            dailyLog: $dailyLogService.currentDailyLog,
                            date: dailyLogService.activelyViewedDate,
                            source: pendingManualBarcode == nil ? "manual_add" : "manual_barcode_create",
                            targetMealName: viewModel.selectedMeal,
                            onLogUpdated: {
                                showingAddFoodManually = false
                                pendingManualBarcode = nil
                                onFoodItemLogged?()
                            }
                        )
                    }
                }
                .sheet(isPresented: $showingQuickAddMacros) {
                    QuickAddMacrosView(
                        selectedMealType: viewModel.selectedMeal,
                        targetDate: dailyLogService.activelyViewedDate
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView(
                        onBarcodeDetected: { barcode in
                            let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
                            self.showingBarcodeScanner = false
                            self.isSearchingAfterScan = true
                            self.pendingManualBarcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
                            DIContainer.shared.analyticsManager.log(.barcodeScanned, [:])
                            Task { @MainActor in
                                if let result = await barcodeLookupService.lookup(barcode) {
                                    self.isSearchingAfterScan = false
                                    self.pendingManualBarcode = nil
                                    self.scannedFoodSource = result.source
                                    self.scannedFoodItem = result.item
                                    showBarcodeResultFeedback(result)
                                    return
                                }
                                self.isSearchingAfterScan = false
                                self.presentBarcodeRecovery(
                                    message: "No match found in FatSecret, USDA, or Open Food Facts.",
                                    barcode: barcode
                                )
                            }
                        },
                        onBarcodesDetected: { barcodes in
                            self.showingBarcodeScanner = false
                            self.isSearchingAfterScan = true
                            Task { @MainActor in
                                var foundItems: [FoodItem] = []
                                for barcode in barcodes {
                                    if let result = await barcodeLookupService.lookup(barcode) {
                                        foundItems.append(result.item)
                                    }
                                }
                                self.isSearchingAfterScan = false
                                if !foundItems.isEmpty {
                                    // Scanned barcodes are exact product lookups, not an AI meal
                                    // estimate — log each as its own entry in the selected meal.
                                    self.scannedBarcodeItemsWrapper = IdentifiableFoodItems(items: foundItems)
                                } else {
                                    self.presentBarcodeRecovery(
                                        message: "No items in the rapid scan tray could be matched to our databases.",
                                        barcode: barcodes.first
                                    )
                                }
                            }
                        }
                    )
                }
                .imageSourceDialog(isPresented: $showingImagePicker) { image in
                    self.isProcessingImage = true
                    DIContainer.shared.analyticsManager.aiFeatureUsed(.mealPhoto)
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
                        DIContainer.shared.analyticsManager.aiFeatureUsed(.menuPhoto)
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
                .sheet(isPresented: $showingValueRadar) { RestaurantValueRadarView() }
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
                        source: scannedFoodSource,
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
                .sheet(item: $scannedBarcodeItemsWrapper) { wrapper in
                     AISummaryView(
                        estimatedItems: .constant(wrapper.items),
                        mealName: viewModel.selectedMeal,
                        source: "barcode",
                        isAIEstimate: false,
                        reviewTitle: "Review scanned items"
                     )
                }
                .sheet(item: $estimatedMenuWrapper) { wrapper in
                     AIMenuSelectionView(estimatedItems: .constant(wrapper.items))
                }
                .sheet(isPresented: $showingChainBuilder) {
                    ChainMealBuilderView(
                        initialMeal: viewModel.selectedMeal,
                        trainingFuelTarget: trainingFuelTarget
                    ) { mealItem, mealName in
                        viewModel.selectedMeal = mealName
                        handleSelection(food: mealItem, source: "chain_builder")
                    }
                }
                .sheet(isPresented: $showingMyFoodsLibrary) {
                    MyFoodsLibraryView(
                        initialFoods: myFoodsInitialFoods,
                        recentFoods: myFoodsRecentFoods,
                        loadsRemoteData: myFoodsLoadsRemoteData,
                        onLibraryChanged: refreshSavedFoods
                    )
                }
                .sheet(isPresented: $showingBarcodeRecovery, onDismiss: handleBarcodeRecoveryDismissed) {
                    BarcodeMissRecoveryView(
                        message: barcodeRecoveryMessage,
                        barcode: pendingManualBarcode,
                        createFromLabel: createFoodFromBarcodeMiss,
                        useCamera: useCameraFromBarcodeMiss,
                        searchByName: searchByNameFromBarcodeMiss,
                        dismiss: dismissBarcodeRecovery
                    )
                }
                .alert("Scan error", isPresented: $scanError.0) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(scanError.1)
                }

                if isProcessingImage || isSearchingAfterScan {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView(isProcessingImage ? "Analyzing image" : "Searching barcode")
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
                title: "Smart history",
                subtitle: "One tap on + repeats your usual \(viewModel.selectedMeal.lowercased()).",
                foods: viewModel.recommendedFoods,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "smart_history_quick_log") } : nil,
                source: "recent_tap"
            )
        }
    }

    private func manualFoodSeed() -> FoodItem {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled, ScreenshotDemoData.requestedScreen == "add-food" {
            return ScreenshotDemoData.manualFoodDemoFood
        }
        #endif

        let metadata: FoodSourceMetadata?
        if let pendingManualBarcode, !pendingManualBarcode.isEmpty {
            metadata = FoodSourceMetadata(
                sourceType: .manual,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "Manual Barcode Entry",
                barcode: pendingManualBarcode,
                notes: "Created after a barcode lookup miss."
            )
        } else {
            metadata = nil
        }

        return FoodItem(
            id: UUID().uuidString,
            name: "",
            calories: 0,
            protein: 0,
            carbs: 0,
            fats: 0,
            servingSize: "",
            servingWeight: 0,
            sourceMetadata: metadata
        )
    }

    private var myFoodsInitialFoods: [FoodItem] {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled, ScreenshotDemoData.requestedScreen == "my-foods" {
            return ScreenshotDemoData.myFoodsDemoFoods
        }
        #endif
        return viewModel.savedFoods
    }

    private var myFoodsRecentFoods: [FoodItem] {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled, ScreenshotDemoData.requestedScreen == "my-foods" {
            return ScreenshotDemoData.myFoodsDemoRecentFoods
        }
        #endif
        return viewModel.recentFoods
    }

    private var myFoodsLoadsRemoteData: Bool {
        #if DEBUG
        return !(ScreenshotDemoMode.isEnabled && ScreenshotDemoData.requestedScreen == "my-foods")
        #else
        return true
        #endif
    }

    @ViewBuilder
    private var searchHeaderContent: some View {
        FoodSearchHeader(
            searchText: $viewModel.searchText,
            placeholder: onFoodItemSelected == nil ? "Search foods, meals, brands" : "Search ingredients",
            onClear: {
                viewModel.searchText = ""
                viewModel.handleSearchQueryChange("")
            },
            onSubmit: {
                viewModel.submitSearch()
                hideKeyboard()
            },
            onMic: { toggleVoiceRecording() },
            isRecording: voiceLoggingService.state == .recording
        )
        .onChange(of: voiceLoggingService.state) { _, newState in
            handleVoiceStateChange(newState)
        }
    }

    @ViewBuilder
    private var mealTargetContent: some View {
        if onFoodItemSelected == nil {
            if viewModel.isSearching {
                FoodSearchCompactMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])
            } else {
                FoodSearchMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])
            }
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
                textAction: { showingAITextLog = true },
                valueRadarAction: { showingValueRadar = true },
                chainBuilderAction: { showingChainBuilder = true }
            )
        }
    }

    private var hasFastRepeatOptions: Bool {
        onFoodItemSelected == nil &&
        !viewModel.isSearching &&
        (viewModel.hasYesterdayFoods ||
         !viewModel.recommendedFoods.isEmpty ||
         !viewModel.savedFoods.isEmpty ||
         !viewModel.recentFoods.isEmpty)
    }

    @ViewBuilder
    private var fastRepeatContent: some View {
        if hasFastRepeatOptions {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: "Repeat faster",
                    subtitle: "Your history is the fastest way to log today."
                )
                .accessibilityIdentifier("food_search_repeat_section")

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

                smartHistoryContent

                if !viewModel.savedFoods.isEmpty {
                    FoodHorizontalScroller(
                        title: "My foods",
                        subtitle: "Saved foods with your usual serving.",
                        foods: viewModel.savedFoods,
                        quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                        emptyTitle: "",
                        emptyMessage: "",
                        onSelect: { handleSelection(food: $0, source: "custom_food") },
                        onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "saved_food_quick_log") } : nil,
                        source: "custom_food",
                        headerActionTitle: "Manage",
                        headerAction: { showingMyFoodsLibrary = true }
                    )
                }

                if !viewModel.recentFoods.isEmpty {
                    FoodHorizontalScroller(
                        title: "Recent foods",
                        subtitle: "Same foods again in two taps.",
                        foods: viewModel.recentFoods,
                        quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                        emptyTitle: "",
                        emptyMessage: "",
                        onSelect: { handleSelection(food: $0, source: "recent_tap") },
                        onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "recent_food_quick_log") } : nil,
                        source: "recent_tap"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var mainActionContent: some View {
        searchHeaderContent
        if voiceLoggingService.state == .recording || voiceLoggingService.state == .transcribing {
            voiceRecordingBanner
        }
        mealTargetContent
        fastRepeatContent
        alternateLoggingContent
    }

    @ViewBuilder
    private var alternateLoggingContent: some View {
        if onFoodItemSelected == nil && !viewModel.isSearching {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "More ways to log",
                    subtitle: "Scan, describe, or build a meal when search is not the fastest route."
                )
                actionGridContent
            }
            .accessibilityIdentifier("food_search_alternate_actions")
        }
    }

    @ViewBuilder
    private var searchingStateContent: some View {
        let trustedResults = viewModel.trustedSearchResults

        if !trustedResults.isEmpty {
            FoodPickerSection(
                title: "Best matches",
                subtitle: "Saved and recent foods from your history.",
                foods: trustedResults,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: {
                    handleSelection(
                        food: $0,
                        source: viewModel.sourceForTrustedSearchResult($0)
                    )
                },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "best_match_quick_log") } : nil,
                onDelete: nil,
                sourceForFood: { viewModel.sourceForTrustedSearchResult($0) }
            )
        }

        if viewModel.isLoading {
            FoodSearchLoadingState(query: viewModel.searchText)
        } else if let searchErrorMessage = viewModel.searchErrorMessage, viewModel.searchResults.isEmpty {
            FoodSearchEmptyState(
                icon: "wifi.exclamationmark",
                title: String(localized: "Search could not load"),
                message: searchErrorMessage,
                primaryActionTitle: String(localized: "Try again"),
                primaryAction: { viewModel.submitSearch() },
                secondaryActionTitle: onFoodItemSelected == nil ? String(localized: "Create food") : nil,
                secondaryAction: onFoodItemSelected == nil ? { showingAddFoodManually = true } : nil
            )
        } else if viewModel.searchResults.isEmpty && trustedResults.isEmpty {
            FoodSearchEmptyState(
                icon: "magnifyingglass",
                title: String(localized: "No foods found"),
                message: String(localized: "Try a simpler search like \"chicken breast\", or create the food yourself."),
                primaryActionTitle: onFoodItemSelected == nil ? String(localized: "Create food") : nil,
                primaryAction: onFoodItemSelected == nil ? { showingAddFoodManually = true } : nil
            )
        } else if !viewModel.searchResults.isEmpty {
            FoodPickerSection(
                title: "Search results",
                subtitle: "Tap a food to review servings before logging to \(viewModel.selectedMeal).",
                foods: viewModel.searchResults,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "search_result") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "search_result_quick_log") } : nil,
                onDelete: nil,
                sourceForFood: { _ in "search_result" }
            )
        }
    }

    @ViewBuilder
    private var savedAndRecentFoodsContent: some View {
        FoodHorizontalScroller(
            title: "My foods",
            subtitle: "Saved foods with your usual serving.",
            foods: viewModel.savedFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No saved foods yet",
            emptyMessage: "Star foods from detail screens and they will appear here.",
            onSelect: { handleSelection(food: $0, source: "custom_food") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "saved_food_quick_log") } : nil,
            source: "custom_food",
            headerActionTitle: onFoodItemSelected == nil ? "Manage" : nil,
            headerAction: onFoodItemSelected == nil ? { showingMyFoodsLibrary = true } : nil
        )

        FoodHorizontalScroller(
            title: "Recent foods",
            subtitle: "Your fastest path for repeat meals.",
            foods: viewModel.recentFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No recent foods",
            emptyMessage: "Foods you log will appear here for one-tap reuse.",
            onSelect: { handleSelection(food: $0, source: "recent_tap") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0, source: "recent_food_quick_log") } : nil,
            source: "recent_tap"
        )
    }

    @ViewBuilder
    private var searchOrSavedContent: some View {
        if viewModel.isSearching {
            searchingStateContent
        } else if hasFastRepeatOptions {
            EmptyView()
        } else {
            savedAndRecentFoodsContent
        }
    }

    private func handleSelection(food: FoodItem, source: String) {
        if let selectionHandler = onFoodItemSelected {
            guard source == "search_result", FoodSearchRanking.isFatSecretID(food.id) else {
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

    private func refreshSavedFoods() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        viewModel.fetchSavedFoods(userID: userID)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func showBarcodeResultFeedback(_ result: BarcodeFoodLookupResult) {
        if result.source == "custom_barcode" {
            ToastManager.shared.showToast(message: "Matched from My Foods.")
        } else if result.usedRelatedBarcode {
            ToastManager.shared.showToast(message: "Found a related barcode match.")
        }
    }

    private func presentBarcodeRecovery(message: String, barcode: String?) {
        let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode ?? "")
        pendingManualBarcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
        barcodeRecoveryMessage = message
        barcodeRecoveryResolved = false
        showingBarcodeRecovery = true
        DIContainer.shared.analyticsManager.barcodeMissRecovery(
            .selected(action: "recovery_shown", barcode: pendingManualBarcode)
        )
    }

    private func handleBarcodeRecoveryDismissed() {
        if !barcodeRecoveryResolved {
            DIContainer.shared.analyticsManager.barcodeMissRecovery(
                .selected(action: "dismissed", barcode: pendingManualBarcode)
            )
            pendingManualBarcode = nil
        }
        barcodeRecoveryMessage = ""
    }

    private func resolveBarcodeRecovery(action: String) {
        barcodeRecoveryResolved = true
        DIContainer.shared.analyticsManager.barcodeMissRecovery(
            .selected(action: action, barcode: pendingManualBarcode)
        )
        showingBarcodeRecovery = false
    }

    private func createFoodFromBarcodeMiss() {
        resolveBarcodeRecovery(action: "create_from_label")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingAddFoodManually = true
        }
    }

    private func useCameraFromBarcodeMiss() {
        resolveBarcodeRecovery(action: "use_camera")
        pendingManualBarcode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingImagePicker = true
        }
    }

    private func searchByNameFromBarcodeMiss() {
        resolveBarcodeRecovery(action: "search_by_name")
        pendingManualBarcode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            viewModel.searchText = ""
            viewModel.handleSearchQueryChange("")
            ToastManager.shared.showToast(message: "Search by brand or product name.")
        }
    }

    private func dismissBarcodeRecovery() {
        barcodeRecoveryResolved = true
        DIContainer.shared.analyticsManager.barcodeMissRecovery(
            .selected(action: "dismissed", barcode: pendingManualBarcode)
        )
        pendingManualBarcode = nil
        showingBarcodeRecovery = false
    }

    private func deleteRecent(food: FoodItem) {
        viewModel.recentFoods.removeAll { $0.id == food.id }
    }

    private var voiceRecordingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: voiceLoggingService.state == .recording ? "waveform.circle.fill" : "sparkles")
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Color.accentProtein, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(voiceLoggingService.state == .recording ? "Listening... Tap mic or here to stop" : "Transcribing your meal...")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("Speak naturally, e.g., 'Two eggs and a slice of toast'")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            if voiceLoggingService.state == .recording {
                Button {
                    HapticManager.instance.feedback(.medium)
                    stopAndProcessVoiceLog()
                } label: {
                    Text("Done")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentProtein, in: Capsule())
                }
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .background(Color.accentProtein.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentProtein.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            if voiceLoggingService.state == .recording {
                HapticManager.instance.feedback(.medium)
                stopAndProcessVoiceLog()
            }
        }
    }

    private func toggleVoiceRecording() {
        if voiceLoggingService.state == .recording {
            HapticManager.instance.feedback(.medium)
            stopAndProcessVoiceLog()
        } else {
            do {
                try voiceLoggingService.startRecording()
                HapticManager.instance.feedback(.light)
            } catch {
                scanError = (true, "Could not start microphone: \(error.localizedDescription)")
            }
        }
    }

    private func stopAndProcessVoiceLog() {
        Task { @MainActor in
            do {
                let result = try await voiceLoggingService.stopRecording()
                if result.transcript.count > 3 {
                    HapticManager.instance.notification(.success)
                    viewModel.searchText = result.transcript
                    viewModel.handleSearchQueryChange(result.transcript)
                } else {
                    ToastManager.shared.showToast(message: "Didn't catch that — try again or type it.")
                }
            } catch {
                scanError = (true, "Voice recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleVoiceStateChange(_ state: VoiceLoggingState) {
        guard state == .error else { return }
        scanError = (true, "Voice search needs microphone and speech recognition access. Enable both for MyFitPlate in Settings.")
        voiceLoggingService.acknowledgeError()
    }
}

struct BarcodeMissRecoveryView: View {
    let message: String
    let barcode: String?
    let createFromLabel: () -> Void
    let useCamera: () -> Void
    let searchByName: () -> Void
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "barcode.viewfinder")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 54, height: 54)
                        .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("Barcode not found")
                        .appFont(size: 26, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(message)
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    if let barcode, !barcode.isEmpty {
                        Text("Scanned \(barcode)")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.backgroundSecondary.opacity(0.78), in: Capsule())
                    }
                }

                VStack(spacing: 10) {
                    recoveryButton(
                        icon: "camera.macro",
                        title: "Create from label",
                        subtitle: "Use the manual food screen and scan the nutrition label.",
                        tint: .brandPrimary,
                        action: createFromLabel
                    )

                    recoveryButton(
                        icon: "camera.fill",
                        title: "Use camera estimate",
                        subtitle: "Photograph the food when the package data is missing.",
                        tint: .accentProtein,
                        action: useCamera
                    )

                    recoveryButton(
                        icon: "magnifyingglass",
                        title: "Search by name",
                        subtitle: "Try the brand, product name, or a simpler food description.",
                        tint: .accentSignal,
                        action: searchByName
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: 560, alignment: .leading)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: dismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func recoveryButton(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}
