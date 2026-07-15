import MyFitPlateCore

import SwiftUI

struct IdentifiableFoodItems: Identifiable {
    let id = UUID()
    let items: [FoodItem]
    let photoReview: MealPhotoReviewContext?

    init(items: [FoodItem], photoReview: MealPhotoReviewContext? = nil) {
        self.items = items
        self.photoReview = photoReview
    }
}

private struct QuickLogOption: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var id: String { title }
}

struct MainTabView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @EnvironmentObject var insightsService: InsightsService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var showSettings = false
    @State private var showingAddOptions = false
    @State private var showingAllQuickLogActions = false
    @State private var quickLogDetent: PresentationDetent = .medium

    @State private var showingFoodSearch = false
    @State private var showingBarcodeScanner = false
    @State private var showingAddExerciseView = false
    @State private var showingRecipeListView = false
    @State private var showingGroceryList = false
    @State private var showingAITextLog = false
    @State private var showingAddFoodManually = false
    
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems?

    @State private var showingAYCESession = false
    @State private var showingRunHistory = false
    @State private var showingWeeklyReport = false
    
    @State private var scannedFoodItem: FoodItem?
    @State private var scannedFoodSource: String = "barcode_result"
    @State private var pendingManualBarcode: String?
    @State private var showingBarcodeRecovery = false
    @State private var barcodeRecoveryMessage = ""
    @State private var barcodeRecoveryResolved = false
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")
    
    @State private var showingSpotlightTour = false
    @State private var showingAIDataConsent = false
    @State private var livingDayTransition: LivingDayTransition?
    @State private var isLivingDayHomeEnabled: Bool
    @State private var didRefreshLivingDayFlag = false
    @StateObject private var weeklyRecapLoader = WeeklyRecapLoader()

    private let forcesLivingDayHome: Bool
    private let forcesLegacyHome: Bool

    private let imageModel = MLImageModel()
    private let barcodeLookupService = BarcodeFoodLookupService()
    
    private var suppressesSpotlightTours: Bool {
        ScreenshotDemoMode.isEnabled || ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private var isDirectScreenshotSurface: Bool {
        #if DEBUG
        ScreenshotDemoMode.isEnabled && [
            "weight-detail", "wellness-detail", "fasting-detail", "cycle-detail",
            "profile", "challenges", "pantry", "pantry-recipes", "receipt-review",
            "ayce-start", "ayce-live", "ayce-review", "ayce-summary", "value-radar",
            "celebration", "add-meal-plan", "meal-plan-survey", "meal-plan-survey-cooking", "meal-prep",
            "meal-prep-steps", "meal-suggestion", "plate-calculator", "plate-math",
            "nutrition-trends", "maia-insights", "maia-action-cards", "muscle-recovery", "shoe-gear-add"
        ].contains(ScreenshotDemoData.requestedScreen)
        #else
        false
        #endif
    }

    private func contentBottomInset(for width: CGFloat) -> CGFloat {
        if isDirectScreenshotSurface {
            return 0
        }
        if dynamicTypeSize.isAccessibilitySize {
            return 148
        }
        return width < 440 ? 108 : 96
    }

    init() {
        #if DEBUG
        // Development builds should exercise the shipping 2.3 Home by default. Use
        // `-legacy-home` only when deliberately validating the rollback path.
        let forcesLegacyHome = ProcessInfo.processInfo.arguments.contains("-legacy-home")
        let forcesLivingDayHome = !forcesLegacyHome
        #else
        let forcesLegacyHome = false
        let forcesLivingDayHome = false
        #endif
        self.forcesLivingDayHome = forcesLivingDayHome
        self.forcesLegacyHome = forcesLegacyHome
        _isLivingDayHomeEnabled = State(
            initialValue: !forcesLegacyHome && (forcesLivingDayHome || (
                DIContainer.shared.featureFlagService?.isFeatureEnabled(.livingDayHome)
                    ?? FeatureFlag.livingDayHome.defaultValue
            ))
        )

        #if DEBUG
        let screenshotScreen = ScreenshotDemoData.requestedScreen
        _showSettings = State(initialValue: screenshotScreen.hasPrefix("settings"))
        _showingAddOptions = State(initialValue: screenshotScreen == "quick-log")
        _showingFoodSearch = State(
            initialValue: [
                "food-search", "builder", "trust", "my-foods", "add-food", "quick-add-macros"
            ].contains(screenshotScreen)
        )
        _showingRecipeListView = State(initialValue: screenshotScreen == "recipes")
        _showingGroceryList = State(initialValue: screenshotScreen == "grocery")
        _showingRunHistory = State(initialValue: screenshotScreen == "runs")
        _showingWeeklyReport = State(initialValue: screenshotScreen == "weekly-report")
        _showingAITextLog = State(
            initialValue: ["ai-text-log", "ai-text-results"].contains(screenshotScreen)
        )
        #endif
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                GeometryReader { geometry in
                    Group {
                        switch appState.selectedTab {
                        case 0:
                            homeContent
                        case 1:
                            NavigationStack { AIChatbotView(selectedTab: $appState.selectedTab) }.trackScreen(.maiaChat)
                        case 2:
                            WorkoutRoutinesView().trackScreen(.workoutsHome)
                        case 3:
                            NavigationStack { MealPlannerView() }.trackScreen(.mealPlanner)
                        case 4:
                            NavigationStack {
                                ReportsView(
                                    dailyLogService: dailyLogService,
                                    weeklyRecapLoader: weeklyRecapLoader
                                )
                            }
                            .trackScreen(.reports)
                        default:
                            NavigationStack {
                                HomeView(
                                    navigateToProfile: .constant(false),
                                    showSettings: $showSettings,
                                    livingDayTransition: livingDayTransition,
                                    isLivingDayHomeEnabled: isLivingDayHomeEnabled
                                )
                            }
                            .trackScreen(.homeDashboard)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, contentBottomInset(for: geometry.size.width))
                }

                if !isDirectScreenshotSurface {
                    CustomTabBar(
                        selectedIndex: $appState.selectedTab,
                        showingAddOptions: $showingAddOptions,
                        centerButtonAction: {
                            guard !showingAddOptions else { return }
                            HapticsService.shared.playImpact(style: .light)
                            withAnimation(AppMotion.standard) {
                                showingAddOptions = true
                            }
                        }
                    )
                    .zIndex(showingAddOptions ? 0 : 1)
                }
                
                if isSearchingAfterScan {
                    Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                    ProgressView("Searching...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                        .zIndex(3)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(showSettings: $showSettings) } }
            .sheet(isPresented: $showingAddOptions, onDismiss: resetQuickLogPresentation) {
                quickLogSheet
                    .presentationDetents([.medium, .large], selection: $quickLogDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(AppPalette.canvas)
                    .interactiveDismissDisabled(showingSpotlightTour)
            }
            .sheet(isPresented: $showingWeeklyReport) {
                WeeklyRecapView()
            }
            .sheet(isPresented: $showingAIDataConsent) {
                AIDataConsentSheet()
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: {
                    showingFoodSearch = false
                }, searchContext: "general_search")
            }
            .sheet(isPresented: $showingAddFoodManually, onDismiss: { pendingManualBarcode = nil }) {
                NavigationStack {
                    AddFoodView(
                        initialFoodItem: manualFoodSeed(),
                        dailyLog: $dailyLogService.currentDailyLog,
                        source: pendingManualBarcode == nil ? "manual_add" : "manual_barcode_create",
                        onLogUpdated: {
                            showingAddFoodManually = false
                            pendingManualBarcode = nil
                        }
                    )
                }
            }
            .imageSourceDialog(isPresented: $showingImagePicker) { image in
                self.isProcessingImage = true
                imageModel.analyzeNutritionFromImage(image: image) { result in
                    self.isProcessingImage = false
                    switch result {
                    case .success(let analysis):
                        self.estimatedFoodItemsWrapper = IdentifiableFoodItems(
                            items: analysis.items,
                            photoReview: analysis.reviewContext
                        )
                    case .failure(let error):
                        self.scanError = (true, "Could not analyze the image. Error: \(error.localizedDescription)")
                    }
                }
            }
            .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                 AISummaryView(estimatedItems: wrapper.items, photoReview: wrapper.photoReview)
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
                            self.isSearchingAfterScan = false
                            self.pendingManualBarcode = nil
                            self.scannedFoodSource = result.source
                            self.scannedFoodItem = result.item
                            showBarcodeResultFeedback(result)
                            return
                        }
                        self.isSearchingAfterScan = false
                        self.presentBarcodeRecovery(
                            message: "No food or supplement label matched this barcode.",
                            barcode: barcode
                        )
                    }
                }
            }
            .sheet(item: $scannedFoodItem) { foodItem in
                NavigationStack {
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: scannedFoodSource,
                        onLogUpdated: { self.scannedFoodItem = nil }
                    )
                }
            }
            .sheet(isPresented: $showingAITextLog) { AITextLogView() }
            .fullScreenCover(isPresented: $showingAYCESession) {
                AYCEFlowView()
                    .environmentObject(dailyLogService)
                    .environmentObject(goalSettings)
            }
            .sheet(isPresented: $showingRunHistory) {
                NavigationStack { RunHistoryView() }
            }
            .sheet(isPresented: $showingAddExerciseView) {
                AddExerciseView { newExercise in
                    if let userID = DIContainer.shared.authService.currentUserID {
                        dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: newExercise)
                    }
                }
            }
            .sheet(isPresented: $showingRecipeListView) {
                RecipeListView().environmentObject(recipeService)
            }
            .sheet(isPresented: $showingGroceryList) {
                NavigationStack { GroceryListView() }
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
            .alert("Scan Error", isPresented: $scanError.0) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanError.1)
            }
            .onChange(of: showingAddOptions) { _, newValue in
                if newValue &&
                    !suppressesSpotlightTours &&
                    !spotlightManager.isShown(id: "action-menu") {
                    withAnimation(AppMotion.visibility) {
                        showingSpotlightTour = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiDataConsentRequired)) { _ in
                showingAIDataConsent = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .foodItemLogged)) { notification in
                handleFoodLoggedTransition(notification)
            }
            .onChange(of: trainingFuelPlanStore.confirmedPlan) { previousPlan, currentPlan in
                handleTrainingFuelTransition(from: previousPlan, to: currentPlan)
            }
            
            if isProcessingImage {
                ImageProcessingView()
            }
        }
        .task { await refreshLivingDayFeatureFlagIfNeeded() }
    }

    @ViewBuilder
    private var homeContent: some View {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen == "visual-system" {
            NavigationStack { AppVisualSystemGallery() }
        } else if ScreenshotDemoMode.isEnabled,
                  isDirectScreenshotSurface {
            directScreenshotContent
        } else if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen.hasPrefix("living-day") {
            NavigationStack {
                LivingDayPrototypeGallery(
                    initialStyle: .initial(for: ScreenshotDemoData.requestedScreen)
                )
            }
        } else {
            standardHomeContent
        }
        #else
        standardHomeContent
        #endif
    }

    #if DEBUG
    @ViewBuilder
    private var directScreenshotContent: some View {
        switch ScreenshotDemoData.requestedScreen {
        case "weight-detail":
            NavigationStack { WeightTrackingView() }
        case "wellness-detail":
            WellnessScoreDetailView(
                wellnessScore: ScreenshotDemoData.wellnessDemoScore,
                mealScore: ScreenshotDemoData.wellnessDemoMealScore,
                sleepReport: ScreenshotDemoData.wellnessDemoSleepReport
            )
        case "fasting-detail":
            NavigationStack {
                ScrollView {
                    FastingTrackerCard()
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.vertical, AppSpacing.group)
                }
                .accessibilityIdentifier("fasting_tracker_screen")
                .background(AppPalette.canvas.ignoresSafeArea())
            }
        case "cycle-detail":
            NavigationStack { CycleTrackingView() }
        case "profile":
            NavigationStack { UserProfileView() }
        case "challenges":
            NavigationStack { ChallengesView() }
        case "pantry":
            PantryView()
        case "pantry-recipes":
            PantryRecipeGenerationView(
                pantryService: pantryService,
                initialRecipes: ScreenshotDemoData.pantryRecipeDrafts
            )
        case "receipt-review":
            ReceiptScannerView(initialItems: ScreenshotDemoData.receiptDemoItems)
        case "ayce-start":
            AYCEFlowView(restoresDraft: false, managesLiveActivity: false)
        case "ayce-live":
            AYCEFlowView(
                initialSession: ScreenshotDemoData.ayceLiveSession,
                restoresDraft: false,
                managesLiveActivity: false
            )
        case "ayce-review":
            AYCEPlateReviewDemoView()
        case "ayce-summary":
            AYCEFlowView(
                finishedSession: ScreenshotDemoData.ayceSummarySession,
                restoresDraft: false,
                managesLiveActivity: false
            )
        case "value-radar":
            RestaurantValueRadarDemoView()
        case "celebration":
            CelebrationOverlayDemoView()
        case "add-meal-plan":
            AddMealToPlanView(date: Date(), isPresented: .constant(true))
        case "meal-plan-survey":
            MealPlanSurveyView()
        case "meal-plan-survey-cooking":
            MealPlanSurveyView(initialStep: 5)
        case "meal-prep":
            MealPrepCookingView(days: ScreenshotDemoData.mealPrepDemoDays)
        case "meal-prep-steps":
            MealPrepCookingView(days: ScreenshotDemoData.mealPrepDemoDays, initialTab: 1)
        case "meal-suggestion":
            MealSuggestionDetailView(
                suggestion: ScreenshotDemoData.mealSuggestionDemo,
                pantryItemNames: ScreenshotDemoData.mealSuggestionDemoPantry,
                remainingCalories: 670,
                remainingProtein: 58,
                remainingCarbs: 72,
                remainingFats: 22,
                onLog: { _ in },
                onRegenerate: {}
            )
        case "plate-calculator":
            PlateCalculatorView(initialTargetWeight: 225)
        case "plate-math":
            PlateMathVisualizer(totalWeight: 185)
        case "nutrition-trends":
            NavigationStack {
                CalorieTrackingView(
                    viewModel: ScreenshotDemoData.reportDemoViewModel(
                        dailyLogService: dailyLogService
                    )
                )
            }
        case "maia-insights":
            NavigationStack {
                DetailedInsightsView(
                    insightsService: insightsService,
                    initialInsights: ScreenshotDemoData.insightsDemo
                )
            }
        case "maia-action-cards":
            NavigationStack { MaiaActionCardGalleryView() }
        case "muscle-recovery":
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        AppScreenHeader(
                            eyebrow: "Training Evidence",
                            title: "Muscle Recovery",
                            subtitle: "See where recent strength work may still be carrying fatigue."
                        )
                        MuscleRecoveryMapView(
                            fixtureRecoveries: ScreenshotDemoData.muscleRecoveryEstimates
                        )
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.group)
                }
                .background(AppPalette.canvas.ignoresSafeArea())
            }
        case "shoe-gear-add":
            ShoeGearManagerView(initiallyShowsAddShoe: true)
        default:
            standardHomeContent
        }
    }
    #endif

    private var standardHomeContent: some View {
        NavigationStack {
            HomeView(
                navigateToProfile: .constant(false),
                showSettings: $showSettings,
                livingDayTransition: livingDayTransition,
                isLivingDayHomeEnabled: isLivingDayHomeEnabled
            )
        }
        .trackScreen(.homeDashboard)
    }

    @MainActor
    private func refreshLivingDayFeatureFlagIfNeeded() async {
        guard !didRefreshLivingDayFlag else { return }
        didRefreshLivingDayFlag = true

        if forcesLegacyHome {
            isLivingDayHomeEnabled = false
            return
        }

        if forcesLivingDayHome {
            isLivingDayHomeEnabled = true
            return
        }

        guard let featureFlagService = DIContainer.shared.featureFlagService else { return }
        await featureFlagService.refresh()
        guard !Task.isCancelled else { return }
        isLivingDayHomeEnabled = featureFlagService.isFeatureEnabled(.livingDayHome)
    }

    private func handleFoodLoggedTransition(_ notification: Notification) {
        guard let payload = DailyLogNotifications.foodLoggedPayload(from: notification),
              payload.userID == DIContainer.shared.authService.currentUserID,
              let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date),
              let meal = log.meals.first(where: { meal in
                  meal.foodItems.contains(where: { $0.id == payload.foodItem.id })
              }) else { return }

        livingDayTransition = .foodLogged(payload.foodItem, meal: meal)
    }

    private func handleTrainingFuelTransition(
        from previousPlan: TrainingFuelConfirmedPlan?,
        to currentPlan: TrainingFuelConfirmedPlan?
    ) {
        guard let currentPlan else { return }
        let now = Date()
        let eventID = "training:\(currentPlan.id)"

        if previousPlan?.outcome?.status != currentPlan.outcome?.status,
           let outcome = currentPlan.outcome,
           abs(now.timeIntervalSince(outcome.recordedAt)) <= 12 {
            let kind: LivingDayTransition.Kind
            let title: String
            let detail: String
            switch outcome.status {
            case .completed:
                kind = .trainingCompleted
                title = "Training complete"
                let outcomeDate = outcome.actualEndAt ?? outcome.recordedAt
                let outcomeLog = dailyLogService.currentDailyLog.flatMap { log in
                    Calendar.current.isDate(log.date, inSameDayAs: outcomeDate) ? log : nil
                }
                let progress = TrainingFuelPlanProgressRules.makeProgress(
                    plan: currentPlan,
                    today: outcomeLog,
                    goals: TodayFuelPlanGoals(
                        calories: goalSettings.calories ?? 0,
                        protein: goalSettings.protein,
                        carbs: goalSettings.carbs,
                        fats: goalSettings.fats
                    ),
                    now: now
                )
                detail = progress.status == .recovery
                    ? "Recovery window is ready"
                    : "Today's path reflects the completed session"
            case .skipped:
                kind = .trainingSkipped
                title = "Session skipped"
                detail = "Today's path has been updated"
            }
            livingDayTransition = LivingDayTransition(
                kind: kind,
                eventID: eventID,
                title: title,
                detail: detail,
                createdAt: outcome.recordedAt
            )
            return
        }

        guard previousPlan?.id != currentPlan.id,
              currentPlan.outcome == nil,
              abs(now.timeIntervalSince(currentPlan.confirmedAt)) <= 12 else { return }
        livingDayTransition = LivingDayTransition(
            kind: .trainingPlanned,
            eventID: eventID,
            title: "Training plan ready",
            detail: currentPlan.draft.sessionTitle,
            createdAt: currentPlan.confirmedAt
        )
    }
    
    private func finishTour() {
        withAnimation(AppMotion.visibility) {
            showingSpotlightTour = false
        }
        spotlightManager.markAsShown(id: "action-menu")
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
            showingFoodSearch = true
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

    private var primaryQuickLogOptions: [QuickLogOption] {
        [
            QuickLogOption(
                title: "Search food",
                subtitle: "Find from the food database",
                icon: "magnifyingglass",
                action: { showingFoodSearch = true }
            ),
            QuickLogOption(
                title: "Scan barcode",
                subtitle: "Fast packaged food lookup",
                icon: "barcode.viewfinder",
                action: { showingBarcodeScanner = true }
            ),
            QuickLogOption(
                title: "Describe your meal",
                subtitle: "Tell Maia what you ate",
                icon: "text.bubble.fill",
                action: { showingAITextLog = true }
            )
        ]
    }

    private var additionalQuickLogOptions: [QuickLogOption] {
        [
            QuickLogOption(
                title: "Log with camera",
                subtitle: "Estimate nutrition from a photo",
                icon: "camera.fill",
                action: { showingImagePicker = true }
            ),
            QuickLogOption(
                title: "Log exercise",
                subtitle: "Record activity and calories",
                icon: "figure.walk",
                action: { showingAddExerciseView = true }
            ),
            QuickLogOption(
                title: "Log recipe or meal",
                subtitle: "Use saved recipes and meals",
                icon: "list.clipboard",
                action: { showingRecipeListView = true }
            ),
            QuickLogOption(
                title: "Beat the buffet",
                subtitle: "Log an all-you-can-eat session",
                icon: "fork.knife",
                action: { showingAYCESession = true }
            ),
            QuickLogOption(
                title: "Running",
                subtitle: "Your runs from every watch",
                icon: "figure.run",
                action: { showingRunHistory = true }
            )
        ]
    }

    private var quickLogSheet: some View {
        ZStack {
            AppSheetScaffold(
                title: "Quick Log",
                subtitle: "The fastest ways to capture food and activity.",
                dismiss: dismissQuickLog
            ) {
                ScrollView {
                    VStack(spacing: AppSpacing.group) {
                        quickLogGroup(primaryQuickLogOptions, highlightsFirst: true)
                        quickLogMoreButton

                        if showingAllQuickLogActions {
                            quickLogGroup(additionalQuickLogOptions)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.group)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

            if showingSpotlightTour {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture(perform: finishTour)
                    .transition(.opacity)

                SpotlightTextView(
                    content: (
                        title: "Quick Actions",
                        text: "Search, scan, describe a meal, or open specialty logging tools from one place."
                    ),
                    currentIndex: 0,
                    total: 1,
                    position: .top,
                    onNext: finishTour
                )
            }
        }
        .onAppear {
            if dynamicTypeSize.isAccessibilitySize {
                quickLogDetent = .large
            }
        }
    }

    private func quickLogGroup(_ options: [QuickLogOption], highlightsFirst: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    openQuickLogOption(option)
                } label: {
                    AppListRow(
                        icon: option.icon,
                        iconColor: highlightsFirst && option.id == options.first?.id
                            ? AppPalette.brand
                            : AppPalette.text,
                        title: option.title,
                        subtitle: option.subtitle,
                        hidesTextFromAccessibility: true
                    ) {
                        Image(systemName: "chevron.right")
                            .appTextRole(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityHint(option.subtitle)
                .accessibilityIdentifier("quick_log_\(quickLogIdentifier(for: option.title))")

                if option.id != options.last?.id {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .appSurface(.quiet, padding: 0)
    }

    private var quickLogMoreButton: some View {
        Button {
            HapticsService.shared.playImpact(style: .light)
            let willExpand = !showingAllQuickLogActions
            withAnimation(AppMotion.standard) {
                showingAllQuickLogActions = willExpand
                quickLogDetent = willExpand ? .large : .medium
            }
            DIContainer.shared.analyticsManager?.logEvent("quick_log_more_toggled", parameters: [
                "expanded": willExpand
            ])
        } label: {
            AppListRow(
                icon: showingAllQuickLogActions ? "chevron.up.circle" : "ellipsis.circle",
                title: showingAllQuickLogActions ? "Fewer options" : "More options",
                subtitle: showingAllQuickLogActions
                    ? "Hide specialty logging tools"
                    : "Camera, exercise, recipes, buffet, and running",
                hidesTextFromAccessibility: true
            ) {
                Image(systemName: showingAllQuickLogActions ? "chevron.up" : "chevron.down")
                    .appTextRole(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .appSurface(.quiet, padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingAllQuickLogActions ? "Fewer options" : "More options")
        .accessibilityHint(showingAllQuickLogActions ? "Hide specialty logging tools" : "Show specialty logging tools")
        .accessibilityIdentifier("quick_log_more_options")
        .accessibilityAddTraits(.isButton)
    }

    private func quickLogIdentifier(for title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private func openQuickLogOption(_ option: QuickLogOption) {
        HapticsService.shared.playImpact(style: .light)
        let action = option.action

        withAnimation(AppMotion.visibility) {
            showingAddOptions = false
        }
        showingAllQuickLogActions = false
        quickLogDetent = .medium

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    private func dismissQuickLog() {
        if showingSpotlightTour {
            finishTour()
        }
        withAnimation(AppMotion.visibility) {
            showingAddOptions = false
        }
    }

    private func resetQuickLogPresentation() {
        if showingSpotlightTour {
            finishTour()
        }
        showingAllQuickLogActions = false
        quickLogDetent = .medium
    }
}
