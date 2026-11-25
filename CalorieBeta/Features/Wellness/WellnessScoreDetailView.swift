import SwiftUI

struct WellnessScoreDetailView: View {
    let wellnessScore: WellnessScore
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?

    @EnvironmentObject private var appState: AppState
    @State private var accountChanged = false
    @State private var preferences = PersonalReportPreferences()
    @State private var preferenceOwner: String?
    @State private var preferenceError: String?
    @State private var preferenceReadFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    if preferences.showsWellnessComposite {
                        scoreOverview
                    } else {
                        overviewText
                    }
                    signalSection
                    Toggle("Show the combined habit score", isOn: Binding(
                        get: { preferences.showsWellnessComposite }, set: { updateComposite($0) }))
                        .accessibilityIdentifier("wellness_composite_toggle").disabled(preferenceReadFailed)
                    if let preferenceError { Text(preferenceError).foregroundStyle(.secondary) }
                    DisclosureGroup("About this summary") {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(wellnessScore.scopeDescription)
                            Text(coverageDescription)
                            if preferences.showsWellnessComposite { Text(wellnessScore.methodDescription) }
                        }
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .padding(.top, AppSpacing.compact)
                    }
                    .appTextRole(.secondary)

                    if let mealScore, wellnessScore.hasNutrition {
                        NutritionEvidenceSection(score: mealScore)
                    }

                    if let sleepReport {
                        SleepEvidenceSection(report: sleepReport)
                    }

                    Label(
                        "This is a summary of recorded habits. It does not measure recovery or readiness for training.",
                        systemImage: "info.circle"
                    )
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppSpacing.group)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
            }
            .accessibilityIdentifier("wellness_detail_screen")
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Wellness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(AppPalette.brand)
        .opacity(accountChanged ? 0 : 1)
        .accessibilityHidden(accountChanged)
        .allowsHitTesting(!accountChanged)
        .onReceive(appState.$isUserLoggedIn) { _ in
            if let owner = preferenceOwner, owner != DIContainer.shared.authService.currentUserID {
                accountChanged = true; dismiss()
            }
        }
        .onAppear {
            preferenceOwner = DIContainer.shared.authService.currentUserID
            if let owner = preferenceOwner {
                do { preferences = try PersonalReportPreferenceStore.load(userID: owner) } catch { preferenceReadFailed = true; preferenceError = "The display preference could not be opened. Existing settings are kept. Reopen this view to retry." }
            }
        }
    }

    private func updateComposite(_ enabled: Bool) {
        guard let owner = preferenceOwner else { return }
        var next = preferences; next.showsWellnessComposite = enabled
        do {
            try PersonalReportPreferenceStore.save(next, userID: owner, currentUserID: DIContainer.shared.authService.currentUserID)
            preferences = next; preferenceError = nil
        } catch { preferenceError = "The display preference could not be saved. Try again." }
    }

    private var scoreOverview: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    accessibleScoreSummary
                    overviewText
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: AppSpacing.section) {
                        scoreGauge
                        overviewText
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        scoreGauge
                        overviewText
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.interpreted, radius: AppRadius.hero)
        .accessibilityIdentifier("wellness_score_overview")
    }

    private var accessibleScoreSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(wellnessScore.overallScore.formatted())
                .appTextRole(.display)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()

            Text("out of 100")
                .appTextRole(.body)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(wellnessScore.overallScore), total: 100)
                .tint(wellnessScore.color)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wellnessScore.displayTitle), \(wellnessScore.overallScore) out of 100")
    }

    private var scoreGauge: some View {
        ZStack {
            Circle()
                .stroke(wellnessScore.color.opacity(0.16), lineWidth: 11)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(Double(wellnessScore.overallScore) / 100, 0), 1)))
                .stroke(wellnessScore.color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(wellnessScore.overallScore.formatted())
                    .appTextRole(.screenTitle)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
                Text("of 100")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wellnessScore.displayTitle), \(wellnessScore.overallScore) out of 100")
    }

    private var overviewText: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(wellnessScore.displayTitle)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            Text(wellnessScore.summary)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(wellnessScore.availableComponentCount) of 2 recorded components available")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coverageDescription: String {
        let count = wellnessScore.availableComponentCount
        return "\(count) of 2 habit components available. Missing records do not add or subtract points. Heart-rate readings are separate context."
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Recorded components")

            VStack(spacing: 0) {
                WellnessSignalRow(
                    icon: "fork.knife",
                    title: "Nutrition",
                    score: wellnessScore.hasNutrition ? wellnessScore.nutritionScore : nil,
                    description: wellnessScore.hasNutrition
                        ? "Yesterday's calorie, macro, and food-quality result."
                        : "Log a complete day of meals to add this signal.",
                    color: AppPalette.brand
                )

                Divider().padding(.leading, 64)

                WellnessSignalRow(
                    icon: "moon.fill",
                    title: "Sleep",
                    score: wellnessScore.sleepScore,
                    description: wellnessScore.sleepScore == nil
                        ? "No recent Apple Health sleep result is available."
                        : "Most recent sleep duration, timing, and interruptions.",
                    color: AppPalette.recovery
                )

                Divider().padding(.leading, 64)

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("Recovery data · \(wellnessScore.recoveryLabel)", systemImage: "heart")
                        .appTextRole(.control)
                    Text(wellnessScore.recoveryExplanation)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.group)
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityIdentifier("wellness_signal_section")
    }
}

