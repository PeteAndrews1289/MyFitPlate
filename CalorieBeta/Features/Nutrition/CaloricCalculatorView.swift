import SwiftUI
import MyFitPlateCore
import UIKit

private struct DynamicTypeFieldLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.isAccessibilityElement = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
    }
}

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

struct CaloricCalculatorView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showSaveConfirmation = false
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
        NavigationStack {
            Form {
                personalInfoSection

                Section(header: Text("Weight Goals")) {
                    currentWeightRow
                    targetWeightRow
                }

                Section(header: Text("Daily Calorie Goal")) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        TextField("Calories", text: $calorieInput)
                            .keyboardType(.numberPad)
                            .appTextRole(.metric)
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                            .focused($numericFieldIsFocused)

                        Text("cal")
                            .appTextRole(.control)
                            .foregroundStyle(.secondary)
                    }
                }

                macronutrientSection
                citationSection
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Calorie & Macro Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numericFieldIsFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Goals") {
                    numericFieldIsFocused = false
                    saveCaloricGoal()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(Double(calorieInput) == nil)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("settings_goals_save")
            }
            .onAppear(perform: fetchAndSetGoals)
            .alert(isPresented: $showSaveConfirmation) {
                Alert(
                    title: Text("Goals saved"),
                    message: Text("Your nutrition goals are updated."),
                    dismissButton: .default(Text("OK")) { dismiss() }
                )
            }
            .onChange(of: goalSettings.activityLevel) { _, newLevel in
                let newString = activityString(for: newLevel)
                if selectedActivityString != newString {
                    selectedActivityString = newString
                }
                goalSettings.recalculateAllGoals()
            }
            .onChange(of: goalSettings.goal) { _, newGoal in
                if goals.contains(newGoal) && selectedGoal != newGoal {
                    selectedGoal = newGoal
                }
                goalSettings.recalculateAllGoals()
            }
            .onChange(of: goalSettings.age) {
                if goalSettings.calorieGoalMethod == .custom {
                    goalSettings.calorieGoalMethod = .mifflinWithActivity
                }
                goalSettings.recalculateAllGoals()
            }
            .onChange(of: goalSettings.gender) {
                if goalSettings.calorieGoalMethod == .custom {
                    goalSettings.calorieGoalMethod = .mifflinWithActivity
                }
                goalSettings.recalculateAllGoals()
            }
            .onChange(of: goalSettings.proteinPercentage) { goalSettings.recalculateAllGoals() }
            .onChange(of: goalSettings.carbsPercentage) { goalSettings.recalculateAllGoals() }
            .onChange(of: goalSettings.fatsPercentage) { goalSettings.recalculateAllGoals() }
            .onChange(of: goalSettings.calories) { _, newRecommendedCalories in
                if Double(calorieInput) != newRecommendedCalories {
                    calorieInput = String(format: "%.0f", newRecommendedCalories ?? 0)
                }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
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
                DynamicTypeFieldLabel(text: "Age")
                ageField
            }
        } else {
            HStack(spacing: AppSpacing.group) {
                DynamicTypeFieldLabel(text: "Age")
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
        Section(header: Text("Your Information")) {
            ageRow

            GenderButtonPicker(selectedGender: $goalSettings.gender)
                .padding(.vertical, 5)

             Picker("Activity level", selection: $selectedActivityString) {
                 ForEach(activityLevelStrings, id: \.self) { levelString in
                     Text(levelString).tag(levelString)
                 }
             }
            .onChange(of: selectedActivityString) { _, newValue in
                if let index = activityLevelStrings.firstIndex(of: newValue) {
                    if goalSettings.activityLevel != activityLevelValues[index],
                       goalSettings.calorieGoalMethod == .custom {
                        goalSettings.calorieGoalMethod = .mifflinWithActivity
                    }
                    goalSettings.activityLevel = activityLevelValues[index]
                }
            }

            Picker("Goal", selection: $selectedGoal) {
                ForEach(goals, id: \.self) { goal in
                    Text(goal).tag(goal)
                }
            }
            .onChange(of: selectedGoal) { _, newValue in
                if goalSettings.goal != newValue,
                   goalSettings.calorieGoalMethod == .custom {
                    goalSettings.calorieGoalMethod = .mifflinWithActivity
                }
                goalSettings.goal = newValue
            }
        }
    }

    private var macronutrientSection: some View {
        Section(header: Text("Macronutrient Distribution")) {
            VStack(spacing: 15) {
                macroSlider(title: "Protein", value: $goalSettings.proteinPercentage, color: .accentProtein)
                macroSlider(title: "Carbs", value: $goalSettings.carbsPercentage, color: .accentCarbs)
                macroSlider(title: "Fat", value: $goalSettings.fatsPercentage, color: .accentFats)
            }
             .padding(.vertical, 5)
        }
    }
    
    private var citationSection: some View {
        Section(header: Text("Source Information"), footer: Text("Calorie and macronutrient recommendations are estimates for informational purposes. Your actual nutritional needs may vary. Consult with a healthcare professional before making significant changes to your diet or exercise routine.")) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Calorie goals are estimated using the Mifflin-St Jeor equation combined with standard activity level multipliers.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                
                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                    Link("Source: A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.", destination: url)
                        .appTextRole(.secondary)
                }
            }
            .padding(.vertical, 5)
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
        // goalSettings is already loaded app-wide; re-loading it here on every appear re-ran the
        // full @Published assignment churn and could recompute the goal from partially-loaded
        // state. Seed the local fields from what's already loaded so opening this screen is
        // read-only for the model — nothing changes unless the user edits and taps Save.
        calorieInput = String(format: "%.0f", goalSettings.calories ?? 0)
        if let targetWeight = goalSettings.targetWeight {
            targetWeightInput = String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: targetWeight, metric: useMetric))
        }
        selectedActivityString = activityString(for: goalSettings.activityLevel)
        selectedGoal = goals.contains(goalSettings.goal) ? goalSettings.goal : "Maintain"
    }
    
    private func saveCaloricGoal() {
        guard let userID = DIContainer.shared.authService.currentUserID,
              let calorieValue = Double(calorieInput) else {
            return
        }
        
        let bmr = GoalSettingsRules.calculateBMR(age: goalSettings.age, weightKg: goalSettings.weight * 0.453592, heightCm: goalSettings.height, gender: goalSettings.gender)
        let manualBurn = goalSettings.dailyLogService?.currentDailyLog?.totalCaloriesBurnedFromManualExercises() ?? 0
        let mifflinCalories = GoalSettingsRules.calculateCalorieGoal(
            bmr: bmr,
            goal: goalSettings.goal,
            gender: goalSettings.gender,
            calorieGoalMethod: .mifflinWithActivity,
            activityLevel: goalSettings.activityLevel,
            adaptiveTDEE: goalSettings.adaptiveGoalService?.calculatedTDEE,
            manualCaloriesBurned: manualBurn,
            currentCalories: nil
        )
        if abs(calorieValue - mifflinCalories) <= 5 {
            goalSettings.calorieGoalMethod = .mifflinWithActivity
        } else {
            goalSettings.calorieGoalMethod = .custom
        }
        let minimumGoal: Double = (goalSettings.gender.lowercased() == "male") ? 1500 : 1200
        let clampedCalories = max(minimumGoal, calorieValue)
        goalSettings.calories = clampedCalories
        if let targetWeightValue = Double(targetWeightInput) {
            goalSettings.targetWeight = BodyUnits.weightToLbs(targetWeightValue, metric: useMetric)
        }
        
        goalSettings.recalculateAllGoals()
        goalSettings.saveUserGoals(userID: userID)
        
        showSaveConfirmation = true
    }
}
