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
        XCTAssertEqual(database.deletedUserDataIDs, ["user-1"])
        XCTAssertTrue(cloud.deleteUserDataCalled)
        XCTAssertTrue(auth.deleteCurrentUserCalled)
        XCTAssertTrue(auth.signOutCalled, "the session must be dropped so the account can't be re-created on next launch")
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

    func testDeleteCurrentAccountWrapsDatabaseDeletionFailure() async {
        database.deleteUserDataError = URLError(.notConnectedToInternet)

        do {
            _ = try await service.deleteCurrentAccount(password: "password123")
            XCTFail("expected data deletion error")
        } catch AccountDeletionError.dataDeletionFailed {
            XCTAssertEqual(auth.reauthenticatedPasswords, ["password123"])
            XCTAssertFalse(cloud.deleteUserDataCalled)
            XCTAssertFalse(auth.deleteCurrentUserCalled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeleteCurrentAccountContinuesWhenCloudCleanupFails() async throws {
        cloud.deleteUserDataError = URLError(.badServerResponse)

        let outcome = try await service.deleteCurrentAccount(password: "password123")

        XCTAssertEqual(outcome.userID, "user-1")
        XCTAssertEqual(database.deletedUserDataIDs, ["user-1"])
        XCTAssertFalse(cloud.deleteUserDataCalled)
        XCTAssertTrue(auth.deleteCurrentUserCalled)
    }

    func testDeleteCurrentAccountStillSignsOutWhenAuthDeletionFails() async throws {
        // The user's data is already deleted by the time we try to remove the auth record, so a
        // failure there must NOT abort the flow. We still sign out — otherwise the surviving
        // session silently re-creates the (now-empty) account on the next launch.
        auth.deleteCurrentUserError = URLError(.cannotConnectToHost)

        let outcome = try await service.deleteCurrentAccount(password: "password123")

        XCTAssertEqual(outcome.userID, "user-1")
        XCTAssertEqual(database.deletedUserDataIDs, ["user-1"])
        XCTAssertTrue(auth.signOutCalled, "must sign out even when the auth record can't be deleted")
    }

    func testAccountDeletionErrorDescriptionsAreActionable() {
        XCTAssertEqual(AccountDeletionError.emptyPassword.errorDescription, "Please enter your password to continue.")
        XCTAssertEqual(AccountDeletionError.missingCurrentUser.errorDescription, "We couldn't verify your account. Please sign out, sign back in, and try again.")
        XCTAssertTrue(AccountDeletionError.reauthenticationFailed(URLError(.badURL)).errorDescription?.contains("Re-authentication failed") == true)
        XCTAssertEqual(AccountDeletionError.dataDeletionFailed(URLError(.timedOut)).errorDescription, "We couldn't delete your data. Please check your connection and try again.")
        XCTAssertEqual(AccountDeletionError.authDeletionFailed(URLError(.timedOut)).errorDescription, "Your data was removed, but the login couldn't be deleted. Please sign out, sign back in, and delete again.")
    }
}
