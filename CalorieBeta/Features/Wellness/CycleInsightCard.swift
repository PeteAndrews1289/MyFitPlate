import MyFitPlateCore
import SwiftUI

struct MaiaCycleInsightCard: View {
    let insight: AIInsight

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppSectionHeader(
                title: "Maia Phase Guide",
                subtitle: "AI guidance from your estimated phase and recent logs"
            ) {
                Image(systemName: "sparkles")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(AppPalette.brandText)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text(insight.phaseTitle)
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text(insight.phaseDescription)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(.emphasized)

            AppMetricStrip(items: [
                AppMetricItem(label: "Estimated Pattern", value: insight.hormonalState, accent: AppPalette.recovery),
                AppMetricItem(label: "Energy Cue", value: insight.energyLevel, accent: AppPalette.effort)
            ])
            .appSurface(.quiet)

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(title: "Suggested Focus")

                VStack(spacing: 0) {
                    AppListRow(
                        icon: "figure.strengthtraining.traditional",
                        iconColor: AppPalette.brand,
                        title: insight.trainingFocus.title,
                        subtitle: insight.trainingFocus.description
                    )

                    Divider()
                        .padding(.leading, 60)

                    AppListRow(
                        icon: "fork.knife",
                        iconColor: AppPalette.energy,
                        title: "Nutrition",
                        subtitle: insight.nutritionTip
                    )

                    Divider()
                        .padding(.leading, 60)

                    AppListRow(
                        icon: "heart.text.square",
                        iconColor: AppPalette.recovery,
                        title: "Symptoms",
                        subtitle: insight.symptomTip
                    )
                }
                .appSurface(.quiet, padding: 0)
            }

            Text("Calendar phases and AI guidance are estimates. They do not measure hormones, predict fertility, or replace medical advice.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("maia_cycle_insight")
    }
}
