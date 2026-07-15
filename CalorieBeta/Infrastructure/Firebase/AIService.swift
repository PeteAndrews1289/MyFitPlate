import Foundation
import FirebaseFunctions
import MyFitPlateCore

@MainActor
public class AIService: AIServiceProtocol {

    public static let shared = AIService()
    private lazy var functions = Functions.functions()
    
    private init() {}

    /// Sends a prompt to the Firebase Cloud Function and returns the string content.
    /// Handles retries automatically for network errors or empty responses.
    public func performRequest(
        messages: [[String: Any]],
        model: String = "gpt-4o-mini",
        maxTokens: Int = 2048,
        temperature: Double = 0.7,
        responseFormat: [String: Any]? = nil,
        requestKind: AIRequestKind = .general,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        guard let userID = DIContainer.shared.authService.currentUserID,
              AIDataConsentStore.shared.hasCurrentConsent(for: userID) else {
            NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            return .failure(.consentRequired)
        }
        
        var requestData: [String: Any] = [
            "model": model,
            "messages": messages,
            "maxTokens": maxTokens,
            "temperature": temperature,
            "requestKind": requestKind.rawValue
        ]
        
        if let format = responseFormat {
            requestData["responseFormat"] = format
        }

        do {
            let result = try await functions.httpsCallable("generateAIResponse").call(requestData)
            guard let data = result.data as? [String: Any],
                  let content = data["content"] as? String else {
                return .failure(.apiError("Invalid response from cloud function."))
            }
            return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            if retryCount > 0 {
                AppLog.ai.warning("AI request failed. Retrying: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return await performRequest(
                    messages: messages,
                    model: model,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    responseFormat: responseFormat,
                    requestKind: requestKind,
                    retryCount: retryCount - 1
                )
            }
            return .failure(.networkError(error))
        }
    }
}
