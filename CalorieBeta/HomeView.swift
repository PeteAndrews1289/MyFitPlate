import SwiftUI
import FirebaseAuth
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
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @Binding var navigateToProfile: Bool
    @Binding var showSettings: Bool

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var showingProfileSheet = false
    @State private var showingAddExerciseView = false

    @State private var showingWeightEntrySheet = false
    @State private var showingFastingSheet = false
    @State private var showingDetailedInsights = false
    @State private var showingNutritionAudit = false

    @State private var exerciseToEdit: LoggedExercise? = nil
    @State private var showingEditExerciseView = false
    @State private var weeklyInsight: UserInsight?

    @State private var mealSuggestion: MealSuggestion? = nil
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

    private let spotlightOrder = ["dashboardHeader", "quickActions", "menuScanner", "dailyLog"]

    private let spotlightContent: [String: (title: String, text: String)] = [
        "dashboardHeader": (
            title: "Your Dashboard",
            text: "Your calories and macros for the day, front and center. Swipe left or right to move between the Summary, Hydration, and Micronutrient views."
        ),
        "quickActions": (
            title: "Command Center",
            text: "Your most-used tools in one tap — start a Workout, open Coaching for Maia's game plan, repeat Yesterday's meals, scan a Menu, log your Weight, or track a Fast."
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

                            if let currentDailyLog = currentLogForSelectedDate {
                                dashboardHeaderSection(for: currentDailyLog)
                                    .padding(.horizontal)
                                    .id("dashboardHeader")
                            }

                            quickActions
                                .featureSpotlight(isActive: isSpotlightActive(for: "quickActions"))
                                .padding(.horizontal)
                                .id("quickActions")

                            if currentLogForSelectedDate != nil {
                                HealthActivityCard()
                                    .padding(.horizontal)

                                weightTrackingCard
                                    .padding(.horizontal)
                            }

                            foodDiarySection
                                .padding(.horizontal)
                                .id("dailyLog")
                        }
                        .frame(width: geometry.size.width, alignment: .top)
                        .clipped()
                        .padding(.bottom, 128)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .onAppear {
                        if let userId = Auth.auth().currentUser?.uid {
                            dailyLogService.loadSmartSuggestions(for: userId)
                        }
                    }
                    .onChange(of: appState.isUserLoggedIn) { _, isLoggedIn in
                        if isLoggedIn, let userId = Auth.auth().currentUser?.uid {
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
                  if let userID = Auth.auth().currentUser?.uid {
                      self.dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: newExercise)
                  }
              }
          }
          .sheet(item: $exerciseToEdit) { exerciseToEdit in
              AddExerciseView(exerciseToEdit: exerciseToEdit) { updatedExercise in
                  if let userID = Auth.auth().currentUser?.uid {
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
              menuScannerSheet
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
          .navigationDestination(isPresented: $showingWorkoutRoutines) {
              WorkoutRoutinesView()
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

    private func onHomeViewAppear() {
        dailyLogService.activelyViewedDate = selectedDate
        fetchLogForSelectedDate()
        if isToday {
            healthKitViewModel.checkAuthorizationStatus()
            cycleService.fetchAIInsight()
            
            // Adaptive TDEE loop: proactively recompute the metabolism estimate (throttled to once
            // per day) so the weekly check-in can fire on Home without requiring a Reports visit.
            if goalSettings.calorieGoalMethod == .dynamicTDEE,
               let userID = Auth.auth().currentUser?.uid {
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.backgroundPrimary.opacity(0.82), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(selectedDateFormattedString)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text(selectedDateSubtitle)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            Button(action: {
                changeSelectedDate(by: 1)
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isToday ? Color(UIColor.tertiaryLabel) : .brandPrimary)
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

    private var weeklyCheckInBanner: some View {
        Button(action: {
            HapticFeedback.selection()
            showingWeeklyCheckIn = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly Check-In Ready")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                    Text("Tap to review your new targets")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(16)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dashboardHeaderSection(for dailyLog: DailyLog) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DailySnapshotStrip(
                dailyLog: dailyLog,
                goalSettings: goalSettings,
                isToday: isToday,
                dateTitle: selectedDateFormattedString,
                onOpenInsights: {
                    insightsService.generateAndFetchInsights(forLastDays: 7)
                    showingDetailedInsights = true
                }
            )
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 14)

            NutritionProgressView(dailyLog: dailyLog, goal: goalSettings, insight: weeklyInsight)
                .padding(.top, 10)


        }
        .frame(maxWidth: 520)
        .asCard()
        .featureSpotlight(isActive: isSpotlightActive(for: "dashboardHeader"))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Command Center")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Jump into the tools you use most.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button(action: {
                        HapticFeedback.selection()
                        self.showingWorkoutRoutines = true
                    }) {
                        QuickActionButton(
                            icon: "dumbbell.fill",
                            label: "Workouts",
                            subtitle: "Train or resume a plan",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticFeedback.selection()
                        self.showingCoachingDashboard = true
                    }) {
                        QuickActionButton(
                            icon: "brain.head.profile",
                            label: "Coaching",
                            subtitle: "Maia's Strategy",
                            color: .brandPrimary
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticFeedback.selection()
                        repeatYesterdayMeals()
                    }) {
                        QuickActionButton(
                            icon: "clock.arrow.circlepath",
                            label: "Yesterday",
                            subtitle: "Repeat meals",
                            color: .accentPositive
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticFeedback.selection()
                        self.showingMenuScanner = true
                    }) {
                        QuickActionButton(
                            icon: "menucard.fill",
                            label: "Menu Scan",
                            subtitle: "Find best macros",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    .featureSpotlight(isActive: isSpotlightActive(for: "menuScanner"))
                    
                    Button(action: {
                        HapticFeedback.selection()
                        self.showingWeightEntrySheet = true
                    }) {
                        QuickActionButton(
                            icon: "scalemass.fill",
                            label: "Log Weight",
                            subtitle: "Track body metrics",
                            color: .teal
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        HapticFeedback.selection()
                        self.showingFastingSheet = true
                    }) {
                        QuickActionButton(
                            icon: "timer",
                            label: "Fasting",
                            subtitle: "Start or track a fast",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { self.showSettings = true }) {
                        QuickActionButton(
                            icon: "gearshape.fill",
                            label: "Settings",
                            subtitle: "Manage your goals",
                            color: .gray
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 520)
    }

    private var weightTrackingCard: some View {
        let history = goalSettings.weightHistory.sorted { $0.date < $1.date }
        let current = history.last?.weight ?? goalSettings.weight
        let recent = Array(history.suffix(30))
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let prior = history.last(where: { $0.date <= weekAgo })?.weight ?? history.first?.weight
        let delta = prior.map { current - $0 }

        return Button(action: { showingWeightEntrySheet = true }) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.teal)
                        Text("Weight")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(current > 0 ? String(format: "%.1f", current) : "--")
                            .appFont(size: 26, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text("lb")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    if let delta, abs(delta) >= 0.05 {
                        let down = delta < 0
                        HStack(spacing: 3) {
                            Image(systemName: down ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(String(format: "%.1f", abs(delta))) lb · 7d")
                                .appFont(size: 11, weight: .semibold)
                        }
                        .foregroundColor(down ? .accentPositive : .orange)
                    } else {
                        Text("Tap to log today's weight")
                            .appFont(size: 11, weight: .medium)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }

                Spacer(minLength: 8)

                if recent.count >= 2 {
                    Chart {
                        ForEach(recent, id: \.id) { entry in
                            LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weight))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Color.teal)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 88, height: 42)
                }

                Text("Log")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.teal, in: Capsule())
            }
        }
        .buttonStyle(AnimatedCardButtonStyle())
        .asCard()
    }

    private var smartSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Smart Suggestions")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Log recent meals with 1 tap.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(dailyLogService.smartSuggestions) { item in
                        Button(action: {
                            HapticFeedback.success()
                            if let userId = Auth.auth().currentUser?.uid {
                                // Assume adding it to the current time context meal
                                let hour = Calendar.current.component(.hour, from: Date())
                                let mealType: String
                                if hour < 10 { mealType = "Breakfast" }
                                else if hour < 15 { mealType = "Lunch" }
                                else if hour < 21 { mealType = "Dinner" }
                                else { mealType = "Snacks" }

                                dailyLogService.addFoodToLog(for: userId, date: selectedDate, mealName: mealType, foodItem: item, source: "smart_suggestion")
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(FoodEmojiMapper.getEmoji(for: item.name))
                                    .font(.system(size: 28))

                                Text(item.name.capitalized)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text("\(Int(item.calories)) cal")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                            .padding(12)
                            .frame(width: 120, alignment: .leading)
                            .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 520)
    }

    private var foodDiarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily Log")
                        .appFont(size: 22, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Food, activity, and edits for this day.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            let currentLogForDisplay = currentLogForSelectedDate

            if let currentLogForDisplay,
               currentLogForDisplay.meals.flatMap({ $0.foodItems }).isEmpty,
               currentLogForDisplay.exercises?.isEmpty ?? true {
                EmptyDailyLogView(isToday: isToday)
            } else {
                if let currentLogForDisplay {
                    dailyLogSummaryStrip(for: currentLogForDisplay)
                    foodDiaryGroupedContent(meals: currentLogForDisplay.meals)
                }

                let dedupedExercises = (currentLogForDisplay?.exercises ?? []).dedupedAgainstHealthKit()
                if !dedupedExercises.isEmpty {
                    Divider().padding(.vertical, 8)
                    activityWidget(exercises: dedupedExercises)
                }
            }
        }
        .frame(maxWidth: 520)
        .asCard()
        .background(colorScheme == .dark ? Color.backgroundPrimary : Color.brandPrimary.opacity(0.03))
        .cornerRadius(20)
        .featureSpotlight(isActive: isSpotlightActive(for: "dailyLog"))
    }

    @ViewBuilder
    private func dailyLogSummaryStrip(for log: DailyLog) -> some View {
        let foodItems = log.meals.flatMap(\.foodItems)
        let exercises = (log.exercises ?? []).dedupedAgainstHealthKit()
        let calories = log.totalCalories()
        let exerciseCalories = exercises.reduce(0) { $0 + $1.caloriesBurned }

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            DiaryMetricPill(title: "Food", value: "\(foodItems.count)", subtitle: "items", icon: "fork.knife", color: .brandPrimary)
            DiaryMetricPill(title: "Calories", value: "\(Int(calories.rounded()))", subtitle: "logged", icon: "flame.fill", color: .orange)
            DiaryMetricPill(title: "Activity", value: "\(exercises.count)", subtitle: "sessions", icon: "figure.run", color: .blue)
            DiaryMetricPill(title: "Burned", value: "\(Int(exerciseCalories.rounded()))", subtitle: "cal", icon: "bolt.fill", color: .accentPositive)
        }
    }

    @ViewBuilder
    private func activityWidget(exercises: [LoggedExercise]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(.textPrimary)

                    Text("\(exercises.count) \(exercises.count == 1 ? "session" : "sessions") logged")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Button("Add") { showingAddExerciseView = true }
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(exercises) { exercise in
                    SwipeableExerciseRowView(
                        exercise: exercise,
                        onDelete: { exerciseID in self.deleteExercise(byID: exerciseID) },
                        onTap: { exerciseToView in
                            self.selectedExerciseForDetail = exerciseToView
                            self.showingWorkoutDetail = true
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func foodDiaryGroupedContent(meals: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(meals) { meal in
                if !meal.foodItems.isEmpty {
                    let mealCalories = meal.foodItems.reduce(0) { $0 + $1.calories }
                    let itemCount = meal.foodItems.count

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(meal.name)
                                .appFont(size: 20, weight: .semibold)
                                .foregroundColor(.textPrimary)

                            Spacer()

                            Text("\(itemCount) \(itemCount == 1 ? "item" : "items") • \(Int(mealCalories.rounded())) cal")
                                .appFont(size: 12, weight: .medium)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        VStack(spacing: 8) {
                            ForEach(meal.foodItems) { foodItem in
                                SwipeableFoodItemView(
                                    initialFoodItem: foodItem,
                                    dailyLog: $dailyLogService.currentDailyLog,
                                    onDelete: { itemID in self.deleteFood(byID: itemID) },
                                    onLogUpdated: { },
                                    date: self.selectedDate
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func logMealSuggestion(_ suggestion: MealSuggestion) {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        let foodItem = FoodItem(
            id: UUID().uuidString,
            name: suggestion.mealName,
            calories: suggestion.calories,
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
            guard let userID = Auth.auth().currentUser?.uid else {
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
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItemID)
    }

    private func repeatYesterdayMeals() {
        guard let userID = Auth.auth().currentUser?.uid,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else {
            return
        }

        dailyLogService.repeatFoods(from: yesterday, to: selectedDate, for: userID)
        HapticManager.instance.feedback(.medium)
    }

    private func deleteExercise(byID exerciseID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
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
