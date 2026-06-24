import SwiftUI
import FirebaseAuth

struct OnboardingSurveyView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    var onComplete: () -> Void

    @State private var currentStep = 0
    let totalSteps = 6

    @State private var ageInput: String = ""
    @State private var heightFeetInput: String = ""
    @State private var heightInchesInput: String = ""
    @State private var currentWeightInput: String = ""
    @State private var targetWeightInput: String = ""
    @State private var selectedGender: String = "Male"
    @State private var selectedActivityLevelKey: String = "Sedentary"
    @State private var selectedGoal: String = "Lose"
    @State private var selectedTrainingIntent: String = "General Fitness"
    @State private var selectedReminderStyle: String = "Gentle"
    @State private var selectedMaiaTone: String = "Balanced"
    
    let activityLevels: [String: String] = [
        "Sedentary": "Little to no exercise",
        "Lightly Active": "Light exercise/sports 1-3 days/week",
        "Moderately Active": "Moderate exercise/sports 3-5 days/week",
        "Very Active": "Hard exercise/sports 6-7 days a week",
        "Extremely Active": "Very hard exercise & physical job"
    ]
    let goals = ["Lose", "Maintain", "Gain"]
    let trainingIntents = ["General Fitness", "Strength", "Muscle Gain", "Fat Loss"]
    let reminderStyles = ["Gentle", "Direct", "Minimal"]
    let maiaTones = ["Balanced", "Coach", "Analyst"]
    private let activityLevelMap: [String: Double] = ["Sedentary": 1.2, "Lightly Active": 1.375, "Moderately Active": 1.55, "Very Active": 1.725, "Extremely Active": 1.9]
    private let activityLevelOrder = ["Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active"]

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    private var progressValue: Double {
        Double(currentStep + 1) / Double(totalSteps)
    }

    private var isCurrentStepValid: Bool {
        switch currentStep {
        case 0:
            return !ageInput.isEmpty && (Int(ageInput) ?? 0) > 0
        case 1:
            return !heightFeetInput.isEmpty && (Int(heightFeetInput) ?? 0) >= 0 &&
                   !heightInchesInput.isEmpty && (Int(heightInchesInput) ?? 0) >= 0 && (Int(heightInchesInput) ?? 0) < 12
        case 2:
            return !currentWeightInput.isEmpty && (Double(currentWeightInput) ?? 0) > 0
        case 3:
            return true
        case 4:
            return true
        case 5:
            return !targetWeightInput.isEmpty && (Double(targetWeightInput) ?? 0) > 0
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personal Setup")
                                .appFont(size: 22, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text("Step \(currentStep + 1) of \(totalSteps)")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(.brandPrimary)
                        }

                        Spacer()

                    }

                    ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                        .tint(Color.brandPrimary)
                }
                .padding(18)
                .background(.ultraThinMaterial)

                TabView(selection: $currentStep) {
                    stepView(title: "What's your age?", subtitle: "Your age helps us calculate your metabolic rate.", iconName: "birthday.cake", content: { ageStepView() }).tag(0)
                    stepView(title: "What's your height?", subtitle: "This is used to help determine your energy needs.", iconName: "ruler", content: { heightStepView() }).tag(1)
                    stepView(title: "What's your current weight?", subtitle: "This provides a baseline for tracking your progress.", iconName: "scalemass", content: { currentWeightStepView() }).tag(2)
                    stepView(title: "Tell us about your lifestyle", subtitle: "This helps us tailor your goals to your daily life.", iconName: "figure.walk.circle", content: { activityAndGoalStepView() }).tag(3)
                    stepView(title: "How should MyFitPlate coach you?", subtitle: "These preferences tune training, reminders, and Maia's style.", iconName: "slider.horizontal.3", content: { coachingPreferencesStepView() }).tag(4)
                    stepView(title: "What's your target weight?", subtitle: "Setting a goal is a great first step.", iconName: "flag.checkered.circle", content: { targetWeightStepView() }).tag(5)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Back") {
                            hideKeyboard()
                            withAnimation { currentStep -= 1 }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button(currentStep == totalSteps - 1 ? "Finish Setup" : "Next") {
                        hideKeyboard()
                        saveGoalsAndProceed()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isCurrentStepValid)
                }
                .padding(18)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func saveGoalsAndProceed() {
        if currentStep < totalSteps - 1 {
            withAnimation {
                currentStep += 1
            }
        } else {
            guard let age = Int(ageInput), age > 0,
                  let heightFeet = Int(heightFeetInput),
                  let heightInches = Int(heightInchesInput),
                  let currentWeight = Double(currentWeightInput), currentWeight > 0,
                  let targetWeight = Double(targetWeightInput), targetWeight > 0 else {
                // A required step was skipped (the paged TabView lets users swipe past the
                // disabled Next button). Jump back to the first incomplete step instead of
                // silently doing nothing, which made "Finish Setup" look broken.
                withAnimation { currentStep = firstIncompleteStep() }
                return
            }
            
            goalSettings.age = age
            goalSettings.height = Double((heightFeet * 12) + heightInches) * 2.54
            goalSettings.targetWeight = targetWeight
            goalSettings.gender = selectedGender
            goalSettings.activityLevel = activityLevelMap[selectedActivityLevelKey] ?? 1.2
            goalSettings.goal = selectedGoal
            goalSettings.trainingIntent = selectedTrainingIntent
            goalSettings.reminderStyle = selectedReminderStyle
            goalSettings.maiaTone = selectedMaiaTone

            goalSettings.recalculateAllGoals()
            
            if let userID = Auth.auth().currentUser?.uid {
                goalSettings.saveUserGoals(userID: userID)
                goalSettings.updateUserWeight(currentWeight)
            }
            onComplete()
        }
    }

    private func firstIncompleteStep() -> Int {
        if ageInput.isEmpty || (Int(ageInput) ?? 0) <= 0 { return 0 }
        if heightFeetInput.isEmpty || heightInchesInput.isEmpty { return 1 }
        if currentWeightInput.isEmpty || (Double(currentWeightInput) ?? 0) <= 0 { return 2 }
        if targetWeightInput.isEmpty || (Double(targetWeightInput) ?? 0) <= 0 { return 5 }
        return 0
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private func stepView<Content: View>(title: String, subtitle: String, iconName: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 72, height: 72)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())
                    .padding(.top, 18)

                Text(title)
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .appFont(size: 15)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .asCard()
            .padding(20)
        }
    }

    @ViewBuilder
    private func ageStepView() -> some View {
        onboardingInputField(title: "Age", text: $ageInput, unit: "years", keyboard: .numberPad)
    }

    @ViewBuilder
    private func heightStepView() -> some View {
        HStack(spacing: 12) {
            onboardingInputField(title: "Feet", text: $heightFeetInput, unit: "ft", keyboard: .numberPad)
            onboardingInputField(title: "Inches", text: $heightInchesInput, unit: "in", keyboard: .numberPad)
        }
    }

    @ViewBuilder
    private func currentWeightStepView() -> some View {
        onboardingInputField(title: "Current Weight", text: $currentWeightInput, unit: "lbs", keyboard: .decimalPad)
    }

    @ViewBuilder
    private func targetWeightStepView() -> some View {
        onboardingInputField(title: "Target Weight", text: $targetWeightInput, unit: "lbs", keyboard: .decimalPad)
    }

    private func onboardingInputField(title: String, text: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack {
                TextField("0", text: text)
                    .keyboardType(keyboard)
                    .appFont(size: 24, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(unit)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            }
            .padding(14)
            .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func activityAndGoalStepView() -> some View {
        VStack(spacing: 20) {
            Text("Biological Sex")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
            
            GenderButtonPicker(selectedGender: $selectedGender)

            Text("Activity Level")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 10) {
                ForEach(activityLevelOrder, id: \.self) { key in
                    Button {
                        selectedActivityLevelKey = key
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .appFont(size: 15, weight: .bold)
                                    .foregroundColor(.textPrimary)
                                Text(activityLevels[key] ?? "")
                                    .appFont(size: 12)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: selectedActivityLevelKey == key ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedActivityLevelKey == key ? .brandPrimary : Color(UIColor.tertiaryLabel))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            (selectedActivityLevelKey == key ? Color.brandPrimary.opacity(0.12) : Color.backgroundSecondary.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedActivityLevelKey == key ? Color.brandPrimary.opacity(0.55) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Primary Goal")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Picker("Goal", selection: $selectedGoal) {
                ForEach(goals, id: \.self) { Text($0) }
            }.pickerStyle(SegmentedPickerStyle())
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func coachingPreferencesStepView() -> some View {
        VStack(spacing: 18) {
            onboardingChoiceSection(title: "Training Intent", selection: $selectedTrainingIntent, options: trainingIntents, shortLabels: ["General Fitness": "Fitness", "Muscle Gain": "Muscle"])
            onboardingChoiceSection(title: "Reminder Style", selection: $selectedReminderStyle, options: reminderStyles)
            onboardingChoiceSection(title: "Maia Style", selection: $selectedMaiaTone, options: maiaTones)
        }
        .padding(.top, 4)
    }

    private func onboardingChoiceSection(title: String, selection: Binding<String>, options: [String], shortLabels: [String: String] = [:]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(shortLabels[option] ?? option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
