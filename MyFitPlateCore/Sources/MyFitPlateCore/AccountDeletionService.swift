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

        do {
            try await cloudFunctionService.deleteUserData()
        } catch {
            throw AccountDeletionError.dataDeletionFailed(error)
        }

        // The callable only returns after both the user's associated data and Firebase Auth
        // record are gone. Clear the now-invalid local session without hiding server failures.
        try? authService.signOut()

        return AccountDeletionOutcome(userID: userID)
    }
}
