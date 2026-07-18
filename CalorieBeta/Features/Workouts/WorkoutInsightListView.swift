import MyFitPlateCore

import SwiftUI

struct WorkoutInsightListView: View {
    let insights: [WorkoutAnalysisInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Maia Workout Insights",
                subtitle: insights.isEmpty
                    ? "Patterns will appear as your training history grows."
                    : "Patterns detected across your recent training."
            )

            if insights.isEmpty {
                Text("Complete a few more workouts to unlock personalized observations.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, AppSpacing.compact)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        WorkoutInsightRowView(insight: insight)

                        if index < insights.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .appSurface(.quiet)
            }
        }
        .accessibilityIdentifier("workout_insights")
    }
}
