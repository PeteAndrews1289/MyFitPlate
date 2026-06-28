import Foundation

struct AccountDeletionOutcome: Sendable {
    let userID: String
}

enum AccountDeletionError: LocalizedError {
    case missingCurrentUser
    case emptyPassword
    case reauthenticationFailed(Error)
    case dataDeletionFailed(Error)
    case authDeletionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "We couldn't verify your account. Please sign out, sign back in, and try again."
        case .emptyPassword:
            return "Please enter your password to continue."
        case .reauthenticationFailed(let error):
            return "Re-authentication failed: \(error.localizedDescription)"
        case .dataDeletionFailed:
            return "We couldn't delete your data. Please check your connection and try again."
        case .authDeletionFailed:
            return "Your data was removed, but the login couldn't be deleted. Please sign out, sign back in, and delete again."
        }
    }
}

protocol AccountDeletionServicing: Sendable {
    func deleteCurrentAccount(password: String) async throws -> AccountDeletionOutcome
}
