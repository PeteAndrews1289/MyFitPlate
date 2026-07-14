import SwiftUI
import MyFitPlateCore

struct SettingsAccountSection: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    // Owned, not environment: WorkoutService has no app-wide instance (same latent crash
    // the Weekly Recap sheet hit on device).
    @StateObject private var workoutService = WorkoutService()

    @Binding var showCaloricCalculator: Bool
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @Binding var showHeightEditor: Bool
    @Binding var waterGoalInput: String
    @Binding var showingWaterGoalSheet: Bool

    @State private var isExporting = false
    @State private var exportURLs: [URL] = []
    @State private var showingExportShare = false
    @State private var showingMFPImport = false
    @State private var didPresentScreenshotImport = false

    var body: some View {
        SettingsSectionCard(title: "Goals & Data") {
            Button { showCaloricCalculator = true } label: {
                SettingsLabel(
                    icon: "target",
                    title: "Calorie and macro goals",
                    subtitle: "Adjust targets and goal method.",
                    showsDisclosure: true
                )
            }
            .padding(AppSpacing.group)
            
            Divider().padding(.leading, 50)
            
            Button {
                let currentHeight = goalSettings.getHeightInFeetAndInches()
                feetInput = "\(currentHeight.feet)"
                inchesInput = "\(currentHeight.inches)"
                showHeightEditor = true
            } label: {
                SettingsLabel(
                    icon: "ruler",
                    title: "Height",
                    subtitle: "Update your body metrics.",
                    showsDisclosure: true
                )
            }
            .padding(AppSpacing.group)
            
            Divider().padding(.leading, 50)
            
            Button {
                waterGoalInput = "\(Int(goalSettings.waterGoal.rounded()))"
                showingWaterGoalSheet = true
            } label: {
                SettingsLabel(
                    icon: "drop.fill",
                    title: "Daily water goal",
                    subtitle: "\(Int(goalSettings.waterGoal.rounded()).formatted()) oz per day.",
                    showsDisclosure: true
                )
            }
            .padding(AppSpacing.group)
            
            Divider().padding(.leading, 50)
            
            Menu {
                ForEach(CalorieGoalMethod.allCases) { method in
                    Button {
                        selectCalorieGoalMethod(method)
                    } label: {
                        if goalSettings.calorieGoalMethod == method {
                            Label(method.rawValue, systemImage: "checkmark")
                        } else {
                            Text(method.rawValue)
                        }
                    }
                }
            } label: {
                SettingsLabel(
                    icon: "function",
                    title: "Calorie goal method",
                    subtitle: goalSettings.calorieGoalMethod.rawValue,
                    showsDisclosure: true
                )
            }
            .accessibilityLabel("Calorie goal method")
            .accessibilityValue(goalSettings.calorieGoalMethod.rawValue)
            .padding(AppSpacing.group)

            Divider().padding(.leading, 50)

            Button {
                exportData()
            } label: {
                HStack {
                    SettingsLabel(
                        icon: "square.and.arrow.up",
                        title: "Export your data",
                        subtitle: "Food diary and workouts as CSV files."
                    )
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
            .padding(AppSpacing.group)

            Divider().padding(.leading, 50)

            Button {
                showingMFPImport = true
            } label: {
                SettingsLabel(
                    icon: "square.and.arrow.down",
                    title: "Import from MyFitnessPal",
                    subtitle: "Bring your diary and weight history with you.",
                    showsDisclosure: true
                )
            }
            .padding(AppSpacing.group)
        }
        .accessibilityIdentifier("settings_goals_data")
        .sheet(isPresented: $showingExportShare) {
            PDFShareView(activityItems: exportURLs)
        }
        .sheet(isPresented: $showingMFPImport) {
            MFPImportView()
                .environmentObject(dailyLogService)
                .environmentObject(goalSettings)
        }
        .onAppear(perform: presentScreenshotImportIfNeeded)
    }

    private func presentScreenshotImportIfNeeded() {
        #if DEBUG
        guard ScreenshotDemoMode.isEnabled,
              ScreenshotDemoData.requestedScreen == "settings-import",
              !didPresentScreenshotImport else { return }
        didPresentScreenshotImport = true
        showingMFPImport = true
        #endif
    }

    private func selectCalorieGoalMethod(_ method: CalorieGoalMethod) {
        guard goalSettings.calorieGoalMethod != method else { return }
        goalSettings.calorieGoalMethod = method
        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
        }
    }

    /// Fetches the user's full history, writes two CSVs to temp files, and hands them to
    /// the share sheet. Best-effort: partial data still exports (an empty CSV has a header).
    private func exportData() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        isExporting = true

        Task {
            let logsResult = await dailyLogService.fetchDailyHistory(for: userID, startDate: nil, endDate: nil)
            let sessions = await workoutService.fetchRecentSessionLogs(sinceDays: 3650)

            let foodCSV = DataExporter.foodLogCSV(from: (try? logsResult.get()) ?? [])
            let workoutCSV = DataExporter.workoutCSV(from: sessions)

            let directory = FileManager.default.temporaryDirectory
            let foodURL = directory.appendingPathComponent("myfitplate-food-diary.csv")
            let workoutURL = directory.appendingPathComponent("myfitplate-workouts.csv")

            do {
                try foodCSV.write(to: foodURL, atomically: true, encoding: .utf8)
                try workoutCSV.write(to: workoutURL, atomically: true, encoding: .utf8)
                exportURLs = [foodURL, workoutURL]
                DIContainer.shared.analyticsManager?.logEvent("data_exported", parameters: nil)
                showingExportShare = true
            } catch {
                AppLog.app.error("Data export failed: \(error.localizedDescription, privacy: .public)")
            }

            isExporting = false
        }
    }
}
