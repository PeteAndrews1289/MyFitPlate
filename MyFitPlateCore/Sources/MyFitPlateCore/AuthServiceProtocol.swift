import Foundation

public enum AuthServiceError: LocalizedError {
    case missingCurrentUser
    case missingEmail
    case invalidCredentials
    case invalidEmail
    case accountDisabled
    case emailAlreadyInUse
    case weakPassword
    case tooManyAttempts
    case networkUnavailable
    case secureStorageUnavailable
    case serviceUnavailable
    case unknown

    public var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "No signed-in user is available."
        case .missingEmail:
            return "No email address is available for the signed-in user."
        case .invalidCredentials:
            return "That email or password doesn't look right."
        case .invalidEmail:
            return "Enter a valid email address."
        case .accountDisabled:
            return "This account has been disabled. Contact support for help."
        case .emailAlreadyInUse:
            return "An account already exists for that email address."
        case .weakPassword:
            return "Choose a stronger password with at least 6 characters."
        case .tooManyAttempts:
            return "Too many attempts. Wait a moment, then try again."
        case .networkUnavailable:
            return "Couldn't connect. Check your internet connection and try again."
        case .secureStorageUnavailable:
            return "Secure sign-in storage isn't available right now. Restart the app and try again."
        case .serviceUnavailable:
            return "Sign in is temporarily unavailable. Please try again shortly."
        case .unknown:
            return "Something went wrong. Please try again."
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
