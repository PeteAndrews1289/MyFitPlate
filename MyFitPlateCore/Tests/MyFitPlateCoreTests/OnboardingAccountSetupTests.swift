import XCTest
@testable import MyFitPlateCore

final class OnboardingProfileRulesTests: XCTestCase {
    func testCompleteDraftHasNoValidationIssue() {
        XCTAssertNil(OnboardingProfileRules.validationIssue(for: .sampleLoss))
        XCTAssertTrue(OnboardingProfileDraft.sampleLoss.isComplete)
    }

    func testAgeHeightAndWeightBoundsAreEnforced() {
        var draft = OnboardingProfileDraft.sampleLoss
        draft.age = 12
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .age)

        draft = .sampleLoss
        draft.heightCm = 60
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .height)

        draft = .sampleLoss
        draft.currentWeightLbs = 20
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .currentWeight)

        draft = .sampleLoss
        draft.targetWeightLbs = 900
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .targetWeight)
    }

    func testTargetMustMoveInTheGoalDirection() {
        var draft = OnboardingProfileDraft.sampleLoss
        draft.targetWeightLbs = 210
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .targetDirection(.lose))

        draft.goal = .gain
        XCTAssertNil(OnboardingProfileRules.validationIssue(for: draft))

        draft.targetWeightLbs = 190
        XCTAssertEqual(OnboardingProfileRules.validationIssue(for: draft), .targetDirection(.gain))

        draft.goal = .maintain
        XCTAssertNil(OnboardingProfileRules.validationIssue(for: draft))
    }
}

final class OnboardingPlanRulesTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    func testLossPlanUsesTheSameFormulaAsGoalSettings() {
        let plan = OnboardingPlanRules.plan(for: .sampleLoss, today: today, calendar: calendar)

        // 200 lb, 180 cm, 30-year-old male: BMR 1,887.18 x 1.55 activity - 250.
        XCTAssertEqual(plan.maintenanceCalories, 2_925.14, accuracy: 0.05)
        XCTAssertEqual(plan.dailyCalories, 2_675.14, accuracy: 0.05)
        XCTAssertEqual(plan.proteinGrams, 200.64, accuracy: 0.05)
        XCTAssertEqual(plan.carbsGrams, 334.39, accuracy: 0.05)
        XCTAssertEqual(plan.fatGrams, 59.45, accuracy: 0.05)
        XCTAssertEqual(plan.weeklyChangeLbs, -0.5, accuracy: 0.0001)
        XCTAssertFalse(plan.isMinimumCalorieFloorApplied)
    }

    func testReachableTargetGetsAnEstimatedDate() throws {
        let plan = OnboardingPlanRules.plan(for: .sampleLoss, today: today, calendar: calendar)
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 280, to: today))

        XCTAssertEqual(plan.projection, .reachTarget(date: expected, weeks: 40))
    }

    func testLongJourneyUsesATwelveWeekMilestone() throws {
        var draft = OnboardingProfileDraft.sampleLoss
        draft.targetWeightLbs = 140
        let plan = OnboardingPlanRules.plan(for: draft, today: today, calendar: calendar)
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 84, to: today))

        guard case let .milestone(date, weeks, change) = plan.projection else {
            return XCTFail("Expected a milestone, got \(plan.projection)")
        }
        XCTAssertEqual(date, expected)
        XCTAssertEqual(weeks, 12)
        XCTAssertEqual(change, -6, accuracy: 0.0001)
    }

    func testGainPlanMovesUpward() {
        let draft = OnboardingProfileDraft(
            goal: .gain,
            sex: "Male",
            age: 25,
            heightCm: 175,
            currentWeightLbs: 150,
            targetWeightLbs: 160,
            activityMultiplier: 1.725
        )
        let plan = OnboardingPlanRules.plan(for: draft, today: today, calendar: calendar)

        XCTAssertEqual(plan.weeklyChangeLbs, 0.5, accuracy: 0.0001)
        guard case let .reachTarget(_, weeks) = plan.projection else {
            return XCTFail("Expected a target date, got \(plan.projection)")
        }
        XCTAssertEqual(weeks, 20)
    }

    func testMaintainAndAlreadyAtTargetDoNotInventADate() {
        var draft = OnboardingProfileDraft.sampleLoss
        draft.goal = .maintain
        draft.targetWeightLbs = draft.currentWeightLbs
        XCTAssertEqual(OnboardingPlanRules.plan(for: draft).projection, .maintain)

        draft.goal = .lose
        draft.targetWeightLbs = draft.currentWeightLbs - 0.5
        XCTAssertEqual(OnboardingPlanRules.plan(for: draft).projection, .atTarget)
    }

    func testCalorieFloorWithoutADeficitGivesNoEstimate() {
        let draft = OnboardingProfileDraft(
            goal: .lose,
            sex: "Female",
            age: 60,
            heightCm: 150,
            currentWeightLbs: 110,
            targetWeightLbs: 105,
            activityMultiplier: 1.2
        )
        let plan = OnboardingPlanRules.plan(for: draft)

        XCTAssertEqual(plan.dailyCalories, 1_200, accuracy: 0.001)
        XCTAssertTrue(plan.isMinimumCalorieFloorApplied)
        XCTAssertEqual(plan.projection, .noEstimate)
    }
}

