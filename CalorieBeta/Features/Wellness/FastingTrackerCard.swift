import MyFitPlateCore
import SwiftUI

struct FastingTrackerCard: View {
    @ObservedObject private var fastingManager = FastingManager.shared
    @State private var selectedFastDuration = 16
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let fastOptions = [12, 14, 16, 18, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Fasting Window",
                title: fastingManager.isFasting ? "Fast in Progress" : "Plan a Fast",
                subtitle: fastingManager.isFasting
                    ? "Follow the timer and end early whenever your body asks you to."
                    : "Choose a schedule that fits your day. Individual responses vary."
            )

            if fastingManager.isFasting,
               let start = fastingManager.currentFastStartTime,
               let end = fastingManager.currentFastTargetEndTime {
                activeFastView(start: start, end: end)
            } else {
                readyView
            }

            Text("Fasting is optional and is not appropriate for everyone. Stop if you feel unwell and seek guidance from a qualified clinician when needed.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func activeFastView(start: Date, end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let total = max(1, end.timeIntervalSince(start))
            let elapsed = min(max(0, now.timeIntervalSince(start)), total)
            let remaining = max(0, end.timeIntervalSince(now))
            let progress = elapsed / total
            let stage = fastingStage(hours: elapsed / 3_600)

            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(spacing: AppSpacing.group) {
                    ZStack {
                        Circle()
                            .stroke(AppPalette.separator, lineWidth: 12)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AppPalette.brand,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 4) {
                            Text(remaining > 0 ? "Remaining" : "Complete")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)

                            Text(format(remaining))
                                .appFont(size: 30, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(AppPalette.text)

                            Text("\(Int((progress * 100).rounded()))% complete")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 190, height: 190)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Int((progress * 100).rounded())) percent complete, \(format(remaining)) remaining")

                    AppMetricStrip(items: [
                        AppMetricItem(
                            label: "Started",
                            value: start.formatted(date: .omitted, time: .shortened),
                            accent: AppPalette.effort
                        ),
                        AppMetricItem(
                            label: "Goal",
                            value: end.formatted(date: .omitted, time: .shortened),
                            accent: AppPalette.brand
                        )
                    ])
                }
                .frame(maxWidth: .infinity)
                .appSurface(.emphasized)

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: "Current Stage", subtitle: "A general pattern, not a measurement")

                    AppListRow(
                        icon: stage.icon,
                        iconColor: AppPalette.caution,
                        title: stage.name,
                        subtitle: stage.detail
                    )
                    .appSurface(.quiet, padding: 0)
                }

                Button("End Fast", role: .destructive) {
                    fastingManager.endFast()
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .accessibilityIdentifier("end_fast_button")
            }
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(title: "Schedule", subtitle: "Select your fasting and eating window")

                Menu {
                    ForEach(fastOptions, id: \.self) { hours in
                        Button("\(hours):\(24 - hours) (\(hours)-hour fast)") {
                            selectedFastDuration = hours
                        }
                    }
                } label: {
                    fastingScheduleLabel
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fasting_schedule_picker")
            }

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: "What You May Notice",
                    subtitle: "These are broad timing estimates and vary by person"
                )

                VStack(spacing: 0) {
                    ForEach(Array(stageMilestones.enumerated()), id: \.element.hour) { index, milestone in
                        AppListRow(
                            icon: milestone.icon,
                            iconColor: milestone.color,
                            title: "\(milestone.hour) hours - \(milestone.name)",
                            subtitle: milestone.detail
                        )

                        if index < stageMilestones.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
            }

            Button("Start \(selectedFastDuration)-Hour Fast") {
                fastingManager.startFast(hours: selectedFastDuration)
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("start_fast_button")
        }
    }

    @ViewBuilder
    private var fastingScheduleLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Label("Fasting Schedule", systemImage: "clock")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text("\(selectedFastDuration) hours fasting, \(24 - selectedFastDuration) hours eating")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.compact) {
                    Text("\(selectedFastDuration):\(24 - selectedFastDuration)")
                        .appTextRole(.control)
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(AppPalette.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.group)
            .appSurface(.quiet, padding: 0)
        } else {
            AppListRow(
                icon: "clock",
                iconColor: AppPalette.effort,
                title: "Fasting Schedule",
                subtitle: "\(selectedFastDuration) hours fasting, \(24 - selectedFastDuration) hours eating"
            ) {
                HStack(spacing: 6) {
                    Text("\(selectedFastDuration):\(24 - selectedFastDuration)")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .monospacedDigit()
                    Image(systemName: "chevron.up.chevron.down")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }

    private func fastingStage(hours: Double) -> FastingStage {
        switch hours {
        case ..<4:
            return FastingStage(name: "Fed", detail: "Your body is digesting and absorbing your last meal.", icon: "fork.knife")
        case 4..<12:
            return FastingStage(name: "Post-Meal", detail: "Glucose and insulin generally trend down after eating.", icon: "arrow.down.right")
        case 12..<16:
            return FastingStage(name: "Stored Fuel", detail: "Use of stored energy may gradually increase.", icon: "flame")
        case 16..<24:
            return FastingStage(name: "Extended Window", detail: "Ketone production may rise as the fast continues.", icon: "bolt")
        default:
            return FastingStage(name: "Longer Fast", detail: "Long fasts deserve extra caution and professional guidance.", icon: "exclamationmark.triangle")
        }
    }

    private let stageMilestones: [FastingMilestone] = [
        FastingMilestone(hour: 0, name: "Fed", detail: "Digesting and absorbing", icon: "fork.knife", color: AppPalette.effort),
        FastingMilestone(hour: 4, name: "Post-Meal", detail: "Glucose may trend down", icon: "arrow.down.right", color: AppPalette.positive),
        FastingMilestone(hour: 12, name: "Stored Fuel", detail: "Fuel use may shift", icon: "flame", color: AppPalette.caution),
        FastingMilestone(hour: 16, name: "Extended Window", detail: "Ketones may increase", icon: "bolt", color: AppPalette.achievement)
    ]
}

private struct FastingStage {
    let name: String
    let detail: String
    let icon: String
}

private struct FastingMilestone {
    let hour: Int
    let name: String
    let detail: String
    let icon: String
    let color: Color
}

#Preview {
    ScrollView {
        FastingTrackerCard()
            .padding(AppSpacing.screenHorizontal)
    }
    .background(AppPalette.canvas)
}
