import Foundation

public struct AuthUserSession: Sendable, Equatable {
    public let userID: String
    public let email: String?

    public init(userID: String, email: String? = nil) {
        self.userID = userID
        self.email = email
    }
}
