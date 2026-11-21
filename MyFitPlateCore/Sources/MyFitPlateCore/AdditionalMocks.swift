#if DEBUG
import Foundation
import Combine

public final class MockDatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    public init() {}
    public var darkModePreference = false
    public var loadDarkModePreferenceError: Error?
    public var saveDarkModePreferenceError: Error?
    public var recordLastLoginError: Error?
    public var deleteUserDataError: Error?
    public var loadDarkModePreferenceHandler: ((String) async throws -> Bool)?
    public var loadedDarkModeUserIDs: [String] = []
    public var savedDarkModePreferences: [(userID: String, isEnabled: Bool)] = []
    public var recordedLastLoginUserIDs: [String] = []
    public var deletedUserDataIDs: [String] = []

    public func loadDarkModePreference(userID: String) async throws -> Bool {
        if let loadDarkModePreferenceError { throw loadDarkModePreferenceError }
        loadedDarkModeUserIDs.append(userID)
        if let loadDarkModePreferenceHandler {
            return try await loadDarkModePreferenceHandler(userID)
        }
        return darkModePreference
    }

    public func saveDarkModePreference(userID: String, isEnabled: Bool) async throws {
        if let saveDarkModePreferenceError { throw saveDarkModePreferenceError }
        savedDarkModePreferences.append((userID, isEnabled))
    }

    public func recordLastLogin(userID: String) async throws {
        if let recordLastLoginError { throw recordLastLoginError }
        recordedLastLoginUserIDs.append(userID)
    }

    public func deleteUserAllData(userID: String) async throws {
        if let deleteUserDataError { throw deleteUserDataError }
        deletedUserDataIDs.append(userID)
    }
}

public final class MockCloudFunctionService: CloudFunctionServiceProtocol, @unchecked Sendable {
    public init() {}
    public var mockCallFunctionResult: Result<Any?, Error>?
    public var onCall: (([String: Any]) throws -> Result<Any?, Error>)?
    public var deleteUserDataCalled = false
    public var deleteUserDataError: Error?
    public var onDeleteUserData: (() -> Void)?
    public private(set) var expectedDeletionUserIDs: [String] = []
    public func deleteUserData(expectedUserID: String) async throws {
        expectedDeletionUserIDs.append(expectedUserID)
        try await deleteUserData()
    }

    public func deleteUserData() async throws {
        if let deleteUserDataError { throw deleteUserDataError }
        deleteUserDataCalled = true
        onDeleteUserData?()
    }

    public func callFunction(_ name: String, with data: [String: Any]) async throws -> Any? { 
        if let onCall {
            return try onCall(data).get()
        }
        if let result = mockCallFunctionResult {
            return try result.get()
        }
        return nil 
    }
}

public final class MockGroupRepository: GroupRepositoryProtocol, @unchecked Sendable {
    public init() {}
    public var createdGroups: [CommunityGroup] = []
    public var groupsToFetch: [CommunityGroup] = []
    public var joinedGroups: [(userID: String, groupID: String)] = []
    public var leftGroups: [(userID: String, groupID: String)] = []
    public var membershipChecks: [(userID: String, groupID: String)] = []
    public var isMember = false
    public var error: Error?

    public func createGroup(group: CommunityGroup) async throws {
        if let error { throw error }
        createdGroups.append(group)
    }

    public func fetchGroups() async throws -> [CommunityGroup] {
        if let error { throw error }
        return groupsToFetch
    }

    public func joinGroup(userID: String, groupID: String) async throws {
        if let error { throw error }
        joinedGroups.append((userID, groupID))
    }

    public func leaveGroup(userID: String, groupID: String) async throws {
        if let error { throw error }
        leftGroups.append((userID, groupID))
    }

    public func checkGroupMembership(userID: String, groupID: String) async throws -> Bool {
        if let error { throw error }
        membershipChecks.append((userID, groupID))
        return isMember
    }
}

public final class MockAchievementRepository: AchievementRepositoryProtocol {
    public init() {}
    
    private let lock = NSLock()
    
    public var mockProfilePublisher = PassthroughSubject<(points: Int, level: Int)?, Never>()
    public var mockUserProfile: (points: Int, level: Int)?
    public func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never> {
        if let mockUserProfile {
            let profile: (points: Int, level: Int)? = mockUserProfile
            return Just(profile).eraseToAnyPublisher()
        }
        return mockProfilePublisher.eraseToAnyPublisher()
    }
    
