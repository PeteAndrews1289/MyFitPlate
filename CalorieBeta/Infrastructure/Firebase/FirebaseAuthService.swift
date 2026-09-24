import Foundation
import MyFitPlateCore
import FirebaseAuth

final class FirebaseAuthService: AuthServiceProtocol {
    var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    var currentSignInMethod: AccountSignInMethod? {
        guard let providerIDs = Auth.auth().currentUser?.providerData.map(\.providerID) else { return nil }
        if providerIDs.contains("apple.com") { return .apple }
        if providerIDs.contains("password") { return .email }
        return nil
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

                continuation.resume(returning: AuthUserSession(userID: user.uid, email: user.email, isNewUser: true))
            }
        }
    }

    func signInWithApple(_ credential: AppleIDCredential) async throws -> AuthUserSession {
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: credential.identityToken,
            rawNonce: credential.rawNonce,
            fullName: Self.nameComponents(for: credential)
        )
        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            return AuthUserSession(
                userID: result.user.uid,
                email: result.user.email ?? credential.email,
                isNewUser: result.additionalUserInfo?.isNewUser ?? false
            )
        } catch {
            throw Self.appleUserFacingError(for: error)
        }
    }

    func reauthenticateWithApple(_ credential: AppleIDCredential) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthServiceError.missingCurrentUser }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: credential.identityToken,
            rawNonce: credential.rawNonce,
            fullName: nil
        )
        do {
            _ = try await user.reauthenticate(with: firebaseCredential)
        } catch {
            throw Self.appleUserFacingError(for: error)
        }
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        do {
            try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
        } catch {
            throw Self.appleUserFacingError(for: error)
        }
    }

    private static func nameComponents(for credential: AppleIDCredential) -> PersonNameComponents? {
        guard credential.givenName != nil || credential.familyName != nil else { return nil }
        var components = PersonNameComponents()
        components.givenName = credential.givenName
        components.familyName = credential.familyName
        return components
    }

    /// Apple sign-in failures need their own wording: "email or password" means nothing to someone
    /// who used their Apple ID, and a disabled provider should point them to email instead.
    static func appleUserFacingError(for error: Error) -> AuthServiceError {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .accountExistsWithDifferentCredential, .credentialAlreadyInUse, .emailAlreadyInUse:
                return .accountExistsWithDifferentSignIn
            case .userMismatch:
                return .appleAccountMismatch
            case .invalidCredential, .missingOrInvalidNonce, .operationNotAllowed:
                return .appleSignInUnavailable
            default:
                break
            }
        }
        return userFacingError(for: error)
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
