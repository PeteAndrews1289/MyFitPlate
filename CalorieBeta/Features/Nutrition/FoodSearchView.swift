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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var dailyLogService: DailyLogService

    @StateObject private var viewModel: FoodSearchViewModel
    @StateObject private var voiceLoggingService = VoiceLoggingService(engine: SpeechCaptureEngine())
    @State private var foodDetailPresentationState = FoodDetailPresentationState()

    @State private var showingAddFoodManually = false
    @State private var showingQuickAddMacros = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingMenuImagePicker = false
    @State private var showingAITextLog = false
    private struct ValueRadarDestination: Identifiable {
        let id = UUID()
        let date: Date
        let mealName: String
    }
    @State private var valueRadarDestination: ValueRadarDestination?
    @State private var showingChainBuilder = false
    private struct ChainComponentsReview { let ownerID: String; let items: [FoodItem]; let day: DiaryDayContext; let mealName: String }
    @State private var chainComponentsReview: ChainComponentsReview?
    private enum OtherLog: String, Identifiable {
        case activity, recipes, buffet, running
        var id: Self { self }
    }
    @State private var otherLog: OtherLog?
    @State private var showingMyFoodsLibrary = false
    @State private var repeatScope = "Usual"
    @State private var showAllRepeatFoods = false
    private struct TransferReview: Identifiable { let id = UUID(); let session: DiaryTransferSession }
    @State private var transferReview: TransferReview?
    @State private var transferReviewError: String?
    @State private var diarySyncState: DailyLogSyncState = .synced
    @State private var showingMealDraft = false
    @State private var isSearchFocused = false

    private static let compactPortionHeight = PresentationDetent.fraction(0.68)
    @State private var portionHeight = compactPortionHeight
    @State private var selectedFoodItem: FoodItem?
    @State private var selectedFoodSource: String = "search_result"
    private struct FoodSelectionContext {
        let ownerID: String?
        let date: Date
        let mealName: String
        let sourceID: String
        let draftID: UUID?
        let isForMealDraft: Bool
        var replacesEntry = false
        var dayContext: DiaryDayContext?
    }
    @State private var selectedFoodContext: FoodSelectionContext?

    @State private var isProcessingImage = false
    @State private var imageProcessingKind: ImageProcessingKind = .mealPhoto
    @State private var imageAnalysisID: UUID?
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems?
    @State private var rapidBarcodeBatch: RapidBarcodeBatchCheckpoint?
    @State private var estimatedMenuWrapper: IdentifiableFoodItems?
    @State private var pendingManualBarcode: String?
    @State private var showingBarcodeRecovery = false
    @State private var barcodeRecoveryMessage = ""
    @State private var barcodeRecoveryResolved = false
    private struct CaptureDestination {
        let owner: String
        let date: Date
        let meal: String
        let day: DiaryDayContext?
        let draftID: UUID?
        var photoSource: String { draftID.map { "ai_image_selection_" + $0.uuidString } ?? "ai_image" }
    }
    @State private var capture: CaptureDestination?
    @State private var scanError: (Bool, String) = (false, "")

    private func openChainBuilder() {
        if let pending = MealReviewSaveSession.pendingReview(source: "chain_builder_components", userID: DIContainer.shared.authService.currentUserID) {
            estimatedFoodItemsWrapper = IdentifiableFoodItems(items: pending.draft.entries.map(\.food), loggingDate: pending.draft.date,
                mealName: pending.draft.mealName, source: "chain_builder_components", isAIEstimate: false,
                reviewTitle: "Review restaurant order", dayContext: pending.draft.dayContext)
        } else { showingChainBuilder = true }
    }

    private func captureDestination(forSelection: Bool = true) -> CaptureDestination? {
        guard let owner = DIContainer.shared.authService.currentUserID else { return nil }
        if forSelection, viewModel.isBuildingMeal {
            guard let draft = viewModel.draftForCapture() else { return nil }
            return CaptureDestination(owner: owner, date: draft.date, meal: draft.mealName, day: draft.dayContext, draftID: draft.id)
        }
        let date = dailyLogService.activelyViewedDate
        return CaptureDestination(owner: owner, date: date, meal: viewModel.selectedMeal,
            day: dailyLogService.diaryDayContext(for: owner, date: date), draftID: nil)
    }

    private func openMealPhoto() {
        guard let destination = captureDestination() else { return }
        capture = destination
        presentMealPhoto(at: destination)
    }

    private func presentMealPhoto(at destination: CaptureDestination) {
        if let pending = MealReviewSaveSession.pendingReview(source: destination.photoSource, userID: destination.owner) {
            estimatedFoodItemsWrapper = IdentifiableFoodItems(items: pending.draft.entries.map(\.food),
                loggingDate: pending.draft.date, mealName: pending.draft.mealName, source: destination.photoSource,
                dayContext: pending.draft.dayContext)
            return
        }
        #if DEBUG
        if ScreenshotDemoMode.isEnabled, ProcessInfo.processInfo.arguments.contains("-ui-testing-selected-meal-photo") {
            estimatedFoodItemsWrapper = IdentifiableFoodItems(items: Array(ScreenshotDemoData.aiTextDemoFoods.prefix(2)),
                loggingDate: destination.date, mealName: destination.meal, source: destination.photoSource, dayContext: destination.day)
            return
        }
        #endif
        showingImagePicker = true
    }

    private func openMenuPhoto() {
        guard let destination = captureDestination(forSelection: false) else { return }
        capture = destination
        if let pending = MealReviewSaveSession.pendingReview(source: "ai_menu", userID: destination.owner) {
            estimatedMenuWrapper = IdentifiableFoodItems(items: pending.draft.entries.map(\.food), loggingDate: pending.draft.date, mealName: pending.draft.mealName)
        } else { showingMenuImagePicker = true }
    }

    private let foodAPIService = FatSecretFoodAPIService()
    private let barcodeLookupService = BarcodeFoodLookupService()
    private let imageModel = MLImageModel()

    init(
        dailyLog: Binding<DailyLog?>,
        onFoodItemLogged: (() -> Void)? = nil,
        onFoodItemSelected: ((FoodItem) -> Void)? = nil,
        searchContext: String,
        selectedMeal: String? = nil,
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
                selectedMeal: selectedMeal ?? (ScreenshotDemoMode.isEnabled ? "Dinner" : nil), trainingFuelTarget: trainingFuelTarget
            )
        )
        _showingChainBuilder = State(
            initialValue: initialPresentation == .chainBuilder || screenshotScreen == "builder"
        )
        _showingAddFoodManually = State(initialValue: screenshotScreen == "add-food")
        _showingQuickAddMacros = State(initialValue: screenshotScreen == "quick-add-macros")
        _showingMyFoodsLibrary = State(initialValue: screenshotScreen == "my-foods")
        let screenshotFood: FoodItem?
        switch screenshotScreen {
        case "trust":
            screenshotFood = ScreenshotDemoData.trustDemoFood
        case "trust-sparse":
            screenshotFood = ScreenshotDemoData.sparseTrustDemoFood
        case "trust-correction":
            screenshotFood = ScreenshotDemoData.correctionTrustDemoFood
        default:
            screenshotFood = nil
        }
        _selectedFoodItem = State(initialValue: screenshotFood)
        #else
        _viewModel = StateObject(wrappedValue: FoodSearchViewModel(selectedMeal: selectedMeal, trainingFuelTarget: trainingFuelTarget))
        _showingChainBuilder = State(initialValue: initialPresentation == .chainBuilder)
        #endif
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    pinnedSearchHeader
                    searchResults
                    loggingFooter
                }
                .navigationTitle(onFoodItemSelected == nil ? "Log food" : searchContext == "meal_planner" ? "Choose a food" : "Select ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if onFoodItemSelected == nil {
                            Button("Done", systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly)
                        } else {
                            Button("Cancel") { dismiss() }
                        }
                    }
                    if onFoodItemSelected == nil {
                        ToolbarItem(placement: .principal) {
                            mealTargetContent.disabled(viewModel.isSavingDraft || (viewModel.isBuildingMeal && viewModel.mealDraft?.entries.isEmpty == false))
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            loggingModeButton
                            moreActions
                        }
                    }
                }
                .onAppear {
                    viewModel.setup(dailyLogService: dailyLogService)
                    viewModel.fetchData()
                    if onFoodItemSelected != nil { viewModel.isBuildingMeal = false }
                    refreshSyncState()
                }
                .onReceive(NotificationCenter.default.publisher(for: .dailyLogSyncStateChanged)) { _ in refreshSyncState() }
                .sheet(isPresented: $showingMealDraft) {
                    FoodLoggingDraftView(model: viewModel)
                }
                .sheet(item: $transferReview, onDismiss: { viewModel.fetchData() }) { review in
                    DiaryTransferReviewView(session: review.session)
                }
                .alert("Food transfer", isPresented: Binding(get: { transferReviewError != nil }, set: { if !$0 { transferReviewError = nil } })) {
                    Button("OK", role: .cancel) { transferReviewError = nil }
                } message: {
                    Text(transferReviewError ?? "Review the previous day before copying.")
                }
                .onChange(of: dailyLogService.activelyViewedDate) { _, _ in
                    viewModel.fetchData()
                }
                .onChange(of: viewModel.selectedMeal) { _, meal in
                    if viewModel.isBuildingMeal, let draft = viewModel.mealDraft, draft.entries.isEmpty, draft.mealName != meal {
                        viewModel.updateMealDraft { $0.mealName = meal }
                    }
                    showAllRepeatFoods = false
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
                            date: capture?.date ?? dailyLogService.activelyViewedDate,
                            source: pendingManualBarcode == nil ? "manual_add" : "manual_barcode_create",
                            targetMealName: capture?.meal ?? viewModel.selectedMeal,
                            onLogUpdated: {
                                showingAddFoodManually = false
                                pendingManualBarcode = nil
                                if capture?.draftID == nil { onFoodItemLogged?() }
                            }, trainingFuelTarget: trainingFuelTarget, onSelectForMeal: manualSelectionHandler
                        )
                    }
                }
                .sheet(isPresented: $showingQuickAddMacros) {
                    QuickAddMacrosView(
                        selectedMealType: viewModel.selectedMeal,
                        targetDate: dailyLogService.activelyViewedDate,
                        trainingFuelTarget: trainingFuelTarget
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView(
                        onClose: { showingBarcodeScanner = false },
                        onBarcodeDetected: lookUpScannedFood,
                        onBarcodesDetected: capture?.draftID == nil ? { batch in
                            showingBarcodeScanner = false
                            rapidBarcodeBatch = batch
                        } : nil,
                        loggingDate: capture?.date ?? loggingDestinationDate,
                        mealName: capture?.meal ?? viewModel.selectedMeal,
                        trainingFuelTarget: trainingFuelTarget
                    )
                }
                .imageSourceDialog(isPresented: $showingImagePicker) { image in
                    let requestID = UUID()
                    guard let destination = capture else { return }
                    let ownerID = destination.owner
                    self.imageAnalysisID = requestID
                    self.imageProcessingKind = .mealPhoto
                    self.isProcessingImage = true
                    DIContainer.shared.analyticsManager.aiFeatureUsed(.mealPhoto)
                    imageModel.analyzeNutritionFromImage(image: image) { result in
                        guard self.imageAnalysisID == requestID,
                              ownerID == DIContainer.shared.authService.currentUserID else { return }
                        self.imageAnalysisID = nil
                        self.isProcessingImage = false
                        switch result {
                        case .success(let analysis):
                            self.estimatedFoodItemsWrapper = IdentifiableFoodItems(
                                items: analysis.items,
                                photoReview: analysis.reviewContext,
                                loggingDate: destination.date, mealName: destination.meal, source: destination.photoSource,
                                dayContext: destination.day
                            )
                        case .failure(let error):
                            self.scanError = (true, "Could not analyze the image. Error: \(error.localizedDescription)")
                        }
                    }
                }
                .imageSourceDialog(isPresented: $showingMenuImagePicker) { image in
                        let requestID = UUID()
                        let loggingDate = capture?.date ?? dailyLogService.activelyViewedDate
                        let loggingMeal = capture?.meal ?? viewModel.selectedMeal
                        let ownerID = DIContainer.shared.authService.currentUserID
                        self.imageAnalysisID = requestID
                        self.imageProcessingKind = .menuPhoto
                        self.isProcessingImage = true
                        DIContainer.shared.analyticsManager.aiFeatureUsed(.menuPhoto)
                        imageModel.estimateMenuFromImage(image: image) { result in
                            guard self.imageAnalysisID == requestID,
                                  ownerID == DIContainer.shared.authService.currentUserID else { return }
                            self.imageAnalysisID = nil
                            self.isProcessingImage = false
                            switch result {
                            case .success(let foodItems):
                                self.estimatedMenuWrapper = IdentifiableFoodItems(items: foodItems, loggingDate: loggingDate, mealName: loggingMeal)
                            case .failure(let error):
                                self.scanError = (true, "Could not analyze the menu. Error: \(error.localizedDescription)")
                            }
                        }
                }
                .sheet(isPresented: $showingAITextLog) {
                    AITextLogView(date: dailyLogService.activelyViewedDate, mealName: viewModel.selectedMeal, trainingFuelTarget: trainingFuelTarget)
                }
                .sheet(item: $valueRadarDestination) { destination in
                    RestaurantValueRadarView(date: destination.date, mealName: destination.mealName)
                }
                .sheet(item: $selectedFoodItem, onDismiss: {
                    selectedFoodContext = nil
                    portionHeight = Self.compactPortionHeight
                }) { foodItem in
                    let expanded = dynamicTypeSize.isAccessibilitySize || foodItem.loggingPortionNotice(source: selectedFoodSource) != nil
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: selectedFoodContext?.date ?? dailyLogService.activelyViewedDate,
                        source: selectedFoodSource,
                        targetMealName: selectedFoodContext?.mealName ?? viewModel.selectedMeal,
                        isPresentedModally: true,
                        presentationState: foodDetailPresentationState,
                        onLogUpdated: {
                            selectedFoodItem = nil
                            onFoodItemLogged?()
                        },
                        onUpdateAccepted: mealFoodReviewHandler,
                        reviewActionTitle: mealFoodReviewActionTitle,
                        reviewNavigationTitle: selectedFoodContext?.isForMealDraft == true ? "Review portion" : nil,
                        dayContext: selectedFoodContext?.dayContext,
                        trainingFuelTarget: trainingFuelTarget, onFoodAccepted: viewModel.acceptedPortion,
                        onExpandNutrition: { portionHeight = .large }
                    )
                    .id(foodItem.id)
                    .presentationDetents(expanded ? [.large] : [Self.compactPortionHeight, .large],
                                         selection: expanded ? .constant(.large) : $portionHeight)
                    .presentationDragIndicator(.visible)
                }
                .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                     AISummaryView(estimatedItems: wrapper.items, photoReview: wrapper.photoReview,
                                   mealName: wrapper.mealName ?? viewModel.selectedMeal,
                                   date: wrapper.loggingDate ?? dailyLogService.activelyViewedDate,
                                   source: wrapper.source ?? "ai_image", isAIEstimate: wrapper.isAIEstimate ?? true,
                                   reviewTitle: wrapper.reviewTitle ?? "Review meal", dayContext: wrapper.dayContext,
                                   trainingFuelTarget: trainingFuelTarget, onSelectFoods: photoSelectionHandler(for: wrapper))
                }
                .sheet(item: $rapidBarcodeBatch) { batch in
                    RapidBarcodeReviewView(date: batch.date, mealName: batch.mealName, trainingFuelTarget: trainingFuelTarget)
                }
                .sheet(item: $estimatedMenuWrapper) { wrapper in
                     AIMenuSelectionView(estimatedItems: .constant(wrapper.items),
                                         date: wrapper.loggingDate ?? dailyLogService.activelyViewedDate,
                                         mealName: wrapper.mealName ?? viewModel.selectedMeal, trainingFuelTarget: trainingFuelTarget)
                }
                .sheet(isPresented: $showingChainBuilder, onDismiss: {
                    guard let review = chainComponentsReview else { return }
                    chainComponentsReview = nil
                    guard review.ownerID == DIContainer.shared.authService.currentUserID else { return }
                    estimatedFoodItemsWrapper = IdentifiableFoodItems(items: review.items, loggingDate: review.day.originalDate, mealName: review.mealName,
                        source: "chain_builder_components", isAIEstimate: false, reviewTitle: "Review restaurant order", dayContext: review.day)
                }) {
                    let ownerID = DIContainer.shared.authService.currentUserID
                    let loggingDate = dailyLogService.activelyViewedDate
                    let loggingDay = ownerID.flatMap { dailyLogService.diaryDayContext(for: $0, date: loggingDate) }
                    ChainMealBuilderView(
                        initialMeal: viewModel.selectedMeal,
                        trainingFuelTarget: trainingFuelTarget,
                        onLogComponents: { items, mealName in
                            guard let ownerID, let loggingDay, ownerID == DIContainer.shared.authService.currentUserID else { return }
                            chainComponentsReview = .init(ownerID: ownerID, items: items, day: loggingDay, mealName: mealName)
                            showingChainBuilder = false
                        }
                    ) { mealItem, mealName in
                        viewModel.selectedMeal = mealName
                        handleSelection(food: mealItem, source: "chain_builder")
                    }
                }
                .sheet(item: $otherLog) { destination in
                    switch destination {
                    case .activity:
                        AddExerciseView(initialDate: dailyLogService.activelyViewedDate) { owner, activity, completion in
                            dailyLogService.exerciseLogStore.addExerciseToLog(for: owner, exercise: activity, completion: completion)
                        }
                    case .recipes: RecipeListView()
                    case .running: NavigationStack { RunHistoryView() }
                    case .buffet: AYCEFlowView()
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

                if isProcessingImage {
                    ImageProcessingView(kind: imageProcessingKind) {
                        imageAnalysisID = nil
                        isProcessingImage = false
                    }
                } else if isSearchingAfterScan {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView("Searching barcode")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                }
            }
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
            placeholder: onFoodItemSelected == nil || searchContext == "meal_planner" ? "Food or brand" : "Search ingredients",
            onClear: {
                viewModel.searchText = ""
                viewModel.handleSearchQueryChange("")
            },
            onSubmit: {
                viewModel.submitSearch()
                hideKeyboard()
            },
            onMic: { toggleVoiceRecording() },
            isRecording: voiceLoggingService.state == .recording,
            onFocusChange: { isSearchFocused = $0 }
        )
        .onChange(of: voiceLoggingService.state) { _, newState in
            handleVoiceStateChange(newState)
        }
    }

    private var loggingDestinationDate: Date {
        viewModel.isBuildingMeal ? viewModel.mealDraft?.date ?? dailyLogService.activelyViewedDate : dailyLogService.activelyViewedDate
    }

    private var showsCaptureShortcuts: Bool {
        viewModel.searchText.isEmpty && !dynamicTypeSize.isAccessibilitySize
    }

    private var searchResults: some View {
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
        .accessibilityIdentifier("food_search_results_scroll")
    }

    private var loggingFooter: some View {
        VStack(spacing: 0) {
            if onFoodItemSelected == nil, let draft = viewModel.mealDraft, !draft.entries.isEmpty {
                mealTray(draft)
            }
            if let message = viewModel.lastLogMessage {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if diarySyncState != .synced && viewModel.lastLogSucceeded {
                        Button {
                            if let userID = DIContainer.shared.authService.currentUserID {
                                DIContainer.shared.nutritionRepository.retryPendingDailyLogs(userID: userID)
                            }
                        } label: {
                            Label(diarySyncState == .failed ? "Saved on device · Retry sync" : "Saved on device · Waiting to sync",
                                  systemImage: "icloud.and.arrow.up")
                                .appFont(size: 11, weight: .medium)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }
                    }
                    // Keep Undo at the bottom so a completed sync cannot move its tap target.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.row) { loggingFeedback(message) }
                        VStack(alignment: .leading, spacing: AppSpacing.compact) { loggingFeedback(message) }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.surface)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var pinnedSearchHeader: some View {
        HStack(spacing: AppSpacing.compact) {
            searchHeaderContent
            if onFoodItemSelected == nil && showsCaptureShortcuts {
                FoodCaptureButton(title: "Scan", symbol: "barcode.viewfinder", identifier: "food_search_action_barcode", action: openBarcode)
                FoodCaptureButton(title: "Photo", symbol: "camera", identifier: "food_search_action_camera", action: openMealPhoto)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.canvas)
    }

    private func mealTray(_ draft: FoodLoggingDraft) -> some View {
        let count = draft.entries.count
        let title = "\(count) \(count == 1 ? "food" : "foods")"
        let canLog = viewModel.isBuildingMeal && !draft.isSubmitted && draft.isReadyToSubmit &&
            draft.entries.allSatisfy { $0.food.loggingPortionNotice() == nil } && viewModel.loggingFoodIDs.isEmpty
        return HStack(spacing: AppSpacing.row) {
            Button {
                viewModel.isBuildingMeal = true
                showingMealDraft = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    if dynamicTypeSize.isAccessibilitySize && canLog {
                        Text("Review")
                            .appTextRole(.control)
                    } else {
                        Text(draft.isSubmitted ? "Finish logging meal" : "Review \(title)")
                            .appTextRole(.control)
                        Text("\(draft.calories.formatted(.number.precision(.fractionLength(0)))) cal · \(draft.mealName) · \(draft.date.formatted(date: .abbreviated, time: .omitted))")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mealDraftReviewLabel(draft))
            .accessibilityIdentifier("food_search_review_meal")
            if canLog {
                Button("Log " + title) { viewModel.logMealDraft { _ in } }
                    .buttonStyle(AppActionButtonStyle(.primary, fillsWidth: false))
                    .accessibilityIdentifier("food_search_log_selected")
            }
        }
        .disabled(viewModel.isSavingDraft)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.surface)
    }

    private func selectedFoodSummary(_ draft: FoodLoggingDraft) -> String {
        let names = draft.entries.prefix(2).map { $0.food.name }.joined(separator: ", ")
        let remaining = draft.entries.count - 2
        return remaining > 0 ? "\(names) + \(remaining) more" : names
    }

    private func mealDraftReviewLabel(_ draft: FoodLoggingDraft) -> String {
        let action = draft.isSubmitted ? "Finish logging" : "Review"
        return "\(action) \(draft.entries.count) \(draft.entries.count == 1 ? "food" : "foods"), \(draft.mealName), \(draft.date.formatted(date: .complete, time: .omitted)), \(Int(draft.calories.rounded()).formatted()) calories, \(selectedFoodSummary(draft))"
    }

    private var mealFoodReviewHandler: ((FoodItem) -> Bool)? {
        guard let context = selectedFoodContext, context.isForMealDraft else { return nil }
        return { reviewed in
            viewModel.acceptReviewedMealFood(reviewed, sourceID: context.sourceID,
                userID: context.ownerID, draftID: context.draftID,
                date: context.date, mealName: context.mealName, dayContext: context.dayContext)
        }
    }

    private var mealFoodReviewActionTitle: String? {
        guard let context = selectedFoodContext, context.isForMealDraft else { return nil }
        return context.replacesEntry ? "Update portion" : "Select food"
    }

    @ViewBuilder
    private var mealTargetContent: some View {
        if onFoodItemSelected == nil {
            FoodSearchCompactMealPicker(selectedMeal: $viewModel.selectedMeal,
                foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"], date: loggingDestinationDate)
        }
    }

    private func openBarcode() {
        guard let destination = captureDestination() else { return }
        capture = destination
        if destination.draftID == nil, let pending = RapidBarcodeBatchSession.pending(userID: destination.owner) {
            rapidBarcodeBatch = pending
        } else { showingBarcodeScanner = true }
    }

    private func lookUpScannedFood(_ barcode: String) {
        guard let destination = capture else { return }
        showingBarcodeScanner = false
        isSearchingAfterScan = true
        DIContainer.shared.analyticsManager.log(.barcodeScanned, [:])
        Task { @MainActor in
            let result = await barcodeLookupService.lookup(barcode)
            isSearchingAfterScan = false
            guard destination.owner == DIContainer.shared.authService.currentUserID else { return }
            guard let result else {
                presentBarcodeRecovery(message: "No food or supplement label matched this barcode.", barcode: barcode)
                return
            }
            let food = result.item
            let entry = destination.draftID.flatMap { id in
                viewModel.mealDraft?.id == id ? viewModel.mealDraft?.entries.first { $0.sourceID == food.id } : nil
            }
            selectedFoodContext = FoodSelectionContext(ownerID: destination.owner, date: destination.date,
                mealName: destination.meal, sourceID: food.id, draftID: destination.draftID,
                isForMealDraft: destination.draftID != nil, replacesEntry: entry != nil, dayContext: destination.day)
            selectedFoodSource = entry == nil ? result.source : "image_result_edit"
            selectedFoodItem = entry?.preparedFood ?? viewModel.portionReviewFood(food, source: result.source)
            showBarcodeResultFeedback(result)
        }
    }

    private func photoSelectionHandler(for review: IdentifiableFoodItems) -> (([FoodItem]) -> Bool)? {
        guard review.source?.hasPrefix("ai_image_selection_") == true else { return nil }
        guard let captured = capture, let draftID = captured.draftID, review.source == captured.photoSource else { return { _ in false } }
        return { foods in viewModel.selectReviewedPhotoFoods(foods, owner: captured.owner, draftID: draftID) }
    }

    private func openManualFood() {
        guard let destination = captureDestination() else { return }
        capture = destination
        pendingManualBarcode = nil
        showingAddFoodManually = true
    }

    private var manualSelectionHandler: ((FoodItem) -> Bool)? {
        guard let captured = capture, let id = captured.draftID else { return nil }
        let code = pendingManualBarcode
        return { food in
            viewModel.acceptReviewedMealFood(food, sourceID: code.map { "barcode_" + $0 } ?? food.id,
                userID: captured.owner, draftID: id, date: captured.date, mealName: captured.meal, dayContext: captured.day)
        }
    }

    private var moreActions: some View {
        Menu {
            if !showsCaptureShortcuts {
                Button("Scan barcode", systemImage: "barcode.viewfinder", action: openBarcode)
                Button("Photograph food", systemImage: "camera", action: openMealPhoto)
            }
            Button("My foods", systemImage: "folder") { showingMyFoodsLibrary = true }
            Button("Describe food", systemImage: "text.bubble") { showingAITextLog = true }
            Button("Quick macros", systemImage: "bolt") { showingQuickAddMacros = true }
            Button("Enter manually", systemImage: "square.and.pencil", action: openManualFood)
            Menu("Eating out", systemImage: "fork.knife") {
                Button("Restaurant builder", action: openChainBuilder)
                Button("Scan a menu", action: openMenuPhoto)
                Button("Value radar") {
                    valueRadarDestination = ValueRadarDestination(date: loggingDestinationDate, mealName: viewModel.selectedMeal)
                }
                Button("Beat the buffet") { otherLog = .buffet }
            }
            Section("Other logs") {
                Button("Log recipe or meal", systemImage: "list.clipboard") { otherLog = .recipes }
                Button("Log exercise", systemImage: "figure.walk") { otherLog = .activity }
                Button("Running", systemImage: "figure.run") { otherLog = .running }
            }
            Menu("Food preferences", systemImage: "slider.horizontal.3") {
                Button("Reset remembered servings", action: viewModel.resetUsualServings)
            }
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
        .accessibilityLabel("More logging options")
        .accessibilityIdentifier("food_search_more_actions")
    }

    private var hasFastRepeatOptions: Bool {
        onFoodItemSelected == nil &&
        !viewModel.isSearching &&
        (viewModel.hasYesterdayFoods ||
         !viewModel.recommendedFoods.isEmpty ||
         !viewModel.savedFoods.isEmpty ||
         !viewModel.recentFoods.isEmpty)
    }

    private var repeatFoods: [FoodItem] {
        switch repeatScope {
        case "Saved": return viewModel.savedFoods
        case "Recent": return viewModel.recentFoods
        default: return viewModel.usualFoods
        }
    }

    @ViewBuilder
    private var fastRepeatContent: some View {
        if hasFastRepeatOptions {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack {
                    Menu {
                        repeatScopePicker
                    } label: {
                        HStack(spacing: 6) {
                            Text(repeatScope == "Usual" ? "Usual for \(viewModel.selectedMeal.lowercased())" : "\(repeatScope) foods")
                                .appTextRole(.sectionTitle).accessibilityIdentifier("food_search_repeat_section")
                            Image(systemName: "chevron.down").appTextRole(.caption)
                        }
                        .foregroundStyle(AppPalette.text)
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Food list: \(repeatScope)")
                    .accessibilityIdentifier("food_search_repeat_scope")
                    Spacer(minLength: 0)
                }
                .onChange(of: repeatScope) { _, _ in showAllRepeatFoods = false }
                FoodRepeatQuickList(
                    foods: showAllRepeatFoods ? repeatFoods : Array(repeatFoods.prefix(5)),
                    loggingFoodIDs: viewModel.loggingFoodIDs,
                    loggedFoodIDs: viewModel.selectedFoodIDs,
                    isBuildingMeal: viewModel.isBuildingMeal,
                    onSelect: { handleSelection(food: $0, source: viewModel.sourceForTrustedSearchResult($0)) },
                    onLog: { fuelAwareQuickLog($0, source: "repeat_food_quick_log") }
                )
                if repeatFoods.isEmpty {
                    Text(repeatScope == "Saved" ? "Star a food to keep it here." : "Foods you log will appear here.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }
                if repeatFoods.count > 5 {
                    Button(showAllRepeatFoods ? "Show fewer foods" : "Show all \(repeatFoods.count) foods") {
                        showAllRepeatFoods.toggle()
                    }
                    .appTextRole(.secondary)
                    .frame(minHeight: 44)
                }
                if viewModel.hasYesterdayFoods {
                    previousMealContent
                }
            }
        }
    }

    private var repeatScopePicker: some View {
        Picker("Repeat foods", selection: $repeatScope) {
            ForEach(["Usual", "Saved", "Recent"], id: \.self) { Text($0).tag($0) }
        }
    }

    private var previousMealContent: some View {
        HStack(spacing: AppSpacing.row) {
            if !viewModel.yesterdaysMealItems.isEmpty {
                Button {
                    openPreviousDayTransfer(allMeals: false)
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        Image(systemName: "arrow.counterclockwise")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(viewModel.previousDayLabel) · \(viewModel.selectedMeal)").appTextRole(.control)
                            let items = viewModel.yesterdaysMealItems
                            let names = items.prefix(2).map(\.name).joined(separator: ", ")
                            let extra = items.count > 2 ? " +\(items.count - 2)" : ""
                            Text("\(names)\(extra) · \(items.reduce(0) { $0 + $1.calories }.formatted(.number.precision(.fractionLength(0)))) cal")
                                .appTextRole(.secondary).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("food_search_repeat_meal")
            } else {
                Text(viewModel.previousDayLabel).appTextRole(.secondary)
                Spacer()
            }
            Menu {
                Button("Copy all meals…") { openPreviousDayTransfer(allMeals: true) }
                    .disabled(viewModel.isFetchingYesterday)
                    .accessibilityIdentifier("food_search_copy_all_meals")
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("More repeat options").accessibilityIdentifier("food_search_more_repeat_options")
        }
        .appSurface(.quiet, padding: AppSpacing.row)
    }

    private func openPreviousDayTransfer(allMeals: Bool) {
        do { transferReview = TransferReview(session: try viewModel.makePreviousDayTransfer(allMeals: allMeals)) } catch {
            transferReviewError = error.localizedDescription
        }
    }

    private var loggingModeButton: some View {
        Button {
            viewModel.isBuildingMeal.toggle()
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: viewModel.isBuildingMeal ? "plus" : "square.stack")
                } else {
                    Text(viewModel.isBuildingMeal ? "Quick add" : "Select")
                }
            }
            .appFont(size: 13, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(viewModel.isBuildingMeal ? "Quick add" : "Select foods")
        .accessibilityHint(viewModel.isBuildingMeal ? "Log individual foods. Your meal draft stays saved." : "Select several foods and review them together before saving.")
        .accessibilityIdentifier("food_search_mode")
    }

    @ViewBuilder
    private var mainActionContent: some View {
        if voiceLoggingService.state == .recording || voiceLoggingService.state == .transcribing {
            voiceRecordingBanner
        }
        if viewModel.isBuildingMeal, let message = viewModel.draftMessage, message != "Draft saved on this device." {
            Text(message)
                .appFont(size: 13, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        fastRepeatContent
        if !viewModel.isSearching && !viewModel.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                AppSectionHeader(title: "Recent searches") {
                    Button("Clear", action: viewModel.clearRecentSearches).frame(minHeight: 44)
                }
                ForEach(Array(viewModel.recentSearches.prefix(3)), id: \.self) { query in
                    Button { viewModel.selectRecentSearch(query) } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
                            .appTextRole(.body)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier("food_search_recent_queries")
        }
    }

    @ViewBuilder
    private func loggingFeedback(_ message: String) -> some View {
        Label(isSearchFocused && viewModel.mealDraft?.entries.isEmpty == false && viewModel.lastLogSucceeded ? "Food added" : message,
              systemImage: viewModel.lastLogSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
            .appFont(size: 13, weight: .medium).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(message)
        if viewModel.canUndoQuickLog && dailyLogService.canUndoDiaryChange {
            Button(viewModel.lastLogSucceeded ? "Undo" : "Retry Undo", action: viewModel.undoQuickLog)
                .appFont(size: 17, weight: .semibold)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(viewModel.lastLogSucceeded ? "Undo last food change" : "Retry undoing the last food change")
                .accessibilityIdentifier("food_search_undo")
        } else if viewModel.canRetryLog {
            Button("Retry", action: viewModel.retryQuickLog)
                .appFont(size: 17, weight: .semibold)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("food_search_retry_save")
        }
    }

    private func refreshSyncState() {
        guard let userID = DIContainer.shared.authService.currentUserID else { diarySyncState = .synced; return }
        diarySyncState = DIContainer.shared.nutritionRepository.dailyLogSyncState(userID: userID)
    }

    @ViewBuilder
    private var searchingStateContent: some View {
        let trustedResults = viewModel.trustedSearchResults
        let presentation = viewModel.searchPresentation
        let hasCatalogMatches = !presentation.brandedMatches.isEmpty || !presentation.otherRemoteMatches.isEmpty

        personalSearchSection(presentation.exactPersonalMatches, title: "Your exact matches")
        providerSearchSection(presentation.brandedMatches, title: "Branded matches",
            subtitle: "")
        personalSearchSection(presentation.otherPersonalMatches,
            title: presentation.brandedMatches.isEmpty ? "Best matches" : "Saved and recent")

        if viewModel.isLoading && (!trustedResults.isEmpty || hasCatalogMatches || !viewModel.supplementResults.isEmpty) {
            HStack(spacing: AppSpacing.row) {
                ProgressView().controlSize(.small)
                Text("Searching more sources…").appTextRole(.secondary).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("food_search_loading_more")
        } else if !viewModel.isLoading, let message = viewModel.searchCoverageMessage {
            HStack(spacing: AppSpacing.row) {
                Image(systemName: "wifi.exclamationmark")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.caution)
                    .accessibilityHidden(true)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: viewModel.retrySearchSources) {
                    Text("Retry").appTextRole(.control)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retry unavailable food sources")
                .accessibilityIdentifier("food_search_retry_sources")
            }
            .appSurface(.quiet)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("food_search_partial_coverage")
        }

        if viewModel.isLoading && !hasCatalogMatches && viewModel.supplementResults.isEmpty {
            if trustedResults.isEmpty { FoodSearchLoadingState(query: viewModel.searchText) }
        } else if let searchErrorMessage = viewModel.searchErrorMessage,
                  !hasCatalogMatches,
                  viewModel.supplementResults.isEmpty {
            let family = FoodSearchRanking.catalogQuery(viewModel.searchText)
            FoodSearchEmptyState(
                icon: "wifi.exclamationmark",
                title: String(localized: "Search could not load"),
                message: searchErrorMessage,
                primaryActionTitle: String(localized: "Try again"),
                primaryAction: { viewModel.submitSearch() },
                secondaryActionTitle: family != viewModel.searchText ? "Search other sizes" : onFoodItemSelected == nil ? String(localized: "Create food") : nil,
                secondaryAction: family != viewModel.searchText ? { searchFamily(family) } : onFoodItemSelected == nil ? openManualFood : nil
            )
        } else if !hasCatalogMatches &&
                    viewModel.supplementResults.isEmpty &&
                    trustedResults.isEmpty {
            let family = FoodSearchRanking.catalogQuery(viewModel.searchText)
            if family != viewModel.searchText {
                FoodSearchEmptyState(icon: "magnifyingglass", title: "No match for this size",
                    message: "See other labeled sizes for " + family + ".",
                    primaryActionTitle: "Search other sizes", primaryAction: { searchFamily(family) })
            } else {
                FoodSearchEmptyState(
                    icon: "magnifyingglass",
                    title: viewModel.searchText.trimmed.count < 2 ? "Keep typing" : String(localized: "No foods found"),
                    message: viewModel.searchText.trimmed.count < 2 ? "Enter at least two characters to search." : String(localized: "Try a simpler search like \"chicken breast\", or create the food yourself."),
                    primaryActionTitle: onFoodItemSelected == nil ? String(localized: "Create food") : nil,
                    primaryAction: onFoodItemSelected == nil ? openManualFood : nil
                )
            }
        } else if hasCatalogMatches {
            providerSearchSection(presentation.otherRemoteMatches,
                title: presentation.brandedMatches.isEmpty ? "Search results" : "More results",
                subtitle: "")
        }

        if !viewModel.supplementResults.isEmpty {
            FoodPickerSection(
                title: "Supplements",
                subtitle: "Current manufacturer label records from NIH DSLD. Amounts come from the product label, not laboratory testing.",
                foods: viewModel.supplementResults,
                quickLoggedFoodIDs: viewModel.selectedFoodIDs,
                loggingFoodIDs: viewModel.loggingFoodIDs,
                isBuildingMeal: viewModel.isBuildingMeal,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "nih_dsld") },
                onQuickLog: onFoodItemSelected == nil ? {
                    fuelAwareQuickLog($0, source: "nih_dsld_quick_log")
                } : nil,
                onDelete: nil,
                sourceForFood: { _ in "nih_dsld" }
            )
        }
    }

    private func searchFamily(_ query: String) {
        viewModel.searchText = query
        viewModel.submitSearch()
    }

    @ViewBuilder
    private func personalSearchSection(_ foods: [FoodItem], title: String) -> some View {
        if !foods.isEmpty {
            FoodPickerSection(title: title, subtitle: "", foods: foods,
                quickLoggedFoodIDs: viewModel.selectedFoodIDs, loggingFoodIDs: viewModel.loggingFoodIDs,
                isBuildingMeal: viewModel.isBuildingMeal, emptyTitle: "", emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: viewModel.sourceForTrustedSearchResult($0)) },
                onQuickLog: onFoodItemSelected == nil ? { fuelAwareQuickLog($0, source: "best_match_quick_log") } : nil,
                onDelete: nil, sourceForFood: { viewModel.sourceForTrustedSearchResult($0) })
        }
    }

    @ViewBuilder
    private func providerSearchSection(_ foods: [FoodItem], title: String, subtitle: String) -> some View {
        if !foods.isEmpty {
            FoodPickerSection(title: title, subtitle: subtitle, foods: foods,
                quickLoggedFoodIDs: viewModel.selectedFoodIDs, loggingFoodIDs: viewModel.loggingFoodIDs,
                isBuildingMeal: viewModel.isBuildingMeal, emptyTitle: "", emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "search_result") },
                onQuickLog: onFoodItemSelected == nil ? { fuelAwareQuickLog($0, source: "search_result_quick_log") } : nil,
                onDelete: nil, sourceForFood: { _ in "search_result" })
        }
    }

    @ViewBuilder
    private var savedAndRecentFoodsContent: some View {
        FoodHorizontalScroller(
            title: "My foods",
            subtitle: "Saved foods with your usual serving.",
            foods: viewModel.savedFoods,
            quickLoggedFoodIDs: viewModel.selectedFoodIDs,
            emptyTitle: "No saved foods yet",
            emptyMessage: "Star foods from detail screens and they will appear here.",
            onSelect: { handleSelection(food: $0, source: "custom_food") },
            onQuickLog: onFoodItemSelected == nil ? { fuelAwareQuickLog($0, source: "saved_food_quick_log") } : nil,
            source: "custom_food",
            headerActionTitle: onFoodItemSelected == nil ? "Manage" : nil,
            headerAction: onFoodItemSelected == nil ? { showingMyFoodsLibrary = true } : nil
        )

        FoodHorizontalScroller(
            title: "Recent foods",
            subtitle: "Your fastest path for repeat meals.",
            foods: viewModel.recentFoods,
            quickLoggedFoodIDs: viewModel.selectedFoodIDs,
            emptyTitle: "No recent foods",
            emptyMessage: "Foods you log will appear here for one-tap reuse.",
            onSelect: { handleSelection(food: $0, source: "recent_tap") },
            onQuickLog: onFoodItemSelected == nil ? { fuelAwareQuickLog($0, source: "recent_food_quick_log") } : nil,
            source: "recent_tap"
        )
    }

    @ViewBuilder
    private var searchOrSavedContent: some View {
        if viewModel.isSearching {
            searchingStateContent
        } else if hasFastRepeatOptions {
            EmptyView()
        } else if onFoodItemSelected == nil {
            FoodSearchEmptyState(icon: "fork.knife", title: "Find your first food",
                                 message: "Search above or scan a barcode. Your usual foods will appear here as you log.")
        } else {
            savedAndRecentFoodsContent
        }
    }

    private func fuelAwareQuickLog(_ food: FoodItem, source: String) {
        if trainingFuelTarget != nil { handleSelection(food: food, source: source) } else { viewModel.quickLog(food: food, source: source) }
    }

    private func handleSelection(food: FoodItem, source: String) {
        if onFoodItemSelected == nil, viewModel.isBuildingMeal {
            if viewModel.mealDraft?.isSubmitted == true {
                showingMealDraft = true
                return
            }
            guard !viewModel.loggingFoodIDs.contains(food.id) else { return }
            let existingEntry = viewModel.mealDraft?.entries.first { $0.sourceID == food.id }
            selectedFoodContext = FoodSelectionContext(ownerID: DIContainer.shared.authService.currentUserID,
                date: viewModel.mealDraft?.date ?? dailyLogService.activelyViewedDate,
                mealName: viewModel.mealDraft?.mealName ?? viewModel.selectedMeal,
                sourceID: food.id, draftID: viewModel.mealDraft?.id, isForMealDraft: true,
                replacesEntry: existingEntry != nil,
                dayContext: viewModel.mealDraft != nil ? viewModel.mealDraft?.dayContext : capturedSelectionDay())
            selectedFoodSource = existingEntry == nil ? source : "image_result_edit"
            selectedFoodItem = existingEntry?.preparedFood ?? viewModel.portionReviewFood(food, source: source)
            return
        }
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
            selectedFoodContext = FoodSelectionContext(ownerID: DIContainer.shared.authService.currentUserID,
                date: dailyLogService.activelyViewedDate, mealName: viewModel.selectedMeal,
                sourceID: food.id, draftID: nil, isForMealDraft: false, dayContext: capturedSelectionDay())
            selectedFoodSource = source
            self.selectedFoodItem = viewModel.portionReviewFood(food, source: source)
        }
    }

    private func capturedSelectionDay() -> DiaryDayContext? {
        guard let owner = DIContainer.shared.authService.currentUserID else { return nil }
        return dailyLogService.diaryDayContext(for: owner, date: dailyLogService.activelyViewedDate)
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
            if let capture { presentMealPhoto(at: capture) }
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
                .foregroundColor(AppPalette.onSignal)
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
                        .foregroundColor(AppPalette.onSignal)
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
                        .foregroundColor(.brandForeground)
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
                        subtitle: "Try the brand and product name. Food and supplement package UPCs can change.",
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
