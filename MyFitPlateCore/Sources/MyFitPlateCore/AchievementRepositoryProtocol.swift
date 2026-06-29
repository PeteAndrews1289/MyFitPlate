import Foundation
import Combine

public protocol AchievementRepositoryProtocol {
    func userProfilePublisher(userID: String) -> AnyPublisher<(points: Int, level: Int)?, Never>
    func userStatusesPublisher(userID: String) -> AnyPublisher<[UserAchievementStatus], Error>
    func activeChallengesPublisher(userID: String) -> AnyPublisher<[Challenge], Error>
    
    func saveUserStatus(userID: String, status: UserAchievementStatus) async throws
    func awardPointsAndCheckLevel(userID: String, points: Int, levelThresholds: [Int]) async throws -> (newPoints: Int, newLevel: Int)
    
    func fetchRecipeCount(userID: String) async throws -> Int
    func fetchWorkoutCount(userID: String) async throws -> Int
    
    func generateWeeklyChallenges(userID: String, challengesToSet: [Challenge]) async throws
    func fetchActiveChallenges(userID: String, type: ChallengeType) async throws -> [Challenge]
    func updateChallenge(userID: String, challenge: Challenge) async throws
}
