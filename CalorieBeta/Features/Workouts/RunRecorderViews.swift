import SwiftUI
import CoreLocation
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

    let locationService = RunLocationService()
    private(set) var session: RunSession
    private var rawLocations: [CLLocation] = []
    private var timer: Timer?
    private let store = RunRecorderStore()
    private let workoutResultStore = RunWorkoutResultStore()
    private let metric: Bool
    let workoutPlan: RunWorkoutPlan?
    private var workoutTracker: RunWorkoutTracker?
    private let audioCoach = RunAudioCoach()
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
    #endif

    init(metric: Bool, workoutPlan: RunWorkoutPlan? = nil) {
        self.metric = metric
        self.workoutPlan = workoutPlan
        self.workoutTracker = workoutPlan.map(RunWorkoutTracker.init)
        session = RunSession(metric: metric)
        locationService.onLocation = { [weak self] location in
            Task { @MainActor in
                self?.ingest(location)
            }
        }
        session.onSplitCompleted = { [weak self] split in
            Task { @MainActor in
                self?.speakSplitAnnouncement(split)
            }
        }
    }

    var distanceMeters: Double { session.distanceMeters }
    var currentPace: Double? { session.currentPaceSecondsPerKm }
    var averagePace: Double? { session.averagePaceSecondsPerKm }

    private func speakSplitAnnouncement(_ split: RunSplit) {
        guard audioCoachEnabled else { return }
        let unit = metric ? "kilometer" : "mile"
        let distanceText = "\(split.index) \(unit)\(split.index == 1 ? "" : "s") completed."

        let paceMinutes = Int(split.seconds / 60)
        let paceSeconds = Int(split.seconds.truncatingRemainder(dividingBy: 60))
        let paceText = "Split pace: \(paceMinutes) minutes and \(paceSeconds) seconds per \(unit)."

        let totalText = "Total time: \(RunFormat.durationText(seconds: session.movingSeconds))."

        audioCoach.announce("\(distanceText) \(paceText) \(totalText)")
    }

    private func speakWorkoutStep(_ progress: RunWorkoutProgress) {
        guard audioCoachEnabled, let step = progress.currentStep else { return }
        let targetText = step.targetText(metric: metric).map { " \($0)." } ?? ""
        audioCoach.announce("\(step.title). \(step.goalText(metric: metric)).\(targetText)")
    }

    func begin() {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            session.start()
            locationService.startTracking()
            startTimer()
            stage = .running
            refreshWorkoutProgress(announceTransitions: false)
            startLiveActivity()
            HapticsService.shared.playImpact(style: .medium)
        case .notDetermined:
            stage = .permission
            locationService.requestPermission()
        default:
            stage = .permission
        }
    }

    func pause() {
        session.pause()
        stage = .paused
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
    }

    func resume() {
        session.resume()
        stage = .running
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
    }

    func finish(weightLbs: Double) {
        locationService.stopTracking()
        stopTimer()
        endLiveActivity()
        audioCoach.stop()
        guard let run = session.finish() else { return }
        ActivationFunnel.recordTrainingCompletion(.recordedRun)
        stage = .saving

        store.save(run: run, locations: rawLocations, weightLbs: weightLbs) { [weak self] savedID in
            guard let self else { return }
            if savedID == nil {
                ToastManager.shared.showToast(message: "Saved locally, but Health sync failed.")
            }
            // New recordings get the CURRENT default shoe stamped at save time — history
            // is never retroactively re-tagged when the default changes.
            if let savedID {
                let shoeStore = RunningShoeStore()
                shoeStore.tagRun(runID: savedID, withShoeID: shoeStore.defaultShoe()?.id)
            }
            if let workoutResult = self.workoutTracker?.result(
                runID: savedID ?? run.id,
                completedAt: Date(),
                elapsedSeconds: self.elapsedSeconds,
                distanceMeters: self.distanceMeters
            ) {
                self.workoutResultStore.save(workoutResult)
                self.finishedWorkoutResult = workoutResult
            }
            // Records are judged against strictly-past runs so the just-saved copy of
            // this run (different HK UUID, same stats) can't mask its own achievement.
            let since = Calendar.current.date(byAdding: .year, value: -1, to: run.startDate) ?? run.startDate
            RunImportService().fetchRuns(since: since) { history in
                let past = history.filter { $0.endDate <= run.startDate }
                self.finishedSetRecord = RunStats.setsRecord(run, against: past + [run])
                HapticManager.instance.notification(.success)
                self.stage = .summary(run)
            }
        }
    }

    func discard() {
        locationService.stopTracking()
        stopTimer()
        endLiveActivity()
        audioCoach.stop()
    }

    // MARK: Live Activity

    private func startLiveActivity() {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            liveActivity = try Activity.request(
                attributes: RunActivityAttributes(),
                content: .init(state: activityState(), staleDate: nil)
            )
        } catch {
            AppLog.liveActivity.error("Run Live Activity failed to start: \(error.localizedDescription, privacy: .public)")
        }
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
        Task {
            await liveActivity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
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
        RunActivityAttributes.ContentState(
            startTime: Date().addingTimeInterval(-elapsedSeconds),
            distanceText: RunFormat.distanceText(meters: distanceMeters, metric: metric),
            paceText: RunFormat.paceText(secondsPerKm: currentPace ?? averagePace, metric: metric) ?? "— pace",
            elapsedText: RunFormat.durationText(seconds: elapsedSeconds),
            isPaused: stage == .paused,
            workoutStepText: liveWorkoutStepText,
            workoutTargetText: liveWorkoutTargetText
        )
    }

    private var liveWorkoutStepText: String? {
        guard let progress = workoutProgress else { return nil }
        guard let step = progress.currentStep else { return "Workout complete" }
        return "\(progress.currentStepIndex + 1)/\(progress.stepCount) \(step.title)"
    }

    private var liveWorkoutTargetText: String? {
        guard let progress = workoutProgress, let step = progress.currentStep else { return nil }
        return step.targetText(metric: metric) ?? step.goalText(metric: metric)
    }
    #endif

    private func ingest(_ location: CLLocation) {
        guard stage == .running else { return }
        rawLocations.append(location)
        session.ingest(RunLocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        ))
        tick += 1
        refreshWorkoutProgress()
        pushLiveActivity()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.stage == .running else { return }
                self.elapsedSeconds += 1
                self.refreshWorkoutProgress()
            }
        }
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

        guard announceTransitions,
              let previousStepIndex,
              progress.currentStepIndex != previousStepIndex else { return }
        pushLiveActivity(force: true)
        HapticsService.shared.playImpact(style: .light)
        speakWorkoutStep(progress)
    }
}

