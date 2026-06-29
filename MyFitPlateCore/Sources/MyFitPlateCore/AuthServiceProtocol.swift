import Foundation

public enum AuthServiceError: LocalizedError {
    case missingCurrentUser
    case missingEmail

    public var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "No signed-in user is available."
        case .missingEmail:
            return "No email address is available for the signed-in user."
        }
    }
}

public protocol AuthServiceProtocol: Sendable {
    var currentUserID: String? { get }
    func observeAuthState(listener: @escaping (String?) -> Void) -> Any
    func removeObserver(_ handle: Any)
    func reauthenticateCurrentUser(password: String) async throws
    func deleteCurrentUser() async throws
    func signOut() throws
    func signIn(email: String, password: String) async throws -> AuthUserSession
    func sendPasswordReset(email: String) async throws
    func createUser(email: String, password: String) async throws -> AuthUserSession
}
