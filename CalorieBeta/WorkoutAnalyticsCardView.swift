import SwiftUI

struct WorkoutAnalyticsCardView: View {
    let analytics: WorkoutAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Workout Analysis")
                .appFont(size: 20, weight: .bold)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(analytics.totalVolume)) lbs")
                        .appFont(size: 18, weight: .semibold)
                }
                Spacer()
                VStack(alignment: .leading) {
                    Text("New PRs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(analytics.personalRecords.count)")
                        .appFont(size: 18, weight: .semibold)
                }
            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(10)
            
            Divider()
            
            // Use the new, specific view for the insights list
            WorkoutInsightListView(insights: analytics.aiInsights)
        }
        .padding()
        .background(Color.backgroundPrimary)
        .cornerRadius(15)
        .shadow(radius: 3)
    }
}
