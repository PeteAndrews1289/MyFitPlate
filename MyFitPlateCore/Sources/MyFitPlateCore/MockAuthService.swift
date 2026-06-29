import Foundation
import Combine

public final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    public init() {}
    @Published public var isAuthenticated: Bool = true
    @Published public var currentUserID: String? = "mock_user"
    
    public func observeAuthState(listener: @escaping (String?) -> Void) -> Any {
        listener(currentUserID)
        return UUID()
    }
    public func removeObserver(_ handle: Any) {}
    public func reauthenticateCurrentUser(password: String) async throws {}
    public func deleteCurrentUser() async throws {}
    public func signOut() throws {}
    public func signIn(email: String, password: String) async throws -> AuthUserSession {
        return AuthUserSession(userID: "mock_user", email: email)
    }
    public func sendPasswordReset(email: String) async throws {}
    public func createUser(email: String, password: String) async throws -> AuthUserSession {
        return AuthUserSession(userID: "mock_user", email: email)
    }
}
