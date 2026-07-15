import MyFitPlateCore
import SwiftUI

struct DetailedInsightsView: View {
    @ObservedObject var insightsService: InsightsService
    private let initialInsights: [UserInsight]?
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var exportError: String?

    private var sortedInsights: [UserInsight] {
        insightsService.currentInsights.sorted { first, second in
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Maia",
                    title: "Weekly Insights",
                    subtitle: "Patterns from your logged nutrition, training, hydration, and recovery data."
                )

                if insightsService.isLoadingInsights {
                    InsightsLoadingState()
                } else if sortedInsights.isEmpty {
                    InsightsEmptyState()
                } else {
                    insightSummary

                    if let topInsight {
                        LeadInsightView(insight: topInsight)
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
        .navigationTitle("Maia Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportToPDF) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(sortedInsights.isEmpty || insightsService.isLoadingInsights)
                .accessibilityLabel("Share Maia insights")
                .accessibilityIdentifier("maia_insights_share")
            }
        }
        .tint(AppPalette.brand)
        .onAppear {
            guard let initialInsights else { return }
            insightsService.isLoadingInsights = false
            insightsService.currentInsights = initialInsights
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL {
                PDFShareView(activityItems: [pdfURL])
            }
        }
        .alert("Could Not Export Insights", isPresented: exportAlertBinding) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Try again in a moment.")
        }
    }

    private var insightSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Patterns",
                value: sortedInsights.count.formatted(),
                accent: AppPalette.brand
            ),
            AppMetricItem(
                label: "Areas",
                value: categoryCount.formatted(),
                accent: AppPalette.recovery
            ),
            AppMetricItem(
                label: "Interpretation",
                value: "AI Assisted",
                accent: AppPalette.caution
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("maia_insights_summary")
    }

    private var insightList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Other Patterns",
                subtitle: "Review each observation and open its source data when available."
            )

            VStack(spacing: 0) {
                ForEach(Array(remainingInsights.enumerated()), id: \.element.id) { index, insight in
                    InsightEvidenceRow(insight: insight)

                    if index < remainingInsights.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
            .accessibilityIdentifier("maia_insights_list")
        }
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }

    @MainActor
    private func exportToPDF() {
        let insights = sortedInsights
        guard !insights.isEmpty else { return }

        let url = URL.documentsDirectory.appending(path: "MyFitPlate_Insights.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            exportError = "MyFitPlate could not create the PDF file."
            return
        }

        for (index, insight) in insights.enumerated() {
            let page = InsightsPDFPage(
                insight: insight,
                pageNumber: index + 1,
                pageCount: insights.count
            )
            let renderer = ImageRenderer(content: page)
            renderer.render { _, render in
                pdf.beginPDFPage(nil)
                render(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()

        guard FileManager.default.fileExists(atPath: url.path) else {
            exportError = "The PDF was not saved. Check available storage and try again."
            return
        }
        pdfURL = url
        showShareSheet = true
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
                    Text("Lead Pattern")
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
        .appSurface(.emphasized)
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
            Label("Source Data", systemImage: "doc.text.magnifyingglass")
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
                    Text("Source Data")
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
            Text("Reading the Week")
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
            Text("Not Enough Signal Yet")
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

private struct InsightsPDFPage: View {
    let insight: UserInsight
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("MyFitPlate Weekly Insights")
                    .font(.title.bold())
                Spacer()
                Text("\(pageNumber) / \(pageCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("Generated \(Date().formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text(insight.category.displayName)
                .font(.headline)
                .foregroundStyle(insight.category.tintColor)

            Text(insight.title)
                .font(.title2.bold())

            Text(insight.message)
                .font(.body)
                .lineSpacing(4)

            Spacer()

            Text("Generated from logged data and general guidance. Not medical advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
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
