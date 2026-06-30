import Foundation
import Combine

public final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    public init() {}
    @Published public var isAuthenticated: Bool = true
    @Published public var currentUserID: String? = "mock_user"
    public var signOutCalled = false
    public var signOutError: Error?
    public var reauthenticatedPasswords: [String] = []
    public var reauthenticateError: Error?
    public var deleteCurrentUserCalled = false
    public var deleteCurrentUserError: Error?
    public var removedObserverHandles: [Any] = []
    
    public func observeAuthState(listener: @escaping (String?) -> Void) -> Any {
        listener(currentUserID)
        return UUID()
    }

    public func removeObserver(_ handle: Any) {
        removedObserverHandles.append(handle)
    }

    public func reauthenticateCurrentUser(password: String) async throws {
        if let reauthenticateError { throw reauthenticateError }
        reauthenticatedPasswords.append(password)
    }

    public func deleteCurrentUser() async throws {
        if let deleteCurrentUserError { throw deleteCurrentUserError }
        deleteCurrentUserCalled = true
    }
    public func signOut() throws {
        if let signOutError { throw signOutError }
        signOutCalled = true
    }
    public func signIn(email: String, password: String) async throws -> AuthUserSession {
        return AuthUserSession(userID: "mock_user", email: email)
    }
    public func sendPasswordReset(email: String) async throws {}
    public func createUser(email: String, password: String) async throws -> AuthUserSession {
        return AuthUserSession(userID: "mock_user", email: email)
    }
}
