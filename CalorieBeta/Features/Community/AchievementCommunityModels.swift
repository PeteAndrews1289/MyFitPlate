import Foundation
import FirebaseFirestore

struct ChallengeType: RawRepresentable, Codable, Hashable {
    var rawValue: String
}

extension ChallengeType {
    static let loggingStreak = ChallengeType(rawValue: "loggingStreak")
    static let proteinGoalHit = ChallengeType(rawValue: "proteinGoalHit")
    static let workoutLogged = ChallengeType(rawValue: "workoutLogged")
    static let calorieRange = ChallengeType(rawValue: "calorieRange")
}

struct Challenge: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var type: ChallengeType
    var goal: Double
    var progress: Double = 0
    var pointsValue: Int
    var isCompleted: Bool = false
    var expiresAt: Date
}

enum CalorieGoalMethod: String, CaseIterable, Identifiable, Codable { case custom = "Custom (Manual Entry)"; case dynamicTDEE = "Dynamic (TDEE + Activity)"; case mifflinWithActivity = "Standard (Mifflin + Activity Level)"; var id: String { self.rawValue } }
struct CommunityPost: Identifiable, Codable { @DocumentID var id: String?; let authorID: String?; let author: String; let content: String; var likes: Int = 0; var isLikedByCurrentUser: Bool = false; var reactions: [String: Int] = [:]; var comments: [Comment] = []; var timestamp: Date = Date(); var groupID: String; struct Comment: Identifiable, Codable { var id: String = UUID().uuidString; let author: String; let content: String; var replies: [Reply] = []; struct Reply: Identifiable, Codable { var id: String = UUID().uuidString; let author: String; let content: String } }; }
struct CommunityGroup: Identifiable, Codable { @DocumentID var id: String?; var name: String; var description: String; var creatorID: String; var isPreset: Bool = false }
struct GroupMembership: Codable { var groupID: String; var userID: String; var joinedAt: Timestamp = Timestamp(date: Date()) }

enum AchievementCriteriaType: String, Codable {
    case loggingStreak, goalHitCount, calorieGoalHitCount, macroGoalHitCount, waterGoalHitCount, weightChange, targetWeightReached, featureUsed, barcodeScanUsed, imageScanUsed, aiRecipeLogged, workoutsLogged, recipesCreated
}

struct AchievementDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let criteriaType: AchievementCriteriaType
    let criteriaValue: Double
    let pointsValue: Int
    let secret: Bool = false
}

struct UserAchievementStatus: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var achievementID: String
    var isUnlocked: Bool = false
    var unlockedDate: Date? = nil
    var currentProgress: Double = 0.0
    var lastProgressUpdate: Date? = nil

    static func == (lhs: UserAchievementStatus, rhs: UserAchievementStatus) -> Bool {
        lhs.achievementID == rhs.achievementID &&
        lhs.isUnlocked == rhs.isUnlocked &&
        lhs.unlockedDate == rhs.unlockedDate &&
        lhs.currentProgress == rhs.currentProgress &&
        lhs.lastProgressUpdate == rhs.lastProgressUpdate
    }
}
