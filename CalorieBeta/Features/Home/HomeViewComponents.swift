import SwiftUI
import FirebaseAuth


import Charts

struct HomeQuickActionsView: View {
    @Binding var showingWorkoutRoutines: Bool
    @Binding var showingCoachingDashboard: Bool
    @Binding var showingMenuScanner: Bool
    @Binding var showingWeightEntrySheet: Bool
    @Binding var showingFastingSheet: Bool
    @Binding var showSettings: Bool

    var isMenuScannerSpotlightActive: Bool
    var onRepeatYesterdayMeals: () -> Void

    var body: some View {
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
                        HapticManager.instance.feedback(.light)
                        showingWorkoutRoutines = true
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
                        HapticManager.instance.feedback(.light)
                        showingCoachingDashboard = true
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
                        HapticManager.instance.feedback(.light)
                        onRepeatYesterdayMeals()
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
                        HapticManager.instance.feedback(.light)
                        showingMenuScanner = true
                    }) {
                        QuickActionButton(
                            icon: "menucard.fill",
                            label: "Menu Scan",
                            subtitle: "Find best macros",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    .featureSpotlight(isActive: isMenuScannerSpotlightActive)

                    Button(action: {
                        HapticManager.instance.feedback(.light)
                        showingWeightEntrySheet = true
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
                        HapticManager.instance.feedback(.light)
                        showingFastingSheet = true
                    }) {
                        QuickActionButton(
                            icon: "timer",
                            label: "Fasting",
                            subtitle: "Start or track a fast",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { showSettings = true }) {
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
}


struct HomeWeightTrackingCard: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Binding var showingWeightEntrySheet: Bool

    var body: some View {
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
                            .appFont(size: 13, weight: .bold)
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
                                .appFont(size: 10, weight: .bold)
                            Text("\(String(format: "%.1f", abs(BodyUnits.weightDisplayValue(lbs: delta, metric: useMetric)))) \(BodyUnits.weightUnit(metric: useMetric)) · 7d")
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
}


struct HomeSmartSuggestionsSection: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    var selectedDate: Date

    var body: some View {
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
                            HapticManager.instance.notification(.success)
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
                                    .appFont(size: 28)

                                Text(item.name.capitalized)
                                    .appFont(size: 14, weight: .bold)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text("\(Int(item.calories)) cal")
                                    .appFont(size: 12, weight: .medium)
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
}


struct HomeDashboardHeader: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService

    var dailyLog: DailyLog
    var isToday: Bool
    var selectedDateFormattedString: String
    var weeklyInsight: UserInsight?
    var isHeaderSpotlightActive: Bool
    @Binding var showingDetailedInsights: Bool

    var body: some View {
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
        .featureSpotlight(isActive: isHeaderSpotlightActive)

}
}


struct HomeDailyLogSummaryStrip: View {
    var log: DailyLog
    var body: some View {
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
}


struct HomeActivityWidget: View {
    var exercises: [LoggedExercise]
    @Binding var showingAddExerciseView: Bool
    @Binding var selectedExerciseForDetail: LoggedExercise?
    @Binding var showingWorkoutDetail: Bool
    var onDeleteExercise: (String) -> Void

    var body: some View {
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
                        onDelete: { exerciseID in onDeleteExercise(exerciseID) },
                        onTap: { exerciseToView in
                            selectedExerciseForDetail = exerciseToView
                            showingWorkoutDetail = true
                        }
                    )
                }
            }
        }

}
}


struct HomeFoodDiaryGroupedContent: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    var meals: [Meal]
    var selectedDate: Date
    var onDeleteFood: (String) -> Void

    var body: some View {
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
                                    onDelete: { itemID in onDeleteFood(itemID) },
                                    onLogUpdated: { },
                                    date: selectedDate
                                )
                            }
                        }
                    }
                }
            }
        }

}
}


