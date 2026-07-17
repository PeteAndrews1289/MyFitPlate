import XCTest
import UserNotifications
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

/// NotificationManager itself was 9%-covered because UNUserNotificationCenter.current()
/// crashes outside an app bundle. These tests drive it through the UserNotificationScheduling
/// seam: what gets scheduled, when, with which identifiers, and what a disable removes.
final class NotificationManagerSchedulingTests: XCTestCase {

    private var center: FakeNotificationCenter!
    private var defaults: UserDefaults!
    private var manager: NotificationManager!

    override func setUp() {
        super.setUp()
        center = FakeNotificationCenter()
        defaults = UserDefaults(suiteName: "NotificationManagerSchedulingTests")!
        defaults.removePersistentDomain(forName: "NotificationManagerSchedulingTests")
        manager = NotificationManager(center: center, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "NotificationManagerSchedulingTests")
        super.tearDown()
    }

    // MARK: Authorization

    func testAuthorizedStatusCompletesTrueWithoutPrompting() {
        center.status = .authorized
        let done = expectation(description: "completion")
        manager.requestAuthorization { granted in
            XCTAssertTrue(granted)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(center.authorizationRequests.isEmpty, "Already-authorized users must not be re-prompted")
    }

    func testDeniedStatusCompletesFalseWithoutPrompting() {
        center.status = .denied
        let done = expectation(description: "completion")
        manager.requestAuthorization { granted in
            XCTAssertFalse(granted)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(center.authorizationRequests.isEmpty)
    }

    func testNotDeterminedStatusPromptsWithAlertSoundBadge() {
        center.status = .notDetermined
        center.grantOnRequest = true
        let done = expectation(description: "completion")
        manager.requestAuthorization { granted in
            XCTAssertTrue(granted)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(center.authorizationRequests.count, 1)
        XCTAssertEqual(center.authorizationRequests.first, [.alert, .sound, .badge])
    }

    // MARK: Hydration reminders

    func testEnablingHydrationSchedulesFourSpreadRepeatingReminders() {
        center.status = .authorized
        let added = expectation(description: "4 adds")
        added.expectedFulfillmentCount = 4
        center.onAdd = { _ in added.fulfill() }

        manager.setHydrationReminders(enabled: true)
        wait(for: [added], timeout: 2)

        XCTAssertEqual(center.removedIdentifierBatches.first, ["hydration_0", "hydration_1", "hydration_2", "hydration_3"],
                       "Old reminders are cleared before rescheduling")
        let triggers = center.addedRequests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.compactMap(\.dateComponents.hour).sorted(), [10, 13, 16, 19])
        XCTAssertTrue(triggers.allSatisfy(\.repeats))
        XCTAssertEqual(Set(center.addedRequests.map(\.identifier)).count, 4, "Each reminder needs a distinct identifier")
    }

    func testDisablingHydrationOnlyRemoves() {
        manager.setHydrationReminders(enabled: false)
        XCTAssertEqual(center.removedIdentifierBatches.count, 1)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    // MARK: Weigh-in reminder

    func testWeighInReminderSchedulesAtRequestedTime() throws {
        center.status = .authorized
        let added = expectation(description: "add")
        center.onAdd = { _ in added.fulfill() }

        manager.setWeighInReminder(enabled: true, hour: 6, minute: 45)
        wait(for: [added], timeout: 2)

        let request = try XCTUnwrap(center.addedRequests.first)
        XCTAssertEqual(request.identifier, "weighInReminder")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 6)
        XCTAssertEqual(trigger.dateComponents.minute, 45)
        XCTAssertTrue(trigger.repeats)
    }

    func testDisablingWeighInCancelsWithoutScheduling() {
        manager.setWeighInReminder(enabled: false)
        XCTAssertEqual(center.removedIdentifierBatches.first, ["weighInReminder"])
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    // MARK: Interval notifications

    func testIntervalNotificationCarriesTypeContent() throws {
        manager.scheduleIntervalNotification(.encouragement, timeInterval: 3600, repeats: false)

        let request = try XCTUnwrap(center.addedRequests.first)
        XCTAssertEqual(request.identifier, "encouragement")
        XCTAssertEqual(request.content.title, NotificationType.encouragement.title)
        XCTAssertEqual(request.content.body, NotificationType.encouragement.body())
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 3600, accuracy: 0.01)
    }

    // MARK: Daily log reminder (full content path through DI)

    @MainActor
    func testDailyLogReminderBodyUsesRemainingCalories() throws {
        let auth = MockAuthService()
        auth.currentUserID = "user1"
        DIContainer.shared.authService = auth

        let settings = MockSettingsRepository()
        settings.mockFetchUserGoalsResult = ["goals": ["calories": 2200.0]]
        DIContainer.shared.settingsRepository = settings

        var log = DailyLog(date: Date(), meals: [])
        let dinner = FoodItem(id: "f1", name: "Bowl", calories: 1400, protein: 80, carbs: 120, fats: 40)
        _ = DailyLogRules.addFoodToLog(log: &log, foodItem: dinner, mealName: "Dinner")
        let nutrition = MockNutritionRepository()
        nutrition.mockFetchLogResult = .success(log)
        DIContainer.shared.nutritionRepository = nutrition

        let added = expectation(description: "reminder scheduled")
        center.onAdd = { _ in added.fulfill() }

        manager.scheduleCalendarNotification(.dailyLogReminder(hour: 20, minute: 30))
        wait(for: [added], timeout: 3)

        let request = try XCTUnwrap(center.addedRequests.first)
        XCTAssertEqual(request.identifier, "dailyLogReminder")
        XCTAssertTrue(request.content.body.contains("800 calories"),
                      "Body should state the remaining budget (2,200 goal - 1,400 eaten). Got: \(request.content.body)")
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
    }

    func testNonReminderTypesAreIgnoredByCalendarScheduler() {
        manager.scheduleCalendarNotification(.hydrationNudge)
        XCTAssertTrue(center.addedRequests.isEmpty)
        XCTAssertTrue(center.removedIdentifierBatches.isEmpty)
    }

    // MARK: Stored reminder time

    @MainActor
    func testScheduleIfAuthorizedUsesStoredTime() throws {
        let auth = MockAuthService()
        auth.currentUserID = "user1"
        DIContainer.shared.authService = auth
        DIContainer.shared.settingsRepository = MockSettingsRepository()
        DIContainer.shared.nutritionRepository = MockNutritionRepository()

        defaults.set(21, forKey: "notificationHour")
        defaults.set(15, forKey: "notificationMinute")
        center.status = .authorized

        let added = expectation(description: "scheduled")
        center.onAdd = { _ in added.fulfill() }

        manager.scheduleDailyLogReminderIfAuthorized()
        wait(for: [added], timeout: 3)

        let trigger = try XCTUnwrap(center.addedRequests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 21)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
    }

    func testScheduleIfAuthorizedDoesNothingWhenDenied() {
        center.status = .denied
        manager.scheduleDailyLogReminderIfAuthorized()
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testClearBadgeZeroesTheCount() {
        manager.clearNotificationBadge()
        XCTAssertEqual(center.badgeCounts, [0])
    }

    func testTrainingFuelSyncSchedulesAtMostTwoAndDoesNotStackOnRefresh() throws {
        center.status = .authorized
        let now = utcDate(hour: 8)
        let preferences = TrainingFuelNotificationPreferences(
            preSessionEnabled: true,
            eveningCatchUpEnabled: true
        )
        let log = DailyLog(
            date: now,
            meals: [Meal(name: "Breakfast", foodItems: [FoodItem(name: "Meal", calories: 500, protein: 20)])]
        )
        let plan = notificationPlan(start: utcDate(hour: 12), confirmedAt: now)

        manager.syncTrainingFuelNotifications(
            preferences: preferences,
            plan: plan,
            today: log,
            goals: notificationGoals,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(center.addedRequests.count, 2)
        XCTAssertEqual(Set(center.addedRequests.map(\.identifier)).count, 2)
        XCTAssertTrue(center.addedRequests.allSatisfy { $0.content.userInfo["deep_link"] != nil })

        manager.syncTrainingFuelNotifications(
            preferences: preferences,
            plan: plan,
            today: log,
            goals: notificationGoals,
            now: now,
            calendar: utcCalendar
        )
        XCTAssertEqual(center.addedRequests.count, 2, "An unchanged refresh must not schedule duplicates")
    }

    func testNewerTrainingFuelSyncWinsWhenAuthorizationCallbacksReturnOutOfOrder() throws {
        center.status = .authorized
        center.defersAuthorizationStatus = true
        let now = utcDate(hour: 8)
        let preferences = TrainingFuelNotificationPreferences(preSessionEnabled: true)

        manager.syncTrainingFuelNotifications(
            preferences: preferences,
            plan: notificationPlan(start: utcDate(hour: 12), confirmedAt: now),
            today: nil,
            goals: notificationGoals,
            now: now,
            calendar: utcCalendar
        )
        manager.syncTrainingFuelNotifications(
            preferences: preferences,
            plan: notificationPlan(start: utcDate(hour: 14), confirmedAt: now),
            today: nil,
            goals: notificationGoals,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(center.deferredAuthorizationStatusCount, 2)
        center.resolveDeferredAuthorizationStatuses(newestFirst: true)

        let request = try XCTUnwrap(center.addedRequests.first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(trigger.dateComponents.hour, 12)
        XCTAssertEqual(trigger.dateComponents.minute, 45)
    }

    func testTrainingFuelDisableRemovesEveryTypeAndLegacyNudge() {
        center.status = .authorized
        manager.syncTrainingFuelNotifications(
            preferences: TrainingFuelNotificationPreferences(),
            plan: nil,
            today: nil,
            goals: notificationGoals
        )

        XCTAssertTrue(center.removedIdentifierBatches.contains(["smart_ai_nudge"]))
        XCTAssertTrue(center.removedIdentifierBatches.contains(
            TrainingFuelNotificationCandidate.Kind.allCases.map(\.identifier)
        ))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testCancelAccountNotificationsRemovesPersonalizedRequests() {
        manager.cancelAccountNotifications()

        let removed = Set(center.removedIdentifierBatches.flatMap { $0 })
        XCTAssertTrue(removed.contains("dailyLogReminder"))
        XCTAssertTrue(removed.contains("dailyBriefing"))
        XCTAssertTrue(removed.contains("smart_ai_nudge"))
        XCTAssertTrue(
            TrainingFuelNotificationCandidate.Kind.allCases.allSatisfy {
                removed.contains($0.identifier)
            }
        )
        XCTAssertFalse(removed.contains("weighInReminder"))
        XCTAssertFalse(removed.contains("hydration_0"))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var notificationGoals: TodayFuelPlanGoals {
        TodayFuelPlanGoals(calories: 2_000, protein: 120, carbs: 240, fats: 70)
    }

    private func utcDate(hour: Int, minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 11,
            hour: hour,
            minute: minute
        ))!
    }

    private func notificationPlan(start: Date, confirmedAt: Date) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(
            candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            scheduledAt: start,
            durationMinutes: 60,
            intensity: .hard,
            strengthFocus: .lowerBody,
            preference: TrainingFuelPreference()
        )
        let plannerPlan = TrainingFuelPlannerPlan(
            status: .ready,
            normalizedDurationMinutes: 60,
            normalizedIntensity: .hard,
            minutesUntilSession: 180,
            remainingCalories: 1_200,
            remainingProteinGrams: 100,
            remainingCarbGrams: 160,
            allocations: [
                TrainingFuelAllocation(phase: .beforeTraining, timing: .thirtyTo120Minutes, proteinGrams: 15, carbGrams: 35),
                TrainingFuelAllocation(phase: .afterTraining, timing: .afterSession, proteinGrams: 25, carbGrams: 45)
            ],
            notes: []
        )
        return TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: notificationGoals,
            today: DailyLog(date: start, meals: []),
            confirmedAt: confirmedAt
        )
    }
}

// MARK: - Fake center

private final class FakeNotificationCenter: UserNotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()

    var status: UNAuthorizationStatus = .notDetermined
    var grantOnRequest = true
    var onAdd: ((UNNotificationRequest) -> Void)?
    var defersAuthorizationStatus = false

    private var _authorizationRequests: [UNAuthorizationOptions] = []
    private var _authorizationStatusCompletions: [(UNAuthorizationStatus) -> Void] = []
    private var _addedRequests: [UNNotificationRequest] = []
    private var _removedIdentifierBatches: [[String]] = []
    private var _badgeCounts: [Int] = []

    var authorizationRequests: [UNAuthorizationOptions] { lock.withLock { _authorizationRequests } }
    var deferredAuthorizationStatusCount: Int { lock.withLock { _authorizationStatusCompletions.count } }
    var addedRequests: [UNNotificationRequest] { lock.withLock { _addedRequests } }
    var removedIdentifierBatches: [[String]] { lock.withLock { _removedIdentifierBatches } }
    var badgeCounts: [Int] { lock.withLock { _badgeCounts } }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        if defersAuthorizationStatus {
            lock.withLock { _authorizationStatusCompletions.append(completion) }
            return
        }
        completion(status)
    }

    func resolveDeferredAuthorizationStatuses(newestFirst: Bool) {
        let completions = lock.withLock {
            let callbacks = _authorizationStatusCompletions
            _authorizationStatusCompletions.removeAll()
            return newestFirst ? Array(callbacks.reversed()) : callbacks
        }
        completions.forEach { $0(status) }
    }

    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping (Bool, Error?) -> Void) {
        lock.withLock { _authorizationRequests.append(options) }
        completion(grantOnRequest, nil)
    }

    func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?) {
        lock.withLock { _addedRequests.append(request) }
        completion?(nil)
        onAdd?(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        lock.withLock { _removedIdentifierBatches.append(identifiers) }
    }

    func setBadgeCount(_ count: Int) {
        lock.withLock { _badgeCounts.append(count) }
    }
}
