import MyFitPlateCore

import SwiftUI
import HealthKit

struct IdentifiableFoodItems: Identifiable {
    let id = UUID()
    let items: [FoodItem]
    let photoReview: MealPhotoReviewContext?
    let loggingDate: Date?
    let mealName: String?
    let source: String?
    let isAIEstimate: Bool?
    let reviewTitle: String?
    let dayContext: DiaryDayContext?

    init(items: [FoodItem], photoReview: MealPhotoReviewContext? = nil, loggingDate: Date? = nil, mealName: String? = nil,
         source: String? = nil, isAIEstimate: Bool? = nil, reviewTitle: String? = nil, dayContext: DiaryDayContext? = nil) {
        self.items = items
        self.photoReview = photoReview
        self.loggingDate = loggingDate
        self.mealName = mealName
        self.source = source; self.isAIEstimate = isAIEstimate; self.reviewTitle = reviewTitle; self.dayContext = dayContext
    }
}

struct MainTabView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var groupService: GroupService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @EnvironmentObject var insightsService: InsightsService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @State private var showSettings = false
    @State private var showingFoodSearch = false
    @State private var maiaIsComposing = false
    @State private var showingRecipeListView = false
    @State private var showingGroceryList = false
    @State private var showingAITextLog = false
    @State private var showingRunHistory = false
    @State private var showingWeeklyReport = false
    
    @State private var showingAIDataConsent = false
    @State private var livingDayTransition: LivingDayTransition?
    @State private var isLivingDayHomeEnabled: Bool
    @State private var didRefreshLivingDayFlag = false
    @StateObject private var weeklyRecapLoader = WeeklyRecapLoader()
    #if DEBUG
    @State private var showsSleepPreview = true
    #endif

    private let forcesLivingDayHome: Bool
    private let forcesLegacyHome: Bool

    private var isDirectScreenshotSurface: Bool {
        #if DEBUG
        ScreenshotDemoMode.isEnabled && (
            ScreenshotDemoData.requestedScreen.hasPrefix("design-nutrition-") ||
            ScreenshotDemoData.requestedScreen.hasPrefix("design-training-") ||
            [
            "weight-detail", "wellness-detail", "sleep-history", "fasting-detail", "cycle-detail",
            "profile", "challenges", "pantry", "pantry-recipes", "receipt-review", "barcode-review",
            "ayce-start", "ayce-resume", "ayce-live", "ayce-review", "ayce-summary", "value-radar",
            "celebration", "add-meal-plan", "meal-plan-survey", "meal-plan-survey-cooking", "meal-prep",
            "meal-prep-steps", "meal-suggestion", "plate-calculator", "plate-math",
            "nutrition-trends", "adaptive-tdee-guardrail", "maia-insights", "maia-action-cards",
            "muscle-recovery", "shoe-gear-add", "trust-hub", "week-rescue", "meal-experiments", "useful-question",
            "run-recorder", "run-recorder-workout", "run-detail-unassigned", "shoe-gear-lifetime",
            "cycle-settings", "weight-target", "weight-entry", "design-tools", "design-maia-context", "design-maia-topics",
            "insight-export", "insight-evidence", "design-fuel-history", "design-habit", "home-hydration-design"
        ].contains(ScreenshotDemoData.requestedScreen))
        #else
        false
        #endif
    }

    init() {
        #if DEBUG
        // Development builds should exercise the shipping 2.3 Home by default. Use
        // `-legacy-home` only when deliberately validating the rollback path.
        let forcesLegacyHome = ProcessInfo.processInfo.arguments.contains("-legacy-home")
        let forcesLivingDayHome = !forcesLegacyHome
        #else
        let forcesLegacyHome = false
        let forcesLivingDayHome = false
        #endif
        self.forcesLivingDayHome = forcesLivingDayHome
        self.forcesLegacyHome = forcesLegacyHome
        _isLivingDayHomeEnabled = State(
            initialValue: !forcesLegacyHome && (forcesLivingDayHome || (
                DIContainer.shared.featureFlagService?.isFeatureEnabled(.livingDayHome)
                    ?? FeatureFlag.livingDayHome.defaultValue
            ))
        )

        #if DEBUG
        let screenshotScreen = ScreenshotDemoData.requestedScreen
        _showSettings = State(initialValue: screenshotScreen.hasPrefix("settings"))
        _showingFoodSearch = State(
            initialValue: [
                "quick-log", "food-search", "builder", "trust", "trust-sparse", "trust-correction",
                "my-foods", "add-food",
                "quick-add-macros"
            ].contains(screenshotScreen)
        )
        _showingRecipeListView = State(initialValue: screenshotScreen == "recipes")
        _showingGroceryList = State(initialValue: screenshotScreen == "grocery")
        _showingRunHistory = State(initialValue: screenshotScreen == "runs")
        _showingWeeklyReport = State(initialValue: screenshotScreen.hasPrefix("weekly-report"))
        _showingAITextLog = State(
            initialValue: ["ai-text-log", "ai-text-results"].contains(screenshotScreen)
        )
        #endif
    }

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                // Give each navigation stack the space above the dock. A safe-area
                // inset on the stack can be lost by nested scroll/presentation hosts,
                // leaving their final controls underneath the dock.
                VStack(spacing: 0) {
                    selectedContent
                        .id(appState.selectedTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !isDirectScreenshotSurface && !(appState.selectedTab == 1 && maiaIsComposing) {
                        CustomTabBar(selectedIndex: $appState.selectedTab) {
                            HapticsService.shared.playImpact(style: .light)
                            showingFoodSearch = true
                        }
                    }
                }

            }
            .background { AppPalette.canvas.ignoresSafeArea().accessibilityHidden(true) }
            .ignoresSafeArea(appState.selectedTab == 1 ? [] : .keyboard, edges: .bottom)
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView(showSettings: $showSettings) } }
            .sheet(isPresented: $showingWeeklyReport) {
                WeeklyRecapView()
            }
            .sheet(isPresented: $showingAIDataConsent) {
                AIDataConsentSheet()
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, searchContext: "general_search")
            }
            .sheet(isPresented: $showingAITextLog) {
                AITextLogView(date: dailyLogService.activelyViewedDate, mealName: FoodSearchViewModel.defaultMealName())
            }
            .sheet(isPresented: $showingRunHistory) {
                NavigationStack { RunHistoryView() }
            }
            .sheet(isPresented: $showingRecipeListView) {
                RecipeListView().environmentObject(recipeService)
            }
            .sheet(isPresented: $showingGroceryList) {
                NavigationStack { GroceryListView() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiDataConsentRequired)) { _ in
                showingAIDataConsent = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .foodItemLogged)) { notification in
                handleFoodLoggedTransition(notification)
            }
            .onChange(of: trainingFuelPlanStore.confirmedPlan) { previousPlan, currentPlan in
                handleTrainingFuelTransition(from: previousPlan, to: currentPlan)
            }
            
        }
        .task { await refreshLivingDayFeatureFlagIfNeeded() }
    }

    // Keep the root layout independent of the size of the individual tab and demo views.
    private var selectedContent: AnyView {
        switch appState.selectedTab {
        case 0: return AnyView(homeContent)
        case 1: return AnyView(NavigationStack { AIChatbotView(selectedTab: $appState.selectedTab, isComposing: $maiaIsComposing) }.trackScreen(.maiaChat))
        case 2: return AnyView(WorkoutRoutinesView().trackScreen(.workoutsHome))
        case 3: return AnyView(NavigationStack { MealPlannerView() }.trackScreen(.mealPlanner))
        case 4:
            return AnyView(NavigationStack {
                ReportsView(dailyLogService: dailyLogService, weeklyRecapLoader: weeklyRecapLoader)
            }.trackScreen(.reports))
        default: return AnyView(standardHomeContent)
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen == "visual-system" {
            NavigationStack { AppVisualSystemGallery() }
        } else if ScreenshotDemoMode.isEnabled,
                  isDirectScreenshotSurface {
            screenshotDestination()
        } else if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen.hasPrefix("living-day") {
            NavigationStack {
                LivingDayPrototypeGallery(
                    initialStyle: .initial(for: ScreenshotDemoData.requestedScreen)
                )
            }
        } else {
            standardHomeContent
        }
        #else
        standardHomeContent
        #endif
    }

    #if DEBUG
    private func screenshotDestination() -> AnyView { AnyView(directScreenshotContent) }

    @ViewBuilder
    private var directScreenshotContent: some View {
        switch ScreenshotDemoData.requestedScreen {
        case let route where route.hasPrefix("design-nutrition-"):
            NutritionDesignGallery(screen: String(route.dropFirst("design-nutrition-".count)))
        case let route where route.hasPrefix("design-training-"):
            TrainingDesignGallery(screen: String(route.dropFirst("design-training-".count)))
        case "design-tools":
            NavigationStack { ToolDirectoryView() }
        case "design-maia-context", "design-maia-topics":
            NavigationStack { AIChatbotView(selectedTab: $appState.selectedTab, isComposing: $maiaIsComposing) }
        case "design-fuel-history":
            TrainingFuelHistoryView()
        case "design-habit":
            LoggingHabitView(onSaved: { _ in })
        case "home-hydration-design":
            NavigationStack { CompactHydrationDesignGallery() }
        case "run-recorder":
            RunRecorderView()
        case "run-recorder-workout":
            RunRecorderView(plan: RunWorkoutPlan.builtinTemplates(metric: true).first)
        case "week-rescue":
            NavigationStack { WeekRescueView() }
        case "meal-experiments":
            NavigationStack { MealExperimentsView() }
        case "useful-question":
            AISummaryView(estimatedItems: [ScreenshotDemoData.questionFood], photoReview: ScreenshotDemoData.questionReview)
        case "weight-detail", "weight-target", "weight-entry":
            NavigationStack { WeightTrackingView() }
        case "sleep-history":
            NavigationStack {
                ReportsView(dailyLogService: dailyLogService, weeklyRecapLoader: weeklyRecapLoader)
                    .navigationDestination(isPresented: $showsSleepPreview) {
                        SleepHistoryDetailView(report: Wave3SleepPreview.report)
                    }
            }
        case "wellness-detail":
            WellnessScoreDetailView(
                wellnessScore: ScreenshotDemoData.wellnessDemoScore,
                mealScore: ScreenshotDemoData.wellnessDemoMealScore,
                sleepReport: ScreenshotDemoData.wellnessDemoSleepReport
            )
        case "fasting-detail":
            NavigationStack {
                ScrollView {
                    FastingTrackerCard(manager: ScreenshotDemoData.fastingFixtureManager())
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.vertical, AppSpacing.group)
                }
                .accessibilityIdentifier("fasting_tracker_screen")
                .background(AppPalette.canvas.ignoresSafeArea())
            }
        case "cycle-detail", "cycle-settings":
            NavigationStack { CycleTrackingView() }
        case "profile":
            NavigationStack { UserProfileView() }
        case "challenges":
            NavigationStack { ChallengesView() }
        case "pantry":
            PantryView()
        case "pantry-recipes":
            PantryRecipeGenerationView(
                pantryService: pantryService,
                initialRecipes: ScreenshotDemoData.pantryRecipeDrafts
            )
        case "receipt-review":
            ReceiptScannerView(initialItems: ScreenshotDemoData.receiptDemoItems)
        case "barcode-review":
            RapidBarcodeReviewView(date: Date(), mealName: "Dinner", session: ScreenshotDemoData.barcodeFixtureBatch(), lookupOverride: ScreenshotDemoData.barcodeFixtureLookup)
        case "ayce-start":
            AYCEFlowView(restoresDraft: false, managesLiveActivity: false)
        case "ayce-resume":
            AYCEFlowView(restoresDraft: true, managesLiveActivity: false)
        case "ayce-live":
            AYCEFlowView(
                initialSession: ScreenshotDemoData.ayceLiveSession,
                restoresDraft: false,
                managesLiveActivity: false
            )
        case "ayce-review":
            AYCEPlateReviewDemoView()
        case "ayce-summary":
            AYCEFlowView(
                finishedSession: ScreenshotDemoData.ayceSummarySession,
                restoresDraft: false,
                managesLiveActivity: false
            )
        case "value-radar":
            RestaurantValueRadarDemoView()
        case "celebration":
            CelebrationOverlayDemoView()
        case "add-meal-plan":
            AddMealToPlanView(date: Date(), isPresented: .constant(true))
        case "meal-plan-survey":
            MealPlanSurveyView()
        case "meal-plan-survey-cooking":
            MealPlanSurveyView(initialStep: 5)
        case "meal-prep":
            MealPrepCookingView(days: ScreenshotDemoData.mealPrepDemoDays)
        case "meal-prep-steps":
            MealPrepCookingView(days: ScreenshotDemoData.mealPrepDemoDays, initialTab: 1)
        case "meal-suggestion":
            SavedMealSuggestionDemoView()
        case "plate-calculator":
            PlateCalculatorView(initialTargetWeight: 225)
        case "plate-math":
            PlateMathVisualizer(totalWeight: 185)
        case "nutrition-trends":
            NavigationStack {
                CalorieTrackingView(
                    viewModel: ScreenshotDemoData.reportDemoViewModel(
                        dailyLogService: dailyLogService
                    )
                )
            }
        case "adaptive-tdee-guardrail":
            NavigationStack { MetabolismDashboardView(loadsData: false) }
        case "maia-insights", "insight-export", "insight-evidence":
            NavigationStack {
                DetailedInsightsView(
                    insightsService: insightsService,
                    initialInsights: ScreenshotDemoData.insightsDemo
                )
            }
        case "maia-action-cards":
            NavigationStack { MaiaActionCardGalleryView() }
        case "muscle-recovery":
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            AppScreenHeader(
                                eyebrow: "Training Evidence",
                                title: "Muscle Recovery",
                                subtitle: "See where recent strength work may still be carrying fatigue."
                            )
                        }
                        MuscleRecoveryMapView(
                            fixtureRecoveries: ScreenshotDemoData.muscleRecoveryEstimates
                        )
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.group)
                }
                .background(AppPalette.canvas.ignoresSafeArea())
            }
        case "run-detail-unassigned":
            NavigationStack { RunDetailView(run: ScreenshotDemoData.unassignedGearRun) }
        case "shoe-gear-lifetime":
            ShoeGearManagerView(runs: ScreenshotDemoData.recentGearRuns, lifetimeRuns: ScreenshotDemoData.lifetimeGearRuns)
        case "shoe-gear-add":
            ShoeGearManagerView(initiallyShowsAddShoe: true)
        case "trust-hub":
            NavigationStack {
                NutritionAuditView(
                    dailyLog: ScreenshotDemoData.trustHubDemoLog,
                    dailyLogBinding: .constant(Optional(ScreenshotDemoData.trustHubDemoLog)),
                    date: ScreenshotDemoData.trustHubDemoLog.date
                )
            }
        default:
            standardHomeContent
        }
    }
    #endif

    private var standardHomeContent: some View {
        NavigationStack {
            HomeView(
                navigateToProfile: .constant(false),
                showSettings: $showSettings,
                livingDayTransition: livingDayTransition,
                isLivingDayHomeEnabled: isLivingDayHomeEnabled
            )
        }
        .trackScreen(.homeDashboard)
    }

    @MainActor
    private func refreshLivingDayFeatureFlagIfNeeded() async {
        guard !didRefreshLivingDayFlag else { return }
        didRefreshLivingDayFlag = true

        if forcesLegacyHome {
            isLivingDayHomeEnabled = false
            return
        }

        if forcesLivingDayHome {
            isLivingDayHomeEnabled = true
            return
        }

        guard let featureFlagService = DIContainer.shared.featureFlagService else { return }
        await featureFlagService.refresh()
        guard !Task.isCancelled else { return }
        isLivingDayHomeEnabled = featureFlagService.isFeatureEnabled(.livingDayHome)
    }

    private func handleFoodLoggedTransition(_ notification: Notification) {
        guard let payload = DailyLogNotifications.foodLoggedPayload(from: notification),
              payload.userID == DIContainer.shared.authService.currentUserID,
              let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date),
              let meal = log.meals.first(where: { meal in
                  meal.foodItems.contains(where: { $0.id == payload.foodItem.id })
              }) else { return }

        livingDayTransition = .foodLogged(payload.foodItem, meal: meal)
    }

    private func handleTrainingFuelTransition(
        from previousPlan: TrainingFuelConfirmedPlan?,
        to currentPlan: TrainingFuelConfirmedPlan?
    ) {
        guard let currentPlan else { return }
        let now = Date()
        let eventID = "training:\(currentPlan.id)"

        if previousPlan?.outcome?.status != currentPlan.outcome?.status,
           let outcome = currentPlan.outcome,
           abs(now.timeIntervalSince(outcome.recordedAt)) <= 12 {
            let kind: LivingDayTransition.Kind
            let title: String
            let detail: String
            switch outcome.status {
            case .completed:
                kind = .trainingCompleted
                title = "Training complete"
                let outcomeDate = outcome.actualEndAt ?? outcome.recordedAt
                let outcomeLog = dailyLogService.currentDailyLog.flatMap { log in
                    Calendar.current.isDate(log.date, inSameDayAs: outcomeDate) ? log : nil
                }
                let progress = TrainingFuelPlanProgressRules.makeProgress(
                    plan: currentPlan,
                    today: outcomeLog,
                    goals: TodayFuelPlanGoals(
                        calories: goalSettings.calories ?? 0,
                        protein: goalSettings.protein,
                        carbs: goalSettings.carbs,
                        fats: goalSettings.fats
                    ),
                    now: now
                )
                detail = progress.status == .recovery
                    ? "Recovery window is ready"
                    : "Today's path reflects the completed session"
            case .skipped:
                kind = .trainingSkipped
                title = "Session skipped"
                detail = "Today's path has been updated"
            }
            livingDayTransition = LivingDayTransition(
                kind: kind,
                eventID: eventID,
                title: title,
                detail: detail,
                createdAt: outcome.recordedAt
            )
            return
        }

        guard previousPlan?.id != currentPlan.id,
              currentPlan.outcome == nil,
              abs(now.timeIntervalSince(currentPlan.confirmedAt)) <= 12 else { return }
        livingDayTransition = LivingDayTransition(
            kind: .trainingPlanned,
            eventID: eventID,
            title: "Training plan ready",
            detail: currentPlan.draft.sessionTitle,
            createdAt: currentPlan.confirmedAt
        )
    }
    
}

