import MyFitPlateCore

import SwiftUI

struct ReportsOverviewCard: View {
    let selectedTimeframe: ReportTimeframe
    let customStartDate: Date
    let customEndDate: Date
    let summary: ReportSummary?
    let wellnessScore: WellnessScore?
    let workoutReport: WorkoutReport?
    let sleepReport: EnhancedSleepReport?
    let onOpenInsights: () -> Void

    private var periodTitle: String {
        if selectedTimeframe == .custom {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
        return selectedTimeframe.rawValue
    }

    private var overviewMessage: String {
        if let wellnessScore {
            return wellnessScore.summary
        }
        if let summary, summary.daysLogged > 0 {
            return "\(summary.daysLogged) logged \(summary.daysLogged == 1 ? "day" : "days") in this timeframe."
        }
        if workoutReport != nil || sleepReport != nil {
            return "Activity or sleep data is available for this timeframe."
        }
        return "Start logging to build a useful report."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "At a glance", subtitle: periodTitle) {
                Button(action: onOpenInsights) {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Generate detailed insights")
            }

            Text(overviewMessage)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AppMetricStrip(items: [
                AppMetricItem(
                    label: wellnessScore?.isNutritionOnly == true ? "Nutrition" : "Wellness",
                    value: wellnessScore.map { "\($0.overallScore)" } ?? "--",
                    accent: wellnessScore?.color ?? Color.secondary
                ),
                AppMetricItem(
                    label: "Avg calories",
                    value: summary.map { "\(Int($0.averageCalories.rounded()).formatted()) cal" } ?? "--",
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Workouts",
                    value: workoutReport.map { $0.totalWorkouts.formatted() } ?? "--",
                    accent: AppPalette.effort
                ),
                AppMetricItem(
                    label: "Sleep score",
                    value: sleepReport.map { $0.averageSleepScore.formatted() } ?? "--",
                    accent: AppPalette.recovery
                )
            ])
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("reports_overview")
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
