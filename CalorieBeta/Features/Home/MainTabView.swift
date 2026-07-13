import MyFitPlateCore

import SwiftUI

struct IdentifiableFoodItems: Identifiable {
    let id = UUID()
    let items: [FoodItem]
}

struct MainTabView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    
    @State private var showSettings = false
    @State private var showingAddOptions = false
    @State private var showingAllQuickLogActions = false
    @State private var quickLogBackdropIsInteractive = false

    @State private var showingFoodSearch = false
    @State private var showingBarcodeScanner = false
    @State private var showingAddExerciseView = false
    @State private var showingRecipeListView = false
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

    private let imageModel = MLImageModel()
    private let barcodeLookupService = BarcodeFoodLookupService()
    
    private var containerBackground: Color {
        Color.backgroundSecondary
    }

    private var suppressesSpotlightTours: Bool {
        ScreenshotDemoMode.isEnabled || ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private func contentBottomInset(for width: CGFloat) -> CGFloat {
        width < 440 ? 128 : 112
    }

    init() {
        #if DEBUG
        let screenshotScreen = ScreenshotDemoData.requestedScreen
        _showSettings = State(initialValue: screenshotScreen == "settings")
        _showingAddOptions = State(initialValue: screenshotScreen == "quick-log")
        _showingFoodSearch = State(
            initialValue: ["food-search", "builder", "trust"].contains(screenshotScreen)
        )
        _showingRunHistory = State(initialValue: screenshotScreen == "runs")
        _showingWeeklyReport = State(initialValue: screenshotScreen == "weekly-report")
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
                            NavigationStack { ReportsView(dailyLogService: dailyLogService) }.trackScreen(.reports)
                        default:
                            NavigationStack {
                                HomeView(
                                    navigateToProfile: .constant(false),
                                    showSettings: $showSettings,
                                    livingDayTransition: livingDayTransition
                                )
                            }
                            .trackScreen(.homeDashboard)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, contentBottomInset(for: geometry.size.width))
                }

                CustomTabBar(
                    selectedIndex: $appState.selectedTab,
                    showingAddOptions: $showingAddOptions,
                    centerButtonAction: {
                        guard !showingAddOptions else { return }
                        HapticsService.shared.playImpact(style: .light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            showingAddOptions = true
                        }
                    }
                )
                .zIndex(showingAddOptions ? 0 : 1)

                if showingAddOptions {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .onTapGesture {
                            HapticsService.shared.playImpact(style: .medium)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                showingAddOptions = false
                                showingAllQuickLogActions = false
                            }
                        }
                        .allowsHitTesting(quickLogBackdropIsInteractive)
                        .zIndex(1)

                    let quickLogPanelContent = VStack(alignment: .leading, spacing: 16) {
                        // DESIGN.md rule 2: one hero (search, the primary path, in brand green);
                        // the other rows are neutral — no per-row rainbow tints.
                        let primaryButtons: [(title: String, subtitle: String, icon: String, isPrimary: Bool, action: () -> Void)] = [
                            ("Search food", "Find from the food database", "magnifyingglass", true, { self.showingFoodSearch = true }),
                            ("Scan barcode", "Fast packaged food lookup", "barcode.viewfinder", false, { self.showingBarcodeScanner = true }),
                            ("Describe your meal", "Tell Maia what you ate", "text.bubble.fill", false, { self.showingAITextLog = true })
                        ]
                        let moreButtons: [(title: String, subtitle: String, icon: String, isPrimary: Bool, action: () -> Void)] = [
                            ("Log with camera", "Estimate nutrition from a photo", "camera.fill", false, { self.showingImagePicker = true }),
                            ("Log exercise", "Record activity and calories", "figure.walk", false, { self.showingAddExerciseView = true }),
                            ("Log recipe or meal", "Use saved recipes and meals", "list.clipboard", false, { self.showingRecipeListView = true }),
                            ("Beat the buffet", "Log an all-you-can-eat session", "fork.knife", false, { self.showingAYCESession = true }),
                            ("Running", "Your runs from every watch", "figure.run", false, { self.showingRunHistory = true })
                        ]

                        Capsule()
                            .fill(Color(UIColor.tertiaryLabel).opacity(0.35))
                            .frame(width: 42, height: 5)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quick Log")
                                    .foregroundColor(.textPrimary)
                                    .appFont(size: 24, weight: .bold)

                                Text("The fastest ways to capture food and activity.")
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .appFont(size: 14)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    showingAddOptions = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .appFont(size: 13, weight: .bold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .frame(width: 32, height: 32)
                                    .background(Color.backgroundPrimary.opacity(0.78), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close quick log menu")
                        }

                        ForEach(Array(primaryButtons.enumerated()), id: \.offset) { index, buttonInfo in
                            actionButton(
                                title: buttonInfo.title,
                                subtitle: buttonInfo.subtitle,
                                icon: buttonInfo.icon,
                                isPrimary: buttonInfo.isPrimary
                            ) {
                                buttonInfo.action()
                                self.showingAddOptions = false
                                self.showingAllQuickLogActions = false
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05 * Double(index)), value: showingAddOptions)
                        }

                        quickLogMoreButton

                        if showingAllQuickLogActions {
                            ForEach(Array(moreButtons.enumerated()), id: \.offset) { index, buttonInfo in
                                actionButton(
                                    title: buttonInfo.title,
                                    subtitle: buttonInfo.subtitle,
                                    icon: buttonInfo.icon,
                                    isPrimary: buttonInfo.isPrimary
                                ) {
                                    buttonInfo.action()
                                    self.showingAddOptions = false
                                    self.showingAllQuickLogActions = false
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(
                                    .spring(response: 0.3, dampingFraction: 0.6).delay(0.04 * Double(index)),
                                    value: showingAllQuickLogActions
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)

                    Group {
                        if showingAllQuickLogActions {
                            ScrollView(.vertical) {
                                quickLogPanelContent
                            }
                            .scrollIndicators(.hidden)
                            .scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: 800)
                        } else {
                            quickLogPanelContent
                        }
                    }
                    .frame(maxWidth: 520)
                    .background(containerBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 16)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 92)
                    .zIndex(2)
                    .featureSpotlight(isActive: showingSpotlightTour)
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
            .onChange(of: showingAddOptions) { _, isShowing in
                quickLogBackdropIsInteractive = false
                guard isShowing else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if showingAddOptions {
                        quickLogBackdropIsInteractive = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(showSettings: $showSettings) } }
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
            .imageSourceDialog(isPresented: $showingImagePicker) { image in
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
            .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                 AISummaryView(estimatedItems: .constant(wrapper.items))
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
                            message: "No match found in FatSecret, USDA, or Open Food Facts.",
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
                    withAnimation {
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
            
            if showingSpotlightTour {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .onTapGesture(perform: finishTour)
                    .transition(.opacity)
                
                let content = (
                    title: "Quick Actions",
                    text: "From here you can log anything. Search our database, scan a barcode, analyze a meal with your camera, or add a recipe or exercise."
                )
                
                SpotlightTextView(
                    content: content,
                    currentIndex: 0,
                    total: 1,
                    position: .top,
                    onNext: finishTour
                )
            }
            
            if isProcessingImage {
                ImageProcessingView()
            }
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
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

    private var standardHomeContent: some View {
        NavigationStack {
            HomeView(
                navigateToProfile: .constant(false),
                showSettings: $showSettings,
                livingDayTransition: livingDayTransition
            )
        }
        .trackScreen(.homeDashboard)
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
        withAnimation {
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

    private var quickLogMoreButton: some View {
        Button {
            HapticsService.shared.playImpact(style: .light)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showingAllQuickLogActions.toggle()
            }
            DIContainer.shared.analyticsManager?.logEvent("quick_log_more_toggled", parameters: [
                "expanded": showingAllQuickLogActions
            ])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: showingAllQuickLogActions ? "chevron.up.circle" : "ellipsis.circle")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(showingAllQuickLogActions ? "Fewer options" : "More options")
                        .foregroundColor(.textPrimary)
                        .appFont(size: 16, weight: .semibold)

                    Text(showingAllQuickLogActions ? "Hide specialty logging tools" : "Camera, exercise, recipes, buffet, and running")
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .appFont(size: 13)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showingAllQuickLogActions ? "Fewer options" : "More options")
        .accessibilityValue(showingAllQuickLogActions ? "Hide specialty logging tools" : "Show specialty logging tools")
        .accessibilityAddTraits(.isButton)
    }
    
    private func actionButton(title: String, subtitle: String, icon: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticsService.shared.playImpact(style: .light)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isPrimary ? Color.brandPrimary : Color(UIColor.secondarySystemFill))

                    Image(systemName: icon)
                        .appFont(size: 18, weight: .semibold)
                        .foregroundColor(isPrimary ? .white : Color(UIColor.secondaryLabel))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.textPrimary)
                        .appFont(size: 16, weight: .semibold)

                    Text(subtitle)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .appFont(size: 13)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .accessibilityHint("Opens \(title)")
    }
}
