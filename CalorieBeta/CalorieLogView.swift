import SwiftUI
import FirebaseAuth

struct CalorieLogView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @State private var showingAddFoodView = false
    @State private var foodToEdit: FoodItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let log = dailyLogService.currentDailyLog {
                    if log.meals.flatMap(\.foodItems).isEmpty {
                        CalorieLogEmptyState {
                            showingAddFoodView = true
                        }
                    } else {
                        CalorieLogSummaryCard(log: log)

                        ForEach(log.meals.filter { !$0.foodItems.isEmpty }) { meal in
                            CalorieLogMealSection(
                                meal: meal,
                                onEdit: { foodToEdit = $0 },
                                onDelete: deleteFood
                            )
                        }
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
        .navigationTitle("Calorie Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddFoodView = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        // FIXED: Updated to use the new AddFoodView initializer
        .sheet(isPresented: $showingAddFoodView) {
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
        // FIXED: Added sheet for editing existing items
        .sheet(item: $foodToEdit) { item in
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

    private func deleteFood(_ foodItem: FoodItem) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.deleteFoodFromCurrentLog(for: userID, foodItemID: foodItem.id)
        HapticManager.instance.feedback(.light)
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
                    Text("Today Logged")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("\(log.meals.flatMap(\.foodItems).count) foods across \(log.meals.filter { !$0.foodItems.isEmpty }.count) meals")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.brandPrimary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CalorieLogMetric(title: "Calories", value: "\(Int(log.totalCalories().rounded()))", unit: "cal", color: .orange)
                CalorieLogMetric(title: "Protein", value: "\(Int(macros.protein.rounded()))", unit: "g", color: .accentProtein)
                CalorieLogMetric(title: "Carbs", value: "\(Int(macros.carbs.rounded()))", unit: "g", color: .accentCarbs)
                CalorieLogMetric(title: "Fat", value: "\(Int(macros.fats.rounded()))", unit: "g", color: .accentFats)
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(unit)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
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

    private var calories: Double {
        meal.foodItems.reduce(0) { $0 + $1.calories }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("\(meal.foodItems.count) items - \(Int(calories.rounded())) cal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()
            }

            VStack(spacing: 9) {
                ForEach(meal.foodItems) { foodItem in
                    CalorieLogFoodRow(
                        foodItem: foodItem,
                        onEdit: { onEdit(foodItem) },
                        onDelete: { onDelete(foodItem) }
                    )
                }
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
                        .font(.system(size: 23))
                        .frame(width: 42, height: 42)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(foodItem.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        Text(foodItem.servingSize.isEmpty ? "Serving details" : foodItem.servingSize)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            CalorieLogMacroText(label: "P", value: foodItem.protein, color: .accentProtein)
                            CalorieLogMacroText(label: "C", value: foodItem.carbs, color: .accentCarbs)
                            CalorieLogMacroText(label: "F", value: foodItem.fats, color: .accentFats)
                        }
                    }

                    Spacer(minLength: 4)

                    Text("\(Int(foodItem.calories.rounded()))")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.orange)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
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
        Text("\(label) \(Int(value.rounded()))g")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
    }
}

private struct CalorieLogEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.brandPrimary)

            VStack(spacing: 5) {
                Text("No foods logged yet")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text("Add a food manually or use search, camera, barcode, or Maia from the main log flow.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Add Food", action: onAdd)
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 40)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
