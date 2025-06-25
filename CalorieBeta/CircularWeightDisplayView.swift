
import SwiftUI

struct CircularWeightDisplayView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    
    var currentWeight: Double
    var lastUpdateDate: Date? 
    var progress: Double // Percentage 0-1.0
    var goalWeight: Double?
    var initialWeightForGoal: Double?

    private var weightString: String {
        String(format: "%.1f", currentWeight)
    }

    private var dateString: String {
        if let date = lastUpdateDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "No recent update"
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(lineWidth: 16)
                    .opacity(0.15)
                    .foregroundColor(Color.accentColor)

                Circle()
                    .trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                    .foregroundColor(Color.accentColor)
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.linear(duration: 0.75), value: progress)

                VStack {
                    Text(weightString)
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(Color.accentColor)
                    Text("lb")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text(dateString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 200, height: 200)
            .padding(.bottom, 10)
            
            if let gw = goalWeight, let iw = initialWeightForGoal {
                 HStack {
                    Text(String(format: "Initial: %.1f lb", iw))
                    Spacer()
                    Text(String(format: "Goal: %.1f lb", gw))
                 }
                 .font(.caption)
                 .foregroundColor(.gray)
                 .padding(.horizontal, 40)
            }
        }
    }
}
