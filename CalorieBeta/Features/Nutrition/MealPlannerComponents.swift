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
        meals.compactMap(\.plannedFood)
    }

    private var totalCalories: Double {
        foodItems.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        foodItems.reduce(0) { $0 + $1.protein }
    }

    private var calorieGoal: Double {
        max(goals.calories ?? 0, 1)
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
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("\(meals.count) \(meals.count == 1 ? "meal" : "meals") · \(Int(totalCalories.rounded()).formatted()) of \(Int(calorieGoal.rounded()).formatted()) cal · \(Int(totalProtein.rounded()).formatted()) g protein")
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: min(max(totalCalories / calorieGoal, 0), 1))
                .tint(AppPalette.energy)
                .accessibilityLabel("Planned calories")
                .accessibilityValue("\(Int(totalCalories.rounded()).formatted()) of \(Int(calorieGoal.rounded()).formatted()) calories")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(dateTitle)'s planned meals")
        .accessibilityIdentifier("meal_plan_summary")
    }

}

struct WeeklyPlanOverviewCard: View {
    let plans: [MealPlanDay]
    let onOpenGrocery: () -> Void
    let onStartMealPrep: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plannedDays: Int { plans.filter { !$0.meals.isEmpty }.count }
    private var mealCount: Int { plans.reduce(0) { $0 + $1.meals.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Make the week easier", subtitle: "\(mealCount) meals across \(plannedDays) of 7 days")
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(spacing: AppSpacing.row))
             : AnyLayout(HStackLayout(spacing: AppSpacing.row))) {
                Button(action: onOpenGrocery) { Label("Shop this week", systemImage: "basket") }
                    .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("planner_shop_week")
                Button(action: onStartMealPrep) { Label("Prep this week", systemImage: "flame") }
                    .buttonStyle(AppActionButtonStyle(.secondary)).disabled(mealCount == 0)
                    .accessibilityIdentifier("planner_prep_week")
            }
            Text("Your grocery list and prep quantities follow this week's planned portions.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, AppSpacing.group)
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
        .padding(.vertical, AppSpacing.group)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct MealPlannerEmptyState: View {
    let onGenerate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("No meals planned", systemImage: "calendar")
                .appTextRole(.sectionTitle)
            Text("Add a food or saved recipe, or draft several days together.")
                .appTextRole(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Draft a week", action: onGenerate)
                .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.group)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct MealCardView: View {
    let meal: PlannedMeal
    var isRegenerating: Bool
    var isLogged: Bool
    var isLogging = false
    var onLog: (PlannedMeal) -> Void
    var onRegenerate: () -> Void
    var onDelete: () -> Void
    var onEdit: () -> Void
    var onSwap: () -> Void
    var onCopy: () -> Void
    var onMove: () -> Void
    var onPlanLeftovers: (() -> Void)?
    var executionAction: MealExecutionAction?
    var onPrimaryAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String { meal.foodItem?.name ?? "Planned meal" }

    private var primaryActionIdentifier: String {
        switch executionAction {
        case .useStock, .recordStockUse: return "planner_use_stock_\(meal.id)"
        case .cook: return "planner_record_batch_\(meal.id)"
        case .review: return "planner_review_\(meal.id)"
        default: return "meal_plan_log_\(meal.id)"
        }
    }

    private var primaryActionTitle: String {
        switch executionAction {
        case .log: return "Log my portion"
        case .cook: return "Cook"
        case .useStock: return meal.preparedStock == nil ? "Use cooked portion" : "Use leftovers"
        default: return executionAction?.title ?? (isLogged ? "Logged" : "Log my portion")
        }
    }

    private var primaryActionIcon: String {
        switch executionAction {
        case .cook: return "frying.pan"
        case .useStock, .recordStockUse: return "takeoutbag.and.cup.and.straw"
        case .review: return "calendar"
        case .checkStock, .loadingStock: return "refrigerator"
        default: return isLogged ? "checkmark.circle" : "plus.circle"
        }
    }

    private var usesInlineAction: Bool {
        !dynamicTypeSize.isAccessibilitySize && (executionAction == .log || executionAction == .logged || executionAction == nil)
    }

    private func actionButton(compact: Bool) -> some View {
        Button {
            if let onPrimaryAction { onPrimaryAction() } else { onLog(meal) }
        } label: {
            if compact && !isLogging {
                if isLogged { Image(systemName: "checkmark") } else { Text("Log") }
            } else {
                Label(isLogging ? "Saving…" : primaryActionTitle, systemImage: primaryActionIcon)
            }
        }
        .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
        .accessibilityLabel(primaryActionTitle)
        .disabled(!(executionAction?.isEnabled ?? !isLogged) || isLogging || isRegenerating)
        .accessibilityIdentifier(primaryActionIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Button(action: onEdit) {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        FoodGlyph(name, pointSize: 26).frame(width: 44, height: 44)
                            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.mealType).appTextRole(.caption).foregroundStyle(.secondary)
                            Text(name).appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                            if let food = meal.plannedFood {
                                let portion = meal.portions == 1 ? ServingNutritionCalculator.displayPortion(food.servingSize) : "\(meal.portions.formatted(.number.precision(.fractionLength(0...2)))) × original portion"
                                Text([portion, "\(Int(food.calories.rounded()).formatted())\u{00A0}cal", "\(Int(food.protein.rounded()).formatted())\u{00A0}g protein"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let summary = MealPlanCookingRules.summary(for: meal) {
                                Text(summary).appTextRole(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("planner_batch_summary_\(meal.id)")
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recipe and portions for " + name)
                .accessibilityIdentifier("planner_edit_\(meal.id)")
                if usesInlineAction { actionButton(compact: true) }
                Menu {
                    if executionAction == .log {
                        Button("Adjust before logging", systemImage: "fork.knife") { onLog(meal) }
                            .accessibilityIdentifier("planner_review_log_\(meal.id)")
                    }
                    Button("Edit portions", systemImage: "slider.horizontal.3", action: onEdit)
                    Button("Swap meal", systemImage: "arrow.triangle.swap", action: onSwap)
                    Button("Copy to dates", systemImage: "doc.on.doc", action: onCopy)
                    Button("Move to date", systemImage: "calendar", action: onMove)
                    if let onPlanLeftovers {
                        Button("Plan leftovers", systemImage: "takeoutbag.and.cup.and.straw", action: onPlanLeftovers)
                            .accessibilityIdentifier("planner_plan_leftovers_\(meal.id)")
                    }
                    Button("Suggest alternative", systemImage: "wand.and.stars", action: onRegenerate)
                    if executionAction != nil, executionAction != .log, executionAction != .review, !isLogged {
                        Button("Log food separately", systemImage: "plus.circle") { onLog(meal) }
                    }
                    Divider()
                    Button("Remove meal", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(name)")
                .accessibilityIdentifier("planner_meal_options_\(meal.id)")
                .disabled(isLogging || isRegenerating)
            }
            if !usesInlineAction, executionAction != .review {
                HStack {
                    Spacer(minLength: 0)
                    actionButton(compact: false)
                }
            }
            if isRegenerating { ProgressView("Finding an alternative to review") }
        }
        .padding(.vertical, AppSpacing.row)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension DateFormatter {
    static var longDate: DateFormatter { let formatter = DateFormatter(); formatter.dateStyle = .long; return formatter }
}
