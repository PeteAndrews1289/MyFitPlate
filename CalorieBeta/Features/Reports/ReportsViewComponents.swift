import MyFitPlateCore

import SwiftUI

enum ReportFocus: String, CaseIterable, Identifiable {
    case nutrition, training, recovery
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct ReportNutritionSummary: View {
    let summary: ReportSummary?
    let period: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Nutrition", subtitle: period)
            if let summary, summary.daysLogged > 0 {
                AppMetricStrip(items: [
                    AppMetricItem(label: "Daily calories", value: "\(Int(summary.averageCalories.rounded()).formatted()) cal", accent: AppPalette.energy),
                    AppMetricItem(label: "Daily protein", value: "\(Int(summary.averageProtein.rounded()).formatted()) g", accent: AppPalette.protein)
                ])
                Text("Averages from \(summary.daysLogged.formatted()) fully logged \(summary.daysLogged == 1 ? "day" : "days"). Partial days are excluded.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("reports_nutrition_evidence")
            } else {
                Text("Confirm fully logged days in your diary to see meaningful intake averages.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
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