    public var mockStatusesPublisher = PassthroughSubject<[UserAchievementStatus], Error>()
    public var mockUserStatuses: [UserAchievementStatus]?
    public func userStatusesPublisher(userID: String) -> AnyPublisher<[UserAchievementStatus], Error> {
        if let mockUserStatuses {
            return Just(mockUserStatuses).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return mockStatusesPublisher.eraseToAnyPublisher()
    }
    
    public var mockChallengesPublisher = PassthroughSubject<[Challenge], Error>()
    public var mockChallenges: [Challenge]?
    public func activeChallengesPublisher(userID: String) -> AnyPublisher<[Challenge], Error> {
        if let mockChallenges {
            return Just(mockChallenges).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return mockChallengesPublisher.eraseToAnyPublisher()
    }
    
    private var _savedStatuses: [UserAchievementStatus] = []
    public var savedStatuses: [UserAchievementStatus] {
        lock.lock(); defer { lock.unlock() }; return _savedStatuses
    }
    public func saveUserStatus(userID: String, status: UserAchievementStatus) async throws {
        guard !status.isUnlocked, status.currentProgress.isFinite else { throw AchievementAwardError.invalid }
        lock.withLock {
            let existing = awardStatusesByUser[userID]?[status.achievementID]
                ?? mockUserStatuses?.first(where: { $0.achievementID == status.achievementID })
            guard existing?.isUnlocked != true else { return }
            var next = status; next.currentProgress = max(existing?.currentProgress ?? 0, status.currentProgress)
            awardStatusesByUser[userID, default: [:]][status.achievementID] = next
            _savedStatuses.append(next)
        }
    }
    
    public var awardError: Error?
    public var awardErrorsByID: [String: Error] = [:]
    public var awardErrorsByFoodID: [String: Error] = [:]
    public var awardFailureAfterCommit: Error?
    public var awardDelayNanoseconds: UInt64 = 0
    public var beforeAcceptAward: (@MainActor (AchievementAwardCommand) -> Void)?
    private var awardStatusesByUser: [String: [String: UserAchievementStatus]] = [:]
    private var awardPointsByUser: [String: Int] = [:]
    private var awardReceiptsByUser: [String: [String: AchievementAwardResult]] = [:]
    private var _acceptedAwardCount = 0
    public var acceptedAwardCount: Int { lock.withLock { _acceptedAwardCount } }

    private var legacyBalances: [String: LegacyAchievementBalanceReceipt] = [:]
    public func preserveLegacyPointBalance(userID: String) async throws -> LegacyAchievementBalanceReceipt {
        let owner = await MainActor.run { DIContainer.shared.authService.currentUserID }
        guard owner == userID else { throw AchievementAwardError.accountChanged }
        return try lock.withLock {
            let receipt = try LegacyAchievementBalanceReceipt.preserving(legacyBalances[userID], ownerID: userID,
                profilePoints: awardPointsByUser[userID] ?? mockUserProfile?.points ?? 0)
            legacyBalances[userID] = receipt
            return receipt
        }
    }

    public func acceptAward(_ command: AchievementAwardCommand, levelThresholds: [Int]) async throws -> AchievementAwardResult {
        if let beforeAcceptAward { await beforeAcceptAward(command) }
        if awardDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: awardDelayNanoseconds) }
        let ownerID = await MainActor.run { DIContainer.shared.authService.currentUserID }
        try command.validate(currentUserID: ownerID)
        if let awardError { throw awardError }
        if let error = awardErrorsByID[command.id] { throw error }
        if let foodID = command.evidence.facts?["foodID"], let error = awardErrorsByFoodID[foodID] { throw error }
        let result: AchievementAwardResult = try lock.withLock {
            let owner = command.ownerID
            if awardStatusesByUser[owner] == nil {
                awardStatusesByUser[owner] = Dictionary((mockUserStatuses ?? []).map { ($0.achievementID, $0) }, uniquingKeysWith: { first, second in first.isUnlocked ? first : second })
            }
            let oldPoints = awardPointsByUser[owner] ?? mockUserProfile?.points ?? 0
            guard oldPoints >= 0, oldPoints <= Int.max - command.points else { throw AchievementAwardError.invalid }
            legacyBalances[owner] = try LegacyAchievementBalanceReceipt.preserving(legacyBalances[owner], ownerID: owner, profilePoints: oldPoints)
            if let receipt = awardReceiptsByUser[owner]?[command.id] {
                return AchievementAwardResult(status: receipt.status, totalPoints: oldPoints,
                    level: AchievementRules.level(for: oldPoints, thresholds: levelThresholds), awardedNow: false)
            }
            let existing = awardStatusesByUser[owner]?[command.id]
            var status = command.status
            let awardsNow = existing?.isUnlocked != true
            if let existing, existing.isUnlocked {
                status = existing
                if status.awardEvidence == nil { status.legacyAwardPreserved = true }
            }
            let points = oldPoints + (awardsNow ? command.points : 0)
            let result = AchievementAwardResult(status: status, totalPoints: points,
                level: AchievementRules.level(for: points, thresholds: levelThresholds), awardedNow: awardsNow)
            awardStatusesByUser[owner, default: [:]][command.id] = status
            awardPointsByUser[owner] = points
            awardReceiptsByUser[owner, default: [:]][command.id] = result
            _savedStatuses.append(status)
            if awardsNow { _acceptedAwardCount += 1 }
            return result
        }
        if let awardFailureAfterCommit { throw awardFailureAfterCommit }
        return result
    }

