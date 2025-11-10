
import SwiftUI

struct WorkoutInsightListView: View {
    let insights: [WorkoutAnalysisInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.brandPrimary)
                Text("Maia's Workout Insights")
                    .appFont(size: 18, weight: .bold)
            }
            
            if insights.isEmpty {
                Text("Keep logging your workouts to unlock personalized insights from Maia!")
                    .appFont(size: 14)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ForEach(insights) { insight in
                    WorkoutInsightRowView(insight: insight)
                    if insight != insights.last {
                        Divider()
                    }
                }
            }
        }
    }
}
