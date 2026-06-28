import Foundation

final class AccountDeletionService: AccountDeletionServicing, @unchecked Sendable {
    private let authService: AuthServiceProtocol
    private let databaseService: DatabaseServiceProtocol
    private let cloudFunctionService: CloudFunctionServiceProtocol

    init(
        authService: AuthServiceProtocol,
        databaseService: DatabaseServiceProtocol,
        cloudFunctionService: CloudFunctionServiceProtocol
    ) {
        self.authService = authService
        self.databaseService = databaseService
        self.cloudFunctionService = cloudFunctionService
    }

    func deleteCurrentAccount(password: String) async throws -> AccountDeletionOutcome {
        guard !password.isEmpty else { throw AccountDeletionError.emptyPassword }
        guard let userID = authService.currentUserID else { throw AccountDeletionError.missingCurrentUser }

        do {
            try await authService.reauthenticateCurrentUser(password: password)
        } catch {
            throw AccountDeletionError.reauthenticationFailed(error)
        }

        do {
            try await databaseService.deleteUserAllData(userID: userID)
        } catch {
            throw AccountDeletionError.dataDeletionFailed(error)
        }

        do {
            try await cloudFunctionService.deleteUserData()
        } catch {
            AppLog.data.error("Server-side deletion incomplete: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try await authService.deleteCurrentUser()
        } catch {
            throw AccountDeletionError.authDeletionFailed(error)
        }

        return AccountDeletionOutcome(userID: userID)
    }
}