    public var mockAwardPointsResult = (newPoints: 0, newLevel: 1)
    private var _awardPointsCalledCount = 0
    public var awardPointsCalledCount: Int {
        lock.lock(); defer { lock.unlock() }; return _awardPointsCalledCount
    }
    public func awardPointsAndCheckLevel(userID: String, points: Int, levelThresholds: [Int]) async throws -> (newPoints: Int, newLevel: Int) { 
        incrementAwardPointsCalledCount()
        return mockAwardPointsResult 
    }
    
    public var mockRecipeCount = 0
    public func fetchRecipeCount(userID: String) async throws -> Int { return mockRecipeCount }
    
    public var mockWorkoutCount = 0
    public func fetchWorkoutCount(userID: String) async throws -> Int { return mockWorkoutCount }
    
    private var _generatedChallenges: [Challenge] = []
    public var generatedChallenges: [Challenge] {
        lock.lock(); defer { lock.unlock() }; return _generatedChallenges
    }
    public func generateWeeklyChallenges(userID: String, challengesToSet: [Challenge]) async throws {
        setGeneratedChallenges(challengesToSet)
    }
    
    public var mockActiveChallenges: [Challenge] = []
    public func fetchActiveChallenges(userID: String, type: ChallengeType) async throws -> [Challenge] { return mockActiveChallenges }
    
    private var _updatedChallenges: [Challenge] = []
    public var updatedChallenges: [Challenge] {
        lock.lock(); defer { lock.unlock() }; return _updatedChallenges
    }
    public func updateChallenge(userID: String, challenge: Challenge) async throws {
        appendUpdatedChallenge(challenge)
    }

    private func appendSavedStatus(_ status: UserAchievementStatus) {
        lock.lock(); _savedStatuses.append(status); lock.unlock()
    }

    private func incrementAwardPointsCalledCount() {
        lock.lock(); _awardPointsCalledCount += 1; lock.unlock()
    }

    private func setGeneratedChallenges(_ challenges: [Challenge]) {
        lock.lock(); _generatedChallenges = challenges; lock.unlock()
    }

    private func appendUpdatedChallenge(_ challenge: Challenge) {
        lock.lock(); _updatedChallenges.append(challenge); lock.unlock()
    }
}

