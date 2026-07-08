import Foundation

public final class AccountDeletionService: AccountDeletionServicing, @unchecked Sendable {
    private let authService: AuthServiceProtocol
    private let databaseService: DatabaseServiceProtocol
    private let cloudFunctionService: CloudFunctionServiceProtocol

    public init(
        authService: AuthServiceProtocol,
        databaseService: DatabaseServiceProtocol,
        cloudFunctionService: CloudFunctionServiceProtocol
    ) {
        self.authService = authService
        self.databaseService = databaseService
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
            try await databaseService.deleteUserAllData(userID: userID)
        } catch {
            throw AccountDeletionError.dataDeletionFailed(error)
        }

        do {
            try await cloudFunctionService.deleteUserData()
        } catch {
            AppLog.data.error("Server-side deletion incomplete: \(error.localizedDescription, privacy: .public)")
        }

        // The user's data is gone by here. Deleting the auth record itself is best-effort: on
        // some sessions Firebase's user.delete() can block indefinitely, which is what left the
        // account-deletion UI spinning forever. Time-box it so it can never wedge the flow — if
        // it doesn't finish quickly we abandon it and sign out anyway.
        await runBounded(seconds: 12) { [self] in
            do {
                try await authService.deleteCurrentUser()
            } catch {
                AppLog.data.error("Auth record deletion incomplete: \(error.localizedDescription, privacy: .public)")
            }
        }

        // ALWAYS sign out — otherwise the surviving auth session silently re-creates the
        // (now-empty) account on the next launch, and the user is never returned to the login
        // screen. Dropping the session is what actually completes the deletion for the user.
        try? authService.signOut()

        return AccountDeletionOutcome(userID: userID)
    }

    /// Runs `operation`, but returns after `seconds` even if it hasn't finished. A timed-out
    /// operation is abandoned (left running), not awaited — structured task groups can't bound a
    /// non-cooperative call like Firebase's user.delete(), so we race it against a sleep and take
    /// whichever resumes first.
    private func runBounded(seconds: Double, _ operation: @escaping @Sendable () async -> Void) async {
        let gate = ResumeGate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await operation()
                if gate.claim() { continuation.resume() }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if gate.claim() { continuation.resume() }
            }
        }
    }
}

/// Ensures a continuation is resumed exactly once when two racing tasks may both try.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
