import SwiftUI
import ActivityKit

// DESIGN.md rule 1: in the player, the hero is the set you're doing — header and control
// bar are chrome and stay compact. Progress is stated once (bar + one caption), not five
// ways; the rainbow metric tiles are gone. Green marks "now": the rest countdown and the
// finish action.
struct WorkoutSessionControlBar: View {
    let completedSets: Int
    let totalSets: Int
    let remainingSets: Int
    @Binding var isAutoRestEnabled: Bool
    let onPlateCalculator: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(isAutoRestEnabled ? .accentPositive : Color(UIColor.secondaryLabel))

                Text("Auto rest")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .fixedSize()

                Toggle("", isOn: $isAutoRestEnabled)
                    .labelsHidden()
                    .tint(.accentPositive)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Auto rest timer")
            .accessibilityValue(isAutoRestEnabled ? "On" : "Off")

            Button(action: onPlateCalculator) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .appFont(size: 12, weight: .bold)
                    Text("Plates")
                        .appFont(size: 12, weight: .bold)
                }
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plate math")

            Button(action: {
                HapticManager.instance.notification(.success)
                onFinish()
            }) {
                Label("Finish workout", systemImage: "checkmark.seal.fill")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct WorkoutSessionHeaderCard: View {
    let routineName: String
    let elapsedTime: String
    let restTime: String?
    let completedSets: Int
    let totalSets: Int
    let completedExercises: Int
    let totalExercises: Int
    let progress: Double
    let currentExerciseName: String
    let onClose: () -> Void
    let onStopRest: () -> Void
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(routineName)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(elapsedTime)
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 30, height: 30)
                        .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close workout")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.secondarySystemFill))

                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: geometry.size.width * CGFloat(progress))
                        .animation(.easeInOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Workout progress")
            .accessibilityValue("\(completedSets) of \(totalSets) sets complete")

            if !isCompact {
                HStack(spacing: 8) {
                    Text("\(completedSets) of \(totalSets) sets · Now: \(currentExerciseName)")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 6)

                    if let restTime {
                        Button(action: onStopRest) {
                            HStack(spacing: 5) {
                                Image(systemName: "timer")
                                    .appFont(size: 11, weight: .bold)
                                Text("Rest \(restTime)")
                                    .appFont(size: 12, weight: .bold)
                                    .monospacedDigit()
                                Image(systemName: "xmark.circle.fill")
                                    .appFont(size: 11, weight: .bold)
                                    .opacity(0.7)
                            }
                            .foregroundColor(.accentPositive)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentPositive.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rest timer \(restTime). Double tap to stop.")
                    }
                }
            }
        }
        .asCard()
    }
}
