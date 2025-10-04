import SwiftUI

struct WorkoutInsightRowView: View {
    let insight: WorkoutAnalysisInsight
    
    private var iconName: String {
        switch insight.category {
        case "Performance": return "chart.bar.xaxis"
        case "Consistency": return "calendar.badge.clock"
        case "Recovery": return "moon.zzz.fill"
        case "Nutrition": return "fork.knife"
        case "Mindset": return "brain.head.profile"
        default: return "sparkle"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(.brandPrimary)
                .frame(width: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .appFont(size: 16, weight: .bold)
                
                Text(insight.message)
                    .appFont(size: 14)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}