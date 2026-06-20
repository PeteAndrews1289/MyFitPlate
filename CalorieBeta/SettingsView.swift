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

    @Binding var showSettings: Bool
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
    
    // Wire up the reset confirmation
    @State private var showingResetTourConfirmation = false
    
    @State private var isDeletingAccount = false

    var body: some View {
        List {
            Section {
                SettingsHeaderCard(
                    calorieGoal: goalSettings.calories,
                    waterGoal: goalSettings.waterGoal,
                    heightText: "\(goalSettings.getHeightInFeetAndInches().feet)'\(goalSettings.getHeightInFeetAndInches().inches)\""
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(header: Text("Appearance")) {
                Toggle(isOn: $appState.isDarkModeEnabled.animation()) {
                    SettingsLabel(icon: "moon.fill", title: "Dark Mode", subtitle: "Use the darker app appearance.", color: .purple)
                }
            }
            
            Section(header: Text("Integrations")) {
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
            }

            Section(header: Text("Account")) {
                Button { showCaloricCalculator = true } label: {
                    SettingsLabel(icon: "target", title: "Calorie and Macro Goals", subtitle: "Adjust targets and goal method.", color: .brandPrimary)
                }
                Button {
                    let currentHeight = goalSettings.getHeightInFeetAndInches()
                    feetInput = "\(currentHeight.feet)"; inchesInput = "\(currentHeight.inches)"
                    showHeightEditor = true
                } label: {
                    SettingsLabel(icon: "ruler", title: "Height", subtitle: "Update your body metrics.", color: .blue)
                }
                Button {
                    waterGoalInput = String(format: "%.0f", goalSettings.waterGoal)
                    showingWaterGoalSheet = true
                } label: {
                    SettingsLabel(icon: "drop.fill", title: "Daily Water Goal", subtitle: "\(Int(goalSettings.waterGoal.rounded())) oz per day.", color: .cyan)
                }
                Picker("Calorie Goal Method", selection: $goalSettings.calorieGoalMethod) {
                    ForEach(CalorieGoalMethod.allCases) { method in Text(method.rawValue).tag(method) }
                }
                 .onChange(of: goalSettings.calorieGoalMethod) { _, _ in
                      if let userID = Auth.auth().currentUser?.uid { goalSettings.saveUserGoals(userID: userID) }
                  }
            }
            
            Section(header: Text("Help & Support")) {
                Button {
                    showingResetTourConfirmation = true
                } label: {
                    SettingsLabel(icon: "questionmark.circle.fill", title: "Reset Feature Tooltips", subtitle: "Replay the guided app tips.", color: .orange)
                }
            }
            
            Section {
                Button("Sign Out", role: .destructive) { showingSignOutAlert = true }
                
                if isDeletingAccount {
                    HStack {
                        Text("Deleting Account...")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Button("Delete Account", role: .destructive) { showingDeleteAccountAlert = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary.ignoresSafeArea())
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
        // Alerts
        .alert("Sign Out", isPresented: $showingSignOutAlert, actions: { Button("Cancel", role: .cancel) {}; Button("Sign Out", role: .destructive) { appState.signOut() } }, message: { Text("Are you sure you want to sign out?") })
        .alert("Delete Account", isPresented: $showingDeleteAccountAlert, actions: {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAccount() }
        }, message: {
            Text("Are you sure you want to delete your account? This will permanently delete your profile, logs, recipes, workouts, and account data. This cannot be undone.")
        })
        .alert("Reset Tooltips?", isPresented: $showingResetTourConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                spotlightManager.resetSpotlights()
            }
        } message: {
            Text("This will reset all the \"Quick Tip\" bubbles throughout the app so you can see them again.")
        }
    }
    
    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        isDeletingAccount = true
        
        let db = Firestore.firestore()
        deleteUserFirestoreData(userID: user.uid, db: db) { result in
            if case .failure(let error) = result {
                AppLog.data.error("Failed to delete user data: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    isDeletingAccount = false
                }
                return
            }

            user.delete { error in
                DispatchQueue.main.async {
                    isDeletingAccount = false
                    if let error = error {
                        AppLog.app.error("Failed to delete auth account: \(error.localizedDescription, privacy: .public)")
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
            db.collection("groups").whereField("creatorID", isEqualTo: userID),
            db.collection("posts").whereField("authorID", isEqualTo: userID)
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
