import UserNotifications
import FirebaseAuth
import FirebaseFirestore

enum NotificationType {
    case dailyLogReminder(hour: Int, minute: Int)
    case hydrationNudge
    case achievementNear(achievementName: String, progress: String)
    case encouragement
    case welcomeBack
    case healthTip
    case dailyBriefing
    case weighInReminder

    var id: String {
        switch self {
        case .dailyLogReminder: return "dailyLogReminder"
        case .hydrationNudge: return "hydrationNudge"
        case .achievementNear: return "achievementNear"
        case .encouragement: return "encouragement"
        case .welcomeBack: return "welcomeBack"
        case .healthTip: return "healthTip"
        case .dailyBriefing: return "dailyBriefing"
        case .weighInReminder: return "weighInReminder"
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
        case .weighInReminder: return "⚖️ Time to Weigh In"
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
        case .weighInReminder:
            return "A quick morning weigh-in keeps your trend and adaptive targets accurate."
        }
    }
}

class NotificationManager {
    static let shared = NotificationManager()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func clearNotificationBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    completion(true)
                }
            case .denied:
                DispatchQueue.main.async {
                    completion(false)
                }
            case .notDetermined:
                let options: UNAuthorizationOptions = [.alert, .sound, .badge]
                center.requestAuthorization(options: options) { success, error in
                    if let error {
                        AppLog.notifications.error("Error requesting notification authorization: \(error.localizedDescription, privacy: .public)")
                    }
                    DispatchQueue.main.async {
                        completion(success)
                    }
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    func requestDailyLogReminderAuthorization() {
        requestAuthorization { granted in
            guard granted else { return }
            let hour = UserDefaults.standard.object(forKey: "notificationHour") as? Int ?? 20
            let minute = UserDefaults.standard.object(forKey: "notificationMinute") as? Int ?? 0
            self.scheduleCalendarNotification(.dailyLogReminder(hour: hour, minute: minute))
        }
    }

    func scheduleDailyLogReminderIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let hour = UserDefaults.standard.object(forKey: "notificationHour") as? Int ?? 20
                let minute = UserDefaults.standard.object(forKey: "notificationMinute") as? Int ?? 0
                self.scheduleCalendarNotification(.dailyLogReminder(hour: hour, minute: minute))
            case .denied, .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    private let hydrationHours = [10, 13, 16, 19]

    /// Enables or disables recurring hydration reminders spread through the day.
    func setHydrationReminders(enabled: Bool) {
        let ids = hydrationHours.indices.map { "hydration_\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }
        requestAuthorization { granted in
            guard granted else { return }
            for (index, hour) in self.hydrationHours.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = NotificationType.hydrationNudge.title
                content.body = NotificationType.hydrationNudge.body()
                content.sound = .default
                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: "hydration_\(index)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { error in
                    if let error {
                        AppLog.notifications.error("Error scheduling hydration reminder: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    /// Enables or disables a repeating morning weigh-in reminder.
    func setWeighInReminder(enabled: Bool, hour: Int = 7, minute: Int = 30) {
        cancelNotification(identifier: NotificationType.weighInReminder.id)
        guard enabled else { return }
        requestAuthorization { granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = NotificationType.weighInReminder.title
            content.body = NotificationType.weighInReminder.body()
            content.sound = .default
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: NotificationType.weighInReminder.id, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    AppLog.notifications.error("Error scheduling weigh-in reminder: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func scheduleSmartNudge(title: String, body: String, delayHours: Double) {
        // Cancel existing nudge to avoid stacking
        cancelNotification(identifier: "smart_ai_nudge")
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        // Schedule for X hours from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delayHours * 3600, repeats: false)
        let request = UNNotificationRequest(identifier: "smart_ai_nudge", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLog.notifications.error("Error scheduling smart nudge: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
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
                
                do {
                    try await UNUserNotificationCenter.current().add(request)
                } catch {
                    AppLog.notifications.error("Error scheduling daily briefing: \(error.localizedDescription, privacy: .public)")
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
                        AppLog.notifications.error("Error scheduling calendar notification \(type.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                AppLog.notifications.error("Error scheduling interval notification \(type.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
