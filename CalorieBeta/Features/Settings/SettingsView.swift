import SwiftUI
import MyFitPlateCore
import MyFitPlateShared

@MainActor
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
    @AppStorage("liftingEffortMetric") private var liftingEffortMetric = "rpe"
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
    @State private var showingFoodPreferences = false
    @State private var didPresentScreenshotDestination = false
    @State private var selectedCategory: SettingsCategory?
    @State private var searchQuery = ""

    private var healthSummary: String {
        if !healthKitViewModel.isHealthDataAvailable { return "Unavailable on this device" }
        if let synced = healthKitViewModel.lastSyncedAt { return "Last read " + synced.formatted(date: .abbreviated, time: .shortened) }
        return healthKitViewModel.isAuthorized ? "No Health data read yet" : "Set up Apple Health"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.section) {
                if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsSectionCard(title: "Personalize") {
                    categoryRow(.goals, value: goalSettings.calories.map { "\(Int($0.rounded()).formatted()) cal · \(goalSettings.calorieGoalMethod.rawValue)" } ?? "Set your calorie and macro targets")
                    Divider().padding(.leading, 64)
                    Button { showingFoodPreferences = true } label: {
                        SettingsLabel(icon: "fork.knife", title: "Food preferences",
                            subtitle: "Allergies, dietary preferences and suggestions", showsDisclosure: true)
                            .padding(AppSpacing.group)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings_food_preferences")
                    Divider().padding(.leading, 64)
                    categoryRow(.appearance, value: "\(appState.isDarkModeEnabled ? "Dark" : "Light") · \(useMetricBodyUnits ? "Metric units" : "US units")")
                }

                SettingsSectionCard(title: "Your experience") {
                    categoryRow(.health, value: healthSummary)
                    Divider().padding(.leading, 64)
                    categoryRow(.notifications, value: "Personal schedules · quiet hours · history")
                    Divider().padding(.leading, 64)
                    categoryRow(.training, value: "\(liftingEffortMetric.uppercased()) · set effort")
                    Divider().padding(.leading, 64)
                    categoryRow(.maia, value: "\(goalSettings.maiaTone) · tone and spoken voice")
                }

                SettingsSectionCard(title: "Account & support") {
                    categoryRow(.data, value: "Export your records or import a food diary")
                    Divider().padding(.leading, 64)
                    categoryRow(.support, value: "Help, privacy, AI sharing and account access")
                }
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_screen")
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: "Find a setting")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showSettings = false }
                    .disabled(isDeletingAccount)
            }
        }
        .tint(AppPalette.brandText)
        .navigationDestination(item: $selectedCategory) { category in
            categoryPage(category)
        }
        .interactiveDismissDisabled(isDeletingAccount)
        .sheet(isPresented: $showCaloricCalculator) {
            CaloricCalculatorView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showHeightEditor) {
            SetHeightView(feetInput: $feetInput, inchesInput: $inchesInput, onAccepted: { showHeightEditor = false })
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingWaterGoalSheet) {
            SetWaterGoalView(waterGoalInput: $waterGoalInput, onAccepted: { showingWaterGoalSheet = false })
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingHealthDisclaimer) {
            HealthDisclaimerView()
        }
        .sheet(isPresented: $showingAIDataConsent) {
            AIDataConsentSheet()
        }
        .sheet(isPresented: $showingFoodPreferences) {
            SuggestionPreferencesView(goalSettings: goalSettings)
        }
        .onAppear(perform: presentScreenshotDestinationIfNeeded)
        .alert("Sign out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { appState.signOut() }
        } message: {
            Text("This signs out on this iPhone and clears account details from widgets and Apple Watch. Your cloud data stays saved and returns when you sign in again.")
        }
        .alert("Delete account", isPresented: $showingDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if usesSignInWithApple {
                    // Let the alert finish dismissing before Apple's sheet presents.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirmWithAppleAndDelete() }
                } else {
                    DispatchQueue.main.async { showingReauthForDelete = true }
                }
            }
        } message: {
            usesSignInWithApple
                ? Text("After you confirm with Apple, MyFitPlate will permanently remove your profile, logs, recipes, workouts, cloud data, and sign-in. Keep the app open until deletion finishes. This cannot be undone.")
                : Text("After password confirmation, MyFitPlate will permanently remove your profile, logs, recipes, workouts, cloud data, and sign-in. Keep the app open until deletion finishes. This cannot be undone.")
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

    private var searchResults: some View {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcuts = SettingsShortcut.allCases.filter { $0.searchTerms.localizedCaseInsensitiveContains(query) }
        let categories = SettingsCategory.allCases.filter { $0.searchTerms.localizedCaseInsensitiveContains(query) }
        return VStack(spacing: AppSpacing.section) {
            if !shortcuts.isEmpty {
                SettingsSectionCard(title: "Quick access") {
                    ForEach(shortcuts) { shortcut in
                        Button { openShortcut(shortcut) } label: {
                            SettingsLabel(icon: shortcut.icon, title: shortcut.title, showsDisclosure: true)
                                .padding(AppSpacing.group)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings_search_\(shortcut.rawValue)")
                        if shortcut != shortcuts.last { Divider().padding(.leading, 64) }
                    }
                }
            }
            if !categories.isEmpty {
                SettingsSectionCard(title: "Settings") {
                    ForEach(categories) { category in
                        categoryRow(category, value: category.summary)
                        if category != categories.last { Divider().padding(.leading, 64) }
                    }
                }
            }
            if shortcuts.isEmpty && categories.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func openShortcut(_ shortcut: SettingsShortcut) {
        switch shortcut {
        case .calories: showCaloricCalculator = true
        case .height:
            let current = goalSettings.getHeightInFeetAndInches()
            feetInput = "\(current.feet)"; inchesInput = "\(current.inches)"; showHeightEditor = true
        case .water:
            waterGoalInput = "\(Int(goalSettings.waterGoal.rounded()))"; showingWaterGoalSheet = true
        case .food: showingFoodPreferences = true
        case .ai: showingAIDataConsent = true
        case .guidance: showingHealthDisclaimer = true
        }
    }

    private func categoryRow(_ category: SettingsCategory, value: String) -> some View {
        Button { selectedCategory = category } label: {
            SettingsLabel(icon: category.icon, title: category.title, subtitle: value, showsDisclosure: true)
                .padding(AppSpacing.group)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings_open_\(category.rawValue)")
    }

    private func categoryPage(_ category: SettingsCategory) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                categoryContent(category)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings_category_\(category.rawValue)")
    }

    private func categoryContent(_ category: SettingsCategory) -> AnyView {
        switch category {
        case .goals, .data:
            return AnyView(SettingsAccountSection(
                scope: category == .goals ? .goals : .data,
                showCaloricCalculator: $showCaloricCalculator,
                feetInput: $feetInput, inchesInput: $inchesInput,
                showHeightEditor: $showHeightEditor,
                waterGoalInput: $waterGoalInput,
                showingWaterGoalSheet: $showingWaterGoalSheet
            ))
        case .appearance:
            return AnyView(SettingsAppearanceSection(useMetricBodyUnits: $useMetricBodyUnits))
        case .health: return AnyView(preferences(.integrations))
        case .notifications: return AnyView(preferences(.notifications))
        case .training: return AnyView(preferences(.training))
        case .maia: return AnyView(preferences(.maia))
        case .support:
            return AnyView(SettingsSupportSection(
                showingHealthDisclaimer: $showingHealthDisclaimer,
                showingResetTourConfirmation: $showingResetTourConfirmation,
                showingAIDataConsent: $showingAIDataConsent,
                showingSignOutAlert: $showingSignOutAlert,
                showingDeleteAccountAlert: $showingDeleteAccountAlert,
                isDeletingAccount: isDeletingAccount
            ))
        }
    }

    private func preferences(_ section: SettingsPreferenceSection) -> some View {
        SettingsPreferencesSection(
            section: section,
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
    }

    private func presentScreenshotDestinationIfNeeded() {
        #if DEBUG
        guard ScreenshotDemoMode.isEnabled, !didPresentScreenshotDestination else { return }
        didPresentScreenshotDestination = true

        switch ScreenshotDemoData.requestedScreen {
        case "settings-import", "settings-import-preview", "settings-import-finished", "settings-import-failed", "settings-import-analyzing", "settings-data":
            selectedCategory = .data
        case "settings-appearance": selectedCategory = .appearance
        case "settings-health": selectedCategory = .health
        case "settings-reminders", "settings-reminder-editor", "settings-reminder-history": selectedCategory = .notifications
        case "settings-training": selectedCategory = .training
        case "settings-maia": selectedCategory = .maia
        case "settings-support", "settings-sources", "settings-support-fallback": selectedCategory = .support
        case "settings-search": searchQuery = "water"
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
        case "settings-food-preferences":
            showingFoodPreferences = true
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
    
    private var usesSignInWithApple: Bool {
        DIContainer.shared.authService.currentSignInMethod == .apple
    }

    private func reauthenticateAndDelete() {
        guard let accountDeletionService = DIContainer.shared.accountDeletionService else { return }
        let password = reauthPassword
        reauthPassword = ""

        performAccountDeletion(method: .email) {
            try await accountDeletionService.deleteCurrentAccount(password: password)
        }
    }

    /// Apple accounts have no password; Apple's sheet confirms the deletion and supplies the
    /// single-use code needed to revoke the app's Sign in with Apple token.
    private func confirmWithAppleAndDelete() {
        guard let accountDeletionService = DIContainer.shared.accountDeletionService else { return }

        Task { @MainActor in
            let request = AppleReauthenticationRequest()
            let credential: AppleIDCredential
            do {
                credential = try await request.perform()
            } catch {
                guard !AppleAuthorizationResult.isCancellation(error) else { return }
                deleteErrorMessage = AppleAuthorizationResult.userFacingError(error).localizedDescription
                return
            }

            performAccountDeletion(method: .apple) {
                try await accountDeletionService.deleteCurrentAccount(appleCredential: credential)
            }
        }
    }

    private func performAccountDeletion(
        method: AccountSignInMethod,
        _ deletion: @escaping () async throws -> AccountDeletionOutcome
    ) {
        isDeletingAccount = true
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.accountDeletionStarted.rawValue,
            parameters: nil
        )
        Task {
            do {
                let outcome = try await deletion()
                await MainActor.run {
                    isDeletingAccount = false
                    DIContainer.shared.analyticsManager?.logEvent(
                        ProductAnalytics.Event.accountDeletionCompleted.rawValue,
                        parameters: method == .apple
                            ? ["apple_token": outcome.appleTokenRevocationFailed ? "revocation_failed" : "revoked"]
                            : nil
                    )
                    clearLocalAccountData(userID: outcome.userID)
                    if outcome.appleTokenRevocationFailed {
                        NotificationCenter.default.post(name: .appleSignInRevocationIncomplete, object: outcome.userID)
                    }
                    if DIContainer.shared.authService.currentUserID == nil || DIContainer.shared.authService.currentUserID == outcome.userID {
                        appState.isUserLoggedIn = false
                        showSettings = false
                    }
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteErrorMessage = "\(error.localizedDescription)\n\nNo additional deletion is assumed. Try again, or contact \(MyFitPlateLinks.supportEmailAddress) if the problem continues."
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
        _ = AccountLocalCleanup.attempt(for: userID)
    }
}

private enum SettingsCategory: String, Identifiable, Hashable, CaseIterable {
    case goals, appearance, health, notifications, training, maia, data, support
    var id: String { rawValue }
    var title: String {
        switch self {
        case .goals: return "Goals & body"
        case .appearance: return "Appearance & units"
        case .health: return "Apple Health"
        case .notifications: return "Reminders"
        case .training: return "Training"
        case .maia: return "Maia"
        case .data: return "Import & export"
        case .support: return "Help & account"
        }
    }
    var summary: String {
        switch self {
        case .goals: return "Calories, macros, height and water"
        case .appearance: return "Theme and measurement units"
        case .health: return "Access and activity calories"
        case .notifications: return "Schedules, quiet hours and history"
        case .training: return "Set effort and lifting preferences"
        case .maia: return "Coaching tone and spoken voice"
        case .data: return "Import records or export a copy"
        case .support: return "Help, privacy and account access"
        }
    }
    var searchTerms: String {
        title + " " + summary + " " + (self == .support ? "sign out delete terms policy consent feedback tooltips" : "")
    }
    var icon: String {
        switch self {
        case .goals: return "target"
        case .appearance: return "circle.lefthalf.filled"
        case .health: return "heart"
        case .notifications: return "bell"
        case .training: return "dumbbell"
        case .maia: return "bubble.left.and.bubble.right"
        case .data: return "arrow.up.arrow.down"
        case .support: return "person.crop.circle"
        }
    }
}

private enum SettingsShortcut: String, Identifiable, CaseIterable {
    case calories, height, water, food, ai, guidance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calories: return "Calorie and macro goals"
        case .height: return "Height"
        case .water: return "Water preferences"
        case .food: return "Food preferences"
        case .ai: return "AI data sharing"
        case .guidance: return "Health guidance"
        }
    }
    var icon: String {
        switch self {
        case .calories: return "target"
        case .height: return "ruler"
        case .water: return "drop"
        case .food: return "fork.knife"
        case .ai: return "brain.head.profile"
        case .guidance: return "cross.case"
        }
    }
    var searchTerms: String {
        switch self {
        case .calories: return title + " protein carbs carbohydrates fat nutrition target calculator"
        case .height: return title + " body feet inches centimeters"
        case .water: return title + " hydration goal tracking ounces milliliters"
        case .food: return title + " allergies diet dietary restrictions suggestions"
        case .ai: return title + " privacy consent Maia permission processing"
        case .guidance: return title + " disclaimer sources medical safety"
        }
    }
}

/// One captured-owner cleanup implementation for deletion completion and root startup retries.
@MainActor
enum AccountLocalCleanup {
    static let coordinator = DeletedAccountCleanupCoordinator()
    private static let domains = ["diary-outbox", "workout-outbox", "workout-draft", "workout-corrections", "run-draft", "run-history",
                                  "editor-drafts", "workout-media", "water-inbox", "fasting", "speech", "preferences", "projection"]
    @discardableResult
    static func attempt(for userID: String) -> Bool {
        coordinator.attempt(for: userID, domains: domains, operation: perform)
    }
    @discardableResult
    static func retryPending() -> Bool { coordinator.retryPending(operation: perform) }

    private static func perform(userID: String, domain: String) throws {
        switch domain {
        case "diary-outbox": try DIContainer.shared.nutritionRepository.discardPendingDailyLogs(userID: userID)
        case "workout-outbox": try DIContainer.shared.workoutRepository.discardPendingWorkouts(userID: userID)
        case "workout-draft": try WorkoutDraftStore().remove(userID: userID)
        case "workout-corrections": try WorkoutCorrectionStore().removeAll(userID: userID)
        case "run-draft":
            try RunRecordingDraftStore().remove(userID: userID)
            try RunRouteArchiveStore().removeAccountData(userID: userID)
            try RunHealthExportJobStore().removeAccountData(userID: userID)
        case "run-history": try RunFallbackStore.shared.removeAccountData(for: userID)
        case "editor-drafts": try EditorDraftStore().removeAll(userID: userID)
        case "workout-media": try WorkoutInstructionMediaStore().removeAccountData(for: userID)
        case "water-inbox": try SharedDataManager.shared.waterInbox?.removeAll(accountScope: WatchAccountScopeStore().scope(for: userID))
        case "fasting": try FastingManager.shared.removeAccountData(for: userID)
        case "speech": try TTSManager.shared.removeCachedSpeech(for: userID)
        case "preferences": AccountLocalPreferences.remove(for: userID)
        case "projection":
            AYCESessionManager.invalidateActivities(outsideAccount: DIContainer.shared.authService.currentUserID)
            Task { await CookingNotificationCoordinator.shared.reconcile(userID: DIContainer.shared.authService.currentUserID) }
            if DIContainer.shared.authService.currentUserID == nil || DIContainer.shared.authService.currentUserID == userID {
                EcosystemSyncManager.shared.clearAccountWidgetData()
            }
        default: throw CocoaError(.coderReadCorrupt)
        }
    }
}
