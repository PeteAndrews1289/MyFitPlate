import SwiftUI

func dateKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Calendar.current.startOfDay(for: date))
}

struct MealPlanSummaryCard: View {
    let date: Date
    let meals: [PlannedMeal]
    let goals: GoalSettings

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metricColumns: [GridItem] {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }

    private var foodItems: [FoodItem] {
        meals.compactMap(\.foodItem)
    }

    private var totalCalories: Double {
        foodItems.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        foodItems.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Double {
        foodItems.reduce(0) { $0 + $1.carbs }
    }

    private var totalFats: Double {
        foodItems.reduce(0) { $0 + $1.fats }
    }

    private var calorieGoal: Double {
        max(goals.calories ?? 0, 1)
    }

    private var calorieDelta: Double {
        totalCalories - calorieGoal
    }

    private var calorieStatusText: String {
        let delta = Int(abs(calorieDelta).rounded())
        if calorieDelta > 75 {
            return "\(delta) cal over target"
        }
        if calorieDelta < -75 {
            return "\(delta) cal under target"
        }
        return "On target"
    }

    private var calorieStatusColor: Color {
        abs(calorieDelta) <= 75 ? .accentPositive : .orange
    }

    private var dateTitle: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dateTitle)'s meal plan")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(date, formatter: DateFormatter.longDate)
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "calendar.badge.clock")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.blue)
                    .frame(width: 38, height: 38)
                    .background(Color(UIColor.secondarySystemFill), in: Circle())
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                MealPlanMetric(title: "Meals", value: meals.count.formatted(), color: .blue)
                MealPlanMetric(title: "Calories", value: "\(Int(totalCalories.rounded()).formatted()) cal", color: .orange)
                MealPlanMetric(title: "Protein", value: "\(Int(totalProtein.rounded()).formatted()) g", color: .accentProtein)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Daily fit")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text(calorieStatusText)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(calorieStatusColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(calorieStatusColor.opacity(0.12), in: Capsule())
                }

                MealPlanProgressRow(
                    title: "Calories",
                    value: totalCalories,
                    goal: calorieGoal,
                    unit: "cal",
                    color: .orange
                )
                MealPlanProgressRow(
                    title: "Protein",
                    value: totalProtein,
                    goal: max(goals.protein, 1),
                    unit: "g",
                    color: .accentProtein
                )
                MealPlanProgressRow(
                    title: "Carbs",
                    value: totalCarbs,
                    goal: max(goals.carbs, 1),
                    unit: "g",
                    color: .accentCarbs
                )
                MealPlanProgressRow(
                    title: "Fats",
                    value: totalFats,
                    goal: max(goals.fats, 1),
                    unit: "g",
                    color: .accentFats
                )
            }
            .padding(12)
            .background(Color.backgroundPrimary.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .asCard()
    }
}

struct MealPlanProgressRow: View {
    let title: String
    let value: Double
    let goal: Double
    let unit: String
    let color: Color

    private var progress: CGFloat {
        CGFloat(min(value / max(goal, 1), 1.0))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Spacer()

                Text("\(Int(value.rounded()).formatted()) / \(Int(goal.rounded()).formatted()) \(unit)")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 7)
        }
    }
}

struct MealPlanMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(title)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.backgroundPrimary.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WeeklyPlanOverviewCard: View {
    let plans: [MealPlanDay]
    let onOpenGrocery: () -> Void
    let onStartMealPrep: () -> Void

    private var plannedDays: Int {
        plans.filter { !$0.meals.isEmpty }.count
    }

    private var mealCount: Int {
        plans.reduce(0) { $0 + $1.meals.count }
    }

    private var averageCalories: Double {
        let dailyCalories = plans
            .map { day in day.meals.compactMap(\.foodItem).reduce(0) { $0 + $1.calories } }
            .filter { $0 > 0 }

        guard !dailyCalories.isEmpty else { return 0 }
        return dailyCalories.reduce(0, +) / Double(dailyCalories.count)
    }

    private var progress: CGFloat {
        CGFloat(Double(plannedDays) / 7.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week at a glance")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(plannedDays == 0 ? "No meals planned yet." : "\(plannedDays) planned \(plannedDays == 1 ? "day" : "days").")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Button(action: onOpenGrocery) {
                    Image(systemName: "list.bullet.clipboard")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 38, height: 38)
                        .background(Color(UIColor.secondarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open grocery list")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(plannedDays >= 7 ? Color.accentPositive : Color.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                MealPlanMetric(title: "Days", value: plannedDays == 1 ? "1 day" : "\(plannedDays) days", color: .blue)
                MealPlanMetric(title: "Meals", value: mealCount.formatted(), color: .purple)
                MealPlanMetric(
                    title: "Avg calories",
                    value: averageCalories > 0 ? "\(Int(averageCalories.rounded()).formatted()) cal/day" : "--",
                    color: .orange
                )
            }

            if plannedDays > 0 {
                Button(action: onStartMealPrep) {
                    Label("Start meal prep", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .tint(.orange)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MealPlanLoadingState: View {
    var message: String = "Loading meal plan"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 42, height: 42)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 14)
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 140, height: 20)

                    Text(message)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 48)
                }
            }
        }
        .asCard()
    }
}

struct MealPlannerEmptyState: View {
    let onGenerate: () -> Void
    let onAddRecipe: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .appFont(size: 32, weight: .semibold)
                .foregroundColor(.orange)
                .frame(width: 68, height: 68)
                .background(Color(UIColor.secondarySystemFill), in: Circle())

