import SwiftUI

// This view will display the new, advanced workout analytics.
struct WorkoutAnalyticsCardView: View {
    let analytics: WorkoutAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Workout Analysis")
                .appFont(size: 17, weight: .semibold)

            HStack(spacing: 16) {
                workoutStatBox(value: String(format: "%.0f", analytics.totalVolume), label: "Total Volume (lbs)")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Personal Records This Week")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                if analytics.personalRecords.isEmpty {
                    Text("No new personal records set in the logged workouts this week.")
                        .appFont(size: 14)
                } else {
                    ForEach(analytics.personalRecords.sorted(by: <), id: \.key) { exercise, record in
                        HStack {
                            Text(exercise)
                                .appFont(size: 14, weight: .medium)
                            Spacer()
                            Text(record)
                                .appFont(size: 14)
                                .foregroundColor(.accentPositive)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .asCard()
    }

    @ViewBuilder
    private func workoutStatBox(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .appFont(size: 22, weight: .semibold)
                .foregroundColor(.brandPrimary)
            Text(label)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }
}