struct HomeFoodDiarySection: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.colorScheme) var colorScheme

    var currentLogForDisplay: DailyLog?
    var isToday: Bool
    var selectedDate: Date
    var isDailyLogSpotlightActive: Bool

    @Binding var showingAddExerciseView: Bool
    @Binding var selectedExerciseForDetail: LoggedExercise?
    @Binding var showingWorkoutDetail: Bool

    var onDeleteFood: (String) -> Void
    var onDeleteExercise: (String) -> Void

    var body: some View {
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

            if let currentLogForDisplay,
               currentLogForDisplay.meals.flatMap({ $0.foodItems }).isEmpty,
               currentLogForDisplay.exercises?.isEmpty ?? true {
                EmptyDailyLogView(isToday: isToday)
            } else {
                if let currentLogForDisplay {
                    HomeDailyLogSummaryStrip(log: currentLogForDisplay)
                    HomeFoodDiaryGroupedContent(meals: currentLogForDisplay.meals, selectedDate: selectedDate, onDeleteFood: onDeleteFood)
                }

                let dedupedExercises = (currentLogForDisplay?.exercises ?? []).dedupedAgainstHealthKit()
                if !dedupedExercises.isEmpty {
                    Divider().padding(.vertical, 8)
                    HomeActivityWidget(exercises: dedupedExercises, showingAddExerciseView: $showingAddExerciseView, selectedExerciseForDetail: $selectedExerciseForDetail, showingWorkoutDetail: $showingWorkoutDetail, onDeleteExercise: onDeleteExercise)
                }
            }
        }
        .frame(maxWidth: 520)
        .asCard()
        .background(colorScheme == .dark ? Color.backgroundPrimary : Color.brandPrimary.opacity(0.03))
        .cornerRadius(20)
        .featureSpotlight(isActive: isDailyLogSpotlightActive)

}
}





struct DailySnapshotStrip: View {
    let dailyLog: DailyLog
    @ObservedObject var goalSettings: GoalSettings
    let isToday: Bool
    let dateTitle: String
    let onOpenInsights: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @AppStorage("includeActiveCaloriesInGoal") var includeActiveCaloriesInGoal: Bool = false

    private var foodItems: [FoodItem] {
        dailyLog.meals.flatMap(\.foodItems)
    }

    private var exercises: [LoggedExercise] {
        dailyLog.exercises ?? []
    }

    private var calories: Double {
        dailyLog.totalCalories()
    }

    private var caloriesGoal: Double {
        let baseGoal = max(goalSettings.calories ?? 1, 1)
        if includeActiveCaloriesInGoal && isToday {
            return baseGoal + healthKitViewModel.todayActiveEnergy
        }
        return baseGoal
    }

    private var caloriesRemaining: Double {
        caloriesGoal - calories
    }

    private var protein: Double {
        dailyLog.totalMacros().protein
    }

    private var proteinGoal: Double {
        max(goalSettings.protein, 1)
    }

    private var waterIntake: Double {
        dailyLog.waterTracker?.totalOunces ?? 0
    }

    private var waterGoal: Double {
        max(goalSettings.waterGoal, 1)
    }

