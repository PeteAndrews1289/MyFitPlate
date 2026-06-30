import XCTest
@testable import MyFitPlateCore

final class AchievementCommunityModelsTests: XCTestCase {
    
    func testChallengeType() {
        XCTAssertEqual(ChallengeType.loggingStreak.rawValue, "loggingStreak")
        XCTAssertEqual(ChallengeType.proteinGoalHit.rawValue, "proteinGoalHit")
        XCTAssertEqual(ChallengeType.workoutLogged.rawValue, "workoutLogged")
        XCTAssertEqual(ChallengeType.calorieRange.rawValue, "calorieRange")
        
        let customType = ChallengeType(rawValue: "custom")
        XCTAssertNotNil(customType)
        XCTAssertEqual(customType?.rawValue, "custom")
    }
    
    func testChallengeModel() {
        let challenge = Challenge(
            id: "c1",
            title: "Test",
            description: "Test Desc",
            type: .workoutLogged,
            goal: 5,
            progress: 1,
            pointsValue: 100,
            isCompleted: false,
            expiresAt: Date(timeIntervalSince1970: 0)
        )
        
        XCTAssertEqual(challenge.id, "c1")
        XCTAssertEqual(challenge.title, "Test")
        XCTAssertEqual(challenge.progress, 1)
        XCTAssertFalse(challenge.isCompleted)
    }
    
    func testCalorieGoalMethod() {
        XCTAssertEqual(CalorieGoalMethod.custom.id, "Custom (Manual Entry)")
        XCTAssertEqual(CalorieGoalMethod.dynamicTDEE.id, "Dynamic (TDEE + Activity)")
        XCTAssertEqual(CalorieGoalMethod.mifflinWithActivity.id, "Standard (Mifflin + Activity Level)")
    }
    
    func testCommunityPostAndComments() {
        let reply = CommunityPost.Comment.Reply(author: "User B", content: "Hi A")
        let comment = CommunityPost.Comment(author: "User C", content: "Cool", replies: [reply])
        let post = CommunityPost(
            authorID: "u1",
            author: "User A",
            content: "First post",
            likes: 1,
            isLikedByCurrentUser: true,
            reactions: ["thumb": 1],
            comments: [comment],
            groupID: "g1"
        )
        
        XCTAssertEqual(post.authorID, "u1")
        XCTAssertEqual(post.likes, 1)
        XCTAssertTrue(post.isLikedByCurrentUser)
        XCTAssertEqual(post.reactions["thumb"], 1)
        XCTAssertEqual(post.comments.count, 1)
        XCTAssertEqual(post.comments[0].replies.count, 1)
    }
    
    func testCommunityGroup() {
        let group = CommunityGroup(name: "Runners", description: "Running club", creatorID: "user1", isPreset: true)
        XCTAssertEqual(group.name, "Runners")
        XCTAssertEqual(group.description, "Running club")
        XCTAssertEqual(group.creatorID, "user1")
        XCTAssertTrue(group.isPreset)
    }
    
    func testGroupMembership() {
        let membership = GroupMembership(groupID: "g1", userID: "u1")
        XCTAssertEqual(membership.groupID, "g1")
        XCTAssertEqual(membership.userID, "u1")
        XCTAssertNotNil(membership.joinedAt)
    }
    
    func testAchievementStatusEquality() {
        let status1 = UserAchievementStatus(achievementID: "a1", isUnlocked: true)
        let status2 = UserAchievementStatus(achievementID: "a1", isUnlocked: true)
        let status3 = UserAchievementStatus(achievementID: "a1", isUnlocked: false)
        
        XCTAssertEqual(status1, status2)
        XCTAssertNotEqual(status1, status3)
    }
}
