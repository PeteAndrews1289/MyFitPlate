import SwiftUI

struct SettingsAccountSection: View {
    @EnvironmentObject var goalSettings: GoalSettings
    
    @Binding var showCaloricCalculator: Bool
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @Binding var showHeightEditor: Bool
    @Binding var waterGoalInput: String
    @Binding var showingWaterGoalSheet: Bool

    var body: some View {
        SettingsSectionCard(title: "Account") {
            Button { showCaloricCalculator = true } label: {
                SettingsLabel(icon: "target", title: "Calorie and macro goals", subtitle: "Adjust targets and goal method.", color: .orange)
            }
            .padding(16)
            
            Divider().padding(.leading, 50)
            
            Button {
                let currentHeight = goalSettings.getHeightInFeetAndInches()
                feetInput = "\(currentHeight.feet)"
                inchesInput = "\(currentHeight.inches)"
                showHeightEditor = true
            } label: {
                SettingsLabel(icon: "ruler", title: "Height", subtitle: "Update your body metrics.", color: .blue)
            }
            .padding(16)
            
            Divider().padding(.leading, 50)
            
            Button {
                waterGoalInput = "\(Int(goalSettings.waterGoal.rounded()))"
                showingWaterGoalSheet = true
            } label: {
                SettingsLabel(icon: "drop.fill", title: "Daily water goal", subtitle: "\(Int(goalSettings.waterGoal.rounded()).formatted()) oz per day.", color: .cyan)
            }
            .padding(16)
            
            Divider().padding(.leading, 50)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Calorie goal method")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                
                Picker("Calorie goal method", selection: $goalSettings.calorieGoalMethod) {
                    ForEach(CalorieGoalMethod.allCases) { method in Text(method.rawValue).tag(method) }
                }
                .pickerStyle(.segmented)
                .onChange(of: goalSettings.calorieGoalMethod) { _, _ in
                    if let userID = DIContainer.shared.authService.currentUserID { goalSettings.saveUserGoals(userID: userID) }
                }
            }
            .padding(16)
        }
    }
}
