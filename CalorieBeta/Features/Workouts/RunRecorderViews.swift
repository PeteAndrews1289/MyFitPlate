import SwiftUI
import CoreLocation
import MapKit
import MyFitPlateCore
import AVFoundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// The in-app GPS run recorder. CoreLocation stays out here at the app layer; every fix
// is adapted into a plain RunLocationFix for the tested RunSession engine, and raw
// CLLocations are kept aside for the HealthKit route.

final class RunLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus

    var onLocation: ((CLLocation) -> Void)?
    var onError: (() -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        // When-in-use auth + the location background mode keeps fixes flowing with the
        // screen off; the system shows its background-location indicator, as it should.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func acquireSignal() {
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            onLocation?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.health.error("Run location error: \(error.localizedDescription, privacy: .public)")
        onError?()
    }
}

@MainActor
final class RunRecorderViewModel: ObservableObject {
    enum Stage: Equatable {
        case permission
        case ready
        case running
        case paused
        case saving
        case summary(Run)
    }

    @Published var stage: Stage = .ready
    @Published var elapsedSeconds: Double = 0
    @Published private(set) var tick = 0
    @Published private(set) var finishedSetRecord = false
    @Published private(set) var gpsSignal: RunGPSSignal = .acquiring
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var lapMessage: String?
    @Published private(set) var recoveryBlocked = false
    @Published private(set) var recoveredRecording = false

    enum SaveState: Equatable {
        case pending, syncingLocal, appleHealth, healthConfirmationPending, healthConfirmationUnknown, routeSyncPending, localOnly, localRecoveryPending, failed

        var isSaved: Bool { self == .syncingLocal || self == .appleHealth || self == .healthConfirmationPending || self == .healthConfirmationUnknown || self == .routeSyncPending || self == .localOnly }
        var message: String {
            switch self {
            case .pending: return "Saving your run…"
            case .syncingLocal: return "Saved in MyFitPlate. Syncing to Apple Health…"
            case .appleHealth: return "Saved to Apple Health."
            case .healthConfirmationPending: return "Apple Health saved your run. Confirmation will be available when Health can be read."
            case .healthConfirmationUnknown: return "Your recording is kept in MyFitPlate. Apple Health sync has not been confirmed."
            case .routeSyncPending: return "Workout saved to Apple Health. Its route still needs syncing; your private route is retained temporarily."
            case .localOnly: return "Saved in MyFitPlate. Apple Health sync was unavailable."
            case .localRecoveryPending: return "Your reviewed recording is kept, but its full MyFitPlate copy still needs saving. Retry also checks any pending Apple Health sync."
            case .failed: return "Your run still needs saving. Try again; your reviewed time and distance stay unchanged."
            }
        }
    }
    @Published private(set) var saveState: SaveState = .pending
    private var pendingCompletionWeightLbs: Double?
    private var lastHealthOutcome: RunHealthSaveOutcome?
    var saveReviewActiveSeconds: Double { session.snapshot(at: currentDate())?.movingSeconds ?? elapsedSeconds }
    var saveReviewRequirement: RunSaveReviewRules.Requirement {
        RunSaveReviewRules.requirement(activeSeconds: saveReviewActiveSeconds, distanceMeters: distanceMeters)
    }

