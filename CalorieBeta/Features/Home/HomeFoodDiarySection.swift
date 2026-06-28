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
