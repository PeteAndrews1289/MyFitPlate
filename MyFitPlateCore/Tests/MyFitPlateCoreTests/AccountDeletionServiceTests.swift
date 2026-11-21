import XCTest
@testable import MyFitPlateCore

final class AccountDeletionServiceTests: XCTestCase {
    private var auth: MockAuthService!
    private var database: MockDatabaseService!
    private var cloud: MockCloudFunctionService!
    private var service: AccountDeletionService!

    override func setUp() {
        super.setUp()
        auth = MockAuthService()
        auth.currentUserID = "user-1"
        database = MockDatabaseService()
        cloud = MockCloudFunctionService()
        service = AccountDeletionService(authService: auth, databaseService: database, cloudFunctionService: cloud)
    }

    override func tearDown() {
        service = nil
        cloud = nil
        database = nil
        auth = nil
        super.tearDown()
    }

    func testDeleteCurrentAccountPerformsFullDeletionFlow() async throws {
        let outcome = try await service.deleteCurrentAccount(password: "password123")

        XCTAssertEqual(outcome.userID, "user-1")
        XCTAssertEqual(auth.reauthenticatedPasswords, ["password123"])
        XCTAssertTrue(database.deletedUserDataIDs.isEmpty, "server deletion is the source of truth")
        XCTAssertTrue(cloud.deleteUserDataCalled)
        XCTAssertEqual(cloud.expectedDeletionUserIDs, ["user-1"])
        XCTAssertFalse(auth.deleteCurrentUserCalled, "the server deletes the Firebase Auth record")
        XCTAssertTrue(auth.signOutCalled, "the session must be dropped so the account can't be re-created on next launch")
    }

    func testAccountSwitchDuringReauthenticationNeverStartsServerDeletion() async {
        auth.onReauthenticate = { [self] in auth.currentUserID = "user-2" }
        do { _ = try await service.deleteCurrentAccount(password: "password123"); XCTFail("Expected account switch rejection") } catch AccountDeletionError.accountChanged {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(cloud.deleteUserDataCalled)
        XCTAssertFalse(auth.signOutCalled)
    }

    func testAppleAccountSwitchDuringReauthenticationDoesNotRevokeOrDeleteNewAccount() async {
        auth.onReauthenticate = { [self] in auth.currentUserID = "user-2" }
        do {
            _ = try await service.deleteCurrentAccount(appleCredential: AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: "code"))
            XCTFail("Expected account switch rejection")
        } catch AccountDeletionError.accountChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(auth.revokedAppleAuthorizationCodes.isEmpty)
        XCTAssertFalse(cloud.deleteUserDataCalled)
    }

    func testAcceptedOriginalDeletionDoesNotSignOutNewlySwitchedAccount() async throws {
        cloud.onDeleteUserData = { [self] in auth.currentUserID = "user-2" }
        let outcome = try await service.deleteCurrentAccount(password: "password123")
        XCTAssertEqual(outcome.userID, "user-1")
        XCTAssertEqual(auth.currentUserID, "user-2")
        XCTAssertFalse(auth.signOutCalled)
    }

