import MyFitPlateCore
import SwiftUI
import CoreText
import PDFKit

struct DetailedInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    @ObservedObject var insightsService: InsightsService
    private let initialInsights: [UserInsight]?
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var showsPDFPreview = false
    @State private var exportError: String?
    @State private var selectedReport: SavedInsightReport?
    @State private var showingEvidence: InsightEvidenceSnapshot?
    @State private var showsExportReview = false
    @State private var exportEvidence = true
    @State private var exportSourceText = false
    @State private var didPresentScreenshotDestination = false

    private var ownsPresentation: Bool { ownerID != nil && ownerID == DIContainer.shared.authService.currentUserID }

    private var sortedInsights: [UserInsight] {
        guard ownsPresentation else { return [] }
        let values = selectedReport.flatMap {
            $0.evidence.ownerID == DIContainer.shared.authService.currentUserID ? $0.insights : nil
        } ?? insightsService.currentInsights
        return values.sorted { first, second in
            if first.priority == second.priority {
                return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
            return first.priority > second.priority
        }
    }

    private var topInsight: UserInsight? {
        sortedInsights.first
    }

    private var remainingInsights: [UserInsight] {
        Array(sortedInsights.dropFirst())
    }

    private var categoryCount: Int {
        Set(sortedInsights.map(\.category)).count
    }

    init(insightsService: InsightsService, initialInsights: [UserInsight]? = nil) {
        self.insightsService = insightsService
        self.initialInsights = initialInsights
    }

    #if DEBUG
    /// Read-only fixture: the general insight seed has no immutable input snapshot.
    /// Build the evidence destination directly instead of racing the service refresh.
    private static var screenshotEvidence: InsightEvidenceSnapshot? {
        guard ScreenshotDemoMode.isEnabled,
              let ownerID = DIContainer.shared.authService.currentUserID else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
        let statuses: [NutritionDayStatus] = [.complete, .partial, .unknown]
        let logs = statuses.enumerated().compactMap { offset, status -> DailyLog? in
            guard let day = calendar.date(byAdding: .day, value: offset + 1, to: start) else { return nil }
            return DailyLog(
                id: "design-evidence-day-\(offset)", date: day,
                meals: [Meal(name: "Recorded meals", foodItems: [
                    FoodItem(id: "design-evidence-food-\(offset)", name: "Sample food record", calories: 2_050)
                ])], nutritionDayStatus: status
            )
        }
        return try? InsightEvidenceSnapshot(
            ownerID: ownerID, logs: logs, sleepHoursByNight: [start: 7.4, today: 7.1],
            calorieGoal: 2_100, proteinGoal: 160, start: start, end: today,
            origin: .aiInterpretation, now: now, calendar: calendar
        )
    }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                reportSelection
                if let notice = insightsService.insightHistoryNotice {
                    Text(notice).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                }
                if insightsService.isLoadingInsights && selectedReport == nil {
                    InsightsLoadingState()
                } else if sortedInsights.isEmpty {
                    InsightsEmptyState()
                } else {
                    insightSummary

                    if let topInsight {
                        LeadInsightView(insight: topInsight)
                        evidenceButton(topInsight)
                    }

                    if !remainingInsights.isEmpty {
                        insightList
                    }
                }

                InsightDisclaimer()
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Maia insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showsExportReview = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(sortedInsights.isEmpty || insightsService.isLoadingInsights)
                .accessibilityLabel("Share Maia insights")
                .accessibilityIdentifier("maia_insights_share")
            }
        }
        .opacity(ownsPresentation ? 1 : 0).allowsHitTesting(ownsPresentation).accessibilityHidden(!ownsPresentation)
        .onReceive(appState.$isUserLoggedIn) { _ in
            guard !ownsPresentation else { return }
            selectedReport = nil; showingEvidence = nil; showsExportReview = false; showShareSheet = false; showsPDFPreview = false
            if let folder = accountExportDirectory { try? FileManager.default.removeItem(at: folder) }
            if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }; pdfURL = nil
            dismiss()
        }
        .tint(AppPalette.brand)
        .onAppear {
            if let initialInsights {
                insightsService.isLoadingInsights = false
                insightsService.currentInsights = initialInsights
            }
            #if DEBUG
            if ScreenshotDemoMode.isEnabled, !didPresentScreenshotDestination {
                didPresentScreenshotDestination = true
                if ScreenshotDemoData.requestedScreen == "insight-export" { showsExportReview = true }
                if ScreenshotDemoData.requestedScreen == "insight-evidence" { showingEvidence = Self.screenshotEvidence }
            }
            #endif
        }
        .sheet(item: $showingEvidence) { evidence in
            InsightEvidenceDetailView(evidence: evidence)
        }
        .sheet(isPresented: $showsExportReview) { exportReview }
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL {
                PDFShareView(activityItems: [pdfURL])
            }
        }
        .alert("Could not export insights", isPresented: exportAlertBinding) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Try again in a moment.")
        }
    }

    private var insightSummary: some View {
        HStack(spacing: AppSpacing.compact) {
            Text("\(sortedInsights.count) patterns · \(categoryCount) areas")
            Spacer(minLength: AppSpacing.compact)
            Label("AI interpretation", systemImage: "sparkles")
        }
        .appTextRole(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("maia_insights_summary")
    }

    private var insightList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "More patterns",
                subtitle: "Review each observation and open its source data when available."
            )

            VStack(spacing: 0) {
                ForEach(Array(remainingInsights.enumerated()), id: \.element.id) { index, insight in
                    InsightEvidenceRow(insight: insight)
                    evidenceButton(insight).padding(.horizontal, AppSpacing.group)

                    if index < remainingInsights.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
            .accessibilityIdentifier("maia_insights_list")
        }
    }

    private var reportSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                Menu {
                    Button("Current report") { selectedReport = nil }
                    ForEach(insightsService.insightReports) { report in
                        Button(report.evidence.generatedAt.formatted(date: .abbreviated, time: .shortened)) { selectedReport = report }
                    }
                } label: {
                    Label(selectedReport?.evidence.generatedAt.formatted(date: .abbreviated, time: .shortened) ?? "Current report", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("maia_insights_history")
                Spacer()
                Button("Refresh") {
                    selectedReport = nil
                    insightsService.generateAndFetchInsights(requestConsentIfNeeded: true, forceRefresh: true)
                }.disabled(insightsService.isLoadingInsights)
            }
            if let evidence = sortedInsights.first?.evidence {
                Text("\(evidence.windowStart.formatted(date: .abbreviated, time: .omitted))–\(evidence.windowEnd.formatted(date: .abbreviated, time: .omitted))")
                    .appTextRole(.secondary)
                Text(evidence.coverageDescription).appTextRole(.caption).foregroundStyle(.secondary)
            }
            if selectedReport != nil {
                Text("Saved snapshot on this device. Later log edits do not rewrite it.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func evidenceButton(_ insight: UserInsight) -> some View {
        if let evidence = insight.evidence {
            Button { showingEvidence = evidence } label: {
                Label("Inspect input records", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
            .accessibilityIdentifier("maia_insight_evidence_\(insight.id)")
        } else {
            Text("A record snapshot is not available for this insight.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
    }

    private var exportReview: some View {
        NavigationStack {
            Form {
                Section("Included") {
                    Text("\(sortedInsights.count) insights from the selected report")
                    Toggle("Coverage and calculated input totals", isOn: $exportEvidence)
                    Toggle("Interpretation's source explanation", isOn: $exportSourceText)
                    Text("The source explanation may be AI-written. Coverage and totals come from captured records. Structured account and record IDs are omitted; optional source prose may contain personal details, so inspect the preview before sharing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Preview") {
                    ForEach(sortedInsights) { insight in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(insight.title).font(.headline)
                            Text(insight.message).font(.body)
                            if exportEvidence, let evidence = insight.evidence { Text(evidence.coverageDescription).font(.caption) }
                            if exportSourceText, let source = insight.sourceData { Text(source).font(.caption) }
                        }
                    }
                }
            }
            .appFormStyle()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: AppSpacing.compact) {
                    Button("Preview PDF") { exportToPDF() }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("maia_insights_create_pdf")
                    Menu("Other formats") {
                        Button("Create text report") { exportText(.text) }.accessibilityIdentifier("maia_insights_create_text")
                        Button("Create CSV report") { exportText(.csv) }.accessibilityIdentifier("maia_insights_create_csv")
                    }
                    .appTextRole(.control)
                    .frame(minHeight: 36)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(AppPalette.canvas)
            }
            .navigationDestination(isPresented: $showsPDFPreview) {
                if let pdfURL, ownsPresentation {
                    InsightPDFPagePreview(url: pdfURL, ownerID: ownerID)
                }
            }
            .navigationTitle("Share report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsExportReview = false } } }
        }
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    private var accountExportDirectory: URL? {
        guard let ownerID, let key = AccountScopedStorageKey.make(prefix: "insight-export", userID: ownerID) else { return nil }
        return FileManager.default.temporaryDirectory.appendingPathComponent("MyFitPlateInsights", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }
    private func preparedExportDirectory() throws -> URL {
        guard ownsPresentation, let directory = accountExportDirectory else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        return directory
    }

    @MainActor
    private func exportText(_ format: InsightReportExport.Format) {
        guard ownsPresentation else { return }
        do {
            let value = try InsightReportExport.content(insights: sortedInsights, format: format, includeEvidence: exportEvidence, includeSourceText: exportSourceText)
            let extensionName = format == .text ? "txt" : "csv"
            let url = try preparedExportDirectory().appendingPathComponent("MyFitPlate-Insights-\(UUID().uuidString).\(extensionName)")
            try value.write(to: url, atomically: true, encoding: .utf8)
            do { try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path) } catch { try? FileManager.default.removeItem(at: url); throw error }
            if let previous = pdfURL { try? FileManager.default.removeItem(at: previous) }
            pdfURL = url; showsExportReview = false; showShareSheet = true
        } catch { exportError = error.localizedDescription }
    }

    @MainActor
    private func exportToPDF() {
        let insights = sortedInsights
        guard ownsPresentation, !insights.isEmpty else { return }

        do {
            let url = try InsightPDFExport.render(insights: insights, includeEvidence: exportEvidence,
                                                 includeSourceText: exportSourceText, directory: preparedExportDirectory())
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                try? FileManager.default.removeItem(at: url)
                throw CocoaError(.fileReadCorruptFile)
            }
            if let previous = pdfURL { try? FileManager.default.removeItem(at: previous) }
            pdfURL = url
            showsPDFPreview = true
        } catch { exportError = error.localizedDescription }
    }
}

/// Preview and sharing use the same rendered file, so pagination and selected evidence
/// cannot change between inspection and the system share sheet.
private struct InsightPDFPagePreview: View {
    let url: URL
    let ownerID: String?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showsShare = false
    private var ownsPresentation: Bool { ownerID != nil && ownerID == DIContainer.shared.authService.currentUserID }

    var body: some View {
        VStack(spacing: 0) {
            if ownsPresentation, let document = PDFDocument(url: url), document.pageCount > 0 {
                Text("\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages") · Pinch to zoom; scroll to review")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .padding(AppSpacing.row)
                RenderedInsightPDF(document: document)
                    .accessibilityIdentifier("maia_insights_pdf_pages")
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "doc",
                    description: Text("Return to the report and create the PDF again."))
            }
        }
        .background(AppPalette.canvas)
        .navigationTitle("PDF preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { if ownsPresentation { showsShare = true } } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!ownsPresentation || PDFDocument(url: url) == nil)
                .accessibilityIdentifier("maia_insights_pdf_share")
            }
        }
        .sheet(isPresented: $showsShare) {
            if ownsPresentation { PDFShareView(activityItems: [url]) }
        }
        .onReceive(appState.$isUserLoggedIn) { _ in
            if !ownsPresentation { showsShare = false; dismiss() }
        }
    }
}

private struct RenderedInsightPDF: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != document.documentURL { view.document = document }
    }
}

private struct LeadInsightView: View {
    let insight: UserInsight
    @State private var showsSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: insight.category.iconName)
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(insight.category.tintColor)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lead pattern")
                        .appTextRole(.caption)
                        .foregroundStyle(insight.category.tintColor)
                    Text(insight.title)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(insight.message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let source = normalizedSource(insight.sourceData) {
                sourceDisclosure(source)
            }
        }
        .appSurface(.interpreted)
        .accessibilityIdentifier("maia_insights_lead")
    }

    private func sourceDisclosure(_ source: String) -> some View {
        DisclosureGroup(isExpanded: $showsSource) {
            Text(source)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.compact)
        } label: {
            Label("Source explanation", systemImage: "doc.text.magnifyingglass")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.brandText)
        }
    }
}

