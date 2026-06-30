import XCTest
@testable import MyFitPlateCore

final class NotificationManagerTests: XCTestCase {
    
    func testNotificationTypeProperties() {
        let types: [NotificationType] = [
            .dailyLogReminder(hour: 20, minute: 0),
            .hydrationNudge,
            .achievementNear(achievementName: "First Log", progress: "1 more"),
            .encouragement,
            .welcomeBack,
            .healthTip,
            .dailyBriefing,
            .weighInReminder
        ]
        
        for type in types {
            XCTAssertFalse(type.id.isEmpty)
            XCTAssertFalse(type.title.isEmpty)
            
            // body
            if case .dailyLogReminder = type {
                XCTAssertFalse(type.body(remainingCalories: 500).isEmpty)
                XCTAssertFalse(type.body(remainingCalories: nil).isEmpty)
            } else {
                XCTAssertFalse(type.body().isEmpty)
            }
        }
        
        // Explicit tests for values to hit the switch statements
        let logReminder = NotificationType.dailyLogReminder(hour: 20, minute: 0)
        XCTAssertEqual(logReminder.id, "dailyLogReminder")
        XCTAssertEqual(logReminder.title, "🍽️ How's Your Day?")
        XCTAssertTrue(logReminder.body(remainingCalories: 500).contains("500 calories left"))
        XCTAssertTrue(logReminder.body(remainingCalories: nil).contains("Consistency is key"))
        
        let hydration = NotificationType.hydrationNudge
        XCTAssertEqual(hydration.id, "hydrationNudge")
        XCTAssertEqual(hydration.title, "💧 Hydration Check!")
        XCTAssertTrue(hydration.body().contains("glass of water"))
        
        let achievement = NotificationType.achievementNear(achievementName: "Test", progress: "90%")
        XCTAssertEqual(achievement.id, "achievementNear")
        XCTAssertEqual(achievement.title, "🏆 Goal Within Reach!")
        XCTAssertTrue(achievement.body().contains("Test"))
        XCTAssertTrue(achievement.body().contains("90%"))
        
        let encourage = NotificationType.encouragement
        XCTAssertEqual(encourage.id, "encouragement")
        XCTAssertEqual(encourage.title, "You've Got This!")
        
        let welcome = NotificationType.welcomeBack
        XCTAssertEqual(welcome.id, "welcomeBack")
        XCTAssertEqual(welcome.title, "👋 We've Missed You!")
        
        let health = NotificationType.healthTip
        XCTAssertEqual(health.id, "healthTip")
        XCTAssertEqual(health.title, "💡 Health Tip!")
        
        let brief = NotificationType.dailyBriefing
        XCTAssertEqual(brief.id, "dailyBriefing")
        XCTAssertEqual(brief.title, "☀️ Your Daily Briefing")
        
        let weigh = NotificationType.weighInReminder
        XCTAssertEqual(weigh.id, "weighInReminder")
        XCTAssertEqual(weigh.title, "⚖️ Time to Weigh In")
    }
}
