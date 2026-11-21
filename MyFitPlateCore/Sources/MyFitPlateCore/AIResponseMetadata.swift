import Foundation

/// Provider provenance only. A response is never a food/program mutation receipt.
/// Optional at transport boundaries so older deployed backends remain readable.
public struct AIResponseMetadata: Codable, Equatable, Sendable {
    public let envelopeVersion: Int
    public let requestID: String
    public let requestKind: String
    public let contractVersion: String
    public let serverPolicyVersion: String
    public let model: String
    public let fallbackUsed: Bool
    public let generatedAt: String
    public let durationMs: Int
    public let finishReason: String

    public var isSupported: Bool {
        guard envelopeVersion == 1, UUID(uuidString: requestID) != nil, durationMs >= 0,
              finishReason == "stop", !contractVersion.isEmpty, !model.isEmpty else { return false }
        return ISO8601DateFormatter().date(from: generatedAt) != nil || Self.fractionalDate(generatedAt) != nil
    }

    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
