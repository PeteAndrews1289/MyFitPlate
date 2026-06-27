import SwiftUI
import FirebaseAuth

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
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")
    
    @State private var showingSpotlightTour = false

    private let imageModel = MLImageModel()
    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()
    
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
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            showingAddOptions.toggle()
                        }
                    }
                )

                if showingAddOptions {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)){
                                showingAddOptions = false
                            }
                        }
                        .zIndex(1)

                    VStack(alignment: .leading, spacing: 16) {
                        let buttons: [(title: String, subtitle: String, icon: String, tint: Color, action: () -> Void)] = [
                            ("Search Food", "Find from the food database", "magnifyingglass", .brandPrimary, { self.showingFoodSearch = true }),
                            ("Scan Barcode", "Fast packaged food lookup", "barcode.viewfinder", .accentCarbs, { self.showingBarcodeScanner = true }),
                            ("Log with Camera", "Estimate nutrition from a photo", "camera.fill", .orange, { self.showingImagePicker = true }),
                            ("Describe Your Meal", "Tell Maia what you ate", "text.bubble.fill", .accentPositive, { self.showingAITextLog = true }),
                            ("Log Exercise", "Record activity and calories", "figure.walk", .accentPositive, { self.showingAddExerciseView = true }),
                            ("Log Recipe/Meal", "Use saved recipes and meals", "list.clipboard", .accentFats, { self.showingRecipeListView = true })
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

                                Text("Choose the fastest way to capture food, workouts, or notes.")
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
                                    .font(.system(size: 13, weight: .bold))
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
                                tint: buttonInfo.tint
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
                    initialFoodItem: FoodItem(id: UUID().uuidString, name: "", calories: 0, protein: 0, carbs: 0, fats: 0, servingSize: "", servingWeight: 0),
                    dailyLog: $dailyLogService.currentDailyLog,
                    onLogUpdated: { showingAddFoodManually = false }
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
            .sheet(item: $scannedFoodItem) { foodItem in
                NavigationStack {
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: foodItem.id.hasPrefix("usda_") ? "usda_barcode" : "barcode_result",
                        onLogUpdated: { self.scannedFoodItem = nil }
                    )
                }
            }
            .sheet(isPresented: $showingAITextLog) { AITextLogView() }
            .sheet(isPresented: $showingAddExerciseView) { AddExerciseView { newExercise in if let userID = Auth.auth().currentUser?.uid { dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: newExercise) } } }
            .sheet(isPresented: $showingRecipeListView) {
                RecipeListView().environmentObject(recipeService)
            }
            .alert("Scan Error", isPresented: $scanError.0) { Button("OK") { } } message: { Text(scanError.1) }
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
    
    private func actionButton(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.14))

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
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
                    .font(.system(size: 12, weight: .bold))
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
        .accessibilityHint("Opens \(title)")
    }
}
