import SwiftUI

struct HomeDashboardHeader: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService

    var dailyLog: DailyLog
    var isToday: Bool
    var selectedDateFormattedString: String
    var weeklyInsight: UserInsight?
    var isHeaderSpotlightActive: Bool
    @Binding var showingDetailedInsights: Bool
    let onReviewFoodTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // DESIGN.md: Home's hero is the calorie/macro ring. Coaching stays useful,
            // but reads as a quieter support row below the nutrition state.
            NutritionProgressView(
                dailyLog: dailyLog,
                goal: goalSettings,
                insight: weeklyInsight,
                onReviewFoodTrust: onReviewFoodTrust
            )
                .padding(.top, 4)

            DailySnapshotStrip(
                dailyLog: dailyLog,
                goalSettings: goalSettings,
                isToday: isToday,
                dateTitle: selectedDateFormattedString,
                onOpenInsights: {
                    insightsService.generateAndFetchInsights(forLastDays: 7, requestConsentIfNeeded: true)
                    showingDetailedInsights = true
                }
            )
        }
        .frame(maxWidth: 520)
        .appSurface(.emphasized)
        .featureSpotlight(isActive: isHeaderSpotlightActive)
    }
}

struct HomeDailyLogSummaryStrip: View {
    var log: DailyLog

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        let foodItems = log.meals.flatMap(\.foodItems)
        let exercises = (log.exercises ?? []).dedupedAgainstHealthKit()
        let calories = log.totalCalories()
        let exerciseCalories = exercises.reduce(0) { $0 + $1.caloriesBurned }

        LazyVGrid(columns: columns, spacing: 10) {
            DiaryMetricPill(
                title: "Food",
                value: foodItems.count.formatted(),
                subtitle: foodItems.count == 1 ? "item" : "items",
                icon: "fork.knife",
                color: Color(UIColor.secondaryLabel)
            )
            DiaryMetricPill(
                title: "Calories",
                value: Int(calories.rounded()).formatted(),
                subtitle: "cal logged",
                icon: "flame.fill",
                color: AppPalette.achievement
            )
            DiaryMetricPill(
                title: "Activity",
                value: exercises.count.formatted(),
                subtitle: exercises.count == 1 ? "session" : "sessions",
                icon: "figure.run",
                color: AppPalette.effort
            )
            DiaryMetricPill(
                title: "Burned",
                value: Int(exerciseCalories.rounded()).formatted(),
                subtitle: "cal",
                icon: "bolt.fill",
                color: .accentPositive
            )
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
                    .foregroundColor(.textPrimary)
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

struct DailySnapshotStrip: View {
    let dailyLog: DailyLog
    @ObservedObject var goalSettings: GoalSettings
    let isToday: Bool
    let dateTitle: String
    let onOpenInsights: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                AppPalette.effort
            )
        }

        if caloriesRemaining < -150 {
            return (
                "Protect the rest of the day",
                "You are \(Int(abs(caloriesRemaining).rounded()).formatted()) calories over. Keep the next choice simple and protein-forward.",
                "exclamationmark.circle.fill",
                AppPalette.caution
            )
        }

        if waterProgress < 0.35 && isToday {
            return (
                "Hydration is the easy win",
                "You are at \(Int(waterIntake.rounded()).formatted()) oz. One quick water log gets the day moving.",
                "drop.fill",
                AppPalette.recovery
            )
        }

        if proteinProgress < 0.5 && calorieProgress > 0.25 {
            return (
                "Protein needs attention",
                "You have logged \(Int(protein.rounded()).formatted())g of \(Int(proteinGoal.rounded()).formatted())g. Build the next meal around protein.",
                "bolt.heart.fill",
                .accentProtein
            )
        }

        if exercises.isEmpty && isToday {
            return (
                "Movement slot is open",
                "No workouts are logged yet. Even a short walk keeps the daily picture more complete.",
                "figure.walk",
                AppPalette.positive
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
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

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
                        .minimumScaleFactor(0.85)

                    Text("\(Int(protein.rounded()).formatted())g protein • \(Int(waterIntake.rounded()).formatted()) oz water")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .minimumScaleFactor(0.82)
                }
                .layoutPriority(dynamicTypeSize.isAccessibilitySize ? 1 : 0)
            }
            Text(coach.message)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("\(isToday ? "Today" : dateTitle). \(calorieStatus). \(coach.title). \(Int(protein.rounded()).formatted()) grams of protein, \(Int(waterIntake.rounded()).formatted()) ounces of water. \(coach.message)")
    }

    private var calorieStatus: String {
        if caloriesRemaining >= 0 {
            return "\(Int(caloriesRemaining.rounded()).formatted()) cal left"
        }
        return "\(Int(abs(caloriesRemaining).rounded()).formatted()) cal over"
    }
}

struct DiaryMetricPill: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaleReference: CGFloat = 100

    var body: some View {
        let fontScale = min(max(scaleReference / 100, 0.95), 1.35)

        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 44 : 30,
                    height: dynamicTypeSize.isAccessibilitySize ? 44 : 30
                )
                .background(color.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            (
                Text(verbatim: "\(title)\n")
                    .font(.system(size: 11 * fontScale, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                + Text(verbatim: "\(value) \(subtitle)")
                    .font(.system(size: 14 * fontScale, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("home_daily_metric_visual_\(title.lowercased())")
            .accessibilityHidden(true)
        }
        .padding(10)
        .background(Color.backgroundSecondary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("home_daily_metric_\(title.lowercased())")
        .accessibilityLabel("\(title): \(value) \(subtitle)")
    }
}
