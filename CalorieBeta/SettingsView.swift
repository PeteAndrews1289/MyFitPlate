import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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
    @AppStorage("notificationHour") private var notificationHour: Int = 20
    @AppStorage("notificationMinute") private var notificationMinute: Int = 0

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
    // Known per-user subcollections, including a few legacy names still worth cleaning up.
    private let userScopedCollections = [
        "achievementStatus",
        "activeChallenges",
        "calorieHistory",
        "customFoods",
        "dailyLogs",
        "dailySummaries",
        "mealPlans",
        "pinnedNotes",
        "recentFoods",
        "recipes",
        "savedPrograms",
        "userSettings",
        "weightHistory",
        "workoutHistory",
        "workoutPrograms",
        "workoutRoutines",
        "workoutSessionLogs",
        "workouts"
    ]
    
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
    @State private var deleteErrorMessage: String? = nil
    @State private var showingResetTourConfirmation = false
    
    @State private var isDeletingAccount = false

    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            ScrollView {
                VStack(spacing: 24) {
                    SettingsHeaderCard(
                        calorieGoal: goalSettings.calories,
                        waterGoal: goalSettings.waterGoal,
                        heightText: "\(goalSettings.getHeightInFeetAndInches().feet)'\(goalSettings.getHeightInFeetAndInches().inches)\""
                    )

                    SettingsSectionCard(title: "Appearance") {
                        Toggle(isOn: $appState.isDarkModeEnabled.animation()) {
                            SettingsLabel(icon: "moon.fill", title: "Dark Mode", subtitle: "Use the darker app appearance.", color: .purple)
                        }
                        .padding(16)
                    }
                    
                    SettingsSectionCard(title: "Integrations") {
                        Button(action: {
                            healthKitViewModel.requestAuthorization()
                        }) {
                            HStack {
                                Image("Apple_Health")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(healthKitViewModel.isAuthorized ? "Review Health Access & Sync" : "Connect to Apple Health")
                                        .appFont(size: 15, weight: .semibold)
                                    Text(healthKitViewModel.isAuthorized ? "Refresh workouts, sleep, and recovery permissions." : "Import workouts and sleep where available.")
                                        .appFont(size: 12)
                                        .foregroundColor(Color(UIColor.secondaryLabel))
                                }
                                
                                Spacer()
                                
                                if healthKitViewModel.isSyncing {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else if healthKitViewModel.isAuthorized {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentPositive)
                                }
                            }
                        }
                        .foregroundColor(.textPrimary)
                        .disabled(healthKitViewModel.isSyncing)
                        .opacity(healthKitViewModel.isSyncing ? 0.55 : 1.0)
                        .padding(16)
                        
                        if healthKitViewModel.isAuthorized {
                            Divider().padding(.leading, 50)
                            Toggle(isOn: $includeActiveCaloriesInGoal) {
                                SettingsLabel(
                                    icon: "flame.fill",
                                    title: "Include Active Calories",
                                    subtitle: "Add exercise calories burned to your daily food allowance.",
                                    color: .orange
                                )
                            }
                            .tint(.brandPrimary)
                            .padding(16)
                        }
                    }

                    SettingsSectionCard(title: "Account") {
                        Button { showCaloricCalculator = true } label: {
                            SettingsLabel(icon: "target", title: "Calorie and Macro Goals", subtitle: "Adjust targets and goal method.", color: .brandPrimary)
                        }
                        .padding(16)
                        
                        Divider().padding(.leading, 50)
                        
                        Button {
                            let currentHeight = goalSettings.getHeightInFeetAndInches()
                            feetInput = "\(currentHeight.feet)"; inchesInput = "\(currentHeight.inches)"
                            showHeightEditor = true
                        } label: {
                            SettingsLabel(icon: "ruler", title: "Height", subtitle: "Update your body metrics.", color: .blue)
                        }
                        .padding(16)
                        
                        Divider().padding(.leading, 50)
                        
                        Button {
                            waterGoalInput = String(format: "%.0f", goalSettings.waterGoal)
                            showingWaterGoalSheet = true
                        } label: {
                            SettingsLabel(icon: "drop.fill", title: "Daily Water Goal", subtitle: "\(Int(goalSettings.waterGoal.rounded())) oz per day.", color: .cyan)
                        }
                        .padding(16)
                        
                        Divider().padding(.leading, 50)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Calorie Goal Method")
                                .appFont(size: 15, weight: .semibold)
                                .foregroundColor(.textPrimary)
                            
                            Picker("Calorie Goal Method", selection: $goalSettings.calorieGoalMethod) {
                                ForEach(CalorieGoalMethod.allCases) { method in Text(method.rawValue).tag(method) }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: goalSettings.calorieGoalMethod) { _, _ in
                                if let userID = Auth.auth().currentUser?.uid { goalSettings.saveUserGoals(userID: userID) }
                            }
                        }
                        .padding(16)
                    }
                    
                    SettingsSectionCard(title: "Notifications") {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsLabel(
                                icon: "bell.fill",
                                title: "Daily Log Reminder",
                                subtitle: "Nightly check-in to log your meals.",
                                color: .orange
                            )
                            DatePicker("", selection: notificationTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .onChange(of: notificationTimeBinding.wrappedValue) { _, _ in
                                    NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
                                }
                        }
                        .padding(16)
                    }

                    SettingsSectionCard(title: "Help & Support") {
                        Button {
                            showingHealthDisclaimer = true
                        } label: {
                            SettingsLabel(icon: "cross.case.fill", title: "Health Disclaimers & Sources", subtitle: "Review medical, nutrition, and AI estimate guidance.", color: .orange)
                        }
                        .padding(16)

                        Divider().padding(.leading, 50)

                        Link(destination: URL(string: "https://PeteAndrews1289.github.io/MyFitPlate/privacy_policy.html")!) {
                            SettingsLabel(icon: "lock.shield.fill", title: "Privacy & Data", subtitle: "See how health, nutrition, and AI data are handled.", color: .blue)
                        }
                        .padding(16)

                        Divider().padding(.leading, 50)

                        Link(destination: URL(string: "https://PeteAndrews1289.github.io/MyFitPlate/terms_of_service.html")!) {
                            SettingsLabel(icon: "doc.text.fill", title: "Terms of Service", subtitle: "Read our terms, conditions, and usage policies.", color: .purple)
                        }
                        .padding(16)

                        Divider().padding(.leading, 50)

                        Button {
                            showingResetTourConfirmation = true
                        } label: {
                            SettingsLabel(icon: "questionmark.circle.fill", title: "Reset Feature Tooltips", subtitle: "Replay the guided app tips.", color: .orange)
                        }
                        .padding(16)
                    }
                    
                    SettingsSectionCard {
                        Button(role: .destructive) { showingSignOutAlert = true } label: {
                            Text("Sign Out")
                                .appFont(size: 17, weight: .semibold)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(16)
                        
                        Divider()
                        
                        if isDeletingAccount {
                            HStack {
                                Text("Deleting Account...")
                                    .appFont(size: 17, weight: .semibold)
                                Spacer()
                                ProgressView()
                            }
                            .padding(16)
                        } else {
                            Button(role: .destructive) { showingDeleteAccountAlert = true } label: {
                                Text("Delete Account")
                                    .appFont(size: 17, weight: .semibold)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(16)
                        }
                    }
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
                    if let userID = Auth.auth().currentUser?.uid { dailyLogService.updateDailyLog(for: userID, updatedLog: currentLog) }
                }
            }
            showingWaterGoalSheet = false
        }).environmentObject(goalSettings) }
        .sheet(isPresented: $showingHealthDisclaimer) {
            NavigationView {
                HealthDisclaimerView()
            }
        }
        // Alerts
        .alert("Sign Out", isPresented: $showingSignOutAlert, actions: { Button("Cancel", role: .cancel) {}; Button("Sign Out", role: .destructive) { appState.signOut() } }, message: { Text("Are you sure you want to sign out?") })
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert, actions: {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { DispatchQueue.main.async { showingReauthForDelete = true } }
        }, message: {
            Text("Are you sure you want to delete your account? This will permanently delete your profile, logs, recipes, workouts, and account data. This cannot be undone.")
        })
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
    
    private func reauthenticateAndDelete() {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            deleteErrorMessage = "We couldn't verify your account. Please sign out, sign back in, and try again."
            reauthPassword = ""
            return
        }
        let password = reauthPassword
        reauthPassword = ""
        guard !password.isEmpty else {
            deleteErrorMessage = "Please enter your password to continue."
            return
        }

        isDeletingAccount = true
        // Reauthenticate FIRST so we never delete user data unless we can also remove
        // the auth account — otherwise a stale session leaves a zombie login with no data.
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        user.reauthenticate(with: credential) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    isDeletingAccount = false
                    deleteErrorMessage = "Re-authentication failed: \(error.localizedDescription)"
                }
                return
            }
            performAccountDeletion(user: user)
        }
    }

    private func performAccountDeletion(user: User) {
        let db = Firestore.firestore()
        deleteUserFirestoreData(userID: user.uid, db: db) { result in
            if case .failure(let error) = result {
                AppLog.data.error("Failed to delete user data: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    isDeletingAccount = false
                    deleteErrorMessage = "We couldn't delete your data. Please check your connection and try again."
                }
                return
            }

            user.delete { error in
                DispatchQueue.main.async {
                    isDeletingAccount = false
                    if let error = error {
                        AppLog.app.error("Failed to delete auth account: \(error.localizedDescription, privacy: .public)")
                        deleteErrorMessage = "Your data was removed, but the login couldn't be deleted. Please sign out, sign back in, and delete again."
                    } else {
                        clearLocalAccountData()
                        appState.isUserLoggedIn = false
                        showSettings = false
                    }
                }
            }
        }
    }

    private func clearLocalAccountData() {
        spotlightManager.resetSpotlights()
        UserDefaults.standard.removeObject(forKey: "cycleSettings")
        UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
        UserDefaults.standard.removeObject(forKey: "pinnedExerciseNotes")
    }

    private func deleteUserFirestoreData(userID: String, db: Firestore, completion: @escaping (Result<Void, Error>) -> Void) {
        let userRef = db.collection("users").document(userID)
        deleteUserFirestoreData(userID: userID, userRef: userRef, db: db, completion: completion)
    }

    private func deleteUserFirestoreData(userID: String, userRef: DocumentReference, db: Firestore, completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        func recordError(_ error: Error) {
            lock.lock()
            if firstError == nil {
                firstError = error
            }
            lock.unlock()
        }

        for collectionName in userScopedCollections {
            group.enter()
            deleteCollection(userRef.collection(collectionName), db: db) { error in
                if let error = error {
                    recordError(error)
                }
                group.leave()
            }
        }

        let topLevelQueries: [Query] = [
            db.collection("groupMemberships").whereField("userID", isEqualTo: userID),
            db.collection("groupMemberships").whereField("userId", isEqualTo: userID),
            db.collection("groups").whereField("creatorID", isEqualTo: userID),
            db.collection("groups").whereField("creatorId", isEqualTo: userID),
            db.collection("posts").whereField("authorID", isEqualTo: userID),
            db.collection("posts").whereField("authorId", isEqualTo: userID)
        ]

        for query in topLevelQueries {
            group.enter()
            deleteQueryResults(query, db: db) { error in
                if let error = error {
                    recordError(error)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError = firstError {
                completion(.failure(firstError))
                return
            }

            userRef.delete { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private func deleteCollection(_ collection: CollectionReference, db: Firestore, batchSize: Int = 100, completion: @escaping (Error?) -> Void) {
        collection.limit(to: batchSize).getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let documents = snapshot?.documents, !documents.isEmpty else {
                completion(nil)
                return
            }

            let batch = db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    deleteCollection(collection, db: db, batchSize: batchSize, completion: completion)
                }
            }
        }
    }

    private func deleteQueryResults(_ query: Query, db: Firestore, batchSize: Int = 100, completion: @escaping (Error?) -> Void) {
        query.limit(to: batchSize).getDocuments { snapshot, error in
            if let error = error {
                completion(error)
                return
            }

            guard let documents = snapshot?.documents, !documents.isEmpty else {
                completion(nil)
                return
            }

            let batch = db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }

            batch.commit { error in
                if let error = error {
                    completion(error)
                } else {
                    deleteQueryResults(query, db: db, batchSize: batchSize, completion: completion)
                }
            }
        }
    }
}