final class AccountSetupRulesTests: XCTestCase {
    private let onboarded: [String: Any] = ["isFirstLogin": false]
    private let unfinished: [String: Any] = ["isFirstLogin": true]

    private func pending(userID: String = "user-1", isNewUser: Bool) -> PendingAccountSetup {
        PendingAccountSetup(userID: userID, isNewUser: isNewUser, method: .apple, email: nil, displayName: nil)
    }

    func testBrandNewAccountCreatesProfileBeforeApplyingTheDraft() {
        XCTAssertEqual(
            AccountSetupRules.action(profile: nil, currentUserID: "user-1", pendingAccount: pending(isNewUser: true), hasDraft: true),
            .createProfileThenApplyDraft
        )
        XCTAssertEqual(
            AccountSetupRules.action(profile: nil, currentUserID: "user-1", pendingAccount: pending(isNewUser: true), hasDraft: false),
            .createProfileThenShowSurvey
        )
    }

    func testMissingProfileThatIsNotKnownNewNeverCreatesOrAppliesAnything() {
        XCTAssertEqual(
            AccountSetupRules.action(profile: nil, currentUserID: "user-1", pendingAccount: pending(isNewUser: false), hasDraft: true),
            .showSurvey
        )
        XCTAssertEqual(
            AccountSetupRules.action(profile: nil, currentUserID: "user-1", pendingAccount: pending(userID: "someone-else", isNewUser: true), hasDraft: true),
            .showSurvey
        )
        XCTAssertEqual(
            AccountSetupRules.action(profile: nil, currentUserID: "user-1", pendingAccount: nil, hasDraft: true),
            .showSurvey
        )
    }

    func testUnfinishedProfileReceivesTheDraftOrTheSurvey() {
        XCTAssertEqual(
            AccountSetupRules.action(profile: unfinished, currentUserID: "user-1", pendingAccount: nil, hasDraft: true),
            .applyDraft
        )
        XCTAssertEqual(
            AccountSetupRules.action(profile: unfinished, currentUserID: "user-1", pendingAccount: nil, hasDraft: false),
            .showSurvey
        )
    }

    func testFinishedProfileIsNeverOverwrittenByADeviceDraft() {
        XCTAssertEqual(
            AccountSetupRules.action(profile: onboarded, currentUserID: "user-1", pendingAccount: pending(isNewUser: false), hasDraft: true),
            .discardDraft
        )
        XCTAssertEqual(
            AccountSetupRules.action(profile: onboarded, currentUserID: "user-1", pendingAccount: nil, hasDraft: false),
            .none
        )
    }
}

