import Foundation

public enum AppReviewPromptCoordinator {
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
        let normalizedID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, !appVersion.isEmpty else { return false }

        var sessionIDs = userDefaults.stringArray(forKey: completedSessionIDsKey) ?? []
        guard !sessionIDs.contains(normalizedID) else { return false }

        sessionIDs.append(normalizedID)
        userDefaults.set(Array(sessionIDs.suffix(20)), forKey: completedSessionIDsKey)

        let firstMoment: Date
        if let storedDate = userDefaults.object(forKey: firstPositiveMomentAtKey) as? Date {
            firstMoment = storedDate
        } else {
            firstMoment = now
            userDefaults.set(now, forKey: firstPositiveMomentAtKey)
        }

        guard sessionIDs.count >= minimumCompletedSessions,
              now.timeIntervalSince(firstMoment) >= minimumPositiveHistory,
              userDefaults.string(forKey: lastRequestedVersionKey) != appVersion else {
            return false
        }

        if let lastRequestedAt = userDefaults.object(forKey: lastRequestedAtKey) as? Date,
           now.timeIntervalSince(lastRequestedAt) < requestCooldown {
            return false
        }

        userDefaults.set(now, forKey: lastRequestedAtKey)
        userDefaults.set(appVersion, forKey: lastRequestedVersionKey)
        return true
    }
}
