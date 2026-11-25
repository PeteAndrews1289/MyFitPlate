import AuthenticationServices
import SwiftUI

/// Apple's own Sign in with Apple button, matched to the current appearance. It reports a
/// credential ready for Firebase and stays silent when the person cancels Apple's sheet.
struct AppleSignInButton: View {
    let label: SignInWithAppleButton.Label
    let accessibilityIdentifier: String
    let onResult: (Result<AppleIDCredential, Error>) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(label) { request in
            let nonce = AppleSignInNonce.random()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                do {
                    onResult(.success(try AppleAuthorizationResult.credential(from: authorization, rawNonce: rawNonce)))
                } catch {
                    onResult(.failure(error))
                }
            case .failure(let error):
                guard !AppleAuthorizationResult.isCancellation(error) else { return }
                onResult(.failure(AppleAuthorizationResult.userFacingError(error)))
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 64 : 52)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        // The button's style is fixed when it is created, so rebuild it when appearance changes.
        .id(colorScheme)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

enum AppleAuthorizationResult {
    static func credential(from authorization: ASAuthorization, rawNonce: String) throws -> AppleIDCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              !rawNonce.isEmpty,
              let tokenData = appleCredential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthServiceError.appleSignInUnavailable
        }

        return AppleIDCredential(
            identityToken: identityToken,
            rawNonce: rawNonce,
            authorizationCode: appleCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
            givenName: appleCredential.fullName?.givenName,
            familyName: appleCredential.fullName?.familyName,
            email: appleCredential.email
        )
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// AuthenticationServices errors are not written for people. A missing Apple ID, capability,
    /// or network all surface as the same actionable message.
    static func userFacingError(_ error: Error) -> Error {
        error is AuthServiceError ? error : AuthServiceError.appleSignInUnavailable
    }
}

/// Presents Apple's sheet without a button, for confirming a sensitive action such as deleting
/// the account. Keep a reference to the request until `perform()` returns.
@MainActor
final class AppleReauthenticationRequest: NSObject {
    private var continuation: CheckedContinuation<AppleIDCredential, Error>?
    private var controller: ASAuthorizationController?
    private var rawNonce = ""

    func perform() async throws -> AppleIDCredential {
        let nonce = AppleSignInNonce.random()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = AppleSignInNonce.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AppleReauthenticationRequest: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            do {
                finish(.success(try AppleAuthorizationResult.credential(from: authorization, rawNonce: rawNonce)))
            } catch {
                finish(.failure(error))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            finish(.failure(error))
        }
    }
}

extension AppleReauthenticationRequest: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

/// "or" between Sign in with Apple and the email option.
struct AuthMethodDivider: View {
    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Rectangle().fill(AppPalette.separator).frame(height: 1)
            Text("or")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(AppPalette.separator).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
