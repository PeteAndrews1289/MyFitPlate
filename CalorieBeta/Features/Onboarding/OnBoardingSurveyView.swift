import SwiftUI

/// The onboarding quiz. It collects answers into an `OnboardingProfileDraft` and never writes to an
/// account itself, so the same questions run before sign-up and for an account that never finished.
struct OnboardingSurveyView: View {
    enum Step: Int, CaseIterable {
        case goal
        case aboutYou
        case height
        case currentWeight
        case targetWeight
        case activity
    }

    let onDraftReady: (OnboardingProfileDraft) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(BodyUnits.preferenceKey) private var useMetric = Locale.current.measurementSystem != .us

    @State private var step: Step
    @State private var selectedGoal: OnboardingProfileDraft.Goal?
    @State private var selectedTrainingIntent: String
    @State private var selectedSex: String?
    @State private var ageInput: String
    @State private var heightFeetInput: String
    @State private var heightInchesInput: String
    @State private var heightCmInput: String
    @State private var currentWeightInput: String
    @State private var targetWeightInput: String
    @State private var selectedActivityLevelKey: String?

    /// Preferences the quiz no longer asks about keep their prefilled values on a re-run.
    private let reminderStyle: String
    private let maiaTone: String

    private static let trainingIntents = ["General Fitness", "Strength", "Muscle Gain", "Fat Loss"]
    private static let activityLevels: [String: String] = [
        "Sedentary": "Little to no planned exercise",
        "Lightly Active": "Light exercise 1-3 days each week",
        "Moderately Active": "Moderate exercise 3-5 days each week",
        "Very Active": "Hard exercise 6-7 days each week",
        "Extremely Active": "Very hard exercise plus a physical job"
    ]
    private static let activityLevelMap: [String: Double] = [
        "Sedentary": 1.2,
        "Lightly Active": 1.375,
        "Moderately Active": 1.55,
        "Very Active": 1.725,
        "Extremely Active": 1.9
    ]
    private static let activityLevelOrder = [
        "Sedentary",
        "Lightly Active",
        "Moderately Active",
        "Very Active",
        "Extremely Active"
    ]

    init(
        initialStep: Step = .goal,
        prefill: OnboardingProfileDraft? = nil,
        onDraftReady: @escaping (OnboardingProfileDraft) -> Void
    ) {
        self.onDraftReady = onDraftReady
        _step = State(initialValue: initialStep)

        let metric = BodyUnits.prefersMetric()
        _selectedGoal = State(initialValue: prefill?.goal)
        _selectedTrainingIntent = State(initialValue: prefill?.trainingIntent ?? "General Fitness")
        _selectedSex = State(initialValue: prefill?.sex)
        _ageInput = State(initialValue: prefill.map { String($0.age) } ?? "")

        let imperialHeight = prefill.map { Self.feetAndInches(fromCm: $0.heightCm) }
        _heightFeetInput = State(initialValue: imperialHeight.map { String($0.feet) } ?? "")
        _heightInchesInput = State(initialValue: imperialHeight.map { String($0.inches) } ?? "")
        _heightCmInput = State(initialValue: prefill.map { Self.inputString($0.heightCm.rounded()) } ?? "")
        _currentWeightInput = State(initialValue: prefill.map {
            Self.inputString(BodyUnits.weightDisplayValue(lbs: $0.currentWeightLbs, metric: metric))
        } ?? "")
        _targetWeightInput = State(initialValue: prefill.map {
            Self.inputString(BodyUnits.weightDisplayValue(lbs: $0.targetWeightLbs, metric: metric))
        } ?? "")
        _selectedActivityLevelKey = State(initialValue: prefill.flatMap { draft in
            Self.activityLevelMap.first { abs($0.value - draft.activityMultiplier) < 0.001 }?.key
        })

        reminderStyle = prefill?.reminderStyle ?? "Gentle"
        maiaTone = prefill?.maiaTone ?? "Balanced"
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
        .onChange(of: useMetric) { _, metric in
            convertInputs(toMetric: metric)
        }
        .onChange(of: selectedGoal) { _, _ in
            if !visibleSteps.contains(step) {
                step = .activity
            }
        }
    }

    // MARK: - Steps

    private var visibleSteps: [Step] {
        Step.allCases.filter { $0 != .targetWeight || selectedGoal != .maintain }
    }

    private var stepPosition: Int {
        (visibleSteps.firstIndex(of: step) ?? 0) + 1
    }

    private var isLastStep: Bool {
        step == visibleSteps.last
    }

    private var isCurrentStepValid: Bool {
        isValid(step)
    }

