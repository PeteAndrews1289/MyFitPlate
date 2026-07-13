import MyFitPlateCore
import SwiftUI

struct WeekInMotionLoadingView: View {
    private static let placeholderRecap = WeeklyRecapBuilder.build(
        dailyLogs: [],
        sessionLogs: [],
        priorSessionLogs: [],
        weightHistory: [],
        calorieGoal: 2_000,
        proteinGoal: 120
    )

    var body: some View {
        WeekInMotionView(recap: Self.placeholderRecap)
            .redacted(reason: .placeholder)
            .overlay(alignment: .topTrailing) {
                ProgressView()
                    .tint(.brandPrimary)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Building Week in Motion")
            .accessibilityHint("Joining the last seven days of training, fuel, recovery, and Trust.")
            .accessibilityIdentifier("week_in_motion_loading")
    }
}

struct WeekInMotionView: View {
    let recap: WeeklyRecap
    var showsDetailAction = true
    var detailAction: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var motion: WeekInMotion { WeekInMotionBuilder.build(from: recap) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            rhythm

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                evidenceRow(
                    title: "Training rhythm",
                    summary: motion.trainingSummary,
                    progress: nil,
                    icon: "figure.mixed.cardio",
                    color: .brandPrimary,
                    isLast: false
                )
                evidenceRow(
                    title: "Fuel coverage",
                    summary: motion.fuelSummary,
                    progress: motion.trainingCoverage.eligible > 0
                        ? motion.trainingCoverage
                        : motion.diaryCoverage,
                    icon: "fork.knife",
                    color: .accentProtein,
                    isLast: false
                )
                evidenceRow(
                    title: "Recovery timing",
                    summary: motion.recoverySummary,
                    progress: motion.recoveryProgress,
                    icon: "bolt.heart.fill",
                    color: .accentCarbs,
                    isLast: false
                )
                evidenceRow(
                    title: "Trust coverage",
                    summary: motion.trustSummary,
                    progress: motion.trustProgress,
                    icon: "checkmark.seal.fill",
                    color: .accentPositiveText,
                    isLast: true
                )
            }

            observation

            if showsDetailAction {
                Button(action: detailAction) {
                    HStack(spacing: 10) {
                        Label("Open detailed report", systemImage: "chart.bar.xaxis")
                            .appFont(size: 14, weight: .bold)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .appFont(size: 13, weight: .bold)
                    }
                    .foregroundColor(.brandPrimary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekly_report_entry")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week in Motion")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .textCase(.uppercase)
                Spacer(minLength: 12)
                Text(weekRangeText)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            Text(motion.headline)
                .appFont(size: 26, weight: .bold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("weekly_report_headline")
        }
    }

    @ViewBuilder
    private var rhythm: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(motion.days, id: \.date) { day in
                    accessibilityDayRow(day)
                    if day.date != motion.days.last?.date {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(motion.days, id: \.date) { day in
                    dayNode(day)
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(height: 2)
                    .padding(.horizontal, 22)
                    .offset(y: 43)
                    .zIndex(-1)
            }
        }
    }

    private func dayNode(_ day: WeeklyRecapDay) -> some View {
        VStack(spacing: 7) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            ZStack {
                trainingShape(for: day)
                    .fill(trainingColor(for: day))
                    .frame(width: 34, height: 34)
                Image(systemName: trainingIcon(for: day))
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(day.hasTraining ? .white : Color(UIColor.secondaryLabel))
            }
            .overlay(alignment: .topTrailing) {
                if day.isDemandingStrengthDay {
                    Image(systemName: "flame.fill")
                        .appFont(size: 6, weight: .bold)
                        .foregroundColor(.white)
                        .frame(width: 12, height: 12)
                        .background(Color.orange, in: Circle())
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }

            Image(systemName: day.nutritionLogged ? "fork.knife.circle.fill" : "circle.dashed")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(day.nutritionLogged ? .accentProtein : Color(UIColor.tertiaryLabel))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day))
    }

    private func accessibilityDayRow(_ day: WeeklyRecapDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.textPrimary)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(trainingAccessibilityText(day))
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(day.nutritionLogged ? "Food logged" : "No food logged")
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func evidenceRow(
        title: String,
        summary: String,
        progress: WeeklyRecapProgress?,
        icon: String,
        color: Color,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(Color.backgroundPrimary, in: Circle())
                    .overlay(Circle().stroke(color.opacity(0.45), lineWidth: 1.5))

                if !isLast {
                    Rectangle()
                        .fill(color.opacity(0.25))
                        .frame(width: 2)
                        .frame(minHeight: 42)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(color)
                Text(summary)
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let fraction = progress?.fraction {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(UIColor.tertiarySystemFill))
                            Capsule()
                                .fill(color)
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.map(progressValue) ?? "")
    }

    private var observation: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(observationColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(motion.observation.title)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(observationColor)
                Text(motion.observation.text)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(motion.observation.basis)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("week_in_motion_observation")
    }

    private var weekRangeText: String {
        let start = motion.weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = motion.weekEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    private var observationColor: Color {
        switch motion.observation.tone {
        case .neutral: return Color(UIColor.secondaryLabel)
        case .positive: return .accentPositiveText
        case .attention: return .orange
        }
    }

    private func trainingShape(for day: WeeklyRecapDay) -> AnyShape {
        switch day.trainingKind {
        case .rest, .run:
            return AnyShape(Circle())
        case .strength:
            return AnyShape(RoundedRectangle(cornerRadius: 6))
        case .mixed:
            return AnyShape(Capsule())
        }
    }

    private func trainingColor(for day: WeeklyRecapDay) -> Color {
        switch day.trainingKind {
        case .rest: return Color(UIColor.tertiarySystemFill)
        case .strength: return day.isDemandingStrengthDay ? .orange : .brandPrimary
        case .run: return .blue
        case .mixed: return .accentCarbs
        }
    }

    private func trainingIcon(for day: WeeklyRecapDay) -> String {
        switch day.trainingKind {
        case .rest: return "minus"
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .mixed: return "figure.cross.training"
        }
    }

    private func trainingAccessibilityText(_ day: WeeklyRecapDay) -> String {
        switch day.trainingKind {
        case .rest:
            return "No training recorded"
        case .strength:
            let suffix = day.isDemandingStrengthDay ? ", demanding day" : ""
            return "\(day.strengthSessions) strength \(day.strengthSessions == 1 ? "session" : "sessions")\(suffix)"
        case .run:
            return "\(day.runCount) \(day.runCount == 1 ? "run" : "runs")"
        case .mixed:
            return "\(day.strengthSessions) strength \(day.strengthSessions == 1 ? "session" : "sessions") and \(day.runCount) \(day.runCount == 1 ? "run" : "runs")"
        }
    }

    private func dayAccessibilityLabel(_ day: WeeklyRecapDay) -> String {
        "\(day.date.formatted(.dateTime.weekday(.wide))), \(trainingAccessibilityText(day)), \(day.nutritionLogged ? "food logged" : "no food logged")"
    }

    private func progressValue(_ progress: WeeklyRecapProgress) -> String {
        progress.eligible > 0
            ? "\(progress.completed) of \(progress.eligible)"
            : "No assessable denominator"
    }
}
