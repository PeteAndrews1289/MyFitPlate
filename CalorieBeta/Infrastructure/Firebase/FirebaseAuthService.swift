import Foundation
import MyFitPlateCore
import FirebaseAuth

final class FirebaseAuthService: AuthServiceProtocol {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }
    
    func observeAuthState(listener: @escaping (String?) -> Void) -> Any {
        return Auth.auth().addStateDidChangeListener { _, user in
            listener(user?.uid)
        }
    }
    
    func removeObserver(_ handle: Any) {
        if let handle = handle as? AuthStateDidChangeListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUserSession {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthUserSession, Error>) in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let user = result?.user else {
                    continuation.resume(throwing: AuthServiceError.missingCurrentUser)
                    return
                }

                continuation.resume(returning: AuthUserSession(userID: user.uid, email: user.email))
            }
        }
    }

    func createUser(email: String, password: String) async throws -> AuthUserSession {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthUserSession, Error>) in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let user = result?.user else {
                    continuation.resume(throwing: AuthServiceError.missingCurrentUser)
                    return
                }

                continuation.resume(returning: AuthUserSession(userID: user.uid, email: user.email))
            }
        }
    }

    func sendPasswordReset(email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func reauthenticateCurrentUser(password: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthServiceError.missingCurrentUser }
        guard let email = user.email else { throw AuthServiceError.missingEmail }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.reauthenticate(with: credential) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthServiceError.missingCurrentUser }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
