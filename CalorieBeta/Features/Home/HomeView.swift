import MyFitPlateCore

import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var cycleService: CycleTrackingService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.colorScheme) var colorScheme

    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool
    let livingDayTransition: LivingDayTransition?

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var lastRecoveryCheck: Date?
    @State private var showingProfileSheet = false
    @State private var showingAddExerciseView = false

    @State private var showingWeightEntrySheet = false
    @State private var showingFastingSheet = false
    @State private var showingDetailedInsights = false
    @State private var showingNutritionAudit = false

    @State private var exerciseToEdit: LoggedExercise?
    @State private var showingEditExerciseView = false
    @State private var weeklyInsight: UserInsight?

    @State private var mealSuggestion: MealSuggestion?
    @State private var mealSuggestionTarget: TrainingFuelTarget?
    @State private var showingSuggestionDetail = false
    @State private var showingSuggestionPreferences = false

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false
    @State private var showingCoachingDashboard = false

    @State private var showingWorkoutRoutines = false

    @State private var selectedExerciseForDetail: LoggedExercise?
    @State private var showingWorkoutDetail = false
    @State private var showingWeeklyCheckIn = false
    @State private var showingMenuScanner = false
    @State private var showingWeeklyRecap = false
    @State private var showingRecoveryFuelSearch = false
    @State private var showingTrainingFuelPlanner = false
    @State private var showingTrainingFuelSearch = false
    @State private var showingTrainingFuelBuilder = false
    @State private var pendingTrainingFuelDestination: TrainingFuelDestination?
    @State private var selectedTrainingFuelTarget: TrainingFuelTarget?
    @State private var showingMFPImport = false
    @State private var livingDayMealPlan: MealPlanDay?
    @State private var livingDayMealPlanUserID: String?
    @State private var didRefreshLivingDayFlag = false
    @State private var livingDayFlagRevision = 0
    @StateObject private var runPlanStore = RunWorkoutPlanStore()
    @AppStorage("mfpSwitcherPromptDismissed") private var mfpSwitcherPromptDismissed = false
    @AppStorage("mfpSwitcherPromptSeen") private var mfpSwitcherPromptSeen = false

    // Streak inputs: past logged days fetched once per day; today joins live the moment
    // food is logged, so the flame ticks immediately.
    @State private var pastLoggedDays: [Date] = []
    @State private var lastStreakFetchDay: Date?
    @State private var hasCheckedSwitcherHistory = false

    private var isMenuScannerEnabled: Bool {
        DIContainer.shared.featureFlagService?.isFeatureEnabled(.menuScanner) ?? FeatureFlag.menuScanner.defaultValue
    }

    private var isLivingDayHomeEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-living-day-home") { return true }
        #endif
        _ = livingDayFlagRevision
        return DIContainer.shared.featureFlagService?.isFeatureEnabled(.livingDayHome)
            ?? FeatureFlag.livingDayHome.defaultValue
    }

    private var spotlightOrder: [String] {
        var ids = ["dashboardHeader", "quickActions"]
        if isMenuScannerEnabled {
            ids.append("menuScanner")
        }
        ids.append("dailyLog")
        return ids
    }

    private let spotlightContent: [String: (title: String, text: String)] = [
        "dashboardHeader": (
            title: "Your Dashboard",
            text: "Your calories and macros for the day, front and center. Swipe left or right to move between the Summary, Hydration, and Micronutrient views."
        ),
        "quickActions": (
            title: "Quick Actions",
            text: "Your most-used tools in one tap: start a workout, open Maia's plan, repeat yesterday's meals, scan a menu, log weight, or track a fast."
        ),
        "menuScanner": (
            title: "Menu Matchmaker",
            text: "Out to eat? Tap Menu Scan to photograph the menu and Maia returns 5 picks — the three best fits for your remaining macros, plus the most nutritious and a lighter option."
        ),
        "dailyLog": (
            title: "Your Daily Log",
            text: "Everything you track lands here. Swipe any food or exercise row to delete it, or tap to edit the details."
        )
    ]

    private var selectedDateFormattedString: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(selectedDate) {
            formatter.dateFormat = "MMMM d"
            return "Today, \(formatter.string(from: selectedDate))"
        }
        formatter.dateStyle = .long
        return formatter.string(from: selectedDate)
    }

    private var selectedDateSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var currentLogForSelectedDate: DailyLog? {
        dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: selectedDate) ? log : nil
        }
    }

    var body: some View {
          ZStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 16) {
                            dateNavigationView
                                .padding(.horizontal)
                                .padding(.top, 10)

                            if goalSettings.isCheckInReady {
                                weeklyCheckInBanner
                                    .padding(.horizontal)
                            }

                            Group {
                                if isLivingDayHomeEnabled, isToday {
                                    LivingDayHomeExperience(
                                        snapshot: livingDaySnapshot,
                                        transition: livingDayTransition,
                                        onEventSelected: { event in
                                            handleLivingDayEvent(event, scrollProxy: proxy)
                                        },
                                        onActionSelected: { action in
                                            handleLivingDayAction(action, scrollProxy: proxy)
                                        }
                                    )
                                } else {
                                    // The existing dashboard remains the default and the fallback
                                    // while Living Day soaks behind Remote Config.
                                    HomeDashboardHeader(
                                        dailyLog: currentLogForSelectedDate ?? DailyLog(date: selectedDate, meals: []),
                                        isToday: isToday,
                                        selectedDateFormattedString: selectedDateFormattedString,
                                        weeklyInsight: weeklyInsight,
                                        isHeaderSpotlightActive: isSpotlightActive(for: "dashboardHeader"),
                                        showingDetailedInsights: $showingDetailedInsights,
                                        onReviewFoodTrust: {
                                            showingNutritionAudit = true
                                        }
                                    )
                                }
                            }
                                .padding(.horizontal)
                                .id("dashboardHeader")

                            if shouldOfferSwitcherPrompt {
                                switcherPromptCard
                                    .padding(.horizontal)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            HomeQuickActionsView(
                                showingWorkoutRoutines: $showingWorkoutRoutines,
                                showingCoachingDashboard: $showingCoachingDashboard,
                                showingMenuScanner: $showingMenuScanner,
                                showingWeightEntrySheet: $showingWeightEntrySheet,
                                showingFastingSheet: $showingFastingSheet,
                                showSettings: $showSettings,
                                isMenuScannerEnabled: isMenuScannerEnabled,
                                isMenuScannerSpotlightActive: isMenuScannerEnabled && isSpotlightActive(for: "menuScanner"),
                                onRepeatYesterdayMeals: { repeatYesterdayMeals() }
                            )
                                .featureSpotlight(isActive: isSpotlightActive(for: "quickActions"))
                                .padding(.horizontal)
                                .id("quickActions")

                            // DESIGN.md rule 1: the diary is the most-touched section, so it
                            // sits directly under the hero + actions; activity and weight are
                            // supporting cards and follow it.
                            HomeFoodDiarySection(
                                currentLogForDisplay: currentLogForSelectedDate,
                                isToday: isToday,
                                selectedDate: selectedDate,
                                isDailyLogSpotlightActive: isSpotlightActive(for: "dailyLog"),
                                showingAddExerciseView: $showingAddExerciseView,
                                selectedExerciseForDetail: $selectedExerciseForDetail,
                                showingWorkoutDetail: $showingWorkoutDetail,
                                onDeleteFood: { deleteFood(byID: $0) },
                                onDeleteExercise: { deleteExercise(byID: $0) }
                            )
                                .padding(.horizontal)
                                .id("dailyLog")

                            if isToday, (goalSettings.calories ?? 0) > 0 {
                                TrainingFuelPlannerCard(
                                    suggestedSession: suggestedTrainingFuelSession,
                                    savedPlan: trainingFuelPlanStore.confirmedPlan,
                                    progress: trainingFuelProgress,
                                    onOpen: {
                                        HapticManager.instance.feedback(.light)
                                        DIContainer.shared.analyticsManager?.logEvent(
                                            ProductAnalytics.Event.trainingFuelPlannerOpened.rawValue,
                                            parameters: [
                                                "has_saved_plan": trainingFuelPlanStore.confirmedPlan != nil,
                                                "has_program_suggestion": suggestedTrainingFuelSession != nil
                                            ]
                                        )
                                        showingTrainingFuelPlanner = true
                                    }
                                )
                                .padding(.horizontal)
                            }

                            if shouldOfferFillMyMacros,
                               todayFuelPlan.action == .none,
                               trainingFuelPlanStore.confirmedPlan == nil {
                                fillMyMacrosCard
                                    .padding(.horizontal)
                            }

                            weeklyRecapBanner
                                .padding(.horizontal)

                            if currentLogForSelectedDate != nil {
                                HealthActivityCard()
                                    .padding(.horizontal)

                                HomeWeightTrackingCard(showingWeightEntrySheet: $showingWeightEntrySheet)
                                    .padding(.horizontal)
                            }

                            // The training-aware fuel plan is a "next step" nudge, not the
                            // screen's headline — it sits at the bottom so the rings, quick
                            // actions, and diary keep the prime real estate up top.
                            if shouldShowTodayFuelPlan {
                                todayFuelPlanCard(for: todayFuelPlan)
                                    .padding(.horizontal)
                            }
                        }
                        .frame(width: geometry.size.width, alignment: .top)
                        .clipped()
                        .padding(.bottom, 128)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .onAppear {
                        if let userId = DIContainer.shared.authService.currentUserID {
                            dailyLogService.loadSmartSuggestions(for: userId)
                        }
                    }
                    .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
                        if isLoggedIn, let userId = DIContainer.shared.authService.currentUserID {
                            dailyLogService.loadSmartSuggestions(for: userId)
                            workoutService.fetchRoutinesAndPrograms()
                            trainingFuelPlanStore.load(for: userId)
                            refreshLivingDayMealPlan()
                        } else {
                            dailyLogService.smartSuggestions = []
                            trainingFuelPlanStore.load(for: nil)
                            livingDayMealPlan = nil
                            livingDayMealPlanUserID = nil
                        }
                    }
                    .onChange(of: currentSpotlightIndex) { _, newIndex in
                        if showingSpotlightTour && newIndex < tourSpotlightIDs.count {
                            let spotlightID = tourSpotlightIDs[newIndex]
                            withAnimation {
                                proxy.scrollTo(spotlightID, anchor: .center)
                            }
                        }
                    }
                }
            }

          }
          .overlayPreferenceValue(SpotlightBoundsKey.self) { anchor in
              GeometryReader { proxy in
                  if showingSpotlightTour,
                     currentSpotlightIndex < tourSpotlightIDs.count,
                     let content = spotlightContent[tourSpotlightIDs[currentSpotlightIndex]] {
                      SpotlightTourOverlay(
                          targetRect: anchor.map { proxy[$0] },
                          containerSize: proxy.size,
                          content: content,
                          currentIndex: currentSpotlightIndex,
                          total: tourSpotlightIDs.count,
                          onNext: advanceTour,
                          onSkip: skipTour
                      )
                      .animation(.easeInOut(duration: 0.25), value: currentSpotlightIndex)
                  }
              }
          }
          .toolbar {
              ToolbarItem(placement: .navigationBarLeading) {
                  Button(action: { self.showingProfileSheet = true }) {
                      Text("MFP")
                          .appFont(size: 13, weight: .bold)
                          .foregroundColor(.brandPrimary)
                          .frame(width: 44, height: 44)
                          .background(.ultraThinMaterial, in: Circle())
                          .overlay(
                              Circle()
                                  .stroke(Color.white.opacity(0.18), lineWidth: 1)
                          )
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Open profile")
              }
              ToolbarItem(placement: .navigationBarTrailing) {
                  Menu {
                      Button(action: { self.showingProfileSheet = true }) {
                          Label("Profile", systemImage: "person")
                      }
                      Divider()
                      Button(action: { self.showSettings = true }) {
                          Label("Settings", systemImage: "gearshape")
                      }
                  } label: {
                      Image(systemName: "line.3.horizontal")
                          .font(.title2)
                          .foregroundColor(Color(UIColor.secondaryLabel))
                  }
              }
          }
          // MARK: - Sheets
          .sheet(isPresented: $showingDetailedInsights) {
              NavigationStack {
                  DetailedInsightsView(insightsService: insightsService)
              }
          }
          .sheet(isPresented: $showingNutritionAudit) {
              if let currentDailyLog = currentLogForSelectedDate {
                  NavigationStack {
                      NutritionAuditView(
                          dailyLog: currentDailyLog,
                          dailyLogBinding: $dailyLogService.currentDailyLog,
                          date: selectedDate
                      )
                  }
              }
          }
          .sheet(isPresented: $showingSuggestionDetail) {
              if let suggestion = mealSuggestion {
                  MealSuggestionDetailView(
                      suggestion: suggestion,
                      pantryItemNames: pantryService.pantryItems.map(\.name),
                      remainingCalories: mealSuggestionTarget.map { Double($0.calories) } ?? remainingCaloriesToday,
                      remainingProtein: mealSuggestionTarget.map { Double($0.proteinGrams) } ?? remainingProteinToday,
                      remainingCarbs: mealSuggestionTarget.map { Double($0.carbGrams) } ?? remainingCarbsToday,
                      remainingFats: mealSuggestionTarget == nil ? remainingFatsToday : nil,
                      onLog: logMealSuggestion
                  )
              }
          }
          .sheet(isPresented: $showingCoachingDashboard) {
              CoachingDashboardView()
          }
          .sheet(isPresented: $showingWeeklyRecap) {
              WeeklyRecapView()
          }
          .sheet(isPresented: $showingSuggestionPreferences) {
              SuggestionPreferencesView(goalSettings: goalSettings)
          }
          .sheet(isPresented: $showingProfileSheet) {
              NavigationStack {
                  UserProfileView()
              }
          }
          .sheet(isPresented: $showingAddExerciseView) {
              AddExerciseView { newExercise in
                  if let userID = DIContainer.shared.authService.currentUserID {
                      self.dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: newExercise)
                  }
              }
          }
          .sheet(item: $exerciseToEdit) { exerciseToEdit in
              AddExerciseView(exerciseToEdit: exerciseToEdit) { updatedExercise in
                  if let userID = DIContainer.shared.authService.currentUserID {
                      self.dailyLogService.exerciseLogStore.deleteExerciseFromLog(for: userID, exerciseID: exerciseToEdit.id)
                      self.dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: updatedExercise)
                  }
              }
          }
          .sheet(isPresented: $showingWeightEntrySheet) {
              CurrentWeightView()
                  .environmentObject(goalSettings)
          }
          .sheet(isPresented: $showingFastingSheet) {
              NavigationStack {
                  ScrollView {
                      FastingTrackerCard()
                          .padding()
                  }
                  .background(Color.backgroundPrimary.ignoresSafeArea())
                  .navigationTitle("Fasting")
                  .navigationBarTitleDisplayMode(.inline)
                  .toolbar {
                      ToolbarItem(placement: .cancellationAction) {
                          Button("Done") { showingFastingSheet = false }
                      }
                  }
              }
          }
          .sheet(isPresented: $showingMenuScanner) {
              if isMenuScannerEnabled {
                  menuScannerSheet
              }
          }
          .sheet(isPresented: $showingRecoveryFuelSearch) {
              FoodSearchView(
                  dailyLog: $dailyLogService.currentDailyLog,
                  onFoodItemLogged: {
                      showingRecoveryFuelSearch = false
                  },
                  searchContext: "run_recovery"
              )
          }
          .sheet(isPresented: $showingTrainingFuelPlanner, onDismiss: presentPendingTrainingFuelDestination) {
              TrainingFuelPlannerSheet(
                  candidates: trainingFuelCandidates,
                  savedPlan: trainingFuelPlanStore.confirmedPlan,
                  savedProgress: trainingFuelProgress,
                  today: currentLogForSelectedDate,
                  goals: trainingFuelGoals,
                  onConfirm: confirmTrainingFuelPlan,
                  onUseTarget: useTrainingFuelTarget,
                  onUseSavedTarget: queueTrainingFuelTarget,
                  onMarkComplete: completeTrainingFuelSession,
                  onSkip: skipTrainingFuelSession,
                  onRemove: removeTrainingFuelPlan
              )
          }
          .sheet(isPresented: $showingTrainingFuelSearch) {
              FoodSearchView(
                  dailyLog: $dailyLogService.currentDailyLog,
                  onFoodItemLogged: { showingTrainingFuelSearch = false },
                  searchContext: "training_fuel",
                  trainingFuelTarget: selectedTrainingFuelTarget
              )
          }
          .sheet(isPresented: $showingTrainingFuelBuilder) {
              FoodSearchView(
                  dailyLog: $dailyLogService.currentDailyLog,
                  onFoodItemLogged: { showingTrainingFuelBuilder = false },
                  searchContext: "training_fuel_builder",
                  initialPresentation: .chainBuilder,
                  trainingFuelTarget: selectedTrainingFuelTarget
              )
          }
          .sheet(isPresented: $showingMFPImport) {
              MFPImportView()
                  .environmentObject(dailyLogService)
                  .environmentObject(goalSettings)
          }
          .onAppear(perform: onHomeViewAppear)
          .onChange(of: dailyLogService.currentDailyLog) { _, _ in
              refreshDeferredTrainingRecoveryIfNeeded()
          }
          .onChange(of: livingDayWidgetSignature) { _, _ in
              syncLivingDayWidgetPath()
          }
          .onChange(of: selectedDate) { _, _ in
              refreshLivingDayMealPlan()
          }
          .onChange(of: spotlightManager.replayToken) { _, _ in
              startSpotlightTourIfNeeded()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
              // Check if we need to advance the day when app comes to foreground
              let today = Calendar.current.startOfDay(for: Date())
              if !Calendar.current.isDate(selectedDate, inSameDayAs: today) {
                  withAnimation {
                      selectedDate = today
                  }
                  onHomeViewAppear()
              }
          }
          .onReceive(NotificationCenter.default.publisher(for: .openTrainingFuelPlanner)) { _ in
              if !isToday {
                  selectedDate = Calendar.current.startOfDay(for: Date())
                  dailyLogService.activelyViewedDate = selectedDate
                  fetchLogForSelectedDate {
                      showingTrainingFuelPlanner = true
                  }
              } else {
                  showingTrainingFuelPlanner = true
              }
          }
          // The "start workout" quick action switches to the Train tab instead of pushing
          // a second copy of the whole Train screen inside Home's navigation stack.
          .onChange(of: showingWorkoutRoutines) { _, isShowing in
              if isShowing {
                  showingWorkoutRoutines = false
                  appState.selectedTab = 2
              }
          }
          .navigationDestination(isPresented: $showingWorkoutDetail) {
              if let selectedExerciseForDetail {
                  PastWorkoutDetailView(exercise: selectedExerciseForDetail)
              }
          }
          .fullScreenCover(isPresented: $showingWeeklyCheckIn) {
              WeeklyCheckInView()
                  .environmentObject(goalSettings)
                  .environmentObject(adaptiveGoalService)
          }
          .onReceive(insightsService.$currentInsights) { insights in
              self.weeklyInsight = insights.first
          }
    }

    // MARK: - Logic

    /// The Today fuel plan reads insightsService.currentRunRecoveryPrompt, but nothing
    /// computed it — the feature could never fire. Home evaluates on appear: any run
    /// finished in the last two hours (recorded or from a watch via HealthKit) feeds the
    /// 45-minute recovery window logic.
    private func refreshRunRecoveryPrompt() {
        // Home reappears constantly (tab switches, sheet dismissals); a HealthKit query on
        // every appearance is wasteful and makes the banner flicker. Re-check at most once
        // every 5 minutes — well inside the 45-minute recovery window it feeds.
        if let last = lastRecoveryCheck, Date().timeIntervalSince(last) < 300 { return }
        lastRecoveryCheck = Date()

        let since = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        RunImportService().fetchRuns(since: since) { runs in
            insightsService.evaluateRunRecoveryPrompt(
                recentRun: runs.first,
                weightLbs: goalSettings.weight
            )
        }
    }

    private func onHomeViewAppear() {
        dailyLogService.activelyViewedDate = selectedDate
        workoutService.fetchRoutinesAndPrograms()
        trainingFuelPlanStore.load(for: DIContainer.shared.authService.currentUserID)
        fetchLogForSelectedDate()
        refreshLivingDayFeatureFlagIfNeeded()
        refreshLivingDayMealPlan()
        syncLivingDayWidgetPath()
        refreshStreakHistory()
        if isToday {
            if !ScreenshotDemoMode.isEnabled {
                healthKitViewModel.checkAuthorizationStatus()
            }
            cycleService.fetchAIInsight()
            refreshRunRecoveryPrompt()

            // Adaptive TDEE loop: proactively recompute the metabolism estimate (throttled to once
            // per day) so the weekly check-in can fire on Home without requiring a Reports visit.
            if goalSettings.calorieGoalMethod == .dynamicTDEE,
               let userID = DIContainer.shared.authService.currentUserID {
                Task {
                    await adaptiveGoalService.fetchAndCalculateIfNeeded(
                        userID: userID,
                        goalSettings: goalSettings,
                        dailyLogService: dailyLogService
                    )
                    await MainActor.run {
                        if goalSettings.isCheckInReady {
                            self.showingWeeklyCheckIn = true
                        }
                    }
                }
            }
        }

        startSpotlightTourIfNeeded()
    }

    /// Starts the Home tour for any spotlights not yet seen. Called on appear and when the
    /// user taps "Replay feature tour" in Settings (which clears the seen flags first).
    private func startSpotlightTourIfNeeded() {
        guard !ScreenshotDemoMode.isEnabled,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        let needed = spotlightOrder.filter { !spotlightManager.isShown(id: $0) }
        guard !needed.isEmpty else { return }
        self.tourSpotlightIDs = needed
        self.currentSpotlightIndex = 0
        // Mark the FIRST one as shown immediately so it doesn't repeat if they leave now.
        spotlightManager.markAsShown(id: needed[0])
        withAnimation {
            self.showingSpotlightTour = true
        }
    }

    private func isSpotlightActive(for id: String) -> Bool {
        guard showingSpotlightTour, !tourSpotlightIDs.isEmpty, currentSpotlightIndex < tourSpotlightIDs.count else {
            return false
        }
        return tourSpotlightIDs[currentSpotlightIndex] == id
    }

    private func advanceTour() {
        // Mark current as shown
        if currentSpotlightIndex < tourSpotlightIDs.count {
            spotlightManager.markAsShown(id: tourSpotlightIDs[currentSpotlightIndex])
        }

        if currentSpotlightIndex < tourSpotlightIDs.count - 1 {
            // Only mark the current step shown (above). Marking the NEXT one here meant a
            // step the user hadn't seen yet got skipped if they left the tour mid-way.
            withAnimation {
                currentSpotlightIndex += 1
            }
        } else {
            finishTour()
        }
    }

    private func skipTour() {
        tourSpotlightIDs.forEach { spotlightManager.markAsShown(id: $0) }
        finishTour()
    }

    private func finishTour() {
        withAnimation {
            showingSpotlightTour = false
        }
        if let last = tourSpotlightIDs.last {
            spotlightManager.markAsShown(id: last)
        }
        spotlightManager.markAsShown(id: "action-menu")
    }

    // MARK: - Components & Subviews

    private var dateNavigationView: some View {
        HStack(spacing: 12) {
            Button(action: {
                changeSelectedDate(by: -1)
            }) {
                Image(systemName: "chevron.left")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)
                    .background(Color.backgroundPrimary.opacity(0.82), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(selectedDateFormattedString)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                // The streak replaces the weekday line once it means something. Orange is
                // the flame's semantic color; the grace-day copy nudges without shaming.
                if isToday, streakDays >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .appFont(size: 10, weight: .bold)
                            .foregroundColor(.orange)
                        Text(streakOnGrace ? "\(streakDays)-day streak — log to keep it" : "\(streakDays)-day streak")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(streakOnGrace ? .orange : Color(UIColor.secondaryLabel))
                            .contentTransition(.numericText())
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: streakDays)
                    .accessibilityLabel(streakOnGrace
                        ? "\(streakDays) day logging streak. Log today to keep it."
                        : "\(streakDays) day logging streak")
                } else {
                    Text(selectedDateSubtitle)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            Spacer()

            Button(action: {
                changeSelectedDate(by: 1)
            }) {
                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(isToday ? Color(UIColor.tertiaryLabel) : Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)
                    .background(Color.backgroundPrimary.opacity(isToday ? 0.36 : 0.82), in: Circle())
            }
            .disabled(isToday)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var todayHasLoggedFood: Bool {
        guard let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date) else { return false }
        return !log.meals.flatMap(\.foodItems).isEmpty
    }

    private var streakInputDays: [Date] {
        todayHasLoggedFood ? pastLoggedDays + [Date()] : pastLoggedDays
    }

    private var streakDays: Int {
        LoggingStreak.currentStreak(loggedDays: streakInputDays)
    }

    private var streakOnGrace: Bool {
        LoggingStreak.isOnGraceDay(loggedDays: streakInputDays)
    }

    private var shouldOfferSwitcherPrompt: Bool {
        guard isToday,
              hasCheckedSwitcherHistory,
              !mfpSwitcherPromptDismissed else { return false }

        let foodItemsLoggedToday = currentLogForSelectedDate?.meals.flatMap(\.foodItems).count ?? 0
        return foodItemsLoggedToday == 0 && pastLoggedDays.isEmpty
    }

    private var switcherPromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Switching from MyFitnessPal?")
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Bring your diary and weight history over. Days you log here stay untouched.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: openSwitcherImport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .appFont(size: 13, weight: .bold)
                        Text("Import history")
                            .appFont(size: 14, weight: .bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: dismissSwitcherPrompt) {
                    Text("Not now")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.backgroundPrimary.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.backgroundSecondary.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.16), lineWidth: 1)
        )
        .onAppear(perform: recordSwitcherPromptSeen)
    }

    private func recordSwitcherPromptSeen() {
        guard !mfpSwitcherPromptSeen else { return }
        mfpSwitcherPromptSeen = true
        DIContainer.shared.analyticsManager?.logEvent("mfp_import_prompt_viewed", parameters: [
            "surface": "home_empty_day"
        ])
    }

    private func openSwitcherImport() {
        HapticManager.instance.feedback(.light)
        DIContainer.shared.analyticsManager?.logEvent("mfp_import_prompt_tapped", parameters: [
            "surface": "home_empty_day"
        ])
        showingMFPImport = true
    }

    private func dismissSwitcherPrompt() {
        HapticManager.instance.feedback(.light)
        mfpSwitcherPromptDismissed = true
        DIContainer.shared.analyticsManager?.logEvent("mfp_import_prompt_dismissed", parameters: [
            "surface": "home_empty_day"
        ])
    }

    private func refreshStreakHistory() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let last = lastStreakFetchDay, Calendar.current.isDate(last, inSameDayAs: todayStart) {
            hasCheckedSwitcherHistory = true
            return
        }
        guard let userID = DIContainer.shared.authService.currentUserID else {
            hasCheckedSwitcherHistory = true
            return
        }
        lastStreakFetchDay = todayStart

        Task {
            let start = Calendar.current.date(byAdding: .day, value: -45, to: todayStart)
            if case .success(let logs) = await dailyLogService.fetchDailyHistory(for: userID, startDate: start, endDate: Date()) {
                pastLoggedDays = logs
                    .filter { !$0.meals.flatMap(\.foodItems).isEmpty && !Calendar.current.isDateInToday($0.date) }
                    .map(\.date)
            }
            hasCheckedSwitcherHistory = true
        }
    }

    private var remainingCaloriesToday: Double {
        max(0, (goalSettings.calories ?? 0) - (currentLogForSelectedDate?.totalCalories() ?? 0))
    }

    private var remainingProteinToday: Double {
        max(0, goalSettings.protein - (currentLogForSelectedDate?.totalMacros().protein ?? 0))
    }

    private var remainingCarbsToday: Double {
        max(0, goalSettings.carbs - (currentLogForSelectedDate?.totalMacros().carbs ?? 0))
    }

    private var remainingFatsToday: Double {
        max(0, goalSettings.fats - (currentLogForSelectedDate?.totalMacros().fats ?? 0))
    }

    private var trainingFuelGoals: TodayFuelPlanGoals {
        TodayFuelPlanGoals(
            calories: goalSettings.calories ?? 0,
            protein: goalSettings.protein,
            carbs: goalSettings.carbs,
            fats: goalSettings.fats
        )
    }

    private var livingDaySnapshot: LivingDaySnapshot {
        let currentUserID = DIContainer.shared.authService.currentUserID
        let plannedMeals: [PlannedMeal]
        if livingDayMealPlanUserID == currentUserID,
           let plan = livingDayMealPlan,
           Calendar.current.isDate(plan.date, inSameDayAs: selectedDate) {
            plannedMeals = plan.meals
        } else {
            plannedMeals = []
        }

        let activities = (currentLogForSelectedDate?.exercises ?? []).map {
            LivingDayActivityInput(exercise: $0)
        }

        return LivingDaySnapshotBuilder.make(
            date: selectedDate,
            dailyLog: currentLogForSelectedDate,
            goals: trainingFuelGoals,
            plannedMeals: plannedMeals,
            activities: activities,
            trainingPlan: trainingFuelPlanStore.confirmedPlan,
            freshness: .current(updatedAt: nil)
        )
    }

    private var livingDayWidgetSignature: String {
        guard isLivingDayHomeEnabled, isToday else { return "disabled" }
        let snapshot = livingDaySnapshot
        let events = snapshot.events.map { event in
            [
                event.id,
                event.kind.rawValue,
                event.state.rawValue,
                String(event.startDate.timeIntervalSinceReferenceDate),
                event.evidence.rawValue
            ].joined(separator: ":")
        }
        let budget = snapshot.budget.nutrients.map { nutrient in
            [nutrient.consumed, nutrient.planned, nutrient.target]
                .map { value in
                    value.map { String($0) } ?? "nil"
                }
                .joined(separator: ":")
        }
        return ([snapshot.nextAction.kind.rawValue] + budget + events).joined(separator: "|")
    }

    private func syncLivingDayWidgetPath() {
        guard isLivingDayHomeEnabled, isToday else {
            EcosystemSyncManager.shared.updateWidgetPath(snapshot: nil)
            return
        }
        EcosystemSyncManager.shared.updateWidgetPath(snapshot: livingDaySnapshot)
    }

    private func refreshLivingDayMealPlan() {
        guard isLivingDayHomeEnabled,
              isToday,
              let userID = DIContainer.shared.authService.currentUserID else {
            livingDayMealPlan = nil
            livingDayMealPlanUserID = nil
            return
        }

        let requestedDate = selectedDate
        livingDayMealPlan = mealPlannerService.cachedPlan(for: requestedDate, userID: userID)
        livingDayMealPlanUserID = userID

        Task { @MainActor in
            let plan = await mealPlannerService.fetchPlan(for: requestedDate, userID: userID)
            guard DIContainer.shared.authService.currentUserID == userID,
                  Calendar.current.isDate(selectedDate, inSameDayAs: requestedDate) else { return }
            livingDayMealPlan = plan
            livingDayMealPlanUserID = userID
        }
    }

    private func refreshLivingDayFeatureFlagIfNeeded() {
        guard !didRefreshLivingDayFlag,
              let featureFlagService = DIContainer.shared.featureFlagService else { return }
        didRefreshLivingDayFlag = true

        Task { @MainActor in
            await featureFlagService.refresh()
            livingDayFlagRevision += 1
            refreshLivingDayMealPlan()
        }
    }

    private func handleLivingDayEvent(
        _ event: LivingDaySnapshot.Event,
        scrollProxy: ScrollViewProxy
    ) {
        HapticManager.instance.feedback(.light)
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.livingDayEventOpened.rawValue, parameters: [
            "kind": event.kind.rawValue,
            "state": event.state.rawValue,
            "evidence": event.evidence.rawValue
        ])

        let needsTrustReview = event.evidence == .correction || event.evidence == .review
        if event.kind == .meal,
           needsTrustReview,
           currentLogForSelectedDate != nil {
            showingNutritionAudit = true
            return
        }

        switch event.destination {
        case .diary:
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProxy.scrollTo("dailyLog", anchor: .top)
            }
        case .mealPlan:
            appState.selectedTab = 3
        case .workouts:
            appState.selectedTab = 2
        case .runs:
            openLivingDayRoute("myfitplate://runs")
        case .trainingFuel:
            showingTrainingFuelPlanner = true
        case .none:
            break
        }
    }

    private func handleLivingDayAction(
        _ action: DailyNextAction,
        scrollProxy: ScrollViewProxy
    ) {
        HapticManager.instance.feedback(.light)
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.livingDayActionOpened.rawValue, parameters: [
            "kind": action.kind.rawValue
        ])

        switch action.kind {
        case .preWorkoutFuel, .recoveryMeal:
            showingTrainingFuelPlanner = true
        case .proteinCatchUp:
            openLivingDayRoute(action.deepLink)
        case .trustReview:
            if currentLogForSelectedDate != nil {
                showingNutritionAudit = true
            }
        case .steadyDay:
            if action.deepLink.contains("meal-plan") {
                appState.selectedTab = 3
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo("dailyLog", anchor: .top)
                }
            }
        }
    }

    private func openLivingDayRoute(_ deepLink: String) {
        guard let url = URL(string: deepLink) else { return }
        AppCoordinator.shared.handle(url: url, appState: appState)
    }

    private var trainingFuelCandidates: [TrainingFuelSessionCandidate] {
        var result: [TrainingFuelSessionCandidate] = []
        if let activeProgram = workoutService.activeProgram,
           let candidate = TrainingFuelSessionAdapter.activeStrengthCandidate(from: activeProgram) {
            result.append(candidate)
        }
        result.append(TrainingFuelSessionAdapter.manualCandidate(kind: .strength))

        var seenRunPlanIDs = Set<String>()
        let runPlans = RunWorkoutPlan.builtinTemplates(metric: useMetric) + runPlanStore.customPlans
        for plan in runPlans where seenRunPlanIDs.insert(plan.id).inserted {
            result.append(TrainingFuelSessionAdapter.runCandidate(from: plan))
        }
        result.append(TrainingFuelSessionAdapter.manualCandidate(kind: .run))
        return result
    }

    private var suggestedTrainingFuelSession: TrainingFuelSessionCandidate? {
        guard let activeProgram = workoutService.activeProgram else { return nil }
        return TrainingFuelSessionAdapter.activeStrengthCandidate(from: activeProgram)
    }

    private var trainingFuelProgress: TrainingFuelPlanProgress? {
        guard let plan = trainingFuelPlanStore.confirmedPlan else { return nil }
        return TrainingFuelPlanProgressRules.makeProgress(
            plan: plan,
            today: currentLogForSelectedDate,
            goals: trainingFuelGoals,
            now: Date()
        )
    }

    private func confirmTrainingFuelPlan(
        draft: TrainingFuelPlanDraft,
        plannerPlan: TrainingFuelPlannerPlan
    ) {
        guard plannerPlan.status == .ready || plannerPlan.status == .deferredRecovery else { return }
        let confirmed = TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: trainingFuelGoals,
            today: currentLogForSelectedDate,
            existingPlan: trainingFuelPlanStore.confirmedPlan
        )
        trainingFuelPlanStore.confirm(
            confirmed,
            for: DIContainer.shared.authService.currentUserID
        )
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.trainingFuelPlanSaved.rawValue, parameters: [
            "training_mode": draft.kind.rawValue,
            "phase_count": plannerPlan.allocations.count,
            "confirmation_path": "save"
        ])
        HapticManager.instance.feedback(.medium)
        showingTrainingFuelPlanner = false
    }

    private func useTrainingFuelTarget(
        draft: TrainingFuelPlanDraft,
        plannerPlan: TrainingFuelPlannerPlan,
        target: TrainingFuelTarget,
        destination: TrainingFuelDestination
    ) {
        guard plannerPlan.status == .ready else { return }
        let confirmed = TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: trainingFuelGoals,
            today: currentLogForSelectedDate,
            existingPlan: trainingFuelPlanStore.confirmedPlan
        )
        trainingFuelPlanStore.confirm(
            confirmed,
            for: DIContainer.shared.authService.currentUserID
        )
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.trainingFuelPlanSaved.rawValue, parameters: [
            "training_mode": draft.kind.rawValue,
            "phase_count": plannerPlan.allocations.count,
            "confirmation_path": "handoff"
        ])
        queueTrainingFuelTarget(target, destination: destination)
    }

    private func queueTrainingFuelTarget(
        _ target: TrainingFuelTarget,
        destination: TrainingFuelDestination
    ) {
        selectedTrainingFuelTarget = target
        pendingTrainingFuelDestination = destination
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.trainingFuelHandoffSelected.rawValue, parameters: [
            "destination": destination.rawValue,
            "phase": target.phase.rawValue
        ])
        showingTrainingFuelPlanner = false
    }

    private func presentPendingTrainingFuelDestination() {
        guard let destination = pendingTrainingFuelDestination,
              let target = selectedTrainingFuelTarget else { return }
        pendingTrainingFuelDestination = nil

        switch destination {
        case .foodSearch:
            showingTrainingFuelSearch = true
        case .fastFoodBuilder:
            showingTrainingFuelBuilder = true
        case .maiaIdea:
            generateTrainingFuelSuggestion(target: target)
        case .mealPlan:
            appState.pendingTrainingFuelTarget = target
            appState.selectedTab = 3
        }
    }

    private func generateTrainingFuelSuggestion(target: TrainingFuelTarget) {
        Task {
            let suggestion = await insightsService.generateTrainingFuelSuggestion(
                target: target,
                pantryItems: pantryService.pantryItems.map(\.name)
            )
            if let suggestion {
                mealSuggestionTarget = target
                mealSuggestion = suggestion
                showingSuggestionDetail = true
            } else {
                ToastManager.shared.showToast(
                    message: "Maia couldn't build a training fuel idea right now. Try food search instead."
                )
            }
        }
    }

    private func removeTrainingFuelPlan() {
        trainingFuelPlanStore.clear(for: DIContainer.shared.authService.currentUserID)
        selectedTrainingFuelTarget = nil
        pendingTrainingFuelDestination = nil
        HapticManager.instance.feedback(.light)
        showingTrainingFuelPlanner = false
    }

    private func completeTrainingFuelSession() {
        guard trainingFuelPlanStore.markCurrentPlanCompleted(
            today: currentLogForSelectedDate,
            goals: trainingFuelGoals,
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
        recordTrainingFuelOutcome("completed", source: "manual_confirmation")
        HapticManager.instance.notification(.success)
    }

    private func skipTrainingFuelSession() {
        guard trainingFuelPlanStore.markCurrentPlanSkipped(
            today: currentLogForSelectedDate,
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
        recordTrainingFuelOutcome("skipped", source: "manual_confirmation")
        HapticManager.instance.feedback(.light)
    }

    private func recordTrainingFuelOutcome(_ outcome: String, source: String) {
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
            parameters: ["outcome": outcome, "source": source]
        )
    }

    private func refreshDeferredTrainingRecoveryIfNeeded() {
        guard isToday,
              let today = currentLogForSelectedDate,
              let userID = DIContainer.shared.authService.currentUserID else { return }
        trainingFuelPlanStore.refreshDeferredRecovery(
            today: today,
            goals: trainingFuelGoals,
            for: userID
        )
    }

    private var todayFuelPlan: TodayFuelPlan {
        TodayFuelPlanRules.makePlan(
            today: currentLogForSelectedDate,
            goals: TodayFuelPlanGoals(
                calories: goalSettings.calories ?? 0,
                protein: goalSettings.protein,
                carbs: goalSettings.carbs,
                fats: goalSettings.fats
            ),
            runRecoveryTarget: insightsService.currentRunRecoveryPrompt,
            now: Date()
        )
    }

    private var shouldShowTodayFuelPlan: Bool {
        guard isToday, (goalSettings.calories ?? 0) > 0 else { return false }
        guard trainingFuelPlanStore.confirmedPlan == nil else { return false }
        return todayFuelPlan.kind != .steadyDay || todayHasLoggedFood
    }

    /// "Fill my macros" appears when it can actually help: viewing today, from mid-afternoon
    /// on, with at least a snack's worth of calories left. No upper bound — a lightly
    /// logged day with 1,800 remaining is exactly when a planned dinner helps most.
    private var shouldOfferFillMyMacros: Bool {
        guard isToday, goalSettings.calories != nil else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 15 && remainingCaloriesToday >= 150
    }

    private func todayFuelPlanCard(for plan: TodayFuelPlan) -> some View {
        let icon = todayFuelPlanIcon(for: plan.kind)
        let isGenerating = plan.action == .fillMacros && insightsService.isGeneratingSuggestion

        return Button(action: {
            handleTodayFuelPlan(plan)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon.name)
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(icon.color)
                        .frame(width: 40, height: 40)
                        .background(icon.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(plan.statusLabel)
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(icon.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(icon.color.opacity(0.12), in: Capsule())

                            Text("Today fuel plan")
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Text(plan.title)
                            .appFont(size: 17, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(plan.summary)
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if isGenerating {
                        ProgressView()
                    } else if plan.action != .none {
                        Image(systemName: "chevron.right")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }

                Text(plan.detail)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        todayFuelPlanMetricPill(
                            title: plan.remainingCalories >= 0 ? "Budget" : "Over",
                            value: "\(Int(abs(plan.remainingCalories).rounded()).formatted()) cal",
                            color: plan.remainingCalories >= 0 ? .brandPrimary : .orange
                        )

                        if let protein = plan.targetProteinGrams {
                            todayFuelPlanMetricPill(title: "Protein", value: "\(protein)g", color: .accentProtein)
                        }
                    }

                    if plan.targetCarbGrams != nil || plan.targetWaterOunces != nil {
                        HStack(spacing: 8) {
                            if let carbs = plan.targetCarbGrams {
                                todayFuelPlanMetricPill(title: "Carbs", value: "\(carbs)g", color: .accentCarbs)
                            }

                            if let water = plan.targetWaterOunces {
                                todayFuelPlanMetricPill(title: "Water", value: "\(water) oz", color: .accentWater)
                            }
                        }
                    }
                }

                if plan.action != .none {
                    HStack(spacing: 6) {
                        Text(plan.actionTitle)
                            .appFont(size: 13, weight: .bold)
                        Image(systemName: "arrow.right")
                            .appFont(size: 12, weight: .bold)
                    }
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.backgroundPrimary.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(icon.color.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .accessibilityHint(todayFuelPlanAccessibilityHint(for: plan))
    }

    private func todayFuelPlanMetricPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .padding(.horizontal, 8)
        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func todayFuelPlanIcon(for kind: TodayFuelPlan.Kind) -> (name: String, color: Color) {
        switch kind {
        case .runRecovery:
            return ("bolt.heart.fill", .accentSignal)
        case .workoutRecovery:
            return ("figure.strengthtraining.traditional", .brandPrimary)
        case .proteinCatchUp:
            return ("fork.knife.circle.fill", .accentProtein)
        case .planDinner:
            return ("moon.stars.fill", .accentCarbs)
        case .overTargetReview:
            return ("exclamationmark.triangle.fill", .orange)
        case .steadyDay:
            return ("checkmark.circle.fill", .accentPositive)
        }
    }

    private func todayFuelPlanAccessibilityHint(for plan: TodayFuelPlan) -> String {
        switch plan.action {
        case .openRecoverySearch:
            return "Opens food search for recovery options."
        case .fillMacros:
            return "Asks Maia to suggest a meal for your remaining targets."
        case .reviewDay:
            return "Opens today's nutrition review."
        case .none:
            return "No action needed right now."
        }
    }

    private func handleTodayFuelPlan(_ plan: TodayFuelPlan) {
        guard plan.action != .none else { return }
        HapticManager.instance.feedback(.light)
        DIContainer.shared.analyticsManager?.logEvent("today_fuel_plan_tapped", parameters: [
            "kind": plan.kind.rawValue,
            "action": plan.action.rawValue,
            "remaining_calories": Int(plan.remainingCalories.rounded()),
            "target_protein": plan.targetProteinGrams ?? 0,
            "target_carbs": plan.targetCarbGrams ?? 0
        ])

        switch plan.action {
        case .openRecoverySearch:
            showingRecoveryFuelSearch = true
        case .fillMacros:
            generateFillMacrosSuggestion(source: "today_fuel_plan", includeHaptic: false)
        case .reviewDay:
            if currentLogForSelectedDate != nil {
                showingNutritionAudit = true
            } else {
                ToastManager.shared.showToast(message: "Nothing to review yet.")
            }
        case .none:
            break
        }
    }

    private func generateFillMacrosSuggestion(source: String, includeHaptic: Bool = true) {
        if includeHaptic {
            HapticManager.instance.feedback(.light)
        }

        Task {
            mealSuggestionTarget = nil
            let pantryNames = pantryService.pantryItems.map(\.name)
            DIContainer.shared.analyticsManager?.logEvent("fill_my_macros_tapped", parameters: [
                "source": source,
                "remaining_calories": Int(remainingCaloriesToday),
                "pantry_count": pantryNames.count
            ])
            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames) {
                self.mealSuggestion = suggestion
                self.showingSuggestionDetail = true
            } else {
                // Never fail silently (the AI call needs a network round-trip).
                ToastManager.shared.showToast(message: "Maia couldn't build a meal right now. Check your connection and try again.")
            }
        }
    }

    private var fillMyMacrosCard: some View {
        Button(action: {
            generateFillMacrosSuggestion(source: "home_fill_macros_card")
        }) {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill my macros")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text(pantryService.pantryItems.isEmpty
                         ? "Maia plans a meal for your remaining \(Int(remainingCaloriesToday).formatted()) cal"
                         : "Maia builds a meal from your pantry for the remaining \(Int(remainingCaloriesToday).formatted()) cal")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                if insightsService.isGeneratingSuggestion {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(insightsService.isGeneratingSuggestion)
        .accessibilityHint("Maia suggests a meal that fits your remaining calories and macros.")
    }

    private var weeklyRecapBanner: some View {
        Button(action: {
            HapticManager.instance.feedback(.light)
            showingWeeklyRecap = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.checkmark")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training & Fuel")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Training, recovery, nutrition, and change from the last 7 days")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var weeklyCheckInBanner: some View {
        Button(action: {
            HapticManager.instance.feedback(.light)
            showingWeeklyCheckIn = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.accentPositive)
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly check-in ready")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Tap to review your new targets")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(Color.backgroundSecondary.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func logMealSuggestion(_ suggestion: MealSuggestion) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: suggestion.mealName,
            calories: Double(suggestion.calories),
            protein: suggestion.protein,
            carbs: suggestion.carbs,
            fats: suggestion.fats,
            servingSize: "1 serving (AI Suggestion)",
            servingWeight: 0,
            timestamp: Date()
        )

        let logSource = mealSuggestionTarget == nil ? "ai_suggestion" : "training_fuel_ai_suggestion"
        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: foodItem, source: logSource)

        withAnimation {
            self.mealSuggestion = nil
            self.mealSuggestionTarget = nil
        }
    }

    private func fetchLogForSelectedDate(completion: @escaping () -> Void = {}) {
            guard let userID = DIContainer.shared.authService.currentUserID else {
                completion()
                return
            }

            dailyLogService.fetchLog(for: userID, date: selectedDate) { [self] _ in
                self.goalSettings.recalculateAllGoals()
                self.refreshDeferredTrainingRecoveryIfNeeded()
                if self.isToday {
                    self.insightsService.generateDailySmartInsight()
                }
                completion()
            }
        }

    private func changeSelectedDate(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        dailyLogService.activelyViewedDate = selectedDate
        fetchLogForSelectedDate()
    }

    private func deleteFood(byID foodItemID: String) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItemID)
    }

    private func repeatYesterdayMeals() {
        guard let userID = DIContainer.shared.authService.currentUserID,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else {
            return
        }

        dailyLogService.repeatFoods(from: yesterday, to: selectedDate, for: userID)
        HapticManager.instance.feedback(.medium)
    }

    private func deleteExercise(byID exerciseID: String) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.exerciseLogStore.deleteExerciseFromLog(for: userID, exerciseID: exerciseID)
    }

    // MARK: - Menu Scanner View Wrapper
    private var menuScannerSheet: some View {
        MenuScannerView()
            .environmentObject(dailyLogService)
            .environmentObject(goalSettings)
    }
}

// MARK: - Helper Components
