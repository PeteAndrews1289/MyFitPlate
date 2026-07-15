import SwiftUI
import UniformTypeIdentifiers
import MyFitPlateCore

// "Switching from MyFitnessPal? Bring your history in five minutes." Drop in any CSVs
// from an MFP export; each file is auto-detected as diary or weight data, previewed,
// and written day-by-day. Days already logged in MyFitPlate are never touched.

@MainActor
final class MFPImportViewModel: ObservableObject {

    enum Stage: Equatable {
        case instructions
        case analyzing
        case preview
        case importing(written: Int, total: Int)
        case finished(days: Int, entries: Int, weighIns: Int, conflicts: Int)
        case failed(String)
    }

    @Published var stage: Stage = .instructions

    private(set) var diaryLogs: [DailyLog] = []
    private(set) var weighIns: [(date: Date, weightLbs: Double)] = []
    private(set) var skippedRows = 0
    private(set) var unrecognizedFiles = 0
    private(set) var conflictCount = 0
    private var importableLogs: [DailyLog] = []
    private var importableWeighIns: [(date: Date, weightLbs: Double)] = []

    var totalEntries: Int {
        diaryLogs.reduce(0) { $0 + $1.meals.reduce(0) { $0 + $1.foodItems.count } }
    }

    func handlePicked(urls: [URL], dailyLogService: DailyLogService, goalSettings: GoalSettings) {
        stage = .analyzing
        diaryLogs = []
        weighIns = []
        skippedRows = 0
        unrecognizedFiles = 0

        var byDay: [Date: DailyLog] = [:]
        let calendar = Calendar.current

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let csv = Self.readText(from: url) else {
                unrecognizedFiles += 1
                continue
            }

            if let parsed = try? MFPImport.parseDiary(csv: csv), parsed.totalFoodEntries > 0 {
                skippedRows += parsed.skippedRows
                for log in parsed.dailyLogs {
                    let day = calendar.startOfDay(for: log.date)
                    if var existing = byDay[day] {
                        existing.meals.append(contentsOf: log.meals)
                        byDay[day] = existing
                    } else {
                        byDay[day] = log
                    }
                }
            } else {
                let measurements = MFPImport.parseMeasurements(csv: csv)
                if measurements.isEmpty {
                    unrecognizedFiles += 1
                } else {
                    weighIns.append(contentsOf: measurements)
                }
            }
        }

        diaryLogs = byDay.values.sorted { $0.date < $1.date }

        guard !diaryLogs.isEmpty || !weighIns.isEmpty else {
            stage = .failed(unrecognizedFiles > 0
                ? "Those files don't look like MyFitnessPal exports. Look for the CSVs inside the export ZIP."
                : "Nothing importable found in the selected files.")
            return
        }

        prepareMergePlan(dailyLogService: dailyLogService, goalSettings: goalSettings)
    }

    private func prepareMergePlan(dailyLogService: DailyLogService, goalSettings: GoalSettings) {
        Task { @MainActor in
            let calendar = Calendar.current

            var existingDays = Set<Date>()
            let sortedDates = diaryLogs.map(\.date).sorted()
            if let first = sortedDates.first, let last = sortedDates.last,
               let userID = DIContainer.shared.authService.currentUserID {
                let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: first, endDate: last)
                let existing = (try? result.get()) ?? []
                existingDays = Set(
                    existing
                        .filter { !$0.meals.flatMap(\.foodItems).isEmpty }
                        .map { calendar.startOfDay(for: $0.date) }
                )
            }

            let plan = MFPImport.mergePlan(imported: diaryLogs, existingLoggedDays: existingDays, calendar: calendar)
            importableLogs = plan.toImport
            conflictCount = plan.skippedConflicts

            let existingWeightDays = Set(goalSettings.weightHistory.map { calendar.startOfDay(for: $0.date) })
            importableWeighIns = weighIns.filter { !existingWeightDays.contains(calendar.startOfDay(for: $0.date)) }

            stage = .preview
        }
    }

    func runImport(dailyLogService: DailyLogService, goalSettings: GoalSettings) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            stage = .failed("You need to be signed in to import.")
            return
        }
        let logs = importableLogs
        let weights = importableWeighIns
        let total = logs.count + weights.count
        stage = .importing(written: 0, total: total)

        Task { @MainActor in
            var written = 0
            // Each day is its own document, so writes are independent; the stagger keeps
            // a multi-year import from stampeding Firestore all at once.
            for log in logs {
                dailyLogService.addMealGroupsToLog(
                    for: userID,
                    date: log.date,
                    mealGroups: log.meals.map { (mealName: $0.name, foodItems: $0.foodItems) },
                    source: "mfp_import"
                )
                written += 1
                stage = .importing(written: written, total: total)
                try? await Task.sleep(nanoseconds: 60_000_000)
            }

            for weighIn in weights {
                goalSettings.updateUserWeight(weighIn.weightLbs, date: weighIn.date)
                written += 1
                stage = .importing(written: written, total: total)
                try? await Task.sleep(nanoseconds: 60_000_000)
            }

            DIContainer.shared.analyticsManager?.logEvent("mfp_import_completed", parameters: [
                "days": logs.count,
                "entries": logs.reduce(0) { $0 + $1.meals.reduce(0) { $0 + $1.foodItems.count } },
                "weigh_ins": weights.count,
                "conflicts_skipped": conflictCount
            ])

            stage = .finished(
                days: logs.count,
                entries: logs.reduce(0) { $0 + $1.meals.reduce(0) { $0 + $1.foodItems.count } },
                weighIns: weights.count,
                conflicts: conflictCount
            )
        }
    }

    private static func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

