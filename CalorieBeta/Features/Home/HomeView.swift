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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var cycleService: CycleTrackingService
    @EnvironmentObject var pantryService: PantryService
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool
    let livingDayTransition: LivingDayTransition?
    let isLivingDayHomeEnabled: Bool

    private struct DiaryRepeatReview: Identifiable { let id = UUID(); let session: DiaryTransferSession }
    @State private var diaryRepeatReview: DiaryRepeatReview?
    @State private var loadingRepeatMeal = false
    @State private var repeatMealError: String?
    @State private var diarySyncState: DailyLogSyncState = .synced
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDayOwnerID: String?
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var showingProfileSheet = false
    @State private var showingAddExerciseView = false

    @State private var showingWeightEntrySheet = false
    @State private var showingFastingSheet = false
    @State private var showingDetailedInsights = false
    @State private var showingNutritionAudit = false
    private struct NutrientDashboardRequest: Identifiable {
        let id = UUID()
        let ownerID: String
        let date: Date
        let log: DailyLog?
    }
    @State private var nutrientDashboardRequest: NutrientDashboardRequest?

    @State private var exerciseToEdit: LoggedExercise?
    @State private var showingEditExerciseView = false
    @State private var weeklyInsight: UserInsight?
    @State private var showsSupportingInsights = false

    @State private var mealSuggestionReview: MealReviewSaveSession?
    @State private var mealSuggestion: MealSuggestion?
    @State private var mealSuggestionTarget: TrainingFuelTarget?
    @State private var mealSuggestionUserID: String?
    @State private var showingSuggestionDetail = false
    @State private var showingSuggestionPreferences = false

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false
    @State private var showingCoachingDashboard: Bool = {
        #if DEBUG
        return ScreenshotDemoMode.isEnabled && ScreenshotDemoData.requestedScreen == "coaching"
        #else
        return false
        #endif
    }()

    @State private var selectedExerciseForDetail: LoggedExercise?
    @State private var showingWorkoutDetail = false
    @State private var showingWeeklyCheckIn: Bool = {
        #if DEBUG
        return ScreenshotDemoMode.isEnabled && ["weekly-checkin", "weekly-checkin-ready"].contains(ScreenshotDemoData.requestedScreen)
        #else
        return false
        #endif
    }()
    @State private var weeklyCheckInMode: WeeklyCheckInView.Mode = .checkIn
    @State private var showingSetupFoodSearch = false
    @StateObject private var firstWeekGuidance = FirstWeekGuidanceModel()
    @State private var showingMenuScanner = false
    @State private var showingWeeklyRecap = false
    @State private var showingRecoveryFuelSearch = false
    @State private var showingTrainingFuelPlanner = {
        #if DEBUG
        return ScreenshotDemoMode.isEnabled && ScreenshotDemoData.requestedScreen == "training-fuel"
        #else
        return false
        #endif
    }()
    @State private var showingTrainingFuelSearch = false
    @State private var showingTrainingFuelBuilder = false
    @State private var pendingTrainingFuelDestination: TrainingFuelDestination?
    @State private var selectedTrainingFuelTarget: TrainingFuelTarget?
    @State private var showingMFPImport = false
    @State private var livingDayMealPlan: MealPlanDay?
    @State private var livingDayMealPlanUserID: String?
    @StateObject private var runPlanStore = RunWorkoutPlanStore()
    @AppStorage("mfpSwitcherPromptDismissed") private var mfpSwitcherPromptDismissed = false
    @AppStorage("mfpSwitcherPromptSeen") private var mfpSwitcherPromptSeen = false

    // Streak inputs: past logged days fetched once per day; today joins live the moment
    // food is logged, so the flame ticks immediately.
    @State private var pastLoggedDays: [Date] = []
    @State private var pastCompleteDays: [Date] = []
    @State private var habitPreferences = LoggingHabitPreferences()
    @State private var showingLoggingHabit = false
    @State private var streakRequestID = UUID()
    @State private var lastStreakFetchDay: Date?
    @State private var streakHistoryUserID: String?
    @State private var hasCheckedSwitcherHistory = false

    private var isMenuScannerEnabled: Bool {
        DIContainer.shared.featureFlagService?.isFeatureEnabled(.menuScanner) ?? FeatureFlag.menuScanner.defaultValue
    }

    private var spotlightOrder: [String] {
        return ["dashboardHeader", "dailyLog", "quickActions"]
    }

    private let spotlightContent: [String: (title: String, text: String)] = [
        "dashboardHeader": (
            title: "Your day, at a glance",
            text: "See your food and targets together. Your day builds as you log, with room to review the details."
        ),
        "quickActions": (
            title: "One useful next step",
            text: "Log food, add water or start your next workout. Your everyday actions are close at hand."
        ),
        "menuScanner": (
            title: "Menu Matchmaker",
            text: "Out to eat? Tap Menu Scan to photograph the menu and Maia returns 5 picks — the three best fits for your remaining macros, plus the most nutritious and a lighter option."
        ),
        "dailyLog": (
            title: "Your log, your control",
            text: "Tap an entry to make a correction. Swipe to remove it. Change the date to revisit another day."
        )
    ]

    private var selectedDateFormattedString: String {
        let formatter = DateFormatter()
        formatter.calendar = selectedDiaryDay?.calendar ?? Calendar(identifier: .gregorian)
        formatter.timeZone = selectedDiaryDay?.timeZone ?? .current
        let date = selectedDiaryDay?.displayDate ?? selectedDate
        if isToday {
            formatter.dateFormat = "MMMM d"
            return "Today, \(formatter.string(from: date))"
        }
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func refreshDiarySyncState() {
        guard let userID = DIContainer.shared.authService.currentUserID else { diarySyncState = .synced; return }
        diarySyncState = DIContainer.shared.nutritionRepository.dailyLogSyncState(userID: userID)
        if diarySyncState == .synced, dailyLogService.isActiveAccount(userID), let diary = dailyLogService.currentDailyLog {
            trainingFuelPlanStore.reconcileFoodLinks(with: diary, for: userID)
        }
    }

    @ViewBuilder
    private var diarySyncNotice: some View {
        if diarySyncState != .synced {
            HStack {
                Label(diarySyncState == .failed ? "Saved on this device. Sync needs a retry." : "Saved on this device. Waiting to sync…",
                      systemImage: "icloud.and.arrow.up")
                    .appTextRole(.caption)
                Spacer()
                Button("Retry") {
                    if let userID = DIContainer.shared.authService.currentUserID {
                        DIContainer.shared.nutritionRepository.retryPendingDailyLogs(userID: userID)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .accessibilityIdentifier("diarySyncNotice")
        }
    }

    private var selectedDateSubtitle: String {
        let formatter = DateFormatter()
        formatter.calendar = selectedDiaryDay?.calendar ?? Calendar(identifier: .gregorian)
        formatter.timeZone = selectedDiaryDay?.timeZone ?? .current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: selectedDiaryDay?.displayDate ?? selectedDate)
    }

    private var selectedDiaryDay: DiaryDayContext? {
        guard let userID = DIContainer.shared.authService.currentUserID else { return nil }
        if let owner = selectedDayOwnerID, owner != userID {
            return DiaryDayContext(userID: userID, date: Calendar.current.startOfDay(for: Date()))
        }
        let active = dailyLogService.activelyViewedDayContext.flatMap { $0.isOwned(by: userID) ? $0 : nil }
        if let active, active.originalDate == selectedDate { return active }
        let timeZone = active?.timeZone ?? .current
        let captured = DiaryDayContext(userID: userID, date: selectedDate, timeZone: timeZone)
        if let captured, let log = dailyLogService.currentDailyLog,
           captured.calendar.isDate(log.date, inSameDayAs: captured.displayDate), let existingKey = log.id {
            return DiaryDayContext(userID: userID, date: selectedDate, timeZone: timeZone, dayKey: existingKey)
        }
        return captured
    }

    private var isToday: Bool {
        selectedDiaryDay?.isToday() ?? Calendar.current.isDateInToday(selectedDate)
    }

    private var currentLogForSelectedDate: DailyLog? {
        dailyLogService.currentDailyLog.flatMap { log in
            guard let day = selectedDiaryDay else { return nil }
            if let key = log.id { return key == day.dayKey ? log : nil }
            return day.calendar.isDate(log.date, inSameDayAs: day.displayDate) ? log : nil
        }
    }

    private func dashboardHeaderContent(proxy: ScrollViewProxy) -> AnyView {
        if isLivingDayHomeEnabled {
            let hydrationTarget = goalSettings.hydrationTarget(for: selectedDate, recordedGoal: currentLogForSelectedDate?.waterTracker?.goalOunces)
            return AnyView(LivingDayHomeExperience(
                snapshot: livingDaySnapshot,
                transition: isToday ? livingDayTransition : nil,
                hydration: LivingDayHydrationState(
                    consumed: currentWaterIntake,
                    target: hydrationTarget ?? 0,
                    increment: goalSettings.hydrationPreferences.preferredContainer?.ounces ?? 8,
                    canAddWater: isToday,
                    trackingOnly: hydrationTarget == nil,
                    unit: goalSettings.hydrationPreferences.unit
                ),
                showsCurrentDayActions: isToday,
                isHeaderSpotlightActive: isSpotlightActive(for: "dashboardHeader"),
                onEventSelected: { event in
                    handleLivingDayEvent(event, scrollProxy: proxy)
                },
                onActionSelected: { action in
                    handleLivingDayAction(action, scrollProxy: proxy)
                },
                onAddWater: {
                    HapticManager.instance.feedback(.medium)
                    logWaterFromHome(amount: goalSettings.hydrationPreferences.preferredContainer?.ounces ?? 8)
                }, compactPresentation: true,
                shareLog: currentLogForSelectedDate,
                shareWeightPounds: selectedDayShareWeight,
                shareOwnerID: selectedDiaryDay?.userID,
                shareCalendar: selectedDiaryDay?.calendar ?? .current
            ))
        } else {
            // Keep the previous dashboard available if Living Day is disabled.
            return AnyView(HomeDashboardHeader(
                dailyLog: currentLogForSelectedDate ?? DailyLog(date: selectedDate, meals: []),
                isToday: isToday,
                selectedDateFormattedString: selectedDateFormattedString,
                weeklyInsight: weeklyInsight,
                isHeaderSpotlightActive: isSpotlightActive(for: "dashboardHeader"),
                showingDetailedInsights: $showingDetailedInsights,
                onReviewFoodTrust: {
                    showingNutritionAudit = true
                }
            ))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            homeScreenHeader
            dateNavigationView
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.compact)

            ZStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 16) {
                            if !isToday {
                                Text("Historical log · current targets")
                                    .appFont(size: 11, weight: .medium).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("home_historical_target_scope")
                            }
                            diarySyncNotice
                            if let repeatMealError {
                                Text(repeatMealError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                                    .padding(.horizontal, AppSpacing.screenHorizontal)
                                    .accessibilityIdentifier("home_repeat_meal_error")
                            }
                            if let undoError = dailyLogService.undoErrorMessage {
                                Text(undoError).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                                    .accessibilityIdentifier("diary_undo_error")
                            }
                            if dailyLogService.isUndoingDiaryChange {
                                ProgressView("Saving Undo…").appTextRole(.secondary)
                            }
                            if dailyLogService.canUndoDiaryChange {
                                Button("Undo last diary change") {
                                    if let userID = DIContainer.shared.authService.currentUserID {
                                        dailyLogService.undoLastDiaryChange(for: userID)
                                    }
                                }
                                .appTextRole(.caption)
                                .accessibilityIdentifier("undoDiaryChange")
                            }

                            dashboardHeaderContent(proxy: proxy)
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .id("dashboardHeader")

                            if let review = mealSuggestionReview, !review.isAccepted, !review.isDiscarded {
                                Button { showingSuggestionDetail = true } label: {
                                    Label("Resume meal suggestion", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(AppActionButtonStyle(.secondary))
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .accessibilityIdentifier("home_resume_meal_suggestion")
                            }

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
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .id("dailyLog")

                            if shouldOfferSwitcherPrompt {
                                switcherPromptCard
                                    .padding(.horizontal, AppSpacing.screenHorizontal)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if shouldShowSetupChecklist {
                                setupChecklistCard
                                    .padding(.horizontal, AppSpacing.screenHorizontal)
                                    .transition(.opacity)
                            }

                            if isToday, let program = workoutService.activeProgram,
                               let routine = program.routine(forSlot: program.currentProgressIndex ?? 0) {
                                Button { appState.selectedTab = 2 } label: {
                                    HStack {
                                        Image(systemName: "figure.strengthtraining.traditional")
                                        Text("Next workout").appTextRole(.control)
                                        Spacer()
                                        Text(routine.name).appTextRole(.secondary).lineLimit(1)
                                        Image(systemName: "chevron.right")
                                    }.frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .appSurface(.quiet)
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .accessibilityIdentifier("home_next_workout")
                            }

                            Button {
                                guard let owner = DIContainer.shared.authService.currentUserID else { return }
                                nutrientDashboardRequest = NutrientDashboardRequest(ownerID: owner,
                                    date: selectedDate, log: currentLogForSelectedDate)
                            } label: {
                                HStack {
                                    Label("Nutrients & food sources", systemImage: "chart.bar.doc.horizontal")
                                    Spacer(minLength: AppSpacing.compact)
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                }
                                .appTextRole(.control).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .accessibilityIdentifier("home_nutrient_dashboard")

                            if !isToday {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Current tools & insights").appFont(size: 13, weight: .bold)
                                    Text("Health, weight and coaching below use current information.")
                                        .appFont(size: 11, weight: .medium).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .accessibilityIdentifier("home_current_support_scope")
                            }

                            if goalSettings.isCheckInReady {
                                weeklyCheckInBanner
                                    .padding(.horizontal, AppSpacing.screenHorizontal)
                            }

                            if shouldShowAdaptiveOffer && !goalSettings.isCheckInReady {
                                adaptiveTargetsOfferCard
                                    .padding(.horizontal, AppSpacing.screenHorizontal)
                                    .transition(.opacity)
                            }

                            HomeQuickActionsView(
                                showingCoachingDashboard: $showingCoachingDashboard,
                                showingMenuScanner: $showingMenuScanner,
                                showingWeightEntrySheet: $showingWeightEntrySheet,
                                showingFastingSheet: $showingFastingSheet,
                                showSettings: $showSettings,
                                isMenuScannerEnabled: isMenuScannerEnabled,
                                isMenuScannerSpotlightActive: isMenuScannerEnabled && isSpotlightActive(for: "menuScanner"),
                                waterIntake: currentWaterIntake,
                                waterGoal: goalSettings.isWaterTrackingOnly ? 0 : goalSettings.waterGoal,
                                canLogWater: isToday && !isLivingDayHomeEnabled,
                                onOpenWorkouts: { appState.selectedTab = 2 },
                                onOpenMaia: { appState.selectedTab = 1 },
                                onLogWater: { logWaterFromHome(amount: goalSettings.hydrationPreferences.preferredContainer?.ounces ?? 8) },
                                onRepeatYesterdayMeals: { repeatYesterdayMeals() },
                                showsWorkouts: !isToday || workoutService.activeProgram.flatMap { $0.routine(forSlot: $0.currentProgressIndex ?? 0) } == nil
                            )
                                .featureSpotlight(isActive: isSpotlightActive(for: "quickActions"))
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                                .id("quickActions")

                            AnyView(supportingInsights)
                                .padding(.horizontal, AppSpacing.screenHorizontal)
                        }
                        .frame(width: geometry.size.width, alignment: .top)
                        .clipped()
                        .padding(.bottom, AppSpacing.section)
                    }
                    .accessibilityIdentifier("home_scroll")
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .onAppear {
                        if let userId = DIContainer.shared.authService.currentUserID {
                            dailyLogService.loadSmartSuggestions(for: userId)
                        }
                    }
                    .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
                        firstWeekGuidance.refresh(userID: DIContainer.shared.authService.currentUserID)
                        if isLoggedIn, let userId = DIContainer.shared.authService.currentUserID {
                            dailyLogService.loadSmartSuggestions(for: userId)
                            workoutService.fetchRoutinesAndPrograms()
                            trainingFuelPlanStore.load(for: userId)
                            refreshLivingDayMealPlan()
                            refreshStreakHistory()
                        } else {
                            dailyLogService.smartSuggestions = []
                            trainingFuelPlanStore.load(for: nil)
                            livingDayMealPlan = nil
                            livingDayMealPlanUserID = nil
                            mealSuggestionReview = nil
                            mealSuggestion = nil
                            mealSuggestionTarget = nil
                            mealSuggestionUserID = nil
                            showingSuggestionDetail = false
                            pastLoggedDays = []; pastCompleteDays = []; habitPreferences = .init()
                            streakRequestID = UUID()
                            lastStreakFetchDay = nil
                            streakHistoryUserID = nil
                            hasCheckedSwitcherHistory = false
                        }
                    }
                    .onChange(of: currentSpotlightIndex) { _, newIndex in
                        if showingSpotlightTour && newIndex < tourSpotlightIDs.count {
                            let spotlightID = tourSpotlightIDs[newIndex]
                            withAnimation(reduceMotion ? nil : AppMotion.standard) {
                                proxy.scrollTo(spotlightID, anchor: spotlightID == "dashboardHeader" ? .top : .center)
                            }
                        }
                    }
                }
            }
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .overlayPreferenceValue(SpotlightBoundsKey.self) { anchor in
              if showingSpotlightTour, !spotlightManager.isPresentationPaused,
                 currentSpotlightIndex < tourSpotlightIDs.count,
                 let content = spotlightContent[tourSpotlightIDs[currentSpotlightIndex]] {
                  GeometryReader { proxy in
                      SpotlightTourOverlay(
                          targetRect: anchor.map { proxy[$0] },
                          containerSize: proxy.size,
                          content: content,
                          currentIndex: currentSpotlightIndex,
                          total: tourSpotlightIDs.count,
                          onNext: advanceTour,
                          onSkip: skipTour,
                          onBack: { withAnimation(reduceMotion ? nil : AppMotion.standard) { currentSpotlightIndex = max(0, currentSpotlightIndex - 1) } }
                      )
                      .animation(reduceMotion ? nil : AppMotion.standard, value: currentSpotlightIndex)
                  }
              }
        }
        .toolbar(.hidden, for: .navigationBar)
          // MARK: - Sheets
          .sheet(isPresented: $showingDetailedInsights) {
              NavigationStack {
                  DetailedInsightsView(insightsService: insightsService)
              }
          }
          .sheet(item: $diaryRepeatReview) { review in
              DiaryTransferReviewView(session: review.session)
          }
          .sheet(item: $nutrientDashboardRequest) { request in
              if request.ownerID == DIContainer.shared.authService.currentUserID {
                  NavigationStack {
                      DailyNutrientDashboardView(date: request.date, initialLog: request.log)
                          .toolbar {
                              ToolbarItem(placement: .cancellationAction) {
                                  Button("Done") { nutrientDashboardRequest = nil }
                              }
                          }
                  }
              } else { Text("Return to the account that opened this day.").padding() }
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
              if let review = mealSuggestionReview {
                  SavedMealSuggestionDetailView(
                      review: review, pantryItemNames: pantryService.pantryItems.map(\.name),
                      remainingCalories: remainingCaloriesToday, remainingProtein: remainingProteinToday,
                      remainingCarbs: remainingCarbsToday, remainingFats: remainingFatsToday,
                      onRegenerate: regenerateSavedMealSuggestion,
                      isRegenerating: insightsService.isGeneratingSuggestion,
                      onAccepted: clearMealSuggestion, onDiscarded: clearMealSuggestion
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
              AddExerciseView(initialDate: selectedDate) { userID, newExercise, completion in
                  dailyLogService.exerciseLogStore.addExerciseToLog(
                      for: userID, exercise: newExercise, completion: completion
                  )
              }
          }
          .sheet(item: $exerciseToEdit) { exerciseToEdit in
              AddExerciseView(exerciseToEdit: exerciseToEdit) { userID, updatedExercise, completion in
                  dailyLogService.exerciseLogStore.updateExerciseInLog(
                      for: userID, original: exerciseToEdit, updated: updatedExercise, completion: completion
                  )
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
                          .padding(.horizontal, AppSpacing.screenHorizontal)
                          .padding(.vertical, AppSpacing.group)
                  }
                  .background(Color.backgroundPrimary.ignoresSafeArea())
                  .navigationTitle("")
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
          .sheet(isPresented: $showingSetupFoodSearch) {
              FoodSearchView(
                  dailyLog: $dailyLogService.currentDailyLog,
                  onFoodItemLogged: { showingSetupFoodSearch = false },
                  searchContext: "setup_checklist"
              )
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
                  saveError: trainingFuelPlanStore.errorMessage,
                  weightHistory: goalSettings.weightHistory,
                  foodAvailability: trainingFuelFoodAvailability,
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
          .onChange(of: scenePhase) { _, phase in
              if phase == .active { refreshDiarySyncState() }
          }
          .onChange(of: dailyLogService.currentDailyLog) { _, _ in
              refreshDeferredTrainingRecoveryIfNeeded()
          }
          .onChange(of: livingDayWidgetSignature) { _, _ in
              syncLivingDayWidgetPath()
          }
          .onReceive(NotificationCenter.default.publisher(for: .dailyLogSyncStateChanged)) { _ in
              refreshDiarySyncState()
              lastStreakFetchDay = nil; refreshStreakHistory()
          }
          .onChange(of: selectedDate) { _, _ in
              refreshLivingDayMealPlan()
          }
          .onChange(of: dailyLogService.activelyViewedDayContext) { previous, day in
              guard let day, day.isOwned(by: DIContainer.shared.authService.currentUserID),
                    selectedDayOwnerID != day.userID || selectedDate != day.originalDate || previous?.dayKey != day.dayKey else { return }
              selectedDayOwnerID = day.userID
              selectedDate = day.originalDate
          }
          .onReceive(NotificationCenter.default.publisher(for: .mealPlanChanged)) { notification in
              guard notification.object as? String == DIContainer.shared.authService.currentUserID else {
                  return
              }
              refreshLivingDayMealPlan()
          }
          .onChange(of: isLivingDayHomeEnabled) { _, _ in
              refreshLivingDayMealPlan()
          }
          .onChange(of: spotlightManager.isPresentationPaused) { _, paused in
              if paused { showingSpotlightTour = false } else { startSpotlightTourIfNeeded() }
          }
          .onChange(of: spotlightManager.replayToken) { _, _ in
              startSpotlightTourIfNeeded()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
              // Notification permission may have changed in Settings while the app was away.
              firstWeekGuidance.refresh(userID: DIContainer.shared.authService.currentUserID)
              if let userID = DIContainer.shared.authService.currentUserID {
                  TransferHealthSyncQueue.shared.retryPending(userID: userID)
              }
              // An open historical day survives foregrounding, midnight and travel.
              // Today remains an explicit, persistent navigation action.
              fetchLogForSelectedDate()
          }
          .task(id: appState.pendingRunFuelReview?.id) {
              guard let request = appState.pendingRunFuelReview else { return }
              // MainApp closes the originating runner sheet. The typed request stays
              // queued across tab creation; an objectless notification cannot lose it.
              while !ReviewPromptPresentation.isScreenCalm, !Task.isCancelled {
                  try? await Task.sleep(nanoseconds: 100_000_000)
              }
              guard !Task.isCancelled else { return }
              openRunFuelReview(request)
          }
          .onReceive(NotificationCenter.default.publisher(for: .openTrainingFuelPlanner)) { _ in
              if !isToday {
                  let calendar = selectedDiaryDay?.calendar ?? Calendar(identifier: .gregorian)
                  if let userID = DIContainer.shared.authService.currentUserID,
                     let today = DiaryDayContext(userID: userID, date: calendar.startOfDay(for: Date()), timeZone: calendar.timeZone) {
                      selectDiaryDay(today) {
                          showingTrainingFuelPlanner = true
                      }
                  }
              } else {
                  showingTrainingFuelPlanner = true
              }
          }
          .navigationDestination(isPresented: $showingWorkoutDetail) {
              if let selectedExerciseForDetail {
                  PastWorkoutDetailView(exercise: selectedExerciseForDetail)
              }
          }
          .fullScreenCover(isPresented: $showingWeeklyCheckIn) {
              WeeklyCheckInView(
                  mode: weeklyCheckInMode,
                  onDeclineOffer: { firstWeekGuidance.declineAdaptiveOffer(surface: "check_in") }
              )
                  .environmentObject(goalSettings)
                  .environmentObject(adaptiveGoalService)
          }
          .onReceive(insightsService.$currentInsights) { insights in
              self.weeklyInsight = insights.first
          }
    }

    // MARK: - Logic

    private func onHomeViewAppear() {
        refreshDiarySyncState()
        mealSuggestionReview = MealReviewSaveSession.resumeMealSuggestion(
            source: "ai_suggestion", userID: DIContainer.shared.authService.currentUserID)
        firstWeekGuidance.refresh(userID: DIContainer.shared.authService.currentUserID)
        let userID = DIContainer.shared.authService.currentUserID
        if selectedDayOwnerID != userID {
            selectedDayOwnerID = userID
            selectedDate = dailyLogService.activelyViewedDayContext.flatMap { $0.isOwned(by: userID) ? $0.originalDate : nil }
                ?? Calendar.current.startOfDay(for: Date())
        }
        dailyLogService.activelyViewedDate = selectedDate
        workoutService.fetchRoutinesAndPrograms()
        trainingFuelPlanStore.load(for: DIContainer.shared.authService.currentUserID)
        fetchLogForSelectedDate()
        refreshLivingDayMealPlan()
        syncLivingDayWidgetPath()
        refreshStreakHistory()
        if isToday {
            if !ScreenshotDemoMode.isEnabled {
                healthKitViewModel.checkAuthorizationStatus()
            }
            cycleService.fetchAIInsight()

            // Adaptive TDEE loop: proactively recompute the metabolism estimate (throttled to once
            // per day) so the weekly check-in can fire on Home without requiring a Reports visit.
            if shouldRefreshAdaptiveEstimate,
               let userID = DIContainer.shared.authService.currentUserID {
                Task {
                    await adaptiveGoalService.fetchAndCalculateIfNeeded(
                        userID: userID,
                        goalSettings: goalSettings,
                        dailyLogService: dailyLogService
                    )
                    await MainActor.run {
                        guard DIContainer.shared.authService.currentUserID == userID else { return }
                        if goalSettings.isCheckInReady {
                            self.weeklyCheckInMode = .checkIn
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
        guard SpotlightPresentation.isEnabled, !spotlightManager.isPresentationPaused, !showingSpotlightTour else { return }
        let needed = spotlightOrder.filter { !spotlightManager.isShown(id: $0) }
        guard !needed.isEmpty else { return }
        self.tourSpotlightIDs = needed
        self.currentSpotlightIndex = 0
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
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
            withAnimation(reduceMotion ? nil : AppMotion.standard) {
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
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
            showingSpotlightTour = false
        }
        if let last = tourSpotlightIDs.last {
            spotlightManager.markAsShown(id: last)
        }
        spotlightManager.markAsShown(id: "action-menu")
    }

    // MARK: - Components & Subviews

    private var supportingInsights: some View {
        DisclosureGroup(isExpanded: $showsSupportingInsights) {
            VStack(spacing: AppSpacing.section) {
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
                }
                if shouldOfferFillMyMacros,
                   todayFuelPlan.action == .none,
                   trainingFuelPlanStore.confirmedPlan == nil {
                    fillMyMacrosCard
                }
                weeklyRecapBanner
                if currentLogForSelectedDate != nil {
                    HealthActivityCard()
                    HomeWeightTrackingCard(showingWeightEntrySheet: $showingWeightEntrySheet)
                }
                if shouldShowTodayFuelPlan {
                    todayFuelPlanCard(for: todayFuelPlan)
                }
                if goalSettings.isCheckInReady && shouldShowAdaptiveOffer {
                    adaptiveTargetsOfferCard
                }
            }
            .padding(.top, AppSpacing.row)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fuel, health & trends").appTextRole(.control)
                Text("Training fuel, weekly review, activity and weight")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home_supporting_insights")
        }
        .tint(AppPalette.text)
    }

    private var homeScreenHeader: some View {
        AppScreenHeader(title: "Home") {
            HStack(spacing: AppSpacing.compact) {
                Button { showingLoggingHabit = true } label: {
                    Image(systemName: "calendar.badge.checkmark")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Logging consistency")
                .accessibilityIdentifier("logging_habit_open")

                Button(action: { showingProfileSheet = true }) {
                    Image(systemName: "person.crop.circle")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Open profile")
                .accessibilityIdentifier("home_profile_button")

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Open settings")
                .accessibilityIdentifier("home_settings_button")
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.compact)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_screen_header")
    }

    @ViewBuilder
    private var dateNavigationView: some View {
        if let day = selectedDiaryDay {
            DiaryDateNavigator(day: day, subtitle: isToday && !habitPreferences.hidden && !habitPreferences.paused && streakDays >= 2
                               ? "\(streakDays)\(habitPreferences.reviewed && habitPreferences.rule == .reviewedComplete ? " reviewed" : " entry") days · recent consistency"
                               : selectedDateSubtitle, onSelect: { selectDiaryDay($0) })
            .sheet(isPresented: $showingLoggingHabit) {
                LoggingHabitView { value in
                    habitPreferences = value; lastStreakFetchDay = nil; refreshStreakHistory()
                }
            }
        }
    }

    private var selectedDayShareWeight: Double? {
        guard let owner = selectedDiaryDay?.userID, goalSettings.isActiveAccount(owner) else { return nil }
        return goalSettings.weightHistory.filter { (selectedDiaryDay?.calendar ?? .current).isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date > $1.date }.first?.weight
    }

    private var todayHasLoggedFood: Bool {
        guard let log = dailyLogService.currentDailyLog,
              let civilDate = LoggingHabitRules.civilDate(for: log), Calendar.current.isDateInToday(civilDate) else { return false }
        return !log.meals.flatMap(\.foodItems).isEmpty
    }

    private var streakInputDays: [Date] {
        if habitPreferences.reviewed && habitPreferences.rule == .reviewedComplete {
            let completeToday = dailyLogService.currentDailyLog.map { log in
                LoggingHabitRules.civilDate(for: log).map { Calendar.current.isDateInToday($0) } == true && NutritionDayEvidence.isComplete(log)
            } ?? false
            return completeToday ? pastCompleteDays + [Date()] : pastCompleteDays
        }
        return todayHasLoggedFood ? pastLoggedDays + [Date()] : pastLoggedDays
    }

    private var streakDays: Int {
        if habitPreferences.paused { return 0 }
        return habitPreferences.reviewed ? LoggingHabitRules.streak(loggedDays: streakInputDays).count
            : LoggingStreak.currentStreak(loggedDays: streakInputDays)
    }

    private var streakOnGrace: Bool {
        if habitPreferences.reviewed, let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) {
            return LoggingHabitRules.streak(loggedDays: streakInputDays).graceDates.contains(yesterday)
        }
        return LoggingStreak.isOnGraceDay(loggedDays: streakInputDays)
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
                    .foregroundColor(.brandForeground)
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
                    .foregroundColor(AppPalette.onBrand)
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

    // MARK: - First-week guidance

    /// People on adaptive targets need a fresh estimate for the weekly check-in; people on the
    /// formula need one so Home can offer adaptive targets once their data supports it.
    private var shouldRefreshAdaptiveEstimate: Bool {
        switch goalSettings.calorieGoalMethod {
        case .dynamicTDEE:
            return true
        case .mifflinWithActivity:
            return !ScreenshotDemoMode.isEnabled
                && !AppRuntime.isUITesting()
                && !firstWeekGuidance.isAdaptiveOfferSnoozed
        case .custom:
            return false
        }
    }

    private var setupChecklistState: SetupChecklistState {
        if FirstWeekGuidancePreview.isEnabled {
            return FirstWeekGuidancePreview.checklistState
        }
        return firstWeekGuidance.checklistState(
            hasLoggedFood: todayHasLoggedFood || !pastLoggedDays.isEmpty,
            healthConnected: healthKitViewModel.isAuthorized,
            healthAvailable: healthKitViewModel.isHealthDataAvailable
        )
    }

    private var shouldShowSetupChecklist: Bool {
        guard isToday else { return false }
        if FirstWeekGuidancePreview.isEnabled {
            return firstWeekGuidance.checklistDismissedAt == nil
        }
        guard !ScreenshotDemoMode.isEnabled,
              !AppRuntime.isUITesting(),
              hasCheckedSwitcherHistory else { return false }
        return firstWeekGuidance.shouldShowChecklist(setupChecklistState)
    }

    private var shouldShowAdaptiveOffer: Bool {
        guard isToday else { return false }
        if FirstWeekGuidancePreview.isEnabled {
            return firstWeekGuidance.adaptiveOfferDeclinedAt == nil
        }
        guard !ScreenshotDemoMode.isEnabled, !AppRuntime.isUITesting() else { return false }
        return firstWeekGuidance.shouldOfferAdaptiveTargets(
            goalSettings: goalSettings,
            adaptiveGoalService: adaptiveGoalService
        )
    }

    private var setupChecklistCard: some View {
        let state = setupChecklistState
        let completedCount = SetupChecklistRules.completedCount(for: state)
        return SetupChecklistCard(
            state: state,
            reminderTime: firstWeekGuidance.reminderTimeText,
            onSelect: handleSetupChecklistItem,
            onDismiss: {
                HapticManager.instance.feedback(.light)
                withAnimation(AppMotion.visibility) {
                    firstWeekGuidance.dismissChecklist(completedCount: completedCount)
                }
            }
        )
        .onAppear {
            firstWeekGuidance.recordChecklistViewed(
                completedCount: completedCount,
                itemCount: SetupChecklistRules.items(for: state).count
            )
        }
    }

    private var adaptiveTargetsOfferCard: some View {
        let isPreview = FirstWeekGuidancePreview.isEnabled
        return AdaptiveTargetsOfferCard(
            measuredBurn: isPreview ? FirstWeekGuidancePreview.measuredBurn : adaptiveGoalService.calculatedTDEE ?? 0,
            formulaEstimate: isPreview ? FirstWeekGuidancePreview.formulaEstimate : goalSettings.formulaMaintenanceCalories,
            onReview: openAdaptiveTargetsOffer,
            onDecline: {
                HapticManager.instance.feedback(.light)
                withAnimation(AppMotion.visibility) {
                    firstWeekGuidance.declineAdaptiveOffer(surface: "home_card")
                }
            }
        )
        .onAppear {
            firstWeekGuidance.recordOfferViewed(confidence: adaptiveGoalService.dataConfidence)
        }
    }

    private func handleSetupChecklistItem(_ item: SetupChecklistItem) {
        HapticManager.instance.feedback(.light)
        firstWeekGuidance.recordChecklistAction(item)
        guard !FirstWeekGuidancePreview.isEnabled else { return }
        switch item {
        case .firstMeal:
            showingSetupFoodSearch = true
        case .dailyReminder:
            firstWeekGuidance.requestDailyReminder()
        case .appleHealth:
            healthKitViewModel.requestAuthorization()
        case .firstWorkout:
            appState.selectedTab = 2
        }
    }

    private func openAdaptiveTargetsOffer() {
        HapticManager.instance.feedback(.light)
        firstWeekGuidance.recordOfferOpened()
        guard !FirstWeekGuidancePreview.isEnabled else { return }
        weeklyCheckInMode = .adaptiveOffer
        showingWeeklyCheckIn = true
    }

    private func refreshStreakHistory() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        guard let userID = DIContainer.shared.authService.currentUserID else {
            pastLoggedDays = []; pastCompleteDays = []; habitPreferences = .init()
            lastStreakFetchDay = nil
            streakHistoryUserID = nil
            hasCheckedSwitcherHistory = true
            return
        }
        if streakHistoryUserID != userID {
            pastLoggedDays = []; pastCompleteDays = []; habitPreferences = .init()
            lastStreakFetchDay = nil
            hasCheckedSwitcherHistory = false
            streakHistoryUserID = userID
        }
        if let last = lastStreakFetchDay, Calendar.current.isDate(last, inSameDayAs: todayStart) {
            hasCheckedSwitcherHistory = true
            return
        }
        lastStreakFetchDay = todayStart

        let requestID = UUID(); streakRequestID = requestID
        do { habitPreferences = try LoggingHabitStore().load(userID: userID) } catch { habitPreferences.hidden = true }
        Task {
            let start = Calendar.current.date(byAdding: .day, value: -45, to: todayStart)
            if case .success(let logs) = await dailyLogService.fetchDailyHistory(for: userID, startDate: start, endDate: Date()) {
                guard DIContainer.shared.authService.currentUserID == userID,
                      streakHistoryUserID == userID, streakRequestID == requestID else { return }
                pastCompleteDays = logs.filter { NutritionDayEvidence.isComplete($0) }.compactMap { LoggingHabitRules.civilDate(for: $0) }
                    .filter { !Calendar.current.isDateInToday($0) }
                pastLoggedDays = logs.filter { !$0.meals.flatMap(\.foodItems).isEmpty }.compactMap { LoggingHabitRules.civilDate(for: $0) }
                    .filter { !Calendar.current.isDateInToday($0) }
            }
            guard DIContainer.shared.authService.currentUserID == userID,
                  streakHistoryUserID == userID, streakRequestID == requestID else { return }
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

    private var currentWaterIntake: Double {
        currentLogForSelectedDate?.waterTracker?.totalOunces ?? 0
    }

    private func logWaterFromHome(amount: Double) {
        guard isToday,
              amount > 0,
              let userID = DIContainer.shared.authService.currentUserID else { return }

        dailyLogService.addWaterToCurrentLog(
            for: userID,
            amount: amount,
            goalOunces: goalSettings.isWaterTrackingOnly ? 0 : goalSettings.waterGoal
        )
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
            let meal = livingDayMealPlan?.meals.first { "planned:\($0.id)" == event.id }
            openMealPlan(date: selectedDate, meal: meal)
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
                openMealPlan(date: selectedDate)
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
        if let owner = DIContainer.shared.authService.currentUserID,
           let commitments = try? TrainingRunCommitmentStore().entries(userID: owner) {
            result += commitments.filter { ($0.day.date() ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
                .sorted { ($0.day.date() ?? .distantPast) < ($1.day.date() ?? .distantPast) }
                .map { TrainingFuelSessionAdapter.scheduledRunCandidate(from: $0) }
        }

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
        return trainingFuelPlanStore.progress(
            for: plan,
            today: currentLogForSelectedDate,
            goals: trainingFuelGoals,
            now: Date()
        )
    }

    private func openRunFuelReview(_ request: RunFuelReviewRequest) {
        let owner = DIContainer.shared.authService.currentUserID
        trainingFuelPlanStore.load(for: owner)
        guard appState.pendingRunFuelReview?.id == request.id, !request.day.isFuture(),
              request.isCurrent(history: trainingFuelPlanStore.history, conflictingPlanIDs: trainingFuelPlanStore.conflictingPlanIDs, currentUserID: owner) else {
            appState.clearRunFuelReview(id: request.id)
            ToastManager.shared.showToast(message: "This linked fuel plan changed. Reopen the run to review its current plan.")
            return
        }
        do {
            if let planID = request.planID { try trainingFuelPlanStore.select(planID: planID, for: request.ownerID) }
        } catch {
            appState.clearRunFuelReview(id: request.id)
            ToastManager.shared.showToast(message: error.localizedDescription)
            return
        }
        selectedDayOwnerID = request.ownerID
        selectedDate = request.day.originalDate
        dailyLogService.fetchLog(for: request.ownerID, day: request.day) { result in
            guard appState.pendingRunFuelReview?.id == request.id,
                  request.day.isOwned(by: DIContainer.shared.authService.currentUserID) else { return }
            guard case .success(let log) = result, log.id == request.day.dayKey,
                  selectedDiaryDay?.dayKey == request.day.dayKey,
                  request.isCurrent(history: trainingFuelPlanStore.history, conflictingPlanIDs: trainingFuelPlanStore.conflictingPlanIDs,
                    currentUserID: DIContainer.shared.authService.currentUserID) else {
                appState.clearRunFuelReview(id: request.id)
                ToastManager.shared.showToast(message: "The exact diary day or linked fuel plan could not be loaded. Your records are unchanged; reopen the run to retry.")
                return
            }
            appState.clearRunFuelReview(id: request.id)
            showingTrainingFuelPlanner = true
        }
    }

    private func confirmTrainingFuelPlan(
        draft: TrainingFuelPlanDraft,
        plannerPlan: TrainingFuelPlannerPlan
    ) {
        let isFuture = Calendar.current.startOfDay(for: draft.scheduledAt) > Calendar.current.startOfDay(for: Date())
        guard plannerPlan.status == .ready || plannerPlan.status == .deferredRecovery
                || plannerPlan.status == .outsideToday && isFuture else { return }
        let confirmed = TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: trainingFuelGoals,
            today: currentLogForSelectedDate,
            existingPlan: trainingFuelPlanStore.confirmedPlan
        )
        guard trainingFuelPlanStore.confirm(
            confirmed,
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
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
        guard trainingFuelPlanStore.confirm(
            confirmed,
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
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
        do {
            selectedTrainingFuelTarget = try trainingFuelPlanStore.makeTarget(planID: target.planID, phase: target.phase,
                today: currentLogForSelectedDate, goals: trainingFuelGoals)
        } catch {
            ToastManager.shared.showToast(message: error.localizedDescription)
            return
        }
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
        guard let owner = DIContainer.shared.authService.currentUserID, let context = target.context,
              let date = context.day.date(calendar: context.calendar) else { return }
        do {
            try trainingFuelPlanStore.validateTarget(target, day: date, today: currentLogForSelectedDate,
                goals: trainingFuelGoals, userID: owner)
        } catch {
            ToastManager.shared.showToast(message: error.localizedDescription)
            return
        }

        switch destination {
        case .foodSearch:
            showingTrainingFuelSearch = true
        case .fastFoodBuilder:
            showingTrainingFuelBuilder = true
        case .maiaIdea:
            generateTrainingFuelSuggestion(target: target)
        case .mealPlan:
            appState.pendingTrainingFuelTarget = target
            openMealPlan(date: date)
        }
    }

    private func openMealPlan(date: Date, meal: PlannedMeal? = nil) {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        appState.openMealPlanner(.init(userID: owner, date: date, meal: meal))
    }

    private func generateTrainingFuelSuggestion(target: TrainingFuelTarget) {
        guard let userID = DIContainer.shared.authService.currentUserID,
              let context = target.context, let date = context.day.date(calendar: context.calendar),
              let day = DiaryDayContext(userID: userID, date: date, timeZone: context.calendar.timeZone) else { return }
        if resumeMealSuggestion() { return }
        Task {
            let suggestion = await insightsService.generateTrainingFuelSuggestion(
                target: target,
                pantryItems: pantryService.pantryItems.map(\.name)
            )
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            if let suggestion {
                prepareMealSuggestion(suggestion, userID: userID, day: day, target: target)
            } else {
                ToastManager.shared.showToast(
                    message: "Maia couldn't build a training fuel idea right now. Try food search instead."
                )
            }
        }
    }

    private func removeTrainingFuelPlan() {
        guard trainingFuelPlanStore.clear(for: DIContainer.shared.authService.currentUserID) else { return }
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
            runRecoveryTarget: nil,
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
                            color: plan.remainingCalories >= 0 ? .brandPrimary : AppPalette.caution
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
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
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
            return ("exclamationmark.triangle.fill", AppPalette.caution)
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

        guard let userID = DIContainer.shared.authService.currentUserID,
              let day = selectedDiaryDay, day.isOwned(by: userID) else { return }
        if resumeMealSuggestion() { return }
        Task {
            mealSuggestionTarget = nil
            let pantryNames = pantryService.pantryItems.map(\.name)
            DIContainer.shared.analyticsManager?.logEvent("fill_my_macros_tapped", parameters: [
                "source": source,
                "remaining_calories": Int(remainingCaloriesToday),
                "pantry_count": pantryNames.count
            ])
            if let suggestion = await insightsService.generateSingleMealSuggestion(pantryItems: pantryNames, day: day) {
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                prepareMealSuggestion(suggestion, userID: userID, day: day)
            } else {
                guard DIContainer.shared.authService.currentUserID == userID else { return }
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
            weeklyCheckInMode = .checkIn
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
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func resumeMealSuggestion() -> Bool {
        guard let saved = MealReviewSaveSession.resumeMealSuggestion(
            source: "ai_suggestion", userID: DIContainer.shared.authService.currentUserID) else { return false }
        mealSuggestionReview = saved
        showingSuggestionDetail = true
        return true
    }

    private func prepareMealSuggestion(_ suggestion: MealSuggestion, userID: String,
                                       day: DiaryDayContext, target: TrainingFuelTarget? = nil) {
        guard DIContainer.shared.authService.currentUserID == userID else { return }
        mealSuggestionReview = suggestion.makeReview(userID: userID, day: day,
            source: "ai_suggestion", trainingFuelTarget: target)
        showingSuggestionDetail = true
    }

    private func trainingFuelFoodAvailability(_ target: TrainingFuelTarget) -> TrainingFuelFoodAvailability {
        guard let owner = DIContainer.shared.authService.currentUserID,
              target.context?.ownerID == nil || target.context?.ownerID == owner else { return .init() }
        let date = target.context.flatMap { $0.day.date(calendar: $0.calendar) } ?? selectedDate
        let planned = mealPlannerService.cachedPlan(for: date, userID: owner)?.meals.filter { $0.plannedFood != nil }.count ?? 0
        return TrainingFuelFoodAvailability(plannedMealCount: planned,
            recentFoodCount: currentLogForSelectedDate?.meals.flatMap(\.foodItems).count ?? 0,
            pantryItemCount: pantryService.pantryItems.filter { $0.availableQuantity > 0 && ($0.bestBefore == nil || $0.bestBefore! >= date) }.count)
    }

    private func regenerateSavedMealSuggestion() {
        guard let review = mealSuggestionReview, !review.isLocked, !insightsService.isGeneratingSuggestion,
              let owner = review.userID, owner == DIContainer.shared.authService.currentUserID,
              let current = review.checkpoint.mealSuggestion else { return }
        Task {
            let pantry = pantryService.pantryItems.map(\.name)
            let result: MealSuggestion?
            if let target = review.checkpoint.trainingFuelTarget {
                result = await insightsService.generateTrainingFuelSuggestion(target: target, pantryItems: pantry,
                    alternative: review.checkpoint.requestedAlternative)
            } else {
                result = await insightsService.generateSingleMealSuggestion(pantryItems: pantry, avoiding: [current.mealName],
                    alternative: review.checkpoint.requestedAlternative, day: review.checkpoint.draft.dayContext)
            }
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            if let result { _ = review.replaceMealSuggestion(result) } else { ToastManager.shared.showToast(message: "Another idea could not be prepared within your current targets. Your original meal is kept.") }
        }
    }

    private func clearMealSuggestion() {
        mealSuggestionReview = nil
        mealSuggestion = nil
        mealSuggestionTarget = nil
        mealSuggestionUserID = nil
        showingSuggestionDetail = false
    }

    private func fetchLogForSelectedDate(completion: @escaping () -> Void = {}) {
            guard let userID = DIContainer.shared.authService.currentUserID else {
                completion()
                return
            }
            guard let requestedDay = selectedDiaryDay, requestedDay.isOwned(by: userID) else { completion(); return }

            dailyLogService.fetchLog(for: userID, day: requestedDay) { [self] _ in
                guard DIContainer.shared.authService.currentUserID == userID,
                      selectedDiaryDay?.dayKey == requestedDay.dayKey else {
                    completion()
                    return
                }
                self.goalSettings.recalculateAllGoals()
                self.refreshDeferredTrainingRecoveryIfNeeded()
                if self.isToday {
                    self.insightsService.generateDailySmartInsight()
                }
                completion()
            }
        }

    private func selectDiaryDay(_ day: DiaryDayContext, completion: @escaping () -> Void = {}) {
        guard day.isOwned(by: DIContainer.shared.authService.currentUserID), !day.isFuture() else { return }
        HapticManager.instance.feedback(.light)
        selectedDayOwnerID = day.userID
        selectedDate = day.originalDate
        dailyLogService.fetchLog(for: day.userID, day: day) { _ in
            guard day.isOwned(by: DIContainer.shared.authService.currentUserID),
                  selectedDiaryDay?.dayKey == day.dayKey else { return }
            goalSettings.recalculateAllGoals()
            refreshLivingDayMealPlan()
            refreshDeferredTrainingRecoveryIfNeeded()
            if isToday { insightsService.generateDailySmartInsight() }
            completion()
        }
    }

    private func deleteFood(byID foodItemID: String) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItemID)
    }

    private func repeatYesterdayMeals() {
        guard !loadingRepeatMeal, diaryRepeatReview == nil,
              let userID = DIContainer.shared.authService.currentUserID,
              let destination = selectedDiaryDay, let source = destination.adding(days: -1) else { return }
        let pending = DiaryTransferSession(userID: userID)
        if pending.checkpoint != nil || pending.isUnreadable {
            diaryRepeatReview = DiaryRepeatReview(session: pending); return
        }
        loadingRepeatMeal = true; repeatMealError = nil
        dailyLogService.fetchLogInternal(for: userID, day: source) { result in
            loadingRepeatMeal = false
            guard DIContainer.shared.authService.currentUserID == userID,
                  selectedDiaryDay?.dayKey == destination.dayKey else { return }
            do {
                let log = try result.get()
                guard !log.meals.flatMap(\.foodItems).isEmpty else {
                    repeatMealError = "No foods are saved on the previous day. Choose another day using the calendar."; return
                }
                let draft = try DiaryTransferDraft(source: source, destination: destination, sourceLog: log, mode: .copy)
                diaryRepeatReview = DiaryRepeatReview(session: DiaryTransferSession(userID: userID, draft: draft))
                HapticManager.instance.feedback(.light)
            } catch { repeatMealError = "The previous day's foods could not be opened. Try again." }
        }
    }

    private func deleteExercise(byID exerciseID: String) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.exerciseLogStore.deleteExerciseFromLog(for: userID, exerciseID: exerciseID, date: selectedDate)
    }

    // MARK: - Menu Scanner View Wrapper
    private var menuScannerSheet: some View {
        MenuScannerView()
            .environmentObject(dailyLogService)
            .environmentObject(goalSettings)
    }
}

// MARK: - Helper Components
