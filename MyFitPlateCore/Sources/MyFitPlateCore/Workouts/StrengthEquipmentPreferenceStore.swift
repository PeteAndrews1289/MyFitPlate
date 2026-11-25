import CryptoKit
import Foundation

/// Remembers equipment for an exact exercise in a routine without editing its saved program.
/// Draft metadata takes precedence when a session is resumed.
@MainActor
public final class StrengthEquipmentPreferenceStore {
    public enum StoreError: LocalizedError {
        case invalidIdentity, invalidEquipment

        public var errorDescription: String? {
            switch self {
            case .invalidIdentity: return "Sign in before remembering equipment for this exercise."
            case .invalidEquipment: return "Review the available weights and equipment before saving."
            }
        }
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load(userID: String, routineID: String, exerciseID: String, exerciseName: String) -> StrengthEquipment? {
        guard let key = key(userID: userID, routineID: routineID, exerciseID: exerciseID, exerciseName: exerciseName),
              let data = userDefaults.data(forKey: key),
              let equipment = try? JSONDecoder().decode(StrengthEquipment.self, from: data),
              equipment.isValid else { return nil }
        return equipment
    }

    public func save(_ equipment: StrengthEquipment?, userID: String, routineID: String, exerciseID: String, exerciseName: String) throws {
        guard let key = key(userID: userID, routineID: routineID, exerciseID: exerciseID, exerciseName: exerciseName) else {
            throw StoreError.invalidIdentity
        }
        guard let equipment else {
            userDefaults.removeObject(forKey: key)
            return
        }
        guard equipment.isValid else { throw StoreError.invalidEquipment }
        let data = try JSONEncoder().encode(equipment)
        userDefaults.set(data, forKey: key)
    }

    private func key(userID: String, routineID: String, exerciseID: String, exerciseName: String) -> String? {
        let normalizedName = exerciseName.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !routineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !exerciseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalizedName.isEmpty,
              let accountKey = AccountScopedStorageKey.make(prefix: "strengthEquipment", userID: userID),
              let context = try? JSONEncoder().encode([routineID, exerciseID, normalizedName]) else { return nil }
        let digest = SHA256.hash(data: context).map { String(format: "%02x", $0) }.joined()
        return accountKey + "." + digest
    }
}
