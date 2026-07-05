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
    
    @State private var showSettings = false
    @State private var showingAddOptions = false

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
    
    @State private var scannedFoodItem: FoodItem?
    @State private var scannedFoodSource: String = "barcode_result"
    @State private var pendingManualBarcode: String?
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")
    
    @State private var showingSpotlightTour = false

    private let imageModel = MLImageModel()
    private let barcodeLookupService = BarcodeFoodLookupService()
    
    private var containerBackground: Color {
        Color.backgroundSecondary
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch appState.selectedTab {
                    case 0:
                        NavigationStack { HomeView(navigateToProfile: .constant(false), showSettings: $showSettings) }.trackScreen(.homeDashboard)
                    case 1:
                        NavigationStack { AIChatbotView(selectedTab: $appState.selectedTab) }.trackScreen(.maiaChat)
                    case 2:
                        WorkoutRoutinesView().trackScreen(.workoutsHome)
                    case 3:
                        NavigationStack { MealPlannerView() }.trackScreen(.mealPlanner)
                    case 4:
                        NavigationStack { ReportsView(dailyLogService: dailyLogService) }.trackScreen(.reports)
                    default:
                        NavigationStack { HomeView(navigateToProfile: .constant(false), showSettings: $showSettings) }.trackScreen(.homeDashboard)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 88)

                CustomTabBar(
                    selectedIndex: $appState.selectedTab,
                    showingAddOptions: $showingAddOptions,
                    centerButtonAction: {
                        HapticsService.shared.playImpact(style: .light)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            showingAddOptions.toggle()
                        }
                    }
                )

                if showingAddOptions {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .onTapGesture {
                            HapticsService.shared.playImpact(style: .medium)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                showingAddOptions = false
                            }
                        }
                        .zIndex(1)

                    VStack(alignment: .leading, spacing: 16) {
                        // DESIGN.md rule 2: one hero (search, the primary path, in brand green);
                        // the other rows are neutral — no per-row rainbow tints.
                        let buttons: [(title: String, subtitle: String, icon: String, isPrimary: Bool, action: () -> Void)] = [
                            ("Search food", "Find from the food database", "magnifyingglass", true, { self.showingFoodSearch = true }),
                            ("Scan barcode", "Fast packaged food lookup", "barcode.viewfinder", false, { self.showingBarcodeScanner = true }),
                            ("Log with camera", "Estimate nutrition from a photo", "camera.fill", false, { self.showingImagePicker = true }),
                            ("Describe your meal", "Tell Maia what you ate", "text.bubble.fill", false, { self.showingAITextLog = true }),
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
                                Text("Quick log")
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

                        ForEach(Array(buttons.enumerated()), id: \.offset) { index, buttonInfo in
                            actionButton(
                                title: buttonInfo.title,
                                subtitle: buttonInfo.subtitle,
                                icon: buttonInfo.icon,
                                isPrimary: buttonInfo.isPrimary
                            ) {
                                buttonInfo.action()
                                self.showingAddOptions = false
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05 * Double(index)), value: showingAddOptions)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .frame(maxWidth: 520)
                    .background(containerBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 16)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 104)
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
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(showSettings: $showSettings) } }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: {
                    showingFoodSearch = false
                }, searchContext: "general_search")
            }
            .sheet(isPresented: $showingAddFoodManually) {
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
                        self.scanError = (true, "No match found in FatSecret, USDA, or Open Food Facts. Create it manually, use camera capture, or search by name.")
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
            .alert("Scan Error", isPresented: $scanError.0) {
                Button("Create Food") {
                    DIContainer.shared.analyticsManager.barcodeMissRecovery(
                        .selected(action: "create_food", barcode: pendingManualBarcode)
                    )
                    showingAddFoodManually = true
                }
                Button("Use Camera") {
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
            .onChange(of: showingAddOptions) { _, newValue in
                if newValue && !spotlightManager.isShown(id: "action-menu") {
                    withAnimation {
                        showingSpotlightTour = true
                    }
                }
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
