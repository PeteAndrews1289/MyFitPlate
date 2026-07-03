import SwiftUI

// An honest glance: current weight, the goal, and the gap in words. The old
// version drew a progress ring hardcoded to 0.3 — a chart that lies is worse
// than no chart. Weigh-ins happen on the phone; the watch just answers
// "where am I?".
struct WeightTracker: View {
    @EnvironmentObject var appDelegate: AppDelegate

    private var current: Double { appDelegate.userWeight }
    private var goal: Double { appDelegate.goalWeight }

    private var unit: String { appDelegate.usesMetric ? "kg" : "lbs" }

    private func display(_ lbs: Double) -> String {
        let value = appDelegate.usesMetric ? lbs * 0.45359237 : lbs
        return appDelegate.usesMetric ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    private var gapLine: String? {
        guard current > 0, goal > 0 else { return nil }
        let gapLbs = abs(current - goal)
        if gapLbs < 1 { return "At your goal" }
        return "\(display(gapLbs)) \(unit) to go"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if current > 0 {
                    Text("\(display(current)) \(unit)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())

                    if goal > 0 {
                        Text("Goal \(display(goal)) \(unit)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if let gapLine {
                        Text(gapLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(gapLine == "At your goal" ? WatchPalette.brandPrimary : .primary)
                    }

                    Text("Log weigh-ins on your phone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                } else {
                    Text("No weight yet")
                        .font(.headline)
                    Text("Open MyFitPlate on your phone to sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Weight")
    }
}
