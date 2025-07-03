import SwiftUI
import FirebaseAuth

struct MainTabView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var mealPlannerService: MealPlannerService

    @State private var showSettings = false
    @State private var showingAddFoodOptions = false

    @State private var showingAddFoodView = false
    @State private var showingBarcodeScanner = false
    @State private var showingAddExerciseView = false
    @State private var showingRecipeListView = false
    @State private var showingFoodSearch = false
    
    @State private var showingImagePicker = false
    @State private var isProcessingImage = false
    @State private var estimatedFoodItems: [FoodItem]? = nil
    
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")

    private let imageModel = MLImageModel()
    private let foodAPIService = FatSecretFoodAPIService()
    
    private var containerBackground: Color {
        Color.backgroundSecondary
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch appState.selectedTab {
                case 0:
                    NavigationView { HomeView(navigateToProfile: .constant(false), showSettings: $showSettings) }
                    .navigationViewStyle(StackNavigationViewStyle())
                case 1:
                    NavigationView { AIChatbotView(selectedTab: $appState.selectedTab) }
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
                showingAddOptions: $showingAddFoodOptions,
                centerButtonAction: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        showingAddFoodOptions.toggle()
                    }
                }
            )

            if showingAddFoodOptions {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)){
                            showingAddFoodOptions = false
                        }
                    }
                    .zIndex(1)

                VStack(spacing: 16) {
                    let buttons = [
                        ("Search Food", "magnifyingglass", { self.showingFoodSearch = true }),
                        ("Scan Barcode", "barcode.viewfinder", { self.showingBarcodeScanner = true }),
                        ("Log with Camera", "camera.fill", { self.showingImagePicker = true }),
                        ("Add Food Manually", "plus.circle", { self.showingAddFoodView = true }),
                        ("Log Exercise", "figure.walk", { self.showingAddExerciseView = true }),
                        ("Log Recipe/Meal", "list.clipboard", { self.showingRecipeListView = true })
                    ]

                    ForEach(Array(buttons.enumerated()), id: \.offset) { index, buttonInfo in
                        actionButton(title: buttonInfo.0, icon: buttonInfo.1) {
                            buttonInfo.2()
                            self.showingAddFoodOptions = false
                        }
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05 * Double(index)), value: showingAddFoodOptions)
                    }
                }
                .padding()
                .background(containerBackground)
                .cornerRadius(20)
                .shadow(radius: 10)
                .padding(40)
                .zIndex(2)
            }
            
            if isSearchingAfterScan || isProcessingImage {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                ProgressView(isProcessingImage ? "Analyzing Image..." : "Searching...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .scaleEffect(1.5)
                    .zIndex(3)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showSettings) { NavigationView { SettingsView(showSettings: $showSettings) } }
        .sheet(isPresented: $showingAddFoodView) { AddFoodView { newFood in if let userID = Auth.auth().currentUser?.uid { dailyLogService.addFoodToCurrentLog(for: userID, foodItem: newFood, source: "manual_log") } } }
        .sheet(isPresented: $showingFoodSearch) { FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: { showingFoodSearch = false }, searchContext: "general_search" ) }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera) { image in
                self.isProcessingImage = true
                imageModel.estimateNutritionFromImage(image: image) { result in
                    self.isProcessingImage = false
                    switch result {
                    case .success(let foodItems):
                        self.estimatedFoodItems = foodItems
                    case .failure(let error):
                        self.scanError = (true, "Could not analyze the image. Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        .sheet(item: $estimatedFoodItems) { items in
             AISummaryView(estimatedItems: $estimatedFoodItems)
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
        .sheet(isPresented: $showingAddExerciseView) { AddExerciseView { newExercise in if let userID = Auth.auth().currentUser?.uid { dailyLogService.addExerciseToLog(for: userID, exercise: newExercise) } } }
        .sheet(isPresented: $showingRecipeListView) { RecipeListView() }
        .alert("Scan Error", isPresented: $scanError.0) {
            Button("OK") { }
        } message: {
            Text(scanError.1)
        }
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

extension Array: Identifiable where Element: Identifiable {
    public var id: [Element.ID] {
        self.map { $0.id }
    }
}