    private var coach: (title: String, message: String, icon: String, color: Color) {
        let calorieProgress = calories / caloriesGoal
        let proteinProgress = protein / proteinGoal
        let waterProgress = waterIntake / waterGoal

        if foodItems.isEmpty {
            return (
                "Start the day clean",
                isToday ? "Log your first meal so the rest of today has a real baseline." : "No food was logged for this day.",
                "fork.knife",
                .brandPrimary
            )
        }

        if caloriesRemaining < -150 {
            return (
                "Protect the rest of the day",
                "You are \(Int(abs(caloriesRemaining).rounded())) calories over. Keep the next choice simple and protein-forward.",
                "exclamationmark.circle.fill",
                .orange
            )
        }

        if waterProgress < 0.35 && isToday {
            return (
                "Hydration is the easy win",
                "You are at \(Int(waterIntake.rounded())) oz. One quick water log gets the day moving.",
                "drop.fill",
                .cyan
            )
        }

        if proteinProgress < 0.5 && calorieProgress > 0.25 {
            return (
                "Protein needs attention",
                "You have logged \(Int(protein.rounded()))g of \(Int(proteinGoal.rounded()))g. Build the next meal around protein.",
                "bolt.heart.fill",
                .accentProtein
            )
        }

        if exercises.isEmpty && isToday {
            return (
                "Movement slot is open",
                "No workouts are logged yet. Even a short walk keeps the daily picture more complete.",
                "figure.walk",
                .blue
            )
        }

        return (
            "You are building a useful day",
            "Food, hydration, and activity are coming together. Review insights when you want the deeper read.",
            "checkmark.seal.fill",
            .accentPositive
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: coach.icon)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(coach.color)
                    .frame(width: 36, height: 36)
                    .background(coach.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(isToday ? "Today" : dateTitle)
                            .appFont(size: 19, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(calorieStatus)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(coach.color)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(coach.color.opacity(0.10), in: Capsule())
                    }

                    Text(coach.title)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(coach.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("\(Int(protein.rounded()))g protein • \(Int(waterIntake.rounded())) oz water")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                }
            Text(coach.message)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var calorieStatus: String {
        if caloriesRemaining >= 0 {
            return "\(Int(caloriesRemaining.rounded())) cal left"
        }
        return "\(Int(abs(caloriesRemaining).rounded())) cal over"
    }
}

struct DiaryMetricPill: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text("\(value) \(subtitle)")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.backgroundSecondary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NutritionAuditLaunchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review nutrition audit")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Find foods where macros and calories disagree.")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(12)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct NutritionAuditView: View {
    let dailyLog: DailyLog
    @Binding var dailyLogBinding: DailyLog?
    let date: Date
    @Environment(\.dismiss) private var dismiss

    private var dailyStatus: NutritionCalorieConsistency.Status {
        dailyLog.calorieConsistencyStatus()
    }

    private var mismatchedFoods: [FoodItem] {
        dailyLog.foodsWithMeaningfulCalorieMacroMismatch()
            .sorted { $0.calorieConsistencyStatus.mismatchAmount > $1.calorieConsistencyStatus.mismatchAmount }
    }

    private var totalFoods: Int {
        dailyLog.meals.flatMap(\.foodItems).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nutrition Audit")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Logged calories stay official, but this shows where macro math suggests a different total.")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NutritionConsistencyNoticeCard(status: dailyStatus, style: .detail)

                HStack(spacing: 10) {
                    DiaryMetricPill(title: "Foods", value: "\(totalFoods)", subtitle: "logged", icon: "fork.knife", color: .brandPrimary)
                    DiaryMetricPill(title: "Flagged", value: "\(mismatchedFoods.count)", subtitle: "items", icon: "exclamationmark.triangle.fill", color: .orange)
                }

                if mismatchedFoods.isEmpty {
                    NutritionAuditEmptyState()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Items to review")
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.textPrimary)

