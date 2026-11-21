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
        var log1 = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])])
        var log2 = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 210)])])
        
        log1.id = "earlier-session"; log1.date = Date(timeIntervalSince1970: 1_700_000_000)
        log2.id = "later-session"; log2.date = Date(timeIntervalSince1970: 1_700_086_400)
        mockRepo.mockFetchHistoryResult = [log1, log2]

        let trends = await service.fetchTrends(for: "Squat", userID: "user_123")
        XCTAssertEqual(trends.count, 2)
        XCTAssertEqual(trends.first?.value, 200)
        XCTAssertEqual(trends.last?.value, 210) // Trends follow the actual session chronology.
    }

    func testCompareAgainstPrevious() async {
        let currentLog = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])])
        var prevLog = makeSessionLog(exercises: [completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 180)])])
        prevLog.id = "previous-session"
        prevLog.date = currentLog.date.addingTimeInterval(-86_400)
        
        mockRepo.mockFetchHistoryResult = [currentLog, prevLog]

        let comparison = await service.compareAgainstPrevious(currentLog: currentLog, userID: "user_123")
        XCTAssertNotNil(comparison)
        XCTAssertEqual(comparison?.volumeDiffPercent ?? 0.0, (1000.0 - 900.0) / 900.0, accuracy: 0.001)
    }

    func testConfirmedRecordsDoNotCrossLoadingMeaningsOrNamedMachines() async {
        let currentSetup = StrengthEquipment(loadingMeaning: .total, name: "Bench rack", availableWeights: [60, 100, 110])
        let current = equipmentLog(id: "current", date: Date(), setup: currentSetup, weight: 110)
        let oldSetups: [StrengthEquipment?] = [nil,
            StrengthEquipment(loadingMeaning: .perHand, name: "Bench rack", availableWeights: [60, 100]),
            StrengthEquipment(loadingMeaning: .added, name: "Bench rack", availableWeights: [60, 100]),
            StrengthEquipment(loadingMeaning: .total, name: "Different machine", availableWeights: [60, 100])]
        mockAI.mockResult = .success("{\"insights\":[]}")
        for (index, setup) in oldSetups.enumerated() {
            let previous = equipmentLog(id: "previous-\(index)", date: current.date.addingTimeInterval(-86_400), setup: setup, weight: 60)
            mockRepo.mockFetchHistoryResult = [current, previous]
            let result = await service.generateAnalytics(for: current, userID: "user_123")
            XCTAssertTrue(result.personalRecords.isEmpty, "A new load convention or machine starts a new comparison baseline")
            XCTAssertFalse(result.aiInsights.contains { $0.title == "Confirmed Progress" })
            XCTAssertEqual(result.totalVolume, 1100, "Keep the recorded canonical numbers unchanged")
        }
    }

    func testUnitOnlyChangeCanConfirmComparableProgressButFirstExposureCannot() async {
        let currentSetup = StrengthEquipment(unit: .kg, loadingMeaning: .total, name: "Bench rack", availableWeights: [100, 110])
        var oldSetup = currentSetup
        oldSetup.unit = .lb
        let current = equipmentLog(id: "current", date: Date(), setup: currentSetup, weight: 110)
        let previous = equipmentLog(id: "previous", date: current.date.addingTimeInterval(-86_400), setup: oldSetup, weight: 100)
        mockAI.mockResult = .success("{\"insights\":[]}")
        mockRepo.mockFetchHistoryResult = [current, previous]
        let confirmed = await service.generateAnalytics(for: current, userID: "user_123")
        XCTAssertNotNil(confirmed.personalRecords["Bench press"])
        let comparison = await service.compareAgainstPrevious(currentLog: current, userID: "user_123")
        XCTAssertEqual(comparison?.volumeDiffPercent ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertEqual(confirmed.totalVolume, 1100)
        mockRepo.mockFetchHistoryResult = [current]
        let firstExposure = await service.generateAnalytics(for: current, userID: "user_123")
        XCTAssertTrue(firstExposure.personalRecords.isEmpty)
    }

    func testSessionVolumeComparisonIsOmittedAcrossChangedMeaningOrMachine() async {
        let currentSetup = StrengthEquipment(loadingMeaning: .total, name: "Bench rack", availableWeights: [100, 110])
        let current = equipmentLog(id: "current", date: Date(), setup: currentSetup, weight: 110)
        let incompatible = [StrengthEquipment(loadingMeaning: .perHand, name: "Bench rack", availableWeights: [100, 110]),
                            StrengthEquipment(loadingMeaning: .total, name: "Other machine", availableWeights: [100, 110])]
        for setup in incompatible {
            let previous = equipmentLog(id: "previous", date: current.date.addingTimeInterval(-86_400), setup: setup, weight: 100)
            mockRepo.mockFetchHistoryResult = [current, previous]
            let comparison = await service.compareAgainstPrevious(currentLog: current, userID: "user_123")
            XCTAssertNil(comparison, "Incompatible load meanings cannot trigger a session-volume PR celebration")
            XCTAssertEqual(service.generateImmediateSessionAnalytics(for: current).totalVolume, 1100)
        }
    }

    func testAggregateRecordsOmitAmbiguousNamesWhileKeepingVolumeAndOtherRecords() async {
        let perHand = StrengthEquipment(loadingMeaning: .perHand, name: "Bench rack", availableWeights: [60, 110])
        let total = StrengthEquipment(loadingMeaning: .total, name: "Bench rack", availableWeights: [60, 110])
        var first = completedExercise(name: "Bench press", type: .strength, sets: [CompletedSet(reps: 10, weight: 60)])
        first.exercise.loadEquipment = perHand
        var second = completedExercise(name: " bench PRESS ", type: .strength, sets: [CompletedSet(reps: 10, weight: 110)])
        second.exercise.loadEquipment = total
        let squat = completedExercise(name: "Squat", type: .strength, sets: [CompletedSet(reps: 5, weight: 200)])
        let session = makeSessionLog(exercises: [first, second, squat])
        mockRepo.mockFetchSessionLogResult = .success(session)
        mockAI.mockResult = .success("{\"insights\":[]}")
        let result = await service.calculateAnalytics(for: [dailyLog(for: session)], program: nil)
        XCTAssertEqual(result.totalVolume, 2700)
        XCTAssertEqual(Set(result.personalRecords.keys), ["Squat"])
        XCTAssertEqual(result.personalRecords["Squat"], "200.0 lbs x 5 reps")
    }

    func testAggregateRecordStillCombinesCompatibleUnitPresentations() async {
        let firstSetup = StrengthEquipment(loadingMeaning: .total, name: "Bench rack", availableWeights: [100, 110])
        var secondSetup = firstSetup
        secondSetup.unit = .kg
        var first = completedExercise(name: "Bench press", type: .strength, sets: [CompletedSet(reps: 10, weight: 100)])
        first.exercise.loadEquipment = firstSetup
        var second = completedExercise(name: "Bench press", type: .strength, sets: [CompletedSet(reps: 10, weight: 110)])
        second.exercise.loadEquipment = secondSetup
        let session = makeSessionLog(exercises: [first, second])
        mockRepo.mockFetchSessionLogResult = .success(session)
        mockAI.mockResult = .success("{\"insights\":[]}")
        let result = await service.calculateAnalytics(for: [dailyLog(for: session)], program: nil)
        XCTAssertEqual(result.totalVolume, 2100)
        XCTAssertEqual(result.personalRecords["Bench press"], "110.0 lbs x 10 reps")
    }

    func testSameNameExercisesWithDifferentCurrentMeaningsCannotClaimOneConfirmedRecord() async {
        let total = StrengthEquipment(loadingMeaning: .total, availableWeights: [50, 60, 100, 110])
        var perHand = total
        perHand.loadingMeaning = .perHand
        let now = Date()
        let totalCurrent = equipmentLog(id: "current", date: now, setup: total, weight: 110)
        let handCurrent = equipmentLog(id: "current", date: now, setup: perHand, weight: 60)
        var current = totalCurrent
        current.completedExercises += handCurrent.completedExercises
        let previous = equipmentLog(id: "previous", date: now.addingTimeInterval(-86_400), setup: total, weight: 100)
        mockRepo.mockFetchHistoryResult = [current, previous]
        mockAI.mockResult = .success("{\"insights\":[]}")
        let result = await service.generateAnalytics(for: current, userID: "user_123")
        XCTAssertTrue(result.personalRecords.isEmpty)
        XCTAssertEqual(result.totalVolume, 1700)
    }

    private func equipmentLog(id: String, date: Date, setup: StrengthEquipment?, weight: Double) -> WorkoutSessionLog {
        var exercise = completedExercise(name: "Bench press", type: .strength, sets: [CompletedSet(reps: 10, weight: weight)])
        exercise.exercise.loadEquipment = setup
        return WorkoutSessionLog(id: id, date: date, routineID: "routine-1", completedExercises: [exercise])
    }

    private func dailyLog(for session: WorkoutSessionLog) -> DailyLog {
        DailyLog(id: "aggregate-day", date: session.date, meals: [], exercises: [
            LoggedExercise(id: "workout", name: "Workout", durationMinutes: 10, caloriesBurned: 100,
                           date: session.date, source: "routine", workoutID: session.routineID, sessionID: session.id)
        ])
    }
}
