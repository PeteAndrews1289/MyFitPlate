import SwiftUI
import MyFitPlateCore

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    @StateObject private var viewModel = FoodSearchViewModel()
    @StateObject private var voiceLoggingService = VoiceLoggingService(engine: SpeechCaptureEngine())

    @State private var showingAddFoodManually = false
    @State private var showingQuickAddMacros = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingMenuImagePicker = false
    @State private var showingAITextLog = false

    @State private var selectedFoodItem: FoodItem?
    @State private var selectedFoodSource: String = "search_result"

    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems?
    @State private var estimatedMenuWrapper: IdentifiableFoodItems?
    @State private var scannedFoodItem: FoodItem?
    @State private var scannedFoodSource: String = "barcode_result"
    @State private var pendingManualBarcode: String?
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    private let barcodeLookupService = BarcodeFoodLookupService()
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
                .navigationTitle(onFoodItemSelected == nil ? "Log food" : "Select ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                .sheet(isPresented: $showingAddFoodManually) {
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
                .sheet(isPresented: $showingQuickAddMacros) {
                    QuickAddMacrosView(
                        selectedMealType: viewModel.selectedMeal,
                        targetDate: dailyLogService.activelyViewedDate
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView { barcode in
                        let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
                        self.showingBarcodeScanner = false
                        self.isSearchingAfterScan = true
                        self.pendingManualBarcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
                        DIContainer.shared.analyticsManager.log(.barcodeScanned, [:])
                        Task { @MainActor in
                            if let result = await barcodeLookupService.lookup(barcode) {
                                DIContainer.shared.analyticsManager.barcodeLookupOutcome(.success(result))
                                self.isSearchingAfterScan = false
                                self.pendingManualBarcode = nil
                                self.scannedFoodSource = result.source
                                self.scannedFoodItem = result.item
                                showBarcodeResultFeedback(result)
                                return
                            }
                            DIContainer.shared.analyticsManager.barcodeLookupOutcome(.miss(barcode: barcode))
                            self.isSearchingAfterScan = false
                            self.scanError = (true, "No match found in FatSecret, USDA, or Open Food Facts. Create it from the label, use camera capture, or search by name.")
                        }
                    }
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
                .sheet(item: $estimatedMenuWrapper) { wrapper in
                     AIMenuSelectionView(estimatedItems: .constant(wrapper.items))
                }
                .alert("Scan error", isPresented: $scanError.0) {
                    Button("Create food") {
                        DIContainer.shared.analyticsManager.barcodeMissRecovery(
                            .selected(action: "create_food", barcode: pendingManualBarcode)
                        )
                        showingAddFoodManually = true
                    }
                    Button("Use camera") {
                        DIContainer.shared.analyticsManager.barcodeMissRecovery(
                            .selected(action: "use_camera", barcode: pendingManualBarcode)
                        )
                        pendingManualBarcode = nil
                        showingImagePicker = true
                    }
                    Button("OK", role: .cancel) {
                        DIContainer.shared.analyticsManager.barcodeMissRecovery(
                            .selected(action: "dismissed", barcode: pendingManualBarcode)
                        )
                        pendingManualBarcode = nil
                    }
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
                subtitle: "Based on \(viewModel.selectedMeal) and past logging.",
                foods: viewModel.recommendedFoods,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
                source: "recent_tap"
            )
        }
    }

    private func manualFoodSeed() -> FoodItem {
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

    @ViewBuilder
    private var searchHeaderContent: some View {
        FoodSearchHeader(
            searchText: $viewModel.searchText,
            placeholder: onFoodItemSelected == nil ? "Search foods, meals, brands" : "Search ingredients",
            onClear: {
                viewModel.searchText = ""
                viewModel.handleSearchQueryChange("")
            },
            onSubmit: hideKeyboard,
            onMic: { toggleVoiceRecording() },
            isRecording: voiceLoggingService.state == .recording
        )
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.handleSearchQueryChange(newValue)
        }
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
                textAction: { showingAITextLog = true }
            )

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
        searchHeaderContent
        if voiceLoggingService.state == .recording || voiceLoggingService.state == .transcribing {
            voiceRecordingBanner
        }
        mealTargetContent
        actionGridContent
        smartHistoryContent
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
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
                onDelete: nil,
                sourceForFood: { viewModel.sourceForTrustedSearchResult($0) }
            )
        }

        if viewModel.isLoading {
            FoodSearchLoadingState(query: viewModel.searchText)
        } else if let searchErrorMessage = viewModel.searchErrorMessage, viewModel.searchResults.isEmpty {
            FoodSearchEmptyState(
                icon: "wifi.exclamationmark",
                title: "Search could not load",
                message: searchErrorMessage
            )
        } else if viewModel.searchResults.isEmpty && trustedResults.isEmpty {
            FoodSearchEmptyState(
                icon: "magnifyingglass",
                title: "No foods found",
                message: "Try a simpler search like \"chicken breast\", or add it manually."
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
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
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
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
            source: "custom_food"
        )

        FoodHorizontalScroller(
            title: "Recent foods",
            subtitle: "Your fastest path for repeat meals.",
            foods: viewModel.recentFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No recent foods",
            emptyMessage: "Foods you log will appear here for one-tap reuse.",
            onSelect: { handleSelection(food: $0, source: "recent_tap") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
            source: "recent_tap"
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

    private func showBarcodeResultFeedback(_ result: BarcodeFoodLookupResult) {
        if result.source == "custom_barcode" {
            ToastManager.shared.showToast(message: "Matched from My Foods.")
        } else if result.usedRelatedBarcode {
            ToastManager.shared.showToast(message: "Found a related barcode match.")
        }
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
