import Foundation

/// Device-local milestones for one account, independent of installation analytics.
/// A second device starts with no milestones until that account performs an action there.
public struct AccountProgressStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func record(_ event: String, userID: String?, at date: Date = Date()) {
        guard let key = AccountScopedStorageKey.make(prefix: "accountProgress." + event, userID: userID) else { return }
        if defaults.object(forKey: key) == nil { defaults.set(date, forKey: key) }
    }

    public func date(_ event: String, userID: String?) -> Date? {
        guard let key = AccountScopedStorageKey.make(prefix: "accountProgress." + event, userID: userID) else { return nil }
        return defaults.object(forKey: key) as? Date
    }
}
