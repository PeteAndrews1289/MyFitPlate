import MyFitPlateCore

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var cycleService: CycleTrackingService
    @EnvironmentObject var recipeService: RecipeService
    
    @AppStorage("includeActiveCaloriesInGoal") var includeActiveCaloriesInGoal: Bool = false
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits: Bool = Locale.current.measurementSystem != .us
    @AppStorage("notificationHour") private var notificationHour: Int = 20
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0
    @AppStorage("hydrationRemindersEnabled") private var hydrationRemindersEnabled: Bool = false
    @AppStorage("weighInReminderEnabled") private var weighInReminderEnabled: Bool = false

    @Binding var showSettings: Bool

    private var notificationTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: notificationHour, minute: notificationMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                notificationHour = components.hour ?? 20
                notificationMinute = components.minute ?? 0
            }
        )
    }
    
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showCaloricCalculator = false
    @State private var showHeightEditor = false
    @State private var feetInput: String = ""
    @State private var inchesInput: String = ""
    @State private var showingWaterGoalSheet = false
    @State private var waterGoalInput: String = ""
    @State private var showingHealthDisclaimer = false
    @State private var showingReauthForDelete = false
    @State private var reauthPassword = ""
    @State private var deleteErrorMessage: String?
    @State private var showingResetTourConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        Group {
        ZStack {
            AnimatedBackgroundView()
            
            ScrollView {
                VStack(spacing: 24) {
                    SettingsHeaderCard(
                        calorieGoal: goalSettings.calories,
                        waterGoal: goalSettings.waterGoal,
                        heightText: useMetricBodyUnits ? "\(Int(goalSettings.height.rounded())) cm" : "\(goalSettings.getHeightInFeetAndInches().feet)'\(goalSettings.getHeightInFeetAndInches().inches)\""
                    )

                    SettingsAppearanceSection(
                        useMetricBodyUnits: $useMetricBodyUnits
                    )
                    
                    SettingsPreferencesSection(
                        includeActiveCaloriesInGoal: $includeActiveCaloriesInGoal,
                        hydrationRemindersEnabled: $hydrationRemindersEnabled,
                        weighInReminderEnabled: $weighInReminderEnabled,
                        notificationTimeBinding: notificationTimeBinding
                    )

                    SettingsAccountSection(
                        showCaloricCalculator: $showCaloricCalculator,
                        feetInput: $feetInput,
                        inchesInput: $inchesInput,
                        showHeightEditor: $showHeightEditor,
                        waterGoalInput: $waterGoalInput,
                        showingWaterGoalSheet: $showingWaterGoalSheet
                    )
                    
                    SettingsSupportSection(
                        showingHealthDisclaimer: $showingHealthDisclaimer,
                        showingResetTourConfirmation: $showingResetTourConfirmation,
                        showingSignOutAlert: $showingSignOutAlert,
                        showingDeleteAccountAlert: $showingDeleteAccountAlert,
                        isDeletingAccount: isDeletingAccount
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showSettings = false } } }
        .tint(.brandPrimary)
        // Sheets
        .sheet(isPresented: $showCaloricCalculator) { CaloricCalculatorView().environmentObject(goalSettings) }
        .sheet(isPresented: $showHeightEditor) { 
            SetHeightView(feetInput: $feetInput, inchesInput: $inchesInput, onSave: updateHeight)
                .environmentObject(goalSettings) 
        }
        .sheet(isPresented: $showingWaterGoalSheet) { 
            SetWaterGoalView(waterGoalInput: $waterGoalInput, onSave: updateWaterGoal)
                .environmentObject(goalSettings) 
        }
        .sheet(isPresented: $showingHealthDisclaimer) {
            NavigationView {
                HealthDisclaimerView()
            }
        }
        }
        // Alerts
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { appState.signOut() }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { DispatchQueue.main.async { showingReauthForDelete = true } }
        } message: {
            Text("Are you sure you want to delete your account? This will permanently delete your profile, logs, recipes, workouts, and account data. This cannot be undone.")
        }
        .modifier(DeleteAccountAlerts(
            showingReauthForDelete: $showingReauthForDelete,
            reauthPassword: $reauthPassword,
            deleteErrorMessage: $deleteErrorMessage,
            onConfirm: reauthenticateAndDelete
        ))
        .alert("Reset Tooltips?", isPresented: $showingResetTourConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                spotlightManager.resetSpotlights()
            }
        } message: {
            Text("This will reset all the \"Quick Tip\" bubbles throughout the app so you can see them again.")
        }
    }
    
    private func updateHeight() {
        if let feet = Int(feetInput), let inches = Int(inchesInput) {
            goalSettings.setHeight(feet: feet, inches: inches)
            if let userID = DIContainer.shared.authService.currentUserID { goalSettings.saveUserGoals(userID: userID) }
        }
        showHeightEditor = false
    }

    private func updateWaterGoal() {
        if let goalValue = Double(waterGoalInput), goalValue > 0 {
            goalSettings.waterGoal = goalValue
            if let userID = DIContainer.shared.authService.currentUserID { goalSettings.saveUserGoals(userID: userID) }
             if var currentLog = goalSettings.dailyLogService?.currentDailyLog {
                if var waterTracker = currentLog.waterTracker {
                    waterTracker.goalOunces = goalValue
                    currentLog.waterTracker = waterTracker
                } else {
                    currentLog.waterTracker = WaterTracker(totalOunces: 0, goalOunces: goalValue, date: currentLog.date)
                }
                if let userID = DIContainer.shared.authService.currentUserID { dailyLogService.updateDailyLog(for: userID, updatedLog: currentLog) }
            }
        }
        showingWaterGoalSheet = false
    }

    private func reauthenticateAndDelete() {
        guard let accountDeletionService = DIContainer.shared.accountDeletionService else { return }
        let password = reauthPassword
        reauthPassword = ""

        isDeletingAccount = true
        Task {
            do {
                let outcome = try await accountDeletionService.deleteCurrentAccount(password: password)
                await MainActor.run {
                    isDeletingAccount = false
                    clearLocalAccountData(userID: outcome.userID)
                    appState.isUserLoggedIn = false
                    showSettings = false
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func clearLocalAccountData(userID: String) {
        spotlightManager.resetSpotlights()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "recentFoods_\(userID)")
        defaults.removeObject(forKey: "chatHistory_\(userID)")
        defaults.removeObject(forKey: "mealPlanCache")
        defaults.removeObject(forKey: "cycleSettings")
        defaults.removeObject(forKey: "lastPeriodStartDate")
        defaults.removeObject(forKey: "pinnedExerciseNotes")
        for key in ["useMetricBodyUnits", "hydrationRemindersEnabled", "weighInReminderEnabled",
                    "notificationHour", "notificationMinute", "includeActiveCaloriesInGoal",
                    "isAutoRestTimerEnabled"] {
            defaults.removeObject(forKey: key)
        }
        SharedDataManager.shared.clearWidgetData()
    }
}
