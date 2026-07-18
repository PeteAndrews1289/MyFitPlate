import SwiftUI

struct MacroProgressRow: View {
    let label: String
    let value: Double
    let goal: Double
    let unit: String
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(max(value / goal, 0), 1)
    }

    private var valueText: String {
        Int(value.rounded()).formatted()
    }

    private var goalText: String {
        Int(goal.rounded()).formatted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .appFont(size: 14, weight: .medium)
                Spacer()
                Text("\(valueText) / \(goalText) \(unit)")
                    .appFont(size: 12, weight: .regular)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
    }
}
