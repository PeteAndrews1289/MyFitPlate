import Foundation

public enum AppReviewPromptCoordinator {
    /// Positive moments that can make a review request appropriate.
    public enum Moment: String, Sendable {
        case completedSession = "completed_session"
        case loggingDay = "logging_day"
        case weeklyCheckIn = "weekly_check_in"
    }

    /// Distinct positive moments of every kind. The key predates logging-day and check-in
    /// moments and is kept so existing workout history still counts toward eligibility.
    private static let completedSessionIDsKey = "app_review_completed_session_ids"
    private static let firstPositiveMomentAtKey = "app_review_first_positive_moment_at"
    private static let lastRequestedAtKey = "app_review_last_requested_at"
    private static let lastRequestedVersionKey = "app_review_last_requested_version"

    public static let minimumCompletedSessions = 3
    public static let minimumPositiveHistory: TimeInterval = 3 * 24 * 60 * 60
    public static let requestCooldown: TimeInterval = 120 * 24 * 60 * 60

    /// Records a distinct fresh workout completion and returns true when this is an
    /// appropriate moment to ask StoreKit for a review. StoreKit still decides whether
    /// the system prompt is displayed.
    public static func registerCompletedSession(
        id sessionID: String,
        appVersion: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard !appVersion.isEmpty,
              recordPositiveMoment(id: sessionID, now: now, userDefaults: userDefaults),
              isEligibleForRequest(appVersion: appVersion, now: now, userDefaults: userDefaults) else {
            return false
        }

        markRequested(appVersion: appVersion, now: now, userDefaults: userDefaults)
        return true
    }

    /// Adds a distinct positive moment to the history. Returns false for a blank or repeated ID.
    @discardableResult
    public static func recordPositiveMoment(
        id: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return false }

        var momentIDs = userDefaults.stringArray(forKey: completedSessionIDsKey) ?? []
        guard !momentIDs.contains(normalizedID) else { return false }

        momentIDs.append(normalizedID)
        userDefaults.set(Array(momentIDs.suffix(20)), forKey: completedSessionIDsKey)

        if userDefaults.object(forKey: firstPositiveMomentAtKey) as? Date == nil {
            userDefaults.set(now, forKey: firstPositiveMomentAtKey)
        }
        return true
    }

    /// Enough distinct positive moments over enough days, not yet asked in this version, and
    /// outside the cooldown since the last request.
    public static func isEligibleForRequest(
        appVersion: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard !appVersion.isEmpty else { return false }

        let momentIDs = userDefaults.stringArray(forKey: completedSessionIDsKey) ?? []
        guard momentIDs.count >= minimumCompletedSessions,
              let firstMoment = userDefaults.object(forKey: firstPositiveMomentAtKey) as? Date,
              now.timeIntervalSince(firstMoment) >= minimumPositiveHistory,
              userDefaults.string(forKey: lastRequestedVersionKey) != appVersion else {
            return false
        }

        if let lastRequestedAt = userDefaults.object(forKey: lastRequestedAtKey) as? Date,
           now.timeIntervalSince(lastRequestedAt) < requestCooldown {
            return false
        }
        return true
    }

    public static func markRequested(
        appVersion: String,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(now, forKey: lastRequestedAtKey)
        userDefaults.set(appVersion, forKey: lastRequestedVersionKey)
    }

    /// Food logging counts once per local calendar day, however many items are logged.
    public static func loggingDayMomentID(for date: Date, calendar: Calendar = .current) -> String {
        "logging-day:" + dayStamp(for: date, calendar: calendar)
    }

    public static func weeklyCheckInMomentID(for date: Date, calendar: Calendar = .current) -> String {
        "weekly-check-in:" + dayStamp(for: date, calendar: calendar)
    }

    private static func dayStamp(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// Holds a review request until the app is calm enough to show it. Food logging and weekly
/// check-ins finish inside sheets, and asking there would interrupt the person, so the root view
/// presents the request once nothing modal is on screen.
@MainActor
public final class AppReviewPromptQueue: ObservableObject {
    public static let shared = AppReviewPromptQueue()

    @Published public private(set) var pendingMoment: AppReviewPromptCoordinator.Moment?

    private let userDefaults: UserDefaults
    private let appVersion: () -> String?
    private let isEnabled: () -> Bool

    public init(
        userDefaults: UserDefaults = .standard,
        appVersion: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        isEnabled: @escaping () -> Bool = {
            !AppRuntime.isUITesting() && NSClassFromString("XCTestCase") == nil
        }
    ) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.isEnabled = isEnabled
    }

    public func recordPositiveMoment(_ moment: AppReviewPromptCoordinator.Moment, id: String, now: Date = Date()) {
        guard isEnabled(), let version = appVersion(), !version.isEmpty else { return }

        AppReviewPromptCoordinator.recordPositiveMoment(id: id, now: now, userDefaults: userDefaults)
        if pendingMoment == nil,
           AppReviewPromptCoordinator.isEligibleForRequest(appVersion: version, now: now, userDefaults: userDefaults) {
            pendingMoment = moment
        }
    }

    public func recordLoggingDay(now: Date = Date(), calendar: Calendar = .current) {
        recordPositiveMoment(
            .loggingDay,
            id: AppReviewPromptCoordinator.loggingDayMomentID(for: now, calendar: calendar),
            now: now
        )
    }

    public func recordWeeklyCheckIn(now: Date = Date(), calendar: Calendar = .current) {
        recordPositiveMoment(
            .weeklyCheckIn,
            id: AppReviewPromptCoordinator.weeklyCheckInMomentID(for: now, calendar: calendar),
            now: now
        )
    }

    /// Call immediately before asking StoreKit. Returns the moment to report, or nil when a
    /// request is no longer appropriate, for example because a workout summary already asked.
    public func takePendingRequest(now: Date = Date()) -> AppReviewPromptCoordinator.Moment? {
        guard let moment = pendingMoment else { return nil }
        pendingMoment = nil

        guard isEnabled(),
              let version = appVersion(),
              AppReviewPromptCoordinator.isEligibleForRequest(appVersion: version, now: now, userDefaults: userDefaults) else {
            return nil
        }
        AppReviewPromptCoordinator.markRequested(appVersion: version, now: now, userDefaults: userDefaults)
        return moment
    }

    public func clearPending() {
        pendingMoment = nil
    }
}
