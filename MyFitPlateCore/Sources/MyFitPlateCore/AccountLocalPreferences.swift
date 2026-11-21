import Foundation

public enum AccountLocalPreferences {
    /// Delete only the captured account's hashed keys and known pre-hash aliases.
    /// Device preferences and every other account remain untouched.
    public static func remove(for userID: String, defaults: UserDefaults = .standard) {
        guard let suffix = AccountScopedStorageKey.make(prefix: "", userID: userID) else { return }
        let legacy = Set(["cached_user_goals_\(userID)", "ai_data_consent_v1_\(userID)",
                          "myfitplate.training_fuel_plan.\(userID)", "chatHistory_\(userID)", "recentFoods_\(userID)"])
        for key in defaults.dictionaryRepresentation().keys where key.hasSuffix(suffix) || legacy.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }
}
