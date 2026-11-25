import SwiftUI
import MyFitPlateCore

struct GenderButtonPicker: View {
    @Binding var selectedGender: String

    var body: some View {
        Picker("Sex", selection: $selectedGender) {
            ForEach(["Male", "Female"], id: \.self) { gender in
                Text(gender).tag(gender)
            }
        }
        .pickerStyle(.segmented)
    }
}

@MainActor
struct CaloricCalculatorView: View {
    @EnvironmentObject var liveGoals: GoalSettings
    @StateObject private var goalSettings = GoalSettings(isEditingPreview: true)
    @State private var baseline: GoalEditorDraft?
    @State private var ownerID: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var seeded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var numericFieldIsFocused: Bool
    
    @State private var calorieInput: String = ""
    @State private var targetWeightInput: String = ""
    // Local draft for the two pickers, seeded on appear. They write to goalSettings only on a
    // real user change — so merely opening (and dismissing) the screen can't reset activity/goal.
    @State private var selectedActivityString: String = "Sedentary"
    @State private var selectedGoal: String = "Maintain"
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

     private let activityLevelStrings = [
         "Sedentary", "Lightly active", "Moderately active", "Very active", "Extremely active"
     ]
     private let activityLevelValues = [1.2, 1.375, 1.55, 1.725, 1.9]

     /// Map a stored multiplier to its picker label, snapping a non-preset value to the
     /// NEAREST preset rather than silently falling back to "Sedentary".
     private func activityString(for level: Double) -> String {
         if let index = activityLevelValues.firstIndex(of: level) {
             return activityLevelStrings[index]
         }
         let nearestIndex = activityLevelValues.indices.min {
             abs(activityLevelValues[$0] - level) < abs(activityLevelValues[$1] - level)
         } ?? 0
         return activityLevelStrings[nearestIndex]
     }

    private let goals = ["Lose", "Maintain", "Gain"]

    var body: some View {
        AppEditorScaffold(
            title: "Calorie & Macro Goals",
            subtitle: "Review the assumptions behind your estimate, then save the target you want to use.",
            dismiss: { if !isSaving { dismiss() } }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                personalInfoSection
                weightGoalsSection
                dailyCalorieSection
                macronutrientSection
                Text("Changes apply to current goals. Diary and workout history are not rewritten.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                citationSection
            }
        } actions: {
            if let saveError {
                Text(saveError).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                    .accessibilityIdentifier("settings_goals_save_error")
            }
            Button(isSaving ? "Saving…" : "Save goals") {
                numericFieldIsFocused = false
                saveCaloricGoal()
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(!hasValidCalorieInput || isSaving)
            .accessibilityIdentifier("settings_goals_save")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { numericFieldIsFocused = false }
            }
        }
        .onAppear(perform: fetchAndSetGoals)
        .onChange(of: resolvedDraft?.calories) { _, value in
            if goalSettings.calorieGoalMethod != .custom, let value { calorieInput = String(format: "%.0f", value) }
        }
        .interactiveDismissDisabled(isSaving)
        .disabled(isSaving)
        .tint(AppPalette.brand)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_goals_screen")
    }

