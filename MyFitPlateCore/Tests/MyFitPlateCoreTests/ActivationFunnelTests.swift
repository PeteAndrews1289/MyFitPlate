import XCTest
@testable import MyFitPlateCore

@MainActor
final class ActivationFunnelTests: XCTestCase {
    private let suiteName = "activation-funnel-tests"
    private var defaults: UserDefaults!
    private var mockAnalytics: MockAnalyticsManager!
    private var mockAuth: MockAuthService!
    private var previousAnalytics: AnalyticsManagerProtocol?
    private var previousAuth: AuthServiceProtocol?

    override func setUp() {
        super.setUp()
        previousAnalytics = DIContainer.shared.analyticsManager
        previousAuth = DIContainer.shared.authService
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        mockAnalytics = MockAnalyticsManager()
        mockAuth = MockAuthService()
        mockAuth.currentUserID = "activation-owner"
        DIContainer.shared.analyticsManager = mockAnalytics
        DIContainer.shared.authService = mockAuth
    }

    override func tearDown() {
        DIContainer.shared.analyticsManager = previousAnalytics
        DIContainer.shared.authService = previousAuth
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAccountProgressRequiresSignedInOwnerWithoutChangingInstallAnalytics() {
        let event = ActivationFunnel.firstFoodLogged
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let progress = AccountProgressStore(defaults: defaults)
        mockAuth.currentUserID = nil
        ActivationFunnel.logOnce(event, now: firstDate, userDefaults: defaults)
        XCTAssertNil(progress.date(event, userID: "activation-owner"))

        mockAuth.currentUserID = "activation-owner"
        ActivationFunnel.logOnce(event, now: firstDate.addingTimeInterval(30), userDefaults: defaults)
        XCTAssertEqual(progress.date(event, userID: "activation-owner"), firstDate.addingTimeInterval(30))
        mockAuth.currentUserID = "another-owner"
        ActivationFunnel.logOnce(event, now: firstDate.addingTimeInterval(60), userDefaults: defaults)
        XCTAssertEqual(progress.date(event, userID: "another-owner"), firstDate.addingTimeInterval(60))
        XCTAssertEqual(progress.date(event, userID: "activation-owner"), firstDate.addingTimeInterval(30))
        XCTAssertEqual(mockAnalytics.loggedEvents.filter { $0.name == event }.count, 1)
    }

    func testLogOnceFiresExactlyOncePerInstall() {
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)

        let fired = mockAnalytics.loggedEvents.filter { $0.name == ActivationFunnel.firstFoodLogged }
        XCTAssertEqual(fired.count, 1)
    }

    func testDistinctEventsFireIndependently() {
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstWorkoutCompleted, userDefaults: defaults)

        XCTAssertEqual(mockAnalytics.loggedEvents.count, 2)
        XCTAssertEqual(
            Set(mockAnalytics.loggedEvents.map(\.name)),
            [ActivationFunnel.onboardingCompleted, ActivationFunnel.firstWorkoutCompleted]
        )
    }

    func testFirstValueEventsIncludeElapsedTimeFromOnboarding() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted, now: start, userDefaults: defaults)
        ActivationFunnel.logOnce(
            ActivationFunnel.firstFoodLogged,
            now: start.addingTimeInterval(95),
            userDefaults: defaults
        )

        let event = try XCTUnwrap(
            mockAnalytics.loggedEvents.first { $0.name == ActivationFunnel.firstFoodLogged }
        )
        XCTAssertEqual(event.parameters?["elapsed_seconds"] as? Int, 95)
    }

    func testNutritionTrainingLoopFiresOnceAfterBothMilestones() {
        ActivationFunnel.logOnce(ActivationFunnel.firstWorkoutCompleted, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstFoodLogged, userDefaults: defaults)
        ActivationFunnel.logOnce(ActivationFunnel.firstWorkoutCompleted, userDefaults: defaults)

        let loopEvents = mockAnalytics.loggedEvents.filter {
            $0.name == ActivationFunnel.nutritionTrainingLoopCompleted
        }
        XCTAssertEqual(loopEvents.count, 1)
    }

    func testTrainingCompletionIncludesRunsAndKeepsFirstMilestoneOneShot() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        ActivationFunnel.logOnce(ActivationFunnel.onboardingCompleted, now: start, userDefaults: defaults)
        ActivationFunnel.logOnce(
            ActivationFunnel.firstFoodLogged,
            now: start.addingTimeInterval(30),
            userDefaults: defaults
        )

        ActivationFunnel.recordTrainingCompletion(
            .recordedRun,
            now: start.addingTimeInterval(120),
            userDefaults: defaults
        )
        ActivationFunnel.recordTrainingCompletion(
            .treadmillRun,
            now: start.addingTimeInterval(240),
            userDefaults: defaults
        )

        let sessions = mockAnalytics.loggedEvents.filter {
            $0.name == ProductAnalytics.Event.trainingSessionCompleted.rawValue
        }
        let firstTraining = mockAnalytics.loggedEvents.filter {
            $0.name == ActivationFunnel.firstWorkoutCompleted
        }
        let loops = mockAnalytics.loggedEvents.filter {
            $0.name == ActivationFunnel.nutritionTrainingLoopCompleted
        }

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first?.parameters?["training_mode"] as? String, "recorded_run")
        XCTAssertEqual(sessions.last?.parameters?["training_mode"] as? String, "treadmill_run")
        XCTAssertEqual(firstTraining.count, 1)
        XCTAssertEqual(firstTraining.first?.parameters?["elapsed_seconds"] as? Int, 120)
        XCTAssertEqual(firstTraining.first?.parameters?["training_mode"] as? String, "recorded_run")
        XCTAssertEqual(loops.count, 1)
    }
}