private struct WellnessSignalRow: View {
    let icon: String
    let title: String
    let score: Int?
    let description: String
    let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    signalIdentity
                    scoreLabel
                }
            } else {
                HStack(alignment: .center, spacing: AppSpacing.row) {
                    signalIdentity
                    Spacer(minLength: AppSpacing.compact)
                    scoreLabel
                }
            }

            ProgressView(value: Double(score ?? 0), total: 100)
                .tint(score == nil ? Color(UIColor.tertiaryLabel) : color)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.group)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(score.map { "\($0) out of 100" } ?? "unavailable"). \(description)")
    }

    private var signalIdentity: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 17, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(
                    color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(description)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scoreLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(score.map(String.init) ?? "--")
                .appTextRole(.sectionTitle)
                .foregroundStyle(score == nil ? Color(UIColor.secondaryLabel) : color)
                .monospacedDigit()
            if score != nil {
                Text("/100")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NutritionEvidenceSection: View {
    let score: MealScore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition Evidence",
                subtitle: "Yesterday's result, grade \(score.grade)."
            ) {
                Text(score.overallScore.formatted())
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(score.color)
                    .monospacedDigit()
                    .accessibilityLabel("Nutrition score \(score.overallScore) out of 100")
            }

            if !score.personalizedAISummary.isEmpty,
               score.personalizedAISummary != "No data available." {
                AppListRow(
                    icon: "sparkles",
                    iconColor: AppPalette.achievement,
                    title: "Maia's Read",
                    subtitle: score.personalizedAISummary
                )
                .appSurface(.quiet, padding: 0)
            }

            VStack(spacing: AppSpacing.group) {
                EvidenceProgressRow(
                    title: "Calories",
                    actual: score.actualCalories,
                    goal: score.goalCalories,
                    unit: "cal",
                    color: AppPalette.energy
                )
                EvidenceProgressRow(
                    title: "Protein",
                    actual: score.actualProtein,
                    goal: score.goalProtein,
                    unit: "g",
                    color: .accentProtein
                )
                EvidenceProgressRow(
                    title: "Carbs",
                    actual: score.actualCarbs,
                    goal: score.goalCarbs,
                    unit: "g",
                    color: .accentCarbs
                )
                EvidenceProgressRow(
                    title: "Fat",
                    actual: score.actualFats,
                    goal: score.goalFats,
                    unit: "g",
                    color: .accentFats
                )
                EvidenceProgressRow(
                    title: "Fiber",
                    actual: score.actualFiber,
                    goal: score.goalFiber,
                    unit: "g",
                    color: AppPalette.positive
                )
            }
            .appSurface(.quiet)

            if !score.improvementTips.isEmpty {
                AppSectionHeader(
                    title: "Next Best Moves",
                    subtitle: "The clearest opportunities from yesterday."
                )

                VStack(spacing: 0) {
                    ForEach(Array(score.improvementTips.enumerated()), id: \.element.id) { index, tip in
                        AppListRow(
                            icon: tip.icon,
                            iconColor: tip.color,
                            title: tip.category,
                            subtitle: tip.advice
                        )

                        if index < score.improvementTips.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
            }
        }
        .accessibilityIdentifier("wellness_nutrition_evidence")
    }
}

private struct EvidenceProgressRow: View {
    let title: String
    let actual: Double
    let goal: Double
    let unit: String
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(actual / goal, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Spacer(minLength: AppSpacing.compact)
                Text("\(Int(actual.rounded()).formatted()) / \(Int(goal.rounded()).formatted()) \(unit)")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }

            ProgressView(value: progress)
                .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int(actual.rounded())) of \(Int(goal.rounded())) \(unit)")
    }
}

