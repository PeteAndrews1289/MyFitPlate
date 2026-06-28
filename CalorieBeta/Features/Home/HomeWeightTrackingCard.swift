import SwiftUI
import Charts

struct HomeWeightTrackingCard: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Binding var showingWeightEntrySheet: Bool

    var body: some View {
let history = goalSettings.weightHistory.sorted { $0.date < $1.date }
        let current = history.last?.weight ?? goalSettings.weight
        let recent = Array(history.suffix(30))
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let prior = history.last(where: { $0.date <= weekAgo })?.weight ?? history.first?.weight
        let delta = prior.map { current - $0 }

        return Button(action: { showingWeightEntrySheet = true }) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.teal)
                        Text("Weight")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(current > 0 ? String(format: "%.1f", current) : "--")
                            .appFont(size: 26, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text("lb")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    if let delta, abs(delta) >= 0.05 {
                        let down = delta < 0
                        HStack(spacing: 3) {
                            Image(systemName: down ? "arrow.down.right" : "arrow.up.right")
                                .appFont(size: 10, weight: .bold)
                            Text("\(String(format: "%.1f", abs(BodyUnits.weightDisplayValue(lbs: delta, metric: useMetric)))) \(BodyUnits.weightUnit(metric: useMetric)) · 7d")
                                .appFont(size: 11, weight: .semibold)
                        }
                        .foregroundColor(down ? .accentPositive : .orange)
                    } else {
                        Text("Tap to log today's weight")
                            .appFont(size: 11, weight: .medium)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }

                Spacer(minLength: 8)

                if recent.count >= 2 {
                    Chart {
                        ForEach(recent, id: \.id) { entry in
                            LineMark(x: .value("Date", entry.date), y: .value("Weight", entry.weight))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Color.teal)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 88, height: 42)
                }

                Text("Log")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.teal, in: Capsule())
            }
        }
        .buttonStyle(AnimatedCardButtonStyle())
        .asCard()

}
}
