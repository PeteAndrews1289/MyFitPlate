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
        XCTAssertFalse(auth.deleteCurrentUserCalled, "the server deletes the Firebase Auth record")
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

    func testAccountDeletionErrorDescriptionsAreActionable() {
        XCTAssertEqual(AccountDeletionError.emptyPassword.errorDescription, "Please enter your password to continue.")
        XCTAssertEqual(AccountDeletionError.missingCurrentUser.errorDescription, "We couldn't verify your account. Please sign out, sign back in, and try again.")
        XCTAssertTrue(AccountDeletionError.reauthenticationFailed(URLError(.badURL)).errorDescription?.contains("Re-authentication failed") == true)
        XCTAssertEqual(AccountDeletionError.dataDeletionFailed(URLError(.timedOut)).errorDescription, "We couldn't delete your data. Please check your connection and try again.")
        XCTAssertEqual(AccountDeletionError.authDeletionFailed(URLError(.timedOut)).errorDescription, "Your data was removed, but the login couldn't be deleted. Please sign out, sign back in, and delete again.")
    }
}
