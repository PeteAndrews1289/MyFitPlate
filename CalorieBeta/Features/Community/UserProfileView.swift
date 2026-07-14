import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var achievementService: AchievementService
    @Environment(\.dismiss) private var dismiss

    @State private var showingChallenges = false

    private var levelProgress: AchievementRules.LevelProgress {
        AchievementRules.levelProgress(
            for: achievementService.userTotalAchievementPoints,
            thresholds: achievementService.levelThresholds
        )
    }

    private var sortedDefinitions: [AchievementDefinition] {
        achievementService.achievementDefinitions.sorted { first, second in
            let firstStatus = achievementService.userStatuses[first.id]
            let secondStatus = achievementService.userStatuses[second.id]
            let firstUnlocked = firstStatus?.isUnlocked ?? false
            let secondUnlocked = secondStatus?.isUnlocked ?? false

            if firstUnlocked != secondUnlocked {
                return firstUnlocked
            }
            if firstUnlocked {
                return (firstStatus?.unlockedDate ?? .distantPast) >
                    (secondStatus?.unlockedDate ?? .distantPast)
            }

            let firstProgress = firstStatus?.currentProgress ?? 0
            let secondProgress = secondStatus?.currentProgress ?? 0
            if firstProgress != secondProgress {
                return firstProgress > secondProgress
            }
            if first.pointsValue != second.pointsValue {
                return first.pointsValue > second.pointsValue
            }
            return first.title < second.title
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Profile",
                    title: "Your Progress",
                    subtitle: "A clear view of your level, weekly momentum, and earned milestones."
                )

                progressSummary
                levelProgressSection
                weeklyChallengesLink
                currentTargetsSection
                achievementsSection
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingChallenges) {
            ChallengesView()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear(perform: refreshProgressIfNeeded)
    }

    private var progressSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Level",
                value: "\(levelProgress.level)",
                accent: AppPalette.brand
            ),
            AppMetricItem(
                label: "Points",
                value: achievementService.userTotalAchievementPoints.formatted(),
                accent: .orange
            ),
            AppMetricItem(
                label: "Unlocked",
                value: "\(achievementService.unlockedAchievementsCount)/\(achievementService.achievementDefinitions.count)",
                accent: .blue
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("profile_progress_summary")
    }

    private var levelProgressSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Level Progress",
                subtitle: levelProgress.isMaximumLevel
                    ? "You have reached the highest current level."
                    : "Every unlocked achievement moves you toward Level \(levelProgress.level + 1)."
            )

            ProgressView(value: levelProgress.fraction)
                .tint(AppPalette.brand)
                .accessibilityLabel("Level progress")
                .accessibilityValue(levelProgressAccessibilityValue)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                Text("Level \(levelProgress.level)")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.text)

                Spacer(minLength: AppSpacing.compact)

                Text(levelProgressDetail)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .monospacedDigit()
        }
        .appSurface(.quiet)
    }

    private var weeklyChallengesLink: some View {
        Button {
            showingChallenges = true
        } label: {
            AppListRow(
                icon: "flag.checkered",
                iconColor: .orange,
                title: "Weekly Challenges",
                subtitle: weeklyChallengeSummary
            ) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .appSurface(.quiet, padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_weekly_challenges_button")
        .accessibilityHint("Opens your active weekly challenges")
    }

    private var currentTargetsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Current Targets",
                subtitle: "The baseline currently used by your daily plan."
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calorie Target",
                    value: calorieGoalText,
                    accent: .orange
                ),
                AppMetricItem(
                    label: "BMI Estimate",
                    value: bmiText,
                    accent: .blue
                )
            ])

            Divider()

            Text("BMI is a general screening estimate, not a diagnosis or a complete measure of health.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appSurface(.quiet)
    }

    @ViewBuilder
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Achievements",
                subtitle: "\(achievementService.unlockedAchievementsCount) of \(achievementService.achievementDefinitions.count) unlocked"
            )

            if achievementService.isLoading {
                HStack(spacing: AppSpacing.row) {
                    ProgressView()
                        .tint(AppPalette.brand)
                    Text("Loading achievements")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .appSurface(.quiet)
            } else if sortedDefinitions.isEmpty {
                GuidanceEmptyState(
                    icon: "trophy",
                    title: "No achievements yet",
                    message: "Your available milestones will appear here."
                )
                .appSurface(.quiet)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedDefinitions.enumerated()), id: \.element.id) { index, definition in
                        AchievementProgressRow(
                            definition: definition,
                            status: achievementService.userStatuses[definition.id]
                        )

                        if index < sortedDefinitions.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
                .accessibilityIdentifier("profile_achievement_list")
            }
        }
    }

    private var levelProgressDetail: String {
        if levelProgress.isMaximumLevel {
            return "Maximum level"
        }
        return "\(levelProgress.pointsToNext.formatted()) points to next level"
    }

    private var levelProgressAccessibilityValue: String {
        if levelProgress.isMaximumLevel {
            return "Maximum level reached"
        }
        return "\(Int((levelProgress.fraction * 100).rounded())) percent, \(levelProgress.pointsToNext) points remaining"
    }

    private var weeklyChallengeSummary: String {
        let challenges = achievementService.activeChallenges
        guard !challenges.isEmpty else {
            return "No active challenges right now"
        }
        let completed = challenges.filter(\.isCompleted).count
        return "\(completed) of \(challenges.count) complete this week"
    }

    private var calorieGoalText: String {
        guard let calories = goalSettings.calories, calories > 0 else {
            return "Not set"
        }
        return "\(Int(calories).formatted()) cal"
    }

    private var bmiText: String {
        let weightKilograms = goalSettings.weight * 0.453592
        let heightMeters = goalSettings.height / 100
        guard weightKilograms > 0, heightMeters > 0 else {
            return "Not available"
        }
        return String(format: "%.1f", weightKilograms / (heightMeters * heightMeters))
    }

    private func refreshProgressIfNeeded() {
        guard !ScreenshotDemoMode.isEnabled,
              let userID = DIContainer.shared.authService.currentUserID else { return }
        achievementService.fetchUserStatuses(userID: userID)
        achievementService.listenToUserProfile(userID: userID)
    }
}

