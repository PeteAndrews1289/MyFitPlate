import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseAppCheck
import MyFitPlateCore

/// A dedicated session lets cancellation close the connection consumed by the callable's abort signal.
@MainActor
final class MaiaStreamingTransport {
    func send(payload: [String: Any], requestID: UUID, ownerID: String,
              consent: AIDataConsent, onDelta: @escaping @MainActor (String) -> Void) async throws -> MaiaAIResponse {
        guard let user = Auth.auth().currentUser, user.uid == ownerID,
              let projectID = FirebaseApp.app()?.options.projectID,
              let endpoint = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/generateAIResponse") else {
            throw AIError.accountChanged
        }
        let token = try await user.getIDToken()
        let appCheck = try await AppCheck.appCheck().token(forcingRefresh: false)
        try validate(ownerID: ownerID, consent: consent)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 130)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(appCheck.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])
        return try await execute(request, requestID: requestID, ownerID: ownerID, consent: consent, onDelta: onDelta)
    }

    func execute(_ request: URLRequest, requestID: UUID, ownerID: String, consent: AIDataConsent,
                 configuration: URLSessionConfiguration = .ephemeral,
                 onDelta: @escaping @MainActor (String) -> Void) async throws -> MaiaAIResponse {
        let session = URLSession(configuration: configuration)
        let consentObserver = NotificationCenter.default.addObserver(forName: .aiDataConsentChanged, object: nil, queue: nil) { note in
            guard note.userInfo?["ownerID"] as? String == ownerID,
                  !AIDataConsentStore.shared.matches(consent, for: ownerID) else { return }
            session.invalidateAndCancel()
        }
        defer {
            NotificationCenter.default.removeObserver(consentObserver)
            session.invalidateAndCancel()
        }
        return try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            try validate(ownerID: ownerID, consent: consent)
            guard let response = response as? HTTPURLResponse else { throw AIError.noData }
            guard response.statusCode == 200 else {
                switch response.statusCode {
                case 429: throw AIError.apiError("You've reached the AI usage limit. Try again later.")
                case 401, 403: throw AIError.apiError("AI is unavailable for this session. Check your account and try again.")
                default: throw AIError.apiError("The response service could not finish. Retry your question.")
                }
            }
            var decoder = MaiaStreamDecoder(requestID: requestID)
            for try await line in bytes.lines {
                try validate(ownerID: ownerID, consent: consent)
                switch try decoder.consume(line: line) {
                case .delta(let text): onDelta(text)
                case .completed(let response): return response
                case nil: break
                }
            }
            throw AIError.apiError("The response was interrupted. Your question is kept for retry.")
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private func validate(ownerID: String, consent: AIDataConsent) throws {
        try Task.checkCancellation()
        guard DIContainer.shared.authService.currentUserID == ownerID else { throw AIError.accountChanged }
        guard AIDataConsentStore.shared.matches(consent, for: ownerID) else { throw AIError.consentChanged }
    }
}
