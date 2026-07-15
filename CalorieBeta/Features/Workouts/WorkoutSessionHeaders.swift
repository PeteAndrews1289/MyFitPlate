import SwiftUI
import ActivityKit
import MyFitPlateCore

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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: AppSpacing.compact) {
            HStack(spacing: 6) {
                Label("\(remainingSets) sets left", systemImage: "checklist")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .appFont(size: 12, weight: .bold)
                        .foregroundStyle(isAutoRestEnabled ? AppPalette.recovery : Color.secondary)

                    Text("Auto rest")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(1)

                    Toggle("", isOn: $isAutoRestEnabled)
                        .labelsHidden()
                        .tint(AppPalette.recovery)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Auto rest timer")
                .accessibilityValue(isAutoRestEnabled ? "On" : "Off")
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppSpacing.compact) {
                        actionButtons
                    }
                } else {
                    HStack(spacing: AppSpacing.compact) {
                        actionButtons
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.control)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workout controls. \(completedSets) of \(totalSets) sets complete.")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action: onPlateCalculator) {
            Label("Plate math", systemImage: "square.stack.3d.up.fill")
        }
        .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: dynamicTypeSize.isAccessibilitySize))
        .accessibilityLabel("Plate calculator")

        Button(action: {
            HapticManager.instance.notification(.success)
            onFinish()
        }) {
            Label("Finish Workout", systemImage: "checkmark.seal.fill")
        }
        .buttonStyle(AppActionButtonStyle(.primary))
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            sessionIdentity

            AppProgressTrack(progress: progress, role: .effort, height: 7)
                .accessibilityElement()
                .accessibilityLabel("Workout progress")
                .accessibilityValue("\(completedSets) of \(totalSets) sets complete")

            if !isCompact {
                currentSetContext
            }
        }
        .appSurface(.quiet)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppPalette.effort)
                .frame(width: 4)
                .padding(.vertical, AppSpacing.row)
        }
    }

    @ViewBuilder
    private var sessionIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .center) {
                    Text("IN SESSION")
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(AppPalette.effort)

                    Spacer(minLength: AppSpacing.compact)

                    closeButton
                }

                Text(routineName)
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    Text(elapsedTime)
                        .appFont(size: 17, weight: .semibold)
                        .foregroundStyle(AppPalette.text)
                        .monospacedDigit()

                    Text("elapsed")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IN SESSION")
                        .appTextRole(.caption)
                        .foregroundStyle(AppPalette.effort)

                    Text(routineName)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(elapsedTime)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .monospacedDigit()

                    Text("Elapsed")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }

                closeButton
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(AppIconButtonStyle(.neutral))
        .accessibilityLabel("Close workout")
    }

    @ViewBuilder
    private var currentSetContext: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(spacing: AppSpacing.compact) {
                    setBadge
                    Spacer(minLength: 0)
                    restBadge
                }

                Text(currentExerciseName)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: 8) {
                setBadge

                Text(currentExerciseName)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)
                restBadge
            }
        }
    }

    private var setBadge: some View {
        AppStatusBadge(
            "Set \(min(completedSets + 1, max(totalSets, 1))) of \(max(totalSets, 1))",
            role: .effort
        )
    }

    @ViewBuilder
    private var restBadge: some View {
        if let restTime {
            Button(action: onStopRest) {
                AppStatusBadge("Rest \(restTime)", icon: "timer", role: .recovery)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest timer \(restTime). Double tap to stop.")
        }
    }
}
