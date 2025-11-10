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
    @EnvironmentObject var spotlightManager: SpotlightManager
    
    @StateObject private var recipeService = RecipeService()
    
    @State private var showSettings = false
    @State private var showingAddOptions = false

    @State private var showingFoodSearch = false
    @State private var showingBarcodeScanner = false
    @State private var showingAddExerciseView = false
    @State private var showingRecipeListView = false
    @State private var showingAITextLog = false
    @State private var showingAddFoodManually = false
    @State private var showingAddJournalView = false // Add state for journal view
    
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")
    
    @State private var showingSpotlightTour = false

    private let imageModel = MLImageModel()
    private let foodAPIService = FatSecretFoodAPIService()
    
    private var containerBackground: Color {
        Color.backgroundSecondary
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch appState.selectedTab {
                    case 0:
                        NavigationView { HomeView(navigateToProfile: .constant(false), showSettings: $showSettings) }
                        .navigationViewStyle(StackNavigationViewStyle())
                    case 1:
                        NavigationView { AIChatbotView(selectedTab: $appState.selectedTab) }
                        .navigationViewStyle(StackNavigationViewStyle())
                    case 2:
                        NavigationView { WorkoutRoutinesView() }
                        .navigationViewStyle(StackNavigationViewStyle())
                    case 3:
                        NavigationView { MealPlannerView() }
                        .navigationViewStyle(StackNavigationViewStyle())
                    case 4:
                        NavigationView { ReportsView(dailyLogService: dailyLogService) }
                        .navigationViewStyle(StackNavigationViewStyle())
                    default:
                        NavigationView { HomeView(navigateToProfile: .constant(false), showSettings: $showSettings) }
                        .navigationViewStyle(StackNavigationViewStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 70)

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
                    Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)){
                                showingAddOptions = false
                            }
                        }
                        .zIndex(1)

                    VStack(spacing: 16) {
                        let buttons = [
                            ("Search Food", "magnifyingglass", { self.showingFoodSearch = true }),
                            ("Scan Barcode", "barcode.viewfinder", { self.showingBarcodeScanner = true }),
                            ("Log with Camera", "camera.fill", { self.showingImagePicker = true }),
                            ("Describe Your Meal", "text.bubble.fill", { self.showingAITextLog = true }),
                            ("Add Journal Entry", "book.closed.fill", { self.showingAddJournalView = true }), // New Button
                            ("Log Exercise", "figure.walk", { self.showingAddExerciseView = true }),
                            ("Log Recipe/Meal", "list.clipboard", { self.showingRecipeListView = true })
                        ]

                        ForEach(Array(buttons.enumerated()), id: \.offset) { index, buttonInfo in
                            actionButton(title: buttonInfo.0, icon: buttonInfo.1) {
                                buttonInfo.2()
                                self.showingAddOptions = false
                            }
                            .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05 * Double(index)), value: showingAddOptions)
                        }
                    }
                    .padding()
                    .background(containerBackground)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                    .padding(40)
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
            .sheet(isPresented: $showSettings) { NavigationView { SettingsView(showSettings: $showSettings) } }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: {
                    showingFoodSearch = false
                }, searchContext: "general_search")
            }
            .sheet(isPresented: $showingAddFoodManually) {
                AddFoodView(
                    isPresented: $showingAddFoodManually,
                    onFoodLogged: { foodItem, mealType in
                        Task {
                            await dailyLogService.logFoodItem(foodItem, mealType: mealType)
                            showingAddFoodManually = false
                        }
                    }
                )
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
            .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                 AISummaryView(estimatedItems: .constant(wrapper.items))
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
            .sheet(item: $scannedFoodItem) { foodItem in
                NavigationView {
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "barcode_result",
                        onLogUpdated: { self.scannedFoodItem = nil }
                    )
                }
            }
            .sheet(isPresented: $showingAITextLog) { AITextLogView() }
            .sheet(isPresented: $showingAddExerciseView) { AddExerciseView { newExercise in if let userID = Auth.auth().currentUser?.uid { dailyLogService.addExerciseToLog(for: userID, exercise: newExercise) } } }
            .sheet(isPresented: $showingRecipeListView) {
                RecipeListView().environmentObject(recipeService)
            }
            .sheet(isPresented: $showingAddJournalView) { // Add sheet for journal
                JournalView()
            }
            .alert("Scan Error", isPresented: $scanError.0) { Button("OK") { } } message: { Text(scanError.1) }
            .onChange(of: showingAddOptions) { newValue in
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
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 24, height: 24)
                Text(title)
                    .foregroundColor(.textPrimary)
                    .appFont(size: 17, weight: .semibold)
                Spacer()
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(12)
        }
    }
}
