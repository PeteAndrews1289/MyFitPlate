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
                    HStack(spacing: 12) {
                        Text(goalSettings.calorieGoalMethod.rawValue)
                            .appFont(size: 15, weight: .semibold)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.up.chevron.down")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .accessibilityLabel("Calorie goal method")
                .accessibilityValue(goalSettings.calorieGoalMethod.rawValue)
            }
            .padding(16)

            Divider().padding(.leading, 50)

            Button {
                exportData()
            } label: {
                HStack {
                    SettingsLabel(
                        icon: "square.and.arrow.up",
                        title: "Export your data",
                        subtitle: "Food diary and workouts as CSV files.",
                        color: .blue
                    )
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)
            .padding(16)

            Divider().padding(.leading, 50)

            Button {
                showingMFPImport = true
            } label: {
                SettingsLabel(
                    icon: "square.and.arrow.down",
                    title: "Import from MyFitnessPal",
                    subtitle: "Bring your diary and weight history with you.",
                    color: .accentProtein
                )
            }
            .padding(16)
        }
        .sheet(isPresented: $showingExportShare) {
            PDFShareView(activityItems: exportURLs)
        }
        .sheet(isPresented: $showingMFPImport) {
            MFPImportView()
                .environmentObject(dailyLogService)
                .environmentObject(goalSettings)
        }
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