public final class MockSettingsRepository: SettingsRepositoryProtocol, @unchecked Sendable {
    public init() {}
    public var mockFetchUserGoalsResult: [String: Any]?
    public var shouldDeferFetchUserGoals = false
    private let fetchLock = NSLock()
    private var storedFetchCallbacks: [String: ([String: Any]?) -> Void] = [:]
    private var storedFetchedIDs: [String] = []
    public var fetchUserGoalsCallbacks: [String: ([String: Any]?) -> Void] {
        fetchLock.withLock { storedFetchCallbacks }
    }
    public var fetchedUserGoalIDs: [String] {
        get { fetchLock.withLock { storedFetchedIDs } }
        set { fetchLock.withLock { storedFetchedIDs = newValue } }
    }
    public var mockWeightHistory: [(id: String, date: Date, weight: Double)] = []
    public var savedUserGoals: [String: Any]?
    public func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void) {
        // accountProfile's async bridge may call this on a cooperative executor
        // while a test awaits the deferred callback on MainActor.
        fetchLock.withLock {
            storedFetchedIDs.append(userID)
            storedFetchCallbacks[userID] = completion
        }
        if !shouldDeferFetchUserGoals {
            completion(mockFetchUserGoalsResult)
        }
    }
    public func emitUserGoals(_ data: [String: Any]?, for userID: String) {
        fetchUserGoalsCallbacks[userID]?(data)
    }
    
    public var onSave: (() -> Void)?
    public var saveUserGoalsError: Error?
    public var goalEditorSaveDelayNanoseconds: UInt64 = 0
    public private(set) var goalEditorSaveUserIDs: [String] = []
    public private(set) var waterGoalSaveUserIDs: [String] = []
    public private(set) var foodPreferencesSaveUserIDs: [String] = []
    public var saveWeightEntryError: Error?
    public var weightSaveDelayNanoseconds: UInt64 = 0
    public private(set) var savedWeightEntries: [(userID: String, weight: Double)] = []
    public private(set) var savedWeightMeasurements: [String: (userID: String, weight: Double, date: Date)] = [:]
    public private(set) var weightSaveAttemptIDs: [String] = []
    public private(set) var createdInitialUserData: [(userID: String, email: String, username: String)] = []

    public func saveUserGoals(userID: String, data: [String: Any]) async throws {
        if let saveUserGoalsError { throw saveUserGoalsError }
        savedUserGoals = data
        onSave?()
    }
    public var weeklyDecisionNow: () -> Date = { Date() }
    public var weeklyDecisionErrorAfterCommit: Error?
    public private(set) var weeklyTargetDecisions: [String: [UUID: WeeklyTargetDecision]] = [:]
    public private(set) var weeklyTargetCommitCount = 0
    @MainActor
    public func saveWeeklyTargetDecision(_ decision: WeeklyTargetDecision) async throws -> WeeklyTargetDecision {
        let owner = decision.proposal.userID
        guard DIContainer.shared.authService.currentUserID == owner else { throw WeeklyTargetReviewError.accountChanged }
        if let existing = weeklyTargetDecisions[owner]?[decision.id] {
            guard existing == decision else { throw WeeklyTargetReviewError.changed }
            return existing
        }
        try decision.validateForNewCommit(now: weeklyDecisionNow())
        if let current = mockFetchUserGoalsResult, !decision.proposal.matchesPersistedTargets(current) {
            throw WeeklyTargetReviewError.changed
        }
        if goalEditorSaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: goalEditorSaveDelayNanoseconds) }
        guard DIContainer.shared.authService.currentUserID == owner else { throw WeeklyTargetReviewError.accountChanged }
        if let saveUserGoalsError { throw saveUserGoalsError }
        if !decision.profilePatch.isEmpty {
            savedUserGoals = decision.profilePatch
            if var current = mockFetchUserGoalsResult {
                var goals = current["goals"] as? [String: Any] ?? [:]
                for (key, value) in decision.profilePatch where key != "goals" { current[key] = value }
                for (key, value) in decision.profilePatch["goals"] as? [String: Any] ?? [:] { goals[key] = value }
                current["goals"] = goals; mockFetchUserGoalsResult = current
            }
        }
        weeklyTargetDecisions[owner, default: [:]][decision.id] = decision
        weeklyTargetCommitCount += 1
        if let weeklyDecisionErrorAfterCommit { throw weeklyDecisionErrorAfterCommit }
        return decision
    }
    @MainActor
    public func fetchWeeklyTargetDecisions(userID: String) async throws -> [WeeklyTargetDecision] {
        guard DIContainer.shared.authService.currentUserID == userID else { throw WeeklyTargetReviewError.accountChanged }
        return (weeklyTargetDecisions[userID] ?? [:]).values.sorted { $0.decidedAt > $1.decidedAt }
    }

    @MainActor
    public func saveGoalEditorChange(userID: String, baseline: GoalEditorDraft, data: [String: Any]) async throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw GoalEditorError.accountChanged }
        if let current = mockFetchUserGoalsResult, !baseline.matchesPersistedInputs(current) { throw GoalEditorError.changed }
        goalEditorSaveUserIDs.append(userID)
        if goalEditorSaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: goalEditorSaveDelayNanoseconds) }
        guard DIContainer.shared.authService.currentUserID == userID else { throw GoalEditorError.accountChanged }
        try await saveUserGoals(userID: userID, data: data)
    }
    @MainActor
    public func saveWaterGoalChange(userID: String, baseline: Double, goal: Double) async throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw GoalEditorError.accountChanged }
        if let goals = mockFetchUserGoalsResult?["goals"] as? [String: Any], let current = goals["waterGoal"] {
            guard let value = current as? NSNumber,
                  abs(value.doubleValue - baseline) < 0.0001 || abs(value.doubleValue - goal) < 0.0001 else { throw GoalEditorError.changed }
        }
        waterGoalSaveUserIDs.append(userID)
        if goalEditorSaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: goalEditorSaveDelayNanoseconds) }
        guard DIContainer.shared.authService.currentUserID == userID else { throw GoalEditorError.accountChanged }
        try await saveUserGoals(userID: userID, data: ["goals": ["waterGoal": goal]])
    }
    @MainActor
    public func saveFoodPreferencesChange(userID: String, baseline: FoodPreferencesDraft, draft: FoodPreferencesDraft) async throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw FoodPreferencesError.accountChanged }
        if let current = mockFetchUserGoalsResult,
           !baseline.matchesPersistedPreferences(current), !draft.matchesPersistedPreferences(current) { throw FoodPreferencesError.changed }
        foodPreferencesSaveUserIDs.append(userID)
        if goalEditorSaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: goalEditorSaveDelayNanoseconds) }
        guard DIContainer.shared.authService.currentUserID == userID else { throw FoodPreferencesError.accountChanged }
        try await saveUserGoals(userID: userID, data: draft.profilePatch(updatedAt: Date()))
    }

    public func weightHistoryPublisher(userID: String) -> AnyPublisher<[(id: String, date: Date, weight: Double)], Error> {
        return Just(mockWeightHistory).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    public func saveWeightEntry(userID: String, weight: Double, date: Date) async throws {
        if let saveWeightEntryError { throw saveWeightEntryError }
        savedWeightEntries.append((userID: userID, weight: weight))
    }
    public func saveWeightMeasurement(userID: String, entryID: String, weight: Double, date: Date) async throws -> Bool {
        weightSaveAttemptIDs.append(entryID)
        if let saveWeightEntryError { throw saveWeightEntryError }
        if weightSaveDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: weightSaveDelayNanoseconds) }
        let key = "\(userID):\(entryID)"
        if let existing = savedWeightMeasurements[key] {
            guard existing.weight == weight, existing.date == date else { throw GoalEditorError.changed }
            return false
        }
        try await saveWeightEntry(userID: userID, weight: weight, date: date)
        savedWeightMeasurements[key] = (userID, weight, date)
        return true
    }
    public func deleteWeightEntry(userID: String, entryID: String) async throws {}
    public func fetchWeightHistory(userID: String) async throws -> [(id: String, date: Date, weight: Double)] { return mockWeightHistory }
    public func fetchWeightHistoryForReview(userID: String) async throws -> [(id: String, date: Date, weight: Double)] { return mockWeightHistory }
    public func updateUserAsOnboarded(userID: String) async throws {}
    public func createInitialUserData(userID: String, email: String, username: String) async throws {
        createdInitialUserData.append((userID: userID, email: email, username: username))
    }
}

