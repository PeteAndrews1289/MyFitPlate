import SwiftUI

struct FastingTrackerCard: View {
    @ObservedObject var fastingManager = FastingManager.shared

    let fastOptions = [12, 14, 16, 18, 20]
    @State private var selectedFastDuration = 16
    @State private var showingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if fastingManager.isFasting,
               let start = fastingManager.currentFastStartTime,
               let end = fastingManager.currentFastTargetEndTime {
                activeFastView(start: start, end: end)
            } else {
                readyView
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("Intermittent Fasting")
                .font(.headline)
            Spacer()
            if fastingManager.isFasting {
                Text(fastingManager.fastType)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Button(action: { showingOptions.toggle() }) {
                    Text("\(selectedFastDuration):\(24 - selectedFastDuration)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .confirmationDialog("Select fast length", isPresented: $showingOptions, titleVisibility: .visible) {
                    ForEach(fastOptions, id: \.self) { hours in
                        Button("\(hours):\(24 - hours)  (\(hours)h fast)") { selectedFastDuration = hours }
                    }
                }
            }
        }
    }

    // MARK: - Active fast

    @ViewBuilder
    private func activeFastView(start: Date, end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let total = max(1, end.timeIntervalSince(start))
            let elapsed = min(max(0, now.timeIntervalSince(start)), total)
            let remaining = max(0, end.timeIntervalSince(now))
            let progress = elapsed / total
            let stage = fastingStage(hours: elapsed / 3600)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 3) {
                        Text(remaining > 0 ? "REMAINING" : "COMPLETE")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                        Text(format(remaining))
                            .appFont(size: 34, weight: .bold)
                            .monospacedDigit()
                            .foregroundColor(.orange)
                        Text("\(Int((progress * 100).rounded()))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 210, height: 210)
                .padding(.top, 4)

                HStack(spacing: 10) {
                    Image(systemName: stage.icon)
                        .foregroundColor(.orange)
                        .frame(width: 34, height: 34)
                        .background(Color.orange.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stage.name).font(.subheadline.weight(.bold))
                        Text(stage.detail).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    timeColumn("Started", start)
                    Spacer()
                    timeColumn("Goal", end)
                }

                Button(action: { fastingManager.endFast() }) {
                    Text("End Fast")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Ready state

    private var readyView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Ready to start a \(selectedFastDuration):\(24 - selectedFastDuration) fast")
                    .font(.subheadline.weight(.semibold))
                Text("You'll move through these stages:")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(stageMilestones, id: \.hour) { milestone in
                    HStack(spacing: 10) {
                        Text("\(milestone.hour)h")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                            .frame(width: 30, alignment: .leading)
                        Image(systemName: milestone.icon).foregroundColor(.orange).font(.caption)
                        Text(milestone.name).font(.caption.weight(.semibold))
                        Spacer()
                        Text(milestone.detail).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: { fastingManager.startFast(hours: selectedFastDuration) }) {
                Text("Start Fast")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func timeColumn(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundColor(.secondary)
            Text(date, format: .dateTime.hour().minute()).font(.subheadline.weight(.semibold))
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func fastingStage(hours: Double) -> (name: String, detail: String, icon: String) {
        switch hours {
        case ..<4:    return ("Fed", "Digesting your last meal", "fork.knife")
        case 4..<12:  return ("Stabilizing", "Blood sugar settling, glycogen burning", "arrow.down.right")
        case 12..<16: return ("Fat Burning", "Switching to stored fat for fuel", "flame.fill")
        case 16..<24: return ("Ketosis", "Producing ketones for deep fat burn", "bolt.fill")
        default:      return ("Autophagy", "Cellular cleanup in full swing", "sparkles")
        }
    }

    private let stageMilestones: [(hour: Int, name: String, detail: String, icon: String)] = [
        (0, "Fed", "Digesting", "fork.knife"),
        (4, "Stabilizing", "Glycogen burn", "arrow.down.right"),
        (12, "Fat Burning", "Fat for fuel", "flame.fill"),
        (16, "Ketosis", "Deep fat burn", "bolt.fill")
    ]
}

#Preview {
    FastingTrackerCard()
        .padding()
}
