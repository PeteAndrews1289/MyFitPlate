import SwiftUI
import Firebase
import FirebaseAuth
import AppTrackingTransparency
import GoogleMobileAds
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isReachable: Bool = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }


    func sendNutritionToWatch(goalCal: Double, userCal: Int, userProt: Double, totalProt: Double, totalCarb: Double, totalFat: Double, userCarb: Double, userFat: Double, goalWeight: Double, userWeight: Double, currWater: Double, goalWater: Double) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        
        let context: [String : Any] = [
            "goalCal": goalCal,
            "userCal": userCal,
            "userProt": userProt,
            "totalProt": totalProt,
            "userCarb": userCarb,
            "totalCarb": totalCarb,
            "userFat": userFat,
            "totalFat": totalFat,
            "userWeight": userWeight,
            "goalWeight": goalWeight,
            "currWater": currWater,
            "goalWater": goalWater
        ]
        
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("❌ Failed to send context to watch: \(error.localizedDescription)")
        }
    }
}


@main
struct CalorieBetaApp: App {
    @StateObject var dailyLogService: DailyLogService
    @StateObject var goalSettings: GoalSettings
    @StateObject var appState: AppState
    @StateObject var groupService: GroupService
    @StateObject var achievementService: AchievementService
    @StateObject var recipeService: RecipeService
    @StateObject var insightsService: InsightsService
    @StateObject var bannerService: BannerService
    @StateObject var mealPlannerService: MealPlannerService
    @StateObject var healthKitViewModel: HealthKitViewModel
    @StateObject var spotlightManager: SpotlightManager
    
    @StateObject var connectivityManager = WatchConnectivityManager()