    private var currentWeightBinding: Binding<Double> {
        Binding(
            get: { BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric) },
            set: { goalSettings.weight = BodyUnits.weightToLbs($0, metric: useMetric) }
        )
    }

    @ViewBuilder
    private var ageRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("Age")
                    .appTextRole(.control)
                ageField
            }
        } else {
            HStack(spacing: AppSpacing.group) {
                Text("Age")
                    .appTextRole(.control)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: AppSpacing.group)
                ageField
                    .frame(maxWidth: 120)
            }
        }
    }

    private var ageField: some View {
        TextField("Age", value: $goalSettings.age, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .textFieldStyle(.roundedBorder)
            .focused($numericFieldIsFocused)
            .accessibilityLabel("Age")
            .accessibilityHint("Enter your age in years")
            .accessibilityIdentifier("settings_goals_age")
    }

    @ViewBuilder
    private var currentWeightRow: some View {
        numericWeightRow(
            title: "Current Weight",
            value: currentWeightBinding,
            identifier: "settings_goals_current_weight"
        )
    }

    @ViewBuilder
    private var targetWeightRow: some View {
        labeledInputRow(title: "Target Weight") {
            HStack(spacing: AppSpacing.compact) {
                TextField("Target weight", text: $targetWeightInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($numericFieldIsFocused)
                    .accessibilityIdentifier("settings_goals_target_weight")

                Text(BodyUnits.weightUnit(metric: useMetric))
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func numericWeightRow(
        title: String,
        value: Binding<Double>,
        identifier: String
    ) -> some View {
        labeledInputRow(title: title) {
            HStack(spacing: AppSpacing.compact) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($numericFieldIsFocused)
                    .accessibilityIdentifier(identifier)

                Text(BodyUnits.weightUnit(metric: useMetric))
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func labeledInputRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(title)
                    .appTextRole(.control)
                content()
            }
        } else {
            HStack(spacing: AppSpacing.group) {
                Text(title)
                    .appTextRole(.control)
                Spacer(minLength: AppSpacing.group)
                content()
                    .frame(maxWidth: 180)
            }
        }
    }

    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Your Information",
                subtitle: "Age, sex, and activity level are assumptions in the energy estimate."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                ageRow

                GenderButtonPicker(selectedGender: $goalSettings.gender)

                Picker("Activity level", selection: $selectedActivityString) {
                    ForEach(activityLevelStrings, id: \.self) { levelString in
                        Text(levelString).tag(levelString)
                    }
                }
                .appTextRole(.control)
            .onChange(of: selectedActivityString) { _, newValue in
                if let index = activityLevelStrings.firstIndex(of: newValue) {
                    goalSettings.activityLevel = activityLevelValues[index]
                }
            }

                Picker("Goal", selection: $selectedGoal) {
                    ForEach(goals, id: \.self) { goal in
                        Text(goal).tag(goal)
                    }
                }
                .appTextRole(.control)
                .onChange(of: selectedGoal) { _, newValue in
                    if newValue != "Maintain" {
                        goalSettings.weeklyChangeLbs = GoalSettingsRules.normalizedWeeklyChange(
                            goalSettings.weeklyChangeLbs,
                            forGoal: newValue
                        )
                    }
                    goalSettings.goal = newValue
                }

                if selectedGoal != "Maintain" {
                    Picker("Weekly pace", selection: $goalSettings.weeklyChangeLbs) {
                        ForEach(GoalSettingsRules.weeklyChangeOptions(forGoal: selectedGoal), id: \.self) { lbs in
                            Text(GoalSettingsRules.weeklyChangeText(lbs: lbs, metric: useMetric)).tag(lbs)
                        }
                    }
                    .appTextRole(.control)
                    .accessibilityIdentifier("goal_weekly_pace")
                }
            }
            .appSurface(.emphasized)
        }
    }

    private var weightGoalsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Weight Goals",
                subtitle: "These values shape the direction of the recommendation."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                currentWeightRow
                Divider()
                targetWeightRow
            }
            .appSurface(.emphasized)
        }
    }

    private var dailyCalorieSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Daily Calorie Goal",
                subtitle: "The calculated value remains editable before you save."
            )

            Picker("Calorie method", selection: $goalSettings.calorieGoalMethod) {
                ForEach(CalorieGoalMethod.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("settings_goals_method")
            Text("Editing other fields keeps your chosen method.").appTextRole(.secondary).foregroundStyle(.secondary)
            if goalSettings.calorieGoalMethod != .custom {
                Text("Calculated target: \(resolvedDraft?.calories.formatted(.number.precision(.fractionLength(0))) ?? "—") cal")
                    .appTextRole(.control).accessibilityIdentifier("settings_goals_preview")
                if goalSettings.calorieGoalMethod == .dynamicTDEE, liveGoals.adaptiveGoalService?.calculatedTDEE == nil {
                    Text("Adaptive stays selected. Until enough evidence is available, its formula and logged-activity fallback is used.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                if goalSettings.calorieGoalMethod == .custom {
                    TextField("Calories", text: $calorieInput)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("settings_goals_calories")
                    .appTextRole(.metric)
                    .foregroundStyle(AppPalette.energy)
                    .monospacedDigit()
                    .focused($numericFieldIsFocused)
                } else {
                    Text((resolvedDraft?.calories ?? goalSettings.calories ?? 0).formatted(.number.precision(.fractionLength(0))))
                        .appTextRole(.metric).foregroundStyle(AppPalette.energy).monospacedDigit()
                        .accessibilityIdentifier("settings_goals_calories")
                }

                Text("cal")
                    .appTextRole(.control)
                    .foregroundStyle(.secondary)
            }
            .appSurface(.interpreted)
            if let value = resolvedDraft, goalSettings.calorieGoalMethod == .custom, value.calories > (Double(calorieInput) ?? 0) {
                Text("Saving uses the app minimum of \(value.calories.formatted(.number.precision(.fractionLength(0)))) cal.")
                    .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
            }
            if !calorieInput.isEmpty, !hasValidCalorieInput {
                Text("Check your body inputs and target. Macro percentages must total 100%.")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.critical)
            }
        }
    }

    private var macronutrientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Macronutrient Distribution",
                subtitle: "Percentages must total 100%. Invalid splits are kept for correction."
            )

            VStack(spacing: 15) {
                macroSlider(title: "Protein", value: $goalSettings.proteinPercentage, color: .accentProtein)
                macroSlider(title: "Carbs", value: $goalSettings.carbsPercentage, color: .accentCarbs)
                macroSlider(title: "Fat", value: $goalSettings.fatsPercentage, color: .accentFats)
            }
            .appSurface(.emphasized)
        }
    }
    
    private var citationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Source & Limits",
                subtitle: "This is an estimate, not a measurement or medical recommendation."
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Calorie goals are estimated using the Mifflin-St Jeor equation combined with standard activity level multipliers.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                
                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                    Link("Source: A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.", destination: url)
                        .appTextRole(.secondary)
                }

                Text("Your actual needs may vary. Consult a qualified healthcare professional before making significant dietary or exercise changes.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appSurface(.quiet)
        }
    }

     private func macroSlider(title: String, value: Binding<Double>, color: Color) -> some View {
         VStack(alignment: .leading, spacing: 5) {
             HStack {
                 Text(title)
                 Spacer()
                 Text("\(Int(value.wrappedValue.rounded()))%")
             }
             .appFont(size: 15)

             Slider(value: value, in: 10...70, step: 5)
                 .tint(color)
         }
     }

    private func fetchAndSetGoals() {
        guard !seeded else { return }
        seeded = true
        ownerID = DIContainer.shared.authService.currentUserID
        let initial = liveGoals.makeGoalEditorDraft()
        baseline = initial
        let editable = initial.normalizedForEditing()
        goalSettings.applyGoalEditorPreview(editable)
        calorieInput = String(format: "%.0f", editable.calories)
        targetWeightInput = editable.targetWeight.map { String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)) } ?? ""
        selectedActivityString = activityString(for: editable.activityLevel)
        selectedGoal = editable.goal
    }

    private var proposal: GoalEditorDraft? {
        var value = goalSettings.makeGoalEditorDraft()
        if value.method == .custom {
            guard let calories = Double(calorieInput) else { return nil }
            value.calories = calories
        }
        if targetWeightInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.targetWeight = nil } else {
            guard let target = Double(targetWeightInput) else { return nil }
            value.targetWeight = BodyUnits.weightToLbs(target, metric: useMetric)
        }
        return value
    }

    private var resolvedDraft: GoalEditorDraft? {
        try? proposal?.resolved(adaptiveTDEE: liveGoals.adaptiveGoalService?.calculatedTDEE,
                               manualCaloriesBurned: liveGoals.dailyLogService?.currentDailyLog?.totalCaloriesBurnedFromManualExercises() ?? 0)
    }

    private var hasValidCalorieInput: Bool { resolvedDraft != nil }

    private func saveCaloricGoal() {
        guard !isSaving, let proposal, let baseline, let ownerID else { return }
        isSaving = true; saveError = nil
        Task { @MainActor in
            do {
                try await liveGoals.saveGoalEditorDraft(proposal, baseline: baseline, userID: ownerID)
                isSaving = false
                dismiss()
            } catch { isSaving = false; saveError = error.localizedDescription }
        }
    }
}
