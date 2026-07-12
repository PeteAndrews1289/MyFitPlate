import XCTest
@testable import MyFitPlateCore

@MainActor
final class ActivationFunnelTests: XCTestCase {
    private let suiteName = "activation-funnel-tests"
    private var defaults: UserDefaults!
    private var mockAnalytics: MockAnalyticsManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        mockAnalytics = MockAnalyticsManager()
        DIContainer.shared.analyticsManager = mockAnalytics
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
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