private enum SleepEvidenceRange: String, CaseIterable {
    case lastNight = "Last Night"
    case average = "7-Day Average"
}

private struct SleepEvidenceSection: View {
    let report: EnhancedSleepReport

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedRange: SleepEvidenceRange = .average

    private var lastNightData: EnhancedSleepReport.DailySleepStageData? {
        report.dailySleepData.max(by: { $0.date < $1.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Sleep Evidence",
                subtitle: "Readable sleep records for \(report.dateRange). Stages are device-reported estimates."
            )

            rangePicker

            if selectedRange == .average {
                averageContent
            } else if let lastNightData {
                lastNightContent(lastNightData)
            } else {
                GuidanceEmptyState(
                    icon: "moon.zzz",
                    title: "No recent night available",
                    message: "A recent Apple Health sleep sample has not synced yet."
                )
                .appSurface(.quiet)
            }
        }
        .accessibilityIdentifier("wellness_sleep_evidence")
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Sleep range", selection: $selectedRange) {
                ForEach(SleepEvidenceRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Sleep range", selection: $selectedRange) {
                ForEach(SleepEvidenceRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var averageContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Sleep Score",
                    value: report.averageSleepScore.formatted(),
                    accent: sleepScoreColor(report.averageSleepScore)
                ),
                AppMetricItem(
                    label: "Time Asleep",
                    value: formatDuration(report.averageTimeAsleep),
                    accent: AppPalette.recovery
                ),
                AppMetricItem(
                    label: "Consistency",
                    value: "\(report.sleepConsistencyScore)/100",
                    accent: AppPalette.effort
                )
            ])

            Divider()

            Text(report.sleepConsistencyMessage)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SleepStageDistribution(
                awake: report.averageTimeAwake,
                rem: report.averageTimeInREM,
                core: report.averageTimeInCore,
                deep: report.averageTimeInDeep,
                unspecified: max(0, report.averageTimeAsleep - report.averageTimeInCore - report.averageTimeInDeep - report.averageTimeInREM)
            )
        }
        .appSurface(.quiet)
    }

    private func lastNightContent(_ data: EnhancedSleepReport.DailySleepStageData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppMetricStrip(items: [
                AppMetricItem(label: "Time Asleep", value: formatDuration(data.timeAsleep), accent: AppPalette.recovery),
                AppMetricItem(label: "Time in Bed", value: data.timeInBed > 0 ? formatDuration(data.timeInBed) : "Not reported", accent: AppPalette.effort),
                AppMetricItem(label: "Awake", value: formatDuration(data.timeAwake), accent: .gray)
            ])

            Divider()

            SleepStageDistribution(
                awake: data.timeAwake,
                rem: data.timeREM,
                core: data.timeCore,
                deep: data.timeDeep,
                unspecified: max(0, data.timeAsleep - data.timeCore - data.timeDeep - data.timeREM)
            )
        }
        .appSurface(.quiet)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: return AppPalette.positive
        case 70..<85: return AppPalette.achievement
        case 50..<70: return AppPalette.caution
        default: return AppPalette.critical
        }
    }
}

private struct SleepStageDistribution: View {
    let awake: TimeInterval
    let rem: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    var unspecified: TimeInterval = 0

