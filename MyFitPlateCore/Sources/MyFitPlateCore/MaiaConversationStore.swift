import Foundation

public struct MaiaCommunicationProfile: Codable, Equatable {
    public enum Length: String, Codable, CaseIterable { case brief, balanced, detailed }
    public enum Motivation: String, Codable, CaseIterable { case neutral, supportive, direct }
    public var tone: String
    public var length: Length
    public var motivation: Motivation

    public init(tone: String = "Balanced", length: Length = .balanced, motivation: Motivation = .neutral) {
        self.tone = ["Balanced", "Coach", "Analyst"].contains(tone) ? tone : "Balanced"
        self.length = length; self.motivation = motivation
    }

    public static let previewQuestion = "I have 500 calories and 30 g protein remaining. What should I do?"

    /// Same illustrative facts for every style. This is wording, never generated advice or a target change.
    public var previewAnswer: String {
        let facts = "500 calories and 30 g protein"
        let core: String
        switch tone {
        case "Coach": core = "Choose a meal that works for your day, then review its portion against your remaining \(facts)."
        case "Analyst": core = "Remaining targets: \(facts). Compare the meal's portion with both before saving."
        default: core = "You have \(facts) remaining. Choose a meal and review its portion before saving."
        }
        var answer = core
        if length != .brief { answer += " Reviewing a suggestion does not log food; you confirm the save." }
        if length == .detailed { answer += " These are remaining daily targets, not a required amount for a single meal. Portion information may still be estimated." }
        if motivation == .supportive { answer += " Keep the choice practical for you." }
        if motivation == .direct { answer += " Start with a meal you already know." }
        return answer
    }

    public var promptInstructions: String {
        let lengthText: String
        switch length {
        case .brief: lengthText = "Answer in one short paragraph unless safety or the requested details require more."
        case .balanced: lengthText = "Give the direct answer and just enough reasoning to act."
        case .detailed: lengthText = "Explain the relevant reasoning, assumptions, and alternatives; keep it organized and specific."
        }
        let motivationText: String
        switch motivation {
        case .neutral: motivationText = "Use neutral language; do not add praise or motivational messaging."
        case .supportive: motivationText = "Use gentle support without judgment, guilt, or fabricated progress."
        case .direct: motivationText = "State the practical next step directly without pressure or shaming."
        }
        return """
        \(MaiaConversationStyle.promptInstructions(for: tone))
        Communication only: \(lengthText) \(motivationText)
        These presentation preferences never change facts, calorie targets, exercise prescriptions, uncertainty, safety boundaries, or the requirement for explicit reviewed saves.
        """
    }
}

public struct MaiaConversationContext: Codable, Equatable {
    public var includedScopes: [MaiaContextScope]
    public var includeRecentMessages: Bool
    public var notes: String

    public init(includedScopes: [MaiaContextScope] = MaiaContextScope.allCases.filter { $0 != .healthKit },
                includeRecentMessages: Bool = true, notes: String = "") {
        self.includedScopes = includedScopes
        self.includeRecentMessages = includeRecentMessages
        self.notes = String(notes.prefix(2_000))
    }

    public func restricting(_ contract: MaiaContextContract) -> MaiaContextContract {
        MaiaContextContract(action: contract.action, scopes: contract.scopes.filter(includedScopes.contains))
    }
}

public struct MaiaConversationRequest: Codable, Equatable, Identifiable {
    public enum State: String, Codable { case waiting, streaming, completed, failed, cancelled, interrupted }
    public let id: UUID
    public let questionMessageID: UUID
    public let responseMessageID: UUID
    public let question: String
    public let requestedAt: Date
    public var contextDate: Date
    public var contract: MaiaContextContract
    public var state: State
    public var partialText: String
    public var errorMessage: String?
    public var attempts: Int

    public init(questionMessageID: UUID, question: String, contextDate: Date, contract: MaiaContextContract,
                id: UUID = UUID(), now: Date = Date()) {
        self.id = id; self.questionMessageID = questionMessageID; responseMessageID = UUID()
        self.question = question; requestedAt = now; self.contextDate = contextDate; self.contract = contract
        state = .waiting; partialText = ""; errorMessage = nil; attempts = 1
    }

    public var isPending: Bool { state == .waiting || state == .streaming }
}

