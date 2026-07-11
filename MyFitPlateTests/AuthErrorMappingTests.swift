import FirebaseAuth
import XCTest
@testable import MyFitPlate

final class AuthErrorMappingTests: XCTestCase {
    func testInvalidCredentialGetsFriendlyMessage() {
        let mapped = FirebaseAuthService.userFacingError(
            for: firebaseError(.invalidCredential)
        )

        XCTAssertEqual(mapped.errorDescription, "That email or password doesn't look right.")
    }

    func testKeychainFailureDoesNotExposeInternalDetails() {
        let mapped = FirebaseAuthService.userFacingError(
            for: firebaseError(.keychainError)
        )

        XCTAssertEqual(
            mapped.errorDescription,
            "Secure sign-in storage isn't available right now. Restart the app and try again."
        )
        XCTAssertFalse(mapped.errorDescription?.contains("NSLocalizedFailureReasonErrorKey") == true)
    }

    func testNetworkFailureSuggestsRetryableAction() {
        let mapped = FirebaseAuthService.userFacingError(
            for: firebaseError(.networkError)
        )

        XCTAssertEqual(
            mapped.errorDescription,
            "Couldn't connect. Check your internet connection and try again."
        )
    }

    private func firebaseError(_ code: AuthErrorCode) -> NSError {
        NSError(domain: AuthErrorDomain, code: code.rawValue)
    }
}
