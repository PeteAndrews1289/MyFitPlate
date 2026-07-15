import SwiftUI

struct OnboardingSurveyView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onComplete: () -> Void

    @State private var currentStep: Int

    @State private var ageInput = ""
    @AppStorage("useMetricBodyUnits") private var useMetric = Locale.current.measurementSystem != .us
    @State private var heightFeetInput = ""
    @State private var heightInchesInput = ""
    @State private var heightCmInput = ""
    @State private var currentWeightInput = ""
    @State private var targetWeightInput = ""
    @State private var selectedGender = "Male"
    @State private var selectedActivityLevelKey = "Sedentary"
    @State private var selectedGoal = "Lose"
    @State private var selectedTrainingIntent = "General Fitness"
    @State private var selectedReminderStyle = "Gentle"
    @State private var selectedMaiaTone = "Balanced"

    private let totalSteps = 6
    private let activityLevels: [String: String] = [
        "Sedentary": "Little to no planned exercise",
        "Lightly Active": "Light exercise 1-3 days each week",
        "Moderately Active": "Moderate exercise 3-5 days each week",
        "Very Active": "Hard exercise 6-7 days each week",
        "Extremely Active": "Very hard exercise plus a physical job"
    ]
    private let goals = ["Lose", "Maintain", "Gain"]
    private let trainingIntents = ["General Fitness", "Strength", "Muscle Gain", "Fat Loss"]
    private let reminderStyles = ["Gentle", "Direct", "Minimal"]
    private let maiaTones = ["Balanced", "Coach", "Analyst"]
    private let activityLevelMap: [String: Double] = [
        "Sedentary": 1.2,
        "Lightly Active": 1.375,
        "Moderately Active": 1.55,
        "Very Active": 1.725,
        "Extremely Active": 1.9
    ]
    private let activityLevelOrder = [
        "Sedentary",
        "Lightly Active",
        "Moderately Active",
        "Very Active",
        "Extremely Active"
    ]

    init(initialStep: Int = 0, onComplete: @escaping () -> Void) {
        _currentStep = State(initialValue: min(max(initialStep, 0), 5))
        self.onComplete = onComplete
    }

    private var isCurrentStepValid: Bool {
        switch currentStep {
        case 0:
            return !ageInput.isEmpty && (Int(ageInput) ?? 0) > 0
        case 1:
            if useMetric {
                return !heightCmInput.isEmpty && (Double(heightCmInput) ?? 0) > 0
            }
            return !heightFeetInput.isEmpty && (Int(heightFeetInput) ?? 0) > 0 &&
                !heightInchesInput.isEmpty && (Int(heightInchesInput) ?? -1) >= 0 &&
                (Int(heightInchesInput) ?? 12) < 12
        case 2:
            return !currentWeightInput.isEmpty && (Double(currentWeightInput) ?? 0) > 0
        case 3, 4:
            return true
        case 5:
            return !targetWeightInput.isEmpty && (Double(targetWeightInput) ?? 0) > 0
        default:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            currentStepView
        }
        .safeAreaInset(edge: .bottom) {
            navigationActions
        }
        .background(AppPalette.canvas.ignoresSafeArea())
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        progressTitle
                        progressCount
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        progressTitle
                        Spacer()
                        progressCount
                    }
                }
            }

            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .tint(AppPalette.brand)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(currentStep + 1) of \(totalSteps)")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
    }

    private var progressTitle: some View {
        Text("Personal setup")
            .appTextRole(.sectionTitle)
            .foregroundStyle(AppPalette.text)
    }

    private var progressCount: some View {
        Text("Step \(currentStep + 1) of \(totalSteps)")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case 0:
            stepView(
                eyebrow: "Your baseline",
                title: "What's your age?",
                subtitle: "Age is one input in your estimated daily energy needs.",
                icon: "birthday.cake"
            ) { ageStepView }
        case 1:
            stepView(
                eyebrow: "Your baseline",
                title: "What's your height?",
                subtitle: "Height helps estimate energy needs and can be changed later.",
                icon: "ruler"
            ) { heightStepView }
        case 2:
            stepView(
                eyebrow: "Your baseline",
                title: "What's your current weight?",
                subtitle: "This becomes the starting point for your body trend.",
                icon: "scalemass"
            ) { currentWeightStepView }
        case 3:
            stepView(
                eyebrow: "Your daily context",
                title: "How active is your life?",
                subtitle: "Choose the closest baseline. Training can still vary from day to day.",
                icon: "figure.walk"
            ) { activityAndGoalStepView }
        case 4:
            stepView(
                eyebrow: "Your preferences",
                title: "How should MyFitPlate coach you?",
                subtitle: "These choices shape defaults and tone; they do not lock your plan.",
                icon: "slider.horizontal.3"
            ) { coachingPreferencesStepView }
        default:
            stepView(
                eyebrow: "Your direction",
                title: "What's your target weight?",
                subtitle: "Use a practical target you can revisit as your training changes.",
                icon: "flag.checkered"
            ) { targetWeightStepView }
        }
    }

    private func stepView<Content: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(eyebrow: eyebrow, title: title, subtitle: subtitle) {
                    Image(systemName: icon)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.brandText)
                        .frame(width: 52, height: 52)
                        .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                        .accessibilityHidden(true)
                }

                content()
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .id(currentStep)
        .transition(.opacity)
        .animation(AppMotion.visibility, value: currentStep)
    }

    private var navigationActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    if currentStep > 0 { backButton }
                    nextButton
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    if currentStep > 0 { backButton }
                    nextButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
    }

    private var backButton: some View {
        Button("Back") {
            hideKeyboard()
            withAnimation(AppMotion.standard) { currentStep -= 1 }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("onboarding_back")
    }

    private var nextButton: some View {
        Button(currentStep == totalSteps - 1 ? "Finish setup" : "Next") {
            hideKeyboard()
            saveGoalsAndProceed()
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(!isCurrentStepValid)
        .accessibilityIdentifier("onboarding_next")
    }

    private var ageStepView: some View {
        OnboardingMeasurementField(
            title: "Age",
            text: $ageInput,
            unit: "years",
            keyboard: .numberPad
        )
    }

    @ViewBuilder
    private var heightStepView: some View {
        if useMetric {
            OnboardingMeasurementField(
                title: "Height",
                text: $heightCmInput,
                unit: "cm",
                keyboard: .decimalPad
            )
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.row) {
                imperialFeetField
                imperialInchesField
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                imperialFeetField
                imperialInchesField
            }
        }
    }

    private var imperialFeetField: some View {
        OnboardingMeasurementField(
            title: "Feet",
            text: $heightFeetInput,
            unit: "ft",
            keyboard: .numberPad
        )
    }

    private var imperialInchesField: some View {
        OnboardingMeasurementField(
            title: "Inches",
            text: $heightInchesInput,
            unit: "in",
            keyboard: .numberPad
        )
    }

    private var currentWeightStepView: some View {
        OnboardingMeasurementField(
            title: "Current weight",
            text: $currentWeightInput,
            unit: BodyUnits.weightUnit(metric: useMetric),
            keyboard: .decimalPad
        )
    }

    private var targetWeightStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            OnboardingMeasurementField(
                title: "Target weight",
                text: $targetWeightInput,
                unit: BodyUnits.weightUnit(metric: useMetric),
                keyboard: .decimalPad
            )

            Label("Your target can be changed from Settings at any time.", systemImage: "arrow.triangle.2.circlepath")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activityAndGoalStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Energy estimate",
                    subtitle: "Select the sex used by the current metabolic formula."
                )

                Picker("Sex used for energy estimate", selection: $selectedGender) {
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                }
                .pickerStyle(.segmented)
            }
            .appSurface(.emphasized)

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Activity baseline",
                    subtitle: "Pick the closest description of a typical week."
                )

                VStack(spacing: 0) {
                    ForEach(Array(activityLevelOrder.enumerated()), id: \.element) { index, key in
                        activityButton(key)

                        if index < activityLevelOrder.count - 1 {
                            Divider().padding(.leading, AppSpacing.group)
                        }
                    }
                }
                .appSurface(.emphasized, padding: 0)
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Primary direction",
                    subtitle: "This sets the starting calorie direction."
                )

                Picker("Primary goal", selection: $selectedGoal) {
                    ForEach(goals, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            .appSurface(.emphasized)
        }
    }

    private func activityButton(_ key: String) -> some View {
        Button {
            selectedActivityLevelKey = key
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(key)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    Text(activityLevels[key] ?? "")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.compact)

                Image(systemName: selectedActivityLevelKey == key ? "checkmark.circle.fill" : "circle")
                    .appTextRole(.control)
                    .foregroundStyle(selectedActivityLevelKey == key ? AppPalette.brandText : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedActivityLevelKey == key ? AppPalette.brand.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedActivityLevelKey == key ? .isSelected : [])
    }

    private var coachingPreferencesStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Coaching defaults",
                subtitle: "Choose the starting style for training, reminders, and Maia."
            )

            VStack(spacing: 0) {
                OnboardingMenuRow(
                    title: "Training intent",
                    subtitle: "Shapes training and recovery defaults",
                    icon: "dumbbell",
                    selection: $selectedTrainingIntent,
                    options: trainingIntents
                )

                Divider().padding(.leading, 68)

                OnboardingMenuRow(
                    title: "Reminder style",
                    subtitle: "Controls how daily nudges are written",
                    icon: "bell",
                    selection: $selectedReminderStyle,
                    options: reminderStyles
                )

                Divider().padding(.leading, 68)

                OnboardingMenuRow(
                    title: "Maia style",
                    subtitle: "Controls the tone of AI guidance",
                    icon: "sparkles",
                    selection: $selectedMaiaTone,
                    options: maiaTones
                )
            }
            .appSurface(.emphasized, padding: 0)
        }
    }

    private func saveGoalsAndProceed() {
        guard isCurrentStepValid else { return }

        if currentStep < totalSteps - 1 {
            withAnimation(AppMotion.standard) { currentStep += 1 }
            return
        }

        guard let age = Int(ageInput), age > 0,
              let heightCm = parsedHeightCm(),
              let currentWeightValue = Double(currentWeightInput), currentWeightValue > 0,
              let targetWeightValue = Double(targetWeightInput), targetWeightValue > 0 else {
            withAnimation(AppMotion.standard) { currentStep = firstIncompleteStep() }
            return
        }

        goalSettings.age = age
        goalSettings.height = heightCm
        goalSettings.targetWeight = BodyUnits.weightToLbs(targetWeightValue, metric: useMetric)
        goalSettings.gender = selectedGender
        goalSettings.activityLevel = activityLevelMap[selectedActivityLevelKey] ?? 1.2
        goalSettings.goal = selectedGoal
        goalSettings.trainingIntent = selectedTrainingIntent
        goalSettings.reminderStyle = selectedReminderStyle
        goalSettings.maiaTone = selectedMaiaTone
        goalSettings.recalculateAllGoals()

        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
            goalSettings.updateUserWeight(BodyUnits.weightToLbs(currentWeightValue, metric: useMetric))
        }
        onComplete()
    }

    private func firstIncompleteStep() -> Int {
        if ageInput.isEmpty || (Int(ageInput) ?? 0) <= 0 { return 0 }
        if useMetric {
            if heightCmInput.isEmpty || (Double(heightCmInput) ?? 0) <= 0 { return 1 }
        } else if heightFeetInput.isEmpty || (Int(heightFeetInput) ?? 0) <= 0 ||
                    heightInchesInput.isEmpty || (Int(heightInchesInput) ?? -1) < 0 ||
                    (Int(heightInchesInput) ?? 12) >= 12 {
            return 1
        }
        if currentWeightInput.isEmpty || (Double(currentWeightInput) ?? 0) <= 0 { return 2 }
        if targetWeightInput.isEmpty || (Double(targetWeightInput) ?? 0) <= 0 { return 5 }
        return 0
    }

    private func parsedHeightCm() -> Double? {
        if useMetric {
            guard let cm = Double(heightCmInput), cm > 0 else { return nil }
            return cm
        }
        guard let feet = Int(heightFeetInput), feet > 0,
              let inches = Int(heightInchesInput), inches >= 0, inches < 12 else { return nil }
        return BodyUnits.cm(feet: feet, inches: inches)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct OnboardingMeasurementField: View {
    let title: String
    @Binding var text: String
    let unit: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                TextField("0", text: $text)
                    .appTextRole(.metric)
                    .foregroundStyle(AppPalette.text)
                    .keyboardType(keyboard)
                    .submitLabel(.done)
                    .accessibilityLabel(title)

                Text(unit)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.brandText)
            }
        }
        .appSurface(.emphasized)
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingMenuRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var selection: String
    let options: [String]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    label
                    picker
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    label
                    Spacer(minLength: AppSpacing.compact)
                    picker
                }
            }
        }
        .padding(AppSpacing.group)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .pickerStyle(.menu)
        .tint(AppPalette.brand)
        .accessibilityIdentifier("onboarding_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}