private struct SettingsLegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

private enum SettingsLegalInfoKind {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy & Data"
        case .terms: return "Terms & Safety"
        }
    }

    var icon: String {
        switch self {
        case .privacy: return "lock.shield.fill"
        case .terms: return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .privacy: return .blue
        case .terms: return .purple
        }
    }

    var intro: String {
        switch self {
        case .privacy:
            return "This in-app summary is here for transparency. Your App Store privacy policy should remain the full legal source of truth."
        case .terms:
            return "MyFitPlate is designed to support everyday nutrition and fitness tracking. It should not replace professional medical, nutrition, or emergency care."
        }
    }

    var sections: [SettingsLegalSection] {
        switch self {
        case .privacy:
            return [
                SettingsLegalSection(title: "Personal Data", body: "MyFitPlate stores account, goal, nutrition, weight, workout, recipe, meal plan, pantry, and progress data so the app can personalize your experience."),
                SettingsLegalSection(title: "Apple Health", body: "Health data is requested only when you connect Apple Health. You can manage or revoke those permissions in the Health app or iOS Settings."),
                SettingsLegalSection(title: "AI Features", body: "Maia, food photo analysis, recipe generation, meal planning, and insights may send your prompts and relevant nutrition context to the configured AI service to generate a response."),
                SettingsLegalSection(title: "Analytics", body: "Analytics should be used only to understand app stability and feature health. Keep your App Store privacy labels aligned with the analytics and SDKs actually enabled in the release build."),
                SettingsLegalSection(title: "Deleting Your Account", body: "The Delete Account action removes the app's stored user data and then attempts to delete the Firebase Authentication account.")
            ]
        case .terms:
            return [
                SettingsLegalSection(title: "Not Medical Advice", body: "Nutrition targets, calorie estimates, fasting suggestions, cycle insights, workouts, and AI responses are informational and may not fit every health situation."),
                SettingsLegalSection(title: "Estimate Accuracy", body: "Food databases, barcode matches, manual entries, and AI-generated estimates can be incomplete or wrong. Review entries before relying on them."),
                SettingsLegalSection(title: "User Responsibility", body: "Use your judgment and consult a qualified professional before making major diet, exercise, medication, fasting, or weight-change decisions."),
                SettingsLegalSection(title: "Emergency Care", body: "Do not use MyFitPlate for urgent medical concerns. Contact emergency services or a licensed clinician when immediate care is needed.")
            ]
        }
    }
}