#if DEBUG
@MainActor
private struct SavedMealSuggestionDemoView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goalSettings: GoalSettings
    @StateObject private var review: MealReviewSaveSession
    @State private var accepted = false

    init() {
        let owner = DIContainer.shared.authService.currentUserID ?? "mock_user"
        let day = DiaryDayContext(userID: owner, date: Calendar.current.startOfDay(for: Date()))!
        _review = StateObject(wrappedValue: ScreenshotDemoData.mealSuggestionDemo.makeReview(
            userID: owner, day: day, source: "ui_test_suggestion", meal: "Lunch"))
    }

    var body: some View {
        if accepted {
            VStack(spacing: 12) {
                Text("Suggestion saved").accessibilityIdentifier("meal_suggestion_accepted")
                let count = dailyLogService.currentDailyLog?.meals.flatMap(\.foodItems)
                    .filter { $0.name == ScreenshotDemoData.mealSuggestionDemo.mealName }.count ?? 0
                Text("Matching food records: \(count)").accessibilityIdentifier("meal_suggestion_saved_count")
            }
        } else {
            SavedMealSuggestionDetailView(review: review,
                pantryItemNames: ScreenshotDemoData.mealSuggestionDemoPantry,
                remainingCalories: 670, remainingProtein: 58, remainingCarbs: 72, remainingFats: 22,
                onRegenerate: regenerationAction,
                onAccepted: { accepted = true })
                .task {
                    guard ScreenshotDemoMode.isEnabled,
                          DIContainer.shared.authService.currentUserID == ScreenshotDemoData.userID,
                          ProcessInfo.processInfo.arguments.contains("-ui-testing-meal-constraints") else { return }
                    goalSettings.mealConstraintProfile = MealConstraintProfile(revisionID: "ui-test-constraints", hardExclusions: ["sesame"])
                }
        }
    }
    private var regenerationAction: (() -> Void)? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-suggestion-alternatives") else { return nil }
        return { regenerate() }
    }
    private func regenerate() {
        guard ScreenshotDemoMode.isEnabled, DIContainer.shared.authService.currentUserID == ScreenshotDemoData.userID,
              ProcessInfo.processInfo.arguments.contains("-ui-testing-suggestion-alternatives") else { return }
        let idea = MealSuggestion(title: "Quick QA bowl", calories: 450, mealName: "Quick QA bowl", protein: 25, carbs: 65, fats: 10,
            ingredients: ["150 g cooked rice", "100 g beans"], instructions: "Combine and warm.", prepMinutes: 8).withGeneratedEvidence()
        _ = review.replaceMealSuggestion(idea)
    }
}

