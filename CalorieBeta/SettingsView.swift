import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @Binding var showSettings: Bool
    
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showCaloricCalculator = false
    @State private var showHeightEditor = false
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""
    @State private var showingWaterGoalSheet = false
    @State private var waterGoalInput: String = ""

    var body: some View {
        List {
            Section(header: Text("Appearance")) {
                Toggle("Enable Dark Mode", isOn: $appState.isDarkModeEnabled.animation())
            }
            
            Section(header: Text("Integrations")) {
                Button(action: {
                    if healthKitViewModel.isAuthorized {
                        healthKitViewModel.fetchTodayWorkouts()
                    } else {
                        healthKitViewModel.requestAuthorization()
                    }
                }) {
                    HStack {
                        Image("Apple_Health")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        
                        Text(healthKitViewModel.isAuthorized ? "Sync with Health Now" : "Connect to Apple Health")
                        
                        Spacer()
                        
                        if healthKitViewModel.isSyncing {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else if healthKitViewModel.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .foregroundColor(Color(uiColor: .label))
                .disabled(healthKitViewModel.isSyncing)

                if !healthKitViewModel.isAuthorized {
                    if let hkError = healthKitViewModel.authError {
                        Text(hkError)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("Connect to sync workouts and activity.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }

            Section(header: Text("Account")) {
                Button("Set New Calorie/Macro Goals") { showCaloricCalculator = true }
                Button("Set Height") {
                    let currentHeight = goalSettings.getHeightInFeetAndInches()
                    feetInput = "\(currentHeight.feet)"; inchesInput = "\(currentHeight.inches)"
                    showHeightEditor = true
                }
                Button("Set New Daily Water Goal") {
                    waterGoalInput = String(format: "%.0f", goalSettings.waterGoal)
                    showingWaterGoalSheet = true
                }
                Picker("Calorie Goal Method", selection: $goalSettings.calorieGoalMethod) {
                    ForEach(CalorieGoalMethod.allCases) { method in Text(method.rawValue).tag(method) }
                }
                 .onChange(of: goalSettings.calorieGoalMethod) { _ in
                      if let userID = Auth.auth().currentUser?.uid { goalSettings.saveUserGoals(userID: userID) }
                  }
            }
            
            Section(header: Text("About")) {
                NavigationLink("Health Disclaimers & Sources", destination: HealthDisclaimerView())
            }

            Section {
                Button("Sign Out", role: .destructive) { showingSignOutAlert = true }
                Button("Delete Account", role: .destructive) { showingDeleteAccountAlert = true }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showSettings = false } } }
        .sheet(isPresented: $showCaloricCalculator) { CaloricCalculatorView().environmentObject(goalSettings) }
        .sheet(isPresented: $showHeightEditor) { SetHeightView(feetInput: $feetInput, inchesInput: $inchesInput, onSave: {
             if let feet = Int(feetInput), let inches = Int(inchesInput) {
                 goalSettings.setHeight(feet: feet, inches: inches)
                 if let userID = Auth.auth().currentUser?.uid { goalSettings.saveUserGoals(userID: userID) }
             }
             showHeightEditor = false
         }).environmentObject(goalSettings) }
        .sheet(isPresented: $showingWaterGoalSheet) { SetWaterGoalView(waterGoalInput: $waterGoalInput, onSave: {
            if let goalValue = Double(waterGoalInput), goalValue > 0 {
                goalSettings.waterGoal = goalValue
                if let userID = Auth.auth().currentUser?.uid { goalSettings.saveUserGoals(userID: userID) }
                 if var currentLog = goalSettings.dailyLogService?.currentDailyLog {
                    if var waterTracker = currentLog.waterTracker {
                        waterTracker.goalOunces = goalValue
                        currentLog.waterTracker = waterTracker
                    } else {
                        currentLog.waterTracker = WaterTracker(totalOunces: 0, goalOunces: goalValue, date: currentLog.date)
                    }
                    if let userID = Auth.auth().currentUser?.uid { goalSettings.dailyLogService?.updateDailyLog(for: userID, updatedLog: currentLog) }
                }
            }
            showingWaterGoalSheet = false
        }).environmentObject(goalSettings) }
        .alert("Sign Out", isPresented: $showingSignOutAlert, actions: { Button("Cancel", role: .cancel) {}; Button("Sign Out", role: .destructive) { appState.signOut() } }, message: { Text("Are you sure you want to sign out?") })
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert, actions: { Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { deleteUserAccount() } }, message: { Text("Are you sure you want to delete your account? This action cannot be undone.") })
    }

    private func deleteUserAccount() {
    }
}
