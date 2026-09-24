import Foundation

public final class AccountDeletionService: AccountDeletionServicing, @unchecked Sendable {
    private let authService: AuthServiceProtocol
    private let cloudFunctionService: CloudFunctionServiceProtocol

    public init(
        authService: AuthServiceProtocol,
        databaseService: DatabaseServiceProtocol,
        cloudFunctionService: CloudFunctionServiceProtocol
    ) {
        self.authService = authService
        self.cloudFunctionService = cloudFunctionService
    }

    public func deleteCurrentAccount(password: String) async throws -> AccountDeletionOutcome {
        guard !password.isEmpty else { throw AccountDeletionError.emptyPassword }
        guard let userID = authService.currentUserID else { throw AccountDeletionError.missingCurrentUser }

        do {
            try await authService.reauthenticateCurrentUser(password: password)
        } catch {
            throw AccountDeletionError.reauthenticationFailed(error)
        }

        try await deleteServerDataAndSignOut()
        return AccountDeletionOutcome(userID: userID)
    }

    public func deleteCurrentAccount(appleCredential: AppleIDCredential) async throws -> AccountDeletionOutcome {
        guard let userID = authService.currentUserID else { throw AccountDeletionError.missingCurrentUser }

        do {
            try await authService.reauthenticateWithApple(appleCredential)
        } catch {
            throw AccountDeletionError.reauthenticationFailed(error)
        }

        // Apple requires revoking the app's Sign in with Apple tokens when an account is deleted,
        // which takes the fresh single-use code from this confirmation. Revocation has to happen
        // while the Firebase user still exists. A failure is reported rather than blocking the
        // deletion the person asked for.
        var revocationFailed = true
        if let code = appleCredential.authorizationCode, !code.isEmpty {
            do {
                try await authService.revokeAppleToken(authorizationCode: code)
                revocationFailed = false
            } catch {
                revocationFailed = true
            }
        }

        try await deleteServerDataAndSignOut()
        return AccountDeletionOutcome(userID: userID, appleTokenRevocationFailed: revocationFailed)
    }

    private func deleteServerDataAndSignOut() async throws {
        do {
            try await cloudFunctionService.deleteUserData()
        } catch {
            throw AccountDeletionError.dataDeletionFailed(error)
        }

        // The callable only returns after both the user's associated data and Firebase Auth
        // record are gone. Clear the now-invalid local session without hiding server failures.
        try? authService.signOut()
    }
}
