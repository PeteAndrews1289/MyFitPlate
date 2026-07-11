import MyFitPlateCore

import SwiftUI
import Firebase
#if ENABLE_APP_CHECK
import FirebaseAppCheck
#endif
import WatchConnectivity
import HealthKit

#if ENABLE_APP_CHECK
/// Supplies App Attest tokens so Firebase backends (Functions, Firestore) can verify that calls
/// come from a genuine build of this app, not a script replaying an auth token.
final class MyFitPlateAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
#endif

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isReachable: Bool = false

    /// Water logged on the watch, waiting to be written to the daily log. Mirrors the
    /// widget's pending-water pattern: accumulate here, drain exactly once on the main actor.
    @Published private(set) var pendingWatchWaterOunces: Double = 0

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

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let ounces = userInfo["logWaterOunces"] as? Double, ounces > 0 else { return }
        DispatchQueue.main.async {
            self.pendingWatchWaterOunces += ounces
        }
    }

    /// Returns the accumulated watch water and resets it, so each transfer logs exactly once.
    func claimPendingWatchWater() -> Double {
        let claimed = pendingWatchWaterOunces
        pendingWatchWaterOunces = 0
        return claimed
    }

    func sendNutritionToWatch(goalCal: Double, userCal: Int, userProt: Double, totalProt: Double, totalCarb: Double, totalFat: Double, userCarb: Double, userFat: Double, goalWeight: Double, userWeight: Double, currWater: Double, goalWater: Double, usesMetric: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired && session.isWatchAppInstalled else { return }
        
        let context: [String: Any] = [
            "goalCal": goalCal, "userCal": userCal,
            "userProt": userProt, "totalProt": totalProt,
            "userCarb": userCarb, "totalCarb": totalCarb,
            "userFat": userFat, "totalFat": totalFat,
            "userWeight": userWeight, "goalWeight": goalWeight,
            "currWater": currWater, "goalWater": goalWater,
            "usesMetric": usesMetric
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
        let launchStartedAt = Date()
        let launchArguments = ProcessInfo.processInfo.arguments
        let isUITesting = launchArguments.contains("-ui-testing")
        let isScreenshotMode = ScreenshotDemoMode.isEnabled

        #if ENABLE_APP_CHECK
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        NutritionConsistencySelfCheck.run()
        // Simulator/dev can't do App Attest, so use the debug provider. On first launch it prints
        // an App Check debug token — register that in Firebase Console → App Check to allow dev calls.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(MyFitPlateAppCheckProviderFactory())
        #endif
        #else
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        NutritionConsistencySelfCheck.run()
        #endif
        #endif
        // When ENABLE_APP_CHECK is defined, the App Check factory must be set BEFORE configure().
        FirebaseApp.configure()

        #if DEBUG
        // Debug builds, simulators, and CI test hosts otherwise register as "active users" in
        // the production Analytics dashboards (every fresh simulator = a new pseudo-ID). Keep
        // collection off in DEBUG; launch with -enable-debug-analytics for a DebugView session.
        // Crashlytics and Remote Config are unaffected.
        Analytics.setAnalyticsCollectionEnabled(
            ProcessInfo.processInfo.arguments.contains("-enable-debug-analytics")
        )
        #endif

        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        
        if isUITesting {
            let mockAuth = MockAuthService()
            let mockDb = MockDatabaseService()
            let mockCloud = MockCloudFunctionService()
            let mockNutrition = MockNutritionRepository()
            let mockWorkout = MockWorkoutRepository()
            let mockSettings = MockSettingsRepository()
            #if DEBUG
            if isScreenshotMode {
                ScreenshotDemoData.prepareUserDefaults()
                ScreenshotDemoData.configureRepositories(
                    nutrition: mockNutrition,
                    workout: mockWorkout,
                    settings: mockSettings
                )
            }
            #endif
            DIContainer.shared.configure(
                authService: mockAuth,
                databaseService: mockDb,
                nutritionRepository: mockNutrition,
                workoutRepository: mockWorkout,
                groupRepository: MockGroupRepository(),
                achievementRepository: MockAchievementRepository(),
                settingsRepository: mockSettings,
                reportsRepository: MockReportsRepository(),
                postRepository: MockPostRepository(),
                cloudFunctionService: mockCloud,
                accountDeletionService: MockAccountDeletionService(),
                analyticsManager: MockAnalyticsManager(),
                crashManager: MockCrashManager(),
                featureFlagService: FeatureFlagService(),
                aiService: MockAIService()
            )
        } else {
            let auth = FirebaseAuthService()
            let db = FirestoreDatabaseService()
            let cloud = FirebaseCloudFunctionService()
            DIContainer.shared.configure(
                authService: auth,
                databaseService: db,
                nutritionRepository: FirestoreNutritionRepository(),
                workoutRepository: FirestoreWorkoutRepository(),
                groupRepository: FirestoreGroupRepository(),
                achievementRepository: FirestoreAchievementRepository(),
                settingsRepository: FirestoreSettingsRepository(),
                reportsRepository: FirestoreReportsRepository(),
                postRepository: FirestorePostRepository(),
                cloudFunctionService: cloud,
                accountDeletionService: AccountDeletionService(authService: auth, databaseService: db, cloudFunctionService: cloud),
                analyticsManager: FirebaseAnalyticsManager(),
                crashManager: FirebaseCrashManager(),
                featureFlagService: FeatureFlagService(remoteProvider: FirebaseRemoteConfigFeatureFlagProvider.makeIfConfigured()),
                aiService: AIService.shared
            )
            DIContainer.shared.communityBarcodeStore = FirestoreCommunityBarcodeStore()
        }

        ReleaseHealth.configure(
            crashManager: DIContainer.shared.crashManager,
            analyticsManager: DIContainer.shared.analyticsManager,
            context: .current(isDebugBuild: isDebugBuild, isUITesting: isUITesting)
        )
        Task { @MainActor in
            await DIContainer.shared.featureFlagService.refresh()
        }

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
        let pantrySvc = PantryService()

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
        _pantryService = StateObject(wrappedValue: pantrySvc)
        
        logService.goalSettings = goalsSvc
        goalsSvc.adaptiveGoalService = adaptiveSvc
        logService.bannerService = bannerSvc
        logService.achievementService = achieveService
        achieveService.setupDependencies(dailyLogService: logService, goalSettings: goalsSvc, bannerService: bannerSvc)
        hkViewModel.setup(
            dailyLogService: logService,
            goalSettings: goalsSvc,
            checkAuthorization: !isScreenshotMode
        )
        cycleSvc.setupDependencies(goalSettings: goalsSvc, dailyLogService: logService)

        #if DEBUG
        if isScreenshotMode {
            ScreenshotDemoData.configureServices(
                goalSettings: goalsSvc,
                dailyLogService: logService,
                healthKitViewModel: hkViewModel,
                appState: applicationState
            )
        }
        #endif
        
        NotificationManager.shared.clearNotificationBadge()
        ReleaseHealth.recordStartupCompleted(
            duration: Date().timeIntervalSince(launchStartedAt),
            crashManager: DIContainer.shared.crashManager,
            analyticsManager: DIContainer.shared.analyticsManager
        )
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
                .environmentObject(AppCoordinator.shared)
                .preferredColorScheme(appState.isDarkModeEnabled ? .dark : .light)
        }
    }
}
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var appCoordinator: AppCoordinator
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var bannerService: BannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @EnvironmentObject var cycleService: CycleTrackingService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @Environment(\.scenePhase) var scenePhase

    @State private var isLoadingUserState = true
    @State private var shouldShowOnboardingSurvey = false
    @State private var shouldShowFeatureTour = false
    @State private var shouldShowFirstSessionChoice = false
    @State private var shouldShowFirstSessionMFPImport = false
    @State private var shouldShowFirstSessionFoodSearch = false
    @State private var isTransitioningFirstSessionChoice = false
    @State private var presentedDeepLinkRoute: Route?
    @State private var didQueueUITestDeepLink = false
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits: Bool = Locale.current.measurementSystem != .us
    @AppStorage("firstSessionChoicePending") private var firstSessionChoicePending = false
    @AppStorage("firstSessionChoiceCompleted") private var firstSessionChoiceCompleted = false
    @AppStorage("firstSessionChoiceViewed") private var firstSessionChoiceViewed = false

    private var currentUserID: String? {
        DIContainer.shared.authService.currentUserID
    }

    private var isScreenshotMode: Bool {
        ScreenshotDemoMode.isEnabled
    }

    var body: some View {
        ZStack {
            mainContent
            
            NotificationBanner(banner: $bannerService.currentBanner)
        }
        .onAppear {
            #if DEBUG
            queueUITestDeepLinkIfNeeded()
            #endif
            checkUserStatusAndFirstLogin()
            sendNutritionToWatchIfNeeded()
            processPendingDeepLinkIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handleAppDidBecomeActive()
        }
        .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
            handleLoginStateChange(isLoggedIn: isLoggedIn)
        }
        .onChange(of: appCoordinator.pendingRoute) { _, _ in
            processPendingDeepLinkIfReady()
        }
        .onChange(of: deferredDeepLinkIsBlocked) { _, isBlocked in
            if !isBlocked {
                processPendingDeepLinkIfReady()
            }
        }
        .onChange(of: dailyLogService.currentDailyLog) {
            sendNutritionToWatchIfNeeded()
        }
        .onChange(of: connectivityManager.pendingWatchWaterOunces) { _, pending in
            if pending > 0 { drainPendingWatchWater() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && appState.isUserLoggedIn {
                scheduleBackgroundNudge()
            }
        }
        .withGlobalToast()
        .sheet(isPresented: $shouldShowFeatureTour) {
            FeatureTourView(isPresented: $shouldShowFeatureTour)
        }
        .sheet(isPresented: $shouldShowFirstSessionChoice, onDismiss: handleFirstSessionChoiceDismissed) {
            FirstSessionChoiceView(
                onImportHistory: { handleFirstSessionChoice(.importHistory) },
                onLogFirstMeal: { handleFirstSessionChoice(.logFirstMeal) },
                onExplore: { handleFirstSessionChoice(.explore) },
                onViewed: recordFirstSessionChoiceViewed
            )
        }
        .sheet(isPresented: $shouldShowFirstSessionMFPImport) {
            MFPImportView()
                .environmentObject(dailyLogService)
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $shouldShowFirstSessionFoodSearch) {
            FoodSearchView(
                dailyLog: $dailyLogService.currentDailyLog,
                onFoodItemLogged: {
                    shouldShowFirstSessionFoodSearch = false
                },
                searchContext: "first_session_log"
            )
        }
        .sheet(item: $presentedDeepLinkRoute, onDismiss: processPendingDeepLinkIfReady) { route in
            deepLinkedContent(for: route)
        }
        .onOpenURL { url in
            appCoordinator.handle(url: url, appState: appState)
        }
    }

    private var deferredDeepLinkIsBlocked: Bool {
        !appState.isUserLoggedIn ||
            isLoadingUserState ||
            shouldShowOnboardingSurvey ||
            shouldShowFeatureTour ||
            shouldShowFirstSessionChoice ||
            shouldShowFirstSessionMFPImport ||
            shouldShowFirstSessionFoodSearch ||
            (firstSessionChoicePending && !firstSessionChoiceCompleted) ||
            isTransitioningFirstSessionChoice ||
            presentedDeepLinkRoute != nil
    }

    private func processPendingDeepLinkIfReady() {
        guard !deferredDeepLinkIsBlocked,
              let route = appCoordinator.takePendingRoute() else { return }

        appState.selectedTab = route.selectedTab
        DIContainer.shared.analyticsManager?.logEvent("deep_link_opened", parameters: [
            "route": route.rawValue
        ])

        switch route {
        case .foodSearch, .trust, .builder, .runs:
            presentedDeepLinkRoute = route
        case .home, .maia, .profile, .settings, .nutrition, .workouts, .reports, .community:
            break
        }
    }

    @ViewBuilder
    private func deepLinkedContent(for route: Route) -> some View {
        switch route {
        case .foodSearch:
            FoodSearchView(
                dailyLog: $dailyLogService.currentDailyLog,
                onFoodItemLogged: { presentedDeepLinkRoute = nil },
                searchContext: "deep_link_food_search"
            )
        case .trust:
            DeepLinkedTrustView()
        case .builder:
            FoodSearchView(
                dailyLog: $dailyLogService.currentDailyLog,
                onFoodItemLogged: { presentedDeepLinkRoute = nil },
                searchContext: "deep_link_builder",
                initialPresentation: .chainBuilder
            )
        case .runs:
            DeepLinkedRunHistoryView()
        case .home, .maia, .profile, .settings, .nutrition, .workouts, .reports, .community:
            EmptyView()
        }
    }

    #if DEBUG
    private func queueUITestDeepLinkIfNeeded() {
        guard !didQueueUITestDeepLink else { return }
        didQueueUITestDeepLink = true

        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-ui-testing"),
              let flagIndex = arguments.firstIndex(of: "-deep-link-url"),
              arguments.indices.contains(flagIndex + 1),
              let url = URL(string: arguments[flagIndex + 1]) else { return }
        appCoordinator.handle(url: url, appState: appState)
    }
    #endif

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
            goalWater: max(1, goalSettings.waterGoal),
            usesMetric: useMetricBodyUnits
        )
    }

    private func handleAppDidBecomeActive() {
        if appState.isUserLoggedIn && !shouldShowOnboardingSurvey {
            if !isScreenshotMode {
                healthKitViewModel.checkAuthorizationStatus()
            }
            sendNutritionToWatchIfNeeded()
            drainPendingWidgetWater()
            drainPendingWatchWater()
        }
    }

    /// Logs water queued by the home-screen widget's button while the app was backgrounded, then
    /// clears the pending value so it's applied exactly once.
    private func drainPendingWidgetWater() {
        guard let userID = currentUserID else { return }
        let pending = SharedDataManager.shared.getAndClearPendingWater()
        guard pending > 0 else { return }
        dailyLogService.addWaterToCurrentLog(for: userID, amount: pending, goalOunces: goalSettings.waterGoal)
        bannerService.showBanner(title: "Water Logged", message: "Added \(Int(pending)) oz from your widget.")
    }

    /// Same idea for water logged on the watch: the log write mutates currentDailyLog, which
    /// re-pushes context so the watch's optimistic total gets replaced by the real one.
    private func drainPendingWatchWater() {
        guard appState.isUserLoggedIn, let userID = currentUserID else { return }
        let pending = connectivityManager.claimPendingWatchWater()
        guard pending > 0 else { return }
        dailyLogService.addWaterToCurrentLog(for: userID, amount: pending, goalOunces: goalSettings.waterGoal)
        bannerService.showBanner(title: "Water Logged", message: "Added \(Int(pending)) oz from your watch.")
    }
    
    private func handleOnboardingComplete() {
        if let userID = currentUserID {
            goalSettings.updateUserAsOnboarded(userID: userID)
        }
        // Spotlight "seen" flags are stored per-device, not per-account, so a second account on
        // the same device inherited the first account's completed tour and never saw its own.
        // A brand-new user just finished onboarding — clear the flags so the Home tour fires fresh.
        spotlightManager.resetSpotlights()
        self.shouldShowOnboardingSurvey = false
        self.firstSessionChoicePending = !firstSessionChoiceCompleted
        self.loadMainUserData()
        if firstSessionChoicePending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                presentFirstSessionChoiceIfNeeded()
            }
        } else {
            self.shouldShowFeatureTour = true
        }
        NotificationManager.shared.requestDailyLogReminderAuthorization()
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted)
    }
    
    private func handleLoginStateChange(isLoggedIn: Bool) {
        if isLoggedIn {
            checkUserStatusAndFirstLogin()
        } else {
            self.isLoadingUserState = false
            self.shouldShowOnboardingSurvey = false
            self.shouldShowFirstSessionChoice = false
            self.shouldShowFirstSessionMFPImport = false
            self.shouldShowFirstSessionFoodSearch = false
            self.pantryService.stopListening()
        }
    }
    
    private func checkUserStatusAndFirstLogin() {
        self.isLoadingUserState = true
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            DispatchQueue.main.async {
                self.shouldShowOnboardingSurvey = false
                self.isLoadingUserState = false
                if self.isScreenshotMode {
                    self.loadMainUserData()
                }
            }
            return
        }
        if let userID = currentUserID {
             checkFirstLogin(userID: userID) { isFirstLogin in
                 DispatchQueue.main.async {
                     self.shouldShowOnboardingSurvey = isFirstLogin
                     self.isLoadingUserState = false
                     if !isFirstLogin {
                         self.loadMainUserData()
                         self.presentFirstSessionChoiceIfNeeded()
                     }
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

     private func checkFirstLogin(userID: String, completion: @escaping (Bool) -> Void) {
         DIContainer.shared.settingsRepository.fetchUserGoals(userID: userID) { data in
             if let data = data, let isFirstLogin = data["isFirstLogin"] as? Bool {
                 completion(isFirstLogin)
             } else {
                 completion(false) // Default if field missing
             }
         }
     }

    private func loadMainUserData() {
        guard appState.isUserLoggedIn, !shouldShowOnboardingSurvey, !isLoadingUserState else { return }
        
        if let userID = currentUserID {
            pantryService.startListening(userID: userID)
            goalSettings.loadUserGoals(userID: userID) {
                self.goalSettings.loadWeightHistory()
                self.sendNutritionToWatchIfNeeded()
            }
            dailyLogService.fetchLog(for: userID, date: Date()) { _ in
                self.sendNutritionToWatchIfNeeded()
            }
            insightsService.generateAndFetchInsights()
            NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
        }
        
        if !isScreenshotMode {
            healthKitViewModel.checkAuthorizationStatus()
        }
    }

    private func presentFirstSessionChoiceIfNeeded() {
        guard appState.isUserLoggedIn,
              !isLoadingUserState,
              !shouldShowOnboardingSurvey,
              firstSessionChoicePending,
              !firstSessionChoiceCompleted else { return }
        shouldShowFeatureTour = false
        shouldShowFirstSessionChoice = true
    }

    private func recordFirstSessionChoiceViewed() {
        guard !firstSessionChoiceViewed else { return }
        firstSessionChoiceViewed = true
        DIContainer.shared.analyticsManager?.logEvent("first_session_choice_viewed", parameters: nil)
    }

    private func handleFirstSessionChoiceDismissed() {
        guard firstSessionChoicePending, !firstSessionChoiceCompleted else { return }
        firstSessionChoicePending = false
        firstSessionChoiceCompleted = true
        DIContainer.shared.analyticsManager?.logEvent("first_session_choice_selected", parameters: [
            "choice": FirstSessionChoice.explore.rawValue,
            "dismissed": true
        ])
    }

    private func handleFirstSessionChoice(_ choice: FirstSessionChoice) {
        firstSessionChoicePending = false
        firstSessionChoiceCompleted = true
        isTransitioningFirstSessionChoice = true
        DIContainer.shared.analyticsManager?.logEvent("first_session_choice_selected", parameters: [
            "choice": choice.rawValue
        ])
        shouldShowFirstSessionChoice = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch choice {
            case .importHistory:
                shouldShowFirstSessionMFPImport = true
            case .logFirstMeal:
                appState.selectedTab = 0
                shouldShowFirstSessionFoodSearch = true
            case .explore:
                shouldShowFeatureTour = true
            }
            isTransitioningFirstSessionChoice = false
        }
    }
}

private struct DeepLinkedTrustView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService

    var body: some View {
        NavigationStack {
            NutritionAuditView(
                dailyLog: dailyLogService.currentDailyLog ?? DailyLog(
                    date: dailyLogService.activelyViewedDate,
                    meals: []
                ),
                dailyLogBinding: $dailyLogService.currentDailyLog,
                date: dailyLogService.activelyViewedDate
            )
        }
    }
}

private struct DeepLinkedRunHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RunHistoryView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private enum FirstSessionChoice: String {
    case importHistory = "import_history"
    case logFirstMeal = "log_first_meal"
    case explore
}

private struct FirstSessionChoiceView: View {
    let onImportHistory: () -> Void
    let onLogFirstMeal: () -> Void
    let onExplore: () -> Void
    let onViewed: () -> Void

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 62, height: 62)
                        .background(Color.brandPrimary.opacity(0.12), in: Circle())

                    Text("Start with your first win")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Bring your history over or log one meal now so today has a real baseline.")
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    firstSessionOption(
                        icon: "square.and.arrow.down",
                        title: "Import my history",
                        subtitle: "Bring MyFitnessPal diary and weight history into MyFitPlate.",
                        color: .brandPrimary,
                        action: onImportHistory
                    )

                    firstSessionOption(
                        icon: "fork.knife",
                        title: "Log my first meal",
                        subtitle: "Open food search with barcode, camera, and Maia options ready.",
                        color: .accentProtein,
                        action: onLogFirstMeal
                    )
                }

                Button(action: onExplore) {
                    Text("I'll explore first")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.backgroundSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 540)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: onViewed)
    }

    private func firstSessionOption(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 46, height: 46)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundSecondary.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}
