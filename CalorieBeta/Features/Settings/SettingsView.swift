import SwiftUI
import MyFitPlateCore

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
    @AppStorage(TrainingFuelNotificationPreferenceKey.preSessionEnabled) private var preSessionFuelRemindersEnabled = false
    @AppStorage(TrainingFuelNotificationPreferenceKey.recoveryEnabled) private var recoveryFuelRemindersEnabled = false
    @AppStorage(TrainingFuelNotificationPreferenceKey.eveningCatchUpEnabled) private var eveningProteinRemindersEnabled = false
    @AppStorage(TrainingFuelNotificationPreferenceKey.quietStartMinutes) private var trainingFuelQuietStartMinutes = 22 * 60
    @AppStorage(TrainingFuelNotificationPreferenceKey.quietEndMinutes) private var trainingFuelQuietEndMinutes = 7 * 60
    @AppStorage(TrainingFuelNotificationPreferenceKey.eveningMinutes) private var eveningProteinReminderMinutes = 19 * 60 + 30

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

    private var trainingFuelQuietStartBinding: Binding<Date> {
        minuteOfDayBinding(
            get: { trainingFuelQuietStartMinutes },
            set: { trainingFuelQuietStartMinutes = $0 }
        )
    }

    private var trainingFuelQuietEndBinding: Binding<Date> {
        minuteOfDayBinding(
            get: { trainingFuelQuietEndMinutes },
            set: { trainingFuelQuietEndMinutes = $0 }
        )
    }

    private var eveningProteinReminderBinding: Binding<Date> {
        minuteOfDayBinding(
            get: { eveningProteinReminderMinutes },
            set: { eveningProteinReminderMinutes = $0 }
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
    @State private var showingAIDataConsent = false
    @State private var didPresentScreenshotDestination = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.section) {
                SettingsHeaderCard(
                    calorieGoal: goalSettings.calories,
                    waterGoal: goalSettings.waterGoal,
                    heightText: useMetricBodyUnits ? "\(Int(goalSettings.height.rounded())) cm" : "\(goalSettings.getHeightInFeetAndInches().feet)'\(goalSettings.getHeightInFeetAndInches().inches)\""
                )

                SettingsAccountSection(
                    showCaloricCalculator: $showCaloricCalculator,
                    feetInput: $feetInput,
                    inchesInput: $inchesInput,
                    showHeightEditor: $showHeightEditor,
                    waterGoalInput: $waterGoalInput,
                    showingWaterGoalSheet: $showingWaterGoalSheet
                )

                SettingsAppearanceSection(
                    useMetricBodyUnits: $useMetricBodyUnits
                )

                SettingsPreferencesSection(
                    includeActiveCaloriesInGoal: $includeActiveCaloriesInGoal,
                    hydrationRemindersEnabled: $hydrationRemindersEnabled,
                    weighInReminderEnabled: $weighInReminderEnabled,
                    notificationTimeBinding: notificationTimeBinding,
                    preSessionFuelRemindersEnabled: $preSessionFuelRemindersEnabled,
                    recoveryFuelRemindersEnabled: $recoveryFuelRemindersEnabled,
                    eveningProteinRemindersEnabled: $eveningProteinRemindersEnabled,
                    quietStartBinding: trainingFuelQuietStartBinding,
                    quietEndBinding: trainingFuelQuietEndBinding,
                    eveningProteinTimeBinding: eveningProteinReminderBinding
                )

                SettingsSupportSection(
                    showingHealthDisclaimer: $showingHealthDisclaimer,
                    showingResetTourConfirmation: $showingResetTourConfirmation,
                    showingAIDataConsent: $showingAIDataConsent,
                    showingSignOutAlert: $showingSignOutAlert,
                    showingDeleteAccountAlert: $showingDeleteAccountAlert,
                    isDeletingAccount: isDeletingAccount
                )
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_screen")
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showSettings = false }
            }
        }
        .tint(AppPalette.brand)
        .sheet(isPresented: $showCaloricCalculator) {
            CaloricCalculatorView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showHeightEditor) {
            SetHeightView(feetInput: $feetInput, inchesInput: $inchesInput, onSave: updateHeight)
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingWaterGoalSheet) {
            SetWaterGoalView(waterGoalInput: $waterGoalInput, onSave: updateWaterGoal)
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingHealthDisclaimer) {
            HealthDisclaimerView()
        }
        .sheet(isPresented: $showingAIDataConsent) {
            AIDataConsentSheet()
        }
        .onAppear(perform: presentScreenshotDestinationIfNeeded)
        .alert("Sign out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { appState.signOut() }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete account", isPresented: $showingDeleteAccountAlert) {
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
        .alert("Replay feature tour?", isPresented: $showingResetTourConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replay") {
                // requestReplay() clears the seen flags AND bumps a token the Home tour
                // observes, so it restarts immediately; closing Settings reveals it.
                spotlightManager.requestReplay()
                showSettings = false
            }
        } message: {
            Text("Closes Settings and plays the guided tips again from the Home screen.")
        }
    }

    private func presentScreenshotDestinationIfNeeded() {
        #if DEBUG
        guard ScreenshotDemoMode.isEnabled, !didPresentScreenshotDestination else { return }
        didPresentScreenshotDestination = true

        switch ScreenshotDemoData.requestedScreen {
        case "settings-goals":
            showCaloricCalculator = true
        case "settings-height":
            let currentHeight = goalSettings.getHeightInFeetAndInches()
            feetInput = "\(currentHeight.feet)"
            inchesInput = "\(currentHeight.inches)"
            showHeightEditor = true
        case "settings-water":
            waterGoalInput = "\(Int(goalSettings.waterGoal.rounded()))"
            showingWaterGoalSheet = true
        case "settings-disclaimer":
            showingHealthDisclaimer = true
        case "settings-ai-data":
            showingAIDataConsent = true
        default:
            break
        }
        #endif
    }

    private func minuteOfDayBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: {
                let minutes = get()
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
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
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.accountDeletionStarted.rawValue,
            parameters: nil
        )
        Task {
            do {
                let outcome = try await accountDeletionService.deleteCurrentAccount(password: password)
                await MainActor.run {
                    isDeletingAccount = false
                    DIContainer.shared.analyticsManager?.logEvent(
                        ProductAnalytics.Event.accountDeletionCompleted.rawValue,
                        parameters: nil
                    )
                    clearLocalAccountData(userID: outcome.userID)
                    appState.isUserLoggedIn = false
                    showSettings = false
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteErrorMessage = error.localizedDescription
                    DIContainer.shared.analyticsManager?.logEvent(
                        ProductAnalytics.Event.accountDeletionFailed.rawValue,
                        parameters: [
                            "reason": (error as? AccountDeletionError)?.analyticsReason ?? "unknown"
                        ]
                    )
                }
            }
        }
    }

    private func clearLocalAccountData(userID: String) {
        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        SharedDataManager.shared.clearWidgetData()
    }
}
