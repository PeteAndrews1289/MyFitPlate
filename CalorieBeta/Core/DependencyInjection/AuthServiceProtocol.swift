import Foundation

protocol AuthServiceProtocol: Sendable {
    var currentUserID: String? { get }
    func observeAuthState(listener: @escaping (String?) -> Void) -> Any
    func removeObserver(_ handle: Any)
    func signOut() throws
}
