import Foundation
import Combine

public final class MockDatabaseService: DatabaseServiceProtocol {
    public init() {}
    public func loadDarkModePreference(userID: String) async throws -> Bool { return false }
    public func saveDarkModePreference(userID: String, isEnabled: Bool) async throws {}
    public func recordLastLogin(userID: String) async throws {}
    public func deleteUserAllData(userID: String) async throws {}
}

public final class MockCloudFunctionService: CloudFunctionServiceProtocol {
    public init() {}
    public func deleteUserData() async throws {}
    public func callFunction(_ name: String, with data: [String: Any]) async throws -> Any? { return nil }
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
    public func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never> {
        return Just(nil).eraseToAnyPublisher()
    }
    public func userStatusesPublisher(userID: String) -> AnyPublisher<[UserAchievementStatus], Error> {
        return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    public func activeChallengesPublisher(userID: String) -> AnyPublisher<[Challenge], Error> {
        return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    public func saveUserStatus(userID: String, status: UserAchievementStatus) async throws {}
    public func awardPointsAndCheckLevel(userID: String, points: Int, levelThresholds: [Int]) async throws -> (newPoints: Int, newLevel: Int) { return (0, 1) }
    public func fetchRecipeCount(userID: String) async throws -> Int { return 0 }
    public func fetchWorkoutCount(userID: String) async throws -> Int { return 0 }
    public func generateWeeklyChallenges(userID: String, challengesToSet: [Challenge]) async throws {}
    public func fetchActiveChallenges(userID: String, type: ChallengeType) async throws -> [Challenge] { return [] }
    public func updateChallenge(userID: String, challenge: Challenge) async throws {}
}

public final class MockSettingsRepository: SettingsRepositoryProtocol {
    public init() {}
    public func fetchUserGoals(userID: String, completion: @escaping ([String: Any]?) -> Void) { completion(nil) }
    public func saveUserGoals(userID: String, data: [String: Any]) async throws {}
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

public final class MockAIService: AIServiceProtocol {
    public init() {}
    public func performRequest(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]?,
        retryCount: Int
    ) async -> Result<String, AIError> {
        return .success("Mock response")
    }
}
