import SwiftUI

struct WellnessScoreDetailView: View {
    let wellnessScore: WellnessScore
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Daily Readiness",
                        title: "Wellness Debrief",
                        subtitle: wellnessScore.scopeDescription
                    )

                    scoreOverview
                    signalSection

                    if let mealScore, mealScore.overallScore > 0 {
                        NutritionEvidenceSection(score: mealScore)
                    }

                    if let sleepReport {
                        SleepEvidenceSection(report: sleepReport)
                    }

                    Label(
                        "This score summarizes available wellness signals. It is not a diagnosis or medical recommendation.",
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

            Text(coverageDescription)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coverageDescription: String {
        let count = wellnessScore.availableComponentCount
        return "\(count) of 3 signals available. Missing signals are shown as unavailable and are not estimated."
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Score Signals",
                subtitle: "Each signal is scored independently before the available results are combined."
            )

            VStack(spacing: 0) {
                WellnessSignalRow(
                    icon: "fork.knife",
                    title: "Nutrition",
                    score: wellnessScore.nutritionScore > 0 ? wellnessScore.nutritionScore : nil,
                    description: wellnessScore.nutritionScore > 0
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

                WellnessSignalRow(
                    icon: "heart.fill",
                    title: "Recovery",
                    score: wellnessScore.recoveryScore,
                    description: wellnessScore.recoveryScore == nil
                        ? "No recent resting heart rate or HRV signal is available."
                        : "Readiness estimated from available resting heart rate and HRV.",
                    color: AppPalette.positive
                )
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
                subtitle: "Apple Health sleep stages for \(report.dateRange)."
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
                deep: report.averageTimeInDeep
            )
        }
        .appSurface(.quiet)
    }

    private func lastNightContent(_ data: EnhancedSleepReport.DailySleepStageData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppMetricStrip(items: [
                AppMetricItem(label: "Time Asleep", value: formatDuration(data.timeAsleep), accent: AppPalette.recovery),
                AppMetricItem(label: "Time in Bed", value: formatDuration(data.timeInBed), accent: AppPalette.effort),
                AppMetricItem(label: "Awake", value: formatDuration(data.timeAwake), accent: .gray)
            ])

            Divider()

            SleepStageDistribution(
                awake: data.timeAwake,
                rem: data.timeREM,
                core: data.timeCore,
                deep: data.timeDeep
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

    private var total: TimeInterval { awake + rem + core + deep }

    private var stages: [(name: String, value: TimeInterval, color: Color)] {
        [
            ("Awake", awake, .gray),
            ("REM", rem, .purple),
            ("Core", core, .blue),
            ("Deep", deep, .indigo)
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
