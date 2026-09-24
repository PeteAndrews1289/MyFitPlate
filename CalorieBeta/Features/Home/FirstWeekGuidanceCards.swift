import MyFitPlateCore
import SwiftUI
import UserNotifications

// MARK: - Setup checklist

extension SetupChecklistItem {
    var title: String {
        switch self {
        case .firstMeal: "Log your first meal"
        case .dailyReminder: "Get a daily reminder"
        case .appleHealth: "Connect Apple Health"
        case .firstWorkout: "Try a workout"
        }
    }

    func detail(reminderTime: String) -> String {
        switch self {
        case .firstMeal: "Search for a food or scan a barcode."
        case .dailyReminder: "One nudge at \(reminderTime) to finish your log. Change the time in Settings."
        case .appleHealth: "Bring in your workouts, steps, and sleep."
        case .firstWorkout: "Start a plan or a quick session in Workouts."
        }
    }

    var symbol: String {
        switch self {
        case .firstMeal: "fork.knife"
        case .dailyReminder: "bell"
        case .appleHealth: "heart.text.square"
        case .firstWorkout: "figure.strengthtraining.traditional"
        }
    }
}

struct SetupChecklistCard: View {
    let state: SetupChecklistState
    let reminderTime: String
    let onSelect: (SetupChecklistItem) -> Void
    let onDismiss: () -> Void

    private var items: [SetupChecklistItem] { SetupChecklistRules.items(for: state) }
    private var completedCount: Int { SetupChecklistRules.completedCount(for: state) }
    private var nextItem: SetupChecklistItem? { SetupChecklistRules.nextItem(for: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get set up")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("setup_checklist_title")
                    Text("\(completedCount) of \(items.count) done")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Text("Hide")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.brandText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide setup checklist")
                .accessibilityIdentifier("setup_checklist_hide")
            }

            ProgressView(value: Double(completedCount), total: Double(max(items.count, 1)))
                .tint(AppPalette.brand)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    row(for: item)
                    if item != items.last {
                        Divider()
                    }
                }
            }
        }
        .appSurface(.emphasized)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func row(for item: SetupChecklistItem) -> some View {
        let isDone = SetupChecklistRules.isComplete(item, state: state)
        let isNext = item == nextItem
        return Button {
            onSelect(item)
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                Image(systemName: isDone ? "checkmark.circle.fill" : item.symbol)
                    .appTextRole(.control)
                    .foregroundStyle(isDone ? AppPalette.positive : isNext ? AppPalette.brandText : Color.secondary)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .fontWeight(isNext ? .semibold : .regular)
                        .appTextRole(.body)
                        .foregroundStyle(isDone ? Color.secondary : AppPalette.text)
                    if !isDone {
                        Text(item.detail(reminderTime: reminderTime))
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isDone {
                    Image(systemName: "chevron.right")
                        .appTextRole(.secondary)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, AppSpacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .accessibilityValue(isDone ? "Done" : "")
        .accessibilityIdentifier("setup_checklist_\(item.rawValue)")
    }
}

// MARK: - Adaptive targets offer

struct AdaptiveTargetsOfferCard: View {
    let measuredBurn: Double
    let formulaEstimate: Double?
    let onReview: () -> Void
    let onDecline: () -> Void

    private var comparisonText: String {
        let burn = Int(measuredBurn.rounded()).formatted()
        guard let formulaEstimate else {
            return "Your logs and weigh-ins show you burn about \(burn) cal a day."
        }
        let difference = Int((measuredBurn - formulaEstimate).rounded())
        guard abs(difference) >= 50 else {
            return "Your logs and weigh-ins show you burn about \(burn) cal a day, close to your first estimate."
        }
        let direction = difference > 0 ? "more" : "less"
        return "Your logs and weigh-ins show you burn about \(burn) cal a day, \(abs(difference).formatted()) \(direction) than your first estimate."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.brandText)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your adaptive targets are ready")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("adaptive_offer_title")
                    Text(comparisonText)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Adaptive targets follow that number as it changes, so your plan keeps up with you.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.compact) {
                    reviewButton
                    declineButton
                }
                VStack(spacing: AppSpacing.compact) {
                    reviewButton
                    declineButton
                }
            }
        }
        .appSurface(.emphasized)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var reviewButton: some View {
        Button("See my targets", action: onReview)
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("adaptive_offer_review")
    }

    private var declineButton: some View {
        Button("Not now", action: onDecline)
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityIdentifier("adaptive_offer_decline")
    }
}

// MARK: - State

/// Home's first-week guidance: the setup checklist and the adaptive-targets offer. Permission
/// prompts only happen here after a tap, never on launch or at the end of onboarding.
@MainActor
final class FirstWeekGuidanceModel: ObservableObject {
    @Published private(set) var notificationStatus: UNAuthorizationStatus?
    @Published private(set) var checklistDismissedAt: Date?
    @Published private(set) var adaptiveOfferDeclinedAt: Date?

    // Home is rebuilt on every tab switch. Remembering the last permission answer keeps the
    // checklist from blinking in, and view events count once per account per launch.
    private static var lastNotificationStatus: (userID: String?, status: UNAuthorizationStatus)?
    private static var viewedChecklistAccounts: Set<String> = []
    private static var viewedOfferAccounts: Set<String> = []

