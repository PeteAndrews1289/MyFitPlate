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
    @Environment(\.colorScheme) var colorScheme

    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

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

    // Streak inputs: past logged days fetched once per day; today joins live the moment
    // food is logged, so the flame ticks immediately.
    @State private var pastLoggedDays: [Date] = []
    @State private var lastStreakFetchDay: Date?

    private var isMenuScannerEnabled: Bool {
        DIContainer.shared.featureFlagService?.isFeatureEnabled(.menuScanner) ?? FeatureFlag.menuScanner.defaultValue
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
            title: "Quick actions",
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

                            if let target = insightsService.currentRunRecoveryPrompt, !target.isExpired {
                                runRecoveryBanner(for: target)
                                    .padding(.horizontal)
                            }

                            // DESIGN.md rule 1: the rings are Home's hero and always render —
                            // before anything is logged they show a zeroed day, which invites
                            // the first log instead of hiding the screen's whole answer.
                            HomeDashboardHeader(
                                dailyLog: currentLogForSelectedDate ?? DailyLog(date: selectedDate, meals: []),
                                isToday: isToday,
                                selectedDateFormattedString: selectedDateFormattedString,
                                weeklyInsight: weeklyInsight,
                                isHeaderSpotlightActive: isSpotlightActive(for: "dashboardHeader"),
                                showingDetailedInsights: $showingDetailedInsights
                            )
                                .padding(.horizontal)
                                .id("dashboardHeader")

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

                            if shouldOfferFillMyMacros {
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
                        } else {
                            dailyLogService.smartSuggestions = []
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

            // MARK: - Spotlight Overlay
            if showingSpotlightTour {
                Color.black.opacity(0.6).ignoresSafeArea()
                    .onTapGesture(perform: advanceTour)
                    .transition(.opacity)

                // Skip Button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: skipTour) {
                            Text("Skip Tour")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .zIndex(100)

                if currentSpotlightIndex < tourSpotlightIDs.count {
                    let currentID = tourSpotlightIDs[currentSpotlightIndex]
                    if let content = spotlightContent[currentID] {
                        SpotlightTextView(
                            content: content,
                            currentIndex: currentSpotlightIndex,
                            total: tourSpotlightIDs.count,
                            position: .bottom,
                            onNext: advanceTour
                        )
                    }
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
                  MealSuggestionDetailView(suggestion: suggestion, onLog: logMealSuggestion)
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
          .onAppear(perform: onHomeViewAppear)
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

    /// The recovery banner reads insightsService.currentRunRecoveryPrompt, but nothing
    /// computed it — the feature could never fire. Home evaluates on appear: any run
    /// finished in the last two hours (recorded or from a watch via HealthKit) feeds the
    /// 45-minute recovery window logic.
    private func refreshRunRecoveryPrompt() {
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
        fetchLogForSelectedDate()
        refreshStreakHistory()
        if isToday {
            healthKitViewModel.checkAuthorizationStatus()
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

        // Check which spotlights haven't been seen yet
        let needed = spotlightOrder.filter { !spotlightManager.isShown(id: $0) }

        if !needed.isEmpty {
            self.tourSpotlightIDs = needed
            self.currentSpotlightIndex = 0

            // Mark the FIRST one as shown immediately so it doesn't repeat if they leave now
            spotlightManager.markAsShown(id: needed[0])

            withAnimation {
                self.showingSpotlightTour = true
            }
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
            let nextID = tourSpotlightIDs[currentSpotlightIndex + 1]
            spotlightManager.markAsShown(id: nextID)

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

    private func refreshStreakHistory() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let last = lastStreakFetchDay, Calendar.current.isDate(last, inSameDayAs: todayStart) { return }
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        lastStreakFetchDay = todayStart

        Task {
            let start = Calendar.current.date(byAdding: .day, value: -45, to: todayStart)
            if case .success(let logs) = await dailyLogService.fetchDailyHistory(for: userID, startDate: start, endDate: Date()) {
                pastLoggedDays = logs
                    .filter { !$0.meals.flatMap(\.foodItems).isEmpty && !Calendar.current.isDateInToday($0.date) }
                    .map(\.date)
            }
        }
    }

    private var remainingCaloriesToday: Double {
        max(0, (goalSettings.calories ?? 0) - (currentLogForSelectedDate?.totalCalories() ?? 0))
    }

    /// "Fill my macros" appears when it can actually help: viewing today, from mid-afternoon
    /// on, with at least a snack's worth of calories left. No upper bound — a lightly
    /// logged day with 1,800 remaining is exactly when a planned dinner helps most.
    private var shouldOfferFillMyMacros: Bool {
        guard isToday, goalSettings.calories != nil else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 15 && remainingCaloriesToday >= 150
    }

    private var fillMyMacrosCard: some View {
        Button(action: {
            HapticManager.instance.feedback(.light)
            Task {
                let pantryNames = pantryService.pantryItems.map(\.name)
                DIContainer.shared.analyticsManager?.logEvent("fill_my_macros_tapped", parameters: [
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
                    Text("Your week")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Calories, workouts, and records from the last 7 days")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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

    private func runRecoveryBanner(for target: RunRecoveryTarget) -> some View {
        Button(action: {
            HapticManager.instance.feedback(.light)
            showingRecoveryFuelSearch = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.heart.fill")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.accentSignal)
                        .frame(width: 38, height: 38)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Run recovery window")
                                .appFont(size: 16, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text("• \(target.remainingMinutes) min left")
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(.accentSignal)
                                .monospacedDigit()
                        }
                        Text("Log fuel within 45 min to optimize muscle synthesis")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("\(target.targetCarbGrams)g")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.accentCarbs)
                        Text("carbs")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 4) {
                        Text("\(target.targetProteinGrams)g")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.accentProtein)
                        Text("protein")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 4) {
                        Text("\(target.rehydrateMilliLiters) mL")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.accentWater)
                        Text("water")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
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

        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: foodItem, source: "ai_suggestion")

        withAnimation {
            self.mealSuggestion = nil
        }
    }

    private func fetchLogForSelectedDate(completion: @escaping () -> Void = {}) {
            guard let userID = DIContainer.shared.authService.currentUserID else {
                completion()
                return
            }

            dailyLogService.fetchLog(for: userID, date: selectedDate) { [self] _ in
                self.goalSettings.recalculateAllGoals()
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
