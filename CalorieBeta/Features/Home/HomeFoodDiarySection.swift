import SwiftUI

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
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)

                            Spacer()

                            Text("\(itemCount.formatted()) \(itemCount == 1 ? "item" : "items") • \(Int(mealCalories.rounded()).formatted()) cal")
                                .appFont(size: 12, weight: .medium)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(meal.foodItems.enumerated()), id: \.element.id) { index, foodItem in
                                SwipeableFoodItemView(
                                    initialFoodItem: foodItem,
                                    dailyLog: $dailyLogService.currentDailyLog,
                                    onDelete: { itemID in onDeleteFood(itemID) },
                                    onLogUpdated: { },
                                    date: selectedDate
                                )

                                if index < meal.foodItems.count - 1 {
                                    Divider()
                                        .padding(.leading, 50)
                                }
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

    private var hasDailyEntries: Bool {
        guard let log = currentLogForDisplay else { return false }
        return !log.meals.flatMap(\.foodItems).isEmpty
            || !(log.exercises?.isEmpty ?? true)
            || (log.waterTracker?.totalOunces ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily log")
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Food, hydration, activity, and edits for this day.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            if !hasDailyEntries {
                EmptyDailyLogView(isToday: isToday)
            } else if let currentLogForDisplay {
                HomeDailyLogSummaryStrip(log: currentLogForDisplay)

                Divider()

                HomeFoodDiaryGroupedContent(meals: currentLogForDisplay.meals, selectedDate: selectedDate, onDeleteFood: onDeleteFood)

                let dedupedExercises = (currentLogForDisplay.exercises ?? []).dedupedAgainstHealthKit()
                if !dedupedExercises.isEmpty {
                    Divider().padding(.vertical, 8)
                    HomeActivityWidget(exercises: dedupedExercises, showingAddExerciseView: $showingAddExerciseView, selectedExerciseForDetail: $selectedExerciseForDetail, showingWorkoutDetail: $showingWorkoutDetail, onDeleteExercise: onDeleteExercise)
                }
            }
        }
        .frame(maxWidth: 520)
        .appSurface(.emphasized)
        .featureSpotlight(isActive: isDailyLogSpotlightActive)
    }
}

struct EmptyDailyLogView: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.viewfinder")
                .appFont(size: 28, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 56, height: 56)
                .background(AppPalette.brand.opacity(0.10), in: Circle())

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
    }
}
