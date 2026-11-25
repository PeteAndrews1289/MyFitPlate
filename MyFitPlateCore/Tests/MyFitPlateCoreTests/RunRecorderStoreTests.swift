import XCTest
import HealthKit
import CoreLocation
@testable import MyFitPlateCore

@MainActor
final class RunRecorderStoreTests: XCTestCase {
    private var mockStore: MockHealthStore!
    private var store: RunRecorderStore!

    override func setUp() {
        super.setUp()
        mockStore = MockHealthStore()
        store = RunRecorderStore(healthStore: mockStore)
    }

    override func tearDown() {
        mockStore.executedQueries.removeAll()
        store = nil
        mockStore = nil
        super.tearDown()
    }

    func testRecoveredRouteExportRetainsSegmentBoundariesAndIgnoresDuplicateFixes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let resumed = start.addingTimeInterval(300)
        let run = Run(id: "recording", source: .recorded, startDate: start, endDate: resumed.addingTimeInterval(5),
                      distanceMeters: 20, movingSeconds: 10, routeSegmentStarts: [start, resumed])
        func point(_ at: Date, _ latitude: Double) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -74), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: at)
        }
        let locations = [point(start, 40), point(start.addingTimeInterval(5), 40.0001),
                         point(resumed, 41), point(resumed, 41), point(resumed.addingTimeInterval(5), 41.0001)]
        let segments = RunRecorderRules.routeSegments(for: run, locations: locations)
        XCTAssertEqual(segments.map(\.count), [2, 2])
        XCTAssertEqual(segments[0].last?.coordinate.latitude, 40.0001)
        XCTAssertEqual(segments[1].first?.coordinate.latitude, 41)
    }

    func testInitWithDefaultStore() {
        let defaultStore = RunRecorderStore()
        XCTAssertNotNil(defaultStore)
    }

    func testReviewedShortRunExportsAffirmativeReviewWithoutInventedDistance() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(id: "short-recording", source: .recorded, startDate: start,
            endDate: start.addingTimeInterval(15), distanceMeters: 0, movingSeconds: 15,
            recordingID: "short-recording", saveReview: .shortRecording)
        let completed = expectation(description: "Reviewed short export")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            if case .saved = outcome {} else { XCTFail("Expected Health save") }
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        XCTAssertTrue(mockStore.savedWorkouts.first?.samples.isEmpty == true)
        XCTAssertEqual(mockStore.savedWorkoutMetadata.first?[RunSaveReviewRules.healthReviewMetadataKey] as? String,
                       RunSaveReview.shortRecording.rawValue)
        XCTAssertEqual(mockStore.savedWorkoutMetadata.first?[RunRecorderRules.recordingIDMetadataKey] as? String, "short-recording")
    }

    func testEmptyRunIsRejectedBeforeAnyHealthQueryOrWrite() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start,
                      distanceMeters: 0, movingSeconds: 0, saveReview: .shortRecording)
        let completed = expectation(description: "Empty export rejected")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            XCTAssertEqual(outcome, .failed); completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(mockStore.executedQueries.isEmpty)
        XCTAssertTrue(mockStore.savedWorkouts.isEmpty)
    }

    func testSaveWithoutExternalOverlapAndEstimatedCalories() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: nil, // Should estimate
            averageHeartRate: 145,
            isIndoor: false,
            hasRoute: true
        )
        
        let locs = [CLLocation(latitude: 40.0, longitude: -74.0)]
        mockStore.workoutQueryResult = [] // No overlapping external workouts
        
        let exp = expectation(description: "Save run")
        var savedUUID: String?
        store.save(run: run, locations: locs, weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(savedUUID, mockStore.saveWorkoutUUID)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.configuration.activityType, .running)
        XCTAssertEqual(saved.configuration.locationType, .outdoor)
        XCTAssertEqual(saved.samples.count, 2, "Should include distance and energy samples when no external overlap")
        XCTAssertTrue(saved.locations.isEmpty, "A lone route point cannot form a drawable route")
    }

    func testSaveWithExternalOverlap() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: 350,
            averageHeartRate: 150,
            isIndoor: false,
            hasRoute: true
        )
        
        // External watch workout overlapping by > 60 seconds
        let watchWorkout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            workoutEvents: nil,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 360),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5050),
            metadata: nil
        )
        mockStore.workoutQueryResult = [watchWorkout]
        
        let exp = expectation(description: "Save run with overlap")
        var savedUUID: String?
        store.save(run: run, locations: [], weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(savedUUID, mockStore.saveWorkoutUUID)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.samples.count, 0, "Should NOT include quantity samples when external recording overlaps")
    }

    func testOverlappingStrengthAndCyclingKeepRunDistanceWhileDeferringMeasuredEnergy() {
        for activity in [HKWorkoutActivityType.traditionalStrengthTraining, .cycling] {
            let workout = overlappingWorkout(activity: activity, meters: activity == .cycling ? 12_000 : nil, calories: 360)
            XCTAssertEqual(exportedSampleIdentifiers(overlapping: [workout]),
                           [HKQuantityType(.distanceWalkingRunning).identifier],
                           "Another activity's energy can overlap without supplying running distance")
        }
    }

    func testExternalWorkoutWithoutQuantityEvidenceCannotSuppressRecordedValues() {
        let expected: Set<String> = [HKQuantityType(.distanceWalkingRunning).identifier, HKQuantityType(.activeEnergyBurned).identifier]
        for activity in [HKWorkoutActivityType.running, .walking, .cycling, .traditionalStrengthTraining] {
            XCTAssertEqual(exportedSampleIdentifiers(overlapping: [overlappingWorkout(activity: activity)]), expected)
        }
    }

    func testFootWorkoutEnergyAndDistanceAreSuppressedIndependently() {
        for activity in [HKWorkoutActivityType.running, .walking] {
            let energyOnly = overlappingWorkout(activity: activity, calories: 360)
            XCTAssertEqual(exportedSampleIdentifiers(overlapping: [energyOnly]), [HKQuantityType(.distanceWalkingRunning).identifier])
            let distanceOnly = overlappingWorkout(activity: activity, meters: 5_050)
            XCTAssertEqual(exportedSampleIdentifiers(overlapping: [distanceOnly]), [HKQuantityType(.activeEnergyBurned).identifier])
            let both = overlappingWorkout(activity: activity, meters: 5_050, calories: 360)
            XCTAssertTrue(exportedSampleIdentifiers(overlapping: [both]).isEmpty,
                          "The matching watch run/walk still protects both quantities from duplication")
        }
    }

    func testCyclingDistanceWithoutEnergyDoesNotReplaceEitherRunQuantity() {
        let cycling = overlappingWorkout(activity: .cycling, meters: 12_000)
        XCTAssertEqual(exportedSampleIdentifiers(overlapping: [cycling]),
                       [HKQuantityType(.distanceWalkingRunning).identifier, HKQuantityType(.activeEnergyBurned).identifier])
    }

    func testOurSourceAndBriefOverlapsDoNotSuppressEitherQuantity() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1_800)
        func evidence(_ source: String, start: Date, end: Date) -> RunRecorderRules.WorkoutQuantityEvidence {
            .init(start: start, end: end, sourceBundleID: source, activity: .running, distanceMeters: 5_000, activeCalories: 360)
        }
        let own = evidence("MyFitPlate.CalorieBeta", start: start, end: end)
        let brief = evidence("com.watch.app", start: end.addingTimeInterval(-60), end: end.addingTimeInterval(300))
        let adjacent = evidence("com.watch.app", start: end, end: end.addingTimeInterval(300))
        XCTAssertEqual(RunRecorderRules.quantitySuppression(runStart: start, runEnd: end, workouts: [own, brief, adjacent]),
                       RunRecorderRules.QuantitySuppression())
        let meaningful = evidence("com.watch.app", start: end.addingTimeInterval(-61), end: end.addingTimeInterval(300))
        XCTAssertEqual(RunRecorderRules.quantitySuppression(runStart: start, runEnd: end, workouts: [meaningful]),
                       RunRecorderRules.QuantitySuppression(distance: true, activeEnergy: true))
    }

    func testInvalidAndZeroExternalQuantitiesCannotSupplyMissingEvidence() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(1_800)
        for quantity in [nil, 0, -1, Double.nan, .infinity] as [Double?] {
            let evidence = RunRecorderRules.WorkoutQuantityEvidence(start: start, end: end, sourceBundleID: "com.watch.app",
                                                                   activity: .running, distanceMeters: quantity, activeCalories: quantity)
            XCTAssertEqual(RunRecorderRules.quantitySuppression(runStart: start, runEnd: end, workouts: [evidence]),
                           RunRecorderRules.QuantitySuppression())
        }
    }

    func testIndependentExternalSourcesOnlyReplaceQuantitiesTheyActuallySupply() {
        let strength = overlappingWorkout(activity: .traditionalStrengthTraining, calories: 360)
        let walking = overlappingWorkout(activity: .walking, meters: 5_050)
        XCTAssertTrue(exportedSampleIdentifiers(overlapping: [strength, walking]).isEmpty)
    }

    func testSaveWithIndoorRunAndProvidedCalories() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let end = now
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: start,
            endDate: end,
            distanceMeters: 4000,
            movingSeconds: 1800,
            activeCalories: 300,
            averageHeartRate: 140,
            isIndoor: true,
            hasRoute: false
        )
        
        mockStore.workoutQueryResult = []
        let exp = expectation(description: "Save indoor run")
        store.save(run: run, locations: [], weightLbs: 165) { _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
        let saved = mockStore.savedWorkouts.first!
        XCTAssertEqual(saved.configuration.locationType, .indoor)
        XCTAssertEqual(saved.samples.count, 2)
    }

    func testSaveWithError() {
        let now = Date()
        let run = Run(
            id: UUID().uuidString,
            source: .recorded,
            startDate: now.addingTimeInterval(-1800),
            endDate: now,
            distanceMeters: 5000,
            movingSeconds: 1800,
            activeCalories: 350,
            averageHeartRate: nil,
            isIndoor: false,
            hasRoute: false
        )
        
        mockStore.workoutQueryResult = []
        mockStore.saveWorkoutError = NSError(domain: "test", code: 1, userInfo: nil)
        mockStore.saveWorkoutUUID = nil
        
        let exp = expectation(description: "Save run error")
        var savedUUID: String? = "initial"
        store.save(run: run, locations: [], weightLbs: 165) { uuid in
            savedUUID = uuid
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        XCTAssertNil(savedUUID)
    }

    func testTemporaryRecorderSurvivesAsynchronousOverlapQueryUntilSaveCompletes() {
        mockStore.sampleQueryDelay = 0.05
        mockStore.workoutQueryResult = []
        let now = Date()
        let run = Run(source: .recorded, startDate: now.addingTimeInterval(-600), endDate: now,
                      distanceMeters: 2_000, movingSeconds: 600)
        let saved = expectation(description: "Temporary recorder completes its Health save")
        RunRecorderStore(healthStore: mockStore).save(run: run, locations: [], weightLbs: 165) { id in
            XCTAssertEqual(id, self.mockStore.saveWorkoutUUID)
            saved.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
    }

    func testPausedRunSendsExactEventsAndPreservesWindowAndRouteTimes() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(120)
        let run = Run(source: .recorded, startDate: start, endDate: end, distanceMeters: 1_000, movingSeconds: 90,
                      pauseTimeline: RunPauseTimeline(completeness: .complete, intervals: [
                        RunPauseInterval(startDate: start.addingTimeInterval(30), endDate: start.addingTimeInterval(50), origin: .explicitPause),
                        RunPauseInterval(startDate: start.addingTimeInterval(80), endDate: start.addingTimeInterval(90), origin: .explicitPause)
                      ]))
        let route = [10.0, 11.0].map { seconds in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 40 + (seconds - 10) * 0.00001, longitude: -74), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: start.addingTimeInterval(seconds))
        }
        let saved = expectation(description: "Pause events reach the Health writer")
        store.save(run: run, locations: route, weightLbs: 165) { id in
            XCTAssertEqual(id, self.mockStore.saveWorkoutUUID)
            saved.fulfill()
        }
        waitForExpectations(timeout: 1)
        let actual = try XCTUnwrap(mockStore.savedWorkouts.first)
        XCTAssertEqual(actual.start, start)
        XCTAssertEqual(actual.end, end)
        XCTAssertEqual(actual.locations.map(\.timestamp), route.map(\.timestamp))
        let events = try XCTUnwrap(mockStore.savedWorkoutEvents.first)
        XCTAssertEqual(events.map(\.type), [.pause, .resume, .pause, .resume])
        XCTAssertEqual(events.map { $0.dateInterval.start.timeIntervalSince(start) }, [30, 50, 80, 90])
        XCTAssertTrue(events.allSatisfy { $0.dateInterval.duration == 0 })
    }

    func testInvalidCompleteTimelineRejectsHealthWriteBeforeQueries() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(120),
                      distanceMeters: 1_000, movingSeconds: 90, pauseTimeline: RunPauseTimeline(completeness: .complete))
        let failed = expectation(description: "Invalid complete timing stays local")
        store.save(run: run, locations: [], weightLbs: 165) { id in
            XCTAssertNil(id)
            failed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(mockStore.executedQueries.isEmpty)
        XCTAssertTrue(mockStore.savedWorkouts.isEmpty)
    }

    func testEventFailureDoesNotClaimHealthSuccessOrRemoveLocalRun() {
        let defaults = UserDefaults(suiteName: "RunRecorderPauseFailureTests")!
        defer { defaults.removePersistentDomain(forName: "RunRecorderPauseFailureTests") }
        let fallback = RunFallbackStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 80,
                      pauseTimeline: RunPauseTimeline(completeness: .complete, intervals: [
                        RunPauseInterval(startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(40), origin: .explicitPause)
                      ]))
        XCTAssertTrue(fallback.save(run, for: "owner"))
        mockStore.saveWorkoutEventError = NSError(domain: "event-test", code: 42)
        let failed = expectation(description: "Pause event failure propagates")
        store.save(run: run, locations: [], weightLbs: 165) { id in
            XCTAssertNil(id)
            failed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(mockStore.savedWorkoutEvents.count, 1)
        XCTAssertTrue(mockStore.savedWorkouts.isEmpty)
        XCTAssertTrue(fallback.containsRecording(id: run.id, for: "owner"))
        XCTAssertEqual(fallback.runs(since: .distantPast, for: "owner").first?.pauseTimeline, run.pauseTimeline)
    }

    func testPartialAndLegacyTimelinesNeverInventMissingPauses() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 50)
        XCTAssertTrue(try XCTUnwrap(RunRecorderRules.workoutEvents(for: run)).isEmpty)
        run.pauseTimeline = RunPauseTimeline(completeness: .partial, intervals: [
            RunPauseInterval(startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(30), origin: .recoveryGap)
        ])
        let events = try XCTUnwrap(RunRecorderRules.workoutEvents(for: run))
        XCTAssertEqual(events.map { $0.dateInterval.start.timeIntervalSince(start) }, [20, 30])
        let workout = healthWorkout(for: run, events: events)
        XCTAssertEqual(workout.duration, 90, "Known exclusions only; never manufacture the missing 40 seconds")
    }

    func testRealHealthWorkoutDurationMatchesMultiplePausesAndFinishWhilePaused() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = RunSession(metric: true, timeAccounting: .activeElapsed)
        session.start(at: start)
        session.pause(at: start.addingTimeInterval(30))
        session.resume(at: start.addingTimeInterval(50))
        session.pause(at: start.addingTimeInterval(80))
        let run = try XCTUnwrap(session.finish(at: start.addingTimeInterval(120)))
        let events = try XCTUnwrap(RunRecorderRules.workoutEvents(for: run))
        let workout = healthWorkout(for: run, events: events)
        XCTAssertEqual(workout.startDate, start)
        XCTAssertEqual(workout.endDate, start.addingTimeInterval(120))
        XCTAssertEqual(events.map { $0.dateInterval.start.timeIntervalSince(start) }, [30, 50, 80, 120])
        XCTAssertEqual(workout.duration, run.movingSeconds, accuracy: 0.001)
        XCTAssertEqual(workout.duration, 60, accuracy: 0.001)
    }

    func testRealHealthWorkoutRecoveryUnionDoesNotDoubleSubtractOverlappingPauses() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 50,
                      pauseTimeline: RunPauseTimeline(completeness: .complete, intervals: [
                        RunPauseInterval(startDate: start.addingTimeInterval(20), endDate: start.addingTimeInterval(40), origin: .explicitPause),
                        RunPauseInterval(startDate: start.addingTimeInterval(30), endDate: start.addingTimeInterval(70), origin: .recoveryGap)
                      ]))
        let events = try XCTUnwrap(RunRecorderRules.workoutEvents(for: run))
        let workout = healthWorkout(for: run, events: events)
        XCTAssertEqual(events.map { $0.dateInterval.start.timeIntervalSince(start) }, [20, 70])
        XCTAssertEqual(workout.duration, 50, accuracy: 0.001)
        XCTAssertEqual(workout.startDate, run.startDate)
        XCTAssertEqual(workout.endDate, run.endDate)
    }

    func testCommittedButUnreadableWorkoutHasDistinctNonRetryOutcome() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 100)
        mockStore.saveWorkoutUUID = nil
        mockStore.saveWorkoutError = HealthWorkoutWriteError.savedButUnreadable
        let pending = expectation(description: "Committed Health result awaits read access")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            XCTAssertEqual(outcome, .savedAwaitingReadAccess)
            pending.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(mockStore.savedWorkouts.count, 1)
    }

    func testStableWorkoutAndQuantitySyncMetadataSurviveReidentifiedRetries() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(id: "local-id", source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 100, activeCalories: 90, recordingID: "recording-id")
        var another = run
        another.recordingID = "another-recording"
        for payload in [run, run.reidentified(as: "confirmed-health-id"), another] {
            let saved = expectation(description: "Write immutable payload")
            store.saveWithOutcome(run: payload, locations: [], weightLbs: 165) { outcome in
                XCTAssertEqual(outcome, .saved(self.mockStore.saveWorkoutUUID!))
                saved.fulfill()
            }
            waitForExpectations(timeout: 1)
        }
        let metadata = mockStore.savedWorkoutMetadata
        XCTAssertEqual(metadata.count, 3)
        XCTAssertEqual(metadata[0][RunRecorderRules.recordingIDMetadataKey] as? String, "recording-id")
        XCTAssertEqual(metadata[0][HKMetadataKeySyncIdentifier] as? String, metadata[1][HKMetadataKeySyncIdentifier] as? String)
        XCTAssertNotEqual(metadata[0][HKMetadataKeySyncIdentifier] as? String, metadata[2][HKMetadataKeySyncIdentifier] as? String)
        XCTAssertEqual(metadata[0][HKMetadataKeySyncVersion] as? Int, 1)
        let first = mockStore.savedWorkouts[0].samples, retried = mockStore.savedWorkouts[1].samples
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String },
                       retried.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
        XCTAssertEqual(Set(first.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }).count, 2)
        XCTAssertTrue(first.allSatisfy { $0.metadata?[HKMetadataKeySyncVersion] as? Int == 1 })
        XCTAssertNotEqual(first.first?.metadata?[HKMetadataKeySyncIdentifier] as? String,
                          mockStore.savedWorkouts[2].samples.first?.metadata?[HKMetadataKeySyncIdentifier] as? String)
    }

    func testMetadataFailureAndErrorAlongsideUUIDCannotClaimHealthSuccess() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(100),
                      distanceMeters: 1_000, movingSeconds: 100)
        mockStore.saveWorkoutMetadataError = NSError(domain: "metadata-test", code: 4)
        let rejected = expectation(description: "Metadata failure remains failed")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            XCTAssertEqual(outcome, .failed)
            rejected.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(mockStore.savedWorkouts.isEmpty)
        mockStore.saveWorkoutMetadataError = nil
        mockStore.saveWorkoutError = NSError(domain: "save-test", code: 5)
        let inconsistent = expectation(description: "An error cannot be reported as a successful UUID")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            XCTAssertEqual(outcome, .failed)
            inconsistent.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    private func healthWorkout(for run: Run, events: [HKWorkoutEvent]) -> HKWorkout {
        HKWorkout(activityType: .running, start: run.startDate, end: run.endDate, workoutEvents: events,
                  totalEnergyBurned: nil, totalDistance: nil, metadata: nil)
    }

    private func overlappingWorkout(activity: HKWorkoutActivityType, meters: Double? = nil, calories: Double? = nil) -> HKWorkout {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return HKWorkout(activityType: activity, start: start, end: start.addingTimeInterval(1_800), workoutEvents: nil,
                         totalEnergyBurned: calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
                         totalDistance: meters.map { HKQuantity(unit: .meter(), doubleValue: $0) }, metadata: nil)
    }

    private func exportedSampleIdentifiers(overlapping workouts: [HKWorkout]) -> Set<String> {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(source: .recorded, startDate: start, endDate: start.addingTimeInterval(1_800),
                      distanceMeters: 5_000, movingSeconds: 1_800, activeCalories: 350)
        mockStore.workoutQueryResult = workouts
        let previousCount = mockStore.savedWorkouts.count
        let completed = expectation(description: "Save run with quantity-specific overlap evidence")
        store.saveWithOutcome(run: run, locations: [], weightLbs: 165) { outcome in
            XCTAssertEqual(outcome, .saved(self.mockStore.saveWorkoutUUID!))
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(mockStore.savedWorkouts.count, previousCount + 1)
        return Set(mockStore.savedWorkouts.last?.samples.compactMap { ($0 as? HKQuantitySample)?.quantityType.identifier } ?? [])
    }
}