    private func isValid(_ candidate: Step) -> Bool {
        switch candidate {
        case .goal:
            return selectedGoal != nil
        case .aboutYou:
            return selectedSex != nil && parsedAge.map(OnboardingProfileRules.isValidAge) == true
        case .height:
            return parsedHeightCm.map { OnboardingProfileRules.isValidHeight(cm: $0) } == true
        case .currentWeight:
            return parsedWeightLbs(currentWeightInput).map { OnboardingProfileRules.isValidWeight(lbs: $0) } == true
        case .targetWeight:
            return targetWeightHint == nil && parsedWeightLbs(targetWeightInput) != nil
        case .activity:
            return selectedActivityLevelKey != nil
        }
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

            ProgressView(value: Double(stepPosition), total: Double(visibleSteps.count))
                .tint(AppPalette.brand)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(stepPosition) of \(visibleSteps.count)")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
    }

    private var progressTitle: some View {
        Text("Build your plan")
            .appTextRole(.sectionTitle)
            .foregroundStyle(AppPalette.text)
    }

    private var progressCount: some View {
        Text("Step \(stepPosition) of \(visibleSteps.count)")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .goal:
            stepView(
                eyebrow: "Your goal",
                title: "What do you want to work toward?",
                subtitle: "Your calorie target and plan start here. You can change direction anytime.",
                icon: "flag.checkered"
            ) { goalStepView }
        case .aboutYou:
            stepView(
                eyebrow: "About you",
                title: "A little about you",
                subtitle: "Age and sex are inputs to the energy estimate behind your targets.",
                icon: "person.crop.circle"
            ) { aboutYouStepView }
        case .height:
            stepView(
                eyebrow: "Your baseline",
                title: "What's your height?",
                subtitle: "Height helps estimate how much energy you use each day.",
                icon: "ruler"
            ) { heightStepView }
        case .currentWeight:
            stepView(
                eyebrow: "Your baseline",
                title: "What's your current weight?",
                subtitle: "This becomes the first point on your body trend.",
                icon: "scalemass"
            ) { currentWeightStepView }
        case .targetWeight:
            stepView(
                eyebrow: "Your direction",
                title: "What's your target weight?",
                subtitle: "Pick a practical target. You can revisit it as your training changes.",
                icon: "target"
            ) { targetWeightStepView }
        case .activity:
            stepView(
                eyebrow: "Your daily context",
                title: "How active is your life?",
                subtitle: "Choose the closest baseline. Training can still vary from day to day.",
                icon: "figure.walk"
            ) { activityStepView }
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
        .id(step)
        .transition(.opacity)
        .animation(AppMotion.visibility, value: step)
    }

