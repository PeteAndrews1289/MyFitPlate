import XCTest
@testable import MyFitPlateCore

final class MaiaConversationStoreTests: XCTestCase {
    func testLegacyMigrationPreservesActionIDsAndUnknownTimesWithoutTruncatingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let messages = (0..<30).map { ChatMessage(text: "Message \($0)", isUser: $0.isMultiple(of: 2), createdAt: nil) }
        defaults.set(try JSONEncoder().encode(messages), forKey: "chatHistory_one")
        let store = MaiaConversationStore(drafts: EditorDraftStore(directory: directory))
        let library = try store.loadOrMigrate(userID: "one", defaults: defaults)
        XCTAssertEqual(library.conversations.first?.messages, messages)
        XCTAssertNil(library.conversations.first?.createdAt)
        XCTAssertNil(defaults.data(forKey: "chatHistory_one"))
        XCTAssertEqual(try store.load(userID: "one"), library)
        XCTAssertNil(try store.load(userID: "two"))
    }

    func testOldMessageDecodeDoesNotInventTimestamp() throws {
        let id = UUID()
        let raw = "{\"id\":\"\(id)\",\"text\":\"Original\",\"isUser\":false}"
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(raw.utf8))
        XCTAssertEqual(message.id, id)
        XCTAssertNil(message.createdAt)
    }

    func testInterruptedRequestKeepsDraftAndQuestionWithoutPublishingPartialAction() throws {
        var conversation = MaiaConversation()
        let message = ChatMessage(text: "Log water", isUser: true)
        conversation.messages = [message]; conversation.draft = "Next question"
        conversation.request = .init(questionMessageID: message.id, question: message.text, contextDate: Date(), contract: .hydration)
        conversation.request?.partialText = "Here is {\"type\":\"log_water\""
        conversation.recoverInterruptedRequest()
        XCTAssertEqual(conversation.request?.state, .interrupted)
        XCTAssertEqual(conversation.messages, [message])
        XCTAssertEqual(conversation.draft, "Next question")
        XCTAssertFalse(conversation.acceptResponse("Late answer", requestID: conversation.request!.id))
    }

    func testFinalResponseUsesStableIdentityAndIsNeverAppendedTwice() {
        var conversation = MaiaConversation()
        let request = MaiaConversationRequest(questionMessageID: UUID(), question: "Next?", contextDate: Date(), contract: .hydration)
        conversation.request = request
        XCTAssertTrue(conversation.acceptResponse("Drink water.", requestID: request.id))
        XCTAssertFalse(conversation.acceptResponse("Drink water again.", requestID: request.id))
        XCTAssertEqual(conversation.messages.map(\.id), [request.responseMessageID])
    }

    func testContextCanOnlyNarrowQuickActionAndProfilesDoNotChangeFacts() {
        let context = MaiaConversationContext(includedScopes: [.water], includeRecentMessages: false, notes: "I prefer short answers.")
        let narrowed = context.restricting(.generalChat(includeHealthKit: true))
        XCTAssertEqual(narrowed.scopes, [.water])
        for length in MaiaCommunicationProfile.Length.allCases {
            for motivation in MaiaCommunicationProfile.Motivation.allCases {
                let profile = MaiaCommunicationProfile(length: length, motivation: motivation)
                XCTAssertTrue(profile.promptInstructions.contains("never change facts, calorie targets, exercise prescriptions"))
                XCTAssertTrue(profile.promptInstructions.contains("explicit reviewed saves"))
            }
        }
    }

    func testStylePreviewKeepsTheSameNumbersAndReviewBoundaryAcrossEveryChoice() {
        for tone in ["Balanced", "Coach", "Analyst"] {
            for length in MaiaCommunicationProfile.Length.allCases {
                for motivation in MaiaCommunicationProfile.Motivation.allCases {
                    let profile = MaiaCommunicationProfile(tone: tone, length: length, motivation: motivation)
                    let answer = profile.previewAnswer
                    XCTAssertTrue(answer.contains("500 calories and 30 g protein"))
                    XCTAssertTrue(answer.lowercased().contains("review") || answer.lowercased().contains("compare"))
                    XCTAssertFalse(answer.contains("saved your") || answer.contains("logged your"))
                    XCTAssertTrue(profile.promptInstructions.contains("never change facts"))
                }
            }
        }
    }

    func testUserMaintainedSummaryRoundTripsWithoutInventingEarlierMemory() throws {
        let context = MaiaConversationContext(includedScopes: [], includeRecentMessages: false,
            notes: "I prefer a simple lunch. I have not supplied a verified weight.")
        let restored = try JSONDecoder().decode(MaiaConversationContext.self, from: JSONEncoder().encode(context))
        XCTAssertEqual(restored, context)
        XCTAssertFalse(restored.includeRecentMessages)
        XCTAssertTrue(restored.includedScopes.isEmpty)
    }

    func testStaleLibrarySaveCannotReplaceNewerDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaiaConversationStore(drafts: EditorDraftStore(directory: directory))
        let first = try store.save(.init(conversations: [MaiaConversation()]), userID: "one")
        var newer = first; newer.conversations[0].draft = "Newer draft"
        newer = try store.save(newer, userID: "one")
        var stale = first; stale.conversations[0].draft = "Stale draft"
        XCTAssertThrowsError(try store.save(stale, userID: "one"))
        XCTAssertEqual(try store.load(userID: "one"), newer)
    }

    func testFirstVersionLibraryWithoutRevisionStillDecodesAndUpgrades() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MaiaConversationLibrary())) as? [String: Any])
        object.removeValue(forKey: "revisionID")
        let legacy = try JSONDecoder().decode(MaiaConversationLibrary.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.revisionID)
    }

    func testUnreadableHistoryBlocksMigrationWithoutDeletingOriginalMessages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let raw = Data("unreadable history".utf8)
        defaults.set(raw, forKey: "chatHistory_one")
        let store = MaiaConversationStore(drafts: EditorDraftStore(directory: directory))
        XCTAssertThrowsError(try store.loadOrMigrate(userID: "one", defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: "chatHistory_one"), raw)
    }
}
