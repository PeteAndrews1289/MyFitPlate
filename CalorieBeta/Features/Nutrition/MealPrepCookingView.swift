import Combine
import MyFitPlateCore
import SwiftUI
import UIKit

struct MealPrepCookingView: View {
    @StateObject private var mealPrepService = MealPrepService()

    let days: [MealPlanDay]

    @State private var keepScreenOn = true
    @State private var selectedTab: Int
    @State private var completedStepIndexes: Set<Int> = []
    @State private var timerRemaining: TimeInterval = 0
    @State private var timerEndDate: Date?
    @State private var isTimerRunning = false
    @State private var showTimerSheet = false
    @State private var lastTimerMinutes = 10
    @State private var idleTimerStateBeforePresentation: Bool?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(days: [MealPlanDay], initialTab: Int = 0) {
        self.days = days
        _selectedTab = State(initialValue: min(max(initialTab, 0), 1))
    }

    var body: some View {
        AppSheetScaffold(
            title: "Meal Prep",
            subtitle: "Turn the planned week into one cooking session.",
            dismiss: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    prepSummary
                    screenAwakeControl
                    modePicker

                    if selectedTab == 0 {
                        ingredientsContent
                    } else {
                        stepsContent
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .safeAreaInset(edge: .bottom) {
                timerBar
                    .dynamicTypeSize(.xSmall ... .accessibility1)
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showTimerSheet) {
            TimerSetupView(initialMinutes: lastTimerMinutes) { minutes in
                startTimer(minutes: minutes)
                showTimerSheet = false
            }
        }
        .onAppear {
            mealPrepService.aggregate(days: days)
            if idleTimerStateBeforePresentation == nil {
                idleTimerStateBeforePresentation = UIApplication.shared.isIdleTimerDisabled
            }
            applyIdleTimerPreference()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleTimerStateBeforePresentation ?? false
            idleTimerStateBeforePresentation = nil
        }
        .onChange(of: keepScreenOn) {
            applyIdleTimerPreference()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                updateTimer()
                applyIdleTimerPreference()
            }
        }
        .onReceive(timer) { date in
            updateTimer(now: date)
        }
        .accessibilityIdentifier("meal_prep_screen")
    }

    private var prepSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(label: "Ingredients", value: ingredientCount.formatted()),
            AppMetricItem(label: "Recipes", value: recipeCount.formatted()),
            AppMetricItem(
                label: "Steps",
                value: "\(completedStepIndexes.count)/\(mealPrepService.prepSteps.count)",
                accent: completedStepIndexes.count == mealPrepService.prepSteps.count
                    && !mealPrepService.prepSteps.isEmpty ? .accentPositive : AppPalette.brand
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("meal_prep_summary")
    }

    private var screenAwakeControl: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: keepScreenOn ? "lightbulb.fill" : "lightbulb.slash")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(keepScreenOn ? AppPalette.brand : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keep Screen Awake")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text("Prevent Auto-Lock during prep")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppSpacing.compact)
            Toggle("Keep Screen Awake", isOn: $keepScreenOn)
                .labelsHidden()
                .tint(AppPalette.brand)
        }
        .padding(AppSpacing.group)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }

    private var modePicker: some View {
        Picker("Prep Mode", selection: $selectedTab) {
            Text("Ingredients").tag(0)
            Text("Steps").tag(1)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("meal_prep_mode_picker")
    }

    @ViewBuilder
    private var ingredientsContent: some View {
        if ingredientCount == 0 {
            MealPrepEmptyState(
                icon: "basket",
                title: "No Ingredients Yet",
                message: "Add ingredients to planned meals before opening meal prep."
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSectionHeader(
                    title: "Bulk Ingredients",
                    subtitle: "Combined quantities across the visible week."
                )

                ForEach(categoryNames, id: \.self) { category in
                    if let items = mealPrepService.bulkIngredients[category], !items.isEmpty {
                        ingredientSection(category: category, items: items)
                    }
                }
            }
            .accessibilityIdentifier("meal_prep_ingredients")
        }
    }

    private func ingredientSection(category: String, items: [BulkIngredient]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: category,
                subtitle: "\(items.count) item\(items.count == 1 ? "" : "s")"
            )

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AppListRow(
                        title: item.name,
                        subtitle: recipeUsageText(for: item),
                        hidesTextFromAccessibility: true
                    ) {
                        Text(quantityText(for: item))
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(item.name), \(quantityText(for: item)), \(recipeUsageText(for: item))"
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, AppSpacing.group)
                    }
                }
            }
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var stepsContent: some View {
        if mealPrepService.prepSteps.isEmpty {
            MealPrepEmptyState(
                icon: "list.number",
                title: "No Prep Steps Yet",
                message: "Add instructions to planned meals before opening meal prep."
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: "Prep Steps",
                    subtitle: "\(completedStepIndexes.count) of \(mealPrepService.prepSteps.count) complete"
                )

                VStack(spacing: 0) {
                    ForEach(mealPrepService.prepSteps.indices, id: \.self) { index in
                        prepStepRow(index: index)

                        if index < mealPrepService.prepSteps.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
            }
            .accessibilityIdentifier("meal_prep_steps")
        }
    }

    private func prepStepRow(index: Int) -> some View {
        let step = mealPrepService.prepSteps[index]
        let isComplete = completedStepIndexes.contains(index)

        return Button {
            HapticManager.instance.feedback(.light)
            if isComplete {
                completedStepIndexes.remove(index)
            } else {
                completedStepIndexes.insert(index)
            }
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 20, weight: .semibold)
                    .foregroundStyle(isComplete ? Color.accentPositive : AppPalette.brand)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.recipeName)
                        .appTextRole(.caption)
                        .foregroundStyle(isComplete ? Color.accentPositive : AppPalette.brand)
                    Text(step.step)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .strikethrough(isComplete, color: .secondary)
                        .opacity(isComplete ? 0.65 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.group)
            .padding(.vertical, AppSpacing.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1), \(step.recipeName), \(step.step)")
        .accessibilityValue(isComplete ? "Complete" : "Not complete")
        .accessibilityHint(isComplete ? "Marks this step incomplete" : "Marks this step complete")
    }

    @ViewBuilder
    private var timerBar: some View {
        if timerRemaining > 0 {
            HStack(spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isTimerRunning ? "Cooking Timer" : "Timer Paused")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Text(MealPrepTimerRules.display(timerRemaining))
                        .appTextRole(.metric)
                        .foregroundStyle(AppPalette.text)
                        .monospacedDigit()
                }

                Spacer(minLength: AppSpacing.compact)

                Button {
                    isTimerRunning ? pauseTimer() : resumeTimer()
                } label: {
                    Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel(isTimerRunning ? "Pause timer" : "Resume timer")

                Button(action: clearTimer) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Clear timer")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("meal_prep_active_timer")
        } else {
            Button {
                showTimerSheet = true
            } label: {
                Label("Start Cooking Timer", systemImage: "timer")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("meal_prep_start_timer")
        }
    }

    private var categoryNames: [String] {
        mealPrepService.bulkIngredients.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var ingredientCount: Int {
        mealPrepService.bulkIngredients.values.reduce(0) { $0 + $1.count }
    }

    private var recipeCount: Int {
        Set(days.flatMap(\.meals).compactMap { meal in
            let name = meal.foodItem?.name ?? meal.mealType
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? nil : trimmedName
        }).count
    }

    private func recipeUsageText(for item: BulkIngredient) -> String {
        let recipes = item.originalRecipes
        if recipes.count == 1 {
            return recipes[0]
        }
        return "Used in \(recipes.count) planned meals"
    }

    private func quantityText(for item: BulkIngredient) -> String {
        let safeQuantity = item.quantity.isFinite ? max(0, item.quantity) : 0
        let quantity = safeQuantity.formatted(.number.precision(.fractionLength(0...2)))
        let unit = MealPrepQuantityRules.displayUnit(item.unit, quantity: safeQuantity)
        return unit.isEmpty ? quantity : "\(quantity) \(unit)"
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    }

    private func startTimer(minutes: Int) {
        let safeMinutes = MealPrepTimerRules.clampedMinutes(minutes)
        lastTimerMinutes = safeMinutes
        timerRemaining = MealPrepTimerRules.duration(minutes: safeMinutes)
        timerEndDate = Date().addingTimeInterval(timerRemaining)
        isTimerRunning = true
    }

    private func updateTimer(now: Date = Date()) {
        guard isTimerRunning, let timerEndDate else { return }
        let updatedRemaining = MealPrepTimerRules.remaining(until: timerEndDate, now: now)
        timerRemaining = updatedRemaining
        if updatedRemaining <= 0 {
            isTimerRunning = false
            self.timerEndDate = nil
            HapticManager.instance.notification(.success)
        }
    }

    private func pauseTimer() {
        updateTimer()
        isTimerRunning = false
        timerEndDate = nil
    }

    private func resumeTimer() {
        guard timerRemaining > 0 else { return }
        timerEndDate = Date().addingTimeInterval(timerRemaining)
        isTimerRunning = true
    }

    private func clearTimer() {
        timerRemaining = 0
        timerEndDate = nil
        isTimerRunning = false
    }
}

private struct MealPrepEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .accessibilityHidden(true)
            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.emphasized)
    }
}

struct TimerSetupView: View {
    var onStart: (Int) -> Void

    @State private var minutes: Int
    @Environment(\.dismiss) private var dismiss

    init(initialMinutes: Int = 10, onStart: @escaping (Int) -> Void) {
        self.onStart = onStart
        _minutes = State(initialValue: MealPrepTimerRules.clampedMinutes(initialMinutes))
    }

    var body: some View {
        AppSheetScaffold(
            title: "Cooking Timer",
            subtitle: "Choose a duration for the next prep task.",
            dismiss: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Duration")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(minutes) min")
                            .appTextRole(.metric)
                            .foregroundStyle(AppPalette.text)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.emphasized)

                    Stepper("Timer Minutes", value: $minutes, in: 1...120, step: 1)
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.section)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onStart(MealPrepTimerRules.clampedMinutes(minutes))
                } label: {
                    Label("Start Timer", systemImage: "timer")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .dynamicTypeSize(.xSmall ... .accessibility1)
                .accessibilityIdentifier("meal_prep_timer_start")
            }
        }
        .accessibilityIdentifier("meal_prep_timer_setup")
    }
}
