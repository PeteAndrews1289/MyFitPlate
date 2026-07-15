

import Foundation

public enum AIRequestKind: String, Sendable {
    case general
    case mealPhoto = "meal_photo"
    case nutritionLabel = "nutrition_label"
    case menuPhoto = "menu_photo"
    case receiptPhoto = "receipt_photo"
    case recipePhoto = "recipe_photo"
}

public enum AIError: Error, LocalizedError {
    case consentRequired
    case invalidURL
    case noData
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesExceeded

    public var errorDescription: String? {
        switch self {
        case .consentRequired: return "Review and allow AI data sharing before using Maia."
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
        requestKind: AIRequestKind,
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
        requestKind: AIRequestKind = .general,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        return await performRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            responseFormat: responseFormat,
            requestKind: requestKind,
            retryCount: retryCount
        )
    }
}
