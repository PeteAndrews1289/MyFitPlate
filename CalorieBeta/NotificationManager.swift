import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import UIKit

enum NotificationType {
    case dailyLogReminder(hour: Int, minute: Int)
    case hydrationNudge
    case achievementNear(achievementName: String, progress: String)
    case encouragement
    case welcomeBack
    case healthTip
    case dailyBriefing 

    var id: String {
        switch self {
        case .dailyLogReminder: return "dailyLogReminder"
        case .hydrationNudge: return "hydrationNudge"
        case .achievementNear: return "achievementNear"
        case .encouragement: return "encouragement"
        case .welcomeBack: return "welcomeBack"
        case .healthTip: return "healthTip"
        case .dailyBriefing: return "dailyBriefing"
        }
    }

    var title: String {
        switch self {
        case .dailyLogReminder: return "🍽️ How's Your Day?"
        case .hydrationNudge: return "💧 Hydration Check!"
        case .achievementNear: return "🏆 Goal Within Reach!"
        case .encouragement: return "You've Got This!"
        case .welcomeBack: return "👋 We've Missed You!"
        case .healthTip: return "💡 Health Tip!"
        case .dailyBriefing: return "☀️ Your Daily Briefing"
        }
    }

    func body(remainingCalories: Int? = nil) -> String {
        switch self {
        case .dailyLogReminder:
            if let remaining = remainingCalories {
                return "Don't forget to log your meals! You have \(remaining) calories left for today."
            }
            return "Consistency is key. Don't forget to log your meals today to stay on track!"
        case .hydrationNudge:
            return "A glass of water could make all the difference right now."
        case .achievementNear(let name, let progress):
            return "You're \(progress) from unlocking the '\(name)' achievement! Let's go!"
        case .encouragement:
            return "Health is a journey, not a straight line. Let's get back on track today."
        case .welcomeBack:
            return "Your goals are waiting for you! Let's dive back in and build those healthy habits."
        case .healthTip:
            return "Did you know? Eating a variety of colorful foods helps ensure you get a wide range of vitamins."
        case .dailyBriefing:
            return "Here's your personalized tip to start the day strong!"
        }
    }
}

class NotificationManager {
    static let shared = NotificationManager()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func clearNotificationBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        UNUserNotificationCenter.current().requestAuthorization(options: options) { (success, error) in
            if let error = error {
                print("❌ Error requesting notification authorization: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    // NEW FUNCTION: Schedules the AI-powered daily briefing.
    func scheduleDailyBriefingNotification(insightsService: InsightsService) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        cancelNotification(identifier: NotificationType.dailyBriefing.id) // Cancel any existing briefing
        
        Task {
            if let briefing = await insightsService.generateDailyBriefing(for: userID) {
                let content = UNMutableNotificationContent()
                content.title = briefing.title
                content.body = briefing.body
                content.sound = .default
                content.badge = 1

                var dateComponents = DateComponents()
                dateComponents.hour = 8 // Schedule for 8:00 AM
                dateComponents.minute = 0
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: NotificationType.dailyBriefing.id, content: content, trigger: trigger)
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Error scheduling daily briefing: \(error.localizedDescription)")
                    } else {
                        print("✅ Daily briefing scheduled for 8:00 AM.")
                    }
                }
            }
        }
    }

    func scheduleCalendarNotification(_ type: NotificationType) {
        guard case .dailyLogReminder(let hour, let minute) = type else { return }
        
        cancelNotification(identifier: type.id)
        
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.sound = .default
        content.badge = 1

        if let userID = Auth.auth().currentUser?.uid {
            fetchUserData(userID: userID) { calorieGoal, caloriesConsumed in
                let remaining = max(0, calorieGoal - caloriesConsumed)
                content.body = type.body(remainingCalories: Int(remaining))
                
                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: type.id, content: content, trigger: trigger)
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Error scheduling calendar notification \(type.id): \(error.localizedDescription)")
                    } else {
                        print("✅ Calendar notification scheduled: \(type.id) for \(hour):\(minute)")
                    }
                }
            }
        }
    }
    
    func scheduleIntervalNotification(_ type: NotificationType, timeInterval: TimeInterval, repeats: Bool = false) {
        cancelNotification(identifier: type.id)
        
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.body()
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: repeats)
        let request = UNNotificationRequest(identifier: type.id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling interval notification \(type.id): \(error.localizedDescription)")
            } else {
                print("✅ Interval notification scheduled: \(type.id)")
            }
        }
    }

    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    private func fetchUserData(userID: String, completion: @escaping (Double, Double) -> Void) {
        db.collection("users").document(userID).getDocument { document, error in
            var calorieGoal: Double = 2000
            if let document = document, document.exists,
               let data = document.data(),
               let goals = data["goals"] as? [String: Any],
               let goalCalories = goals["calories"] as? Double {
                calorieGoal = goalCalories
            }

            let today = Calendar.current.startOfDay(for: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: today)
            
            self.db.collection("users").document(userID).collection("dailyLogs").document(dateString).getDocument { logDoc, logErr in
                var caloriesConsumed: Double = 0
                if let logDoc = logDoc, logDoc.exists, let data = logDoc.data(), let meals = data["meals"] as? [[String: Any]] {
                    for meal in meals {
                        if let foodItems = meal["foodItems"] as? [[String: Any]] {
                            for item in foodItems {
                                if let calories = item["calories"] as? Double {
                                    caloriesConsumed += calories
                                }
                            }
                        }
                    }
                }
                completion(calorieGoal, caloriesConsumed)
            }
        }
    }
}
