import MyFitPlateCore

import SwiftUI

struct WorkoutReport {
    let totalWorkouts: Int
    let activeDays: Int
    let totalCaloriesBurned: Double
    let mostFrequentWorkout: String
}

struct WorkoutReportCard: View {
    let report: WorkoutReport

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text("Workout summary").appTextRole(.sectionTitle)
            AppMetricStrip(items: [
                AppMetricItem(label: "Logged workouts", value: report.totalWorkouts.formatted(), accent: AppPalette.effort),
                AppMetricItem(label: "Active days", value: report.activeDays.formatted(), accent: AppPalette.brand)
            ])
            Text("Most frequent: " + report.mostFrequentWorkout)
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if report.totalCaloriesBurned > 0 {
                Text(report.totalCaloriesBurned.formatted(.number.precision(.fractionLength(0))) + " cal recorded across these workouts")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