public struct MaiaConversation: Identifiable, Codable, Equatable {
    public let id: UUID
    /// Legacy conversations have no reliable creation time; migration never invents one.
    public let createdAt: Date?
    public var updatedAt: Date
    public var title: String
    public var messages: [ChatMessage]
    public var draft: String
    public var context: MaiaConversationContext
    public var communicationOverride: MaiaCommunicationProfile?
    public var request: MaiaConversationRequest?

    public init(id: UUID = UUID(), title: String = "New conversation", messages: [ChatMessage] = [],
                createdAt: Date? = Date(), now: Date = Date()) {
        self.id = id; self.createdAt = createdAt; updatedAt = now; self.title = title
        self.messages = messages; draft = ""; context = .init(); request = nil
    }

    public mutating func recoverInterruptedRequest() {
        guard request?.isPending == true else { return }
        request?.state = .interrupted
        request?.errorMessage = "The previous request was interrupted. Your question is kept; retry when ready."
    }

    /// Only a finalized response becomes a message with available domain actions.
    public mutating func acceptResponse(_ text: String, requestID: UUID, metadata: AIResponseMetadata? = nil, now: Date = Date()) -> Bool {
        guard let request, request.id == requestID, request.isPending else { return false }
        if !messages.contains(where: { $0.id == request.responseMessageID }) {
            messages.append(ChatMessage(id: request.responseMessageID, text: text, isUser: false, createdAt: now, responseMetadata: metadata))
        }
        self.request?.state = .completed; self.request?.partialText = ""; self.request?.errorMessage = nil
        updatedAt = now
        return true
    }
}

public struct MaiaConversationLibrary: Codable, Equatable {
    public var revisionID: UUID?
    public var conversations: [MaiaConversation]
    public var selectedID: UUID?
    public var profile: MaiaCommunicationProfile
    public init(conversations: [MaiaConversation] = [], profile: MaiaCommunicationProfile = .init()) {
        revisionID = UUID()
        self.conversations = conversations; selectedID = conversations.first?.id; self.profile = profile
    }
}

/// Local durable history. It is covered by the existing checked editor-data account cleanup.
public final class MaiaConversationStore {
    private let drafts: EditorDraftStore
    private let scope = "maia-conversation-library-v1"
    public init(drafts: EditorDraftStore = EditorDraftStore()) { self.drafts = drafts }

    public func load(userID: String) throws -> MaiaConversationLibrary? {
        try drafts.load(MaiaConversationLibrary.self, userID: userID, scope: scope)?.value
    }

    @discardableResult
    public func save(_ library: MaiaConversationLibrary, userID: String) throws -> MaiaConversationLibrary {
        if let current = try load(userID: userID), current.revisionID != library.revisionID {
            throw MaiaConversationStoreError.changed
        }
        guard Set(library.conversations.map(\.id)).count == library.conversations.count,
              library.selectedID == nil || library.conversations.contains(where: { $0.id == library.selectedID }) else {
            throw CocoaError(.coderInvalidValue)
        }
        var saved = library
        saved.revisionID = UUID()
        try drafts.save(saved, userID: userID, scope: scope)
        return saved
    }

    /// Remove the old key only after the full migration was durably written.
    public func loadOrMigrate(userID: String, defaults: UserDefaults, legacyTone: String? = nil) throws -> MaiaConversationLibrary {
        if let existing = try load(userID: userID) { return existing }
        let key = AccountScopedStorageKey.make(prefix: "chatHistory", userID: userID)
        let legacyKey = "chatHistory_\(userID)"
        let data = key.flatMap { defaults.data(forKey: $0) } ?? defaults.data(forKey: legacyKey)
        let messages = try data.map { try JSONDecoder().decode([ChatMessage].self, from: $0) } ?? []
        let conversation = MaiaConversation(title: messages.first(where: \.isUser).map { String($0.text.prefix(60)) } ?? "New conversation",
                                            messages: messages, createdAt: data == nil ? Date() : nil)
        let library = MaiaConversationLibrary(conversations: [conversation], profile: .init(tone: legacyTone ?? "Balanced"))
        let saved = try save(library, userID: userID)
        if let key { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: legacyKey)
        return saved
    }
}

public enum MaiaConversationStoreError: LocalizedError {
    case changed
    public var errorDescription: String? {
        "A newer conversation was saved in another view. Keep both versions to recover your current text without replacing it."
    }
}
