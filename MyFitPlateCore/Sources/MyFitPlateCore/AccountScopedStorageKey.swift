import CryptoKit
import Foundation

public enum AccountScopedStorageKey {
    public static func make(prefix: String, userID: String?) -> String? {
        guard let userID, !userID.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(prefix).\(digest)"
    }
}