    private var total: TimeInterval { awake + rem + core + deep + unspecified }

    private var stages: [(name: String, value: TimeInterval, color: Color)] {
        [
            ("Awake", awake, .gray),
            ("REM", rem, .purple),
            ("Core", core, .blue),
            ("Deep", deep, .indigo),
            ("Unspecified", unspecified, .gray)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Stage Distribution")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            GeometryReader { geometry in
                if total > 0 {
                    HStack(spacing: 2) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                            stage.color
                                .frame(width: max(0, geometry.size.width * (stage.value / total)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    AppPalette.control
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    HStack(spacing: AppSpacing.compact) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 8, height: 8)
                        Text(stage.name)
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.text)
                        Spacer(minLength: AppSpacing.compact)
                        Text(formatDuration(stage.value))
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, AppSpacing.compact)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stage.name), \(formatDuration(stage.value))")

                    if index < stages.count - 1 { Divider() }
                }
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct SleepHistoryDetailView: View {
    let report: EnhancedSleepReport
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var accountChanged = false
    @State private var routine = SleepRoutineNotes()
    @State private var savedRoutine: SleepRoutineNotes?
    @FocusState private var focusedNight: String?
    @State private var owner: String?
    @State private var noteError: String?
    @State private var confirmsDiscard = false

    private var hasEdits: Bool {
        savedRoutine.map { $0 != routine } ?? false
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section("Recorded sleep") {
                LabeledContent("Dates", value: report.dateRange)
                LabeledContent("Recorded nights", value: "\(report.dailySleepData.count) of \(report.requestedDayCount ?? report.dailySleepData.count)")
                LabeledContent("Average recorded sleep", value: duration(report.averageTimeAsleep))
                Text("Missing nights are not zero sleep. Night dates use the evening on which each 18:00–18:00 window begins, in the report timezone. Daytime episodes remain visible.")
                    .font(.caption).foregroundStyle(.secondary)
                if let notice = report.evidenceNotice { Text(notice).foregroundStyle(.secondary) }
            }
            if !report.nightEvidence.isEmpty {
                Section("Sleep windows") {
                    SleepWindowChart(report: report) { night in
                        proxy.scrollTo(night.id, anchor: .top)
                    }
                }
            }
            Section("Your routine") {
                Toggle("Compare with a preferred sleep window", isOn: $routine.usesPreferredWindow)
                    .disabled(savedRoutine == nil)
                if routine.usesPreferredWindow {
                    DatePicker("Bedtime", selection: minuteBinding(\.preferredBedtimeMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Wake time", selection: minuteBinding(\.preferredWakeMinutes), displayedComponents: .hourAndMinute)
                }
                Text("A personal planning preference. It does not change Apple Health records or prescribe how much sleep you need.")
                    .font(.caption).foregroundStyle(.secondary)
                if savedRoutine == nil, let noteError {
                    Text(noteError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    Button("Retry loading notes", action: loadNotes)
                }
            }
            if report.nightEvidence.isEmpty {
                Section("Earlier report") {
                    Text("This earlier report has aggregate durations. Refresh the selected dates in Reports to inspect source intervals.")
                }
            }
            ForEach(report.nightEvidence.reversed()) { night in
                Section("Night of \(formatDate(night.night, zone: night.timeZoneIdentifier, includesTime: false))") {
                    LabeledContent("Recorded asleep", value: duration(night.timeAsleep)).id(night.id)
                        .accessibilityIdentifier("sleep_selected_night")
                    if night.timeInBed > 0 { LabeledContent("Recorded in bed", value: duration(night.timeInBed)) } else { Text("Time in bed was not reported.").foregroundStyle(.secondary) }
                    LabeledContent("Sleep episodes", value: "\(night.episodes.count)")
                    if night.daytimeEpisodeCount > 0 {
                        Text("\(night.daytimeEpisodeCount) daytime episode(s), possibly naps or a daytime sleep schedule.").font(.caption)
                    }
                    if routine.usesPreferredWindow, let first = night.firstSleep {
                        Text("First recorded sleep: \(formatDate(first, zone: night.timeZoneIdentifier, includesTime: true)); preferred bedtime: \(timeString(routine.preferredBedtimeMinutes)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Device-reported stage estimates") {
                        LabeledContent("Core", value: duration(night.timeCore))
                        LabeledContent("Deep", value: duration(night.timeDeep))
                        LabeledContent("REM", value: duration(night.timeREM))
                        LabeledContent("Unspecified or conflicting", value: duration(night.timeUnspecified))
                        Text("Overlapping sleep intervals count once. Conflicting detailed stages stay unspecified; no source is assumed more accurate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Sources and intervals") {
                        Text(night.sourceNames.isEmpty ? "Source name unavailable" : night.sourceNames.joined(separator: ", "))
                        LabeledContent("Report timezone", value: night.timeZoneIdentifier)
                        if !night.sourceTimeZones.isEmpty { Text("Source timezones: \(night.sourceTimeZones.joined(separator: ", "))").font(.caption) }
                        LabeledContent("Source records", value: "\(night.sourceSampleIDs.count)")
                        ForEach(Array(night.episodes.enumerated()), id: \.offset) { _, interval in
                            Text("\(formatDate(interval.start, zone: night.timeZoneIdentifier, includesTime: true)) – \(formatDate(interval.end, zone: night.timeZoneIdentifier, includesTime: true))")
                                .font(.caption)
                        }
                        Text(SleepNightEvidence.calculationVersion).font(.caption2).foregroundStyle(.secondary)
                    }
                    noteField(for: night.id)
                }
            }
        }
        }
        .appFormStyle()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasEdits {
                VStack(spacing: AppSpacing.compact) {
                    if let noteError {
                        Text(noteError).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Save routine and notes", action: saveNotes)
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("sleep_history_save_notes")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(AppPalette.canvas)
            }
        }
        .navigationTitle("Sleep history").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasEdits && isPresented)
        .interactiveDismissDisabled(hasEdits)
        .toolbar {
            if hasEdits && isPresented {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.backward") { confirmsDiscard = true }
                }
            }
        }
        .alert("Discard unsaved sleep changes?", isPresented: $confirmsDiscard) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep_history_detail")
        .opacity(accountChanged ? 0 : 1)
        .accessibilityHidden(accountChanged)
        .allowsHitTesting(!accountChanged)
        .onReceive(appState.$isUserLoggedIn) { _ in
            if let owner, owner != DIContainer.shared.authService.currentUserID { accountChanged = true; dismiss() }
        }
        .onAppear(perform: loadNotes)
        .onChange(of: hasEdits) { _, dirty in
            if !dirty, savedRoutine != nil { noteError = nil }
        }
    }

    private func noteField(for nightID: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.compact) {
            TextField("Optional note for this night", text: Binding(
                get: { routine.nightNotes[nightID] ?? "" },
                set: { routine.nightNotes[nightID] = $0.isEmpty ? nil : String($0.prefix(500)) }), axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedNight, equals: nightID)
                .accessibilityIdentifier("sleep_night_note_\(nightID)")
            if focusedNight == nightID, routine.nightNotes[nightID] != nil {
                Button {
                    routine.nightNotes.removeValue(forKey: nightID)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear note")
                .accessibilityIdentifier("sleep_night_clear_\(nightID)")
            }
        }
        .disabled(savedRoutine == nil)
    }

    private func formatDate(_ date: Date, zone: String, includesTime: Bool) -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateStyle = .medium; formatter.timeStyle = includesTime ? .short : .none
        return formatter.string(from: date)
    }
    private func minuteBinding(_ keyPath: WritableKeyPath<SleepRoutineNotes, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: routine[keyPath: keyPath] / 60,
                minute: routine[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            routine[keyPath: keyPath] = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
        })
    }
    private func timeString(_ minutes: Int) -> String {
        (Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date())
            .formatted(date: .omitted, time: .shortened)
    }
    private func loadNotes() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        guard owner == nil || owner == userID else { accountChanged = true; dismiss(); return }
        guard savedRoutine == nil else { return }
        owner = userID
        do {
            var loaded = try SleepRoutineNoteStore.load(userID: userID)
            loaded.nightNotes = loaded.nightNotes.filter { !$0.value.isEmpty }
            routine = loaded
            savedRoutine = loaded
            noteError = nil
        } catch {
            noteError = "Your saved routine and notes couldn’t be opened."
        }
    }

