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
                    continuation.resume(throwing: Self.userFacingError(for: error))
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
                    continuation.resume(throwing: Self.userFacingError(for: error))
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
                    continuation.resume(throwing: Self.userFacingError(for: error))
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
                    continuation.resume(throwing: Self.userFacingError(for: error))
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
                    continuation.resume(throwing: Self.userFacingError(for: error))
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func signOut() throws {
        do {
            try Auth.auth().signOut()
        } catch {
            throw Self.userFacingError(for: error)
        }
    }

    static func userFacingError(for error: Error) -> AuthServiceError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .invalidCredential, .wrongPassword, .userNotFound, .userMismatch:
            return .invalidCredentials
        case .invalidEmail, .missingEmail, .invalidRecipientEmail:
            return .invalidEmail
        case .userDisabled:
            return .accountDisabled
        case .emailAlreadyInUse, .accountExistsWithDifferentCredential:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .tooManyRequests:
            return .tooManyAttempts
        case .networkError, .webNetworkRequestFailed:
            return .networkUnavailable
        case .keychainError:
            return .secureStorageUnavailable
        case .operationNotAllowed, .appNotAuthorized, .invalidAPIKey, .internalError:
            return .serviceUnavailable
        default:
            return .unknown
        }
    }
}
