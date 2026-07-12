import UserNotifications
public enum NotificationType: Sendable {
    case dailyLogReminder(hour: Int, minute: Int)
    case hydrationNudge
    case achievementNear(achievementName: String, progress: String)
    case encouragement
    case welcomeBack
    case healthTip
    case dailyBriefing
    case weighInReminder

    public var id: String {
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

    public var title: String {
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

    public func body(remainingCalories: Int? = nil) -> String {
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

public class NotificationManager {
    public static let shared = NotificationManager()

    private let center: UserNotificationScheduling
    private let defaults: UserDefaults
    /// The XCTest guard below only protects the REAL center (app-target test runs must not
    /// mutate the device's pending notifications). Injected fakes are exactly for tests.
    private let isSystemCenter: Bool
    private let trainingFuelLedgerKey = "trainingFuelNotificationLedger.v1"
    private let trainingFuelLedgerLock = NSLock()
    private var trainingFuelSyncGeneration = 0

    public init(center: UserNotificationScheduling = SystemUserNotificationCenter(),
                defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        self.isSystemCenter = center is SystemUserNotificationCenter
    }

    public func clearNotificationBadge() {
        center.setBadgeCount(0)
    }

    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.authorizationStatus { status in
            switch status {
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
                self.center.requestAuthorization(options: options) { success, error in
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

    public func requestDailyLogReminderAuthorization() {
        requestAuthorization { granted in
            guard granted else { return }
            let hour = self.defaults.object(forKey: "notificationHour") as? Int ?? 20
            let minute = self.defaults.object(forKey: "notificationMinute") as? Int ?? 0
            self.scheduleCalendarNotification(.dailyLogReminder(hour: hour, minute: minute))
        }
    }

    public func scheduleDailyLogReminderIfAuthorized() {
        if isSystemCenter && NSClassFromString("XCTest") != nil { return }
        center.authorizationStatus { status in
            switch status {
            case .authorized, .provisional, .ephemeral:
                let hour = self.defaults.object(forKey: "notificationHour") as? Int ?? 20
                let minute = self.defaults.object(forKey: "notificationMinute") as? Int ?? 0
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
    public func setHydrationReminders(enabled: Bool) {
        let ids = hydrationHours.indices.map { "hydration_\($0)" }
        center.removePendingRequests(withIdentifiers: ids)
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
                self.center.add(request) { error in
                    if let error {
                        AppLog.notifications.error("Error scheduling hydration reminder: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    /// Enables or disables a repeating morning weigh-in reminder.
    public func setWeighInReminder(enabled: Bool, hour: Int = 7, minute: Int = 30) {
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
            self.center.add(request) { error in
                if let error {
                    AppLog.notifications.error("Error scheduling weigh-in reminder: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    public func syncTrainingFuelNotifications(
        preferences: TrainingFuelNotificationPreferences,
        plan: TrainingFuelConfirmedPlan?,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        if isSystemCenter && NSClassFromString("XCTest") != nil { return }
        let generation = beginTrainingFuelSync()
        // Remove the retired AI-generated engagement nudge from older app versions.
        center.removePendingRequests(withIdentifiers: ["smart_ai_nudge"])

        let candidates = TrainingFuelNotificationRules.candidates(
            preferences: preferences,
            plan: plan,
            today: today,
            goals: goals,
            now: now,
            calendar: calendar
        )
        let allIDs = TrainingFuelNotificationCandidate.Kind.allCases.map(\.identifier)
        let candidateIDs = Set(candidates.map { $0.kind.identifier })
        let removedIDs = allIDs.filter { !candidateIDs.contains($0) }
        if !removedIDs.isEmpty {
            center.removePendingRequests(withIdentifiers: removedIDs)
            removeTrainingFuelLedgerEntries(identifiers: removedIDs)
        }
        guard preferences.hasAnyEnabled, !candidates.isEmpty else { return }

        center.authorizationStatus { status in
            let scheduleCurrentCandidates = {
                guard self.isCurrentTrainingFuelSync(generation),
                      status == .authorized || status == .provisional else { return }
                for candidate in candidates {
                    self.scheduleTrainingFuelCandidate(
                        candidate,
                        calendar: calendar,
                        generation: generation
                    )
                }
            }
            if Thread.isMainThread {
                scheduleCurrentCandidates()
            } else {
                DispatchQueue.main.async(execute: scheduleCurrentCandidates)
            }
        }
    }
    
    /// NOT WIRED UP yet (no caller). When it is: `wellnessScoreSummary` and `todaysWorkout`
    /// MUST be real (from HealthKitViewModel + WorkoutService), never placeholders — see the
    /// landmine note on generateDailyBriefing.
    public func scheduleDailyBriefingNotification(insightsService: InsightsService, wellnessScoreSummary: String, todaysWorkout: String) {
        Task { @MainActor in
            guard let userID = DIContainer.shared.authService.currentUserID else { return }

            self.cancelNotification(identifier: NotificationType.dailyBriefing.id) // Cancel any existing briefing

            if let briefing = await insightsService.generateDailyBriefing(for: userID, wellnessScoreSummary: wellnessScoreSummary, todaysWorkout: todaysWorkout) {
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

                self.center.add(request) { error in
                    if let error {
                        AppLog.notifications.error("Error scheduling daily briefing: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    public func scheduleCalendarNotification(_ type: NotificationType) {
        guard case .dailyLogReminder(let hour, let minute) = type else { return }
        
        cancelNotification(identifier: type.id)
        
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.sound = .default
        content.badge = 1

        Task { @MainActor in
            if let userID = DIContainer.shared.authService.currentUserID {
                fetchUserData(userID: userID) { calorieGoal, caloriesConsumed in
                    let remaining = max(0, calorieGoal - caloriesConsumed)
                    content.body = type.body(remainingCalories: Int(remaining))
                    
                    var dateComponents = DateComponents()
                    dateComponents.hour = hour
                    dateComponents.minute = minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(identifier: type.id, content: content, trigger: trigger)

                    self.center.add(request) { error in
                        if let error = error {
                            AppLog.notifications.error("Error scheduling calendar notification \(type.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        }
    }
    
    public func scheduleIntervalNotification(_ type: NotificationType, timeInterval: TimeInterval, repeats: Bool = false) {
        cancelNotification(identifier: type.id)
        
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.body()
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: repeats)
        let request = UNNotificationRequest(identifier: type.id, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                AppLog.notifications.error("Error scheduling interval notification \(type.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func cancelNotification(identifier: String) {
        center.removePendingRequests(withIdentifiers: [identifier])
    }

    public func cancelTrainingFuelNotifications() {
        invalidateTrainingFuelSync()
        let identifiers = TrainingFuelNotificationCandidate.Kind.allCases.map(\.identifier) + ["smart_ai_nudge"]
        center.removePendingRequests(withIdentifiers: identifiers)
        removeTrainingFuelLedgerEntries(identifiers: identifiers)
    }

    private func scheduleTrainingFuelCandidate(
        _ candidate: TrainingFuelNotificationCandidate,
        calendar: Calendar,
        generation: Int
    ) {
        let identifier = candidate.kind.identifier
        let fingerprint = [
            String(Int(candidate.fireDate.timeIntervalSince1970)),
            candidate.title,
            candidate.body,
            candidate.deepLink
        ].joined(separator: "|")
        guard claimTrainingFuelFingerprint(
            fingerprint,
            identifier: identifier,
            generation: generation
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        content.userInfo = [
            "deep_link": candidate.deepLink,
            "notification_type": candidate.kind.rawValue
        ]
        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: candidate.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                self.removeTrainingFuelLedgerEntries(identifiers: [identifier])
                AppLog.notifications.error("Error scheduling training fuel reminder: \(error.localizedDescription, privacy: .public)")
                return
            }
            Task { @MainActor in
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.trainingFuelNotificationScheduled.rawValue,
                    parameters: ["notification_type": candidate.kind.rawValue]
                )
            }
        }
    }

    private func beginTrainingFuelSync() -> Int {
        trainingFuelLedgerLock.lock()
        defer { trainingFuelLedgerLock.unlock() }
        trainingFuelSyncGeneration &+= 1
        return trainingFuelSyncGeneration
    }

    private func invalidateTrainingFuelSync() {
        trainingFuelLedgerLock.lock()
        defer { trainingFuelLedgerLock.unlock() }
        trainingFuelSyncGeneration &+= 1
    }

    private func isCurrentTrainingFuelSync(_ generation: Int) -> Bool {
        trainingFuelLedgerLock.lock()
        defer { trainingFuelLedgerLock.unlock() }
        return trainingFuelSyncGeneration == generation
    }

    private func claimTrainingFuelFingerprint(
        _ fingerprint: String,
        identifier: String,
        generation: Int
    ) -> Bool {
        trainingFuelLedgerLock.lock()
        defer { trainingFuelLedgerLock.unlock() }
        guard trainingFuelSyncGeneration == generation else { return false }
        var ledger = defaults.dictionary(forKey: trainingFuelLedgerKey) as? [String: String] ?? [:]
        guard ledger[identifier] != fingerprint else { return false }
        ledger[identifier] = fingerprint
        defaults.set(ledger, forKey: trainingFuelLedgerKey)
        return true
    }

    private func removeTrainingFuelLedgerEntries(identifiers: [String]) {
        trainingFuelLedgerLock.lock()
        defer { trainingFuelLedgerLock.unlock() }
        var ledger = defaults.dictionary(forKey: trainingFuelLedgerKey) as? [String: String] ?? [:]
        identifiers.forEach { ledger[$0] = nil }
        defaults.set(ledger, forKey: trainingFuelLedgerKey)
    }
    
    private func fetchUserData(userID: String, completion: @escaping (Double, Double) -> Void) {
        Task {
            var calorieGoal: Double = 2000
            
            // 1. Fetch Goal
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    DIContainer.shared.settingsRepository.fetchUserGoals(userID: userID) { data in
                        if let goals = data?["goals"] as? [String: Any],
                           let goalCalories = goals["calories"] as? Double {
                            calorieGoal = goalCalories
                        }
                        continuation.resume()
                    }
                }
            }
            
            // 2. Fetch Daily Log
            let today = Calendar.current.startOfDay(for: Date())
            
            var caloriesConsumed: Double = 0
            
            let result: Result<DailyLog, Error> = await withCheckedContinuation { continuation in
                Task { @MainActor in
                    DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: today) { res in
                        continuation.resume(returning: res)
                    }
                }
            }
            
            switch result {
            case .success(let log):
                caloriesConsumed = log.totalCalories()
            case .failure:
                break
            }
            
            DispatchQueue.main.async {
                completion(calorieGoal, caloriesConsumed)
            }
        }
    }
}