    func testLocalPreferenceDeletionPreservesOtherAccountsAndDeviceSettings() throws {
        let name = "account-delete-scope-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: "first"))
        let second = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: "second"))
        defaults.set("private-first", forKey: first); defaults.set("private-second", forKey: second)
        defaults.set("legacy-first", forKey: "cached_user_goals_first")
        defaults.set("legacy-second", forKey: "cached_user_goals_second")
        defaults.set("chat-first", forKey: "chatHistory_first")
        defaults.set("chat-second", forKey: "chatHistory_second")
        defaults.set(true, forKey: "useMetricBodyUnits")
        AccountLocalPreferences.remove(for: "first", defaults: defaults)
        XCTAssertNil(defaults.object(forKey: first))
        XCTAssertNil(defaults.object(forKey: "cached_user_goals_first"))
        XCTAssertNil(defaults.object(forKey: "chatHistory_first"))
        XCTAssertEqual(defaults.string(forKey: "chatHistory_second"), "chat-second")
        XCTAssertEqual(defaults.string(forKey: second), "private-second")
        XCTAssertEqual(defaults.string(forKey: "cached_user_goals_second"), "legacy-second")
        XCTAssertTrue(defaults.bool(forKey: "useMetricBodyUnits"))
    }

    func testDeleteCurrentAccountRejectsEmptyPasswordBeforeSideEffects() async {
        do {
            _ = try await service.deleteCurrentAccount(password: "")
            XCTFail("expected empty password error")
        } catch AccountDeletionError.emptyPassword {
            XCTAssertTrue(auth.reauthenticatedPasswords.isEmpty)
            XCTAssertTrue(database.deletedUserDataIDs.isEmpty)
            XCTAssertFalse(cloud.deleteUserDataCalled)
            XCTAssertFalse(auth.deleteCurrentUserCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeleteCurrentAccountRejectsMissingCurrentUser() async {
        auth.currentUserID = nil

        do {
            _ = try await service.deleteCurrentAccount(password: "password123")
            XCTFail("expected missing current user error")
        } catch AccountDeletionError.missingCurrentUser {
            XCTAssertTrue(auth.reauthenticatedPasswords.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeleteCurrentAccountWrapsReauthenticationFailure() async {
        auth.reauthenticateError = URLError(.userAuthenticationRequired)

        do {
            _ = try await service.deleteCurrentAccount(password: "password123")
            XCTFail("expected reauthentication error")
        } catch AccountDeletionError.reauthenticationFailed {
            XCTAssertTrue(database.deletedUserDataIDs.isEmpty)
            XCTAssertFalse(auth.deleteCurrentUserCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeleteCurrentAccountDoesNotDependOnClientDatabaseDeletion() async throws {
        database.deleteUserDataError = URLError(.notConnectedToInternet)

        _ = try await service.deleteCurrentAccount(password: "password123")

        XCTAssertTrue(database.deletedUserDataIDs.isEmpty)
        XCTAssertTrue(cloud.deleteUserDataCalled)
    }

    func testDeleteCurrentAccountFailsWhenServerDeletionFails() async {
        cloud.deleteUserDataError = URLError(.badServerResponse)

        do {
            _ = try await service.deleteCurrentAccount(password: "password123")
            XCTFail("expected data deletion error")
        } catch AccountDeletionError.dataDeletionFailed {
            XCTAssertFalse(auth.signOutCalled, "keep the session so the user can retry")
            XCTAssertFalse(auth.deleteCurrentUserCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAppleDeletionReauthenticatesRevokesThenDeletesOnTheServer() async throws {
        auth.currentSignInMethod = .apple
        let credential = AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: "code-1")

        let outcome = try await service.deleteCurrentAccount(appleCredential: credential)

        XCTAssertEqual(outcome.userID, "user-1")
        XCTAssertFalse(outcome.appleTokenRevocationFailed)
        XCTAssertEqual(auth.appleReauthenticationCredentials, [credential])
        XCTAssertEqual(auth.revokedAppleAuthorizationCodes, ["code-1"])
        XCTAssertTrue(cloud.deleteUserDataCalled)
        XCTAssertTrue(auth.signOutCalled)
        XCTAssertTrue(auth.reauthenticatedPasswords.isEmpty)
    }

    func testAppleDeletionStillDeletesWhenRevocationFails() async throws {
        auth.revokeAppleTokenError = URLError(.badServerResponse)
        let credential = AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: "code-1")

        let outcome = try await service.deleteCurrentAccount(appleCredential: credential)

        XCTAssertTrue(outcome.appleTokenRevocationFailed)
        XCTAssertTrue(cloud.deleteUserDataCalled, "a revocation failure must not strand a deletion request")
        XCTAssertTrue(auth.signOutCalled)
    }

    func testAppleDeletionWithoutAnAuthorizationCodeIsReportedAsUnrevoked() async throws {
        let credential = AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: nil)

        let outcome = try await service.deleteCurrentAccount(appleCredential: credential)

        XCTAssertTrue(outcome.appleTokenRevocationFailed)
        XCTAssertTrue(auth.revokedAppleAuthorizationCodes.isEmpty)
        XCTAssertTrue(cloud.deleteUserDataCalled)
    }

    func testAppleDeletionStopsWhenReauthenticationFails() async {
        auth.appleReauthenticationError = AuthServiceError.appleAccountMismatch
        let credential = AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: "code-1")

        do {
            _ = try await service.deleteCurrentAccount(appleCredential: credential)
            XCTFail("expected reauthentication error")
        } catch AccountDeletionError.reauthenticationFailed {
            XCTAssertTrue(auth.revokedAppleAuthorizationCodes.isEmpty)
            XCTAssertFalse(cloud.deleteUserDataCalled)
            XCTAssertFalse(auth.signOutCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAppleDeletionRejectsMissingCurrentUser() async {
        auth.currentUserID = nil
        let credential = AppleIDCredential(identityToken: "token", rawNonce: "nonce", authorizationCode: "code-1")

        do {
            _ = try await service.deleteCurrentAccount(appleCredential: credential)
            XCTFail("expected missing current user error")
        } catch AccountDeletionError.missingCurrentUser {
            XCTAssertTrue(auth.appleReauthenticationCredentials.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAccountDeletionErrorDescriptionsAreActionable() {
        XCTAssertEqual(AccountDeletionError.emptyPassword.errorDescription, "Please enter your password to continue.")
        XCTAssertEqual(AccountDeletionError.missingCurrentUser.errorDescription, "We couldn't verify your account. Please sign out, sign back in, and try again.")
        XCTAssertTrue(AccountDeletionError.reauthenticationFailed(URLError(.badURL)).errorDescription?.contains("Re-authentication failed") == true)
        XCTAssertEqual(AccountDeletionError.dataDeletionFailed(URLError(.timedOut)).errorDescription, "We couldn't delete your data. Please check your connection and try again.")
        XCTAssertEqual(AccountDeletionError.authDeletionFailed(URLError(.timedOut)).errorDescription, "Your data was removed, but the login couldn't be deleted. Please sign out, sign back in, and delete again.")
    }

    func testAccountDeletionAnalyticsReasonsAreStableAndDoNotExposeErrors() {
        XCTAssertEqual(AccountDeletionError.emptyPassword.analyticsReason, "empty_password")
        XCTAssertEqual(AccountDeletionError.missingCurrentUser.analyticsReason, "missing_user")
        XCTAssertEqual(
            AccountDeletionError.reauthenticationFailed(URLError(.badURL)).analyticsReason,
            "reauthentication"
        )
        XCTAssertEqual(
            AccountDeletionError.dataDeletionFailed(URLError(.timedOut)).analyticsReason,
            "server_data_deletion"
        )
        XCTAssertEqual(
            AccountDeletionError.authDeletionFailed(URLError(.timedOut)).analyticsReason,
            "authentication_deletion"
        )
    }
}