struct MFPImportView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MFPImportViewModel()
    @State private var showingFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    switch viewModel.stage {
                    case .instructions, .analyzing:
                        instructions
                    case .preview:
                        preview
                    case .importing(let written, let total):
                        importingView(written: written, total: total)
                    case .finished(let days, let entries, let weighIns, let conflicts):
                        finishedView(days: days, entries: entries, weighIns: weighIns, conflicts: conflicts)
                    case .failed(let message):
                        failedView(message)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                stageActionFooter
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                        .disabled(isImporting)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    viewModel.handlePicked(urls: urls, dailyLogService: dailyLogService, goalSettings: goalSettings)
                }
            }
        }
        .tint(AppPalette.brand)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(isImporting)
        .accessibilityIdentifier("settings_import_screen")
    }

    private var isImporting: Bool {
        if case .importing = viewModel.stage { return true }
        return false
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Data Import",
                title: "Bring Your History With You",
                subtitle: "Import your diary and weight history in a few minutes. Days you've already logged in MyFitPlate are never changed."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                instructionRow(number: 1, text: "On myfitnesspal.com, open Settings and choose Download My Data (or Reports → Export).")
                instructionRow(number: 2, text: "Unzip the export they email you.")
                instructionRow(number: 3, text: "Choose the CSV files below. Diary and weight files are detected automatically.")
            }
            .appSurface(.quiet)

        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Text("\(number)")
                .appTextRole(.caption)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 28, height: 28)
                .background(AppPalette.brand.opacity(0.10), in: Circle())
            Text(text)
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Import Preview",
                title: "Ready to Import",
                subtitle: "Review what MyFitPlate found before adding it to your history."
            )

            VStack(spacing: 0) {
                previewRow("Days of food history", "\(viewModel.diaryLogs.count)")
                Divider()
                previewRow("Food entries", "\(viewModel.totalEntries.formatted())")
                Divider()
                previewRow("Weigh-ins", "\(viewModel.weighIns.count)")
                if viewModel.conflictCount > 0 {
                    Divider()
                    previewRow("Days skipped (already logged here)", "\(viewModel.conflictCount)")
                }
                if viewModel.skippedRows > 0 {
                    Divider()
                    previewRow("Unreadable rows skipped", "\(viewModel.skippedRows)")
                }
            }
            .appSurface(.quiet)

            Text("Imported entries are labeled as MyFitnessPal data. Days you've already logged in MyFitPlate stay exactly as they are.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)

            Button {
                DIContainer.shared.analyticsManager?.logEvent("mfp_import_started", parameters: [
                    "source": "preview_choose_different"
                ])
                showingFilePicker = true
            } label: {
                Text("Choose Different Files")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
        }
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.row)
    }

    private func importingView(written: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Importing",
                title: "Writing Your History",
                subtitle: "Keep MyFitPlate open until this finishes."
            )

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                ProgressView(value: Double(written), total: Double(max(total, 1)))
                    .tint(AppPalette.brand)
                Text("\(written) of \(total) items complete")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
            }
            .appSurface(.emphasized)
        }
    }

    private func finishedView(days: Int, entries: Int, weighIns: Int, conflicts: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Import Complete",
                title: "Your History Moved In",
                subtitle: "Reports and trends now include your imported history."
            ) {
                Image(systemName: "checkmark.circle.fill")
                    .appTextRole(.screenTitle)
                    .foregroundStyle(AppPalette.brandText)
                    .accessibilityHidden(true)
            }

            Text("\(days) days · \(entries.formatted()) entries · \(weighIns) weigh-ins" + (conflicts > 0 ? " · \(conflicts) days left untouched" : ""))
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .appSurface(.emphasized)

        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Import Problem",
                title: "That Didn't Work",
                subtitle: message
            )
        }
    }

    @ViewBuilder
    private var stageActionFooter: some View {
        switch viewModel.stage {
        case .instructions, .analyzing:
            importFooter {
                Button {
                    DIContainer.shared.analyticsManager?.logEvent("mfp_import_started", parameters: [
                        "source": "instructions"
                    ])
                    showingFilePicker = true
                } label: {
                    if case .analyzing = viewModel.stage {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Label("Choose Files", systemImage: "doc.badge.plus")
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(viewModel.stage == .analyzing)
                .accessibilityIdentifier("settings_import_choose_files")
            }

        case .preview:
            importFooter {
                Button {
                    viewModel.runImport(dailyLogService: dailyLogService, goalSettings: goalSettings)
                } label: {
                    Label("Import Everything", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("settings_import_confirm")
            }

        case .finished:
            importFooter {
                Button("Done") { dismiss() }
                    .buttonStyle(AppActionButtonStyle(.primary))
            }

        case .failed:
            importFooter {
                Button("Try Again") { viewModel.stage = .instructions }
                    .buttonStyle(AppActionButtonStyle(.primary))
            }

        case .importing:
            EmptyView()
        }
    }

    private func importFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.row)
            .padding(.bottom, AppSpacing.compact)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
    }
}