public final class MockReportsRepository: ReportsRepositoryProtocol {
    public init() {}
    public func fetchMealScoreHistory(userID: String) async throws -> [DateValuePoint] { return [] }
    public func saveMealScore(userID: String, date: Date, score: MealScore) async throws {}
}

public final class MockPostRepository: PostRepositoryProtocol {
    public init() {}
    public func fetchPostsForGroup(groupID: String) -> AnyPublisher<[CommunityPost], Error> {
        return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    public func savePost(post: CommunityPost) async throws {}
    public func updatePostComments(postId: String, comments: [CommunityPost.Comment]) async throws {}
    public func updatePostLikes(postId: String, likes: Int, isLikedByCurrentUser: Bool) async throws {}
    public func fetchUserName(userID: String) async throws -> String? { return nil }
}

public final class MockAccountDeletionService: AccountDeletionServicing {
    public init() {}
    public func deleteCurrentAccount(password: String) async throws -> AccountDeletionOutcome { return AccountDeletionOutcome(userID: "") }
    public func deleteCurrentAccount(appleCredential: AppleIDCredential) async throws -> AccountDeletionOutcome { return AccountDeletionOutcome(userID: "") }
}

public final class MockAIService: AIServiceProtocol, @unchecked Sendable {
    public var mockResult: Result<String, AIError> = .success("Mock response")
    public var mockResults: [Result<String, AIError>] = []
    public var responseDelayNanoseconds: UInt64 = 0
    public private(set) var lastMessages: [[String: Any]] = []
    public private(set) var lastRequestKind: AIRequestKind = .general
    
    public init() {}
    public func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        requestKind: AIRequestKind,
        retryCount: Int
    ) async -> Result<String, AIError> {
        lastMessages = messages
        lastRequestKind = requestKind
        if responseDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        if !mockResults.isEmpty {
            return mockResults.removeFirst()
        }
        return mockResult
    }
}
#endif