    let locationService = RunLocationService()
    private(set) var session: RunSession
    private var route: RunRouteRecording
    private let liveSensors = RunLiveSensorService()
    private(set) var sensors: RunSensorCheckpoint
    private var sensorResumedAt = Date.distantFuture
    var liveHeartRate: RunHeartRateSample? { stage == .running ? sensors.latestHeartRate(at: currentDate(), after: sensorResumedAt) : nil }
    var liveCadence: RunCadenceSample? { stage == .running ? sensors.latestCadence(at: currentDate(), after: sensorResumedAt) : nil }
    var recordedRouteSegments: [[RunLocationFix]] { route.segments }
    var recoveredCheckpointDate: Date?
    private var rawLocations: [CLLocation] {
        route.segments.flatMap { $0 }.map {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), altitude: 0,
                       horizontalAccuracy: $0.horizontalAccuracy, verticalAccuracy: -1, timestamp: $0.timestamp)
        }
    }
    private var timer: Timer?
    private let store: RunHealthSaving
    private let completedRunStore: RunFallbackStore
    private let workoutResultStore: RunWorkoutResultStore
    private let draftStore: RunRecordingDraftStore
    private let routeStore: RunRouteArchiveStore
    private let persistsRecovery: Bool
    private let exportJobs: RunHealthExportJobStore?
    private let validateStart: (() -> Bool)?
    private let onStarted: ((String) -> Void)?
    private let metric: Bool
    private let ownerID: String?
    private let currentDate: () -> Date
    private let recordsLocation: Bool
    private var latestFix: RunLocationFix?
    private var hasLocationError = false
    private var didRecordCompletion = false
    private var isSaving = false
    private var didLoadDraft = false
    private var lastCheckpoint = Date.distantPast
    private var routeSafelyRetained = false
    private var workoutReceiptSafelyRetained = false
    @Published private(set) var workoutReceiptMessage: String?
    private(set) var workoutPlan: RunWorkoutPlan?
    private var scheduledContext: RunScheduledContext?
    @Published private(set) var planProgressMessage: String?
    private var workoutTracker: RunWorkoutTracker?
    private let audioCoach = RunAudioCoach()
    private var paceAudioPolicy = RunAudioCuePolicy()
    private var audioPreferencesLoaded = false
    private var audioPreferencesWritable = true
    @Published var audioPreferences = RunAudioPreferences() {
        didSet { if audioPreferencesLoaded { saveAudioPreferences() } }
    }
    @Published private(set) var audioMessage: String?
    @Published private(set) var workoutProgress: RunWorkoutProgress?
    @Published private(set) var finishedWorkoutResult: RunWorkoutResult?
    @Published var audioCoachEnabled: Bool = UserDefaults.standard.object(forKey: "runAudioCoachEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(audioCoachEnabled, forKey: "runAudioCoachEnabled")
            if !audioCoachEnabled { audioCoach.stop() }
        }
    }
    #if canImport(ActivityKit)
    private var liveActivity: Activity<RunActivityAttributes>?
    private var lastActivityPush = Date.distantPast
    private var activityRevision = 0
    #endif

    init(metric: Bool, workoutPlan: RunWorkoutPlan? = nil, currentDate: @escaping () -> Date = Date.init,
         recordsLocation: Bool = true, store: RunHealthSaving = RunRecorderStore(),
         completedRunStore: RunFallbackStore = .shared,
         draftStore: RunRecordingDraftStore = RunRecordingDraftStore(),
         routeStore: RunRouteArchiveStore = RunRouteArchiveStore(), persistsRecovery: Bool? = nil,
         workoutResultStore: RunWorkoutResultStore? = nil,
         exportJobs: RunHealthExportJobStore? = nil, validateStart: (() -> Bool)? = nil, onStarted: ((String) -> Void)? = nil, scheduledContext: RunScheduledContext? = nil) {
        self.metric = metric
        self.currentDate = currentDate
        self.recordsLocation = recordsLocation
        self.store = store
        self.completedRunStore = completedRunStore
        self.workoutResultStore = workoutResultStore ?? RunWorkoutResultStore()
        self.draftStore = draftStore
        self.routeStore = routeStore
        self.persistsRecovery = persistsRecovery ?? recordsLocation
        self.exportJobs = exportJobs ?? (recordsLocation ? RunHealthExportJobStore() : nil)
        self.validateStart = validateStart
        self.onStarted = onStarted
        self.ownerID = DIContainer.shared.authService.currentUserID
        self.workoutPlan = workoutPlan
        self.scheduledContext = scheduledContext
        self.workoutTracker = workoutPlan.map(RunWorkoutTracker.init)
        let newSession = RunSession(metric: metric, timeAccounting: .activeElapsed)
        session = newSession
        route = RunRouteRecording(recordingID: newSession.id)
        sensors = RunSensorCheckpoint(recordingID: newSession.id)
        locationService.onLocation = { [weak self] location in
            Task { @MainActor in
                self?.ingest(location)
            }
        }
        locationService.onError = { [weak self] in
            Task { @MainActor in
                self?.hasLocationError = true
                self?.refreshSignal()
            }
        }
        liveSensors.onHeartRate = { [weak self] sample in self?.ingestHeartRate(sample) }
        liveSensors.onCadence = { [weak self] sample in self?.ingestCadence(sample) }
        loadAudioPreferences()
        configureSessionCallbacks()
    }

    private func loadAudioPreferences() {
        defer { audioPreferencesLoaded = true }
        guard let ownerID else { return }
        do {
            if let saved = try EditorDraftStore().load(RunAudioPreferences.self, userID: ownerID, scope: "run.audio.preferences.v1") {
                audioPreferences = saved.value
            }
        } catch {
            audioPreferencesWritable = false
            audioMessage = "Your earlier audio settings could not be read. Session choices still work; the saved settings stay unchanged."
        }
    }

    private func saveAudioPreferences() {
        paceAudioPolicy.resetPending()
        guard audioPreferencesWritable, let ownerID, accountStillMatches else { return }
        do { try EditorDraftStore().save(audioPreferences, userID: ownerID, scope: "run.audio.preferences.v1") } catch {
            audioMessage = "These audio choices apply now, but could not be kept for next time."
        }
    }

    func testAudio() {
        let message = stage == .ready ? "MyFitPlate audio check. Your workout has not started." : "MyFitPlate audio check. Keep your effort comfortable."
        if !audioCoach.announce(message) { audioMessage = "Audio is unavailable right now. Check your output device or try again after the interruption." }
    }

    private func speakPaceIfUseful(_ progress: RunWorkoutProgress) {
        guard audioCoachEnabled, audioPreferences.pace else { paceAudioPolicy.resetPending(); return }
        let pace = progress.stepDistanceMeters > 0 ? progress.stepElapsedSeconds / (progress.stepDistanceMeters / 1000) : nil
        guard let cue = paceAudioPolicy.evaluate(stepID: progress.currentStep?.id, target: progress.currentStep?.target,
            pace: pace, activeSeconds: elapsedSeconds, stepSeconds: progress.stepElapsedSeconds,
            stepMeters: progress.stepDistanceMeters, isRunning: stage == .running,
            hasFreshSignal: currentPace != nil) else { return }
        let message: String
        switch cue {
        case .easeBack: message = "Faster than your planned range. Ease back if that matches how you feel."
        case .gentlyQuicker: message = "Slower than your planned range. Only pick up the pace if it feels comfortable."
        case .paceUnavailable: message = "Pace guidance needs a fresh GPS signal. Your timer is still running."
        }
        _ = audioCoach.announce(message, interruptCurrent: false)
    }

    private func configureSessionCallbacks() {
        session.onSplitCompleted = { [weak self] split in
            Task { @MainActor in
                self?.speakSplitAnnouncement(split)
            }
        }
    }

    deinit { timer?.invalidate() }

    var distanceMeters: Double { session.distanceMeters }
    var currentPace: Double? {
        guard stage == .running, gpsSignal == .ready else { return nil }
        return session.currentPaceSecondsPerKm(at: currentDate())
    }
    var averagePace: Double? {
        guard distanceMeters >= 100, elapsedSeconds > 0 else { return nil }
        return elapsedSeconds / (distanceMeters / 1000)
    }
    var belongsToCurrentAccount: Bool { accountStillMatches }
    var nextWorkoutStep: RunWorkoutStep? {
        guard let progress = workoutProgress, let plan = workoutPlan,
              plan.steps.indices.contains(progress.currentStepIndex + 1) else { return nil }
        return plan.steps[progress.currentStepIndex + 1]
    }

    private var isFixture: Bool {
        #if DEBUG
        ScreenshotDemoMode.isEnabled
        #else
        false
        #endif
    }

    func prepare() {
        guard stage == .ready || stage == .permission else { return }
        guard !recordsLocation || accountStillMatches else {
            recoveryBlocked = true
            recoveryMessage = "Sign in to your account before opening a saved recording."
            return
        }
        if !didLoadDraft { restoreDraftIfNeeded() }
        if case .summary = stage { return }
        if stage == .paused {
            startTimer()
            if !isFixture, recordsLocation,
               locationService.authorizationStatus == .authorizedWhenInUse || locationService.authorizationStatus == .authorizedAlways {
                locationService.acquireSignal()
            }
            return
        }
        startTimer()
        guard !isFixture, recordsLocation else { stage = .ready; return }
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            stage = .ready
            locationService.acquireSignal()
        default:
            stage = .permission
        }
    }

    func requestLocation() {
        locationService.requestPermission()
    }

    func refreshAfterForeground() {
        refreshClock()
        refreshSignal()
        refreshWorkoutProgress(announceTransitions: false)
        if stage == .running || stage == .paused { pushLiveActivity(force: true) }
    }

    func checkpointForBackground() {
        refreshClock()
        refreshWorkoutProgress(announceTransitions: false)
        checkpoint(force: true)
    }

    func retryRecovery() {
        didLoadDraft = false
        recoveryBlocked = false
        recoveryMessage = nil
        prepare()
    }

    private func restoreDraftIfNeeded() {
        didLoadDraft = true
        guard persistsRecovery, accountStillMatches, let ownerID else { return }
        do {
            #if DEBUG
            if isFixture, ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-run-draft") {
                try draftStore.remove(userID: ownerID)
            }
            if isFixture, ownerID == ScreenshotDemoData.userID,
               ProcessInfo.processInfo.arguments.contains("-ui-testing-seed-run-route-checkpoint"),
               try draftStore.load(userID: ownerID) == nil {
                try seedRouteRecoveryFixture(userID: ownerID)
            }
            #endif
            guard let draft = try draftStore.load(userID: ownerID) else { return }
            // A completed local commit takes precedence if removing its recovery file
            // was interrupted. Never resurrect a run already in history.
            if completedRunStore.containsRecording(id: draft.session.id, for: ownerID) {
                guard var completed = completedRunStore.runs(since: draft.session.startDate, for: ownerID)
                    .first(where: { ($0.recordingID ?? $0.id) == draft.session.id }) else { throw CocoaError(.coderReadCorrupt) }
                if completed.workoutResult == nil, let snapshot = draft.workout,
                   let tracker = RunWorkoutTracker(snapshot: snapshot),
                   let receipt = tracker.result(runID: completed.id, completedAt: completed.endDate,
                       elapsedSeconds: completed.movingSeconds, distanceMeters: completed.distanceMeters) {
                    completed.workoutResult = receipt
                    guard completedRunStore.save(completed, for: ownerID) else { throw CocoaError(.fileWriteUnknown) }
                }
                if let retainedRoute = draft.route, retainedRoute.hasDrawableRoute {
                    try routeStore.save(retainedRoute, run: completed, userID: ownerID)
                }
                // Exact steps are already committed with the run. A corrupt legacy
                // lookup must remain unchanged and cannot block or resurrect history.
                if let receipt = completed.workoutResult { try? workoutResultStore.saveChecked(receipt, userID: ownerID) }
                try draftStore.remove(userID: ownerID, sessionID: draft.session.id)
                return
            }
            guard let restored = RunSession(snapshot: draft.session, at: currentDate()) else {
                recoveryBlocked = true
                recoveryMessage = "Your saved recording has been kept, but couldn't be opened. Try recovery again."
                return
            }
            session = restored
            sensors = draft.sensors ?? RunSensorCheckpoint(recordingID: restored.id)
            route = draft.route ?? RunRouteRecording(recordingID: restored.id, earlierRouteUnavailable: true)
            recoveredCheckpointDate = draft.updatedAt
            scheduledContext = draft.scheduledContext
            workoutPlan = draft.workout?.plan
            workoutTracker = draft.workout.flatMap(RunWorkoutTracker.init(snapshot:))
            configureSessionCallbacks()
            recoveredRecording = true
            if let pending = draft.pendingCompletion {
                pendingCompletionWeightLbs = pending.weightLbs
                finishedWorkoutResult = pending.run.workoutResult
                elapsedSeconds = pending.run.movingSeconds
                stage = .summary(pending.run)
                saveState = .failed
                if let job = try? exportJobs?.load(recordingID: pending.run.recordingID ?? pending.run.id, userID: ownerID),
                   job.phase != .queued, job.phase != .workoutRetryRequired {
                    saveState = .localRecoveryPending
                }
                recoveryMessage = "Your reviewed run is kept. Retry saves the same time, distance and recording without starting it again."
                return
            }
            let checkpoint = draft.recoveredPreviousCheckpoint ? "Recovered the previous verified checkpoint." : "Recovered at the last checkpoint."
            let routeMessage = route.earlierRouteUnavailable ? "The earlier route was not stored; new route segments can still be recorded."
                : route.hasDrawableRoute ? "Your earlier route is kept. Any interruption stays a gap on the map."
                : "No route had been measured yet."
            recoveryMessage = "\(checkpoint) Time away is excluded. \(routeMessage)"
            stage = .paused
            refreshClock()
            refreshWorkoutProgress(announceTransitions: false)
            startLiveActivity()
        } catch {
            recoveryBlocked = true
            recoveryMessage = "Your saved recording has been kept, but couldn't be read. Try recovery again before starting a new run."
        }
    }

    #if DEBUG
    private func seedRouteRecoveryFixture(userID: String) throws {
        let start = currentDate().addingTimeInterval(-600)
        let sample = RunSession(metric: metric, timeAccounting: .activeElapsed)
        var trace = RunRouteRecording(recordingID: sample.id)
        sample.start(at: start)
        func add(_ seconds: Double, latitude: Double) {
            let fix = RunLocationFix(latitude: latitude, longitude: -74, horizontalAccuracy: 5,
                                     timestamp: start.addingTimeInterval(seconds))
            if sample.ingest(fix) { trace.append(fix, startsNewSegment: sample.lastIngestStartedSegment) }
        }
        add(0, latitude: 40); add(5, latitude: 40.0001); add(10, latitude: 40.0002)
        sample.pause(at: start.addingTimeInterval(15))
        sample.resume(at: start.addingTimeInterval(120))
        add(120, latitude: 40.001); add(125, latitude: 40.0011); add(130, latitude: 40.0012)
        let checkpointDate = start.addingTimeInterval(150)
        guard let snapshot = sample.snapshot(at: checkpointDate) else { return }
        try draftStore.save(RunRecordingDraft(session: snapshot, updatedAt: checkpointDate, route: trace), userID: userID)
    }
    #endif

    private func checkpoint(force: Bool = false) {
        guard persistsRecovery, let ownerID, accountStillMatches,
              stage == .running || stage == .paused,
              force || currentDate().timeIntervalSince(lastCheckpoint) >= 5,
              let snapshot = session.snapshot(at: currentDate()) else { return }
        do {
            try draftStore.save(RunRecordingDraft(session: snapshot, workout: workoutTracker?.snapshot(), updatedAt: currentDate(), route: route, scheduledContext: scheduledContext, sensors: sensors), userID: ownerID)
            lastCheckpoint = currentDate()
        } catch {
            recoveryMessage = "Automatic recovery couldn't be updated. Keep this recording open until you've saved your run."
        }
    }

    @discardableResult
    private func clearDraftAfterSaving(discard: Bool = false) -> Bool {
        guard persistsRecovery, let ownerID else { return !persistsRecovery }
        // Health confirmation cannot replace the full local record: Health does not
        // retain every sensor/lap/plan field, and may be unreadable after a write.
        guard discard || completedRunStore.containsRecording(id: session.id, for: ownerID) else { return false }
        guard discard || !route.hasDrawableRoute || routeSafelyRetained else { return false }
        guard discard || workoutPlan == nil || workoutReceiptSafelyRetained else { return false }
        do {
            try draftStore.remove(userID: ownerID, sessionID: session.id)
            return true
        } catch {
            AppLog.workouts.error("Saved run recovery cleanup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func speakSplitAnnouncement(_ split: RunSplit) {
        guard audioCoachEnabled, audioPreferences.splits, stage == .running else { return }
        let unit = session.splitDistanceMeters == 1000 ? "kilometer" : "mile"
        let distanceText = "\(split.index) \(unit)\(split.index == 1 ? "" : "s") completed."

        let paceMinutes = Int(split.seconds / 60)
        let paceSeconds = Int(split.seconds.truncatingRemainder(dividingBy: 60))
        let paceText = "Split pace: \(paceMinutes) minutes and \(paceSeconds) seconds per \(unit)."

        let totalText = "Total time: \(RunFormat.durationText(seconds: session.activeElapsedSeconds(at: currentDate())))."

        audioCoach.announce("\(distanceText) \(paceText) \(totalText)")
    }

    private func speakWorkoutStep(_ progress: RunWorkoutProgress) {
        guard audioCoachEnabled, audioPreferences.steps else { return }
        guard let step = progress.currentStep else {
            audioCoach.announce("Workout complete. Keep running, or finish when you're ready.")
            return
        }
        let targetText = step.targetText(metric: metric).map { " \($0)." } ?? ""
        audioCoach.announce("\(step.title). \(step.goalText(metric: metric)).\(targetText)")
    }

    func begin() {
        guard stage == .ready, !recoveryBlocked else { return }
        guard validateStart?() ?? true else {
            recoveryMessage = "This planned run changed. Close this screen and review the current session before starting."
            return
        }
        guard !recordsLocation || accountStillMatches else { return }
        guard isFixture || !recordsLocation || locationService.authorizationStatus == .authorizedWhenInUse
                || locationService.authorizationStatus == .authorizedAlways else {
            stage = .permission
            return
        }
        session.start(at: currentDate())
        if !isFixture, recordsLocation { locationService.startTracking() }
        startTimer()
        stage = .running
        startSensors()
        refreshClock()
        refreshWorkoutProgress(announceTransitions: false)
        checkpoint(force: true)
        if let context = scheduledContext, let ownerID {
            do { try RunTrainingBlockStore().recordStarted(context: context, recordingID: session.id, userID: ownerID) } catch {
                recoveryMessage = "Recording started. Its plan receipt could not update yet; your recording keeps the scheduled session identity."
            }
        }
        onStarted?(session.id)
        startLiveActivity()
        if let workoutProgress { speakWorkoutStep(workoutProgress) } else if audioCoachEnabled { audioCoach.announce("Run started.") }
        HapticsService.shared.playImpact(style: .medium)
    }

    var canReviseGoal: Bool {
        stage == .paused && workoutPlan?.steps.count == 1 && workoutProgress?.currentStep != nil
            && workoutProgress?.currentStep?.goal != .open
    }

    func reviseGoal(step: RunWorkoutStep, goal: RunWorkoutStep.Goal, operationID: String) -> String? {
        guard canReviseGoal, accountStillMatches, let workoutTracker,
              let candidate = RunWorkoutTracker(snapshot: workoutTracker.snapshot()) else {
            return "This run or goal changed. Close this review and reopen the current paused goal."
        }
        refreshClock()
        guard candidate.reviseCurrentGoal(expectedStepID: step.id, expectedGoal: step.goal, newGoal: goal,
            operationID: operationID, elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters) else {
            return "Choose an unfinished target beyond your recorded time or distance. The original goal stays unchanged."
        }
        if persistsRecovery {
            guard let ownerID, let snapshot = session.snapshot(at: currentDate()) else { return "This paused recording could not be checkpointed. Try again." }
            do {
                try draftStore.save(RunRecordingDraft(session: snapshot, workout: candidate.snapshot(),
                    updatedAt: currentDate(), route: route, scheduledContext: scheduledContext, sensors: sensors), userID: ownerID)
            } catch { return "The revised goal could not be saved. Your original goal is still active; try again." }
        }
        self.workoutTracker = candidate
        refreshWorkoutProgress(announceTransitions: false)
        pushLiveActivity(force: true)
        return nil
    }

    func markLap(expectedPreviousID: String?, operationID: String = UUID().uuidString) {
        guard stage == .running, accountStillMatches else { return }
        let now = currentDate()
        guard let lap = session.proposedManualLap(operationID: operationID, expectedPreviousID: expectedPreviousID, at: now),
              var snapshot = session.snapshot(at: now) else { return }
        if session.manualLaps.contains(where: { $0.id == lap.id }) { return }
        snapshot.manualLaps = session.manualLaps + [lap]
        if persistsRecovery {
            guard let ownerID else { return }
            do {
                try draftStore.save(RunRecordingDraft(session: snapshot, workout: workoutTracker?.snapshot(),
                    updatedAt: now, route: route, scheduledContext: scheduledContext, sensors: sensors), userID: ownerID)
            } catch {
                lapMessage = "The lap could not be saved. Your recording and workout step are unchanged; try again."
                return
            }
        }
        guard session.acceptManualLap(lap, expectedPreviousID: expectedPreviousID) else { return }
        lapMessage = "Lap \(lap.index) saved. Workout step unchanged."
        lastCheckpoint = now
        refreshClock()
        HapticsService.shared.playImpact(style: .light)
    }

    func advanceWorkoutStep(expectedStepID: String) {
        guard stage == .running, let workoutTracker else { return }
        refreshClock()
        _ = workoutTracker.advanceManually(expectedStepID: expectedStepID,
            elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)
        refreshWorkoutProgress()
        checkpoint(force: true)
        pushLiveActivity(force: true)
    }

    func pause() {
        guard stage == .running else { return }
        session.pause(at: currentDate())
        guard session.state == .paused else { return }
        refreshClock()
        stage = .paused
        liveSensors.stop()
        refreshWorkoutProgress(announceTransitions: false)
        checkpoint(force: true)
        if audioCoachEnabled { audioCoach.announce("Run paused.") }
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
    }

    func resume() {
        guard stage == .paused else { return }
        guard !recordsLocation || accountStillMatches else { return }
        guard isFixture || !recordsLocation || locationService.authorizationStatus == .authorizedWhenInUse
                || locationService.authorizationStatus == .authorizedAlways else {
            recoveryMessage = "Enable location in Settings before resuming this run. Your recovered time and distance are kept."
            if locationService.authorizationStatus == .notDetermined { locationService.requestPermission() }
            return
        }
        session.resume(at: currentDate())
        guard session.state == .running else { return }
        if !isFixture, recordsLocation { locationService.startTracking() }
        stage = .running
        startSensors()
        refreshClock()
        checkpoint(force: true)
        if recoveredRecording { startLiveActivityIfNeeded() }
        if audioCoachEnabled { audioCoach.announce("Run resumed.") }
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
    }

    func finish(weightLbs: Double, confirmShortRecording: Bool = false) {
        guard stage == .running || stage == .paused, accountStillMatches else { return }
        refreshClock()
        guard saveReviewRequirement != .empty else {
            recoveryMessage = "Record at least 1 second of active time before saving. Your recording is still here."
            return
        }
        guard saveReviewRequirement != .shortRecording || confirmShortRecording else {
            recoveryMessage = "Review this short recording before saving. Only its measured time and distance will be kept."
            return
        }
        let acceptedReview: RunSaveReview = saveReviewRequirement == .shortRecording ? .shortRecording : .standard
        refreshWorkoutProgress(announceTransitions: false)
        checkpoint(force: true)
        let finishDate = currentDate()
        guard let completionSnapshot = session.snapshot(at: finishDate) else { return }
        guard var run = session.finish(at: finishDate) else { return }
        elapsedSeconds = run.movingSeconds
        run.saveReview = acceptedReview
        run.sensors = sensors
        run.workoutResult = workoutTracker?.result(runID: run.id, completedAt: run.endDate,
            elapsedSeconds: run.movingSeconds, distanceMeters: run.distanceMeters)
        finishedWorkoutResult = run.workoutResult
        // Pin the estimate to this completed run so retries export identical energy
        // even if the account's current body weight changes in the meantime.
        if run.activeCalories == nil {
            run.activeCalories = RunEnergy.estimateKcal(distanceMeters: run.distanceMeters, weightLbs: weightLbs)
        }
        run.scheduledContext = scheduledContext
        // The default is stamped once on this accepted recording, never re-read
        // when a save/export is retried after the user's default changes.
        run.shoeID = accountStillMatches ? RunningShoeStore().defaultShoe()?.id : nil
        run.hasRoute = route.hasDrawableRoute
        run.routeSegmentStarts = route.segments.compactMap { $0.first?.timestamp }
        if persistsRecovery, let ownerID {
            do {
                try draftStore.save(RunRecordingDraft(session: completionSnapshot, workout: workoutTracker?.snapshot(),
                    updatedAt: finishDate, route: route, scheduledContext: scheduledContext, sensors: sensors,
                    pendingCompletion: RunRecordingCompletion(run: run, weightLbs: weightLbs)), userID: ownerID)
            } catch {
                if let restored = RunSession(snapshot: completionSnapshot, at: finishDate) {
                    session = restored
                    configureSessionCallbacks()
                }
                stage = .paused
                liveSensors.stop()
                locationService.stopTracking()
                pushLiveActivity(force: true)
                recoveryMessage = "Your run is paused. Its reviewed finish could not be kept safely; try Finish again."
                return
            }
        }
        liveSensors.stop()
        locationService.stopTracking()
        stopTimer()
        endLiveActivity()
        audioCoach.stop()
        pendingCompletionWeightLbs = weightLbs
        stage = .summary(run)
        save(run, weightLbs: weightLbs)
    }

    func retrySave(weightLbs: Double) {
        guard case .summary(let run) = stage, saveState == .failed || saveState == .localRecoveryPending || saveState == .localOnly || saveState == .routeSyncPending || saveState == .healthConfirmationPending || saveState == .healthConfirmationUnknown,
              accountStillMatches else { return }
        // A legacy injected writer has no durable reconciliation seam. It may retry
        // an explicit failure, never a confirmed or uncertain Health commit.
        if saveState == .healthConfirmationPending || saveState == .healthConfirmationUnknown || saveState == .routeSyncPending, exportJobs == nil { return }
        save(run, weightLbs: pendingCompletionWeightLbs ?? weightLbs)
    }

    private func save(_ run: Run, weightLbs: Double) {
        guard !isSaving else { return }
        isSaving = true
        // Commit locally before the asynchronous Health write. The captured account
        // owns this recording even if authentication changes while Health is saving.
        let localSaved = ownerID.map { completedRunStore.save(run, for: $0) } ?? false
        saveState = localSaved ? .syncingLocal : .pending
        let receiptSaved = saveWorkoutResult(for: run)
        workoutReceiptSafelyRetained = run.workoutResult == nil || localSaved || receiptSaved
        workoutReceiptMessage = workoutReceiptSafelyRetained ? nil : "Your workout steps still need saving. Keep this screen open and retry; the recovery checkpoint is kept."
        if localSaved {
            recordScheduledCompletion(run)
            recordCompletionIfNeeded()
            // Keep accepted coordinates even if Health is unavailable. Only clear the
            // recovery checkpoint after its route has a protected completed cache.
            if !persistsRecovery || !route.hasDrawableRoute {
                clearDraftAfterSaving()
            } else if let ownerID {
                do {
                    try routeStore.save(route, run: run, userID: ownerID)
                    routeSafelyRetained = true
                    clearDraftAfterSaving()
                } catch {
                    recoveryMessage = "Your run is saved. Its route checkpoint is kept because the route cache could not be updated."
                }
            }
        }
        let shoeID = run.shoeID
        if localSaved, accountStillMatches { RunningShoeStore().tagRun(runID: run.id, withShoeID: shoeID) }

        #if DEBUG
        if isFixture {
            isSaving = false
            saveState = localSaved ? .localOnly : .failed
            return
        }
        #endif

        let completion: (RunHealthSaveOutcome) -> Void = { [self] outcome in
            self.isSaving = false
            if outcome != .failed { self.lastHealthOutcome = outcome }
            switch outcome {
            case .saved(let savedID), .savedRoutePending(let savedID):
                if let ownerID = self.ownerID {
                    _ = self.completedRunStore.reidentify(id: run.id, as: savedID, for: ownerID)
                }
                let savedRun = run.reidentified(as: savedID)
                if !localSaved, let ownerID = self.ownerID,
                   self.completedRunStore.save(savedRun, for: ownerID) {
                    self.workoutReceiptSafelyRetained = true
                    self.workoutReceiptMessage = nil
                }
                self.recordScheduledCompletion(savedRun)
                self.stage = .summary(savedRun)
                self.saveState = outcome == .saved(savedID) ? .appleHealth : .routeSyncPending
                self.clearDraftAfterSaving()
                self.recordCompletionIfNeeded()
                if self.accountStillMatches {
                    RunningShoeStore().tagRun(runID: savedID, withShoeID: shoeID)
                    if self.saveWorkoutResult(for: savedRun) {
                        self.workoutReceiptSafelyRetained = true
                        self.workoutReceiptMessage = nil
                        if savedID != run.id { self.workoutResultStore.deleteResult(forRunID: run.id) }
                        self.clearDraftAfterSaving()
                    }
                }
            case .savedAwaitingReadAccess:
                // HealthKit can save successfully while the locked database cannot
                // return the UUID. Retrying this outcome would create another workout.
                self.saveState = .healthConfirmationPending
                self.recordScheduledCompletion(run)
                self.clearDraftAfterSaving()
                self.recordCompletionIfNeeded()
            case .confirmationRequired:
                self.saveState = .healthConfirmationUnknown
                if localSaved { self.clearDraftAfterSaving(); self.recordCompletionIfNeeded() }
            case .failed:
                self.saveState = localSaved ? .localOnly : .failed
            }
            if outcome != .failed, let ownerID = self.ownerID,
               !self.completedRunStore.containsRecording(id: run.recordingID ?? run.id, for: ownerID) {
                self.saveState = .localRecoveryPending
            }
            self.refreshRecords(for: run)
        }
        if let ownerID, let exportJobs {
            RunHealthExportCoordinator(jobs: exportJobs, routes: routeStore, fallback: completedRunStore, writer: store)
                .export(run: run, weightLbs: weightLbs, userID: ownerID, locations: rawLocations, completion: completion)
        } else {
            // Legacy injected writers have no durable job seam. An in-session local
            // retry must not issue a second already-accepted Health write.
            if let lastHealthOutcome { completion(lastHealthOutcome) } else {
                store.saveWithOutcome(run: run, locations: rawLocations, weightLbs: weightLbs, completion: completion)
            }
        }
    }

    private var accountStillMatches: Bool { ownerID != nil && ownerID == DIContainer.shared.authService.currentUserID }

    @discardableResult
    private func saveWorkoutResult(for run: Run) -> Bool {
        guard accountStillMatches, let ownerID else { return false }
        guard let result = run.workoutResult else { return workoutPlan == nil }
        finishedWorkoutResult = result
        do { try workoutResultStore.saveChecked(result, userID: ownerID); return true } catch { return false }
    }

    func retryWorkoutReceipt() {
        guard case .summary(let run) = stage, accountStillMatches, let ownerID else { return }
        let localSaved = completedRunStore.save(run, for: ownerID)
        let receiptSaved = saveWorkoutResult(for: run)
        workoutReceiptSafelyRetained = localSaved || receiptSaved || run.workoutResult == nil
        workoutReceiptMessage = workoutReceiptSafelyRetained ? nil : "Workout steps could not be saved. Your entries and recovery checkpoint are kept."
        if workoutReceiptSafelyRetained { clearDraftAfterSaving() }
    }

    private func recordScheduledCompletion(_ run: Run) {
        guard run.scheduledContext != nil, let ownerID, accountStillMatches else { return }
        do {
            try RunTrainingBlockStore().recordCompleted(run: run, userID: ownerID)
            planProgressMessage = nil
        } catch {
            planProgressMessage = "Your run is saved. Open the training plan to reconcile its session receipt."
        }
    }

    private func recordCompletionIfNeeded() {
        guard !didRecordCompletion, accountStillMatches else { return }
        didRecordCompletion = true
        ActivationFunnel.recordTrainingCompletion(.recordedRun)
        HapticManager.instance.notification(.success)
    }

    private func refreshRecords(for run: Run) {
        guard recordsLocation, accountStillMatches, let ownerID else { return }
        RunImportService().fetchLifetimeRuns(userID: ownerID) { [weak self] result in
            guard let self, self.accountStillMatches, case .success(let history) = result else { return }
            let past = history.filter { $0.endDate <= run.startDate }
            self.finishedSetRecord = RunStats.setsRecord(run, against: past + [run])
        }
    }

    func discard() {
        liveSensors.stop()
        locationService.stopTracking()
        stopTimer()
        endLiveActivity()
        audioCoach.stop()
        if stage == .running || stage == .paused {
            let removed = clearDraftAfterSaving(discard: true)
            if removed, let context = scheduledContext, let ownerID, accountStillMatches {
                do { try RunTrainingBlockStore().recordAbandoned(context: context, recordingID: session.id, userID: ownerID) } catch {
                    planProgressMessage = "The recording was discarded. Review its start receipt in the training plan."
                }
            }
        }
    }

    func closePreparation() {
        guard stage == .ready || stage == .permission else { return }
        discard()
    }

    // MARK: Live Activity

    private func startLiveActivity() {
        #if canImport(ActivityKit)
        guard !isFixture, recordsLocation else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityRevision += 1
        let revision = activityRevision
        let existing = Activity<RunActivityAttributes>.activities
        let matching = existing.first { $0.attributes.recordingID == session.id }
        liveActivity = matching
        Task {
            for previous in existing where previous.id != matching?.id {
                await previous.end(nil, dismissalPolicy: .immediate)
            }
            guard activityRevision == revision, stage == .running || stage == .paused else { return }
            if matching != nil { pushLiveActivity(force: true); return }
            do {
                let state = activityState()
                liveActivity = try Activity.request(
                    attributes: RunActivityAttributes(recordingID: session.id),
                    content: .init(state: state, staleDate: RunActivityTimerRules.freshnessDeadline(reportedAt: state.reportedAt))
                )
            } catch {
                AppLog.liveActivity.error("Run Live Activity failed to start: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    private func startLiveActivityIfNeeded() {
        #if canImport(ActivityKit)
        if liveActivity == nil { startLiveActivity() }
        #endif
    }

    /// Distance/pace only change with GPS fixes, so pushes are throttled to ~8s; the
    /// timer renders live on the lock screen via timerInterval without any pushes.
    private func pushLiveActivity(force: Bool = false) {
        #if canImport(ActivityKit)
        guard let liveActivity else { return }
        guard force || Date().timeIntervalSince(lastActivityPush) > 8 else { return }
        lastActivityPush = Date()
        let state = activityState()
        activityRevision += 1
        let revision = activityRevision
        Task {
            guard activityRevision == revision, self.liveActivity?.id == liveActivity.id else { return }
            await liveActivity.update(
                .init(
                    state: state,
                    staleDate: RunActivityTimerRules.freshnessDeadline(reportedAt: state.reportedAt)
                )
            )
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        activityRevision += 1
        guard let liveActivity else { return }
        let state = activityState()
        Task {
            await liveActivity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
        #endif
    }

    #if canImport(ActivityKit)
    private func activityState() -> RunActivityAttributes.ContentState {
        let now = currentDate()
        return RunActivityAttributes.ContentState(
            startTime: now.addingTimeInterval(-session.activeElapsedSeconds(at: now)),
            distanceText: RunFormat.distanceText(meters: distanceMeters, metric: metric),
            paceText: RunFormat.paceText(secondsPerKm: currentPace, metric: metric)
                ?? RunFormat.paceText(secondsPerKm: averagePace, metric: metric).map { "Avg \($0)" } ?? "— pace",
            elapsedText: RunFormat.durationText(seconds: elapsedSeconds),
            isPaused: stage == .paused,
            workoutStepText: liveWorkoutStepText,
            workoutTargetText: liveWorkoutTargetText,
            reportedAt: now
        )
    }

    private var liveWorkoutStepText: String? {
        guard let progress = workoutProgress else { return nil }
        guard let step = progress.currentStep else {
            return stage == .paused ? "Paused · Workout complete" : "Workout complete"
        }
        let prefix = stage == .paused ? "Paused · " : ""
        return "\(prefix)Step \(progress.currentStepIndex + 1) of \(progress.stepCount) · \(step.title)"
    }

    private var liveWorkoutTargetText: String? {
        guard let progress = workoutProgress, let step = progress.currentStep else { return nil }
        return step.targetText(metric: metric) ?? step.goalText(metric: metric)
    }
    #endif

    func ingest(_ location: CLLocation) {
        guard location.timestamp <= currentDate() else { return }
        let fix = RunLocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        latestFix = fix
        hasLocationError = false
        refreshSignal()
        guard stage == .running, accountStillMatches else { return }
        // Route and distance must agree on which fixes actually belong to the run.
        if session.ingest(fix) { route.append(fix, startsNewSegment: session.lastIngestStartedSegment) }
        refreshClock()
        tick += 1
        refreshWorkoutProgress()
        checkpoint()
        pushLiveActivity()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshSignal()
                guard self.accountStillMatches else { self.liveSensors.stop(); return }
                guard self.stage == .running || self.stage == .paused else { return }
                self.refreshClock()
                self.refreshWorkoutProgress()
                self.checkpoint()
                self.pushLiveActivity()
            }
        }
    }

    func ingestHeartRate(_ sample: RunHeartRateSample) {
        guard stage == .running, accountStillMatches else { return }
        if sensors.append(sample, after: sensorResumedAt, now: currentDate()) { tick += 1; checkpoint() }
    }
    func ingestCadence(_ sample: RunCadenceSample) {
        guard stage == .running, accountStillMatches else { return }
        if sensors.append(sample, after: sensorResumedAt, now: currentDate()) { tick += 1; checkpoint() }
    }
    private func startSensors() {
        sensorResumedAt = currentDate()
        guard !isFixture, recordsLocation, accountStillMatches else { return }
        liveSensors.start(at: sensorResumedAt)
    }

    private func refreshClock() {
        elapsedSeconds = session.activeElapsedSeconds(at: currentDate())
    }

    private func refreshSignal() {
        gpsSignal = RunGPSSignal.evaluate(fix: latestFix, at: currentDate(), hasError: hasLocationError)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshWorkoutProgress(announceTransitions: Bool = true) {
        guard let workoutTracker else { return }
        let previousStepIndex = workoutProgress?.currentStepIndex
        let progress = workoutTracker.progress(elapsedSeconds: elapsedSeconds, distanceMeters: distanceMeters)
        workoutProgress = progress
        speakPaceIfUseful(progress)

        guard announceTransitions,
              let previousStepIndex,
              progress.currentStepIndex != previousStepIndex else { return }
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
        speakWorkoutStep(progress)
    }
}

private enum RunDisplayMetric: String, CaseIterable, Identifiable {
    case time, distance, pace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .time: return "Active time"
        case .distance: return "Distance"
        case .pace: return "Live pace"
        }
    }

    var symbol: String {
        switch self {
        case .time: return "stopwatch"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .pace: return "speedometer"
        }
    }

    var accessibilityID: String {
        switch self {
        case .time: return "run_elapsed"
        case .distance: return "run_distance"
        case .pace: return "run_live_pace"
        }
    }
}

struct RunRecorderView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @AppStorage("runDisplayMetric") private var displayMetric = RunDisplayMetric.time.rawValue
    @AppStorage("runKeepScreenAwake") private var keepScreenAwake = false
    @AppStorage("runMetricLayout") private var metricLayout = "focus"
    @StateObject private var viewModel: RunRecorderViewModel
    @State private var showingDiscardAlert = false
    @State private var showingFinishConfirmation = false
    @State private var reconciledTrainingFuelRunID: String?
    @State private var showingDisplaySettings = false
    @State private var showingRecoveredRoute = false
    @State private var goalToRevise: RunWorkoutStep?
    @State private var previousIdleTimerSetting: Bool?

    private var primaryMetric: RunDisplayMetric { RunDisplayMetric(rawValue: displayMetric) ?? .time }

    init(plan: RunWorkoutPlan? = nil, validateStart: (() -> Bool)? = nil, onStarted: ((String) -> Void)? = nil,
         scheduledContext: RunScheduledContext? = nil) {
        let metric = UserDefaults.standard.object(forKey: "useMetricBodyUnits") as? Bool
            ?? (Locale.current.measurementSystem != .us)
        _viewModel = StateObject(wrappedValue: RunRecorderViewModel(metric: metric, workoutPlan: plan, validateStart: validateStart, onStarted: onStarted, scheduledContext: scheduledContext))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .permission:
                    permissionView
                case .ready:
                    readyView
                case .running, .paused:
                    liveView
                case .saving:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Saving your run")
                            .appFont(size: 14)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                case .summary(let run):
                    RunRecorderSummary(
                        run: run,
                        metric: useMetric,
                        setRecord: viewModel.finishedSetRecord,
                        workoutPlanName: viewModel.workoutPlan?.name,
                        workoutResult: viewModel.finishedWorkoutResult,
                        saveState: viewModel.saveState,
                        planProgressMessage: viewModel.planProgressMessage,
                        workoutReceiptMessage: viewModel.workoutReceiptMessage,
                        onRetryReceipt: viewModel.retryWorkoutReceipt,
                        onRetry: { viewModel.retrySave(weightLbs: goalSettings.weight) }
                    ) { dismiss() }
                    .onAppear { if viewModel.saveState.isSaved { reconcileTrainingFuel(for: run) } }
                    .onChange(of: viewModel.saveState) { _, state in
                        if state.isSaved { reconcileTrainingFuel(for: run) }
                    }
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar {
                if viewModel.stage == .permission || viewModel.stage == .ready {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { viewModel.closePreparation(); dismiss() }
                            .accessibilityIdentifier("run_recorder_close")
                    }
                }
                if viewModel.stage == .ready || viewModel.stage == .running || viewModel.stage == .paused {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingDisplaySettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Run display settings")
                        .accessibilityIdentifier("run_display_settings")
                    }
                }
            }
            .onReceive(viewModel.locationService.$authorizationStatus) { _ in
                if viewModel.stage == .permission { viewModel.prepare() }
            }
        }
        .sheet(isPresented: $showingDisplaySettings) { displaySettings }
        .sheet(item: $goalToRevise) { step in
            RunGoalRevisionSheet(step: step, metric: useMetric, activeSeconds: viewModel.elapsedSeconds,
                distanceMeters: viewModel.distanceMeters) { goal, operationID in
                viewModel.reviseGoal(step: step, goal: goal, operationID: operationID)
            }
        }
        .onAppear {
            previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
            updateScreenAwake()
        }
        .task { viewModel.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshAfterForeground() } else { viewModel.checkpointForBackground() }
            updateScreenAwake()
        }
        .onChange(of: viewModel.stage) { _, _ in updateScreenAwake() }
        .onChange(of: keepScreenAwake) { _, _ in updateScreenAwake() }
        .onDisappear {
            if let previousIdleTimerSetting { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting }
            previousIdleTimerSetting = nil
        }
        .interactiveDismissDisabled(viewModel.stage != .ready && viewModel.stage != .permission)
    }

    private func updateScreenAwake() {
        guard let previousIdleTimerSetting else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting
            || (keepScreenAwake && viewModel.stage == .running && scenePhase == .active)
    }

    private var displaySettings: some View {
        AppSheetScaffold(title: "Run display", dismiss: { showingDisplaySettings = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Picker("Metric layout", selection: $metricLayout) {
                        Text("Focus").tag("focus")
                        Text("Dashboard").tag("dashboard")
                    }.pickerStyle(.segmented).accessibilityIdentifier("run_display_layout")
                    Text(metricLayout == "dashboard" ? "Time, distance and both paces share equal space." : "Your primary metric stays large, with the other values below.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Primary metric").appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(RunDisplayMetric.allCases) { metric in
                            Button { displayMetric = metric.rawValue } label: {
                                displayMetricChoice(metric)
                                .foregroundStyle(AppPalette.text)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(metric.title)
                            .accessibilityValue(primaryMetric == metric ? "Selected" : "Not selected")
                            .accessibilityIdentifier("run_display_" + metric.rawValue)
                        }
                    }
                    .appSurface(.quiet)
                    Text("All four metrics stay available. Live pace needs a fresh GPS signal; it is unavailable while paused.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Toggle("Keep screen awake", isOn: $keepScreenAwake)
                            .appTextRole(.control)
                            .accessibilityIdentifier("run_keep_screen_awake")
                        Text("While recording in the foreground. Pausing restores normal auto-lock. You can still lock the screen yourself; keeping it awake uses more battery.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .appSurface(.quiet)
                }
                .padding(AppSpacing.screenHorizontal)
            }
        }
    }

    @ViewBuilder
    private func displayMetricChoice(_ metric: RunDisplayMetric) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(metric.title).appTextRole(.control)
                    .fixedSize(horizontal: false, vertical: true)
                if primaryMetric == metric {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.brandText)
                }
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                Label(metric.title, systemImage: metric.symbol).appTextRole(.control)
                Spacer(minLength: AppSpacing.compact)
                Image(systemName: primaryMetric == metric ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(primaryMetric == metric ? AppPalette.brandText : Color(UIColor.secondaryLabel))
                    .accessibilityHidden(true)
            }
        }
    }

    private func reconcileTrainingFuel(for run: Run) {
        guard viewModel.belongsToCurrentAccount, viewModel.saveState.isSaved,
              reconciledTrainingFuelRunID != viewModel.session.id else { return }
        reconciledTrainingFuelRunID = viewModel.session.id
        let today = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: run.endDate) ? log : nil
        }
        guard trainingFuelPlanStore.recordRunCompletion(
            run,
            selectedPlanID: viewModel.workoutPlan?.id,
            today: today,
            goals: TodayFuelPlanGoals(
                calories: goalSettings.calories ?? 0,
                protein: goalSettings.protein,
                carbs: goalSettings.carbs,
                fats: goalSettings.fats
            ),
            for: DIContainer.shared.authService.currentUserID
        ) else { return }
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
            parameters: ["outcome": "completed", "source": "recorded_run"]
        )
    }

    private var permissionView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                Image(systemName: "location.fill")
                    .appFont(size: 34, weight: .semibold)
                    .foregroundStyle(AppPalette.effort)
                    .accessibilityHidden(true)
                Text("Your run starts here")
                    .appTextRole(.screenTitle)
                Text(locationPermissionText)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if viewModel.locationService.authorizationStatus == .notDetermined {
                    Button("Enable location") { viewModel.requestLocation() }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("run_enable_location")
                } else if viewModel.locationService.authorizationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                }
            }
            .padding(AppSpacing.screenHorizontal)
            .padding(.top, 44)
        }
        .navigationTitle("Record a run")
    }

    private var locationPermissionText: String {
        switch viewModel.locationService.authorizationStatus {
        case .denied: return "Enable location for MyFitPlate in Settings to record your route, distance, and pace."
        case .restricted: return "Location is restricted on this device. You can still log a treadmill run from Running."
        default: return "Allow location to record your route, distance, and pace. A recording can continue with the screen locked."
        }
    }

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Label("Ready when you are", systemImage: "figure.run")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Text(viewModel.workoutPlan?.name ?? "Open run")
                        .appTextRole(.screenTitle)
                        .accessibilityIdentifier("run_ready_plan_name")
                    Text("Start when you are ready. Paused time stays out of your pace.")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                }
                .appSurface(.emphasized)
                signalCard
                recoveryNotice
                audioControl
                if let plan = viewModel.workoutPlan, let first = plan.steps.first {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("First up · \(first.title)").appTextRole(.sectionTitle)
                        Text(first.goalText(metric: useMetric)).appTextRole(.body)
                        if let target = first.targetText(metric: useMetric) {
                            Text(target).appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        Text("\(plan.steps.count) workout \(plan.steps.count == 1 ? "step" : "steps")")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.quiet)
                }
            }
            .padding(AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Start run") { viewModel.begin() }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("run_recorder_start")
                .disabled(viewModel.recoveryBlocked)
                .padding(AppSpacing.screenHorizontal)
                .background(AppPalette.canvas)
        }
        .navigationTitle("Record a run")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_recorder_ready")
    }

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(viewModel.gpsSignal.title, systemImage: viewModel.gpsSignal == .ready ? "location.fill" : "location.slash")
                .appTextRole(.secondary)
                .foregroundStyle(viewModel.gpsSignal == .ready ? AppPalette.positive : AppPalette.caution)
                .accessibilityIdentifier("run_gps_status")
            Text(viewModel.gpsSignal.detail)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
    }

    private var audioControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
        HStack(spacing: AppSpacing.row) {
        Button { viewModel.audioCoachEnabled.toggle() } label: {
            Label(viewModel.audioCoachEnabled ? "Audio cues on" : "Audio cues off",
                  systemImage: viewModel.audioCoachEnabled ? "speaker.wave.2" : "speaker.slash")
                .appTextRole(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityValue(viewModel.audioCoachEnabled ? "On" : "Off")
        .accessibilityHint("Announces splits, workout steps, pause, and resume.")
        .accessibilityIdentifier("run_audio_cues")
        Menu("Audio options", systemImage: "slider.horizontal.3") {
            Toggle("Workout step announcements", isOn: $viewModel.audioPreferences.steps)
            Toggle("Split announcements", isOn: $viewModel.audioPreferences.splits)
            Toggle("Occasional pace prompts", isOn: $viewModel.audioPreferences.pace)
            Button("Test audio") { viewModel.testAudio() }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("run_audio_options")
        }
        if let message = viewModel.audioMessage {
            Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution)
        }
        }
    }

    @ViewBuilder
    private var recoveryNotice: some View {
        if let message = viewModel.recoveryMessage {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label(viewModel.recoveredRecording ? "Recovered recording" : "Recording recovery", systemImage: "arrow.clockwise.circle")
                    .appTextRole(.secondary)
                Text(message)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = viewModel.recoveredCheckpointDate {
                    Text("Checkpoint \(date.formatted(date: .abbreviated, time: .shortened)) · \(RunFormat.distanceText(meters: viewModel.distanceMeters, metric: useMetric)) retained")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.recordedRouteSegments.contains(where: { $0.count > 1 }) {
                    Button {
                        showingRecoveredRoute.toggle()
                    } label: {
                        Label(showingRecoveredRoute ? "Hide recovered route" : "View recovered route",
                              systemImage: showingRecoveredRoute ? "chevron.up" : "map")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showingRecoveredRoute ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("run_recovered_route_review")
                    if showingRecoveredRoute {
                        RunRecoveredRoutePreview(segments: viewModel.recordedRouteSegments)
                    }
                }
                if viewModel.recoveryBlocked {
                    Button("Try recovery again") { viewModel.retryRecovery() }
                        .frame(minHeight: 44)
                }
            }
            .appSurface(.quiet)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("run_recovery_notice")
        }
    }

    private var liveView: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if metricLayout == "dashboard" {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.row) {
                        liveMetric(metricValue(.time), "Active time", id: "run_elapsed")
                        liveMetric(metricValue(.distance), "Distance", id: "run_distance")
                        liveMetric(metricValue(.pace), "Live pace", id: "run_live_pace")
                        liveMetric(RunFormat.paceText(secondsPerKm: viewModel.averagePace, metric: useMetric) ?? "—", "Average pace", id: "run_average_pace")
                    }.accessibilityIdentifier("run_metric_dashboard")
                } else { recordingHero }
                if let progress = viewModel.workoutProgress {
                    RunWorkoutGuidanceCard(progress: progress, metric: useMetric,
                                           currentPace: viewModel.currentPace, nextStep: viewModel.nextWorkoutStep,
                                           isPaused: viewModel.stage == .paused,
                                           onAdvance: viewModel.advanceWorkoutStep)
                    if viewModel.canReviseGoal, let step = progress.currentStep {
                        Button("Review goal change", systemImage: "target") { goalToRevise = step }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("run_goal_change")
                    }
                }
                if metricLayout != "dashboard", dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: AppSpacing.row) { paceMetrics }
                } else if metricLayout != "dashboard" {
                    HStack(spacing: AppSpacing.row) { paceMetrics }
                }
                DisclosureGroup("Sensors") {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        if let heart = viewModel.liveHeartRate {
                            liveMetric("\(Int(heart.bpm.rounded())) bpm", "Heart rate", id: "run_live_heart_rate")
                            Text("\(heart.sourceName) · \(max(0, Int(Date().timeIntervalSince(heart.date)))) s ago")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Heart rate unavailable").appTextRole(.secondary)
                            Text("Requires a fresh sensor reading delivered through Apple Health. Your phone alone does not measure heart rate.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        if let cadence = viewModel.liveCadence {
                            liveMetric("\(Int(cadence.stepsPerMinute.rounded())) spm", "Cadence", id: "run_live_cadence")
                            Text("\(cadence.sourceName) · \(max(0, Int(Date().timeIntervalSince(cadence.date)))) s ago")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Cadence unavailable").appTextRole(.secondary)
                            Text("Carry this iPhone while running and allow Motion & Fitness. Missing or paused samples stay blank.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, AppSpacing.row)
                }.appSurface(.quiet).accessibilityIdentifier("run_live_sensors")
                if viewModel.stage == .paused {
                    Label("Paused time is excluded. Tap Resume when you're ready.", systemImage: "pause.circle")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if viewModel.gpsSignal != .ready {
                    signalCard
                }
                recoveryNotice
                if let split = viewModel.session.completedSplits.last {
                    LabeledContent("Last \(useMetric ? "kilometer" : "mile")") {
                        Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: useMetric) ?? "—")
                            .monospacedDigit()
                    }
                    .appTextRole(.secondary)
                    .accessibilityIdentifier("run_last_split")
                }
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    let previousID = viewModel.session.manualLaps.last?.id
                    Button("Mark lap", systemImage: "flag") { viewModel.markLap(expectedPreviousID: previousID) }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .disabled(viewModel.stage != .running)
                        .accessibilityIdentifier("run_mark_lap")
                    if let message = viewModel.lapMessage { Text(message).appTextRole(.caption).foregroundStyle(.secondary) }
                    if !viewModel.session.manualLaps.isEmpty {
                        RunManualLapsCard(laps: viewModel.session.manualLaps, metric: useMetric)
                    }
                }
                audioControl
            }
            .padding(AppSpacing.screenHorizontal)
        }
        recordingControls
        }
        .navigationTitle(viewModel.workoutPlan?.name ?? "Running")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_recorder_live")
        .confirmationDialog("Finish this run?", isPresented: $showingFinishConfirmation, titleVisibility: .visible) {
            Button("Save run") { viewModel.finish(weightLbs: goalSettings.weight) }
            Button("Keep paused", role: .cancel) {}
        } message: {
            Text("\(RunFormat.distanceText(meters: viewModel.distanceMeters, metric: useMetric)) · \(RunFormat.durationText(seconds: viewModel.elapsedSeconds)) active time")
        }
        .alert("Short recording", isPresented: $showingDiscardAlert) {
            Button("Save recording") {
                viewModel.finish(weightLbs: goalSettings.weight, confirmShortRecording: true)
            }
            .disabled(viewModel.saveReviewRequirement == .empty)
            .accessibilityIdentifier("run_confirm_short_save")
            Button("Keep paused", role: .cancel) {}
            Button("Discard", role: .destructive) { viewModel.discard(); dismiss() }
        } message: {
            Text(viewModel.saveReviewRequirement == .empty
                 ? "No active time to save yet. Resume for at least 1 second, or discard this recording."
                 : "\(RunFormat.durationText(seconds: viewModel.saveReviewActiveSeconds)) active time · \(RunFormat.distanceText(meters: viewModel.distanceMeters, metric: useMetric)). Save this short recording intentionally? Only measured time and distance will be kept, even if GPS recorded no distance.")
        }
    }

    private var recordingHero: some View {
        VStack(spacing: AppSpacing.compact) {
            Label(viewModel.stage == .paused ? "Paused" : "Recording",
                  systemImage: viewModel.stage == .paused ? "pause.circle" : "record.circle")
                .appTextRole(.caption).foregroundStyle(.secondary)
            Text(primaryMetric.title)
                .appTextRole(.secondary).foregroundStyle(.secondary)
            Text(metricValue(primaryMetric))
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 44 : 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityIdentifier(primaryMetric.accessibilityID)
            let supportingMetric: RunDisplayMetric = primaryMetric == .time ? .distance : .time
            Text(metricValue(supportingMetric) + (supportingMetric == .time ? " active" : ""))
                .appTextRole(.screenTitle).monospacedDigit()
                .accessibilityLabel(supportingMetric.title + ", " + metricValue(supportingMetric))
                .accessibilityIdentifier(supportingMetric.accessibilityID)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.group)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_metric_hero")
    }

    private func metricValue(_ metric: RunDisplayMetric) -> String {
        switch metric {
        case .time: return RunFormat.durationText(seconds: viewModel.elapsedSeconds)
        case .distance: return RunFormat.distanceText(meters: viewModel.distanceMeters, metric: useMetric)
        case .pace: return RunFormat.paceText(secondsPerKm: viewModel.currentPace, metric: useMetric) ?? "—"
        }
    }

    @ViewBuilder
    private var paceMetrics: some View {
        if primaryMetric == .pace {
            liveMetric(metricValue(.distance), "Distance", id: "run_distance")
        } else {
            liveMetric(metricValue(.pace), "Live pace", id: "run_live_pace")
        }
        liveMetric(RunFormat.paceText(secondsPerKm: viewModel.averagePace, metric: useMetric) ?? "—", "Average pace", id: "run_average_pace")
    }

    private var recordingControls: some View {
        HStack(spacing: AppSpacing.row) {
            Button {
                viewModel.stage == .running ? viewModel.pause() : viewModel.resume()
            } label: {
                Label(viewModel.stage == .running ? "Pause" : "Resume", systemImage: viewModel.stage == .running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("run_pause_resume")
            Button {
                if viewModel.stage == .running { viewModel.pause() }
                if viewModel.saveReviewRequirement != .standard { showingDiscardAlert = true } else { showingFinishConfirmation = true }
            } label: { Text("Finish") }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityIdentifier("run_finish")
        }
        .padding(AppSpacing.screenHorizontal)
        .background(AppPalette.canvas)
    }

    private func liveMetric(_ value: String, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(label).appTextRole(.caption).foregroundStyle(.secondary)
            Text(value).appTextRole(.sectionTitle).monospacedDigit().accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
    }
}

private struct RunWorkoutGuidanceCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let progress: RunWorkoutProgress
    let metric: Bool
    var currentPace: Double?
    var nextStep: RunWorkoutStep?
    var isPaused = false
    var onAdvance: ((String) -> Void)?
    @State private var stepToSkip: RunWorkoutStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    stepCount
                    stepTitle
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    stepTitle
                    Spacer(minLength: AppSpacing.compact)
                    stepCount
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) { goalAndRemaining }
            } else {
                HStack(alignment: .firstTextBaseline) { goalAndRemaining }
            }

            if progress.currentStep?.goal != .open {
                ProgressView(value: progress.progressFraction)
                    .tint(accentColor)
                    .accessibilityLabel("Workout step progress")
                    .accessibilityValue(remainingText)
            }

            if let targetText {
                Text(targetText)
                    .appTextRole(.secondary)
                    .foregroundColor(accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isPaused, currentPace != nil, let guidance = RunPaceGuidance.evaluate(
                target: progress.currentStep?.target, paceSecondsPerKm: currentStepPace,
                stepElapsedSeconds: progress.stepElapsedSeconds, stepDistanceMeters: progress.stepDistanceMeters
            ) {
                Label("Step pace · \(guidance.title.lowercased())", systemImage: guidance == .onTarget ? "checkmark.circle" : "speedometer")
                    .appTextRole(.secondary)
                    .foregroundStyle(guidance == .onTarget ? AppPalette.positive : Color(UIColor.secondaryLabel))
                    .accessibilityIdentifier("run_pace_guidance")
            }
            if let nextStep {
                Text("Next · \(nextStep.title) · \(nextStep.goalText(metric: metric))")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("run_next_step")
            }
            if let step = progress.currentStep, let onAdvance {
                Button(step.goal == .open ? "Continue step" : "Skip step") {
                    if step.goal == .open { onAdvance(step.id) } else { stepToSkip = step }
                }
                .buttonStyle(.bordered)
                .disabled(isPaused)
                .accessibilityIdentifier("run_advance_step")
            }
        }
        .appSurface(.quiet)
        .confirmationDialog("Skip this step?", isPresented: Binding(
            get: { stepToSkip != nil }, set: { if !$0 { stepToSkip = nil } }
        ), titleVisibility: .visible) {
            Button("Skip step") {
                if let step = stepToSkip { onAdvance?(step.id) }
                stepToSkip = nil
            }
            Button("Keep running", role: .cancel) { stepToSkip = nil }
        } message: {
            Text("Your time and distance are kept. This step will be marked as skipped, not completed.")
        }
    }

    private var stepTitle: some View {
        Text(title)
            .appTextRole(.sectionTitle)
            .foregroundStyle(AppPalette.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stepCount: some View {
        Text(stepCountText)
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var goalAndRemaining: some View {
        Text(progress.currentStep?.goalText(metric: metric) ?? "Done")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Text(remainingText)
            .appTextRole(.sectionTitle)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("run_step_remaining")
    }

    private var title: String {
        guard let step = progress.currentStep else { return "Workout complete" }
        if progress.stepCount == 1 { return step.title }
        if step.kind.displayName.localizedCaseInsensitiveCompare(step.title) == .orderedSame { return step.title }
        return "\(step.kind.displayName) · \(step.title)"
    }

    /// A sixty-second rolling pace can still contain the previous recovery during
    /// short intervals. Compare this step's own average, only with fresh live signal.
    private var currentStepPace: Double? {
        guard currentPace != nil, progress.stepDistanceMeters > 0 else { return nil }
        return progress.stepElapsedSeconds / (progress.stepDistanceMeters / 1000)
    }

    private var targetText: String? {
        progress.currentStep?.targetText(metric: metric)
    }

    private var stepCountText: String {
        guard !progress.isWorkoutComplete else { return "Complete" }
        return "Step \(progress.currentStepIndex + 1) of \(progress.stepCount)"
    }

    private var remainingText: String {
        if progress.isWorkoutComplete { return "Complete" }
        if let seconds = progress.remainingSeconds {
            return "\(RunFormat.durationText(seconds: seconds)) left"
        }
        if let meters = progress.remainingMeters {
            return "\(RunFormat.distanceText(meters: meters, metric: metric)) left"
        }
        return progress.currentStep?.goal == .open ? RunFormat.durationText(seconds: progress.stepElapsedSeconds) : ""
    }

    private var accentColor: Color {
        switch progress.currentStep?.kind {
        case .warmup, .hard:
            return AppPalette.effort
        case .recovery, .cooldown:
            return AppPalette.recovery
        case .none:
            return AppPalette.positive
        }
    }
}

struct RunWorkoutResultCard: View {
    let result: RunWorkoutResult
    let metric: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Workout steps", subtitle: result.planName) {
                let completed = result.steps.filter(\.isComplete).count
                Text("\(completed) \(completed == 1 ? "step" : "steps") completed")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brandText)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(RunResultPresentation.groups(result)) { group in
                if group.steps.count > 1 {
                    DisclosureGroup {
                        ForEach(group.steps) { stepRow($0) }
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(group.title).appTextRole(.control)
                            Text("\(group.steps.filter(\.isComplete).count)/\(group.steps.count) steps · \(RunFormat.durationText(seconds: group.elapsedSeconds)) · \(RunFormat.distanceText(meters: group.distanceMeters, metric: metric))")
                                .appTextRole(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } else {
                    ForEach(group.steps) { stepRow($0) }
                }
            }
            if let revisions = result.goalRevisions, !revisions.isEmpty {
                Divider()
                Text("Goal changes").appTextRole(.control)
                ForEach(revisions) { revision in
                    Text("\(goalLabel(revision.previousGoal)) → \(goalLabel(revision.revisedGoal)) at \(RunFormat.durationText(seconds: revision.activeSeconds)) active time")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Text("The original planned goal is retained. Completed steps were not rewritten.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_workout_steps")
    }

    private func goalLabel(_ goal: RunWorkoutStep.Goal) -> String {
        RunWorkoutStep(kind: .hard, title: "Goal", goal: goal).goalText(metric: metric)
    }

    private func stepRow(_ stepResult: RunWorkoutStepResult) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    stepIdentity(stepResult)
                    stepMetrics(stepResult)
                        .padding(.leading, 38)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    stepIdentity(stepResult)
                    Spacer(minLength: AppSpacing.compact)
                    stepMetrics(stepResult)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stepIdentity(_ stepResult: RunWorkoutStepResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(stepResult.stepIndex + 1)")
                .appTextRole(.caption)
                .foregroundStyle(accentColor(for: stepResult.step.kind))
                .frame(width: 28, height: 28)
                .background(accentColor(for: stepResult.step.kind).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("\(stepResult.step.kind.displayName) · \(stepResult.step.title)")
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                if !stepResult.isComplete {
                    Label(stepResult.completionReason == .skipped ? "Skipped" : "Partial",
                          systemImage: stepResult.completionReason == .skipped ? "forward.end" : "circle.lefthalf.filled")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(planText(for: stepResult.step))
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepMetrics(_ stepResult: RunWorkoutStepResult) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text(RunFormat.durationText(seconds: stepResult.elapsedSeconds))
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
            Text(RunFormat.distanceText(meters: stepResult.distanceMeters, metric: metric))
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let pace = RunFormat.paceText(secondsPerKm: stepResult.paceSecondsPerKm, metric: metric) {
                Text(pace)
                    .appTextRole(.caption)
                    .foregroundStyle(accentColor(for: stepResult.step.kind))
                    .monospacedDigit()
            }
        }
    }

    private func planText(for step: RunWorkoutStep) -> String {
        var parts = ["Plan \(step.goalText(metric: metric))"]
        if let target = step.targetText(metric: metric) {
            parts.append(target)
        }
        return parts.joined(separator: " · ")
    }

    private func accentColor(for kind: RunWorkoutStep.Kind) -> Color {
        switch kind {
        case .hard:
            return AppPalette.caution
        case .recovery:
            return AppPalette.recovery
        case .cooldown:
            return AppPalette.positive
        case .warmup:
            return AppPalette.brand
        }
    }
}

private struct RunRecorderSummary: View {
    let run: Run
    let metric: Bool
    let setRecord: Bool
    let workoutPlanName: String?
    let workoutResult: RunWorkoutResult?
    let saveState: RunRecorderViewModel.SaveState
    let planProgressMessage: String?
    let workoutReceiptMessage: String?
    let onRetryReceipt: () -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    @State private var showingCelebration = false
    @State private var hasCelebrated = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run complete")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                    if setRecord {
                        Text("🏅 New record — see the Records card in your history.")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(.brandForeground)
                    }
                    if let workoutPlanName {
                        Text(workoutPlanName)
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(.brandForeground)
                    }
                    Text(saveState.message)
                        .appFont(size: 13)
                        .foregroundColor(saveState == .failed ? AppPalette.critical : Color(UIColor.secondaryLabel))
                        .accessibilityIdentifier("run_save_status")
                    if let planProgressMessage {
                        Text(planProgressMessage).appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    if let workoutReceiptMessage {
                        Text(workoutReceiptMessage).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                        Button("Retry workout steps", action: onRetryReceipt)
                            .accessibilityIdentifier("run_retry_step_receipt")
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryTile(RunFormat.distanceText(meters: run.distanceMeters, metric: metric), "Distance")
                    if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: metric) {
                        summaryTile(pace, "Avg pace")
                    }
                }

                RunTimingSummaryCard(run: run, accessibilityPrefix: "run_summary_timing")
                if let laps = run.manualLaps, !laps.isEmpty { RunManualLapsCard(laps: laps, metric: metric) }

                if let workoutResult {
                    RunWorkoutResultCard(result: workoutResult, metric: metric)
                }

                if !run.splits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Splits")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.textPrimary)
                        ForEach(run.splits, id: \.index) { split in
                            HStack {
                                Text("\(split.index) · \(RunFormat.distanceText(meters: split.distanceMeters, metric: metric))")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                Spacer()
                                Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: metric) ?? RunFormat.durationText(seconds: split.seconds))
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(.textPrimary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .appSurface(.emphasized)
                }

                if saveState == .failed || saveState == .localRecoveryPending {
                    Button("Retry save", action: onRetry)
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("run_retry_save")
                } else {
                    if saveState == .localOnly || saveState == .routeSyncPending || saveState == .healthConfirmationPending || saveState == .healthConfirmationUnknown {
                        Button(saveState == .healthConfirmationPending || saveState == .healthConfirmationUnknown ? "Check Health status" : "Retry Health sync", action: onRetry)
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityIdentifier("run_retry_health_sync")
                    }
                    Button("Done", action: onDone)
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(!saveState.isSaved)
                        .accessibilityIdentifier("run_summary_done")
                }
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_recorder_summary")
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { celebrateIfNeeded() }
        .onChange(of: setRecord) { _, _ in celebrateIfNeeded() }
        .celebrationOverlay(type: .routePR, isPresented: $showingCelebration)
    }

    private func celebrateIfNeeded() {
        guard setRecord, !hasCelebrated else { return }
        hasCelebrated = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showingCelebration = true }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
            Text(label)
                .appFont(size: 11, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.emphasized)
    }
}

/// The run audio coach. Antigravity's original spoke split announcements but left the
/// audio session active in `.playback` after every one — which ducks the runner's music
/// and never lets it back up for the rest of the run. This owns the synthesizer, and as
/// its delegate deactivates the session with `.notifyOthersOnDeactivation` the moment
/// speech finishes, so music returns to full volume between kilometers.
@MainActor
final class RunAudioCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtteranceID: ObjectIdentifier?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        // Calls, route changes and media resets invalidate queued guidance. The
        // recorder keeps running; an old prompt is never resumed into a new step.
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if name == AVAudioSession.routeChangeNotification {
                    guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                          let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                          reason == .oldDeviceUnavailable || reason == .newDeviceAvailable || reason == .override else { return }
                }
                Task { @MainActor in self?.stop() }
            })
        }
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    @discardableResult
    func announce(_ text: String, interruptCurrent: Bool = true) -> Bool {
        guard interruptCurrent || !synthesizer.isSpeaking else { return false }
        // Invalidate the old callback before stopping it so its late cancellation
        // cannot unduck music underneath the replacement utterance.
        currentUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLog.workouts.error("Run audio coach session activation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        currentUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        currentUtteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        Self.deactivateSession()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ identity: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, currentUtteranceID == identity else { return }
            currentUtteranceID = nil
            Self.deactivateSession()
        }
    }

    private nonisolated static func deactivateSession() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {
            AppLog.workouts.error("Run audio coach session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct RunRecoveredRoutePreview: View {
    let segments: [[RunLocationFix]]
    var body: some View {
        Map(interactionModes: []) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, fixes in
                if fixes.count > 1 {
                    MapPolyline(coordinates: fixes.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(Color.brandPrimary, lineWidth: 3)
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded route segments; interruptions are left as gaps")
        .accessibilityIdentifier("run_recovered_route_map")
    }
}

private struct RunGoalRevisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let step: RunWorkoutStep
    let metric: Bool
    let activeSeconds: Double
    let distanceMeters: Double
    let apply: (RunWorkoutStep.Goal, String) -> String?
    @State private var minutes: String
    @State private var seconds: String
    @State private var distance: String
    @State private var operationID = UUID().uuidString
    @State private var error: String?
    private let originalMinutes: String
    private let originalSeconds: String
    private let originalDistance: String

    init(step: RunWorkoutStep, metric: Bool, activeSeconds: Double, distanceMeters: Double,
         apply: @escaping (RunWorkoutStep.Goal, String) -> String?) {
        self.step = step
        self.metric = metric
        self.activeSeconds = activeSeconds
        self.distanceMeters = distanceMeters
        self.apply = apply
        var minuteText = "30"
        var secondText = "0"
        var distanceText = "5"
        switch step.goal {
        case .duration(let value):
            if value.isFinite, value >= 0, value <= 86_400 {
                minuteText = String(Int(value) / 60)
                secondText = String(Int(value) % 60)
            }
        case .distance(let value):
            distanceText = String(format: "%.3f", value / (metric ? 1000 : RunFormat.metersPerMile))
        case .open: break
        }
        originalMinutes = minuteText
        originalSeconds = secondText
        originalDistance = distanceText
        _minutes = State(initialValue: minuteText)
        _seconds = State(initialValue: secondText)
        _distance = State(initialValue: distanceText)
    }

    var body: some View {
        AppEditorScaffold(title: "Review goal change", subtitle: "Your run stays paused while you review.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                LabeledContent("Current goal", value: step.goalText(metric: metric))
                LabeledContent("Recorded", value: "\(RunFormat.durationText(seconds: activeSeconds)) · \(RunFormat.distanceText(meters: distanceMeters, metric: metric))")
                if case .duration = step.goal {
                    HStack {
                        TextField("Minutes", text: $minutes).keyboardType(.numberPad)
                        Text("min")
                        TextField("Seconds", text: $seconds).keyboardType(.numberPad)
                        Text("sec")
                    }
                    .textFieldStyle(.roundedBorder)
                } else {
                    TextField(metric ? "Distance (km)" : "Distance (mi)", text: $distance)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                }
                if let proposed {
                    LabeledContent("New goal", value: RunWorkoutStep(kind: .hard, title: "Goal", goal: proposed).goalText(metric: metric))
                }
                Text("Choose a target beyond your recorded position. Your original goal and the time of this change stay in the completed receipt. Achieved goals cannot be rewritten.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if let error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }
        } actions: {
            Button("Apply while paused") {
                guard let proposed else { return }
                error = apply(proposed, operationID)
                if error == nil { dismiss() }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(proposed == nil || proposed == step.goal)
            .accessibilityIdentifier("run_goal_revision_apply")
        }
        .onChange(of: minutes) { _, _ in operationID = UUID().uuidString }
        .onChange(of: seconds) { _, _ in operationID = UUID().uuidString }
        .onChange(of: distance) { _, _ in operationID = UUID().uuidString }
    }

    private var proposed: RunWorkoutStep.Goal? {
        let goal: RunWorkoutStep.Goal
        switch step.goal {
        case .duration:
            if minutes == originalMinutes, seconds == originalSeconds { return step.goal }
            guard let minuteValue = Int(minutes), let secondValue = Int(seconds),
                  (0...1440).contains(minuteValue), (0...59).contains(secondValue) else { return nil }
            goal = .duration(seconds: Double(minuteValue * 60 + secondValue))
        case .distance:
            if distance == originalDistance { return step.goal }
            guard let value = Double(distance.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")), value.isFinite else { return nil }
            goal = .distance(meters: value * (metric ? 1000 : RunFormat.metersPerMile))
        case .open: return nil
        }
        return RunWorkoutGoalRevision.isSupported(goal, beyondSeconds: activeSeconds, beyondMeters: distanceMeters) ? goal : nil
    }
}
