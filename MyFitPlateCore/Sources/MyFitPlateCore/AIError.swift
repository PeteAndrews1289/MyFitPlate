import Foundation

public enum AIRequestKind: String, Sendable {
    case general
    case coaching
    case planning
    case mealPhoto = "meal_photo"
    case nutritionLabel = "nutrition_label"
    case menuPhoto = "menu_photo"
    case receiptPhoto = "receipt_photo"
    case recipePhoto = "recipe_photo"
    case pantryObservation = "pantry_observation"

    public var requiredFeatureFlag: FeatureFlag? {
        switch self {
        case .general, .coaching, .planning: return nil
        case .mealPhoto: return .mealPhotoLogging
        case .nutritionLabel: return .nutritionLabelScanner
        case .menuPhoto: return .menuScanner
        case .receiptPhoto: return .receiptScanner
        case .recipePhoto, .pantryObservation: return .recipePhotoScanner
        }
    }
}

public enum AIError: Error, LocalizedError {
    case consentRequired
    case consentChanged
    case accountChanged
    case featureUnavailable
    case invalidURL
    case noData
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesExceeded

    public var errorDescription: String? {
        switch self {
        case .consentRequired: return "Review and allow AI data sharing before using Maia."
        case .consentChanged: return "Your AI sharing choices changed. Your review is kept; start a new request using your current choices."
        case .accountChanged: return "The active account changed. Try the request again."
        case .featureUnavailable:
            return "This camera tool is temporarily unavailable. Try another logging method."
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
        model: String = "gpt-6-luna",
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

/// Optional transport capability. Cancellation must disconnect the request, not only hide its result.
public protocol AIStreamingServiceProtocol: AIServiceProtocol {
    @MainActor
    func performStreamingRequest(
        messages: [[String: Any]], model: String, maxTokens: Int, temperature: Double,
        requestKind: AIRequestKind, requestID: UUID,
        onDelta: @escaping @MainActor (String) -> Void
    ) async -> Result<MaiaAIResponse, AIError>
}
