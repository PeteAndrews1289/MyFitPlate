import XCTest
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class MaiaActionIntegrityTests: XCTestCase {
    private var owner: String!
    private var repo: MockNutritionRepository!
    private var settings: MockSettingsRepository!
    private var service: DailyLogService!
    private var goals: GoalSettings!
    private var directory: URL!
    private var store: EditorDraftStore!
    private var chatDefaults: UserDefaults!
    private var chatDefaultsSuite: String!
    private var previousAuth: AuthServiceProtocol!
    private var previousRepo: NutritionRepositoryProtocol!
    private var previousSettings: SettingsRepositoryProtocol!
    private let originalDay = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))

    override func setUpWithError() throws {
        owner = "maia-native-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
        chatDefaultsSuite = "maia-native-chat-\(UUID().uuidString)"
        chatDefaults = try XCTUnwrap(UserDefaults(suiteName: chatDefaultsSuite))
        previousAuth = DIContainer.shared.authService
        previousRepo = DIContainer.shared.nutritionRepository
        previousSettings = DIContainer.shared.settingsRepository
        let auth = MockAuthService(); auth.currentUserID = owner
        repo = MockNutritionRepository(); repo.persistsDailyLogUpdates = true
        settings = MockSettingsRepository()
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repo
        DIContainer.shared.settingsRepository = settings
        service = DailyLogService(undoStore: store); service.activateAccount(owner)
        service.activelyViewedDate = originalDay
        goals = GoalSettings(healthKitManager: MockHealthKitManager(), isEditingPreview: true)
        goals.activateAccount(owner)
    }

    override func tearDownWithError() throws {
        service.activateAccount(nil)
        service = nil
        try? FileManager.default.removeItem(at: directory)
        chatDefaults.removePersistentDomain(forName: chatDefaultsSuite)
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.nutritionRepository = previousRepo
        DIContainer.shared.settingsRepository = previousSettings
        goals = nil
    }

    func testActualMaiaWaterHandlerRetainsDayAcrossNewViewModelAndReplaysOnce() async throws {
        repo.updateLogSuccess = false
        let first = makeViewModel()
        let rejected = await action(.logWater(amountOunces: 16), id: "water-card", model: first)
        XCTAssertFalse(rejected)
        XCTAssertFalse(first.isSavingAction)
        service.activelyViewedDate = originalDay.addingTimeInterval(86_400)
        repo.updateLogSuccess = true
        let restored = makeViewModel()
        let accepted = await action(.logWater(amountOunces: 16), id: "water-card", model: restored)
        XCTAssertTrue(accepted)
        let writeCount = repo.dailyLogUpdateUserIDs.count
        let replay = await action(.logWater(amountOunces: 16), id: "water-card", model: makeViewModel())
        XCTAssertTrue(replay)
        XCTAssertEqual(repo.dailyLogUpdateUserIDs.count, writeCount)
        let saved = try await read(originalDay)
        let untouched = try await read(originalDay.addingTimeInterval(86_400))
        XCTAssertEqual(saved.waterTracker?.totalOunces, 16)
        XCTAssertEqual(untouched.waterTracker?.totalOunces ?? 0, 0)
    }

    func testActualWeightHandlerRejectsChangedPendingAmountAndRetriesCapturedMeasurement() async throws {
        settings.saveWeightEntryError = URLError(.notConnectedToInternet)
        let rejected = await action(.logWeight(weightPounds: 165), id: "weight-card", model: makeViewModel())
        XCTAssertFalse(rejected)
        let receipt = try XCTUnwrap(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: "weight-card", store: store))
        XCTAssertEqual(receipt.command, .weight(pounds: 165))
        service.activelyViewedDate = Date()
        settings.saveWeightEntryError = nil
        let changed = await action(.logWeight(weightPounds: 180), id: "weight-card", model: makeViewModel())
        XCTAssertFalse(changed)
        XCTAssertTrue(settings.savedWeightMeasurements.isEmpty)
        let accepted = await action(.logWeight(weightPounds: 165), id: "weight-card", model: makeViewModel())
        XCTAssertTrue(accepted)
        XCTAssertEqual(settings.savedWeightMeasurements.count, 1)
        XCTAssertEqual(settings.savedWeightMeasurements["\(owner!):\(receipt.entryID)"]?.date, originalDay)
        XCTAssertEqual(settings.savedWeightMeasurements["\(owner!):\(receipt.entryID)"]?.weight, 165)
    }

    func testActualClearReviewDiscardsPreparedPreservesSubmittedAndLeavesDiaryIntact() async throws {
        let model = makeViewModel()
        model.setupView()
        let message = ChatMessage(text: "Private conversation ```json\n{\"type\":\"log_water\",\"amountOunces\":8}\n```", isUser: false)
        model.chatMessages = [message]
        let preparedID = "\(message.id.uuidString)-legacy-meal"
        let prepared = MaiaActionSaveSession(userID: owner, actionID: preparedID, store: store)
        XCTAssertTrue(prepared.prepare(command: .weight(pounds: 165), date: originalDay, mealName: "Lunch"))
        let accepted = await action(.logWater(amountOunces: 16), id: "already-saved", model: model)
        XCTAssertTrue(accepted)
        repo.updateLogSuccess = false
        let submittedID = "\(message.id.uuidString)-action-0"
        let rejected = await action(.logWater(amountOunces: 8), id: submittedID, model: model)
        XCTAssertFalse(rejected)
        model.reviewClearChat()
        XCTAssertEqual(model.conversationClearReview.unsubmittedActions.count, 1)
        XCTAssertEqual(model.conversationClearReview.submittedActions.count, 1)
        model.clearChat(discardUnsubmitted: true)
        XCTAssertEqual(model.chatMessages.count, 1)
        XCTAssertFalse(model.chatMessages[0].text.contains("Private conversation"))
        XCTAssertEqual(model.retainedMaiaActions.map(\.actionID), [submittedID])
        XCTAssertNil(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: preparedID, store: store))
        XCTAssertNil(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: "already-saved", store: store)?.command)
        let existing = try await read(originalDay)
        XCTAssertEqual(existing.waterTracker?.totalOunces, 16)

        let reopened = makeViewModel()
        reopened.setupView()
        XCTAssertEqual(reopened.retainedMaiaActions.map(\.actionID), [submittedID])
        repo.updateLogSuccess = true
        let retried = await action(.logWater(amountOunces: 8), id: submittedID, model: reopened)
        XCTAssertTrue(retried)
        XCTAssertTrue(reopened.retainedMaiaActions.isEmpty)
        XCTAssertNil(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: submittedID, store: store)?.command)
        let final = try await read(originalDay)
        XCTAssertEqual(final.waterTracker?.totalOunces, 24)
    }

    func testActualClearDuringInFlightSaveDoesNotRestoreConversationOrPayload() async throws {
        repo.shouldDeferDailyLogUpdateCompletions = true
        let model = makeViewModel()
        model.setupView()
        model.chatMessages = [ChatMessage(text: "Private original conversation", isUser: false)]
        let result = Task { await action(.logWater(amountOunces: 8), id: "clear-inflight-native", model: model) }
        for _ in 0..<100 where repo.deferredDailyLogUpdateCompletions.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        model.reviewClearChat()
        XCTAssertEqual(model.conversationClearReview.submittedActions.count, 1)
        model.clearChat(discardUnsubmitted: true)
        repo.completeDeferredDailyLogUpdates(success: true)
        let accepted = await result.value
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.chatMessages.count, 1)
        XCTAssertFalse(model.chatMessages[0].text.contains("Private original conversation"))
        XCTAssertTrue(model.retainedMaiaActions.isEmpty)
        let receipt = try XCTUnwrap(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: "clear-inflight-native", store: store))
        XCTAssertTrue(receipt.isAccepted)
        XCTAssertNil(receipt.command)
        let log = try await read(originalDay)
        XCTAssertEqual(log.waterTracker?.totalOunces, 8)
    }

    func testStaleAccountClearCannotDeleteOriginalConversationOrAction() throws {
        let model = makeViewModel()
        model.setupView()
        let message = ChatMessage(text: "Original owner chat", isUser: false)
        model.chatMessages = [message]
        model.saveMessages()
        let prepared = MaiaActionSaveSession(userID: owner, actionID: "stale-clear", store: store)
        XCTAssertTrue(prepared.prepare(command: .weight(pounds: 165), date: originalDay, mealName: "Lunch"))
        let auth = try XCTUnwrap(DIContainer.shared.authService as? MockAuthService)
        auth.currentUserID = "different-owner"
        model.clearChat(discardUnsubmitted: true)
        XCTAssertEqual(model.chatMessages, [message])
        XCTAssertEqual(MaiaActionSaveSession.savedReceipt(userID: owner, actionID: "stale-clear", store: store)?.command, .weight(pounds: 165))
        auth.currentUserID = owner
        let reopened = makeViewModel()
        reopened.setupView()
        XCTAssertEqual(reopened.chatMessages, [message])
    }

    private func makeViewModel() -> AIChatbotViewModel {
        let model = AIChatbotViewModel(actionStore: store, chatDefaults: chatDefaults)
        model.dailyLogService = service
        model.goalSettings = goals
        return model
    }

    private func action(_ action: MaiaAction, id: String, model: AIChatbotViewModel) async -> Bool {
        await withCheckedContinuation { continuation in
            model.handleMaiaAction(action, actionID: id) { [model] accepted in
                _ = model.isSavingAction
                continuation.resume(returning: accepted)
            }
        }
    }

    private func read(_ date: Date) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in repo.fetchLogInternal(userID: owner, date: date) { continuation.resume(with: $0) } }
    }
}