    init() {
        FirebaseApp.configure()
        
        let bannerSvc = BannerService()
        let logService = DailyLogService()
        let goalsSvc = GoalSettings(dailyLogService: logService)
        let achieveService = AchievementService()
        let applicationState = AppState()
        let communityGroupService = GroupService()
        let recipes = RecipeService()
        let hkViewModel = HealthKitViewModel()
        let insightsSvc = InsightsService(dailyLogService: logService, goalSettings: goalsSvc, healthKitViewModel: hkViewModel)
        let plannerService = MealPlannerService(recipeService: recipes)
        let spotlightMgr = SpotlightManager()

        _dailyLogService = StateObject(wrappedValue: logService)
        _goalSettings = StateObject(wrappedValue: goalsSvc)
        _achievementService = StateObject(wrappedValue: achieveService)
        _appState = StateObject(wrappedValue: applicationState)
        _groupService = StateObject(wrappedValue: communityGroupService)
        _recipeService = StateObject(wrappedValue: recipes)
        _healthKitViewModel = StateObject(wrappedValue: hkViewModel)
        _insightsService = StateObject(wrappedValue: insightsSvc)
        _mealPlannerService = StateObject(wrappedValue: plannerService)
        _bannerService = StateObject(wrappedValue: bannerSvc)
        _spotlightManager = StateObject(wrappedValue: spotlightMgr)
        
        logService.goalSettings = goalsSvc
        logService.bannerService = bannerSvc
        logService.achievementService = achieveService
        achieveService.setupDependencies(dailyLogService: logService, goalSettings: goalsSvc, bannerService: bannerSvc)
        hkViewModel.setup(dailyLogService: logService)
        
        Task { await MobileAds.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(appState)
                .environmentObject(groupService)
                .environmentObject(achievementService)
                .environmentObject(recipeService)
                .environmentObject(insightsService)
                .environmentObject(bannerService)
                .environmentObject(mealPlannerService)
                .environmentObject(healthKitViewModel)
                .environmentObject(connectivityManager)
                .environmentObject(spotlightManager)
                .preferredColorScheme(appState.isDarkModeEnabled ? .dark : .light)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var bannerService: BannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    
    @State private var isLoadingUserState = true
    @State private var shouldShowOnboardingSurvey = false
    @State private var shouldShowFeatureTour = false

    var body: some View {
        ZStack {
            mainContent
                .onAppear(perform: {
                    checkUserStatusAndFirstLogin()
                    sendNutritionToWatchIfNeeded()
                })
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    requestTrackingPermissionIfNeeded()
                    handleAppDidBecomeActive()
                }
                .onChange(of: appState.isUserLoggedIn) { isLoggedIn in
                    handleLoginStateChange(isLoggedIn: isLoggedIn)
                }
                .onChange(of: dailyLogService.currentDailyLog) { _ in
                    sendNutritionToWatchIfNeeded()
                }
            
            BannerView(banner: $bannerService.currentBanner)
        }
        .sheet(isPresented: $shouldShowFeatureTour) {
            FeatureTourView(isPresented: $shouldShowFeatureTour)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoadingUserState { LandingPageView() }
        else if appState.isUserLoggedIn {
            if shouldShowOnboardingSurvey {
                OnboardingSurveyView(onComplete: handleOnboardingComplete).environmentObject(goalSettings)
            } else {
                 NavigationView { MainTabView().navigationBarHidden(true) }.navigationViewStyle(StackNavigationViewStyle())
            }
        } else {
            WelcomeView()
        }
    }
    
    private func sendNutritionToWatchIfNeeded() {
        guard appState.isUserLoggedIn else { return }

        connectivityManager.sendNutritionToWatch(
            goalCal: goalSettings.calories ?? 0.0,
            userCal: Int(dailyLogService.currentDailyLog?.totalCalories() ?? 0),
            userProt: dailyLogService.currentDailyLog?.totalMacros().protein ?? 0.0,
            totalProt: goalSettings.protein,
            totalCarb: goalSettings.carbs,
            totalFat: goalSettings.fats,
            userCarb: dailyLogService.currentDailyLog?.totalMacros().carbs ?? 0.0,
            userFat: dailyLogService.currentDailyLog?.totalMacros().fats ?? 0.0,
            goalWeight: goalSettings.targetWeight ?? 0.0,
            userWeight: goalSettings.weight,
            currWater: dailyLogService.currentDailyLog?.waterTracker?.totalOunces ?? 0.0,
            goalWater: max(1, goalSettings.waterGoal)
        )
    }

    private func handleAppDidBecomeActive() {
        if appState.isUserLoggedIn && !shouldShowOnboardingSurvey {
            healthKitViewModel.checkAuthorizationStatus()
            sendNutritionToWatchIfNeeded()
        }
    }
    
    private func handleOnboardingComplete() {
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.updateUserAsOnboarded(userID: userID)
        }
        self.shouldShowOnboardingSurvey = false
        self.shouldShowFeatureTour = true
    }
    
    private func handleLoginStateChange(isLoggedIn: Bool) {
        if isLoggedIn {
            checkUserStatusAndFirstLogin()
        } else {
            self.isLoadingUserState = false
            self.shouldShowOnboardingSurvey = false
        }
    }
    
    private func checkUserStatusAndFirstLogin() {
        self.isLoadingUserState = true
        if let currentUser = Auth.auth().currentUser {
             checkFirstLoginFirestore(userID: currentUser.uid) { isFirstLogin in
                 DispatchQueue.main.async {
                     self.shouldShowOnboardingSurvey = isFirstLogin
                     if !isFirstLogin { self.loadMainUserData() }
                     self.isLoadingUserState = false
                 }
             }
        } else {
            DispatchQueue.main.async {
                self.appState.isUserLoggedIn = false
                self.isLoadingUserState = false
                self.shouldShowOnboardingSurvey = false
            }
        }
    }

     private func checkFirstLoginFirestore(userID: String, completion: @escaping (Bool) -> Void) {
         let db = Firestore.firestore(); db.collection("users").document(userID).getDocument { document, error in
             if let document = document, document.exists, let data = document.data() {
                 completion(data["isFirstLogin"] as? Bool ?? true)
             } else { completion(true) }
         }
     }

    private func loadMainUserData() {
        guard appState.isUserLoggedIn, !shouldShowOnboardingSurvey, !isLoadingUserState else { return }
        
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.loadUserGoals(userID: userID) {
                self.sendNutritionToWatchIfNeeded()
            }
            dailyLogService.fetchLog(for: userID, date: Date()) { _ in
                self.sendNutritionToWatchIfNeeded()
            }
            goalSettings.loadWeightHistory()
            insightsService.generateAndFetchInsights()
        }
        
        healthKitViewModel.checkAuthorizationStatus()
    }

    private func requestTrackingPermissionIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if #available(iOS 14, *) {
                ATTrackingManager.requestTrackingAuthorization { status in
                }
            }
        }
    }
}
