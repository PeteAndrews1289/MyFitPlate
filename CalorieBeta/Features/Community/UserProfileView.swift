import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var accountChanged = false
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var achievementService: AchievementService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits = Locale.current.measurementSystem != .us
    @State private var showingChallenges = false
    @State private var showingSettings = false
    @State private var preferences = PersonalReportPreferences()
    @State private var preferenceOwner: String?
    @State private var preferenceError: String?
    @State private var preferenceReadFailed = false

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
                objectiveSection
                currentTargetsSection
                displayPreferences
                if let notice = achievementService.achievementSyncNotice {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(notice).appTextRole(.secondary).foregroundStyle(.secondary)
                        Button("Retry milestone sync") {
                            achievementService.retryPendingAwards()
                            refreshProgressIfNeeded()
                        }
                    }.appSurface(.quiet)
                }
                if preferences.showsGamification {
                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        progressSummary
                        Divider()
                        levelProgressSection
                    }
                    .appSurface(.quiet)
                    weeklyChallengesLink
                    achievementsSection
                }
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
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Account details and settings")
                .accessibilityIdentifier("profile_account_settings")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .opacity(accountChanged ? 0 : 1)
        .accessibilityHidden(accountChanged)
        .allowsHitTesting(!accountChanged)
        .onReceive(appState.$isUserLoggedIn) { _ in
            if let owner = preferenceOwner, owner != DIContainer.shared.authService.currentUserID {
                accountChanged = true; showingSettings = false; showingChallenges = false; dismiss()
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView(showSettings: $showingSettings) } }
        .onAppear {
            preferenceOwner = DIContainer.shared.authService.currentUserID
            if let owner = preferenceOwner {
                do { preferences = try PersonalReportPreferenceStore.load(userID: owner) } catch { preferenceReadFailed = true; preferenceError = "Display preferences could not be opened. Existing settings are kept." }
            }
            refreshProgressIfNeeded()
        }
    }

    private var objectiveSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Current objective", subtitle: goalSettings.goal)
            NavigationLink { WeightTrackingView() } label: {
                AppListRow(icon: "chart.line.uptrend.xyaxis", iconColor: AppPalette.brand,
                    title: "Recorded weight", subtitle: recordedWeightSummary) {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("profile_weight_evidence")
        }.appSurface(.quiet)
    }

    private var recordedWeightSummary: String {
        let unit = useMetricBodyUnits ? "kg" : "lb"
        let factor = useMetricBodyUnits ? 0.45359237 : 1.0
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let records = goalSettings.weightHistory.filter { $0.date >= start && $0.date <= now && $0.weight.isFinite && $0.weight > 0 }
            .sorted { $0.date < $1.date }
        guard let latest = records.last else { return "No recorded weigh-ins in the past 30 days" }
        guard let first = records.first, first.id != latest.id else {
            return "\((latest.weight * factor).formatted(.number.precision(.fractionLength(1)))) \(unit) · \(latest.date.formatted(date: .abbreviated, time: .omitted))"
        }
        let change = (latest.weight - first.weight) * factor
        let sign = change > 0 ? "+" : ""
        return "\(sign)\(change.formatted(.number.precision(.fractionLength(1)))) \(unit) across \(records.count) recorded weigh-ins · past 30 days"
    }

    private var displayPreferences: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
            Toggle("Show points and milestones", isOn: Binding(get: { preferences.showsGamification }, set: {
                var next = preferences; next.showsGamification = $0; savePreferences(next)
            })).accessibilityIdentifier("profile_show_gamification")
            Toggle("Show BMI estimate", isOn: Binding(get: { preferences.showsBMI }, set: {
                var next = preferences; next.showsBMI = $0; savePreferences(next)
            })).accessibilityIdentifier("profile_show_bmi")
            if let preferenceError { Text(preferenceError).appTextRole(.caption).foregroundStyle(.secondary) }
            }.padding(.top, AppSpacing.row)
        } label: {
            Text("Display preferences")
                .accessibilityIdentifier("profile_display_preferences")
        }
        .appTextRole(.control)
        .disabled(preferenceReadFailed).appSurface(.quiet)
    }

    private func savePreferences(_ next: PersonalReportPreferences) {
        guard let owner = preferenceOwner else { return }
        do {
            try PersonalReportPreferenceStore.save(next, userID: owner, currentUserID: DIContainer.shared.authService.currentUserID)
            preferences = next; preferenceError = nil
        } catch { preferenceError = "The display preference could not be saved. Try again." }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Level",
                    value: "\(levelProgress.level)",
                    accent: AppPalette.brand
                ),
                AppMetricItem(
                    label: "Points",
                    value: achievementService.hasConfirmedPointBalance ? achievementService.userTotalAchievementPoints.formatted() : "—",
                    accent: AppPalette.achievement
                ),
                AppMetricItem(
                    label: "Milestones",
                    value: "\(achievementService.unlockedAchievementsCount)",
                    accent: AppPalette.effort
                )
            ])
            if let receipt = achievementService.legacyBalanceReceipt {
                Text(receipt.explanation)
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile_points_provenance")
            } else if let notice = achievementService.legacyBalanceNotice {
                Text(notice).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                Button("Retry balance receipt") { achievementService.retryLegacyBalanceReceipt() }
                    .appTextRole(.control).accessibilityIdentifier("profile_points_retry")
            } else {
                Text("Checking the recorded opening balance. No points are added by this migration.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("profile_progress_summary")
    }

    private var levelProgressSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Level progress",
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
    }

    private var weeklyChallengesLink: some View {
        Button {
            showingChallenges = true
        } label: {
            AppListRow(
                icon: "flag.checkered",
                iconColor: AppPalette.achievement,
                title: "Weekly challenges",
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
                title: "Current targets",
                subtitle: "The baseline currently used by your daily plan."
            )

            LabeledContent("Calorie target", value: calorieGoalText)
            if preferences.showsBMI {
                LabeledContent("BMI estimate", value: bmiText)
                Text("BMI does not describe body composition or lifting performance. This optional screening estimate uses your saved height and weight.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }

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
        return "\(Int(calories.rounded()).formatted()) cal"
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
                    .foregroundStyle(AppPalette.brandText)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = status?.awardEvidence {
                    DisclosureGroup("Milestone evidence") {
                        Text(evidence.explanation).appTextRole(.caption)
                        Text(evidence.recordedAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.caption)
                        Text(status?.awardRulesVersion ?? "Earlier definition").appTextRole(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Earlier earned milestone. Original points are preserved; a detailed source receipt was not recorded.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
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
                .foregroundStyle(isUnlocked ? AppPalette.brandText : Color.secondary)
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
            Label("\(status?.awardedPoints ?? definition.pointsValue) points", systemImage: "star.fill")
                .appTextRole(.caption)
                .foregroundStyle(isUnlocked ? AppPalette.brandText : Color.secondary)

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