    /// Nil in preview mode, so a dismissal in one UI test never carries into the next.
    private let store: FirstWeekGuidanceStore?
    private var userID: String?
    private var accountKey: String { userID ?? "" }

    init(store: FirstWeekGuidanceStore? = FirstWeekGuidancePreview.isEnabled ? nil : FirstWeekGuidanceStore()) {
        self.store = store
    }

    var reminderTimeText: String {
        let time = NotificationManager.shared.dailyLogReminderTime()
        let date = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    func refresh(userID: String?) {
        if self.userID != userID || notificationStatus == nil {
            let cached = Self.lastNotificationStatus
            notificationStatus = cached?.userID == userID ? cached?.status : nil
        }
        self.userID = userID
        if let store {
            checklistDismissedAt = store.checklistDismissedAt(userID: userID)
            adaptiveOfferDeclinedAt = store.adaptiveOfferDeclinedAt(userID: userID)
        }
        refreshNotificationStatus()
    }

    func checklistState(hasLoggedFood: Bool, healthConnected: Bool, healthAvailable: Bool) -> SetupChecklistState {
        SetupChecklistState(
            hasLoggedFood: hasLoggedFood || ActivationFunnel.hasLogged(ActivationFunnel.firstFoodLogged),
            reminderResolved: notificationStatus != .notDetermined,
            healthResolved: healthConnected,
            healthAvailable: healthAvailable,
            hasCompletedWorkout: ActivationFunnel.hasLogged(ActivationFunnel.firstWorkoutCompleted)
        )
    }

    /// Waits for the notification status so a finished step never flashes as unfinished.
    func shouldShowChecklist(_ state: SetupChecklistState) -> Bool {
        guard notificationStatus != nil else { return false }
        return SetupChecklistRules.shouldShow(
            state: state,
            onboardingCompletedAt: ActivationFunnel.onboardingCompletedAt(),
            dismissedAt: checklistDismissedAt
        )
    }

    func shouldOfferAdaptiveTargets(goalSettings: GoalSettings, adaptiveGoalService: AdaptiveGoalService) -> Bool {
        AdaptiveTargetsOfferRules.shouldOffer(
            method: goalSettings.calorieGoalMethod,
            confidence: adaptiveGoalService.dataConfidence,
            isEstimateActionable: adaptiveGoalService.isEstimateActionable,
            calculatedTDEE: adaptiveGoalService.calculatedTDEE,
            lastDeclinedAt: adaptiveOfferDeclinedAt
        )
    }

    func requestDailyReminder() {
        NotificationManager.shared.requestAuthorization { granted in
            if granted {
                NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
            }
            Task { @MainActor [weak self] in
                self?.refreshNotificationStatus()
            }
        }
    }

    var isAdaptiveOfferSnoozed: Bool {
        guard let adaptiveOfferDeclinedAt else { return false }
        return Date().timeIntervalSince(adaptiveOfferDeclinedAt) < AdaptiveTargetsOfferRules.snoozeInterval
    }

    func dismissChecklist(completedCount: Int) {
        let now = Date()
        store?.dismissChecklist(userID: userID, now: now)
        checklistDismissedAt = now
        log(.setupChecklistDismissed, ["completed_count": completedCount])
    }

    func declineAdaptiveOffer(surface: String) {
        let now = Date()
        store?.declineAdaptiveOffer(userID: userID, now: now)
        adaptiveOfferDeclinedAt = now
        log(.adaptiveTargetsOfferDeclined, ["surface": surface])
    }

    func recordChecklistViewed(completedCount: Int, itemCount: Int) {
        guard Self.viewedChecklistAccounts.insert(accountKey).inserted else { return }
        log(.setupChecklistViewed, ["completed_count": completedCount, "item_count": itemCount])
    }

    func recordChecklistAction(_ item: SetupChecklistItem) {
        log(.setupChecklistAction, ["checklist_item": item.rawValue])
    }

    func recordOfferViewed(confidence: AdaptiveGoalService.DataConfidence) {
        guard Self.viewedOfferAccounts.insert(accountKey).inserted else { return }
        log(.adaptiveTargetsOfferViewed, ["confidence": confidence == .high ? "high" : "medium"])
    }

    func recordOfferOpened() {
        log(.adaptiveTargetsOfferOpened, ["surface": "home_card"])
    }

    private func refreshNotificationStatus() {
        let requestedUserID = userID
        NotificationManager.shared.authorizationStatus { status in
            Task { @MainActor [weak self] in
                guard let self, self.userID == requestedUserID else { return }
                Self.lastNotificationStatus = (requestedUserID, status)
                self.notificationStatus = status
            }
        }
    }

    private func log(_ event: ProductAnalytics.Event, _ parameters: [String: Any]) {
        DIContainer.shared.analyticsManager?.logEvent(event.rawValue, parameters: parameters)
    }
}

/// UI tests and design review can show both cards with fixed content. Debug builds only.
enum FirstWeekGuidancePreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-first-week-guidance-preview")
        #else
        false
        #endif
    }

    static let checklistState = SetupChecklistState(
        hasLoggedFood: true,
        reminderResolved: false,
        healthResolved: false,
        healthAvailable: true,
        hasCompletedWorkout: false
    )
    static let measuredBurn: Double = 2_430
    static let formulaEstimate: Double = 2_210
}
