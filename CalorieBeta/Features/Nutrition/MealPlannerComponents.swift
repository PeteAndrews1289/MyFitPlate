import MyFitPlateCore

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
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "\(dateTitle)'s meal plan",
                subtitle: DateFormatter.longDate.string(from: date)
            ) {
                Text(calorieStatusText)
                    .appTextRole(.caption)
                    .foregroundStyle(calorieStatusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(calorieStatusColor.opacity(0.12), in: Capsule())
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Meals", value: meals.count.formatted(), accent: AppPalette.brand),
                AppMetricItem(
                    label: "Calories",
                    value: "\(Int(totalCalories.rounded()).formatted()) cal",
                    accent: .orange
                ),
                AppMetricItem(
                    label: "Protein",
                    value: "\(Int(totalProtein.rounded()).formatted()) g",
                    accent: .accentProtein
                )
            ])

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Daily fit")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

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
        }
        .appSurface(.emphasized, radius: AppRadius.hero)
        .accessibilityIdentifier("meal_plan_summary")
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
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(value.rounded()).formatted()) / \(Int(goal.rounded()).formatted()) \(unit)")
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
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
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Week at a glance",
                subtitle: plannedDays == 0
                    ? "No meals planned yet."
                    : "\(plannedDays) planned \(plannedDays == 1 ? "day" : "days")."
            ) {
                Button(action: onOpenGrocery) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
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

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Days",
                    value: plannedDays == 1 ? "1 day" : "\(plannedDays) days",
                    accent: AppPalette.brand
                ),
                AppMetricItem(label: "Meals", value: mealCount.formatted(), accent: .blue),
                AppMetricItem(
                    label: "Avg calories",
                    value: averageCalories > 0 ? "\(Int(averageCalories.rounded()).formatted()) cal" : "--",
                    accent: .orange
                )
            ])

            if plannedDays > 0 {
                Button(action: onStartMealPrep) {
                    Label("Start meal prep", systemImage: "flame.fill")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
        .appSurface(.quiet)
    }
}

struct MealPlanLoadingState: View {
    var message: String = "Loading meal plan"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppPalette.control)
                    .frame(width: 42, height: 42)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppPalette.control)
                        .frame(width: 80, height: 14)
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppPalette.control)
                        .frame(width: 140, height: 20)

                    Text(message)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppPalette.control)
                        .frame(height: 48)
                }
            }
        }
        .appSurface(.quiet)
    }
}

struct MealPlannerEmptyState: View {
    let onGenerate: () -> Void
    let onAddRecipe: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .appFont(size: 32, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 68, height: 68)
                .background(AppPalette.control, in: Circle())

            VStack(spacing: 5) {
                Text("No plan for this day yet")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text("Generate a weekly plan from your goals and preferences, or place a saved recipe into this day manually.")
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button("Generate meal plan", action: onGenerate)
                    .buttonStyle(AppActionButtonStyle(.primary))

                Button("Add saved recipe", action: onAddRecipe)
                    .buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .appSurface(.quiet)
    }
}

