import Foundation

/// A late response may neither write audio nor play it after account, consent, or playback changed.
struct MaiaSpeechLease: Equatable {
    let ownerID: String
    let consent: AIDataConsent
    let generation: UUID

    func allows(ownerID: String?, consent: AIDataConsent?, generation: UUID) -> Bool {
        self.ownerID == ownerID && self.consent == consent && self.generation == generation
    }
}

@MainActor
struct MaiaSpeechEnvironment {
    var currentOwner: () -> String?
    var consent: (String) -> AIDataConsent?
    var request: (String) async throws -> Data
    var requestBatch: (([String]) async throws -> [Data])?
    var cacheDirectory: URL?
    var now: () -> Date = Date.init
    var playAudio: ((Data) -> Bool)?
    var defaults: UserDefaults = .standard
    var drafts = EditorDraftStore()

    static var live: Self {
        Self(currentOwner: { DIContainer.shared.authService?.currentUserID },
             consent: { AIDataConsentStore.shared.consent(for: $0) },
             request: { text in
                 guard let service = DIContainer.shared.cloudFunctionService else { throw APIError.noData }
                 let payload = try await service.callFunction("generateMaiaSpeech", with: ["text": text])
                 guard let dictionary = payload as? [String: Any], let encoded = dictionary["audioBase64"] as? String,
                       let data = Data(base64Encoded: encoded), !data.isEmpty else { throw APIError.noData }
                 return data
             }, requestBatch: { sentences in
                 guard let service = DIContainer.shared.cloudFunctionService else { throw APIError.noData }
                 let payload = try await service.callFunction("generateMaiaSpeech", with: ["sentences": sentences])
                 return try MaiaSpeechBatchPayload.audio(from: payload, expectedCount: sentences.count)
             })
    }
}

public enum MaiaPlaybackState: String { case idle, preparing, playing, paused }

public struct MaiaSpeechPlan: Codable, Equatable {
    public let text: String
    public let sentences: [String]

    public init(source: String, maximumChunkUTF16: Int = 1_800) {
        text = MaiaSpeechFormatter.spokenText(from: source)
        var sentences: [String] = []
        let limit = max(32, maximumChunkUTF16)
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            var chunk = ""
            for word in sentence.split(whereSeparator: \.isWhitespace) {
                if !chunk.isEmpty && chunk.utf16.count + 1 + word.utf16.count > limit {
                    sentences.append(chunk); chunk = ""
                }
                if word.utf16.count > limit {
                    if !chunk.isEmpty { sentences.append(chunk); chunk = "" }
                    var piece = ""
                    for character in word {
                        if !piece.isEmpty && piece.utf16.count + String(character).utf16.count > limit {
                            sentences.append(piece); piece = ""
                        }
                        piece.append(character)
                    }
                    chunk = piece
                } else {
                    if !chunk.isEmpty { chunk += " " }
                    chunk += word
                }
            }
            if !chunk.isEmpty { sentences.append(chunk) }
        }
        self.sentences = sentences
    }

    public func onlineBatch(startingAt index: Int) -> [String] {
        guard sentences.indices.contains(index) else { return [] }
        var batch: [String] = []
        var characters = 0
        for sentence in sentences[index...] {
            let next = characters + sentence.utf16.count + (batch.isEmpty ? 0 : 1)
            guard batch.count < 6, next <= 1_800 else { break }
            batch.append(sentence); characters = next
        }
        return batch
    }
}

public struct MaiaSpeechBookmark: Codable, Equatable {
    public let plan: MaiaSpeechPlan
    public let sentenceIndex: Int
    public let voiceIdentifier: String
    public let rate: Double
    public let updatedAt: Date

    public init(plan: MaiaSpeechPlan, sentenceIndex: Int, voiceIdentifier: String, rate: Double, now: Date = Date()) {
        self.plan = plan; self.sentenceIndex = sentenceIndex; self.voiceIdentifier = voiceIdentifier
        self.rate = rate; updatedAt = now
    }

    public func canResume(now: Date) -> Bool {
        plan.sentences.indices.contains(sentenceIndex) && rate.isFinite && (0.75...1.5).contains(rate)
            && now.timeIntervalSince(updatedAt) >= 0 && now.timeIntervalSince(updatedAt) <= 7 * 86_400
    }
}

/// Explicit batch envelopes only: old joined speech cannot be attributed to a sentence.
enum MaiaSpeechBatchPayload {
    static func audio(from payload: Any?, expectedCount: Int) throws -> [Data] {
        guard (1...6).contains(expectedCount), let dictionary = payload as? [String: Any],
              let values = dictionary["segments"] as? [[String: Any]], values.count == expectedCount else { throw APIError.noData }
        var totalBytes = 0
        return try values.enumerated().map { index, value in
            guard value["index"] as? Int == index, let encoded = value["audioBase64"] as? String,
                  let audio = Data(base64Encoded: encoded), !audio.isEmpty else { throw APIError.noData }
            totalBytes += audio.count
            guard totalBytes <= 6 * 1_024 * 1_024 else { throw APIError.noData }
            return audio
        }
    }
}