final class OnboardingDraftStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: OnboardingDraftStore!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingDraftStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = OnboardingDraftStore(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDraftAndPendingAccountRoundTrip() {
        let draft = OnboardingProfileDraft.sampleLoss
        let pending = PendingAccountSetup(userID: "user-1", isNewUser: true, method: .email, email: "a@b.co", displayName: "Pete")

        store.saveDraft(draft)
        store.savePendingAccount(pending)

        XCTAssertEqual(store.loadDraft(now: draft.createdAt), draft)
        XCTAssertEqual(store.loadPendingAccount(), pending)

        store.clearAll()
        XCTAssertNil(store.loadDraft(now: draft.createdAt))
        XCTAssertNil(store.loadPendingAccount())
    }

    func testExpiredDraftIsDiscarded() {
        let draft = OnboardingProfileDraft.sampleLoss
        store.saveDraft(draft)

        let later = draft.createdAt.addingTimeInterval(OnboardingDraftStore.draftLifetime + 1)
        XCTAssertNil(store.loadDraft(now: later))
        XCTAssertNil(store.loadDraft(now: draft.createdAt), "an expired draft is removed, not just hidden")
    }

    func testInvalidDraftIsDiscarded() {
        var draft = OnboardingProfileDraft.sampleLoss
        draft.age = 9
        store.saveDraft(draft)

        XCTAssertNil(store.loadDraft(now: draft.createdAt))
    }
}

@MainActor
final class AccountSetupCoordinatorTests: XCTestCase {
    func testFinishingAuthenticationRecordsTheNewAccountAndReleasesTheRoot() throws {
        let suiteName = "AccountSetupCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = AccountSetupCoordinator(store: OnboardingDraftStore(userDefaults: defaults))

        coordinator.beginAuthentication()
        XCTAssertTrue(coordinator.isAuthenticationInFlight)

        coordinator.finishAuthentication(
            session: AuthUserSession(userID: "user-1", email: "relay@privaterelay.appleid.com", isNewUser: true),
            method: .apple,
            displayName: "Pete"
        )

        XCTAssertFalse(coordinator.isAuthenticationInFlight)
        let pending = try XCTUnwrap(coordinator.store.loadPendingAccount())
        XCTAssertEqual(pending.userID, "user-1")
        XCTAssertTrue(pending.isNewUser)
        XCTAssertEqual(pending.method, .apple)
        XCTAssertEqual(pending.displayName, "Pete")
    }

    func testCancellingAuthenticationRecordsNothing() throws {
        let suiteName = "AccountSetupCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = AccountSetupCoordinator(store: OnboardingDraftStore(userDefaults: defaults))

        coordinator.beginAuthentication()
        coordinator.cancelAuthentication()

        XCTAssertFalse(coordinator.isAuthenticationInFlight)
        XCTAssertNil(coordinator.store.loadPendingAccount())
    }
}