    private var navigationActions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    if stepPosition > 1 { backButton }
                    nextButton
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    if stepPosition > 1 { backButton }
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
            guard let index = visibleSteps.firstIndex(of: step), index > 0 else { return }
            withAnimation(AppMotion.standard) { step = visibleSteps[index - 1] }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("onboarding_back")
    }

    private var nextButton: some View {
        Button(isLastStep ? "See my plan" : "Next") {
            hideKeyboard()
            advance()
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(!isCurrentStepValid)
        .accessibilityIdentifier("onboarding_next")
    }

    private func advance() {
        guard isCurrentStepValid else { return }

        if !isLastStep, let index = visibleSteps.firstIndex(of: step) {
            withAnimation(AppMotion.standard) { step = visibleSteps[index + 1] }
            return
        }

        guard let draft = makeDraft() else {
            withAnimation(AppMotion.standard) { step = firstIncompleteStep() }
            return
        }
        onDraftReady(draft)
    }

    // MARK: - Step content

    private var goalStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(spacing: 0) {
                goalRow(.lose, icon: "arrow.down.right", title: "Lose weight", subtitle: "Lower body fat while protecting your strength")
                Divider().padding(.leading, 68)
                goalRow(.maintain, icon: "equal", title: "Maintain", subtitle: "Hold your weight and fuel your training")
                Divider().padding(.leading, 68)
                goalRow(.gain, icon: "arrow.up.right", title: "Gain weight", subtitle: "Build muscle with a steady surplus")
            }
            .appSurface(.emphasized, padding: 0)

            VStack(spacing: 0) {
                OnboardingMenuRow(
                    title: "Training focus",
                    subtitle: "Shapes training and recovery defaults",
                    icon: "dumbbell",
                    selection: $selectedTrainingIntent,
                    options: Self.trainingIntents
                )
            }
            .appSurface(.emphasized, padding: 0)
        }
    }

    private func goalRow(_ goal: OnboardingProfileDraft.Goal, icon: String, title: String, subtitle: String) -> some View {
        OnboardingChoiceRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isSelected: selectedGoal == goal,
            accessibilityIdentifier: "onboarding_goal_\(goal.rawValue.lowercased())"
        ) {
            selectedGoal = goal
        }
    }

    private var aboutYouStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Sex for the energy formula",
                    subtitle: "The Mifflin-St Jeor estimate uses different constants for each."
                )

                VStack(spacing: 0) {
                    sexRow("Female", icon: "figure.stand.dress")
                    Divider().padding(.leading, 68)
                    sexRow("Male", icon: "figure.stand")
                }
                .appSurface(.emphasized, padding: 0)
            }

            OnboardingMeasurementField(
                title: "Age",
                text: $ageInput,
                unit: "years",
                keyboard: .numberPad,
                hint: ageHint
            )
        }
    }

    private func sexRow(_ sex: String, icon: String) -> some View {
        OnboardingChoiceRow(
            icon: icon,
            title: sex,
            subtitle: nil,
            isSelected: selectedSex == sex,
            accessibilityIdentifier: "onboarding_sex_\(sex.lowercased())"
        ) {
            selectedSex = sex
        }
    }

    private var unitsPicker: some View {
        Picker("Units", selection: $useMetric) {
            Text("ft, lb").tag(false)
            Text("cm, kg").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("onboarding_units")
    }

    @ViewBuilder
    private var heightStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            unitsPicker

            if useMetric {
                OnboardingMeasurementField(
                    title: "Height",
                    text: $heightCmInput,
                    unit: "cm",
                    keyboard: .decimalPad,
                    hint: heightHint
                )
            } else {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
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

                if let heightHint {
                    OnboardingHint(text: heightHint)
                }
            }
        }
    }

    private var imperialFeetField: some View {
        OnboardingMeasurementField(
            title: "Feet",
            text: $heightFeetInput,
            unit: "ft",
            keyboard: .numberPad,
            hint: nil
        )
    }

    private var imperialInchesField: some View {
        OnboardingMeasurementField(
            title: "Inches",
            text: $heightInchesInput,
            unit: "in",
            keyboard: .numberPad,
            hint: nil
        )
    }

    private var currentWeightStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            unitsPicker

            OnboardingMeasurementField(
                title: "Current weight",
                text: $currentWeightInput,
                unit: BodyUnits.weightUnit(metric: useMetric),
                keyboard: .decimalPad,
                hint: weightHint(for: currentWeightInput)
            )
        }
    }

    private var targetWeightStepView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            OnboardingMeasurementField(
                title: "Target weight",
                text: $targetWeightInput,
                unit: BodyUnits.weightUnit(metric: useMetric),
                keyboard: .decimalPad,
                hint: targetWeightHint
            )

            Label("You can change your target from Settings at any time.", systemImage: "arrow.triangle.2.circlepath")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activityStepView: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.activityLevelOrder.enumerated()), id: \.element) { index, key in
                OnboardingChoiceRow(
                    icon: nil,
                    title: key,
                    subtitle: Self.activityLevels[key],
                    isSelected: selectedActivityLevelKey == key,
                    accessibilityIdentifier: "onboarding_activity_\(index)"
                ) {
                    selectedActivityLevelKey = key
                }

                if index < Self.activityLevelOrder.count - 1 {
                    Divider().padding(.leading, AppSpacing.group)
                }
            }
        }
        .appSurface(.emphasized, padding: 0)
    }

    // MARK: - Validation hints

    private var ageHint: String? {
        guard !ageInput.isEmpty else { return nil }
        guard let age = parsedAge, OnboardingProfileRules.isValidAge(age) else {
            return "MyFitPlate sets targets for ages 13 to 100."
        }
        return nil
    }

    private var heightHint: String? {
        let hasInput = useMetric ? !heightCmInput.isEmpty : (!heightFeetInput.isEmpty && !heightInchesInput.isEmpty)
        guard hasInput else { return nil }
        guard let cm = parsedHeightCm, OnboardingProfileRules.isValidHeight(cm: cm) else {
            return "Check your height. It looks outside the range MyFitPlate supports."
        }
        return nil
    }

    private func weightHint(for input: String) -> String? {
        guard !input.isEmpty else { return nil }
        guard let lbs = parsedWeightLbs(input), OnboardingProfileRules.isValidWeight(lbs: lbs) else {
            return "Check this weight. It looks outside the range MyFitPlate supports."
        }
        return nil
    }

    private var targetWeightHint: String? {
        if let rangeHint = weightHint(for: targetWeightInput) { return rangeHint }
        guard let goal = selectedGoal,
              let current = parsedWeightLbs(currentWeightInput),
              let target = parsedWeightLbs(targetWeightInput),
              !OnboardingProfileRules.targetMatchesGoal(goal, currentWeightLbs: current, targetWeightLbs: target) else {
            return nil
        }
        switch goal {
        case .lose:
            return "To lose weight, choose a target below your current weight."
        case .gain:
            return "To gain weight, choose a target above your current weight."
        case .maintain:
            return nil
        }
    }

    // MARK: - Parsing

    private var parsedAge: Int? {
        Int(ageInput.trimmingCharacters(in: .whitespaces))
    }

    private var parsedHeightCm: Double? {
        if useMetric {
            return Self.number(from: heightCmInput)
        }
        guard let feet = Int(heightFeetInput), feet > 0,
              let inches = Int(heightInchesInput), (0..<12).contains(inches) else { return nil }
        return BodyUnits.cm(feet: feet, inches: inches)
    }

    private func parsedWeightLbs(_ input: String) -> Double? {
        guard let value = Self.number(from: input), value > 0 else { return nil }
        return BodyUnits.weightToLbs(value, metric: useMetric)
    }

    private func makeDraft() -> OnboardingProfileDraft? {
        guard let goal = selectedGoal,
              let sex = selectedSex,
              let age = parsedAge,
              let heightCm = parsedHeightCm,
              let currentWeight = parsedWeightLbs(currentWeightInput),
              let activityKey = selectedActivityLevelKey,
              let activityMultiplier = Self.activityLevelMap[activityKey] else { return nil }
        let targetWeight = goal == .maintain ? currentWeight : parsedWeightLbs(targetWeightInput)
        guard let targetWeight else { return nil }

        let draft = OnboardingProfileDraft(
            goal: goal,
            trainingIntent: selectedTrainingIntent,
            sex: sex,
            age: age,
            heightCm: heightCm,
            currentWeightLbs: currentWeight,
            targetWeightLbs: targetWeight,
            activityMultiplier: activityMultiplier,
            reminderStyle: reminderStyle,
            maiaTone: maiaTone
        )
        return draft.isComplete ? draft : nil
    }

    private func firstIncompleteStep() -> Step {
        visibleSteps.first { !isValid($0) } ?? visibleSteps.first ?? .goal
    }

    private func convertInputs(toMetric metric: Bool) {
        if metric {
            if let feet = Int(heightFeetInput), let inches = Int(heightInchesInput), (0..<12).contains(inches) {
                heightCmInput = Self.inputString(BodyUnits.cm(feet: feet, inches: inches).rounded())
            }
        } else if let cm = Self.number(from: heightCmInput) {
            let imperial = Self.feetAndInches(fromCm: cm)
            heightFeetInput = String(imperial.feet)
            heightInchesInput = String(imperial.inches)
        }

        currentWeightInput = Self.convertedWeightInput(currentWeightInput, toMetric: metric)
        targetWeightInput = Self.convertedWeightInput(targetWeightInput, toMetric: metric)
    }

    private static func convertedWeightInput(_ input: String, toMetric metric: Bool) -> String {
        guard let value = number(from: input) else { return input }
        let lbs = BodyUnits.weightToLbs(value, metric: !metric)
        return inputString(BodyUnits.weightDisplayValue(lbs: lbs, metric: metric))
    }

    /// Accepts either decimal separator so a comma keypad works too.
    private static func number(from input: String) -> Double? {
        Double(input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func inputString(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    private static func feetAndInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / BodyUnits.cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
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

private struct OnboardingChoiceRow: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                if let icon {
                    Image(systemName: icon)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brandText)
                        .frame(width: 40, height: 40)
                        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    if let subtitle {
                        Text(subtitle)
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: AppSpacing.compact)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appTextRole(.control)
                    .foregroundStyle(isSelected ? AppPalette.brandText : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppPalette.brand.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct OnboardingMeasurementField: View {
    let title: String
    @Binding var text: String
    let unit: String
    let keyboard: UIKeyboardType
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
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
                        .accessibilityHint(hint ?? "")

                    Text(unit)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brandText)
                }
            }
            .appSurface(.emphasized)
            .frame(maxWidth: .infinity)

            if let hint {
                OnboardingHint(text: hint)
            }
        }
    }
}

private struct OnboardingHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .appTextRole(.secondary)
            .foregroundStyle(AppPalette.caution)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("onboarding_hint")
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
