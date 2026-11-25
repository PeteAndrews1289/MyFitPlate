import CryptoKit
import Foundation

/// The parts of an Apple ID authorization that account sign-in and deletion need, kept free of
/// AuthenticationServices so the rules around them stay testable.
public struct AppleIDCredential: Equatable, Sendable {
    public let identityToken: String
    /// The unhashed nonce whose SHA-256 digest was sent with the authorization request.
    public let rawNonce: String
    /// Short-lived and single-use. Account deletion needs it to revoke the Apple token.
    public let authorizationCode: String?
    public let givenName: String?
    public let familyName: String?
    public let email: String?

    public init(
        identityToken: String,
        rawNonce: String,
        authorizationCode: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        email: String? = nil
    ) {
        self.identityToken = identityToken
        self.rawNonce = rawNonce
        self.authorizationCode = authorizationCode
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
    }

    /// Apple shares a name only on the first authorization for this app.
    public var displayName: String? {
        AppleSignInNames.displayName(givenName: givenName, familyName: familyName)
    }
}

public enum AppleSignInNonce {
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    /// A single-use nonce from the system's cryptographically secure generator.
    public static func random(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(length, 1)).map { _ in
            characters[Int.random(in: 0..<characters.count, using: &generator)]
        })
    }

    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum AppleSignInNames {
    /// MyFitPlate addresses people by first name, matching the email sign-up field.
    public static func displayName(givenName: String?, familyName: String?) -> String? {
        let given = givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !given.isEmpty { return given }
        let family = familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return family.isEmpty ? nil : family
    }
}