struct MealCardView: View {
    let meal: PlannedMeal
    var isRegenerating: Bool
    var isLogged: Bool
    var onLog: (PlannedMeal) -> Void
    var onRegenerate: () -> Void
    var onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: mealIcon)
                    .appFont(size: 17, weight: .bold)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(meal.mealType)
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(sourceLabel)
                            .appFont(size: 10, weight: .bold)
                            .foregroundColor(sourceColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(sourceColor.opacity(0.12), in: Capsule())
                    }

                    Text(displayName)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(displayName) from meal plan")
            }

            if let foodItem = meal.foodItem {
                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Calories",
                        value: "\(Int(foodItem.calories.rounded()).formatted()) cal",
                        accent: .orange
                    ),
                    AppMetricItem(
                        label: "Protein",
                        value: "\(Int(foodItem.protein.rounded()).formatted()) g",
                        accent: .accentProtein
                    ),
                    AppMetricItem(
                        label: "Carbs",
                        value: "\(Int(foodItem.carbs.rounded()).formatted()) g",
                        accent: .accentCarbs
                    ),
                    AppMetricItem(
                        label: "Fats",
                        value: "\(Int(foodItem.fats.rounded()).formatted()) g",
                        accent: .accentFats
                    )
                ])
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

            mealActions

        }
        .appSurface(.quiet)
    }

    @ViewBuilder
    private var mealActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.compact) {
                mealActionButtons
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                mealActionButtons
            }
        }
    }

    @ViewBuilder
    private var mealActionButtons: some View {
        Button(action: { onLog(meal) }) {
            Label(
                isLogged ? "Logged" : "Log meal",
                systemImage: isLogged ? "checkmark.circle.fill" : "plus.circle.fill"
            )
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .disabled(isLogged)

        Button(action: onRegenerate) {
            if isRegenerating {
                ProgressView()
            } else {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .buttonStyle(AppActionButtonStyle(.ghost))
        .disabled(isRegenerating)
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

struct MealPlanWeekStrip: View {
    @Binding var selectedDate: Date
    let mealCountsByDay: [String: Int]

    @Namespace private var animationNamespace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let calendar = Calendar.current

    private var dayWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 250 : 44
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }

        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.compact) {
                ForEach(dates, id: \.self) { date in
                    dayButton(
                        date,
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date),
                        mealCount: mealCountsByDay[dateKey(for: date)] ?? 0
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("meal_plan_week")
    }

    private func dayButton(_ date: Date, isSelected: Bool, isToday: Bool, mealCount: Int) -> some View {
        Button {
            withAnimation(AppMotion.standard) { selectedDate = date }
            HapticManager.instance.feedback(.light)
        } label: {
            dayLabel(date, isSelected: isSelected, isToday: isToday, mealCount: mealCount)
            .frame(width: dayWidth)
            .frame(minHeight: 82)
            .background(
                isSelected ? AppPalette.control : Color.clear,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, mealCount: mealCount, isSelected: isSelected))
    }

    @ViewBuilder
    private func dayLabel(_ date: Date, isSelected: Bool, isToday: Bool, mealCount: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeek(for: date))
                        .appTextRole(.control)
                        .foregroundStyle(isSelected ? AppPalette.brand : Color.secondary)

                    Text(monthAndDay(for: date))
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text(mealCount == 1 ? "1 planned meal" : "\(mealCount) planned meals")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brand)
                        .accessibilityHidden(true)
                }
            }
            .padding(AppSpacing.row)
        } else {
            VStack(spacing: 6) {
                Text(dayOfWeek(for: date))
                    .appTextRole(.caption)
                    .foregroundStyle(isSelected ? AppPalette.brand : Color.secondary)

                Text(dayOfMonth(for: date))
                    .appTextRole(.control)
                    .foregroundStyle(isSelected ? Color.white : AppPalette.text)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(AppPalette.brand)
                                .matchedGeometryEffect(id: "selectedMealPlanDay", in: animationNamespace)
                        }
                    }

                HStack(spacing: 3) {
                    Circle()
                        .fill(mealCount > 0 ? AppPalette.brand : Color.clear)
                        .frame(width: 5, height: 5)

                    Text(mealCount > 0 ? "\(mealCount)" : (isToday ? "Today" : " "))
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 16)
            }
        }
    }

    private func accessibilityLabel(for date: Date, mealCount: Int, isSelected: Bool) -> String {
        let mealText = mealCount == 1 ? "1 planned meal" : "\(mealCount) planned meals"
        return "\(dayOfWeek(for: date)) \(monthAndDay(for: date)), \(mealText)\(isSelected ? ", selected" : "")"
    }

    private func dayOfWeek(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dayOfMonth(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func monthAndDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

extension DateFormatter {
    static var longDate: DateFormatter { let formatter = DateFormatter(); formatter.dateStyle = .long; return formatter }
}
