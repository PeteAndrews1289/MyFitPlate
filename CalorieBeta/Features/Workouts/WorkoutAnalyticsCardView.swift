import MyFitPlateCore

import SwiftUI

struct WorkoutAnalyticsCardView: View {
    let analytics: WorkoutAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Workout Analysis",
                    subtitle: "Current saved totals and detected personal records."
                )

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Total volume",
                        value: "\(Int(analytics.totalVolume).formatted()) lb"
                    ),
                    AppMetricItem(
                        label: "Personal records",
                        value: analytics.personalRecords.count.formatted(),
                        accent: .accentPositive
                    )
                ])
                .appSurface(.emphasized)
            }

            WorkoutInsightListView(insights: analytics.aiInsights)
        }
    }
}
