

import Foundation

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

@MainActor
class AIService {
    static let shared = AIService()
    private var apiKey: String { getAPIKey() }
    
    private init() {}

    /// Sends a prompt to OpenAI and returns the string content.
    /// Handles retries automatically for network errors or empty responses.
    func performRequest(
        messages: [[String: Any]],
        model: String = "gpt-4o-mini",
        maxTokens: Int = 2048,
        temperature: Double = 0.7,
        responseFormat: [String: Any]? = nil,
        retryCount: Int = 1
    ) async -> Result<String, AIError> {
        
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
            return .failure(.apiError("API Key is missing or invalid."))
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        
        if let format = responseFormat {
            requestBody["response_format"] = format
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return .failure(.networkError(error))
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                // If server error (5xx), retry
                if retryCount > 0 && httpResponse.statusCode >= 500 {
                    print("⚠️ AIService: Server error \(httpResponse.statusCode). Retrying...")
                    try await Task.sleep(nanoseconds: 1_000_000_000) // Sleep 1s
                    return await performRequest(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, responseFormat: responseFormat, retryCount: retryCount - 1)
                }
                
                // Parse error message if possible
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = json["error"] as? [String: Any],
                   let msg = errorDict["message"] as? String {
                    return .failure(.apiError("Status \(httpResponse.statusCode): \(msg)"))
                }
                return .failure(.apiError("Server returned status code \(httpResponse.statusCode)"))
            }

            // Parse Success
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return .failure(.decodingError(NSError(domain: "AIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"])))
            }
            
            return .success(content.trimmingCharacters(in: .whitespacesAndNewlines))

        } catch {
            if retryCount > 0 {
                print("⚠️ AIService: Network error. Retrying... (\(error.localizedDescription))")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return await performRequest(messages: messages, model: model, maxTokens: maxTokens, temperature: temperature, responseFormat: responseFormat, retryCount: retryCount - 1)
            }
            return .failure(.networkError(error))
        }
    }
}