private struct InsightEvidenceRow: View {
    let insight: UserInsight
    @State private var showsSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: insight.category.iconName)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundStyle(insight.category.tintColor)
                    .frame(width: 40, height: 40)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.category.displayName)
                        .appTextRole(.caption)
                        .foregroundStyle(insight.category.tintColor)
                    Text(insight.title)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(insight.message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let source = normalizedSource(insight.sourceData) {
                DisclosureGroup(isExpanded: $showsSource) {
                    Text(source)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AppSpacing.compact)
                } label: {
                    Text("Source explanation")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.brandText)
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }
}

private struct InsightsLoadingState: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)
            Text("Reading your week")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text("Maia is checking nutrition, training, hydration, sleep, and journal signals for useful patterns.")
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.quiet)
    }
}

private struct InsightsEmptyState: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "chart.line.text.clipboard")
                .appFont(size: 28, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
            Text("No insights yet")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text("A few logged meals, water entries, and workouts give Maia enough context to produce a more useful weekly read.")
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.quiet)
    }
}

private struct InsightDisclaimer: View {
    var body: some View {
        Label {
            Text("Maia interprets logged data using general health guidance. These insights can be incomplete and are not medical advice.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private func normalizedSource(_ source: String?) -> String? {
    guard let source else { return nil }
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension UserInsight.InsightCategory {
    var displayName: String {
        switch self {
        case .nutritionGeneral: "Nutrition"
        case .hydration: "Hydration"
        case .macroBalance: "Macros"
        case .microNutrient: "Micros"
        case .mealTiming: "Meal Timing"
        case .consistency: "Consistency"
        case .postWorkout: "Post Workout"
        case .foodVariety: "Variety"
        case .positiveReinforcement: "Win"
        case .sugarAwareness: "Sugar"
        case .fiberIntake: "Fiber"
        case .saturatedFat: "Fats"
        case .smartSuggestion: "Suggestion"
        case .sleep: "Sleep"
        case .calorieFluctuation: "Calories"
        case .weekendTrends: "Weekend"
        case .exerciseSynergy: "Training"
        }
    }

    var iconName: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .hydration: "drop.fill"
        case .microNutrient, .fiberIntake, .saturatedFat: "leaf.fill"
        case .macroBalance: "chart.pie.fill"
        case .nutritionGeneral, .foodVariety: "fork.knife"
        case .consistency, .mealTiming, .weekendTrends: "calendar.badge.clock"
        case .postWorkout, .exerciseSynergy: "flame.fill"
        case .positiveReinforcement: "star.fill"
        case .sugarAwareness: "bubbles.and.sparkles"
        default: "lightbulb.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .sleep: AppPalette.recovery
        case .hydration: AppPalette.hydration
        case .microNutrient, .fiberIntake, .foodVariety: AppPalette.positive
        case .saturatedFat: AppPalette.caution
        case .macroBalance: AppPalette.carbohydrate
        case .nutritionGeneral: AppPalette.fat
        case .consistency, .mealTiming, .weekendTrends: AppPalette.recovery
        case .postWorkout, .exerciseSynergy: AppPalette.effort
        case .positiveReinforcement: AppPalette.achievement
        case .sugarAwareness: AppPalette.critical
        default: AppSignalRole.neutral.color
        }
    }
}

struct InsightEvidenceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let evidence: InsightEvidenceSnapshot

    var body: some View {
        NavigationStack {
            Group {
                if appState.isUserLoggedIn, evidence.ownerID == DIContainer.shared.authService.currentUserID {
                    evidenceList
                } else { Text("Return to the account that owns this report.").padding() }
            }
            .navigationTitle("Insight evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var evidenceList: some View {
        List {
            scopeSection
            Section("Recorded days") {
                ForEach(evidence.days) { day in InsightEvidenceDayRow(day: day) }
            }
            Section("Included sleep nights") {
                if evidence.sleepNights.isEmpty { Text("No sleep evidence included.") }
                ForEach(evidence.sleepNights) { night in
                    let date = night.date.formatted(date: .abbreviated, time: .omitted)
                    let hours = night.hours.formatted(.number.precision(.fractionLength(1)))
                    Text(verbatim: date + " · " + hours + " h asleep")
                }
            }
            Section("Calculation") {
                Text(evidence.calculationVersion).font(.caption)
                Text("Targets at review: \(evidence.calorieGoal.formatted(.number.precision(.fractionLength(0)))) cal · \(evidence.proteinGoal.formatted(.number.precision(.fractionLength(0...1)))) g protein")
                Text("Unknown or partial intake is excluded rather than counted as zero.").font(.footnote)
            }
        }
        .appFormStyle()
        .accessibilityIdentifier("maia_insight_evidence_records")
    }

    private var scopeSection: some View {
        Section("Scope and coverage") {
            Text(evidence.sourceLabel)
            Text(evidence.coverageDescription)
            let start = evidence.windowStart.formatted(date: .abbreviated, time: .omitted)
            let end = evidence.windowEnd.formatted(date: .abbreviated, time: .omitted)
            Text(verbatim: start + "–" + end + " · " + evidence.timeZoneIdentifier)
            Text("Captured \(evidence.generatedAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Inputs describe what was available. They do not prove that an AI interpretation or a causal explanation is correct.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct InsightEvidenceDayRow: View {
    let day: InsightEvidenceSnapshot.Day
    var body: some View {
        DisclosureGroup(day.dayKey + " · " + day.status.title) {
            if let calories = day.calories, let protein = day.protein {
                let caloriesText = calories.formatted(.number.precision(.fractionLength(0)))
                let proteinText = protein.formatted(.number.precision(.fractionLength(0)))
                Text(verbatim: caloriesText + " cal · " + proteinText + " g protein")
            } else { Text("Intake excluded: this day was not confirmed fully logged.") }
            if let water = day.waterOunces { Text("\(water.formatted()) oz water recorded") }
            Text("\(day.foodIDs.count) food records · \(day.workoutIDs.count) workout records · \(day.journalIDs.count) journal entries")
            DisclosureGroup("Record references") {
                Text(verbatim: "Diary: " + (day.sourceID ?? day.dayKey)).font(.caption).textSelection(.enabled)
                Text(verbatim: "Snapshot: " + day.sourceFingerprint).font(.caption).textSelection(.enabled)
            }
        }
    }
}

/// Core Text supplies page ranges so long paragraphs, Unicode and evidence tables
/// continue on subsequent pages instead of being clipped into a fixed SwiftUI frame.
@MainActor
enum InsightPDFExport {
    static func render(insights: [UserInsight], includeEvidence: Bool, includeSourceText: Bool,
                       directory: URL = FileManager.default.temporaryDirectory,
                       createdAt: Date = Date()) throws -> URL {
        guard !insights.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let text = NSMutableAttributedString(string: "")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3; paragraph.paragraphSpacing = 12
        func append(_ value: String, size: CGFloat = 12, bold: Bool = false, color: UIColor = .black) {
            text.append(NSAttributedString(string: value + "\n", attributes: [
                .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                .foregroundColor: color, .paragraphStyle: paragraph
            ]))
        }
        for (index, insight) in insights.enumerated() {
            append("\(index + 1). \(insight.title)", size: 20, bold: true)
            append(insight.message)
            if includeEvidence {
                if let evidence = insight.evidence {
                    append(evidence.sourceLabel, size: 11, bold: true)
                    append("Window: " + InsightReportExport.window(evidence) + "\n" + evidence.coverageDescription, size: 10)
                    append("Captured targets: \(evidence.calorieGoal.formatted(.number.precision(.fractionLength(0)))) cal/day; \(evidence.proteinGoal.formatted(.number.precision(.fractionLength(0...1)))) g protein/day", size: 10)
                    for day in evidence.days {
                        let intake: String
                        if let calories = day.calories, let protein = day.protein {
                            intake = "\(calories.formatted()) cal, \(protein.formatted()) g protein"
                        } else { intake = "intake excluded" }
                        append("\(day.dayKey): \(day.status.title); \(intake); \(day.workoutIDs.count) workout records", size: 10)
                    }
                    append("Method: " + evidence.calculationVersion + ". Unknown or partial intake is excluded; missing days are not zero-intake days.", size: 9)
                    append("These are the inputs available at review. They do not establish a causal relationship or validate every AI-written interpretation.", size: 10)
                } else { append("No captured record evidence is available for this insight.", size: 10) }
            }
            if includeSourceText, let source = normalizedSource(insight.sourceData) {
                append("Interpretation's source explanation (may be AI-written):", size: 10, bold: true)
                append(source, size: 11)
            }
        }
        append("Generated by MyFitPlate. These observations are for reviewing your records, not medical diagnosis.", size: 9)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let contentPath = CGPath(rect: CGRect(x: 40, y: 72, width: 532, height: 640), transform: nil)
        var frames: [CTFrame] = []
        var location = 0
        while location < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), contentPath, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw CocoaError(.fileWriteUnknown) }
            frames.append(frame); location += visible.length
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("MyFitPlate-Insights-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        do {
            try renderer.writePDF(to: url) { context in
                for (index, frame) in frames.enumerated() {
                    context.beginPage()
                    ("MyFitPlate | Insights" as NSString).draw(at: CGPoint(x: 40, y: 32), withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.black
                    ])
                    let cg = context.cgContext
                    cg.saveGState(); cg.textMatrix = .identity
                    cg.translateBy(x: 0, y: 792); cg.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, cg); cg.restoreGState()
                    ("\(index + 1) / \(frames.count)  |  Exported \(createdAt.formatted(date: .abbreviated, time: .omitted))" as NSString)
                        .draw(at: CGPoint(x: 40, y: 752), withAttributes: [
                            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray
                        ])
                }
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}
