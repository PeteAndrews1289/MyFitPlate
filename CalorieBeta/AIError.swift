

import Foundation
import FirebaseFunctions

enum AIError: Error, LocalizedError {
    case invalidURL
    case noData
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .noData: return "The AI returned no data."
        case .apiError(let msg): return "AI Error: \(msg)"
        case .decodingError(let err): return "Failed to process AI response: \(err.localizedDescription)"
        case .networkError(let err): return "Network connection failed: \(err.localizedDescription)"
        case .maxRetriesExceeded: return "Unable to generate a valid response after multiple attempts."
        }
    }
}


protocol AIServiceProtocol {
    func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        retryCount: Int
    ) async -> Result<String, AIError>
}

@MainActor
class AIService: AIServiceProtocol {

    static let shared = AIService()
    private lazy var functions = Functions.functions()
    
    private init() {}

    /// Sends a prompt to the Firebase Cloud Function and returns the string content.
    /// Handles retries automatically for network errors or empty responses.
    func performRequest(
        messages: [[String: Any]],
        model: String = "gpt-4o-mini",
        maxTokens: Int = 2048,
        temperature: Double = 0.7,
        responseFormat: [String: Any]? = nil,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        
        var requestData: [String: Any] = [
            "model": model,
            "messages": messages,
            "maxTokens": maxTokens,
            "temperature": temperature
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
                return await performRequest(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, responseFormat: responseFormat, retryCount: retryCount - 1)
            }
            return .failure(.networkError(error))
        }
    }
}
