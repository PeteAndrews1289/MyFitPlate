import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseAppCheck
import FirebaseCrashlytics
import WatchConnectivity

/// Supplies App Attest tokens so Firebase backends (Functions, Firestore) can verify that calls
/// come from a genuine build of this app, not a script replaying an auth token.
final class MyFitPlateAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        // App Attest requires iOS 14+; this app targets iOS 16+, so it's always available.
        AppAttestProvider(app: app)
    }
}

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
    @StateObject var pantryService: PantryService
    
    @StateObject var connectivityManager = WatchConnectivityManager()

    init() {
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        NutritionConsistencySelfCheck.run()
        // Simulator/dev can't do App Attest, so use the debug provider. On first launch it prints
        // an App Check debug token — register that in Firebase Console → App Check to allow dev calls.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(MyFitPlateAppCheckProviderFactory())
        #endif
        // App Check factory must be set BEFORE configure().
        FirebaseApp.configure()
        
        // Reference Crashlytics so the linker keeps it (it's otherwise never imported) and crash
        // capture stays live from launch; the custom key tags every report with the build version.
        Crashlytics.crashlytics().setCustomValue(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            forKey: "app_version"
        )

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
        _pantryService = StateObject(wrappedValue: PantryService())
        
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
                .environmentObject(pantryService)
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
    @EnvironmentObject var cycleService: CycleTrackingService
    @EnvironmentObject var pantryService: PantryService
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
            drainPendingWidgetWater()
        }
    }

    /// Logs water queued by the home-screen widget's button while the app was backgrounded, then
    /// clears the pending value so it's applied exactly once.
    private func drainPendingWidgetWater() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let pending = SharedDataManager.shared.getAndClearPendingWater()
        guard pending > 0 else { return }
        dailyLogService.addWaterToCurrentLog(for: userID, amount: pending, goalOunces: goalSettings.waterGoal)
        bannerService.showBanner(title: "Water Logged", message: "Added \(Int(pending)) oz from your widget.")
    }
    
    private func handleOnboardingComplete() {
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.updateUserAsOnboarded(userID: userID)
        }
        self.shouldShowOnboardingSurvey = false
        self.shouldShowFeatureTour = true
        NotificationManager.shared.requestDailyLogReminderAuthorization()
    }
    
    private func handleLoginStateChange(isLoggedIn: Bool) {
        if isLoggedIn {
            checkUserStatusAndFirstLogin()
        } else {
            self.isLoadingUserState = false
            self.shouldShowOnboardingSurvey = false
            self.pantryService.stopListening()
        }
    }
    
    private func checkUserStatusAndFirstLogin() {
        self.isLoadingUserState = true
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            DispatchQueue.main.async {
                self.shouldShowOnboardingSurvey = false
                self.isLoadingUserState = false
            }
            return
        }
        if let currentUser = Auth.auth().currentUser {
             checkFirstLoginFirestore(userID: currentUser.uid) { isFirstLogin in
                 DispatchQueue.main.async {
                     self.shouldShowOnboardingSurvey = isFirstLogin
                     self.isLoadingUserState = false
                     if !isFirstLogin { self.loadMainUserData() }
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
            pantryService.startListening(userID: userID)
            goalSettings.loadUserGoals(userID: userID) {
                self.sendNutritionToWatchIfNeeded()
            }
            dailyLogService.fetchLog(for: userID, date: Date()) { _ in
                self.sendNutritionToWatchIfNeeded()
            }
            goalSettings.loadWeightHistory()
            insightsService.generateAndFetchInsights()
            NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
        }
        
        healthKitViewModel.checkAuthorizationStatus()
    }
}