    private func saveNotes() {
        guard hasEdits, let owner else { return }
        do {
            try SleepRoutineNoteStore.save(routine, userID: owner, currentUserID: DIContainer.shared.authService.currentUserID)
            savedRoutine = routine
            focusedNight = nil
            noteError = nil
            ToastManager.shared.showToast(message: "Sleep changes saved on this device.")
        } catch { noteError = "Routine notes could not be saved. Your edits are still here." }
    }
    private func duration(_ value: Double) -> String {
        let minutes = max(0, Int((value / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private struct SleepWindowChart: View {
    let report: EnhancedSleepReport
    let select: (SleepNightEvidence) -> Void
    @Environment(\.locale) private var locale
    @State private var page = 0

    var body: some View {
        if let first = report.nightEvidence.min(by: { $0.night < $1.night }),
           let last = report.nightEvidence.max(by: { $0.night < $1.night }),
           let zone = TimeZone(identifier: first.timeZoneIdentifier) {
            let calendar = reportCalendar(zone)
            let range = report.requestedNights ?? first.night...last.night
            let count = (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.lowerBound),
                                                 to: calendar.startOfDay(for: range.upperBound)).day ?? 0) + 1
            let offset = min(page, max(0, (count - 1) / 7)) * 7
            let dates = (offset..<min(offset + 7, count)).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: range.upperBound))
            }
            let byDay = Dictionary(grouping: report.nightEvidence) { calendar.startOfDay(for: $0.night) }
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                if count > 7 {
                    HStack {
                        Button("Earlier", systemImage: "chevron.left") { page += 1 }.disabled(offset + 7 >= count)
                        Spacer()
                        Button("Later", systemImage: "chevron.right") { page -= 1 }.disabled(offset == 0)
                    }.appTextRole(.secondary)
                }
                HStack {
                    Color.clear.frame(width: 53, height: 1)
                    HStack(spacing: 0) {
                        let hours = [18, 0, 6, 12, 18]
                        ForEach(hours.indices, id: \.self) { index in
                            if index > 0 { Spacer(minLength: 0) }
                            Text(clockLabel(hour: hours[index], calendar: calendar)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }.appTextRole(.caption).foregroundStyle(.secondary)
                    Color.clear.frame(width: 9, height: 1)
                }
                ForEach(dates, id: \.self) { date in
                    let dateLabel = Text(date, format: Date.FormatStyle(timeZone: zone).month(.abbreviated).day())
                        .frame(width: 53, alignment: .leading).appTextRole(.caption)
                    if let night = byDay[date]?.first {
                        Button { select(night) } label: {
                            HStack {
                                dateLabel
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.quaternary).frame(height: 3)
                                        ForEach(Array(night.clockSegments.enumerated()), id: \.offset) { _, part in
                                            Capsule().fill(AppPalette.recovery)
                                                .frame(width: max(1, geo.size.width * (part.upperBound - part.lowerBound) / 24), height: 9)
                                                .offset(x: geo.size.width * part.lowerBound / 24)
                                        }
                                    }.frame(maxHeight: .infinity)
                                }
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary).frame(width: 9)
                            }.frame(minHeight: 36).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("sleep_window_recorded")
                    } else {
                        HStack {
                            dateLabel
                            Text("No record").appTextRole(.caption).foregroundStyle(.secondary)
                            Capsule().fill(.quaternary).frame(height: 2)
                            Color.clear.frame(width: 9, height: 1)
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("sleep_window_missing")
                    }
                }
                Text("Sleep window · " + zone.identifier.replacingOccurrences(of: "_", with: " "))
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clockLabel(hour: Int, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let usesDayPeriod = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") == true
        formatter.setLocalizedDateFormatFromTemplate(usesDayPeriod ? "j" : "jm")
        let time = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: hour))
        return time.map(formatter.string(from:)) ?? ""
    }

    private func reportCalendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
