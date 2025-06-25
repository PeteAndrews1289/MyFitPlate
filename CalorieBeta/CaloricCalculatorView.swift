import SwiftUI
import Firebase
import FirebaseAuth

struct GenderButtonPicker: View {
    @Binding var selectedGender: String
    let genders = ["🙋‍♂️ Male", "🙋‍♀️ Female"]
    let accentColor = Color(red: 61/255, green: 156/255, blue: 86/255)

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
                                RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedGender == (gender.contains("Male") ? "Male" : "Female") ? accentColor : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(.primary)
                        .cornerRadius(20)
                        .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
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

     private let activityLevelStrings = [
         "Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active"
     ]
     private let activityLevelValues = [1.2, 1.375, 1.55, 1.725, 1.9]

     private var activityLevelSelection: Binding<String> {
         Binding<String>(
             get: {
                 if let index = self.activityLevelValues.firstIndex(of: self.goalSettings.activityLevel) {
                     return self.activityLevelStrings[index]
                 }
                 return self.activityLevelStrings[0]
             },
             set: { newValue in
                 if let index = self.activityLevelStrings.firstIndex(of: newValue) {
                     self.goalSettings.activityLevel = self.activityLevelValues[index]
                 }
             }
         )
     }

    private let goals = ["Lose", "Maintain", "Gain"]
    private let accentColor = Color(red: 61/255, green: 156/255, blue: 86/255)

    var body: some View {
        Form {
            personalInfoSection
            
            Section(header: Text("Daily Calorie Goal")) {
                HStack {
                    TextField("Calories", text: $calorieInput)
                        .keyboardType(.numberPad)
                        .font(.title.weight(.bold))
                        .foregroundColor(accentColor)
                    
                    Text("kcal")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            macronutrientSection

            citationSection

            Button(action: saveCaloricGoal) {
                Text("Save Goals")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .listRowInsets(EdgeInsets())
            .buttonStyle(PlainButtonStyle())

        }
        .navigationTitle("Calorie Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchAndSetCaloricGoal)
        .alert(isPresented: $showSaveConfirmation) {
            Alert(title: Text("Success"), message: Text("Your goals have been saved!"), dismissButton: .default(Text("OK")))
        }
        .onChange(of: goalSettings.activityLevel) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.goal) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.age) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.gender) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.proteinPercentage) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.carbsPercentage) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.fatsPercentage) { _ in goalSettings.recalculateAllGoals() }
        .onChange(of: goalSettings.calories) { newRecommendedCalories in
            // When an automatic recalculation happens, update the text field
            // but only if the user isn't currently typing in it.
            if Double(calorieInput) != newRecommendedCalories {
                 calorieInput = String(format: "%.0f", newRecommendedCalories ?? 0)
            }
        }
    }

    private var personalInfoSection: some View {
        Section(header: Text("Your Information")) {
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

             Picker("Activity Level", selection: activityLevelSelection) {
                 ForEach(activityLevelStrings, id: \.self) { levelString in
                     Text(levelString).tag(levelString)
                 }
             }
            .tint(accentColor)

            Picker("Goal", selection: $goalSettings.goal) {
                ForEach(goals, id: \.self) { goal in
                    Text(goal)
                }
            }
            .tint(accentColor)
        }
    }

    private var macronutrientSection: some View {
        Section(header: Text("Macronutrient Distribution (%)")) {
            VStack(spacing: 15) {
                macroSlider(title: "Protein", value: $goalSettings.proteinPercentage, color: .blue)
                macroSlider(title: "Carbs", value: $goalSettings.carbsPercentage, color: .orange)
                macroSlider(title: "Fats", value: $goalSettings.fatsPercentage, color: .green)
            }
             .padding(.vertical, 5)
        }
    }
    
    private var citationSection: some View {
        Section(header: Text("Source Information"), footer: Text("Calorie and macronutrient recommendations are estimates intended for informational purposes. Your actual nutritional needs may vary. Consult with a healthcare professional before making significant changes to your diet or exercise routine.")) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Calorie goals are estimated using the Mifflin-St Jeor equation combined with standard activity level multipliers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let url = URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/") {
                    Link("Source: A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990.", destination: url)
                        .font(.caption)
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
             .font(.callout)

             Slider(value: value, in: 10...70, step: 5)
                 .tint(color)
         }
     }

    private func fetchAndSetCaloricGoal() {
        guard let userID = Auth.auth().currentUser?.uid else {
            return
        }
        goalSettings.loadUserGoals(userID: userID) {
            self.calorieInput = String(format: "%.0f", self.goalSettings.calories ?? 0)
        }
    }
    
    private func saveCaloricGoal() {
        guard let userID = Auth.auth().currentUser?.uid,
              let calorieValue = Double(calorieInput) else {
            return
        }
        
        goalSettings.calories = calorieValue
        goalSettings.recalculateAllGoals()
        goalSettings.saveUserGoals(userID: userID)
        
        showSaveConfirmation = true
    }
}
