import SwiftUI

struct CircularWeightDisplayView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    
    var currentWeight: Double
    var lastUpdateDate: Date?
    var progress: Double
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
                    .foregroundColor(Color.brandPrimary)

                Circle()
                    .trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                    .foregroundColor(Color.brandPrimary)
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.linear(duration: 0.75), value: progress)

                VStack {
                    Text(weightString)
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(Color.brandPrimary)
                    Text("lb")
                        .appFont(size: 20)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text(dateString)
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
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
                 .appFont(size: 12)
                 .foregroundColor(Color(UIColor.secondaryLabel))
                 .padding(.horizontal, 40)
            }
        }
    }
}
