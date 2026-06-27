import SwiftUI

/// This is the new "Fitness Analytics" page.
/// It combines workout analytics with related health data like sleep and nutrition.
struct WorkoutAnalyticsView: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                Text("Your fitness deep-dive. See how your workouts, nutrition, and recovery all work together.")
                    .appFont(size: 15)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.bottom, 10)

                // 1. The Workout Analytics Card
                // This now checks if analytics are available
                if let analytics = viewModel.workoutAnalytics {
                    WorkoutAnalyticsCardView(analytics: analytics)
                } else {
                    // This is the new loading cue
                    VStack(spacing: 12) {
                        ProgressView("Analyzing your performance...")
                        Text("This may take a moment...")
                            .appFont(size: 12)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color.backgroundSecondary)
                    .cornerRadius(15)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Fitness Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
