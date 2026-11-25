import MyFitPlateCore

import SwiftUI
import Charts

enum ReportFocus: String, CaseIterable, Identifiable {
    case nutrition, training, recovery
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ReportNutritionSummary: View {
    let summary: ReportSummary?
    let period: String

    let calories: [DateValuePoint]
    let protein: [DateValuePoint]
    let range: ClosedRange<Date>

    @Binding var showsProtein: Bool
    @Binding var selectedDate: Date?
    let openDiary: (Date) -> Void
    private var points: [DateValuePoint] { showsProtein ? protein : calories }
    private var accent: Color { showsProtein ? AppPalette.protein : AppPalette.energy }
    private var unit: String { showsProtein ? "g" : "cal" }
    private var average: Double? { showsProtein ? summary?.averageProtein : summary?.averageCalories }
    private var selectedPoint: DateValuePoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack {
                Text("Daily intake").appTextRole(.sectionTitle)
                Spacer()
                Picker("Intake metric", selection: $showsProtein) {
                    Text("Calories").tag(false)
                    Text("Protein").tag(true)
                }
                .pickerStyle(.menu).fixedSize()
                .accessibilityIdentifier("reports_intake_metric")
            }
            if let latest = points.last {
                let value = selectedDate == nil ? (average ?? latest.value) : selectedPoint?.value
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                        .appTextRole(.display).monospacedDigit()
                    Text(unit).appTextRole(.control).foregroundStyle(.secondary)
                    Spacer()
                    if selectedDate != nil {
                        Button("Reset") { selectedDate = nil }.appTextRole(.secondary)
                    }
                }
                Text(metricCaption(latest: latest.date))
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("reports_intake_caption")
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value(unit, point.value))
                            .cornerRadius(3)
                            .foregroundStyle(accent.opacity(selectedDate == nil || selectedPoint?.id == point.id ? 1 : 0.45))
                    }
                    if let selectedDate {
                        RuleMark(x: .value("Selected day", selectedDate, unit: .day))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    if let average {
                        RuleMark(y: .value("Fully logged day average", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: range)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartXSelection(value: $selectedDate)
                .chartGesture { proxy in
                    SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
                }
                .frame(height: 118)
                .accessibilityLabel("Daily recorded " + (showsProtein ? "protein" : "calories"))
                if let selectedDate {
                    Button("Open diary day", systemImage: "book.pages") { openDiary(selectedDate) }
                        .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
                        .accessibilityIdentifier("reports_open_diary_day")
                }
                Text(evidence)
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("reports_nutrition_evidence")
            } else {
                Text("No food recorded for " + period + ".")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: range.lowerBound) { selectedDate = nil }
        .onChange(of: Calendar.current.startOfDay(for: range.upperBound)) { selectedDate = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports_overview")
    }

    private func metricCaption(latest: Date) -> String {
        if let selectedDate {
            return selectedDate.formatted(.dateTime.month(.abbreviated).day()) + (selectedPoint == nil ? " · No intake recorded" : " · Recorded intake")
        }
        return average == nil ? "Latest logged · " + latest.formatted(.dateTime.month(.abbreviated).day()) : "Daily average · " + period
    }

    private var evidence: String {
        if let count = summary?.daysLogged, count > 0 {
            return "Dashed line: average of " + count.formatted() + (count == 1 ? " fully logged day." : " fully logged days.")
        }
        return "Partial days are shown. Confirm a day in the diary to see an average."
    }
}

struct SmartReportInsightCard: View {
    let insight: UserInsight

    private var title: String {
        insight.title.lowercased() == "have a great day!" ? "Have a great day" : insight.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "sparkles")
                .appFont(size: 16, weight: .bold)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(insight.message)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface(.quiet)
    }
}

struct ReportsLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            SkeletonBlock(width: 140, height: 16)
            SkeletonBlock(height: 44)
            HStack(spacing: AppSpacing.compact) {
                SkeletonBlock(height: 72)
                SkeletonBlock(height: 72)
            }
        }
        .appSurface(.quiet)
        .skeletonPulse()
    }
}

struct ReportsMessageState: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .appFont(size: 28, weight: .semibold)
                .foregroundColor(color)
                .frame(width: 62, height: 62)
                .background(Color(UIColor.secondarySystemFill), in: Circle())

            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text(message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .appSurface(.quiet, padding: 0)
    }
}

struct ReportSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppSectionHeader(title: title, subtitle: subtitle)
    }
}

#if !TARGET_IS_WIDGET_EXTENSION
struct ReportDiaryDayView: View {
    let day: DiaryDayContext
    let log: DailyLog
    @EnvironmentObject private var service: DailyLogService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false
    @State private var openingEditor = false
    @State private var visible = false

    var body: some View {
        NutritionReviewDayDetail(log: log)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit in diary", action: openEditor).disabled(openingEditor)
                }
            }
            .alert("Couldn’t open the diary editor", isPresented: $failed) {
                Button("Try again", action: openEditor)
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onReceive(appState.$isUserLoggedIn) { _ in
                if !day.isOwned(by: DIContainer.shared.authService.currentUserID) { dismiss() }
            }
    }

    private func openEditor() {
        guard day.isOwned(by: DIContainer.shared.authService.currentUserID) else { dismiss(); return }
        openingEditor = true
        service.fetchLog(for: day.userID, day: day) { result in
            openingEditor = false
            guard visible, day.isOwned(by: DIContainer.shared.authService.currentUserID) else { return }
            guard case .success(let current) = result, current.id == day.dayKey else { failed = true; return }
            dismiss()
            appState.selectedTab = 0
        }
    }
}
#endif
