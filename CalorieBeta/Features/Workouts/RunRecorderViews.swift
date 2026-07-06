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
    private let metric: Bool
    private let audioCoach = RunAudioCoach()
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

    init(metric: Bool) {
        self.metric = metric
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

    func begin() {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            session.start()
            locationService.startTracking()
            startTimer()
            stage = .running
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
            isPaused: stage == .paused
        )
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
        pushLiveActivity()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.stage == .running else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct RunRecorderView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @StateObject private var viewModel: RunRecorderViewModel
    @State private var showingDiscardAlert = false

    init() {
        let metric = UserDefaults.standard.object(forKey: "useMetricBodyUnits") as? Bool
            ?? (Locale.current.measurementSystem != .us)
        _viewModel = StateObject(wrappedValue: RunRecorderViewModel(metric: metric))
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
                    RunRecorderSummary(run: run, metric: useMetric, setRecord: viewModel.finishedSetRecord) { dismiss() }
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

    private var permissionView: some View {
        VStack(spacing: 12) {
            Text("🏃")
                .font(.system(size: 44))
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
        .navigationTitle(viewModel.stage == .paused ? "Paused" : "Running")
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

private struct RunRecorderSummary: View {
    let run: Run
    let metric: Bool
    let setRecord: Bool
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
                    .asCard()
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
        .asCard()
    }
}

/// The run audio coach. Antigravity's original spoke split announcements but left the
/// audio session active in `.playback` after every one — which ducks the runner's music
/// and never lets it back up for the rest of the run. This owns the synthesizer, and as
/// its delegate deactivates the session with `.notifyOthersOnDeactivation` the moment
/// speech finishes, so music returns to full volume between kilometers.
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
        deactivateSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivateSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivateSession()
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLog.workouts.error("Run audio coach session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
