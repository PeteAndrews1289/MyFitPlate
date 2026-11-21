import XCTest
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class MaiaContinuityNativeTests: XCTestCase {
    private var auth: MockAuthService!
    private var ai: ControlledMaiaService!
    private var previousAuth: AuthServiceProtocol!
    private var previousAI: AIServiceProtocol!
    private var previousAnalytics: AnalyticsManagerProtocol!
    private var previousSettings: SettingsRepositoryProtocol!
    private var settings: MockSettingsRepository!
    private var directory: URL!
    private var store: EditorDraftStore!
    private var defaults: UserDefaults!
    private var owner: String!

    override func setUpWithError() throws {
        previousAuth = DIContainer.shared.authService; previousAI = DIContainer.shared.aiService
        previousAnalytics = DIContainer.shared.analyticsManager; previousSettings = DIContainer.shared.settingsRepository
        owner = "maia-continuity-\(UUID().uuidString)"
        auth = MockAuthService(); auth.currentUserID = owner
        ai = ControlledMaiaService(); settings = MockSettingsRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.aiService = ai
        DIContainer.shared.analyticsManager = MockAnalyticsManager(); DIContainer.shared.settingsRepository = settings
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    override func tearDownWithError() throws {
        ai.finishAll()
        DIContainer.shared.authService = previousAuth; DIContainer.shared.aiService = previousAI
        DIContainer.shared.analyticsManager = previousAnalytics; DIContainer.shared.settingsRepository = previousSettings
        try? FileManager.default.removeItem(at: directory)
    }

    func testCancelDiscardsLateAnswerKeepsQuestionAndUsesStableRetryIdentity() async throws {
        let model = makeModel()
        model.userMessage = "Help with my next session"; model.sendMessage()
        await waitUntil { self.ai.requests.count == 1 }
        let requestID = ai.requests[0].id
        ai.delta("Partial reply", at: 0)
        XCTAssertEqual(model.partialResponse, "Partial reply")
        XCTAssertEqual(model.chatMessages.filter { !$0.isUser }.count, 1)
        model.cancelRequest()
        ai.finish(at: 0, content: "Late reply must be discarded")
        await settle()
        XCTAssertFalse(model.chatMessages.contains { $0.text.contains("Late reply") })
        XCTAssertEqual(model.currentConversation?.request?.state, .cancelled)
        model.retryLastMessage()
        await waitUntil { self.ai.requests.count == 2 }
        XCTAssertEqual(ai.requests[1].id, requestID)
        ai.finish(at: 1, content: "A completed reply")
        await settle()
        XCTAssertEqual(model.chatMessages.filter { $0.text == "Help with my next session" }.count, 1)
        XCTAssertEqual(model.chatMessages.filter { $0.text == "A completed reply" }.count, 1)
        XCTAssertEqual(makeModel().chatMessages, model.chatMessages)
    }

    func testAccountSwitchCannotStoreOrDisplayFormerOwnersLateAnswer() async {
        let model = makeModel()
        model.userMessage = "Private question A"; model.sendMessage()
        await waitUntil { self.ai.requests.count == 1 }
        model.userMessage = "Unsent private draft A"
        model.showingContextControls = true
        auth.currentUserID = "other-owner"; model.setupView()
        XCTAssertEqual(model.userMessage, "")
        XCTAssertFalse(model.showingContextControls)
        ai.finish(at: 0, content: "Private answer A")
        await settle()
        XCTAssertFalse(model.chatMessages.contains { $0.text.contains("Private") })
        XCTAssertFalse(model.isLoading)
        auth.currentUserID = owner
        let restored = makeModel()
        XCTAssertEqual(restored.currentConversation?.request?.state, .interrupted)
        XCTAssertTrue(restored.chatMessages.contains { $0.text == "Private question A" })
    }

    func testSeparateTopicsKeepDraftsAndDoNotShareUnselectedMemory() async throws {
        let model = makeModel()
        let firstID = try XCTUnwrap(model.currentConversation?.id)
        model.userMessage = "Draft for first topic"; model.saveMessages()
        model.newConversation()
        XCTAssertEqual(model.userMessage, "")
        let context = MaiaConversationContext(includedScopes: [], includeRecentMessages: false, notes: "Only this topic's note")
        let topicSaved = await model.updateContext(context, profile: .init(), onlyThisTopic: true)
        XCTAssertTrue(topicSaved)
        model.userMessage = "Second topic question"; model.sendMessage()
        await waitUntil { self.ai.requests.count == 1 }
        let payload = ai.requests[0].messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
        XCTAssertTrue(payload.contains("Only this topic's note"))
        XCTAssertFalse(ai.requests[0].messages.contains { $0["role"] as? String == "system" && ($0["content"] as? String)?.contains("Only this topic's note") == true })
        XCTAssertTrue(ai.requests[0].messages.contains { $0["role"] as? String == "user" && ($0["content"] as? String)?.contains("Only this topic's note") == true })
        XCTAssertFalse(payload.contains("Draft for first topic"))
        model.cancelRequest(); ai.finish(at: 0, content: "discarded")
        model.selectConversation(firstID)
        XCTAssertEqual(model.userMessage, "Draft for first topic")
        XCTAssertEqual(model.currentConversationContext.notes, "")
    }

    func testGlobalStyleContextSurvivesTopicSwitchAndFreshModel() async throws {
        let model = makeModel()
        let firstID = try XCTUnwrap(model.currentConversation?.id)
        model.userMessage = "Tomorrow's lifting question"; model.saveMessages()
        var context = model.currentConversationContext
        context.includeRecentMessages = false; context.notes = "Keep explanations practical"
        let accepted = await model.updateContext(context, profile: model.effectiveCommunicationProfile, onlyThisTopic: false)
        XCTAssertTrue(accepted)
        model.newConversation(); model.selectConversation(firstID)
        XCTAssertFalse(model.currentConversationContext.includeRecentMessages)
        let reopened = makeModel()
        XCTAssertEqual(reopened.userMessage, "Tomorrow's lifting question")
        XCTAssertFalse(reopened.currentConversationContext.includeRecentMessages)
        XCTAssertEqual(reopened.currentConversationContext.notes, "Keep explanations practical")
    }

    func testLateOldViewCannotOverwriteReopenedConversationAndRecoveryKeepsBothVersions() async throws {
        let original = makeModel()
        original.userMessage = "Original question"; original.sendMessage()
        await waitUntil { self.ai.requests.count == 1 }
        let reopened = makeModel()
        reopened.userMessage = "Newer draft"; reopened.saveMessages()
        ai.finish(at: 0, content: "Old late answer")
        await settle()
        XCTAssertTrue(original.hasConversationConflict)
        XCTAssertEqual(makeModel().userMessage, "Newer draft")
        original.retryConversationStorage()
        XCTAssertFalse(original.hasConversationConflict)
        let library = try XCTUnwrap(MaiaConversationStore(drafts: store).load(userID: owner))
        XCTAssertEqual(library.conversations.count, 2)
        XCTAssertTrue(library.conversations.contains { $0.draft == "Newer draft" })
        XCTAssertTrue(library.conversations.contains { $0.title.hasPrefix("Recovered:") })
    }

    func testReceivedActionStaysHiddenUntilConversationSaveSucceeds() async throws {
        let model = makeModel()
        model.userMessage = "Suggest a meal"; model.sendMessage()
        await waitUntil { self.ai.requests.count == 1 }
        let backup = directory.appendingPathExtension("kept")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("Block writes during the reply".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        let answer = "Here is a meal to review. ```json {\"type\":\"meal_suggestion\",\"mealName\":\"Rice bowl\",\"calories\":400,\"protein\":30,\"carbs\":40,\"fats\":10} ```"
        ai.finish(at: 0, content: answer)
        await settle()
        XCTAssertFalse(model.chatMessages.contains { $0.text == answer })
        XCTAssertNotNil(model.storageError)
        XCTAssertFalse(model.canStartNewRequest)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        model.retryConversationStorage()
        XCTAssertEqual(model.chatMessages.filter { $0.text == answer }.count, 1)
        XCTAssertTrue(model.canStartNewRequest)
        XCTAssertEqual(makeModel().chatMessages.filter { $0.text == answer }.count, 1)
    }

    func testToneSaveUsesOnlyTonePatchAndPublishesAfterAcceptance() async throws {
        let model = makeModel()
        let goals = GoalSettings(healthKitManager: MockHealthKitManager(), isEditingPreview: true)
        goals.activateAccount(owner); goals.calories = 2_350; goals.protein = 155; goals.maiaTone = "Balanced"
        model.goalSettings = goals
        settings.mockFetchUserGoalsResult = ["goals": ["calories": 2_350, "protein": 155, "maiaTone": "Balanced"], "activeWorkoutProgramID": "phul-existing"]
        let profile = MaiaCommunicationProfile(tone: "Analyst", length: .detailed, motivation: .neutral)
        settings.saveUserGoalsError = URLError(.notConnectedToInternet)
        let rejected = await model.updateContext(.init(), profile: profile, onlyThisTopic: false)
        XCTAssertFalse(rejected)
        XCTAssertEqual(goals.maiaTone, "Balanced")
        settings.saveUserGoalsError = nil
        let accepted = await model.updateContext(.init(), profile: profile, onlyThisTopic: false)
        XCTAssertTrue(accepted)
        XCTAssertEqual(goals.maiaTone, "Analyst")
        XCTAssertEqual(goals.calories, 2_350); XCTAssertEqual(goals.protein, 155)
        let saved = try XCTUnwrap(settings.savedUserGoals)
        XCTAssertEqual(Set(saved.keys), ["goals"])
        XCTAssertEqual(Set((saved["goals"] as? [String: Any] ?? [:]).keys), ["maiaTone"])
        XCTAssertEqual(settings.mockFetchUserGoalsResult?["activeWorkoutProgramID"] as? String, "phul-existing")
    }

    private func makeModel() -> AIChatbotViewModel {
        let model = AIChatbotViewModel(actionStore: store, chatDefaults: defaults)
        model.setupView(); return model
    }
    private func settle() async { for _ in 0..<100 { await Task.yield() } }
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<200 where !predicate() { await Task.yield() }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class ControlledMaiaService: AIStreamingServiceProtocol {
    struct Request {
        let id: UUID
        let messages: [[String: Any]]
        let onDelta: @MainActor (String) -> Void
        var continuation: CheckedContinuation<Result<MaiaAIResponse, AIError>, Never>?
    }
    var requests: [Request] = []
    func performRequest(messages: [[String: Any]], model: String, maxTokens: Int, temperature: Double,
                        responseFormat: [String: Any]?, requestKind: AIRequestKind, retryCount: Int) async -> Result<String, AIError> {
        .failure(.noData)
    }
    func performStreamingRequest(messages: [[String: Any]], model: String, maxTokens: Int, temperature: Double,
                                 requestKind: AIRequestKind, requestID: UUID, onDelta: @escaping @MainActor (String) -> Void) async -> Result<MaiaAIResponse, AIError> {
        await withCheckedContinuation { continuation in
            requests.append(.init(id: requestID, messages: messages, onDelta: onDelta, continuation: continuation))
        }
    }
    func delta(_ text: String, at index: Int) { requests[index].onDelta(text) }
    func finish(at index: Int, content: String) {
        requests[index].continuation?.resume(returning: .success(.init(content: content)))
        requests[index].continuation = nil
    }
    func finishAll() { for index in requests.indices { finish(at: index, content: "Cleanup") } }
}