            VStack(spacing: 5) {
                Text("No plan for this day yet")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Generate a weekly plan from your goals and preferences, or place a saved recipe into this day manually.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button("Generate meal plan", action: onGenerate)
                    .buttonStyle(PrimaryButtonStyle())

                Button("Add saved recipe", action: onAddRecipe)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .asCard()
    }
}

struct MealCardView: View {
    let meal: PlannedMeal
    var isRegenerating: Bool
    var isLogged: Bool
    var onLog: (PlannedMeal) -> Void
    var onRegenerate: () -> Void
    var onDelete: () -> Void

    private var displayName: String {
        meal.foodItem?.name ?? "Unnamed meal"
    }

    private var sourceLabel: String {
        meal.recipeID == nil ? "AI plan" : "Recipe"
    }

    private var sourceColor: Color {
        meal.recipeID == nil ? .orange : .blue
    }

    private var mealIcon: String {
        switch meal.mealType.lowercased() {
        case let value where value.contains("breakfast"):
            return "sunrise.fill"
        case let value where value.contains("lunch"):
            return "sun.max.fill"
        case let value where value.contains("dinner"):
            return "moon.stars.fill"
        case let value where value.contains("snack"):
            return "leaf.fill"
        default:
            return "fork.knife"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mealIcon)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(meal.mealType)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .textCase(.uppercase)

                        Text(sourceLabel)
                            .appFont(size: 10, weight: .bold)
                            .foregroundColor(sourceColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(sourceColor.opacity(0.12), in: Capsule())
                    }

                    Text(displayName)
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(displayName) from meal plan")
            }

            if let foodItem = meal.foodItem {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    nutrientPill(label: "Cal", valueText: "\(Int(foodItem.calories.rounded()).formatted()) cal", color: .orange)
                    nutrientPill(label: "Protein", valueText: "\(Int(foodItem.protein.rounded()).formatted()) g", color: .accentProtein)
                    nutrientPill(label: "Carbs", valueText: "\(Int(foodItem.carbs.rounded()).formatted()) g", color: .accentCarbs)
                    nutrientPill(label: "Fats", valueText: "\(Int(foodItem.fats.rounded()).formatted()) g", color: .accentFats)
                }
            }

            if let ingredients = meal.ingredients, let instructions = meal.instructions, !ingredients.isEmpty, !instructions.isEmpty {
                DisclosureGroup("View recipe") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ingredients")
                            .appFont(size: 15, weight: .semibold)
                        ForEach(ingredients, id: \.self) { ingredient in
                            Text("- \(ingredient)").appFont(size: 14)
                        }

                        Text("Instructions")
                            .appFont(size: 15, weight: .semibold)
                            .padding(.top, 5)
                        Text(instructions).appFont(size: 14)
                    }
                    .padding(.top, 8)
                }
                .tint(.blue)
            }

            HStack(spacing: 10) {
                Button(action: { onLog(meal) }) {
                    Label(isLogged ? "Logged" : "Log meal", systemImage: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(isLogged ? .accentPositive : .brandPrimary)
                .disabled(isLogged)

                Button(action: onRegenerate) {
                    if isRegenerating {
                        ProgressView()
                            .tint(Color(UIColor.secondaryLabel))
                    } else {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color(UIColor.secondaryLabel))
                .disabled(isRegenerating)
            }
            .padding(.top, 5)

        }
        .asCard()
    }

    @ViewBuilder
    private func nutrientPill(label: String, valueText: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .appFont(size: 10, weight: .bold)
                .foregroundColor(color)
            Text(valueText)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WeekView: View {
    @Binding var selectedDate: Date
    let mealCountsByDay: [String: Int]
    @Namespace private var animationNamespace
    let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }

        HStack(spacing: 8) {
            ForEach(dates, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let mealCount = mealCountsByDay[dateKey(for: date)] ?? 0

                VStack(spacing: 7) {
                    Text(dayOfWeek(for: date))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(isSelected ? .blue : Color(UIColor.secondaryLabel))

                    Text(dayOfMonth(for: date))
                        .appFont(size: 17, weight: .bold)
                        .frame(width: 34, height: 34)
                        .background(
                            Group {
                                if isSelected {
                                    Circle()
                                        .fill(Color.blue)
                                        .matchedGeometryEffect(id: "selectedDay", in: animationNamespace)
                                } else {
                                    Circle().fill(Color.clear)
                                }
                            }
                        )
                        .foregroundColor(isSelected ? .white : .textPrimary)

                    if mealCount > 0 {
                        Text("\(mealCount)")
                            .appFont(size: 10, weight: .bold)
                            .foregroundColor(isSelected ? .blue : Color(UIColor.secondaryLabel))
                            .frame(width: 26, height: 16)
                            .background(
                                (isSelected ? Color.blue.opacity(0.14) : Color(UIColor.secondarySystemFill)),
                                in: Capsule()
                            )
                    } else if isToday {
                        Capsule()
                            .fill(isSelected ? Color.blue.opacity(0.2) : Color.brandPrimary.opacity(0.18))
                            .frame(width: 26, height: 4)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(width: 26, height: 16)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 82)
                .background(isSelected ? Color.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedDate = date }
                    HapticManager.instance.feedback(.light)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func dayOfWeek(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "EEE"; return formatter.string(from: date) }
    private func dayOfMonth(for date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "d"; return formatter.string(from: date) }
}

extension DateFormatter {
    static var longDate: DateFormatter { let formatter = DateFormatter(); formatter.dateStyle = .long; return formatter }
}