private struct SettingsLegalInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: SettingsLegalInfoKind

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(kind.color)
                            .frame(width: 46, height: 46)
                            .background(kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(kind.intro)
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))

                    ForEach(kind.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text(section.body)
                                .appFont(size: 14)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct SettingsHeaderCard: View {
    let calorieGoal: Double?
    let waterGoal: Double
    let heightText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Settings")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Tune the goals and integrations that power the rest of MyFitPlate.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                SettingsMetric(title: "Calories", value: calorieGoal.map { "\(Int($0.rounded()))" } ?? "--", color: .orange)
                SettingsMetric(title: "Water", value: "\(Int(waterGoal.rounded())) oz", color: .cyan)
                SettingsMetric(title: "Height", value: heightText, color: .blue)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SettingsMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title.uppercased())
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.horizontal, 8)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
    }
}

private struct DeleteAccountAlerts: ViewModifier {
    @Binding var showingReauthForDelete: Bool
    @Binding var reauthPassword: String
    @Binding var deleteErrorMessage: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Confirm Your Password", isPresented: $showingReauthForDelete) {
                SecureField("Password", text: $reauthPassword)
                Button("Cancel", role: .cancel) { reauthPassword = "" }
                Button("Delete Account", role: .destructive) { onConfirm() }
            } message: {
                Text("For your security, re-enter your password to permanently delete your account.")
            }
            .alert("Couldn't Delete Account", isPresented: errorBinding) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } })
    }
}
