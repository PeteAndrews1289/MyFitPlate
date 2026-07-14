import SwiftUI

struct CalorieLogView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @State private var showingAddFoodView = false
    @State private var foodToEdit: FoodItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let log = dailyLogService.currentDailyLog {
                    CalorieLogSummaryCard(log: log)

                    ForEach(displayedMeals(from: log)) { meal in
                        CalorieLogMealSection(
                            meal: meal,
                            onEdit: { foodToEdit = $0 },
                            onDelete: deleteFood,
                            onRepeatYesterday: { repeatYesterday(for: meal) }
                        )
                    }
                } else {
                    CalorieLogEmptyState {
                        showingAddFoodView = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Calorie log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddFoodView = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFoodView) {
            NavigationStack {
                AddFoodView(
                    initialFoodItem: FoodItem(
                        id: UUID().uuidString,
                        name: "",
                        calories: 0,
                        protein: 0,
                        carbs: 0,
                        fats: 0,
                        servingSize: "",
                        servingWeight: 0
                    ),
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: dailyLogService.activelyViewedDate,
                    source: "manual_add",
                    onLogUpdated: {
                        showingAddFoodView = false
                    }
                )
            }
        }
        .sheet(item: $foodToEdit) { item in
            NavigationStack {
                AddFoodView(
                    initialFoodItem: item,
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: dailyLogService.activelyViewedDate,
                    source: "log_edit",
                    onLogUpdated: {
                        foodToEdit = nil
                    }
                )
            }
        }
    }

    private func deleteFood(_ foodItem: FoodItem) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItem.id)
        HapticManager.instance.feedback(.light)
    }

    private func displayedMeals(from log: DailyLog) -> [Meal] {
        let standardNames = ["Breakfast", "Lunch", "Dinner", "Snack"]
        var meals = standardNames.map { name -> Meal in
            if let existing = log.meals.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            } else {
                return Meal(name: name, foodItems: [])
            }
        }
        let customMeals = log.meals.filter { existing in
            !standardNames.contains(where: { $0.caseInsensitiveCompare(existing.name) == .orderedSame })
        }
        meals.append(contentsOf: customMeals)
        return meals
    }

    private func repeatYesterday(for meal: Meal) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let targetDate = dailyLogService.activelyViewedDate
        dailyLogService.repeatYesterdayMeal(for: userID, mealName: meal.name, targetDate: targetDate) { _ in
            HapticManager.instance.feedback(.light)
        }
    }
}

private struct CalorieLogSummaryCard: View {
    let log: DailyLog

    private var macros: (protein: Double, fats: Double, carbs: Double) {
        log.totalMacros()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today logged")
                        .appFont(size: 23, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("\(log.meals.flatMap(\.foodItems).count.formatted()) foods across \(log.meals.filter { !$0.foodItems.isEmpty }.count.formatted()) meals")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "fork.knife.circle.fill")
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(.blue)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CalorieLogMetric(
                    title: "Calories",
                    value: Int(log.totalCalories().rounded()).formatted(),
                    unit: "cal",
                    color: .orange
                )
                CalorieLogMetric(
                    title: "Protein",
                    value: Int(macros.protein.rounded()).formatted(),
                    unit: "g",
                    color: .accentProtein
                )
                CalorieLogMetric(
                    title: "Carbs",
                    value: Int(macros.carbs.rounded()).formatted(),
                    unit: "g",
                    color: .accentCarbs
                )
                CalorieLogMetric(
                    title: "Fat",
                    value: Int(macros.fats.rounded()).formatted(),
                    unit: "g",
                    color: .accentFats
                )
            }
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CalorieLogMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(unit)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct CalorieLogMealSection: View {
    let meal: Meal
    let onEdit: (FoodItem) -> Void
    let onDelete: (FoodItem) -> Void
    let onRepeatYesterday: () -> Void

    private var calories: Double {
        meal.foodItems.reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)

                    if !meal.foodItems.isEmpty {
                        Text("\(meal.foodItems.count.formatted()) items - \(Int(calories.rounded()).formatted()) cal")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    } else {
                        Text("No items logged")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }

                Spacer()

                Button(action: onRepeatYesterday) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Repeat Yesterday")
                            .appFont(size: 11, weight: .semibold)
                    }
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if !meal.foodItems.isEmpty {
                VStack(spacing: 9) {
                    ForEach(meal.foodItems) { foodItem in
                        CalorieLogFoodRow(
                            foodItem: foodItem,
                            onEdit: { onEdit(foodItem) },
                            onDelete: { onDelete(foodItem) }
                        )
                    }
                }
            } else {
                Text("Tap + above to add food or repeat from yesterday")
                    .appFont(size: 13, weight: .regular)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color.backgroundSecondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct CalorieLogFoodRow: View {
    let foodItem: FoodItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Text(FoodEmojiMapper.getEmoji(for: foodItem.name))
                        .appFont(size: 23)
                        .frame(width: 42, height: 42)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(foodItem.name)
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        Text(foodItem.servingSize.isEmpty ? "Serving details" : foodItem.servingSize)
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            CalorieLogMacroText(label: "P", value: foodItem.protein, color: .accentProtein)
                            CalorieLogMacroText(label: "C", value: foodItem.carbs, color: .accentCarbs)
                            CalorieLogMacroText(label: "F", value: foodItem.fats, color: .accentFats)
                        }
                    }

                    Spacer(minLength: 4)

                    Text(Int(foodItem.calories.rounded()).formatted())
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.orange)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(foodItem.name)")
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CalorieLogMacroText: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        Text("\(label) \(Int(value.rounded()).formatted()) g")
            .appFont(size: 11, weight: .bold)
            .foregroundColor(color)
    }
}

private struct CalorieLogEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle.fill")
                .appFont(size: 42, weight: .bold)
                .foregroundColor(.blue)

            VStack(spacing: 5) {
                Text("No foods logged yet")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Add a food manually or use search, camera, barcode, or Maia from the main log flow.")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Add food", action: onAdd)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 40)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
