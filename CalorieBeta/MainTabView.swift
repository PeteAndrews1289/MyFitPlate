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
    
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var isSearchingAfterScan = false
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    
    @Environment(\.colorScheme) var colorScheme

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
                    NavigationView { WeightTrackingView() }
                    .navigationViewStyle(StackNavigationViewStyle())
                case 4:
                    NavigationView { ReportsView(dailyLogService: dailyLogService) }
                    .navigationViewStyle(StackNavigationViewStyle())
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 70)

            CustomTabBar(selectedIndex: $appState.selectedTab) {
                withAnimation { showingAddFoodOptions.toggle() }
            }

            if showingAddFoodOptions {
                Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
                    .onTapGesture { withAnimation{ showingAddFoodOptions = false } }
                    .zIndex(1)

                VStack(spacing: 16) {
                    actionButton(title: "Search Food", icon: "magnifyingglass") {
                        self.showingFoodSearch = true
                        self.showingAddFoodOptions = false
                    }
                    actionButton(title: "Scan Barcode", icon: "barcode.viewfinder") {
                        self.showingBarcodeScanner = true
                        self.showingAddFoodOptions = false
                    }
                    actionButton(title: "Add Food Manually", icon: "plus.circle") { self.showingAddFoodView = true; self.showingAddFoodOptions = false }
                    actionButton(title: "Log Exercise", icon: "figure.walk") { self.showingAddExerciseView = true; self.showingAddFoodOptions = false }
                    actionButton(title: "Log Recipe/Meal", icon: "list.clipboard") { self.showingRecipeListView = true; self.showingAddFoodOptions = false }
                }
                .padding().background(containerBackground).cornerRadius(16).shadow(radius: 10)
                .padding(40).zIndex(2).transition(.scale(scale: 0.8).combined(with: .opacity))
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
        .sheet(isPresented: $showingAddFoodView) { AddFoodView { newFood in if let userID = Auth.auth().currentUser?.uid { dailyLogService.addFoodToCurrentLog(for: userID, foodItem: newFood, source: "manual_log") } } }
        .sheet(isPresented: $showingFoodSearch) { FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: { showingFoodSearch = false }, searchContext: "general_search" ) }
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
        .sheet(isPresented: $showingAddExerciseView) {
            AddExerciseView { newExercise in
                if let userID = Auth.auth().currentUser?.uid {
                    dailyLogService.addExerciseToLog(for: userID, exercise: newExercise)
                }
            }
        }
        .sheet(isPresented: $showingRecipeListView) { RecipeListView() }
        .alert("Barcode Scan Failed", isPresented: $scanError.0) {
            Button("OK") { }
        } message: {
            Text(scanError.1)
        }
    }

    private var containerBackground: Color { colorScheme == .dark ? Color(.secondarySystemBackground) : Color(red: 245/255, green: 245/255, blue: 245/255) }
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: { withAnimation { action() } }) { ActionButtonLabel(title: title, icon: icon) } }
}
