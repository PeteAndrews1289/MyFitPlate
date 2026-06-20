import SwiftUI
import Firebase
import FirebaseAuth
import AppTrackingTransparency
import GoogleMobileAds
import WatchConnectivity
import FirebaseAnalytics
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

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sendNutritionToWatch(goalCal: Double, userCal: Int, userProt: Double, totalProt: Double, totalCarb: Double, totalFat: Double, userCarb: Double, userFat: Double, goalWeight: Double, userWeight: Double, currWater: Double, goalWater: Double) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired && session.isWatchAppInstalled else { return }
        
        let context: [String : Any] = [
            "goalCal": goalCal, "userCal": userCal,
            "userProt": userProt, "totalProt": totalProt,
            "userCarb": userCarb, "totalCarb": totalCarb,
            "userFat": userFat, "totalFat": totalFat,
            "userWeight": userWeight, "goalWeight": goalWeight,
            "currWater": currWater, "goalWater": goalWater
        ]
        
        do {
            try session.updateApplicationContext(context)
        } catch {
            AppLog.watch.error("Failed to send context to watch: \(error.localizedDescription, privacy: .public)")
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
    @StateObject var cycleService: CycleTrackingService
    @StateObject var adaptiveGoalService: AdaptiveGoalService
    
    @StateObject var connectivityManager = WatchConnectivityManager()

    init() {
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        NutritionConsistencySelfCheck.run()
        #endif
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        
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
        let cycleSvc = CycleTrackingService()
        let adaptiveSvc = AdaptiveGoalService()

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
        _cycleService = StateObject(wrappedValue: cycleSvc)
        _adaptiveGoalService = StateObject(wrappedValue: adaptiveSvc)
        
        logService.goalSettings = goalsSvc
        goalsSvc.adaptiveGoalService = adaptiveSvc
        logService.bannerService = bannerSvc
        logService.achievementService = achieveService
        achieveService.setupDependencies(dailyLogService: logService, goalSettings: goalsSvc, bannerService: bannerSvc)
        hkViewModel.setup(dailyLogService: logService)
        cycleSvc.setupDependencies(goalSettings: goalsSvc, dailyLogService: logService)
        
        NotificationManager.shared.clearNotificationBadge()
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
                .environmentObject(cycleService)
                .environmentObject(adaptiveGoalService)
                .preferredColorScheme(appState.isDarkModeEnabled ? .dark : .light)
                .onAppear {
                    // Request notification permissions
                    NotificationManager.shared.requestAuthorization { granted in
                        if granted {
                            NotificationManager.shared.scheduleCalendarNotification(.dailyLogReminder(hour: 20, minute: 00))
                        }
                    }
                }
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
    @EnvironmentObject var cycleService: CycleTrackingService
    @Environment(\.scenePhase) var scenePhase
    
    @State private var isLoadingUserState = true
    @State private var shouldShowOnboardingSurvey = false
    @State private var shouldShowFeatureTour = false

    var body: some View {
        ZStack {
            mainContent
                .onAppear {
                    checkUserStatusAndFirstLogin()
                    sendNutritionToWatchIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    requestTrackingPermissionIfNeeded()
                    handleAppDidBecomeActive()
                }
                .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
                    handleLoginStateChange(isLoggedIn: isLoggedIn)
                }
                .onChange(of: dailyLogService.currentDailyLog) {
                    sendNutritionToWatchIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background && appState.isUserLoggedIn {
                        scheduleBackgroundNudge()
                    }
                }
            
            NotificationBanner(banner: $bannerService.currentBanner)
        }
        .sheet(isPresented: $shouldShowFeatureTour) {
            FeatureTourView(isPresented: $shouldShowFeatureTour)
        }
    }
    private func scheduleBackgroundNudge() {
        // Gather Data
        let log = dailyLogService.currentDailyLog
        let goals = goalSettings
        
        // Find last workout info
        let lastWorkoutDate = log?.exercises?.sorted(by: { $0.date < $1.date }).last?.date ?? Date.distantPast
        let daysSinceWorkout = Calendar.current.dateComponents([.day], from: lastWorkoutDate, to: Date()).day ?? 0
        
        // Pass `nil` for wellnessScore since it is not persisted in HealthKitViewModel
        // This is safe because InsightsService will simply skip the "Recovery Hook" if score is nil.
        let context = InsightsService.NotificationContext(
            gender: goals.gender,
            phase: cycleService.cycleDay?.phase, // Will be nil for men or non-trackers
            wellnessScore: nil,
            sleepScore: healthKitViewModel.sleepSummary.lastNightScore,
            caloriesRemaining: (goals.calories ?? 2000) - (log?.totalCalories() ?? 0),
            proteinRemaining: goals.protein - (log?.totalMacros().protein ?? 0),
            daysSinceLastWorkout: daysSinceWorkout,
            lastWorkoutName: log?.exercises?.last?.name,
            stepsToday: healthKitViewModel.todaySteps,
            activeEnergyToday: healthKitViewModel.todayActiveEnergy
        )
        
        Task {
            if let notification = await insightsService.generateSmartNotification(context: context) {
                // Schedule for 5 hours later (e.g. to prompt for the next meal)
                NotificationManager.shared.scheduleSmartNudge(
                    title: notification.title,
                    body: notification.body,
                    delayHours: 5.0
                )
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoadingUserState {
            LandingPageView()
        } else if appState.isUserLoggedIn {
            if shouldShowOnboardingSurvey {
                OnboardingSurveyView(onComplete: handleOnboardingComplete)
                    .environmentObject(goalSettings)
            } else {
                NavigationView {
                    MainTabView()
                        .navigationBarHidden(true)
                }
                .navigationViewStyle(StackNavigationViewStyle())
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
         let db = Firestore.firestore()
         db.collection("users").document(userID).getDocument { document, error in
             if let document = document, document.exists, let data = document.data() {
                 completion(data["isFirstLogin"] as? Bool ?? true)
             } else {
                 completion(true)
             }
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
                ATTrackingManager.requestTrackingAuthorization { status in }
            }
        }
    }
}