final class BoundedOperationTests: XCTestCase {
    func testFastOperationReturnsItsValue() async throws {
        let value = try await BoundedOperation.run(seconds: 2) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testSlowOperationStopsWaitingAtTheLimit() async {
        let started = Date()
        do {
            _ = try await BoundedOperation.run(seconds: 0.1) {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return 1
            }
            XCTFail("Expected a timeout")
        } catch is BoundedOperation.TimedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testOperationErrorsPassThrough() async {
        do {
            _ = try await BoundedOperation.run(seconds: 2) { () -> Int in throw AuthServiceError.networkUnavailable }
            XCTFail("Expected the operation error")
        } catch AuthServiceError.networkUnavailable {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

final class AppleSignInSupportTests: XCTestCase {
    func testNonceUsesTheExpectedLengthAndCharacterSet() {
        let nonce = AppleSignInNonce.random()
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(nonce.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertNotEqual(nonce, AppleSignInNonce.random())
    }

    func testSHA256MatchesTheStandardTestVector() {
        XCTAssertEqual(
            AppleSignInNonce.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testDisplayNamePrefersTheTrimmedFirstName() {
        XCTAssertEqual(AppleSignInNames.displayName(givenName: "  Pete ", familyName: "Andrews"), "Pete")
        XCTAssertEqual(AppleSignInNames.displayName(givenName: nil, familyName: "Andrews"), "Andrews")
        XCTAssertNil(AppleSignInNames.displayName(givenName: " ", familyName: nil))
    }

    func testSignInMethodSurvivesTheAnalyticsPrivacyFilter() {
        let parameters = ProductAnalytics.firebaseParameters([
            "method": AccountSignInMethod.apple.rawValue,
            "apple_token": "revoked"
        ])
        XCTAssertEqual(parameters["method"] as? String, "apple")
        XCTAssertEqual(parameters["apple_token"] as? String, "revoked")
    }
}

final class OnboardingCompletionTests: XCTestCase {
    @MainActor
    func testCompletingOnboardingSavesTheRevealedPlanAndFirstWeighIn() async throws {
        let originalRepository = DIContainer.shared.settingsRepository
        defer { DIContainer.shared.settingsRepository = originalRepository }
        let repository = MockSettingsRepository()
        DIContainer.shared.settingsRepository = repository
        let settings = GoalSettings(healthKitManager: MockCoreHealthKitManager())
        let draft = OnboardingProfileDraft.sampleLoss
        let plan = OnboardingPlanRules.plan(for: draft)

        try await settings.completeOnboarding(with: draft, userID: "new-user")

        let saved = try XCTUnwrap(repository.savedUserGoals)
        let goals = try XCTUnwrap(saved["goals"] as? [String: Any])
        XCTAssertEqual(saved["isFirstLogin"] as? Bool, false)
        XCTAssertEqual(saved["age"] as? Int, 30)
        XCTAssertEqual(saved["weight"] as? Double, 200)
        XCTAssertEqual(saved["goal"] as? String, "Lose")
        XCTAssertEqual(goals["targetWeight"] as? Double, 180)
        XCTAssertEqual(goals["trainingIntent"] as? String, "Strength")
        XCTAssertEqual(try XCTUnwrap(goals["calories"] as? Double), plan.dailyCalories, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(settings.calories), plan.dailyCalories, accuracy: 0.01)
        XCTAssertEqual(settings.protein, plan.proteinGrams, accuracy: 0.01)
        XCTAssertEqual(repository.savedWeightEntries.map(\.userID), ["new-user"])
        XCTAssertEqual(repository.savedWeightEntries.map(\.weight), [200])
    }

    @MainActor
    func testProfileWriteFailureIsSurfaced() async {
        let originalRepository = DIContainer.shared.settingsRepository
        defer { DIContainer.shared.settingsRepository = originalRepository }
        let repository = MockSettingsRepository()
        repository.saveUserGoalsError = AuthServiceError.networkUnavailable
        DIContainer.shared.settingsRepository = repository
        let settings = GoalSettings(healthKitManager: MockCoreHealthKitManager())

        do {
            try await settings.completeOnboarding(with: OnboardingProfileDraft.sampleLoss, userID: "new-user")
            XCTFail("Expected the write failure")
        } catch {
            XCTAssertTrue(repository.savedWeightEntries.isEmpty, "no weigh-in is recorded for a profile that failed to save")
        }
    }
}

private extension OnboardingProfileDraft {
    static let sampleLoss = OnboardingProfileDraft(
        goal: .lose,
        trainingIntent: "Strength",
        sex: "Male",
        age: 30,
        heightCm: 180,
        currentWeightLbs: 200,
        targetWeightLbs: 180,
        activityMultiplier: 1.55,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000)
    )
}
