import MyFitPlateCore

import SwiftUI
import StoreKit
import Firebase
#if ENABLE_APP_CHECK
import FirebaseAppCheck
#endif
import WatchConnectivity
import HealthKit
import UserNotifications

#if ENABLE_APP_CHECK
/// Supplies App Attest tokens so Firebase backends (Functions, Firestore) can verify that calls
/// come from a genuine build of this app, not a script replaying an auth token.
final class MyFitPlateAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
#endif

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let reminderID = userInfo["reminder_id"] as? String
        let fingerprint = userInfo["reminder_fingerprint"] as? String
        let action = response.actionIdentifier
        let notificationID = response.notification.request.identifier
        Task { @MainActor in
            if let reminderID, let fingerprint {
                AccountReminderCoordinator.shared.queueResponse(identifier: reminderID, fingerprint: fingerprint, action: action)
            } else if action == UNNotificationDefaultActionIdentifier {
                AppCoordinator.shared.handleCookingNotification(identifier: notificationID)
            }
            completionHandler()
        }
    }
}

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isReachable: Bool = false
    @Published private(set) var isActivated: Bool = false
    @Published private(set) var isPaired: Bool = false
    @Published private(set) var isWatchAppInstalled: Bool = false
    @Published private(set) var syncRequestRevision: Int = 0

    /// Water logged on the watch, waiting to be written to the daily log. Mirrors the
    /// widget's pending-water pattern: accumulate here, drain exactly once on the main actor.
    @Published private(set) var pendingWatchWaterOunces: Double = 0
    @Published private(set) var pendingWatchMealRepeatCount: Int = 0

    private let accountScopeStore = WatchAccountScopeStore()
    private let mealRepeatInbox = WatchMealRepeatInbox()
    private var latestNutritionContext: [String: Any]?
    private var shouldClearWatchAccount = UserDefaults.standard.bool(forKey: "watchAccountClearPending") {
        didSet {
            UserDefaults.standard.set(shouldClearWatchAccount, forKey: "watchAccountClearPending")
        }
    }

    override init() {
        super.init()
        pendingWatchMealRepeatCount = mealRepeatInbox.pendingCount
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.isActivated = activationState == .activated
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            if self.isActivated && self.shouldClearWatchAccount {
                self.sendClearWatchContext()
            } else if self.isActivated {
                self.sendLatestContextIfPossible()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if session.isReachable {
                self.sendLatestContextIfPossible()
            }
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            if session.isPaired && session.isWatchAppInstalled {
                self.sendLatestContextIfPossible()
                self.syncRequestRevision &+= 1
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchQuickActionPayload.syncRequest] as? Bool == true else { return }
        DispatchQueue.main.async {
            self.sendLatestContextIfPossible()
            self.syncRequestRevision &+= 1
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let ounces = userInfo["logWaterOunces"] as? Double,
           ounces > 0,
           let accountScope = userInfo[WatchQuickActionPayload.accountScope] as? String,
           !accountScope.isEmpty {
            DispatchQueue.main.async {
                let entry = PendingWaterEntry(
                    id: (userInfo["waterEntryID"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                    accountScope: accountScope,
                    ounces: ounces,
                    capturedAt: (userInfo["waterCapturedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
                )
                do {
                    guard let inbox = SharedDataManager.shared.waterInbox else { return }
                    try inbox.enqueue(entry)
                    self.pendingWatchWaterOunces += ounces
                } catch {
                    AppLog.watch.error("Could not retain water delivery on this device.")
                }
            }
        }

        if let data = userInfo[WatchQuickActionPayload.repeatMealRequest] as? Data,
           let request = try? JSONDecoder().decode(WatchMealRepeatRequest.self, from: data),
           mealRepeatInbox.enqueue(request) {
            DispatchQueue.main.async {
                self.pendingWatchMealRepeatCount = self.mealRepeatInbox.pendingCount
            }
        }
    }

    func sendNutritionToWatch(
        goalCal: Double,
        userCal: Double,
        userProt: Double,
        totalProt: Double,
        totalCarb: Double,
        totalFat: Double,
        userCarb: Double,
        userFat: Double,
        goalWeight: Double,
        userWeight: Double,
        currWater: Double,
        goalWater: Double,
        usesMetric: Bool,
        userID: String,
        nextAction: DailyNextAction,
        recentMeal: WatchMealSnapshot?
    ) {
        guard WCSession.isSupported() else { return }

        var context: [String: Any] = [
            WatchQuickActionPayload.schema: WatchQuickActionPayload.schemaVersion,
            WatchQuickActionPayload.generatedAt: Date().timeIntervalSince1970,
            "goalCal": goalCal, "userCal": userCal,
            "userProt": userProt, "totalProt": totalProt,
            "userCarb": userCarb, "totalCarb": totalCarb,
            "userFat": userFat, "totalFat": totalFat,
            "userWeight": userWeight, "goalWeight": goalWeight,
            "currWater": currWater, "goalWater": goalWater,
            "usesMetric": usesMetric,
            WatchQuickActionPayload.accountScope: accountScopeStore.scope(for: userID),
            WatchQuickActionPayload.clearAccount: false
        ]

        if let actionData = try? JSONEncoder().encode(nextAction) {
            context[WatchQuickActionPayload.nextAction] = actionData
        }
        if let recentMeal, let mealData = try? JSONEncoder().encode(recentMeal) {
            context[WatchQuickActionPayload.recentMeal] = mealData
        }

        latestNutritionContext = context
        sendLatestContextIfPossible()
    }

    private func sendLatestContextIfPossible() {
        guard let context = latestNutritionContext else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            AppLog.watch.info("Watch context retained until the connectivity session activates.")
            return
        }
        guard session.isPaired && session.isWatchAppInstalled else {
            AppLog.watch.info("Watch context retained until the paired Watch app is installed.")
            return
        }

        do {
            try session.updateApplicationContext(context)
            shouldClearWatchAccount = false
        } catch {
            AppLog.watch.error("Failed to send context to watch: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearWatchAccount() {
        shouldClearWatchAccount = true
        mealRepeatInbox.discardRequests(exceptAccountScope: nil)
        pendingWatchWaterOunces = 0
        pendingWatchMealRepeatCount = 0
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        sendClearWatchContext()
    }

    private func sendClearWatchContext() {
        let context: [String: Any] = [
            WatchQuickActionPayload.schema: WatchQuickActionPayload.schemaVersion,
            WatchQuickActionPayload.generatedAt: Date().timeIntervalSince1970,
            WatchQuickActionPayload.clearAccount: true
        ]
        latestNutritionContext = context
        do {
            try WCSession.default.updateApplicationContext(context)
            shouldClearWatchAccount = false
        } catch {
            AppLog.watch.error("Failed to clear watch context: \(error.localizedDescription, privacy: .public)")
        }
    }

    func nextMealRepeatRequest(for userID: String) -> WatchMealRepeatRequest? {
        let scope = accountScopeStore.scope(for: userID)
        mealRepeatInbox.discardRequests(exceptAccountScope: scope)
        pendingWatchMealRepeatCount = mealRepeatInbox.pendingCount
        return mealRepeatInbox.nextRequest(accountScope: scope)
    }

    func markMealRepeatHandled(id: String) {
        mealRepeatInbox.markHandled(id: id)
        pendingWatchMealRepeatCount = mealRepeatInbox.pendingCount
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
    @StateObject var workoutService: WorkoutService
    @StateObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @StateObject var mealExperimentStore: MealExperimentStore
    
    @StateObject var connectivityManager = WatchConnectivityManager()

    init() {
        let launchStartedAt = Date()
        let launchArguments = ProcessInfo.processInfo.arguments
        let isUITesting = AppRuntime.isUITesting(arguments: launchArguments)
        let isScreenshotMode = ScreenshotDemoMode.isEnabled

        #if ENABLE_APP_CHECK
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        NutritionConsistencySelfCheck.run()
        let environment = ProcessInfo.processInfo.environment
        let testHost = environment["XCTestConfigurationFilePath"] != nil || environment["MYFITPLATE_EMULATOR_TESTS"] == "YES"
        if isUITesting || isScreenshotMode || testHost {
            // Synthetic screens use local services. Emulator tests configure their own
            // named Firebase apps. Neither needs a registrable token in test artifacts.
            AppCheck.setAppCheckProviderFactory(MyFitPlateAppCheckProviderFactory())
        } else {
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        }
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
        
        let configureProductionDependencies = {
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

        #if DEBUG
        if isUITesting {
            let mockAuth = MockAuthService()
            UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("-ui-testing-auto-rest"), forKey: "isAutoRestTimerEnabled")
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-auth-failure") {
                mockAuth.emailSignInError = AuthServiceError.networkUnavailable
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-onboarding") {
                AccountSetupCoordinator.shared.store.clearAll()
            }
            let mockDb = MockDatabaseService()
            let mockCloud = MockCloudFunctionService()
            let mockAI = MockAIService()
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-recipe-draft") {
                mockAI.mockResult = .success(#"{"name":"Reviewed test soup","ingredients":["200 g beans","100 g rice"],"instructions":["Cook the rice.","Mix beans and rice."],"nutrition":{"calories":500,"protein":40,"carbs":60,"fats":10},"servings":2}"#)
            }

            let mockNutrition = MockNutritionRepository()
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-recipe-save-failure") {
                mockNutrition.recipeRevisionError = CocoaError(.fileWriteUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-meal-plan-save-failure") {
                mockNutrition.mealPlanEditError = CocoaError(.fileWriteUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-food-save-failure") {
                mockNutrition.updateLogSuccess = false
                mockNutrition.saveDailyLogError = CocoaError(.fileWriteUnknown)
            }
            let mockWorkout = MockWorkoutRepository()
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-block-save-failure") {
                mockWorkout.programBlockCommitError = CocoaError(.fileWriteUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-history-load-failure") {
                mockWorkout.fetchRecentSessionLogsError = CocoaError(.fileReadUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-workout-save-failure") {
                mockWorkout.saveProgramError = CocoaError(.fileWriteUnknown)
                mockWorkout.saveWorkoutSessionLogError = CocoaError(.fileWriteUnknown)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-workout-draft"),
               let userID = mockAuth.currentUserID {
                try? WorkoutDraftStore().remove(userID: userID)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-strength-equipment")
                || ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-equipment"),
               let userID = mockAuth.currentUserID,
               let prefix = AccountScopedStorageKey.make(prefix: "strengthEquipment", userID: userID) {
                for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix + ".") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-editor-drafts"),
               let userID = mockAuth.currentUserID {
                try? EditorDraftStore().removeAll(userID: userID)
                // The planner's timer index points into those same disposable draft files.
                if let key = AccountScopedStorageKey.make(prefix: "cooking-timer-index", userID: userID) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-ayce"),
               let userID = mockAuth.currentUserID,
               let key = AccountScopedStorageKey.make(prefix: "ayceSessionDraft", userID: userID) {
                UserDefaults.standard.removeObject(forKey: key)
                if let preferencesKey = AccountScopedStorageKey.make(prefix: "aycePreferences", userID: userID) {
                    UserDefaults.standard.removeObject(forKey: preferencesKey)
                }
            }
            let mockSettings = MockSettingsRepository()
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-goal-save-failure") ||
                ProcessInfo.processInfo.arguments.contains("-ui-testing-food-preferences-save-failure") {
                mockSettings.saveUserGoalsError = CocoaError(.fileWriteUnknown)
            }
            let mockAchievements = MockAchievementRepository()
            if isScreenshotMode {
                ScreenshotDemoData.prepareUserDefaults()
                ScreenshotDemoData.configureRepositories(
                    nutrition: mockNutrition,
                    workout: mockWorkout,
                    settings: mockSettings
                )
                ScreenshotDemoData.configureAchievementRepository(mockAchievements)
            }
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-workout-load-failure") {
                mockWorkout.onProgramsSnapshotListenerAdded = { _, update in
                    update(.failure(CocoaError(.coderValueNotFound)))
                }
                mockWorkout.onRoutinesSnapshotListenerAdded = { _, update in update(.success([])) }
            }
            DIContainer.shared.configure(
                authService: mockAuth,
                databaseService: mockDb,
                nutritionRepository: mockNutrition,
                workoutRepository: mockWorkout,
                groupRepository: MockGroupRepository(),
                achievementRepository: mockAchievements,
                settingsRepository: mockSettings,
                reportsRepository: MockReportsRepository(),
                postRepository: MockPostRepository(),
                cloudFunctionService: mockCloud,
                accountDeletionService: MockAccountDeletionService(),
                analyticsManager: MockAnalyticsManager(),
                crashManager: MockCrashManager(),
                featureFlagService: FeatureFlagService(),
                aiService: mockAI
            )
        } else {
            configureProductionDependencies()
        }
        #else
        configureProductionDependencies()
        #endif

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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-spotlights") { spotlightMgr.resetSpotlights() }
        #endif
        let cycleSvc = CycleTrackingService(userID: DIContainer.shared.authService.currentUserID)
        let adaptiveSvc = AdaptiveGoalService()
        let pantrySvc = PantryService()
        let workoutSvc = WorkoutService()
        plannerService.activeWeekRescue = { [weak workoutSvc] userID in
            guard DIContainer.shared.authService.currentUserID == userID,
                  workoutSvc?.activeProgram?.userID == userID else { return nil }
            return workoutSvc?.activeProgram?.weekRescue
        }
        let fuelPlanStore = TrainingFuelPlanStore(repository: isScreenshotMode ? nil : FirestoreTrainingFuelRepository(),
            auth: DIContainer.shared.authService)

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
        _workoutService = StateObject(wrappedValue: workoutSvc)
        _trainingFuelPlanStore = StateObject(wrappedValue: fuelPlanStore)
        _mealExperimentStore = StateObject(wrappedValue: MealExperimentStore(repository: isScreenshotMode ? nil : FirestoreMealExperimentRepository()))
        
        logService.goalSettings = goalsSvc
        goalsSvc.adaptiveGoalService = adaptiveSvc
        logService.bannerService = bannerSvc
        logService.achievementService = achieveService
        logService.trainingFuelPlanStore = fuelPlanStore
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
                achievementService: achieveService,
                healthKitViewModel: hkViewModel,
                cycleTrackingService: cycleSvc,
                adaptiveGoalService: adaptiveSvc,
                appState: applicationState
            )
        }
        #endif
        
        NotificationManager.shared.clearNotificationBadge()
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
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
                .environmentObject(workoutService)
                .environmentObject(trainingFuelPlanStore)
                .environmentObject(mealExperimentStore)
                .environmentObject(AppCoordinator.shared)
                .tint(AppPalette.brandText)
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
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @EnvironmentObject var mealExperimentStore: MealExperimentStore
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var cycleService: CycleTrackingService

    @ObservedObject private var reminderCoordinator = AccountReminderCoordinator.shared
    @State private var reminderSyncGeneration = UUID()
    @State private var presentedReminderTarget: ReminderTarget?
    @State private var waterEntriesInFlight = Set<UUID>()
    @State private var isLoadingUserState = true
    @State private var shouldShowOnboardingSurvey = false
    @State private var shouldShowFeatureTour = false
    @State private var shouldShowFirstSessionChoice = false
    @State private var shouldShowFirstSessionMFPImport = false
    @State private var shouldShowFirstSessionFoodSearch = false
    @State private var isTransitioningFirstSessionChoice = false
    @State private var presentedDeepLinkRoute: Route?
    @State private var presentedDeepLinkRequest: AppLinkRequest?
    @State private var isResolvingDeepLinkDay = false
    @State private var didQueueUITestDeepLink = false
    @ObservedObject private var accountSetup = AccountSetupCoordinator.shared
    @ObservedObject private var localCleanup = AccountLocalCleanup.coordinator
    @ObservedObject private var reviewPrompts = AppReviewPromptQueue.shared
    @Environment(\.requestReview) private var requestReview
    @State private var accountSetupFailureMessage: String?
    @State private var showingAppleDeletionWarning = false
    @State private var provisioningUserID: String?
    @State private var onboardingPrefill: OnboardingProfileDraft?
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

    #if DEBUG
    private var isOnboardingScreenshotSurface: Bool {
        ScreenshotDemoMode.isEnabled && [
            "welcome",
            "login",
            "signup",
            "create-account",
            "plan-reveal",
            "onboarding-pace",
            "onboarding-baseline",
            "onboarding-lifestyle",
            "onboarding-about", "onboarding-height", "onboarding-weight", "onboarding-target",
            "feature-tour-training", "feature-tour-adapt",
            "feature-tour",
            "first-session"
        ].contains(ScreenshotDemoData.requestedScreen)
    }
    #endif

    var body: some View { presentationContent }

    private var contentWithAccountBanners: some View {
        ZStack {
            mainContent

            if bannerService.currentBanner != nil {
                NotificationBanner(banner: $bannerService.currentBanner)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showingAppleDeletionWarning {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Your account was removed. Apple sign-in access couldn't be revoked; you can manage it in your Apple account settings.")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("apple_deletion_warning")
                    Button("Dismiss") { showingAppleDeletionWarning = false }
                        .buttonStyle(AppActionButtonStyle(.ghost))
                }.padding(AppSpacing.group).background(AppPalette.canvas)
            }
            if let message = localCleanup.errorMessage {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account_cleanup_error")
                    Button("Retry cleanup") { _ = AccountLocalCleanup.retryPending() }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("account_cleanup_retry")
                }
                .padding(AppSpacing.group)
                .background(AppPalette.canvas)
            }
        }
    }

    private var accountLifecycleContent: some View {
        contentWithAccountBanners
        .onAppear {
            #if DEBUG
            queueUITestDeepLinkIfNeeded()
            #endif
            _ = AccountLocalCleanup.retryPending()
            checkUserStatusAndFirstLogin()
            dailyLogService.activateAccount(currentUserID)
            goalSettings.activateAccount(currentUserID)
            insightsService.activateAccount(currentUserID)
            recipeService.activateAccount(currentUserID)
            cycleService.activateAccount(currentUserID)
            trainingFuelPlanStore.load(for: currentUserID)
            mealExperimentStore.activateAccount(currentUserID)
            workoutService.activateAccount(currentUserID)
            FastingManager.shared.activateAccount(currentUserID)
            sendNutritionToWatchIfNeeded()
            syncTrainingFuelNotificationsIfNeeded()
            processPendingDeepLinkIfReady()
        }
        .task(id: currentUserID) {
            RunCloudSyncCoordinator.shared.requestSync(owner: currentUserID)
            AYCESessionManager.invalidateActivities(outsideAccount: currentUserID)
            await CookingNotificationCoordinator.shared.reconcile(userID: currentUserID)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            RunCloudSyncCoordinator.shared.requestSync(owner: currentUserID)
            handleAppDidBecomeActive()
            Task { await mealExperimentStore.synchronize() }
            Task { await CookingNotificationCoordinator.shared.reconcile(userID: currentUserID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appleSignInRevocationIncomplete)) { notification in
            guard let deletedUserID = notification.object as? String,
                  currentUserID == nil || currentUserID == deletedUserID else { return }
            showingAppleDeletionWarning = true
        }
        .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
            RunCloudSyncCoordinator.shared.requestSync(owner: isLoggedIn ? currentUserID : nil)
            dailyLogService.activateAccount(isLoggedIn ? currentUserID : nil)
            goalSettings.activateAccount(isLoggedIn ? currentUserID : nil)
            insightsService.activateAccount(isLoggedIn ? currentUserID : nil)
            recipeService.activateAccount(isLoggedIn ? currentUserID : nil)
            if !isLoggedIn {
                presentedDeepLinkRoute = nil
                presentedDeepLinkRequest = nil
                isResolvingDeepLinkDay = false
                pantryService.stopListening()
            }
            cycleService.activateAccount(isLoggedIn ? currentUserID : nil)
            trainingFuelPlanStore.load(for: isLoggedIn ? currentUserID : nil)
            mealExperimentStore.activateAccount(isLoggedIn ? currentUserID : nil)
            workoutService.activateAccount(isLoggedIn ? currentUserID : nil)
            FastingManager.shared.activateAccount(isLoggedIn ? currentUserID : nil)
            handleLoginStateChange(isLoggedIn: isLoggedIn)
            syncTrainingFuelNotificationsIfNeeded()
        }
        .onChange(of: accountSetup.isAuthenticationInFlight) { _, isInFlight in
            // The auth screen has recorded whether it created the account; setup can decide now.
            if !isInFlight && appState.isUserLoggedIn {
                checkUserStatusAndFirstLogin()
            }
        }
    }

    private var routingContent: some View {
        accountLifecycleContent
        .task(id: reviewPrompts.pendingMoment) {
            await presentReviewPromptWhenCalm()
        }
        .onChange(of: appCoordinator.pendingRoute) { _, _ in
            processPendingDeepLinkIfReady()
        }
        .onChange(of: appState.pendingRunFuelReview?.id) { _, requestID in
            guard requestID != nil else { return }
            presentedDeepLinkRoute = nil
            appState.selectedTab = 0
        }
        .task(id: appCoordinator.pendingRequest?.id) {
            while appCoordinator.pendingRequest != nil, !Task.isCancelled {
                if !deferredDeepLinkIsBlocked && ReviewPromptPresentation.isScreenCalm {
                    processPendingDeepLinkIfReady()
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        .onChange(of: deferredDeepLinkIsBlocked) { _, isBlocked in
            if !isBlocked {
                processPendingDeepLinkIfReady()
            }
        }
    }

    private var watchSyncContent: some View {
        routingContent
        .onChange(of: dailyLogService.currentDailyLog) {
            sendNutritionToWatchIfNeeded()
            syncTrainingFuelNotificationsIfNeeded()
        }
        .onChange(of: trainingFuelPlanStore.confirmedPlan) {
            dailyLogService.updateWidgetData()
            sendNutritionToWatchIfNeeded()
            syncTrainingFuelNotificationsIfNeeded()
        }
        .onChange(of: connectivityManager.pendingWatchWaterOunces) { _, pending in
            if pending > 0 { drainPendingWatchWater() }
        }
        .onChange(of: connectivityManager.pendingWatchMealRepeatCount) { _, pending in
            if pending > 0 { drainPendingWatchMealRepeats() }
        }
        .onChange(of: connectivityManager.isActivated) { _, isActivated in
            guard isActivated else { return }
            if appState.isUserLoggedIn {
                sendNutritionToWatchIfNeeded()
            } else {
                connectivityManager.clearWatchAccount()
            }
        }
        .onChange(of: connectivityManager.syncRequestRevision) { _, _ in
            sendNutritionToWatchIfNeeded()
        }
    }

    private var reminderContent: some View {
        watchSyncContent
        .onReceive(NotificationCenter.default.publisher(for: .runLibrariesChanged)) { note in
            if note.object as? String == currentUserID {
                RunCloudSyncCoordinator.shared.requestSync(owner: currentUserID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reminderEvidenceChanged)) { _ in syncTrainingFuelNotificationsIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyLogSyncStateChanged)) { note in
            if note.object as? String == currentUserID { syncTrainingFuelNotificationsIfNeeded() }
        }
        .onChange(of: goalSettings.weightHistory.count) { _, _ in syncTrainingFuelNotificationsIfNeeded() }
        .onChange(of: trainingFuelPlanStore.history) { _, _ in syncTrainingFuelNotificationsIfNeeded() }
        .onReceive(mealExperimentStore.$experiments) { _ in syncTrainingFuelNotificationsIfNeeded() }
        .onChange(of: reminderCoordinator.ownerID) { _, _ in
            presentedReminderTarget = nil
        }
        .task(id: reminderCoordinator.pendingTarget?.id) {
            while reminderCoordinator.pendingTarget != nil, !Task.isCancelled {
                if !deferredDeepLinkIsBlocked && ReviewPromptPresentation.isScreenCalm { processReminderTarget(); return }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        .sheet(item: $presentedReminderTarget) { target in
            ReminderTaskView(target: target).environmentObject(dailyLogService).environmentObject(goalSettings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingFuelNotificationPreferencesChanged)) { _ in
            syncTrainingFuelNotificationsIfNeeded()
        }
    }

    private var presentationContent: some View {
        reminderContent
        .withGlobalToast()
        .onChange(of: deferredDeepLinkIsBlocked, initial: true) { _, paused in
            spotlightManager.setPresentationPaused(paused)
        }
        .sheet(isPresented: $shouldShowFeatureTour, onDismiss: completeFirstLook) {
            FeatureTourView(isPresented: $shouldShowFeatureTour)
        }
        .sheet(isPresented: $shouldShowFirstSessionChoice, onDismiss: handleFirstSessionChoiceDismissed) {
            FirstSessionChoiceView(
                onImportHistory: { handleFirstSessionChoice(.importHistory) },
                onLogFirstMeal: { handleFirstSessionChoice(.logFirstMeal) },
                onExplore: { handleFirstSessionChoice(.explore) },
                onTour: { handleFirstSessionChoice(.tour) },
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
            appCoordinator.handle(url: url)
        }
    }

    /// Logging and check-ins finish inside sheets. Wait until nothing modal is on screen and the app
    /// has stayed calm briefly, so the rating request never interrupts what the person is doing.
    private func presentReviewPromptWhenCalm() async {
        guard reviewPrompts.pendingMoment != nil else { return }

        var calmChecks = 0
        while calmChecks < 3 {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            calmChecks = !deferredDeepLinkIsBlocked && ReviewPromptPresentation.isScreenCalm ? calmChecks + 1 : 0
        }

        guard let moment = reviewPrompts.takePendingRequest() else { return }
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.appReviewPromptRequested.rawValue,
            parameters: ["moment": moment.rawValue]
        )
        requestReview()
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
            isResolvingDeepLinkDay ||
            presentedDeepLinkRoute != nil || presentedReminderTarget != nil
    }

    private func processPendingDeepLinkIfReady() {
        guard !deferredDeepLinkIsBlocked, ReviewPromptPresentation.isScreenCalm,
              let request = appCoordinator.takePendingRequest() else { return }
        let route = request.resolvedRoute(currentUserID: currentUserID)
        presentedDeepLinkRequest = request
        if route != .unavailable, let owner = currentUserID, let context = request.diaryDayContext(for: owner) {
            isResolvingDeepLinkDay = true
            dailyLogService.fetchLog(for: owner, day: context) { result in
                guard currentUserID == owner, presentedDeepLinkRequest?.id == request.id else { return }
                isResolvingDeepLinkDay = false
                switch result {
                case .success: presentDeepLink(route)
                case .failure: presentDeepLink(.unavailable)
                }
            }
        } else { presentDeepLink(route) }
    }

    private func presentDeepLink(_ route: Route) {
        appState.selectedTab = route.selectedTab
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.deepLinkOpened.rawValue, parameters: [
            "destination": route.rawValue
        ])

        switch route {
        case .foodSearch, .trust, .builder, .runs, .profile, .settings, .unavailable,
             .tools, .foodPreferences, .recipes, .pantry, .grocery, .buffet, .plateCalculator, .weekRescue, .mealExperiments, .cookingTimer:
            presentedDeepLinkRoute = route
        case .trainingFuel:
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openTrainingFuelPlanner, object: nil)
            }
        case .home, .maia, .nutrition, .workouts, .reports, .community:
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
        case .cookingTimer:
            CookingTimersInspectionView(notificationID: presentedDeepLinkRequest?.objectID)
        case .profile:
            NavigationStack { UserProfileView() }
        case .settings:
            NavigationStack {
                SettingsView(showSettings: Binding(get: { presentedDeepLinkRoute == .settings }, set: { if !$0 { presentedDeepLinkRoute = nil } }))
            }
        case .tools:
            NavigationStack { ToolDirectoryView() }
        case .foodPreferences:
            SuggestionPreferencesView(goalSettings: goalSettings)
        case .recipes:
            if let objectID = presentedDeepLinkRequest?.objectID {
                DeepLinkedRecipeView(recipeID: objectID, ownerID: currentUserID)
            } else { RecipeListView() }
        case .pantry:
            NavigationStack { PantryView() }
        case .grocery:
            NavigationStack { GroceryListView() }
        case .buffet:
            AYCEFlowView()
        case .plateCalculator:
            PlateCalculatorView()
        case .weekRescue:
            NavigationStack { WeekRescueView() }
        case .mealExperiments:
            NavigationStack {
                MealExperimentsView(openCheckIn: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { presentedDeepLinkRoute = nil } } }
            }
        case .unavailable:
            AppSheetScaffold(title: "Page unavailable", subtitle: "This link may belong to another account, have been removed, or need a newer version.", dismiss: { presentedDeepLinkRoute = nil }) {
                Button("Go home") { presentedDeepLinkRoute = nil; appState.selectedTab = 0 }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .padding(AppSpacing.group)
                    .accessibilityIdentifier("deep_link_unavailable_home")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("deep_link_unavailable")
        case .home, .maia, .nutrition, .workouts, .reports, .community, .trainingFuel:
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

    @ViewBuilder
    private var mainContent: some View {
        #if DEBUG
        if isOnboardingScreenshotSurface {
            onboardingScreenshotContent
        } else {
            standardMainContent
        }
        #else
        standardMainContent
        #endif
    }

    @ViewBuilder
    private var standardMainContent: some View {
        if isLoadingUserState {
            LandingPageView(
                setupFailureMessage: accountSetupFailureMessage,
                onRetrySetup: retryAccountSetup
            )
        } else if appState.isUserLoggedIn {
            if shouldShowOnboardingSurvey {
                OnboardingFlowView(
                    context: .signedIn,
                    prefill: onboardingPrefill,
                    onAcceptPlan: finishSignedInOnboarding
                )
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

    #if DEBUG
    @ViewBuilder
    private var onboardingScreenshotContent: some View {
        switch ScreenshotDemoData.requestedScreen {
        case "welcome":
            WelcomeView()
        case "login":
            LoginView()
        case "signup", "create-account":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .account)
        case "plan-reveal":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .reveal)
        case "onboarding-baseline":
            OnboardingFlowView(context: .beforeAccount, startingPoint: .quiz(.goal), onClose: { })
        case "onboarding-about":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .quiz(.aboutYou), onClose: { })
        case "onboarding-height":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .quiz(.height), onClose: { })
        case "onboarding-weight":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .quiz(.currentWeight), onClose: { })
        case "onboarding-target":
            OnboardingFlowView(context: .beforeAccount, prefill: Self.screenshotOnboardingDraft, startingPoint: .quiz(.targetWeight), onClose: { })
        case "onboarding-lifestyle":
            OnboardingFlowView(
                context: .beforeAccount,
                prefill: Self.screenshotOnboardingDraft,
                startingPoint: .quiz(.activity),
                onClose: { }
            )
        case "onboarding-pace":
            OnboardingFlowView(
                context: .beforeAccount,
                prefill: Self.screenshotOnboardingDraft,
                startingPoint: .quiz(.pace),
                onClose: { }
            )
        case "feature-tour":
            FeatureTourView(isPresented: .constant(true))
        case "feature-tour-training":
            FeatureTourView(isPresented: .constant(true), initialSelection: 1)
        case "feature-tour-adapt":
            FeatureTourView(isPresented: .constant(true), initialSelection: 2)
        case "first-session":
            FirstSessionChoiceView(onImportHistory: {}, onLogFirstMeal: {}, onExplore: {}, onTour: {}, onViewed: {})
        default:
            WelcomeView()
        }
    }

    private static let screenshotOnboardingDraft = OnboardingProfileDraft(
        goal: .lose,
        trainingIntent: "Strength",
        sex: "Female",
        age: 32,
        heightCm: 168,
        currentWeightLbs: 172,
        targetWeightLbs: 160,
        activityMultiplier: 1.55
    )
    #endif

    private func sendNutritionToWatchIfNeeded() {
        guard appState.isUserLoggedIn,
              let userID = currentUserID,
              let todayLog = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(todayLog.date) else { return }

        let goals = TodayFuelPlanGoals(
            calories: goalSettings.calories ?? 0,
            protein: goalSettings.protein,
            carbs: goalSettings.carbs,
            fats: goalSettings.fats
        )
        let nextAction = DailyNextActionRules.makeAction(
            plan: trainingFuelPlanStore.confirmedPlan,
            today: todayLog,
            goals: goals
        )

        connectivityManager.sendNutritionToWatch(
            goalCal: goalSettings.calories ?? 0.0,
            userCal: todayLog.totalCalories(),
            userProt: todayLog.totalMacros().protein,
            totalProt: goalSettings.protein,
            totalCarb: goalSettings.carbs,
            totalFat: goalSettings.fats,
            userCarb: todayLog.totalMacros().carbs,
            userFat: todayLog.totalMacros().fats,
            goalWeight: goalSettings.targetWeight ?? 0.0,
            userWeight: goalSettings.weight,
            currWater: todayLog.waterTracker?.totalOunces ?? 0.0,
            goalWater: goalSettings.isWaterTrackingOnly ? 0 : goalSettings.waterGoal,
            usesMetric: useMetricBodyUnits,
            userID: userID,
            nextAction: nextAction,
            recentMeal: WatchQuickActionRules.recentMeal(from: todayLog)
        )
    }

    private func handleAppDidBecomeActive() {
        _ = AccountLocalCleanup.retryPending()
        FastingManager.shared.activateAccount(appState.isUserLoggedIn ? currentUserID : nil)
        if appState.isUserLoggedIn && !shouldShowOnboardingSurvey {
            if !isScreenshotMode {
                healthKitViewModel.checkAuthorizationStatus()
            }
            sendNutritionToWatchIfNeeded()
            drainPendingWidgetWater()
            drainPendingWatchWater()
            drainPendingWatchMealRepeats()
            syncTrainingFuelNotificationsIfNeeded()
        }
    }

    private func drainPendingWidgetWater() { drainPendingWater() }
    private func drainPendingWatchWater() { drainPendingWater() }

    private func drainPendingWater() {
        guard appState.isUserLoggedIn, let userID = currentUserID,
              let inbox = SharedDataManager.shared.waterInbox else { return }
        let scope = WatchAccountScopeStore().scope(for: userID)
        SharedDataManager.shared.setWaterAccountScope(scope)
        try? SharedDataManager.shared.migrateLegacyWater(accountScope: scope)
        guard let entries = try? inbox.pending(accountScope: scope) else { return }
        for entry in entries where !waterEntriesInFlight.contains(entry.id) {
            waterEntriesInFlight.insert(entry.id)
            dailyLogService.addWaterToLog(
                for: userID, amount: entry.ounces, goalOunces: goalSettings.hydrationTarget(for: entry.capturedAt) ?? 0,
                capturedAt: entry.capturedAt, entryID: entry.id.uuidString
            ) { accepted in
                waterEntriesInFlight.remove(entry.id)
                guard accepted else { return }
                // The diary outbox now owns this receipt durably, including offline.
                try? inbox.acknowledge(entry)
                if currentUserID == userID {
                    bannerService.showBanner(title: "Water added", message: "Saved \(Int(entry.ounces)) oz to your diary.")
                }
            }
        }
    }

    private func drainPendingWatchMealRepeats() {
        guard appState.isUserLoggedIn,
              let userID = currentUserID,
              let request = connectivityManager.nextMealRepeatRequest(for: userID) else { return }
        let items = WatchQuickActionRules.itemsForLogging(
            from: request.snapshot,
            at: request.requestedAt
        )
        guard !items.isEmpty else {
            connectivityManager.markMealRepeatHandled(id: request.id)
            drainPendingWatchMealRepeats()
            return
        }

        dailyLogService.addMealToLog(
            for: userID,
            date: request.requestedAt,
            mealName: request.snapshot.mealName,
            foodItems: items,
            source: "watch_repeat_meal"
        ) { success in
            DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.watchMealRepeatResult.rawValue, parameters: [
                "result": success ? "logged" : "failed",
                "item_count": items.count
            ])
            guard success else { return }
            connectivityManager.markMealRepeatHandled(id: request.id)
            drainPendingWatchMealRepeats()
        }
    }

    private func syncTrainingFuelNotificationsIfNeeded() {
        let owner = appState.isUserLoggedIn ? currentUserID : nil
        reminderCoordinator.activateAccount(owner)
        reminderSyncGeneration = UUID(); let generation = reminderSyncGeneration
        guard let owner else { return }
        Task { @MainActor in
            guard let evidence = await ReminderEvidenceLoader.load(ownerID: owner, goals: goalSettings, fuelStore: trainingFuelPlanStore, experimentStore: mealExperimentStore),
                  currentUserID == owner, reminderSyncGeneration == generation else { return }
            await reminderCoordinator.reconcile(evidence: evidence)
        }
    }

    private func processReminderTarget() {
        guard let target = reminderCoordinator.takePendingTarget(), target.ownerID == currentUserID,
              let day = target.day() else { return }
        if target.kind == .experimentCheckIn { presentedReminderTarget = target; return }
        if let planID = target.planID {
            guard trainingFuelPlanStore.history.contains(where: { $0.plan.id == planID && $0.id == target.planRevisionID && $0.archivedAt == nil }),
                  !trainingFuelPlanStore.conflictingPlanIDs.contains(planID) else { presentDeepLink(.unavailable); return }
            do { try trainingFuelPlanStore.select(planID: planID, for: target.ownerID) } catch { presentDeepLink(.unavailable); return }
        }
        isResolvingDeepLinkDay = true
        dailyLogService.fetchLog(for: target.ownerID, day: day) { result in
            guard currentUserID == target.ownerID else { return }
            isResolvingDeepLinkDay = false
            guard case .success = result else { presentDeepLink(.unavailable); return }
            if target.kind == .beforeTraining || target.kind == .recovery { presentDeepLink(.trainingFuel) } else if target.kind == .eveningProtein || (target.kind == .dailyLog && reminderCoordinator.preferences.diaryRule == .anyFood) { presentDeepLink(.foodSearch) } else { appState.selectedTab = 0; presentedReminderTarget = target }
        }
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
        firstSessionChoiceCompleted = false
        firstSessionChoiceViewed = false
        self.firstSessionChoicePending = true
        self.loadMainUserData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            presentFirstSessionChoiceIfNeeded()
        }
        // Notifications are requested from Home's setup checklist, after the first meal, when
        // the reminder's value is clear.
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted)
        accountSetup.store.clearAll()
        onboardingPrefill = nil
    }

    private func handleLoginStateChange(isLoggedIn: Bool) {
        if isLoggedIn {
            checkUserStatusAndFirstLogin()
            drainPendingWatchMealRepeats()
        } else {
            self.isLoadingUserState = false
            self.accountSetupFailureMessage = nil
            self.onboardingPrefill = nil
            self.shouldShowOnboardingSurvey = false
            self.shouldShowFirstSessionChoice = false
            self.shouldShowFirstSessionMFPImport = false
            self.shouldShowFirstSessionFoodSearch = false
            self.pantryService.stopListening()
            self.connectivityManager.clearWatchAccount()
            FastingManager.shared.activateAccount(nil)
            NotificationManager.shared.cancelAccountNotifications()
        }
    }
    
    private func checkUserStatusAndFirstLogin() {
        self.isLoadingUserState = true
        if AppRuntime.isUITesting() {
            DispatchQueue.main.async {
                self.shouldShowOnboardingSurvey = false
                self.isLoadingUserState = false
                if self.isScreenshotMode {
                    self.loadMainUserData()
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-first-session") {
                    self.presentFirstSessionChoiceIfNeeded()
                }
                #endif
            }
            return
        }
        // An auth screen is still recording whether this sign-in created the account. Deciding now
        // could mistake a brand-new account's missing profile for an unreadable one, so wait; the
        // `isAuthenticationInFlight` change runs this again.
        if accountSetup.isAuthenticationInFlight { return }
        if let userID = currentUserID {
            accountSetupFailureMessage = nil
            DIContainer.shared.settingsRepository.fetchAccountProfile(userID: userID, requireServer: false) { result in
                DispatchQueue.main.async {
                    guard self.currentUserID == userID, self.appState.isUserLoggedIn else { return }
                    switch result {
                    case .success(let profile):
                        self.resolveAccountSetup(userID: userID, profile: profile)
                    case .failure:
                        self.shouldShowOnboardingSurvey = false
                        self.accountSetupFailureMessage = "We couldn't load your profile. Check your connection and retry. Your saved goals haven't changed."
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

    private func resolveAccountSetup(userID: String, profile: [String: Any]?) {
        let store = accountSetup.store
        let draft = store.loadDraft()
        let action = AccountSetupRules.action(
            profile: profile,
            currentUserID: userID,
            pendingAccount: store.loadPendingAccount(),
            hasDraft: draft != nil
        )

        switch action {
        case .none, .discardDraft:
            store.clearAll()
            shouldShowOnboardingSurvey = false
            isLoadingUserState = false
            loadMainUserData()
            presentFirstSessionChoiceIfNeeded()
        case .showSurvey:
            onboardingPrefill = draft
            shouldShowOnboardingSurvey = true
            isLoadingUserState = false
        case .applyDraft, .createProfileThenApplyDraft, .createProfileThenShowSurvey:
            provisionAccount(userID: userID, action: action, draft: draft)
        }
    }

    /// Creates the profile for a brand-new account and saves the accepted plan, in that order, so
    /// the new-profile defaults can never land on top of the plan. One run per account at a time.
    private func provisionAccount(userID: String, action: AccountSetupAction, draft: OnboardingProfileDraft?) {
        guard provisioningUserID != userID else { return }
        provisioningUserID = userID
        accountSetupFailureMessage = nil
        isLoadingUserState = true

        let store = accountSetup.store
        let pending = store.loadPendingAccount()
        let createsProfile = action == .createProfileThenApplyDraft || action == .createProfileThenShowSurvey
        let settings = goalSettings

        Task { @MainActor in
            defer {
                if provisioningUserID == userID { provisioningUserID = nil }
            }
            do {
                if createsProfile {
                    try await BoundedOperation.run(seconds: 20) {
                        try await DIContainer.shared.settingsRepository.createInitialUserData(
                            userID: userID,
                            email: pending?.email ?? "",
                            username: pending?.displayName ?? ""
                        )
                    }
                    store.clearPendingAccount()
                }
                guard currentUserID == userID, appState.isUserLoggedIn else { return }

                guard let draft, action != .createProfileThenShowSurvey else {
                    onboardingPrefill = nil
                    shouldShowOnboardingSurvey = true
                    isLoadingUserState = false
                    return
                }

                let profile = try await DIContainer.shared.settingsRepository.accountProfile(userID: userID)
                guard currentUserID == userID, appState.isUserLoggedIn else { return }
                guard OnboardingStateRules.requiresSetup(profile: profile) else {
                    store.clearAll()
                    shouldShowOnboardingSurvey = false
                    isLoadingUserState = false
                    loadMainUserData()
                    return
                }
                try await BoundedOperation.run(seconds: 20) {
                    try await settings.completeOnboarding(with: draft, userID: userID)
                }
                guard currentUserID == userID, appState.isUserLoggedIn else { return }
                isLoadingUserState = false
                handleOnboardingComplete()
            } catch {
                guard currentUserID == userID else { return }
                accountSetupFailureMessage = "Your sign-in worked, but setup didn't finish. Check your connection and try again."
                if let crashManager = DIContainer.shared.crashManager {
                    ReleaseHealth.recordNonFatal(
                        error,
                        area: .authentication,
                        operation: "account_setup",
                        crashManager: crashManager,
                        analyticsManager: DIContainer.shared.analyticsManager
                    )
                }
            }
        }
    }

    /// A signed-in account that never finished setup accepted its plan from the quiz.
    private func finishSignedInOnboarding(_ draft: OnboardingProfileDraft) {
        guard let userID = currentUserID else { return }
        accountSetup.store.saveDraft(draft)
        provisionAccount(userID: userID, action: .applyDraft, draft: draft)
    }

    private func retryAccountSetup() {
        accountSetupFailureMessage = nil
        checkUserStatusAndFirstLogin()
    }

    private func loadMainUserData() {
        guard appState.isUserLoggedIn, !shouldShowOnboardingSurvey, !isLoadingUserState else { return }
        
        if let userID = currentUserID {
            SharedDataManager.shared.setWaterAccountScope(WatchAccountScopeStore().scope(for: userID))
            pantryService.startListening(userID: userID)
            goalSettings.loadUserGoals(userID: userID) {
                guard self.currentUserID == userID, self.appState.isUserLoggedIn else { return }
                self.goalSettings.loadWeightHistory()
                self.insightsService.generateAndFetchInsights()
                self.sendNutritionToWatchIfNeeded()
                self.syncTrainingFuelNotificationsIfNeeded()
            }
            dailyLogService.fetchLog(for: userID, date: Date()) { _ in
                guard self.currentUserID == userID, self.appState.isUserLoggedIn else { return }
                self.sendNutritionToWatchIfNeeded()
                self.syncTrainingFuelNotificationsIfNeeded()
            }
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
        completeFirstLook()
        DIContainer.shared.analyticsManager?.logEvent("first_session_choice_selected", parameters: [
            "choice": FirstSessionChoice.explore.rawValue,
            "dismissed": true
        ])
    }

    /// First-run choices are the introduction. Don't stack an automatic Home tour behind them.
    /// Settings can still explicitly replay the contextual spotlights.
    private func completeFirstLook() {
        ["dashboardHeader", "quickActions", "menuScanner", "dailyLog", "action-menu"].forEach {
            spotlightManager.markAsShown(id: $0)
        }
    }

    private func handleFirstSessionChoice(_ choice: FirstSessionChoice) {
        firstSessionChoicePending = false
        firstSessionChoiceCompleted = true
        isTransitioningFirstSessionChoice = true
        completeFirstLook()
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
            case .tour:
                shouldShowFeatureTour = true
            case .explore:
                break
            }
            isTransitioningFirstSessionChoice = false
        }
    }
}

private struct DeepLinkedRecipeView: View {
    let recipeID: String
    let ownerID: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var recipe: Recipe?
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if let recipe { RecipeDetailView(recipe: recipe) } else if isLoading { ProgressView("Loading recipe") } else {
                    VStack(spacing: AppSpacing.row) {
                        Image(systemName: "book.closed").appTextRole(.screenTitle).accessibilityHidden(true)
                        Text("Recipe unavailable").appTextRole(.sectionTitle)
                        Text(message ?? "This recipe may have been removed.")
                            .appTextRole(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Open recipes") {
                            dismiss()
                            AppCoordinator.shared.navigate(to: .recipes)
                        }.buttonStyle(AppActionButtonStyle(.primary))
                    }
                    .padding(AppSpacing.screenHorizontal)
                    .accessibilityIdentifier("deep_link_recipe_unavailable")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.canvas)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: appState.isUserLoggedIn) {
            guard let ownerID, appState.isUserLoggedIn, DIContainer.shared.authService.currentUserID == ownerID else {
                recipe = nil; isLoading = false; message = "Open this link from the account that owns the recipe."
                return
            }
            do {
                let recipes = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: ownerID)
                guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID else { return }
                recipe = recipes.first { $0.id == recipeID }
                isLoading = false
            } catch {
                guard DIContainer.shared.authService.currentUserID == ownerID else { return }
                isLoading = false
                message = "Couldn't load this recipe. Check your connection or open your saved recipes."
            }
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
    case tour = "take_tour"
    case explore
}

/// UIKit is the only reliable view of whether any sheet, cover, or alert is showing anywhere in
/// the SwiftUI hierarchy: each one is presented from the key window's root controller.
enum ReviewPromptPresentation {
    @MainActor
    static var isScreenCalm: Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let rootController = activeScene?.keyWindow?.rootViewController else { return false }
        return rootController.presentedViewController == nil
    }
}

private struct FirstSessionChoiceView: View {
    let onImportHistory: () -> Void
    let onLogFirstMeal: () -> Void
    let onExplore: () -> Void
    let onTour: () -> Void
    let onViewed: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                HStack {
                    Label("Your plan is saved", systemImage: "checkmark.circle.fill")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.brandText)
                    Spacer()
                    Button("Close", systemImage: "xmark", action: onExplore)
                        .labelStyle(.iconOnly).buttonStyle(AppIconButtonStyle(.plain))
                }
                OnboardingHeadline(title: "Make today yours.", subtitle: "Start with one small thing. The rest can wait.")
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text("Your first meal is a great start").appTextRole(.sectionTitle)
                    Text("Search, scan a barcode or try a photo. You can edit every entry later.")
                        .appTextRole(.body).foregroundStyle(.secondary)
                }.appSurface(.quiet)
                VStack(spacing: 0) {
                    option("Take a quick tour", detail: "Three things worth knowing.", icon: "sparkles",
                           identifier: "first_session_tour", action: onTour)
                    Divider()
                    option("Bring your history", detail: "Import your MyFitnessPal diary and weight history.", icon: "square.and.arrow.down",
                           identifier: "first_session_import", action: onImportHistory)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingActionDock {
                Button("Log first meal", systemImage: "plus", action: onLogFirstMeal)
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .accessibilityIdentifier("first_session_log")
                Button("Explore on my own", action: onExplore)
                    .buttonStyle(OnboardingTextButtonStyle())
                    .accessibilityIdentifier("first_session_explore")
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: onViewed)
    }

    private func option(_ title: String, detail: String, icon: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                Image(systemName: icon).frame(width: 32).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).appTextRole(.control).foregroundStyle(AppPalette.text)
                    Text(detail).appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").appTextRole(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.vertical, AppSpacing.group)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
