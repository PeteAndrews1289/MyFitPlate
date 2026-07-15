import MyFitPlateCore

import SwiftUI

struct WorkoutReport {
    let totalWorkouts: Int
    let totalCaloriesBurned: Double
    let mostFrequentWorkout: String
}

struct WorkoutReportCard: View {
    let report: WorkoutReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Workout summary",
                subtitle: "Training volume and most frequent activity."
            ) {
                Image(systemName: "chevron.right")
                    .appTextRole(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Workouts", value: report.totalWorkouts.formatted(), accent: AppPalette.effort),
                AppMetricItem(
                    label: "Calories",
                    value: "\(Int(report.totalCaloriesBurned.rounded()).formatted()) cal",
                    accent: AppPalette.caution
                )
            ])

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 30, height: 30)
                    .background(Color(UIColor.secondarySystemFill), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Most frequent")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Text(report.mostFrequentWorkout)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .appSurface(.quiet)
    }
}
