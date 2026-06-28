import Foundation

enum AuthServiceError: LocalizedError {
    case missingCurrentUser
    case missingEmail

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "No signed-in user is available."
        case .missingEmail:
            return "No email address is available for the signed-in user."
        }
    }
}

protocol AuthServiceProtocol: Sendable {
    var currentUserID: String? { get }
    func observeAuthState(listener: @escaping (String?) -> Void) -> Any
    func removeObserver(_ handle: Any)
    func reauthenticateCurrentUser(password: String) async throws
    func deleteCurrentUser() async throws
    func signOut() throws
}
