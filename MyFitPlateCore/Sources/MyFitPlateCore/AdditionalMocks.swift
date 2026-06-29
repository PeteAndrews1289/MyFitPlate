import Foundation
import Combine

public final class MockDatabaseService: DatabaseServiceProtocol {
    public init() {}
    public func loadDarkModePreference(userID: String) async throws -> Bool { return false }
    public func saveDarkModePreference(userID: String, isEnabled: Bool) async throws {}
    public func recordLastLogin(userID: String) async throws {}
    public func deleteUserAllData(userID: String) async throws {}
}

public final class MockCloudFunctionService: CloudFunctionServiceProtocol, @unchecked Sendable {
    public init() {}
    public var mockCallFunctionResult: Result<Any?, Error>?
    public func deleteUserData() async throws {}
    public func callFunction(_ name: String, with data: [String: Any]) async throws -> Any? { 
        if let result = mockCallFunctionResult {
            return try result.get()
        }
        return nil 
    }
}

public final class MockGroupRepository: GroupRepositoryProtocol {
    public init() {}
    public func createGroup(group: CommunityGroup) async throws {}
    public func fetchGroups() async throws -> [CommunityGroup] { return [] }
    public func joinGroup(userID: String, groupID: String) async throws {}
    public func leaveGroup(userID: String, groupID: String) async throws {}
    public func checkGroupMembership(userID: String, groupID: String) async throws -> Bool { return false }
}

public final class MockAchievementRepository: AchievementRepositoryProtocol {
    public init() {}
    
    private let lock = NSLock()
    
    public var mockProfilePublisher = PassthroughSubject<(points: Int, level: Int)?, Never>()
    public func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never> {
        return mockProfilePublisher.eraseToAnyPublisher()
    }
    
    public var mockStatusesPublisher = PassthroughSubject<[UserAchievementStatus], Error>()
    public func userStatusesPublisher(userID: String) -> AnyPublisher<[UserAchievementStatus], Error> {
        return mockStatusesPublisher.eraseToAnyPublisher()
    }
    
    public var mockChallengesPublisher = PassthroughSubject<[Challenge], Error>()
    public func activeChallengesPublisher(userID: String) -> AnyPublisher<[Challenge], Error> {
        return mockChallengesPublisher.eraseToAnyPublisher()
    }
    
    private var _savedStatuses: [UserAchievementStatus] = []
    public var savedStatuses: [UserAchievementStatus] {
        lock.lock(); defer { lock.unlock() }; return _savedStatuses
    }
    public func saveUserStatus(userID: String, status: UserAchievementStatus) async throws {
        lock.lock(); _savedStatuses.append(status); lock.unlock()
    }
    
    public var mockAwardPointsResult = (newPoints: 0, newLevel: 1)
    private var _awardPointsCalledCount = 0
    public var awardPointsCalledCount: Int {
        lock.lock(); defer { lock.unlock() }; return _awardPointsCalledCount
    }
    public func awardPointsAndCheckLevel(userID: String, points: Int, levelThresholds: [Int]) async throws -> (newPoints: Int, newLevel: Int) { 
        lock.lock(); _awardPointsCalledCount += 1; lock.unlock()
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
        lock.lock(); _generatedChallenges = challengesToSet; lock.unlock()
    }
    
    public var mockActiveChallenges: [Challenge] = []
    public func fetchActiveChallenges(userID: String, type: ChallengeType) async throws -> [Challenge] { return mockActiveChallenges }
    
    private var _updatedChallenges: [Challenge] = []
    public var updatedChallenges: [Challenge] {
        lock.lock(); defer { lock.unlock() }; return _updatedChallenges
    }
    public func updateChallenge(userID: String, challenge: Challenge) async throws {
        lock.lock(); _updatedChallenges.append(challenge); lock.unlock()
    }
}

public final class MockSettingsRepository: SettingsRepositoryProtocol, @unchecked Sendable {
    public init() {}
    public var mockFetchUserGoalsResult: [String: Any]?
    public var savedUserGoals: [String: Any]?
    public func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void) { completion(mockFetchUserGoalsResult) }
    
    public var onSave: (() -> Void)?
    
    public func saveUserGoals(userID: String, data: [String: Any]) async throws {
        savedUserGoals = data
        onSave?()
    }
    public func weightHistoryPublisher(userID: String) -> AnyPublisher<[(id: String, date: Date, weight: Double)], Error> {
        return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    public func saveWeightEntry(userID: String, weight: Double, date: Date) async throws {}
    public func deleteWeightEntry(userID: String, entryID: String) async throws {}
    public func fetchWeightHistory(userID: String) async throws -> [(id: String, date: Date, weight: Double)] { return [] }
    public func updateUserAsOnboarded(userID: String) async throws {}
    public func createInitialUserData(userID: String, email: String, username: String) async throws {}
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
}

public final class MockAIService: AIServiceProtocol, @unchecked Sendable {
    public var mockResult: Result<String, AIError> = .success("Mock response")
    public var mockResults: [Result<String, AIError>] = []
    
    public init() {}
    public func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        retryCount: Int
    ) async -> Result<String, AIError> {
        if !mockResults.isEmpty {
            return mockResults.removeFirst()
        }
        return mockResult
    }
}
