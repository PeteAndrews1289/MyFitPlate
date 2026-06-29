import SwiftUI
import ActivityKit

struct WorkoutSessionControlBar: View {
    let completedSets: Int
    let totalSets: Int
    let remainingSets: Int
    @Binding var isAutoRestEnabled: Bool
    let onPlateCalculator: () -> Void
    let onFinish: () -> Void

    private var progressText: String {
        totalSets == 0 ? "No sets planned" : "\(completedSets)/\(totalSets) sets complete"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                autoRestToggleView
                plateCalculatorButton
            }

            Button(action: {
                HapticManager.instance.notification(.success)
                onFinish()
            }) {
                HStack {
                    Label("Finish Workout", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Text(remainingSets == 0 ? "Ready" : "\(remainingSets) left")
                        .appFont(size: 12, weight: .bold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Text(progressText)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var autoRestToggleView: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .appFont(size: 12, weight: .bold)
                .foregroundColor(isAutoRestEnabled ? .accentPositive : Color(UIColor.secondaryLabel))

            VStack(alignment: .leading, spacing: 1) {
                Text("Auto Rest")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(isAutoRestEnabled ? "On after each set" : "Manual timer")
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Toggle("", isOn: $isAutoRestEnabled)
                .labelsHidden()
                .tint(.accentPositive)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var plateCalculatorButton: some View {
        Button(action: onPlateCalculator) {
            VStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .appFont(size: 15, weight: .bold)
                Text("Plates")
                    .appFont(size: 11, weight: .bold)
            }
            .foregroundColor(.brandPrimary)
            .frame(width: 72, height: 58)
            .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: isCompact ? 8 : 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if !isCompact {
                        Text("Live Workout")
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .textCase(.uppercase)
                    }

                    Text(routineName)
                        .appFont(size: isCompact ? 16 : 23, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(isCompact ? 1 : 2)

                    if !isCompact {
                        Text("Now: \(currentExerciseName)")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                        .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close workout")
            }

            VStack(alignment: .leading, spacing: 8) {
                if !isCompact {
                    HStack {
                        Text("\(completedSets) of \(max(totalSets, 0)) sets")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))

                        Spacer()

                        Text("\(Int((progress * 100).rounded()))%")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.brandPrimary)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPrimary.opacity(0.12))

                        Capsule()
                            .fill(Color.brandPrimary)
                            .frame(width: geometry.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.25), value: progress)
                    }
                }
                .frame(height: 8)
            }

            if !isCompact {
                HStack(spacing: 10) {
                    WorkoutHeaderMetric(title: "Elapsed", value: elapsedTime, icon: "clock.fill", color: .blue)
                    WorkoutHeaderMetric(title: "Exercises", value: "\(completedExercises)/\(totalExercises)", icon: "list.bullet", color: .orange)

                    if let restTime {
                        Button(action: onStopRest) {
                            WorkoutHeaderMetric(title: "Rest", value: restTime, icon: "timer", color: .accentPositive)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop rest timer")
                    } else {
                        WorkoutHeaderMetric(title: "Rest", value: "Ready", icon: "timer", color: .accentPositive)
                    }
                }
            }
        }
        .asCard()
    }
}

struct WorkoutHeaderMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .appFont(size: 10, weight: .bold)
                    .foregroundColor(color)

                Text(title)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Text(value)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
