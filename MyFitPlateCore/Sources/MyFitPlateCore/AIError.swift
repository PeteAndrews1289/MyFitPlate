

import Foundation
public enum AIError: Error, LocalizedError {
    case invalidURL
    case noData
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesExceeded

    public var errorDescription: String? {
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


public protocol AIServiceProtocol {
    func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        retryCount: Int
    ) async -> Result<String, AIError>
}


public extension AIServiceProtocol {
    func performRequest(
        messages: [[String: Any]],
        model: String = "gpt-4o-mini",
        maxTokens: Int = 2048,
        temperature: Double = 0.7,
        responseFormat: [String: Any]? = nil,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        return await performRequest(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, responseFormat: responseFormat, retryCount: retryCount)
    }
}
