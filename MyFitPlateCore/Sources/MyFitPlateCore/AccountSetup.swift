import Foundation

public enum AccountSignInMethod: String, Codable, Sendable {
    case apple
    case email
}

/// Recorded when authentication finishes and cleared when the profile is ready. It lets setup
/// resume after a relaunch and tells a brand-new account apart from an existing profile that
/// could not be read, which must never be overwritten with defaults.
public struct PendingAccountSetup: Codable, Equatable, Sendable {
    public let userID: String
    public let isNewUser: Bool
    public let method: AccountSignInMethod
    public let email: String?
    public let displayName: String?
    public let recordedAt: Date

    public init(
        userID: String,
        isNewUser: Bool,
        method: AccountSignInMethod,
        email: String?,
        displayName: String?,
        recordedAt: Date = Date()
    ) {
        self.userID = userID
        self.isNewUser = isNewUser
        self.method = method
        self.email = email
        self.displayName = displayName
        self.recordedAt = recordedAt
    }
}

/// Device-local storage for the pre-account quiz. Nothing here leaves the device until the
/// person creates or signs in to an account.
public final class OnboardingDraftStore: @unchecked Sendable {
    public static let draftLifetime: TimeInterval = 14 * 24 * 60 * 60

    private let userDefaults: UserDefaults
    private let draftKey = "onboarding_pending_profile_draft_v1"
    private let pendingAccountKey = "onboarding_pending_account_setup_v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveDraft(_ draft: OnboardingProfileDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        userDefaults.set(data, forKey: draftKey)
    }

    /// Returns nil for an expired or no-longer-valid draft and removes it.
    public func loadDraft(now: Date = Date()) -> OnboardingProfileDraft? {
        guard let data = userDefaults.data(forKey: draftKey) else { return nil }
        guard let draft = try? JSONDecoder().decode(OnboardingProfileDraft.self, from: data),
              now.timeIntervalSince(draft.createdAt) <= Self.draftLifetime,
              draft.isComplete else {
            clearDraft()
            return nil
        }
        return draft
    }

    public func clearDraft() {
        userDefaults.removeObject(forKey: draftKey)
    }

    public func savePendingAccount(_ pending: PendingAccountSetup) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        userDefaults.set(data, forKey: pendingAccountKey)
    }

    public func loadPendingAccount() -> PendingAccountSetup? {
        guard let data = userDefaults.data(forKey: pendingAccountKey) else { return nil }
        return try? JSONDecoder().decode(PendingAccountSetup.self, from: data)
    }

    public func clearPendingAccount() {
        userDefaults.removeObject(forKey: pendingAccountKey)
    }

    public func clearAll() {
        clearDraft()
        clearPendingAccount()
    }
}

public enum AccountSetupAction: Equatable, Sendable {
    case createProfileThenApplyDraft
    case createProfileThenShowSurvey
    case applyDraft
    case showSurvey
    /// The account already finished setup; a draft from this device must not replace it.
    case discardDraft
    case none
}

public enum AccountSetupRules {
    public static func action(
        profile: [String: Any]?,
        currentUserID: String,
        pendingAccount: PendingAccountSetup?,
        hasDraft: Bool
    ) -> AccountSetupAction {
        let pending = pendingAccount?.userID == currentUserID ? pendingAccount : nil

        if profile == nil, pending?.isNewUser == true {
            return hasDraft ? .createProfileThenApplyDraft : .createProfileThenShowSurvey
        }

        guard OnboardingStateRules.requiresSetup(profile: profile) else {
            return hasDraft ? .discardDraft : .none
        }

        // Only a profile that was actually read can safely receive the draft. A missing profile
        // that isn't known to be new (an offline read, for example) keeps the survey fallback.
        if profile != nil, hasDraft {
            return .applyDraft
        }
        return .showSurvey
    }
}

/// Coordinates the hand-off between an auth screen and the root view. Firebase reports a
/// signed-in user before the auth call returns, so the root view waits while this is in flight
/// instead of deciding setup before `PendingAccountSetup` has been recorded.
@MainActor
public final class AccountSetupCoordinator: ObservableObject {
    public static let shared = AccountSetupCoordinator()

    @Published public private(set) var isAuthenticationInFlight = false
    public let store: OnboardingDraftStore

    public init(store: OnboardingDraftStore = OnboardingDraftStore()) {
        self.store = store
    }

    public func beginAuthentication() {
        isAuthenticationInFlight = true
    }

    public func finishAuthentication(
        session: AuthUserSession,
        method: AccountSignInMethod,
        displayName: String?
    ) {
        store.savePendingAccount(PendingAccountSetup(
            userID: session.userID,
            isNewUser: session.isNewUser,
            method: method,
            email: session.email,
            displayName: displayName
        ))
        isAuthenticationInFlight = false
    }

    public func cancelAuthentication() {
        isAuthenticationInFlight = false
    }
}

/// Runs an operation that may never complete (a Firestore write waits for the server while
/// offline) and stops waiting after `seconds`. The operation itself is not cancelled.
public enum BoundedOperation {
    public struct TimedOut: LocalizedError {
        public var errorDescription: String? {
            "This is taking longer than expected. Check your connection and try again."
        }
    }

    public static func run<T>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ContinuationGate<T>()
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            Task {
                do {
                    gate.resume(with: .success(try await operation()))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                gate.resume(with: .failure(TimedOut()))
            }
        }
    }
}

private final class ContinuationGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
