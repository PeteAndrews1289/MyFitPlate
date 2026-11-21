import SwiftUI
import MyFitPlateCore

@MainActor
struct SettingsAccountSection: View {
    enum Scope { case goals, data }
    var scope: Scope = .goals
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits = Locale.current.measurementSystem != .us
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService

    @Binding var showCaloricCalculator: Bool
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @Binding var showHeightEditor: Bool
    @Binding var waterGoalInput: String
    @Binding var showingWaterGoalSheet: Bool

    @StateObject private var exportSession = LegacyDataExportSession()
    @State private var showingExportShare = false
    @State private var showingMFPImport = false
    @State private var didPresentScreenshotImport = false

    var body: some View {
        SettingsSectionCard(title: scope == .goals ? "Targets & body" : "Your data") {
            if scope == .goals {
                Button { showCaloricCalculator = true } label: {
                    SettingsLabel(
                        icon: "target",
                        title: "Calorie and macro goals",
                        subtitle: "\(goalSettings.calories.map { "\(Int($0.rounded()).formatted()) cal" } ?? "No target set") · \(goalSettings.calorieGoalMethod.rawValue)",
                        showsDisclosure: true
                    )
                }
                .padding(AppSpacing.group)
                .accessibilityIdentifier("settings_calorie_goals")

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
                        subtitle: heightDescription,
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
                        title: "Water preferences",
                        subtitle: waterDescription,
                        showsDisclosure: true
                    )
                }
                .padding(AppSpacing.group)
            
            }
            if scope == .data {
                Button {
                    exportData()
                } label: {
                    HStack {
                        SettingsLabel(
                            icon: "square.and.arrow.up",
                            title: exportSession.errorMessage == nil ? "Export diary and workouts" : "Retry export",
                            subtitle: "Food diary and workout sets · past 10 years · CSV"
                        )
                        if exportSession.isExporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(exportSession.isExporting)
                .padding(AppSpacing.group)
                .accessibilityIdentifier("settings_export_start")
                if exportSession.isExporting {
                    Button("Cancel export") { exportSession.cancel() }
                        .accessibilityIdentifier("settings_export_cancel").padding(.horizontal, AppSpacing.group)
                }
                if let error = exportSession.errorMessage {
                    Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                        .fixedSize(horizontal: false, vertical: true).padding(AppSpacing.group)
                        .accessibilityIdentifier("settings_export_error")
                }

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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_goals_data")
        .sheet(isPresented: $showingExportShare, onDismiss: cleanupExportFiles) {
            PDFShareView(activityItems: exportSession.urls)
        }
        .sheet(isPresented: $showingMFPImport) {
            MFPImportView()
                .environmentObject(dailyLogService)
                .environmentObject(goalSettings)
        }
        .onAppear(perform: presentScreenshotImportIfNeeded)
        .onDisappear { if !showingExportShare { exportSession.cancel() } }
    }

    private var waterDescription: String {
        let preferences = goalSettings.hydrationPreferences
        if preferences.isTrackingOnly { return "Track water without a daily target" }
        let amount = preferences.unit.amount(fromOunces: goalSettings.waterGoal)
        return "\(Int(amount.rounded()).formatted()) \(preferences.unit.symbol) per day"
    }

    private var heightDescription: String {
        if useMetricBodyUnits { return "\(Int(goalSettings.height.rounded()).formatted()) cm" }
        let height = goalSettings.getHeightInFeetAndInches()
        return "\(height.feet) ft \(height.inches) in"
    }

    private func presentScreenshotImportIfNeeded() {
        #if DEBUG
        guard ScreenshotDemoMode.isEnabled,
              ScreenshotDemoData.requestedScreen.hasPrefix("settings-import"),
              !didPresentScreenshotImport else { return }
        didPresentScreenshotImport = true
        showingMFPImport = true
        #endif
    }

    private func exportData() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        Task { @MainActor in
            if await exportSession.generate(for: userID), DIContainer.shared.authService.currentUserID == userID {
                DIContainer.shared.analyticsManager?.logEvent("data_export_created", parameters: nil)
                showingExportShare = true
            }
        }
    }

    private func cleanupExportFiles() { exportSession.cleanup() }
}
