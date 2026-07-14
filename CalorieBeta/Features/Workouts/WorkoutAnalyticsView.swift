import MyFitPlateCore

import SwiftUI

/// This is the new "Fitness Analytics" page.
/// It combines workout analytics with related health data like sleep and nutrition.
struct WorkoutAnalyticsView: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Training Evidence",
                    title: "Fitness Analytics",
                    subtitle: "See how completed workouts, nutrition, and recovery fit together."
                )

                if let analytics = viewModel.workoutAnalytics {
                    WorkoutAnalyticsCardView(analytics: analytics)
                } else {
                    HStack(spacing: AppSpacing.row) {
                        ProgressView()
                            .tint(AppPalette.brand)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Analyzing Your Performance")
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                            Text("Your saved totals remain available while deeper insights load.")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .appSurface(.quiet)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("fitness_analytics")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
