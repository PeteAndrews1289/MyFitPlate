import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutAnalyticsServiceTests: XCTestCase {
    var service: WorkoutAnalyticsService!
    var mockRepo: MockWorkoutRepository!
    var mockAI: MockAIService!

    override func setUp() {
        super.setUp()
        service = WorkoutAnalyticsService()
        mockRepo = MockWorkoutRepository()
        mockAI = MockAIService()
        
        DIContainer.shared.workoutRepository = mockRepo
        DIContainer.shared.aiService = mockAI
        
        let mockAuth = MockAuthService()
        mockAuth.currentUserID = "user_123"
        DIContainer.shared.authService = mockAuth
    }

    override func tearDown() {
        service = nil
        mockRepo = nil
        mockAI = nil
        super.tearDown()
    }

    func testImmediateAnalyticsCalculatesVolumeAndStrengthInsights() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Barbell Bench Press",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 5, weight: 185),
                        CompletedSet(reps: 8, weight: 165)
                    ]
                ),
                completedExercise(
                    name: "Dumbbell Curl",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 10, weight: 30)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertEqual(analytics.totalVolume, 2_545, accuracy: 0.001)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Session Banked" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Barbell Bench Press Drove the Session" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.category == "Mindset" })
    }

    func testImmediateAnalyticsProducesCardioInsightWhenNoStrengthVolumeExists() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Rowing Machine",
                    type: .cardio,
                    sets: [
                        CompletedSet(reps: 0, weight: 0, distance: 2.5, durationInSeconds: 1_200)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertEqual(analytics.totalVolume, 0, accuracy: 0.001)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Conditioning Logged" })
        XCTAssertTrue(analytics.aiInsights.contains { $0.message.contains("20 minutes") })
    }

    func testImmediateAnalyticsRecommendsRecoveryForHighVolumeSession() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(
                    name: "Deadlift",
                    type: .strength,
                    sets: [
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315),
                        CompletedSet(reps: 5, weight: 315)
                    ]
                )
            ]
        )

        let analytics = service.generateImmediateSessionAnalytics(for: log)

        XCTAssertGreaterThanOrEqual(analytics.totalVolume, 10_000)
        XCTAssertTrue(analytics.aiInsights.contains { $0.title == "Recovery Has Leverage" })
    }

    func testMuscleSplitPrioritizesSpecificLegTermsBeforeGenericRaiseOrCurlTerms() {
        let service = WorkoutAnalyticsService()
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Standing Calf Raise", type: .strength, sets: [CompletedSet(reps: 12, weight: 90)]),
                completedExercise(name: "Leg Curl", type: .strength, sets: [CompletedSet(reps: 12, weight: 80)]),
                completedExercise(name: "Lateral Raise", type: .strength, sets: [CompletedSet(reps: 12, weight: 20)]),
                completedExercise(name: "Bench Press", type: .strength, sets: [CompletedSet(reps: 8, weight: 185)])
            ]
        )

        let split = service.calculateMuscleSplit(log: log)
        let byMuscle = Dictionary(uniqueKeysWithValues: split.map { ($0.muscleName, $0.setCount) })

        XCTAssertEqual(byMuscle["Legs"], 2)
        XCTAssertEqual(byMuscle["Shoulders"], 1)
        XCTAssertEqual(byMuscle["Chest"], 1)
    }

    func testWorkoutInsightDecodesWithFreshIdentifierAndPreservesPayload() throws {
        let data = Data("""
        {"title":"Progress","message":"Add five pounds next week.","category":"Performance"}
        """.utf8)

        let insight = try JSONDecoder().decode(WorkoutAnalysisInsight.self, from: data)

        XCTAssertFalse(insight.id.uuidString.isEmpty)
        XCTAssertEqual(insight.title, "Progress")
        XCTAssertEqual(insight.message, "Add five pounds next week.")
        XCTAssertEqual(insight.category, "Performance")
    }

    private func makeSessionLog(exercises: [CompletedExercise]) -> WorkoutSessionLog {
        WorkoutSessionLog(id: "session-1", date: Date(), routineID: "routine-1", completedExercises: exercises)
    }

    private func completedExercise(
        name: String,
        type: ExerciseType,
        sets: [CompletedSet]
    ) -> CompletedExercise {
        CompletedExercise(
            exerciseName: name,
            exercise: RoutineExercise(name: name, type: type, sets: []),
            sets: sets
        )
    }

    // MARK: - New Tests for Coverage

    func testCalculateAnalyticsAggregatesVolumeAndPersonalRecords() async {
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])
            ]
        )
        // Set mock to return the log when fetched by the service
        mockRepo.mockFetchSessionLogResult = .success(log)
        
        mockAI.mockResult = .success("""
        {"insights":[{"title":"Test AI","message":"Good job.","category":"Performance"}]}
        """)
        
        let dailyLog = DailyLog(id: "dl1", date: Date(), meals: [], totalCaloriesOverride: nil, waterTracker: nil, exercises: [
            LoggedExercise(id: "le1", name: "Squat", durationMinutes: 0, caloriesBurned: 0, date: Date(), source: "manual", workoutID: "w1", sessionID: "session-1")
        ])

        let analytics = await service.calculateAnalytics(for: [dailyLog], program: nil)

        XCTAssertEqual(analytics.totalVolume, 1000)
        XCTAssertEqual(analytics.personalRecords["Squat"], "200.0 lbs x 5 reps")
        XCTAssertEqual(analytics.aiInsights.first?.title, "Test AI")
    }

    func testGenerateInsightsForPastSession() async {
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Deadlift", type: .strength, sets: [CompletedSet(reps: 5, weight: 300)])
            ]
        )
        mockRepo.mockFetchSessionLogResult = .success(log)
        mockAI.mockResult = .success("""
        {"insights":[{"title":"Past Session","message":"Strong.","category":"Performance"}]}
        """)

        let insights = await service.generateInsightsForPastSession(sessionID: "session-1", workoutName: "Legs", userID: "u1")
        XCTAssertEqual(insights.first?.title, "Past Session")
    }

    func testGenerateAnalyticsForPastSession() async {
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Bench Press", type: .strength, sets: [CompletedSet(reps: 10, weight: 100)])
            ]
        )
        mockRepo.mockFetchSessionLogResult = .success(log)
        mockRepo.mockFetchHistoryResult = [log] // Mock history to trigger PR logic

        let analytics = await service.generateAnalyticsForPastSession(sessionID: "session-1", workoutName: "Chest", date: Date())
        XCTAssertEqual(analytics?.totalVolume, 1000)
    }

    func testGenerateAnalytics() async {
        let log = makeSessionLog(
            exercises: [
                completedExercise(name: "Pull Up", type: .strength, sets: [CompletedSet(reps: 10, weight: 0)])
            ]
        )
        mockRepo.mockFetchHistoryResult = [log]

        let analytics = await service.generateAnalytics(for: log, userID: "user_123")
        XCTAssertEqual(analytics.totalVolume, 0)
    }

    func testSaveInsights() async {
        let insight = WorkoutAnalysisInsight(title: "Save Test", message: "Saved.", category: "Mindset")
        await service.saveInsights([insight], forSessionID: "s1", userID: "user_123")

        XCTAssertEqual(mockRepo.savedInsights.count, 1)
        XCTAssertEqual(mockRepo.savedInsights.first?["title"] as? String, "Save Test")
    }

    func testFetchWorkoutHistory() async {
        let log = makeSessionLog(exercises: [])
        mockRepo.mockFetchHistoryResult = [log]

        let history = await service.fetchWorkoutHistory(userID: "user_123", limit: 10)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.id, "session-1")
    }

    func testFetchTrends() async {
        let log1 = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])])
        let log2 = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 210)])])
        
        mockRepo.mockFetchHistoryResult = [log1, log2]

        let trends = await service.fetchTrends(for: "Squat", userID: "user_123")
        XCTAssertEqual(trends.count, 2)
        XCTAssertEqual(trends.last?.value, 200) // Reversed because mock fetch result is not ordered
    }

    func testCompareAgainstPrevious() async {
        let currentLog = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])])
        let prevLog = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 180)])])
        
        mockRepo.mockFetchHistoryResult = [currentLog, prevLog]

        let comparison = await service.compareAgainstPrevious(currentLog: currentLog, userID: "user_123")
        XCTAssertNotNil(comparison)
        XCTAssertEqual(comparison?.volumeDiffPercent ?? 0.0, (1000.0 - 900.0) / 900.0, accuracy: 0.001)
    }
}
