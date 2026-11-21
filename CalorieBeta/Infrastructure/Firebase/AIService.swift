import Foundation
import FirebaseFunctions
import MyFitPlateCore

@MainActor
public class AIService: AIStreamingServiceProtocol {

    public static let shared = AIService()
    private lazy var functions = Functions.functions()
    
    private init() {}

    /// Sends a prompt to the Firebase Cloud Function and returns the string content.
    /// Handles retries automatically for network errors or empty responses.
    public func performRequest(
        messages: [[String: Any]],
        model: String = "gpt-6-luna",
        maxTokens: Int = 2048,
        temperature: Double = 0.7,
        responseFormat: [String: Any]? = nil,
        requestKind: AIRequestKind = .general,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        if let requiredFlag = requestKind.requiredFeatureFlag {
            let isEnabled = DIContainer.shared.featureFlagService?.boolValue(for: requiredFlag)
                ?? requiredFlag.defaultValue
            guard isEnabled else {
                return .failure(.featureUnavailable)
            }
        }

        guard let userID = DIContainer.shared.authService.currentUserID,
              let consent = AIDataConsentStore.shared.consent(for: userID) else {
            NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            return .failure(.consentRequired)
        }

        return await performRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            responseFormat: responseFormat,
            requestKind: requestKind,
            retryCount: retryCount,
            requestingUserID: userID,
            consent: consent
        )
    }

    public func performStreamingRequest(messages: [[String: Any]], model: String, maxTokens: Int, temperature: Double,
                                        requestKind: AIRequestKind, requestID: UUID,
                                        onDelta: @escaping @MainActor (String) -> Void) async -> Result<MaiaAIResponse, AIError> {
        guard let owner = DIContainer.shared.authService.currentUserID,
              let consent = AIDataConsentStore.shared.consent(for: owner) else {
            NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            return .failure(.consentRequired)
        }
        do {
            let payload: [String: Any] = ["messages": messages, "maxTokens": maxTokens, "temperature": temperature,
                                          "requestKind": requestKind.rawValue, "requestID": requestID.uuidString]
            let response = try await MaiaStreamingTransport().send(payload: payload, requestID: requestID, ownerID: owner,
                                                                  consent: consent, onDelta: onDelta)
            try Task.checkCancellation()
            return .success(response)
        } catch let error as AIError { return .failure(error) } catch { return .failure(.networkError(error)) }
    }

    private func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        requestKind: AIRequestKind,
        retryCount: Int,
        requestingUserID: String,
        consent: AIDataConsent
    ) async -> Result<String, AIError> {
        guard DIContainer.shared.authService.currentUserID == requestingUserID else {
            return .failure(.accountChanged)
        }
        if let flag = requestKind.requiredFeatureFlag,
           !(DIContainer.shared.featureFlagService?.boolValue(for: flag) ?? flag.defaultValue) {
            return .failure(.featureUnavailable)
        }
        
        guard !Task.isCancelled else { return .failure(.networkError(CancellationError())) }
        guard AIDataConsentStore.shared.matches(consent, for: requestingUserID) else {
            return .failure(.consentChanged)
        }
        var requestData: [String: Any] = [
            "messages": messages,
            "maxTokens": maxTokens,
            "temperature": temperature,
            "requestKind": requestKind.rawValue
        ]
        
        if let format = responseFormat {
            requestData["responseFormat"] = format
        }

        do {
            let callable = functions.httpsCallable("generateAIResponse")
            callable.timeoutInterval = 130
            let result = try await callable.call(requestData)
            guard !Task.isCancelled else { return .failure(.networkError(CancellationError())) }
            guard DIContainer.shared.authService.currentUserID == requestingUserID else {
                return .failure(.accountChanged)
            }
            guard AIDataConsentStore.shared.matches(consent, for: requestingUserID) else { return .failure(.consentChanged) }
            if let flag = requestKind.requiredFeatureFlag,
               !(DIContainer.shared.featureFlagService?.boolValue(for: flag) ?? flag.defaultValue) {
                return .failure(.featureUnavailable)
            }
            guard let data = result.data as? [String: Any],
                  let content = data["content"] as? String else {
                return .failure(.apiError("Invalid response from cloud function."))
            }
            return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            let nsError = error as NSError
            let code = nsError.domain == FunctionsErrorDomain ? FunctionsErrorCode(rawValue: nsError.code) : nil
            if code == .resourceExhausted {
                return .failure(.apiError("You've reached the AI usage limit. Try again later; saved food search still works."))
            }
            if code == .invalidArgument { return .failure(.apiError("This request is too large or invalid. Try a shorter request.")) }
            if code == .failedPrecondition || code == .permissionDenied || code == .unauthenticated {
                return .failure(.apiError("AI is unavailable for this session. Check your account and try again."))
            }
            let isTransient = code == .unavailable || code == .deadlineExceeded || nsError.domain == NSURLErrorDomain
            if retryCount > 0, isTransient, !Task.isCancelled {
                guard DIContainer.shared.authService.currentUserID == requestingUserID else {
                    return .failure(.accountChanged)
                }
                AppLog.ai.warning("AI request failed. Retrying: \(error.localizedDescription, privacy: .public)")
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return .failure(.networkError(error)) }
                guard DIContainer.shared.authService.currentUserID == requestingUserID else {
                    return .failure(.accountChanged)
                }
                return await performRequest(
                    messages: messages,
                    model: model,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    responseFormat: responseFormat,
                    requestKind: requestKind,
                    retryCount: retryCount - 1,
                    requestingUserID: requestingUserID,
                    consent: consent
                )
            }
            return .failure(.networkError(error))
        }
    }
}
