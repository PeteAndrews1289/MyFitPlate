import Foundation

public struct AIDataConsent: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let grantedAt: Date
    public var includesHealthData: Bool

    public init(
        version: Int = AIDataConsent.currentVersion,
        grantedAt: Date = Date(),
        includesHealthData: Bool
    ) {
        self.version = version
        self.grantedAt = grantedAt
        self.includesHealthData = includesHealthData
    }
}

public final class AIDataConsentStore: @unchecked Sendable {
    public static let shared = AIDataConsentStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let keyPrefix = "ai_data_consent_v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func consent(for userID: String) -> AIDataConsent? {
        guard !userID.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let key = key(for: userID) else { return nil }
        let legacyKey = legacyKey(for: userID)
        if defaults.data(forKey: key) == nil,
           let legacyData = defaults.data(forKey: legacyKey) {
            defaults.set(legacyData, forKey: key)
        }
        defaults.removeObject(forKey: legacyKey)
        guard let data = defaults.data(forKey: key),
              let consent = try? JSONDecoder().decode(AIDataConsent.self, from: data),
              consent.version == AIDataConsent.currentVersion else {
            return nil
        }
        return consent
    }

    public func hasCurrentConsent(for userID: String) -> Bool {
        consent(for: userID) != nil
    }

    public func allowsHealthData(for userID: String) -> Bool {
        consent(for: userID)?.includesHealthData == true
    }

    public func grant(for userID: String, includesHealthData: Bool, date: Date = Date()) {
        guard !userID.isEmpty else { return }
        let consent = AIDataConsent(grantedAt: date, includesHealthData: includesHealthData)
        guard let data = try? JSONEncoder().encode(consent) else { return }
        lock.lock()
        if let key = key(for: userID) {
            defaults.set(data, forKey: key)
        }
        defaults.removeObject(forKey: legacyKey(for: userID))
        lock.unlock()
    }

    public func revoke(for userID: String) {
        guard !userID.isEmpty else { return }
        lock.lock()
        if let key = key(for: userID) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: legacyKey(for: userID))
        lock.unlock()
    }

    private func key(for userID: String) -> String? {
        AccountScopedStorageKey.make(prefix: keyPrefix, userID: userID)
    }

    private func legacyKey(for userID: String) -> String {
        "ai_data_consent_v1_\(userID)"
    }
}

public extension Notification.Name {
    static let aiDataConsentRequired = Notification.Name("MyFitPlate.AIDataConsentRequired")
}
