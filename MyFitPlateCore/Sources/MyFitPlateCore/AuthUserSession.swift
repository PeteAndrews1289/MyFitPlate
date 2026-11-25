import Foundation

public struct AuthUserSession: Sendable, Equatable {
    public let userID: String
    public let email: String?
    /// True when this sign-in created the account (always true for email sign-up).
    public let isNewUser: Bool

    public init(userID: String, email: String? = nil, isNewUser: Bool = false) {
        self.userID = userID
        self.email = email
        self.isNewUser = isNewUser
    }
}