private struct AchievementProgressRow: View {
    let definition: AchievementDefinition
    let status: UserAchievementStatus?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isUnlocked: Bool {
        status?.isUnlocked ?? false
    }

    private var progress: Double {
        status?.currentProgress ?? 0
    }

    private var progressFraction: Double {
        guard definition.criteriaValue > 0 else {
            return isUnlocked ? 1 : 0
        }
        return min(max(progress / definition.criteriaValue, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    identity
                    metadata
                }
            } else {
                HStack(alignment: .center, spacing: AppSpacing.row) {
                    identity
                        .layoutPriority(1)
                    Spacer(minLength: AppSpacing.compact)
                    metadata
                }
            }

            Text(definition.description)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isUnlocked {
                Label(unlockedText, systemImage: "checkmark.seal.fill")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brand)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ProgressView(value: progressFraction)
                        .tint(AppPalette.brand)

                    Text(progressText)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(definition.title) progress")
                .accessibilityValue(progressText)
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }

    private var identity: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: definition.iconName)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(isUnlocked ? AppPalette.brand : Color.secondary)
                .frame(width: 40, height: 40)
                .background(
                    (isUnlocked ? AppPalette.brand : Color.secondary).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(definition.title)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadata: some View {
        HStack(spacing: AppSpacing.compact) {
            Label("\(definition.pointsValue) points", systemImage: "star.fill")
                .appTextRole(.caption)
                .foregroundStyle(isUnlocked ? AppPalette.brand : Color.secondary)

            if isUnlocked {
                ShareLink(
                    item: MyFitPlateLinks.appStoreURL,
                    subject: Text("Achievement Unlocked"),
                    message: Text("I unlocked \(definition.title) in MyFitPlate.")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Share \(definition.title)")
            }
        }
    }

    private var unlockedText: String {
        guard let date = status?.unlockedDate else {
            return "Unlocked"
        }
        return "Unlocked \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var progressText: String {
        guard definition.criteriaValue > 1 else {
            return progress > 0 ? "In progress" : "Not started"
        }
        return "\(formatted(progress)) of \(formatted(definition.criteriaValue))"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}
