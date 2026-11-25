import Foundation

public struct MaiaAIResponse: Equatable {
    public let content: String
    public let metadata: AIResponseMetadata?
    public init(content: String, metadata: AIResponseMetadata? = nil) { self.content = content; self.metadata = metadata }
}

/// Firebase callable SSE envelopes. Partial text is never treated as an accepted action-bearing message.
public struct MaiaStreamDecoder {
    public enum Event: Equatable { case delta(String), completed(MaiaAIResponse) }
    private let requestID: UUID
    private var completed = false
    private var receivedCharacters = 0
    public init(requestID: UUID) { self.requestID = requestID }

    public mutating func consume(line: String) throws -> Event? {
        guard !line.isEmpty, !line.hasPrefix(":") else { return nil }
        guard !completed, line.hasPrefix("data:"), line.utf8.count <= 1_048_576,
              let data = line.dropFirst(5).data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.apiError("The response stream was incomplete. Retry your question.")
        }
        if envelope["error"] != nil { throw AIError.apiError("The response service could not finish. Retry your question.") }
        if let message = envelope["message"] as? [String: Any] {
            guard let identity = message["requestID"] as? String, UUID(uuidString: identity) == requestID,
                  let delta = message["delta"] as? String else { throw AIError.noData }
            receivedCharacters += delta.utf8.count
            guard receivedCharacters <= 1_048_576 else { throw AIError.noData }
            return .delta(delta)
        }
        if let result = envelope["result"] as? [String: Any], let content = result["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let metadata = try result["metadata"].flatMap { value -> AIResponseMetadata? in
                let encoded = try JSONSerialization.data(withJSONObject: value)
                let decoded = try? JSONDecoder().decode(AIResponseMetadata.self, from: encoded)
                return decoded?.isSupported == true ? decoded : nil
            }
            if let metadata, UUID(uuidString: metadata.requestID) != requestID { throw AIError.noData }
            completed = true
            return .completed(.init(content: content, metadata: metadata))
        }
        throw AIError.noData
    }
}
