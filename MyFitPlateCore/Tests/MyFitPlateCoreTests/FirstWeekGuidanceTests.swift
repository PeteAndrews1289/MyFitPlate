import XCTest
@testable import MyFitPlateCore

final class AdaptiveTargetsOfferRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func offer(
        method: CalorieGoalMethod = .mifflinWithActivity,
        confidence: AdaptiveGoalService.DataConfidence = .high,
        actionable: Bool = true,
        tdee: Double? = 2_450,
        declinedAt: Date? = nil
    ) -> Bool {
        AdaptiveTargetsOfferRules.shouldOffer(
            method: method,
            confidence: confidence,
            isEstimateActionable: actionable,
            calculatedTDEE: tdee,
            lastDeclinedAt: declinedAt,
            now: now
        )
    }

    func testFormulaUsersWithAConfidentEstimateGetTheOffer() {
        XCTAssertTrue(offer())
        XCTAssertTrue(offer(confidence: .medium))
    }

    func testNoOfferWithoutAConfidentActionableEstimate() {
        XCTAssertFalse(offer(confidence: .low))
        XCTAssertFalse(offer(confidence: .insufficient))
        XCTAssertFalse(offer(actionable: false))
        XCTAssertFalse(offer(tdee: nil))
    }

    func testAdaptiveAndCustomTargetsAreLeftAlone() {
        XCTAssertFalse(offer(method: .dynamicTDEE), "adaptive users already get the weekly check-in")
        XCTAssertFalse(offer(method: .custom), "a hand-set target is a deliberate choice")
    }

    func testFormulaMaintenanceMatchesTheOnboardingPlan() {
        let settings = GoalSettings()
        settings.age = 30
        settings.weight = 200
        settings.height = 180
        settings.gender = "Male"
        settings.activityLevel = 1.55

        // The same inputs as the onboarding loss plan: BMR 1,887.18 x 1.55 activity.
        XCTAssertEqual(settings.formulaMaintenanceCalories, 2_925.14, accuracy: 0.05)
    }

    func testDecliningSnoozesForTwoWeeks() {
        XCTAssertFalse(offer(declinedAt: now.addingTimeInterval(-13 * 24 * 60 * 60)))
        XCTAssertTrue(offer(declinedAt: now.addingTimeInterval(-15 * 24 * 60 * 60)))
    }
}

final class SetupChecklistRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var fresh: SetupChecklistState {
        SetupChecklistState(
            hasLoggedFood: false,
            reminderResolved: false,
            healthResolved: false,
            healthAvailable: true,
            hasCompletedWorkout: false
        )
    }

    func testTheReminderIsOfferedRightAfterTheFirstMeal() {
        var state = fresh
        XCTAssertEqual(SetupChecklistRules.nextItem(for: state), .firstMeal)

        state.hasLoggedFood = true
        XCTAssertEqual(SetupChecklistRules.nextItem(for: state), .dailyReminder)

        state.reminderResolved = true
        XCTAssertEqual(SetupChecklistRules.nextItem(for: state), .appleHealth)

        state.healthResolved = true
        XCTAssertEqual(SetupChecklistRules.nextItem(for: state), .firstWorkout)
        XCTAssertEqual(SetupChecklistRules.completedCount(for: state), 3)
    }

    func testAppleHealthIsHiddenWhereItIsUnavailable() {
        var state = fresh
        state.healthAvailable = false
        XCTAssertFalse(SetupChecklistRules.items(for: state).contains(.appleHealth))
    }

    func testShownOnlyForNewUndismissedIncompleteSetups() {
        let recent = now.addingTimeInterval(-2 * 24 * 60 * 60)
        XCTAssertTrue(SetupChecklistRules.shouldShow(state: fresh, onboardingCompletedAt: recent, dismissedAt: nil, now: now))

        XCTAssertFalse(
            SetupChecklistRules.shouldShow(state: fresh, onboardingCompletedAt: nil, dismissedAt: nil, now: now),
            "accounts that onboarded before the checklist existed never see it"
        )
        XCTAssertFalse(SetupChecklistRules.shouldShow(state: fresh, onboardingCompletedAt: recent, dismissedAt: now, now: now))
        XCTAssertFalse(SetupChecklistRules.shouldShow(
            state: fresh,
            onboardingCompletedAt: now.addingTimeInterval(-22 * 24 * 60 * 60),
            dismissedAt: nil,
            now: now
        ))

        let done = SetupChecklistState(
            hasLoggedFood: true,
            reminderResolved: true,
            healthResolved: true,
            healthAvailable: true,
            hasCompletedWorkout: true
        )
        XCTAssertFalse(SetupChecklistRules.shouldShow(state: done, onboardingCompletedAt: recent, dismissedAt: nil, now: now))
    }
}

final class FirstWeekGuidanceStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "first-week-guidance-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDismissalsAreScopedToTheAccount() {
        let store = FirstWeekGuidanceStore(userDefaults: defaults)
        let moment = Date(timeIntervalSince1970: 1_790_000_000)

        store.dismissChecklist(userID: "user-a", now: moment)
        store.declineAdaptiveOffer(userID: "user-a", now: moment)

        XCTAssertEqual(store.checklistDismissedAt(userID: "user-a"), moment)
        XCTAssertEqual(store.adaptiveOfferDeclinedAt(userID: "user-a"), moment)
        XCTAssertNil(store.checklistDismissedAt(userID: "user-b"))
        XCTAssertNil(store.adaptiveOfferDeclinedAt(userID: "user-b"))
        XCTAssertNil(store.checklistDismissedAt(userID: nil))
    }

    @MainActor
    func testActivationFunnelExposesWhatItRecorded() {
        let eventName = ActivationFunnel.firstFoodLogged
        XCTAssertFalse(ActivationFunnel.hasLogged(eventName, userDefaults: defaults))
        XCTAssertNil(ActivationFunnel.onboardingCompletedAt(userDefaults: defaults))

        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted, now: moment, userDefaults: defaults)
        ActivationFunnel.logOnce(eventName, now: moment, userDefaults: defaults)

        XCTAssertTrue(ActivationFunnel.hasLogged(eventName, userDefaults: defaults))
        XCTAssertEqual(ActivationFunnel.onboardingCompletedAt(userDefaults: defaults), moment)
    }
}
