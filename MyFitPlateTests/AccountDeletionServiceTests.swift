import XCTest
@testable import MyFitPlate

final class AccountDeletionServiceTests: XCTestCase {
    func testSuccessfulDeletionRunsRequiredStepsAndReturnsUserID() async throws {
        let authService = MockAccountDeletionAuthService(currentUserID: "user-123")
        let databaseService = MockAccountDeletionDatabaseService()
        let cloudFunctionService = MockAccountDeletionCloudFunctionService()
        let service = AccountDeletionService(
            authService: authService,
            databaseService: databaseService,
            cloudFunctionService: cloudFunctionService
        )

        let outcome = try await service.deleteCurrentAccount(password: "correct-password")

        XCTAssertEqual(outcome.userID, "user-123")
        XCTAssertEqual(authService.reauthenticatedPassword, "correct-password")
        XCTAssertEqual(databaseService.deletedUserID, "user-123")
        XCTAssertEqual(cloudFunctionService.deleteCallCount, 1)
        XCTAssertTrue(authService.didDeleteCurrentUser)
    }

    func testEmptyPasswordFailsBeforeRemoteCalls() async {
        let authService = MockAccountDeletionAuthService(currentUserID: "user-123")
        let databaseService = MockAccountDeletionDatabaseService()
        let cloudFunctionService = MockAccountDeletionCloudFunctionService()
        let service = AccountDeletionService(
            authService: authService,
            databaseService: databaseService,
            cloudFunctionService: cloudFunctionService
        )

        do {
            _ = try await service.deleteCurrentAccount(password: "")
            XCTFail("Expected empty password to fail.")
        } catch AccountDeletionError.emptyPassword {
            XCTAssertNil(authService.reauthenticatedPassword)
            XCTAssertNil(databaseService.deletedUserID)
            XCTAssertEqual(cloudFunctionService.deleteCallCount, 0)
            XCTAssertFalse(authService.didDeleteCurrentUser)
        } catch {
            XCTFail("Expected AccountDeletionError.emptyPassword, got \(error).")
        }
    }

    func testDatabaseFailureStopsBeforeCloudAndAuthDeletion() async {
        let authService = MockAccountDeletionAuthService(currentUserID: "user-123")
        let databaseService = MockAccountDeletionDatabaseService(deleteError: AccountDeletionTestError.expected)
        let cloudFunctionService = MockAccountDeletionCloudFunctionService()
        let service = AccountDeletionService(
            authService: authService,
            databaseService: databaseService,
            cloudFunctionService: cloudFunctionService
        )

        do {
            _ = try await service.deleteCurrentAccount(password: "correct-password")
            XCTFail("Expected data deletion to fail.")
        } catch AccountDeletionError.dataDeletionFailed {
            XCTAssertEqual(authService.reauthenticatedPassword, "correct-password")
            XCTAssertEqual(databaseService.deletedUserID, "user-123")
            XCTAssertEqual(cloudFunctionService.deleteCallCount, 0)
            XCTAssertFalse(authService.didDeleteCurrentUser)
        } catch {
            XCTFail("Expected AccountDeletionError.dataDeletionFailed, got \(error).")
        }
    }

    func testCloudFunctionFailureDoesNotBlockAuthDeletion() async throws {
        let authService = MockAccountDeletionAuthService(currentUserID: "user-123")
        let databaseService = MockAccountDeletionDatabaseService()
        let cloudFunctionService = MockAccountDeletionCloudFunctionService(deleteError: AccountDeletionTestError.expected)
        let service = AccountDeletionService(
            authService: authService,
            databaseService: databaseService,
            cloudFunctionService: cloudFunctionService
        )

        let outcome = try await service.deleteCurrentAccount(password: "correct-password")

        XCTAssertEqual(outcome.userID, "user-123")
        XCTAssertEqual(databaseService.deletedUserID, "user-123")
        XCTAssertEqual(cloudFunctionService.deleteCallCount, 1)
        XCTAssertTrue(authService.didDeleteCurrentUser)
    }
}

private enum AccountDeletionTestError: LocalizedError {
    case expected

    var errorDescription: String? {
        "Expected failure"
    }
}

private final class MockAccountDeletionAuthService: AuthServiceProtocol, @unchecked Sendable {
    var currentUserID: String?
    var reauthenticatedPassword: String?
    var didDeleteCurrentUser = false
    var reauthenticationError: Error?
    var deleteError: Error?

    init(currentUserID: String?) {
        self.currentUserID = currentUserID
    }

    func observeAuthState(listener: @escaping (String?) -> Void) -> Any {
        UUID().uuidString
    }

    func removeObserver(_ handle: Any) {}

    func signIn(email: String, password: String) async throws -> AuthUserSession {
        AuthUserSession(userID: currentUserID ?? "user-123", email: email)
    }

    func createUser(email: String, password: String) async throws -> AuthUserSession {
        AuthUserSession(userID: currentUserID ?? "user-123", email: email)
    }

    func sendPasswordReset(email: String) async throws {}

    func reauthenticateCurrentUser(password: String) async throws {
        reauthenticatedPassword = password
        if let reauthenticationError {
            throw reauthenticationError
        }
    }

    func deleteCurrentUser() async throws {
        didDeleteCurrentUser = true
        if let deleteError {
            throw deleteError
        }
    }

    func signOut() throws {}
}

private final class MockAccountDeletionDatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    var deletedUserID: String?
    var deleteError: Error?

    init(deleteError: Error? = nil) {
        self.deleteError = deleteError
    }

    func loadDarkModePreference(userID: String) async throws -> Bool {
        false
    }

    func saveDarkModePreference(userID: String, isEnabled: Bool) async throws {}

    func recordLastLogin(userID: String) async throws {}

    func deleteUserAllData(userID: String) async throws {
        deletedUserID = userID
        if let deleteError {
            throw deleteError
        }
    }
}

private final class MockAccountDeletionCloudFunctionService: CloudFunctionServiceProtocol, @unchecked Sendable {
    var deleteCallCount = 0
    var deleteError: Error?

    init(deleteError: Error? = nil) {
        self.deleteError = deleteError
    }

    func deleteUserData() async throws {
        deleteCallCount += 1
        if let deleteError {
            throw deleteError
        }
    }
    
    func callFunction(_ name: String, with data: [String: Any]) async throws -> Any? {
        // Not used in account deletion tests
        return nil
    }
}
