import SwiftUI
import MyFitPlateCore

struct FoodRepeatQuickList: View {
    let foods: [FoodItem]
    let loggingFoodIDs: Set<String>
    let loggedFoodIDs: Set<String>
    var isBuildingMeal = false
    let onSelect: (FoodItem) -> Void
    let onLog: (FoodItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                FoodPickerRow(food: food, isQuickLogged: loggedFoodIDs.contains(food.id),
                    isLogging: loggingFoodIDs.contains(food.id), isBuildingMeal: isBuildingMeal,
                    onSelect: onSelect, onQuickLog: onLog, onDelete: nil, source: nil,
                    selectionID: "repeat_food_review_\(index)", quickActionID: "repeat_food_add_\(index)")
                if index < foods.count - 1 { Divider() }
            }
        }
        .overlay(alignment: .top) { Divider() }
    }
}

struct RepeatMealDraft: Identifiable {
    let id = UUID()
    let mealName: String
    let date: Date
    let foods: [FoodItem]
}

struct RepeatMealReview: View {
    let draft: RepeatMealDraft
    let onLog: ([FoodItem], @escaping (Bool) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var multipliers: [Double]
    @State private var isSaving = false
    @State private var saveFailed = false

    init(draft: RepeatMealDraft, onLog: @escaping ([FoodItem], @escaping (Bool) -> Void) -> Void) {
        self.draft = draft
        self.onLog = onLog
        _multipliers = State(initialValue: Array(repeating: 1, count: draft.foods.count))
    }

    private var selectedFoods: [FoodItem] {
        draft.foods.enumerated().compactMap { index, food in
            FoodRepeatRules.adjusting(food, by: multipliers[index])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(draft.mealName) · \(draft.date.formatted(date: .abbreviated, time: .omitted))")
                    Text("Adjust each amount. Set it to zero to leave that food out.")
                        .foregroundStyle(.secondary)
                }
                Section("Servings to repeat") {
                    ForEach(draft.foods.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(draft.foods[index].name).fontWeight(.semibold)
                            Text(draft.foods[index].servingSize).foregroundStyle(.secondary)
                            Stepper(value: $multipliers[index], in: 0...5, step: 0.5) {
                                Text(multipliers[index] == 0 ? "Leave out" : "\(multipliers[index].formatted(.number.precision(.fractionLength(0...1)))) × original amount")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityIdentifier("repeat_meal_serving_\(index)")
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    Text("\(selectedFoods.count) \(selectedFoods.count == 1 ? "food" : "foods") · \(Int(selectedFoods.reduce(0) { $0 + $1.calories }.rounded()).formatted()) cal")
                        .monospacedDigit()
                        .accessibilityIdentifier("repeat_meal_total")
                    if saveFailed {
                        Text("Could not save this meal. Your changes are still here; try again.")
                            .foregroundStyle(AppPalette.caution)
                    }
                    Button {
                        isSaving = true
                        saveFailed = false
                        onLog(selectedFoods) { success in
                            isSaving = false
                            saveFailed = !success
                            if success { dismiss() }
                        }
                    } label: {
                        Text(isSaving ? "Saving meal…" : "Log meal")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isSaving || selectedFoods.isEmpty)
                    .accessibilityIdentifier("repeat_meal_confirm")
                }
            }.appFormStyle()
            .disabled(isSaving)
            .navigationTitle("Review servings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}

struct FoodHistorySection: View {
    let title: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let loggingFoodIDs: Set<String>
    let isBuildingMeal: Bool
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let source: String
    var headerActionTitle: String?
    var headerAction: (() -> Void)?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title) {
                if let headerActionTitle, let headerAction {
                    Button(headerActionTitle, action: headerAction).buttonStyle(.plain)
                        .foregroundStyle(AppPalette.brandText).frame(minHeight: 44)
                }
            }
            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 0) {
                    ForEach(foods.prefix(expanded ? foods.count : 5)) { food in
                        Divider()
                        FoodPickerRow(food: food, isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                            isLogging: loggingFoodIDs.contains(food.id), isBuildingMeal: isBuildingMeal,
                            onSelect: onSelect, onQuickLog: onQuickLog, onDelete: nil, source: source)
                    }
                }
                if foods.count > 5 {
                    Button(expanded ? "Show fewer" : "Show all " + foods.count.formatted()) { expanded.toggle() }
                        .buttonStyle(.plain).foregroundStyle(AppPalette.brandText).frame(minHeight: 44)
                }
            }
        }
    }
}

struct FoodSearchLoadingState: View {
    let query: String

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(.secondary)

            Text("Searching foods")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.quiet, padding: AppSpacing.group)
    }
}

struct FoodSearchEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)

            VStack(spacing: 4) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let primaryActionTitle, let primaryAction {
                VStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(AppActionButtonStyle(.primary, fillsWidth: false))

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.brandText)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.compact)
        .appSurface(.quiet, padding: AppSpacing.group)
    }
}