private enum Wave3SleepPreview {
    static var report: EnhancedSleepReport {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))!
        let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
        let end = start.addingTimeInterval(7 * 3600)
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let longWindow = ProcessInfo.processInfo.arguments.contains("-ui-testing-long-sleep-history")
        let windowStart = longWindow ? calendar.date(byAdding: .day, value: -9, to: day)! : day
        var samples = [HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start, end: end),
                       HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: end)]
        if longWindow {
            let earlier = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: windowStart)!
            samples.append(HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                            start: earlier, end: earlier.addingTimeInterval(8 * 3600)))
        }
        let nights = SleepNightEvidence.normalize(samples)
        let days = nights.map { EnhancedSleepReport.DailySleepStageData(date: $0.night, timeInBed: $0.timeInBed,
            timeAsleep: $0.timeAsleep, timeCore: $0.timeCore, timeDeep: $0.timeDeep, timeREM: $0.timeREM, timeAwake: $0.timeAwake) }
        return EnhancedSleepReport(dateRange: longWindow ? "Twelve-day QA window" : "Three-day QA window", averageSleepScore: 0, averageTimeInBed: 0,
            averageTimeAsleep: 7 * 3600, averageTimeInCore: 7 * 3600, averageTimeInDeep: 0, averageTimeInREM: 0,
            averageTimeAwake: 0, sleepConsistencyScore: 0, sleepConsistencyMessage: "One recorded night; no consistency estimate.",
            dailySleepData: days, nightEvidence: nights, requestedDayCount: longWindow ? 12 : 3,
            requestedNights: windowStart...calendar.startOfDay(for: Date()))
    }
}
#endif