struct RunRecorderView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @StateObject private var viewModel: RunRecorderViewModel
    @State private var showingDiscardAlert = false
    @State private var reconciledTrainingFuelRunID: String?

    init(plan: RunWorkoutPlan? = nil) {
        let metric = UserDefaults.standard.object(forKey: "useMetricBodyUnits") as? Bool
            ?? (Locale.current.measurementSystem != .us)
        _viewModel = StateObject(wrappedValue: RunRecorderViewModel(metric: metric, workoutPlan: plan))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.stage {
                case .permission:
                    permissionView
                case .ready:
                    ProgressView()
                        .onAppear { viewModel.begin() }
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
                        workoutResult: viewModel.finishedWorkoutResult
                    ) { dismiss() }
                    .onAppear { reconcileTrainingFuel(for: run) }
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .toolbar {
                if viewModel.stage == .permission {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .onChange(of: viewModel.locationService.authorizationStatus) { _, status in
                if viewModel.stage == .permission,
                   status == .authorizedWhenInUse || status == .authorizedAlways {
                    viewModel.begin()
                }
            }
        }
        .interactiveDismissDisabled(viewModel.stage == .running || viewModel.stage == .paused)
    }

    private func reconcileTrainingFuel(for run: Run) {
        guard reconciledTrainingFuelRunID != run.id else { return }
        reconciledTrainingFuelRunID = run.id
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
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppPalette.effort)
                .frame(width: 64, height: 64)
                .background(AppPalette.effort.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)
            Text("Location makes this a run tracker")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.locationService.authorizationStatus == .denied
                 ? "Location is off for MyFitPlate. Enable it in Settings to record runs."
                 : "Your route, distance, and pace come from GPS while you run. Nothing is tracked outside a recording.")
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)

            if viewModel.locationService.authorizationStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.brandPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(30)
    }

    private var liveView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text(RunFormat.durationText(seconds: viewModel.elapsedSeconds))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.textPrimary)
                        .contentTransition(.numericText())
                    Text("Time")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                HStack(spacing: 0) {
                    liveMetric(RunFormat.distanceText(meters: viewModel.distanceMeters, metric: useMetric), "Distance")
                    liveMetric(RunFormat.paceText(secondsPerKm: viewModel.currentPace, metric: useMetric) ?? "—", "Pace")
                    liveMetric(RunFormat.paceText(secondsPerKm: viewModel.averagePace, metric: useMetric) ?? "—", "Avg pace")
                }

                if let progress = viewModel.workoutProgress {
                    RunWorkoutGuidanceCard(progress: progress, metric: useMetric)
                        .padding(.horizontal)
                }

                Button {
                    viewModel.audioCoachEnabled.toggle()
                } label: {
                    Label(
                        viewModel.audioCoachEnabled ? "Audio coach on" : "Audio coach off",
                        systemImage: viewModel.audioCoachEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(viewModel.audioCoachEnabled ? .brandPrimary : Color(UIColor.secondaryLabel))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.backgroundSecondary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.audioCoachEnabled ? "Turn audio coach off" : "Turn audio coach on")
            }
            .id(viewModel.tick)

            Spacer()

            HStack(spacing: 14) {
                Button {
                    viewModel.stage == .running ? viewModel.pause() : viewModel.resume()
                } label: {
                    Image(systemName: viewModel.stage == .running ? "pause.fill" : "play.fill")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .frame(width: 64, height: 64)
                        .background(Color.backgroundSecondary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.stage == .running ? "Pause run" : "Resume run")

                Button {
                    if viewModel.distanceMeters < 50 {
                        showingDiscardAlert = true
                    } else {
                        viewModel.finish(weightLbs: goalSettings.weight)
                    }
                } label: {
                    Text("Finish run")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .navigationTitle(viewModel.stage == .paused ? "Paused" : (viewModel.workoutPlan?.name ?? "Running"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nothing to save yet", isPresented: $showingDiscardAlert) {
            Button("Keep running", role: .cancel) {}
            Button("Discard", role: .destructive) {
                viewModel.discard()
                dismiss()
            }
        } message: {
            Text("This run is under 50 meters. Discard it?")
        }
    }

    private func liveMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .appFont(size: 11, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RunWorkoutGuidanceCard: View {
    let progress: RunWorkoutProgress
    let metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.planName)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text(title)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                Text(stepCountText)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            ProgressView(value: progress.progressFraction)
                .tint(accentColor)

            if let targetText {
                Text(targetText)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(accentColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(progress.currentStep?.goalText(metric: metric) ?? "Done")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Spacer()
                Text(remainingText)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        guard let step = progress.currentStep else { return "Workout complete" }
        return "\(step.kind.displayName) · \(step.title)"
    }

    private var targetText: String? {
        progress.currentStep?.targetText(metric: metric)
    }

    private var stepCountText: String {
        guard !progress.isWorkoutComplete else { return "\(progress.stepCount)/\(progress.stepCount)" }
        return "\(progress.currentStepIndex + 1)/\(progress.stepCount)"
    }

    private var remainingText: String {
        if progress.isWorkoutComplete { return "Complete" }
        if let seconds = progress.remainingSeconds {
            return "\(RunFormat.durationText(seconds: seconds)) left"
        }
        if let meters = progress.remainingMeters {
            return "\(RunFormat.distanceText(meters: meters, metric: metric)) left"
        }
        return ""
    }

    private var accentColor: Color {
        switch progress.currentStep?.kind {
        case .hard:
            return AppPalette.caution
        case .recovery:
            return AppPalette.recovery
        case .cooldown:
            return AppPalette.positive
        case .warmup, .none:
            return AppPalette.brand
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
                Text("\(result.steps.filter(\.isComplete).count) of \(result.steps.count) complete")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brand)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(result.steps) { stepResult in
                stepRow(stepResult)
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_workout_steps")
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
                    Label("Partial", systemImage: "circle.lefthalf.filled")
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
    let onDone: () -> Void

    @State private var showingCelebration = false

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
                            .foregroundColor(.brandPrimary)
                    }
                    if let workoutPlanName {
                        Text(workoutPlanName)
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                    }
                    Text("Saved to Apple Health — it's in your run history now.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summaryTile(RunFormat.distanceText(meters: run.distanceMeters, metric: metric), "Distance")
                    summaryTile(RunFormat.durationText(seconds: run.movingSeconds), "Moving time")
                    if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: metric) {
                        summaryTile(pace, "Avg pace")
                    }
                    summaryTile("\(run.splits.count)", metric ? "Kilometers" : "Miles")
                }

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
                                Text("\(split.index)")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .frame(width: 24, alignment: .leading)
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

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The summary is a one-shot screen (seen once per finished run), so a plain
            // on-appear guard is enough — no per-day persistence needed.
            guard setRecord else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingCelebration = true
            }
        }
        .celebrationOverlay(type: .routePR, isPresented: $showingCelebration)
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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ text: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLog.workouts.error("Run audio coach session activation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        Self.deactivateSession()
    }

    // The delegate callbacks stay `nonisolated`: AVSpeechSynthesizerDelegate is not main-actor
    // isolated, so isolating these to the main actor makes the conformance cross actors (a data-race
    // warning, and an error in Swift 6). They only tear the session down, which is thread-agnostic.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Self.deactivateSession()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Self.deactivateSession()
    }

    /// Releasing the audio session touches only `AVAudioSession`, which is safe off the main actor,
    /// so this is a `nonisolated static` both the main-actor `stop()` and the delegate callbacks can call.
    private nonisolated static func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLog.workouts.error("Run audio coach session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