                        ForEach(mismatchedFoods) { food in
                            NavigationLink {
                                FoodDetailView(
                                    initialFoodItem: food,
                                    dailyLog: $dailyLogBinding,
                                    date: date,
                                    source: "nutrition_audit",
                                    onLogUpdated: { }
                                )
                            } label: {
                                NutritionAuditFoodRow(food: food)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct NutritionAuditFoodRow: View {
    let food: FoodItem

    private var status: NutritionCalorieConsistency.Status {
        food.calorieConsistencyStatus
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: food.name))
                .appFont(size: 24)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text(food.servingSize)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)

                Text("Logged \(Int(status.loggedCalories.rounded())) cal • macros imply \(Int(status.macroDerivedCalories.rounded())) cal")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("\(Int(status.mismatchAmount.rounded()))")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.orange)
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NutritionAuditEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 28, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 54, height: 54)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            Text("No single food stands out")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("The daily gap is likely coming from smaller rounding differences across multiple foods.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct EmptyDailyLogView: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.viewfinder")
                .appFont(size: 28, weight: .semibold)
                .foregroundColor(.brandPrimary)
                .frame(width: 56, height: 56)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text(isToday ? "Ready for your first log" : "Nothing logged on this day")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.textPrimary)

            Text(isToday ? "Use the center + button to search, scan, take a photo, or describe a meal." : "Switch dates or use this as a clean slate for planning.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(Color.backgroundSecondary.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let subtitle: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .appFont(size: 17, weight: .semibold)
                    .foregroundColor(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            Text(label)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text(subtitle)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 136, height: 136, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            colorScheme == .dark ? Color.backgroundPrimary.opacity(0.76) : color.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SwipeableExerciseRowView: View {
    let exercise: LoggedExercise
    let onDelete: (String) -> Void
    let onTap: (LoggedExercise) -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete(exercise.id)
                            offset = 0
                            isSwiped = false
                        }
                    } label: {
                        Image(systemName: "trash").foregroundColor(.white).frame(width: 60, height: 40, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle()).background(Color.red).contentShape(Rectangle()).cornerRadius(8)
                }
                .padding(.vertical, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(exercise.name)
                            .appFont(size: 15, weight: .semibold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        if exercise.source == "HealthKit" {
                            Image("Apple_Health")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }

                    Text(exerciseSubtitle)
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(exercise.caloriesBurned.rounded()))")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.accentPositive)
                    Text("cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    onTap(exercise)
                } else {
                    withAnimation(.easeInOut) { offset = 0; isSwiped = false }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut) {
                            if value.translation.width < -50 {
                                offset = -70
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
        }
        .padding(.bottom, 2)
    }

    private var exerciseSubtitle: String {
        var parts: [String] = []
        if let duration = exercise.durationMinutes, duration > 0 {
            parts.append("\(duration) min")
        }
        parts.append(exercise.source == "HealthKit" ? "Apple Health" : "Manual")
        return parts.joined(separator: " • ")
    }
}

struct SwipeableFoodItemView: View {
    let initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    let onDelete: (String) -> Void
    let onLogUpdated: () -> Void
    let date: Date
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false
    @State private var showDetailView = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete(initialFoodItem.id)
                            offset = 0
                            isSwiped = false
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 58, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .cornerRadius(12)
                }
                .padding(.vertical, 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Text(FoodEmojiMapper.getEmoji(for: initialFoodItem.name))
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(initialFoodItem.name)
                        .lineLimit(1)
                        .appFont(size: 16, weight: .semibold)
                        .foregroundColor(.textPrimary)

                    Text(macroSummary)
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(initialFoodItem.calories.rounded()))")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundSecondary.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    showDetailView = true
                } else {
                    withAnimation(.easeInOut) {
                        offset = 0
                        isSwiped = false
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut) {
                            if value.translation.width < -50 {
                                offset = -70
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
        }
        .navigationDestination(isPresented: $showDetailView) {
            FoodDetailView(
                initialFoodItem: initialFoodItem,
                dailyLog: $dailyLog,
                date: date,
                source: "log_swipe",
                onLogUpdated: onLogUpdated
            )
        }
        .padding(.bottom, 1)
    }

    private var macroSummary: String {
        "P \(Int(initialFoodItem.protein.rounded()))g • C \(Int(initialFoodItem.carbs.rounded()))g • F \(Int(initialFoodItem.fats.rounded()))g"
    }
}

public struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    var duration: Double = 1.5
    var bounce: Bool = false

    public func body(content: Content) -> some View {
        content
            .modifier(
                AnimatedMask(phase: phase).animation(
                    Animation.linear(duration: duration)
                        .repeatForever(autoreverses: bounce)
                )
            )
            .onAppear { phase = 0.8 }
    }

    struct AnimatedMask: AnimatableModifier {
        var phase: CGFloat = 0

        var animatableData: CGFloat {
            get { phase }
            set { phase = newValue }
        }

        func body(content: Content) -> some View {
            content
                .mask(GradientMask(phase: phase).scaleEffect(3))
        }
    }

    struct GradientMask: View {
        let phase: CGFloat
        let centerColor = Color.black
        let edgeColor = Color.black.opacity(0.3)

        var body: some View {
            LinearGradient(gradient:
                Gradient(stops: [
                    .init(color: edgeColor, location: phase),
                    .init(color: centerColor, location: phase + 0.1),
                    .init(color: edgeColor, location: phase + 0.2)
                ]), startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

public extension View {
    @ViewBuilder func shimmering(
        active: Bool = true,
        duration: Double = 1.5,
        bounce: Bool = false
    ) -> some View {
        if active {
            modifier(Shimmer(duration: duration, bounce: bounce))
        } else {
            self
        }
    }
}
