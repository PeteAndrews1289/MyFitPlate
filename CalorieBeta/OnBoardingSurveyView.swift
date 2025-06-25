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
    @State private var calorieGoalInput: String = ""
    
    let activityLevels: [String: String] = [
        "Sedentary": "Little to no exercise",
        "Lightly Active": "Light exercise/sports 1-3 days/week",
        "Moderately Active": "Moderate exercise/sports 3-5 days/week",
        "Very Active": "Hard exercise/sports 6-7 days a week",
        "Extremely Active": "Very hard exercise & physical job"
    ]
    let goals = ["Lose", "Maintain", "Gain"]
    private let activityLevelMap: [String: Double] = ["Sedentary": 1.2, "Lightly Active": 1.375, "Moderately Active": 1.55, "Very Active": 1.725, "Extremely Active": 1.9]

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
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
            return !targetWeightInput.isEmpty && (Double(targetWeightInput) ?? 0) > 0
        case 5:
            return !calorieGoalInput.isEmpty && (Double(calorieGoalInput) ?? 0) > 0
        default:
            return false
        }
    }

    var body: some View {
        VStack {
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .padding()
                .tint(Color.accentColor)

            TabView(selection: $currentStep) {
                stepView(title: "What's your age?", subtitle: "Your age helps us calculate your metabolic rate.", iconName: "birthday.cake", content: { ageStepView() }).tag(0)
                stepView(title: "What's your height?", subtitle: "This is used to help determine your energy needs.", iconName: "ruler", content: { heightStepView() }).tag(1)
                stepView(title: "What's your current weight?", subtitle: "This provides a baseline for tracking your progress.", iconName: "scalemass", content: { currentWeightStepView() }).tag(2)
                stepView(title: "Tell us about your lifestyle", subtitle: "This helps us tailor your goals to your daily life.", iconName: "figure.walk.circle", content: { activityAndGoalStepView() }).tag(3)
                stepView(title: "What's your target weight?", subtitle: "Setting a goal is a great first step!", iconName: "flag.checkered.circle", content: { targetWeightStepView() }).tag(4)
                stepView(title: "Your Daily Calorie Goal", subtitle: "We've calculated a recommendation based on your info. Feel free to adjust it.", iconName: "target", content: { calorieGoalStepView() }).tag(5)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
            
            HStack {
                if currentStep > 0 {
                    Button("Back") { withAnimation { currentStep -= 1 } }.padding()
                }
                Spacer()
                Button(currentStep == totalSteps - 1 ? "Finish" : "Next") { saveGoalsAndProceed() }
                    .padding()
                    .disabled(!isCurrentStepValid)
            }
            .padding()
        }
    }
    
    private func updateAndPrefillCalorieGoal() {
        guard let age = Int(ageInput),
              let heightFeet = Int(heightFeetInput),
              let heightInches = Int(heightInchesInput),
              let currentWeight = Double(currentWeightInput) else { return }
        
        goalSettings.age = age
        goalSettings.height = Double((heightFeet * 12) + heightInches) * 2.54
        goalSettings.weight = currentWeight
        goalSettings.gender = selectedGender
        goalSettings.activityLevel = activityLevelMap[selectedActivityLevelKey] ?? 1.2
        goalSettings.goal = selectedGoal
        
        goalSettings.recalculateAllGoals()
        
        self.calorieGoalInput = String(format: "%.0f", goalSettings.calories ?? 2000)
    }

    private func saveGoalsAndProceed() {
        if currentStep < totalSteps - 1 {
            if currentStep == totalSteps - 2 {
                updateAndPrefillCalorieGoal()
            }
            withAnimation {
                currentStep += 1
            }
        } else {
            guard let age = Int(ageInput),
                  let heightFeet = Int(heightFeetInput),
                  let heightInches = Int(heightInchesInput),
                  let currentWeight = Double(currentWeightInput),
                  let targetWeight = Double(targetWeightInput),
                  let finalCalorieGoal = Double(calorieGoalInput) else {
                return
            }
            
            goalSettings.age = age
            goalSettings.height = Double((heightFeet * 12) + heightInches) * 2.54
            goalSettings.targetWeight = targetWeight
            goalSettings.gender = selectedGender
            goalSettings.activityLevel = activityLevelMap[selectedActivityLevelKey] ?? 1.2
            goalSettings.goal = selectedGoal
            
            goalSettings.calories = finalCalorieGoal
            
            goalSettings.recalculateAllGoals()
            
            if let userID = Auth.auth().currentUser?.uid {
                goalSettings.saveUserGoals(userID: userID)
                goalSettings.updateUserWeight(currentWeight)
            }
            onComplete()
        }
    }

    @ViewBuilder
    private func stepView<Content: View>(title: String, subtitle: String, iconName: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: iconName)
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
                    .padding(.bottom, 10)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                content()
                
                Spacer()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func calorieGoalStepView() -> some View {
        VStack(spacing: 15) {
            Text("Recommended Goal")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(String(format: "%.0f", goalSettings.calories ?? 0))
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(Color.accentColor)
            + Text(" kcal/day")
                .font(.title2)
                .foregroundColor(.secondary)

            HStack {
                TextField("Your Goal", text: $calorieGoalInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.center)
                    .font(.title3)
                Text("kcal")
            }
            .frame(width: 220)
            .padding(.top)
        }
        .padding(.top, 20)
    }

    @ViewBuilder private func ageStepView() -> some View { TextField("Age (Years)", text: $ageInput).keyboardType(.numberPad).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 200) }
    @ViewBuilder private func heightStepView() -> some View { HStack { TextField("Feet", text: $heightFeetInput).keyboardType(.numberPad).textFieldStyle(RoundedBorderTextFieldStyle()); Text("ft"); TextField("Inches", text: $heightInchesInput).keyboardType(.numberPad).textFieldStyle(RoundedBorderTextFieldStyle()); Text("in") }.frame(width: 250) }
    @ViewBuilder private func currentWeightStepView() -> some View { HStack { TextField("Weight", text: $currentWeightInput).keyboardType(.decimalPad).textFieldStyle(RoundedBorderTextFieldStyle()); Text("lbs") }.frame(width: 200) }
    @ViewBuilder private func targetWeightStepView() -> some View { HStack { TextField("Target Weight", text: $targetWeightInput).keyboardType(.decimalPad).textFieldStyle(RoundedBorderTextFieldStyle()); Text("lbs") }.frame(width: 200) }
    
    @ViewBuilder
    private func activityAndGoalStepView() -> some View {
        Form {
            Section(header: Text("Biological Sex")) {
                Picker("Gender", selection: $selectedGender) {
                    ForEach(["Male", "Female"], id: \.self) { Text($0) }
                }.pickerStyle(SegmentedPickerStyle())
            }
            Section(header: Text("Activity Level")) {
                Picker("Activity Level", selection: $selectedActivityLevelKey) {
                    ForEach(activityLevels.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading) {
                            Text(key)
                                .font(.headline)
                            Text(activityLevels[key] ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(key)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section(header: Text("Primary Goal")) {
                Picker("Goal", selection: $selectedGoal) {
                    ForEach(goals, id: \.self) { Text($0) }
                }.pickerStyle(SegmentedPickerStyle())
            }
        }
        .frame(minHeight: 400)
    }
}
