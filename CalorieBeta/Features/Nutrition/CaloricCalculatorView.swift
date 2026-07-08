import SwiftUI
struct GenderButtonPicker: View {
    @Binding var selectedGender: String
    let genders = ["🙋‍♂️ Male", "🙋‍♀️ Female"]
    let accentColor = Color.blue

    var body: some View {
        HStack {
            ForEach(genders, id: \.self) { gender in
                Button(action: {
                    selectedGender = gender.contains("Male") ? "Male" : "Female"
                }) {
                    Text(gender)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            (selectedGender == (gender.contains("Male") ? "Male" : "Female")) ?
                                RoundedRectangle(cornerRadius: 20).fill(accentColor.opacity(0.2)) :
                                RoundedRectangle(cornerRadius: 20).fill(Color.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedGender == (gender.contains("Male") ? "Male" : "Female") ? accentColor : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(.textPrimary)
                        .cornerRadius(20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 5)
    }
}

struct CaloricCalculatorView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @State private var showSaveConfirmation = false
    
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
         let nearest = activityLevelValues.enumerated().min {
             abs($0.element - level) < abs($1.element - level)
         }
         return activityLevelStrings[nearest?.offset ?? 0]
     }

    private let goals = ["Lose", "Maintain", "Gain"]
    private let accentColor = Color.blue

    var body: some View {
        Form {
            personalInfoSection
            
            Section(header: Text("Weight goals")) {
                HStack {
                    Text("Current weight")
                    Spacer()
                    TextField(BodyUnits.weightUnit(metric: useMetric), value: Binding(
                        get: { BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric) },
                        set: { goalSettings.weight = BodyUnits.weightToLbs($0, metric: useMetric) }
                    ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                HStack {
                    Text("Target weight")
                    Spacer()
                    TextField(BodyUnits.weightUnit(metric: useMetric), text: $targetWeightInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            
            Section(header: Text("Daily calorie goal")) {
                HStack {
                    TextField("Calories", text: $calorieInput)
                        .keyboardType(.numberPad)
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.orange)
                    
                    Text("cal")
                        .appFont(size: 17)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            
            macronutrientSection

            citationSection

            Button("Save goals") {
                saveCaloricGoal()
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowInsets(EdgeInsets())
            .padding(.vertical)

        }
        .navigationTitle("Calorie calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchAndSetGoals)
        .alert(isPresented: $showSaveConfirmation) {
            Alert(title: Text("Goals saved"), message: Text("Your nutrition goals are updated."), dismissButton: .default(Text("OK")))
        }
        .onChange(of: goalSettings.activityLevel) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.goal) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.age) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.gender) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.proteinPercentage) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.carbsPercentage) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.fatsPercentage) { goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.calories) { _, newRecommendedCalories in
            if Double(calorieInput) != newRecommendedCalories {
                 calorieInput = String(format: "%.0f", newRecommendedCalories ?? 0)
            }
        }
    }

    private var personalInfoSection: some View {
        Section(header: Text("Your information")) {
            HStack {
                Text("Age")
                Spacer()
                TextField("e.g., 25", value: $goalSettings.age, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            GenderButtonPicker(selectedGender: $goalSettings.gender)
                .padding(.vertical, 5)

             Picker("Activity level", selection: $selectedActivityString) {
                 ForEach(activityLevelStrings, id: \.self) { levelString in
                     Text(levelString).tag(levelString)
                 }
             }
            .tint(accentColor)
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
            .tint(accentColor)
            .onChange(of: selectedGoal) { _, newValue in
                goalSettings.goal = newValue
            }
        }
    }

    private var macronutrientSection: some View {
        Section(header: Text("Macronutrient distribution")) {
            VStack(spacing: 15) {
                macroSlider(title: "Protein", value: $goalSettings.proteinPercentage, color: .accentProtein)
                macroSlider(title: "Carbs", value: $goalSettings.carbsPercentage, color: .accentCarbs)
                macroSlider(title: "Fat", value: $goalSettings.fatsPercentage, color: .accentFats)
            }
             .padding(.vertical, 5)
        }
    }
    
    private var citationSection: some View {
        Section(header: Text("Source information"), footer: Text("Calorie and macronutrient recommendations are estimates for informational purposes. Your actual nutritional needs may vary. Consult with a healthcare professional before making significant changes to your diet or exercise routine.")) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Calorie goals are estimated using the Mifflin-St Jeor equation combined with standard activity level multipliers.")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                    Link("Source: A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.", destination: url)
                        .appFont(size: 12)
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
        
        goalSettings.calorieGoalMethod = .custom
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
