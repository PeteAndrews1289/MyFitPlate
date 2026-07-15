import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject private var achievementService: AchievementService

    private var sortedChallenges: [Challenge] {
        let now = Date()
        return achievementService.activeChallenges.sorted { first, second in
            let firstRank = stateRank(for: first, now: now)
            let secondRank = stateRank(for: second, now: now)
            if firstRank != secondRank {
                return firstRank < secondRank
            }
            if first.expiresAt != second.expiresAt {
                return first.expiresAt < second.expiresAt
            }
            return first.title < second.title
        }
    }

    private var completedCount: Int {
        achievementService.activeChallenges.filter(\.isCompleted).count
    }

    private var openCount: Int {
        let now = Date()
        return achievementService.activeChallenges.filter {
            !$0.isCompleted && $0.expiresAt > now
        }.count
    }

    private var pointsRemaining: Int {
        let now = Date()
        return achievementService.activeChallenges
            .filter { !$0.isCompleted && $0.expiresAt > now }
            .reduce(0) { $0 + $1.pointsValue }
    }

    private func stateRank(for challenge: Challenge, now: Date) -> Int {
        if challenge.isCompleted { return 1 }
        if challenge.expiresAt <= now { return 2 }
        return 0
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Progress",
                    title: "Weekly Challenges",
                    subtitle: "Focused goals that reward the habits you are already building."
                )

                challengeSummary

                if sortedChallenges.isEmpty {
                    GuidanceEmptyState(
                        icon: "flag.checkered",
                        title: "No Active Challenges",
                        message: "Your next set will appear here when it is ready."
                    )
                    .appSurface(.quiet)
                } else {
                    challengeList
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var challengeSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(label: "Open", value: openCount.formatted(), accent: AppPalette.caution),
            AppMetricItem(label: "Complete", value: completedCount.formatted(), accent: AppPalette.brand),
            AppMetricItem(label: "Points Left", value: pointsRemaining.formatted(), accent: AppPalette.effort)
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("challenges_summary")
    }

    private var challengeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedChallenges.enumerated()), id: \.offset) { index, challenge in
                ChallengeProgressRow(challenge: challenge)

                if index < sortedChallenges.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .appSurface(.quiet, padding: 0)
        .accessibilityIdentifier("challenge_list")
    }
}

private struct ChallengeProgressRow: View {
    let challenge: Challenge

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var progressFraction: Double {
        guard challenge.goal > 0 else {
            return challenge.isCompleted ? 1 : 0
        }
        return min(max(challenge.progress / challenge.goal, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    identity
                    pointsLabel
                }
            } else {
                HStack(alignment: .center, spacing: AppSpacing.row) {
                    identity
                        .layoutPriority(1)
                    Spacer(minLength: AppSpacing.compact)
                    pointsLabel
                }
            }

            Text(challenge.description)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progressFraction)
                .tint(challenge.isCompleted ? AppPalette.brand : AppPalette.effort)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    progressLabel
                    statusLabel
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                    progressLabel
                    Spacer(minLength: AppSpacing.compact)
                    statusLabel
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(challenge.title)
        .accessibilityValue("\(progressText). \(statusText). \(challenge.pointsValue) points")
    }

    private var identity: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: challenge.isCompleted ? "checkmark" : "flag.fill")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(challenge.isCompleted ? AppPalette.brandText : AppPalette.effort)
                .frame(width: 40, height: 40)
                .background(
                    (challenge.isCompleted ? AppPalette.brand : AppPalette.effort).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(challenge.title)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pointsLabel: some View {
        Label("\(challenge.pointsValue) points", systemImage: "star.fill")
            .appTextRole(.caption)
            .foregroundStyle(challenge.isCompleted ? AppPalette.brandText : Color.secondary)
    }

    private var progressLabel: some View {
        Text(progressText)
            .appTextRole(.caption)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
    }

    private var statusLabel: some View {
        Text(statusText)
            .appTextRole(.caption)
            .foregroundStyle(challenge.isCompleted ? AppPalette.brandText : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressText: String {
        "\(formatted(challenge.progress)) of \(formatted(challenge.goal))"
    }

    private var statusText: String {
        if challenge.isCompleted {
            return "Complete"
        }
        if challenge.expiresAt <= Date() {
            return "Ended"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Ends \(formatter.localizedString(for: challenge.expiresAt, relativeTo: Date()))"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}
