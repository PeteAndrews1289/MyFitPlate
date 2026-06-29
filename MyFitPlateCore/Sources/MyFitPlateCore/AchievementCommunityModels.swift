import Foundation
public struct ChallengeType: RawRepresentable, Codable, Hashable {
    public var rawValue: String
    public init?(rawValue: String) { self.rawValue = rawValue }
}

public extension ChallengeType {
    static let loggingStreak = ChallengeType(rawValue: "loggingStreak")!
    static let proteinGoalHit = ChallengeType(rawValue: "proteinGoalHit")!
    static let workoutLogged = ChallengeType(rawValue: "workoutLogged")!
    static let calorieRange = ChallengeType(rawValue: "calorieRange")!
}

public struct Challenge: Identifiable, Codable {
    public var id: String?
    public var title: String
    public var description: String
    public var type: ChallengeType
    public var goal: Double
    public var progress: Double = 0
    public var pointsValue: Int
    public var isCompleted: Bool = false
    public var expiresAt: Date
}

public enum CalorieGoalMethod: String, CaseIterable, Identifiable, Codable { case custom = "Custom (Manual Entry)"; case dynamicTDEE = "Dynamic (TDEE + Activity)"; case mifflinWithActivity = "Standard (Mifflin + Activity Level)"; public var id: String { self.rawValue } }
public struct CommunityPost: Identifiable, Codable { 
    public var id: String?
    public let authorID: String?
    public let author: String
    public let content: String
    public var likes: Int = 0
    public var isLikedByCurrentUser: Bool = false
    public var reactions: [String: Int] = [:]
    public var comments: [Comment] = []
    public var timestamp: Date = Date()
    public var groupID: String
    
    public init(id: String? = nil, authorID: String? = nil, author: String, content: String, likes: Int = 0, isLikedByCurrentUser: Bool = false, reactions: [String: Int] = [:], comments: [Comment] = [], timestamp: Date = Date(), groupID: String) {
        self.id = id
        self.authorID = authorID
        self.author = author
        self.content = content
        self.likes = likes
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.reactions = reactions
        self.comments = comments
        self.timestamp = timestamp
        self.groupID = groupID
    }

    public struct Comment: Identifiable, Codable { 
        public var id: String = UUID().uuidString
        public let author: String
        public let content: String
        public var replies: [Reply] = []
        
        public init(id: String = UUID().uuidString, author: String, content: String, replies: [Reply] = []) {
            self.id = id
            self.author = author
            self.content = content
            self.replies = replies
        }
        
        public struct Reply: Identifiable, Codable { 
            public var id: String = UUID().uuidString
            public let author: String
            public let content: String 
            
            public init(id: String = UUID().uuidString, author: String, content: String) {
                self.id = id
                self.author = author
                self.content = content
            }
        } 
    } 
}
public struct CommunityGroup: Identifiable, Codable { public var id: String?; public var name: String; public var description: String; public var creatorID: String; public var isPreset: Bool = false; public init(id: String? = nil, name: String, description: String, creatorID: String, isPreset: Bool = false) { self.id = id; self.name = name; self.description = description; self.creatorID = creatorID; self.isPreset = isPreset } }
public struct GroupMembership: Codable { public var groupID: String; public var userID: String; public var joinedAt: Date = Date() }

public enum AchievementCriteriaType: String, Codable {
    case loggingStreak, goalHitCount, calorieGoalHitCount, macroGoalHitCount, waterGoalHitCount, weightChange, targetWeightReached, featureUsed, barcodeScanUsed, imageScanUsed, aiRecipeLogged, workoutsLogged, recipesCreated
}

public struct AchievementDefinition: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let description: String
    public let iconName: String
    public let criteriaType: AchievementCriteriaType
    public let criteriaValue: Double
    public let pointsValue: Int
    public let secret: Bool = false
}

public struct UserAchievementStatus: Identifiable, Codable, Equatable {
    public var id: String?
    public var achievementID: String
    public var isUnlocked: Bool = false
    public var unlockedDate: Date? = nil
    public var currentProgress: Double = 0.0
    public var lastProgressUpdate: Date? = nil

    public static func == (lhs: UserAchievementStatus, rhs: UserAchievementStatus) -> Bool {
        lhs.achievementID == rhs.achievementID &&
        lhs.isUnlocked == rhs.isUnlocked &&
        lhs.unlockedDate == rhs.unlockedDate &&
        lhs.currentProgress == rhs.currentProgress &&
        lhs.lastProgressUpdate == rhs.lastProgressUpdate
    }
}
