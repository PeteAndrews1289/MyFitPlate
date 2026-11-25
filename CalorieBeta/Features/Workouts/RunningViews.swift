import SwiftUI
import MapKit
import Charts
import AppIntents
import MyFitPlateCore

private extension Notification.Name {
    static let runLaunchShortcutRequested = Notification.Name("myfitplate.run.launch-shortcut")
}

/// A launch request only opens preparation; it never starts or replaces a run.
@MainActor private enum RunLaunchShortcutInbox {
    private static let key = "myfitplate.run.launch-request.v1"
    static func request(_ action: String) async {
        UserDefaults.standard.set(["action": action, "requestedAt": Date().timeIntervalSince1970], forKey: key)
        if let url = URL(string: "myfitplate://runs") { await UIApplication.shared.open(url) }
        NotificationCenter.default.post(name: .runLaunchShortcutRequested, object: nil)
    }
    static func take(now: Date = Date()) -> String? {
        guard let value = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        guard let action = value["action"] as? String, ["prepare", "workouts", "history"].contains(action),
              let time = value["requestedAt"] as? Double, time.isFinite,
              (0...300).contains(now.timeIntervalSince1970 - time) else { return nil }
        return action
    }
}

struct OpenRunningHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open running history"
    static var description = IntentDescription("Open your MyFitPlate running history.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        await RunLaunchShortcutInbox.request("history")
        return .result()
    }
}

struct PrepareRunningIntent: AppIntent {
    static var title: LocalizedStringResource = "Prepare a run"
    static var description = IntentDescription("Open GPS readiness or recover your existing run. Recording starts only after you confirm in the app.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        await RunLaunchShortcutInbox.request("prepare")
        return .result()
    }
}

struct ChooseRunningWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Choose a running workout"
    static var description = IntentDescription("Open your favorite goals and running workouts for review.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        await RunLaunchShortcutInbox.request("workouts")
        return .result()
    }
}

struct RunningAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PrepareRunningIntent(), phrases: ["Prepare a run in \(.applicationName)"], shortTitle: "Prepare a run", systemImageName: "figure.run")
        AppShortcut(intent: ChooseRunningWorkoutIntent(), phrases: ["Choose a running workout in \(.applicationName)"], shortTitle: "Running workouts", systemImageName: "list.bullet")
        AppShortcut(intent: OpenRunningHistoryIntent(), phrases: ["Open running history in \(.applicationName)"], shortTitle: "Running history", systemImageName: "clock")
    }
}

// Running history + detail. Health workouts are reconciled with durable local saves
// so exact active time and splits remain available when Health read access is absent.

@MainActor
final class RunHistoryViewModel: ObservableObject {
    @Published var runs: [Run] = []
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var historyScopeNote: String?
    private var loadGeneration = UUID()
    private var loadedOwnerID: String?

    private let importer = RunImportService()
    private let fixtureRuns: [Run]?

    init(fixtureRuns: [Run]? = nil) {
        self.fixtureRuns = fixtureRuns
        if let fixtureRuns {
            runs = fixtureRuns
            isLoading = false
        }
    }

    func load() {
        guard fixtureRuns == nil else { return }
        guard let owner = DIContainer.shared.authService.currentUserID else {
            runs = []; loadedOwnerID = nil; historyScopeNote = nil; loadError = nil; isLoading = false; return
        }
        if loadedOwnerID != owner {
            loadedOwnerID = owner
            isLoading = true
            runs = RunFallbackStore.shared.runs(since: .distantPast, for: owner)
            if let cached = try? RunHistorySnapshotStore().load(userID: owner) {
                runs = RunningShoeStore().applyTags(to: RunLocalHistoryRules.merging(healthRuns: cached.runs, localRuns: runs))
                historyScopeNote = "Cached available history from \(cached.capturedAt.formatted(date: .abbreviated, time: .shortened))\(cached.isTruncated ? "; oldest records were not cached" : ""). Refreshing…"
            } else { historyScopeNote = runs.isEmpty ? nil : "Saved recordings on this device. Checking available Apple Health history…" }
            do { runs = try RunReviewStore().projecting(runs, userID: owner) } catch { runs = []; loadError = "Run reviews could not be read. Retry before showing corrected history." }
        }
        let request = UUID(); loadGeneration = request
        loadError = nil
        HealthKitManager.shared.requestAuthorization { [weak self] _, _ in
            guard let self else { return }
            guard self.loadGeneration == request, DIContainer.shared.authService.currentUserID == owner else { return }
            self.importer.fetchLifetimeRuns(userID: owner) { result in
                guard self.loadGeneration == request, DIContainer.shared.authService.currentUserID == owner else { return }
                switch result {
                case .success(let runs):
                    self.runs = RunningShoeStore().applyTags(to: runs)
                    self.historyScopeNote = "All currently available Health runs and saved recordings. Health access can limit imported coverage."
                    do { try RunHistorySnapshotStore().save(runs, userID: owner) } catch { self.loadError = "History refreshed, but its offline copy could not be updated." }
                case .failure:
                    let local = RunFallbackStore.shared.runs(since: .distantPast, for: owner)
                    if let reviewed = try? RunReviewStore().projecting(RunLocalHistoryRules.merging(healthRuns: self.runs, localRuns: local), userID: owner) {
                        self.runs = RunningShoeStore().applyTags(to: reviewed)
                    }
                    self.historyScopeNote = "Previously loaded history and saved recordings. Imported totals may be out of date."
                    self.loadError = "Running history could not refresh. Saved recordings remain available; retry to reconcile Apple Health."
                }
                self.isLoading = false
            }
        }
    }

    var thisWeekMeters: Double {
        runs.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var thisWeekCount: Int {
        runs.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    var thisWeekMovingSeconds: Double {
        runs.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .weekOfYear) }
            .reduce(0) { $0 + max(0, $1.movingSeconds) }
    }

    var records: RunStats.PersonalRecords {
        RunStats.personalRecords(from: runs)
    }
}

struct RunHistoryView: View {
    @StateObject private var viewModel: RunHistoryViewModel
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var recorderDestination: RunRecorderDestination?
    @State private var showingRunStartSheet = false
    @State private var showingGearManager = false
    @State private var showingRecords = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingTreadmillEntry = false
    @State private var pendingLaunch: RunLaunchDestination?
    @State private var hasRecoverableRecording = false
    @State private var visibleHistoryCount = 50
    @State private var historyScope = RunHistoryScope()
    @State private var showingTrainingPlan = false
    @State private var showingRunReviews = false
    @State private var showingCloudSync = false

    private enum RunLaunchDestination { case outdoor(RunWorkoutPlan?), treadmill }

    private struct RunRecorderDestination: Identifiable {
        let id = UUID()
        let plan: RunWorkoutPlan?
    }

    init() {
        #if DEBUG
        let fixtureRuns = ScreenshotDemoMode.isEnabled ? ScreenshotDemoData.runningDemoRuns : nil
        _viewModel = StateObject(wrappedValue: RunHistoryViewModel(fixtureRuns: fixtureRuns))
        #else
        _viewModel = StateObject(wrappedValue: RunHistoryViewModel())
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                runActions
                Button { showingTrainingPlan = true } label: {
                    Label("Training plan", systemImage: "calendar")
                        .appTextRole(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("run_training_plan")

                if let error = viewModel.loadError {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(error).appTextRole(.secondary)
                        Button("Retry running history") { viewModel.load() }
                    }.appSurface(.quiet)
                }

                if let scope = viewModel.historyScopeNote {
                    Text(scope).appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("run_history_scope")
                }
                if !viewModel.runs.isEmpty {
                    weekHero
                    RunHistoryFilterControls(scope: $historyScope, sources: RunHistoryScope.sources(in: viewModel.runs))
                    recentRuns
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if viewModel.loadError == nil {
                    emptyState
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("run_history_screen")
        .navigationTitle("Running")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: RunMapView(runs: viewModel.runs, scope: historyScope)) {
                    Image(systemName: "map")
                }
                .accessibilityLabel("Route map")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Shoes", systemImage: "shoeprints.fill") {
                        HapticManager.instance.feedback(.light)
                        showingGearManager = true
                    }
                    .accessibilityLabel("Shoe Gear Manager")
                    Button("Running sync", systemImage: "icloud") { showingCloudSync = true }
                        .accessibilityIdentifier("run_cloud_sync")
                    Button("Run reviews", systemImage: "clock.arrow.circlepath") { showingRunReviews = true }
                        .accessibilityIdentifier("run_history_reviews")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Running options")
                .accessibilityIdentifier("run_history_options")
            }
        }
        .sheet(isPresented: $showingRecords) { recordsPage }
        .sheet(isPresented: $showingCloudSync) { RunCloudSyncView() }
        .sheet(isPresented: $showingTrainingPlan, onDismiss: refreshHistory) { RunTrainingBlockView() }
        .sheet(isPresented: $showingRunReviews) {
            if let owner = DIContainer.shared.authService.currentUserID {
                RunReviewHistorySheet(ownerID: owner, onChanged: refreshHistory)
            }
        }
        .onAppear(perform: refreshHistory)
        .onReceive(NotificationCenter.default.publisher(for: .runLibrariesChanged)) { notification in
            guard notification.object as? String == DIContainer.shared.authService.currentUserID else { return }
            viewModel.load()
        }
        .onAppear(perform: receiveRunShortcut)
        .onReceive(NotificationCenter.default.publisher(for: .runLaunchShortcutRequested)) { _ in receiveRunShortcut() }
        .onChange(of: historyScope) { _, _ in visibleHistoryCount = 50 }
        .fullScreenCover(item: $recorderDestination, onDismiss: refreshHistory) { destination in
            RunRecorderView(plan: destination.plan)
        }
        .sheet(isPresented: $showingRunStartSheet, onDismiss: finishRunLaunch) {
            RunWorkoutPickerSheet(
                metric: useMetric,
                onStart: { plan in
                    pendingLaunch = .outdoor(plan)
                    showingRunStartSheet = false
                },
                onLogTreadmill: {
                    pendingLaunch = .treadmill
                    showingRunStartSheet = false
                }
            )
        }
        .sheet(isPresented: $showingTreadmillEntry, onDismiss: { viewModel.load() }) {
            TreadmillRunEntrySheet(metric: useMetric) {
                viewModel.load()
            }
        }
        .sheet(isPresented: $showingGearManager, onDismiss: { viewModel.load() }) {
            ShoeGearManagerView(runs: viewModel.runs)
        }
    }

    private func refreshHistory() {
        viewModel.load()
        guard let userID = DIContainer.shared.authService.currentUserID else {
            hasRecoverableRecording = false
            return
        }
        do { hasRecoverableRecording = try RunRecordingDraftStore().load(userID: userID) != nil } catch {
            hasRecoverableRecording = true
        }
    }

    private func finishRunLaunch() {
        switch pendingLaunch {
        case .outdoor(let plan): recorderDestination = RunRecorderDestination(plan: plan)
        case .treadmill: showingTreadmillEntry = true
        case nil: break
        }
        pendingLaunch = nil
    }

    private func receiveRunShortcut() {
        guard DIContainer.shared.authService.currentUserID != nil,
              recorderDestination == nil, !showingRunStartSheet,
              let action = RunLaunchShortcutInbox.take() else { return }
        if action == "workouts" { showingRunStartSheet = true } else if action == "prepare" { recorderDestination = RunRecorderDestination(plan: nil) }
    }

    private var runActions: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
            Button {
                // Preparation still checks permissions/GPS and restores a saved run.
                // Opening this destination never starts a fresh recording implicitly.
                recorderDestination = RunRecorderDestination(plan: nil)
            } label: {
                Label(hasRecoverableRecording ? "Resume run" : "Open run", systemImage: "figure.run")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityHint(hasRecoverableRecording ? "Recover your saved recording." : "Review GPS readiness before starting an outdoor run.")
            .accessibilityIdentifier("run_history_start")

            Button { showingRunStartSheet = true } label: {
                Label("Workouts", systemImage: "list.bullet")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Choose a running workout")
            .accessibilityHint(hasRecoverableRecording ? "Resume or resolve your saved recording before choosing another workout." : "Choose a goal, guided workout or treadmill entry.")
            .disabled(hasRecoverableRecording)
            .accessibilityIdentifier("run_history_workouts")
        }
    }

    private var filteredRuns: [Run] { historyScope.filtered(viewModel.runs) }
    private var selectedWeekRuns: [Run] {
        var scope = historyScope
        scope.period = .week; scope.query = ""; scope.environment = .all; scope.source = nil
        return scope.filtered(viewModel.runs)
    }
    private var selectedWeekLabel: String {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: historyScope.selectedWeek) else { return "Selected week" }
        return interval.start.formatted(date: .abbreviated, time: .omitted) + " – " + interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
    }

    private var weekHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedWeekLabel).appTextRole(.caption).foregroundStyle(.secondary)
                    Text("\(RunFormat.distanceText(meters: selectedWeekRuns.reduce(0) { $0 + $1.distanceMeters }, metric: useMetric)) · \(selectedWeekRuns.count.formatted()) \(selectedWeekRuns.count == 1 ? "run" : "runs")")
                        .appTextRole(.control).foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppSpacing.compact)
                Button { showingRecords = true } label: {
                    Label("Records", systemImage: "rosette")
                        .appTextRole(.secondary).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.text)
                .accessibilityIdentifier("run_history_open_records")
            }
            HStack {
                Button("Previous week", systemImage: "chevron.left") { moveWeek(-1) }
                Spacer()
                Button("This week") { historyScope.selectedWeek = Date(); historyScope.period = .week }
                Spacer()
                Button("Next week", systemImage: "chevron.right") { moveWeek(1) }
                    .disabled(Calendar.current.isDate(historyScope.selectedWeek, equalTo: Date(), toGranularity: .weekOfYear))
            }.appTextRole(.caption).buttonStyle(.plain)
            Text("\(RunFormat.durationText(seconds: selectedWeekRuns.reduce(0) { $0 + max(0, $1.movingSeconds) })) active time")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("run_history_moving_time")
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_history_week_summary")
    }

    private func moveWeek(_ offset: Int) {
        historyScope.period = .week
        if let day = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: historyScope.selectedWeek) { historyScope.selectedWeek = day }
    }

    private var recordsPage: AnyView {
        AnyView(NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if let scope = viewModel.historyScopeNote { Text(scope).appTextRole(.caption).foregroundStyle(.secondary) }
                    if let error = viewModel.loadError { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
                    RunMeasuredRecordsCard(summary: RunMeasuredRecords.summarize(filteredRuns), runs: filteredRuns, metric: useMetric)
                    RunRecordsCard(records: RunStats.personalRecords(from: filteredRuns), metric: useMetric)
                    Text("Records use your selected history filters, including rows beyond the visible list. Clear filters for all available history. Cached history and Health access can limit coverage. Estimated 5K and 10K times use whole-run average pace, not measured best segments.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Running records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingRecords = false } }
            }
        })
    }

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader(title: "Run history", subtitle: "Showing \(min(visibleHistoryCount, filteredRuns.count).formatted()) of \(filteredRuns.count.formatted()) available runs")
                .padding(AppSpacing.group)

            Divider()
            if filteredRuns.isEmpty {
                Text("No runs match these filters. Try another date, source or search.").appTextRole(.secondary).padding(AppSpacing.group)
            }

            ForEach(Array(filteredRuns.prefix(visibleHistoryCount).enumerated()), id: \.element.id) { index, run in
                NavigationLink(destination: RunDetailView(run: run)) {
                    RunRow(run: run, metric: useMetric)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("run_history_row_\(run.id)")

                if index < min(visibleHistoryCount, filteredRuns.count) - 1 {
                    Divider()
                        .padding(.leading, 68)
                }
            }
            if visibleHistoryCount < filteredRuns.count {
                Button("Show older runs") { visibleHistoryCount += 50 }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run_history_load_older")
            }
        }
        .appSurface(.quiet, padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_history_list")
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.compact) {
            Image(systemName: "figure.run")
                .appFont(size: 34, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .accessibilityHidden(true)
            Text("No runs yet")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text("Choose Open run to record outdoors, or Workouts for a guided session or treadmill entry. Runs shared with Apple Health can appear here too.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct RunWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planStore = RunWorkoutPlanStore()
    @State private var editorRoute: RunWorkoutEditorRoute?
    @State private var previewPlan: RunWorkoutPlan?
    @State private var editAfterPreview: RunWorkoutPlan?
    @State private var useAfterEditor: RunWorkoutPlan?
    @State private var deletePlan: RunWorkoutPlan?
    @State private var showingGoalSetup = false
    @State private var goalAfterSetup: RunWorkoutPlan?
    @State private var favoriteError: String?
    let metric: Bool
    let onStart: (RunWorkoutPlan?) -> Void
    let onLogTreadmill: () -> Void

    private var templates: [RunWorkoutPlan] {
        RunWorkoutPlan.builtinTemplates(metric: metric)
    }

    var body: some View {
        AppSheetScaffold(
            title: "Choose a run",
            dismiss: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Button {
                            onStart(nil)
                        } label: {
                            startCard(
                                title: "Open run",
                                subtitle: "GPS, splits, pace, and route",
                                icon: "figure.run",
                                detail: "Outdoor",
                                interpreted: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run_open")

                        Button { showingGoalSetup = true } label: {
                            startCard(title: "Set a goal", subtitle: "Choose a time or distance target", icon: "target", detail: "Your pace, your target")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run_create_goal")

                        Button {
                            onLogTreadmill()
                        } label: {
                            startCard(
                                title: "Log treadmill",
                                subtitle: "Enter indoor distance and time",
                                icon: "figure.run.treadmill",
                                detail: "Manual"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run_log_treadmill")
                    }

                    if !planStore.customPlans.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            AppSectionHeader(
                                title: "Saved workouts",
                                subtitle: "Review the steps before you record."
                            )

                            ForEach(planStore.customPlans.sorted { planStore.isFavorite(id: $0.id) && !planStore.isFavorite(id: $1.id) }) { plan in
                                Button {
                                    previewPlan = plan
                                } label: {
                                    startCard(
                                        title: plan.name,
                                        subtitle: plan.subtitle,
                                        icon: planStore.isFavorite(id: plan.id) ? "star.fill" : "bookmark.fill",
                                        detail: detailText(for: plan)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("run_plan_\(plan.id)")
                                .contextMenu {
                                    Button(planStore.isFavorite(id: plan.id) ? "Remove favorite" : "Favorite", systemImage: "star") {
                                        toggleFavorite(plan)
                                    }
                                    Button {
                                        editorRoute = .edit(plan)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        deletePlan = plan
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    if let favoriteError { Text(favoriteError).appTextRole(.caption).foregroundStyle(AppPalette.caution) }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Guided workouts",
                            subtitle: "Use a built-in session or create a workout around your own intervals."
                        )

                        Button {
                            editorRoute = .repeatTemplate
                        } label: {
                            startCard(
                                title: "Create repeats",
                                subtitle: "Repeat one work and recovery block",
                                icon: "repeat",
                                detail: "Custom"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run_create_repeats")

                        Button {
                            editorRoute = .stepTemplate
                        } label: {
                            startCard(
                                title: "Create step-by-step",
                                subtitle: "Build a fully custom progression",
                                icon: "list.bullet.rectangle",
                                detail: "Custom"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run_create_steps")

                        ForEach(templates) { plan in
                            Button {
                                previewPlan = plan
                            } label: {
                                startCard(
                                    title: plan.name,
                                    subtitle: plan.subtitle,
                                    icon: icon(for: plan),
                                    detail: detailText(for: plan)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("run_plan_\(plan.id)")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
        }
        .sheet(isPresented: $showingGoalSetup, onDismiss: {
            if let plan = goalAfterSetup {
                previewPlan = plan
                goalAfterSetup = nil
            }
        }) {
            RunGoalSetupSheet(metric: metric) { plan in
                goalAfterSetup = plan
                showingGoalSetup = false
            }
        }
        .sheet(item: $previewPlan, onDismiss: {
            if let plan = editAfterPreview {
                editorRoute = .edit(plan)
                editAfterPreview = nil
            }
        }) { plan in
            RunWorkoutPreviewSheet(plan: plan, metric: metric, onStart: { onStart(plan) }, onEdit: planStore.customPlans.contains(where: { $0.id == plan.id }) ? {
                editAfterPreview = plan
                previewPlan = nil
            } : nil, favorite: planStore.isFavorite(id: plan.id), onFavorite: { toggleFavorite(plan) }, favoriteError: favoriteError)
        }
        .confirmationDialog("Delete saved workout?", isPresented: Binding(get: { deletePlan != nil }, set: { if !$0 { deletePlan = nil } })) {
            Button("Delete workout", role: .destructive) {
                if let plan = deletePlan { planStore.deletePlan(id: plan.id) }
                deletePlan = nil
            }
        } message: {
            Text("Completed runs stay in your history.")
        }
        .sheet(item: $editorRoute, onDismiss: {
            if let plan = useAfterEditor { previewPlan = plan; useAfterEditor = nil }
        }) { route in
            switch route {
            case .repeatTemplate:
                RunWorkoutTemplateEditorSheet(metric: metric, plans: planStore) { useAfterEditor = $0 }
            case .stepTemplate:
                RunWorkoutStepTemplateEditorSheet(metric: metric, initialPlan: nil, plans: planStore) { useAfterEditor = $0 }
            case .edit(let plan):
                RunWorkoutStepTemplateEditorSheet(metric: metric, initialPlan: plan, plans: planStore) { useAfterEditor = $0 }
            }
        }
    }

    private func toggleFavorite(_ plan: RunWorkoutPlan) {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        do { try planStore.setFavorite(plan, favorite: !planStore.isFavorite(id: plan.id), userID: owner); favoriteError = nil } catch { favoriteError = error.localizedDescription }
    }

    private func startCard(
        title: String,
        subtitle: String,
        icon: String,
        detail: String?,
        interpreted: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .appTextRole(.secondary)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .appSurface(interpreted ? .emphasized : .quiet)
        .accessibilityElement(children: .combine)
    }

    private func detailText(for plan: RunWorkoutPlan) -> String {
        var parts: [String] = ["\(plan.steps.count) \(plan.steps.count == 1 ? "step" : "steps")"]
        if plan.estimatedDurationSeconds > 0 {
            let time = RunFormat.durationText(seconds: plan.estimatedDurationSeconds)
            parts.append(plan.totalDistanceMeters > 0 ? "\(time) + distance blocks" : time)
        }
        if plan.totalDistanceMeters > 0 {
            parts.append(RunFormat.distanceText(meters: plan.totalDistanceMeters, metric: metric))
        }
        return parts.joined(separator: " · ")
    }

    private func icon(for plan: RunWorkoutPlan) -> String {
        switch plan.id {
        case "5x400m":
            return "flag.checkered"
        case "30-30-fartlek":
            return "timer"
        default:
            return "speedometer"
        }
    }
}

private struct RunGoalSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: Bool
    let onReview: (RunWorkoutPlan) -> Void
    @State private var kind: RunWorkGoalMode = .duration
    @State private var minutes = "30"
    @State private var goalID = UUID().uuidString
    @State private var distance: String
    @FocusState private var isEditing: Bool

    init(metric: Bool, onReview: @escaping (RunWorkoutPlan) -> Void) {
        self.metric = metric
        self.onReview = onReview
        _distance = State(initialValue: metric ? "5" : "3")
    }

    var body: some View {
        AppEditorScaffold(title: "Set a run goal", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Picker("Goal", selection: $kind) {
                    Text("Time").tag(RunWorkGoalMode.duration)
                    Text("Distance").tag(RunWorkGoalMode.distance)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("run_goal_kind")

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    HStack {
                        Text(kind == .duration ? "Active time (minutes:seconds)" : "Distance (\(unit))").appTextRole(.control)
                        Spacer(minLength: AppSpacing.compact)
                        Button("Done") { isEditing = false }
                            .frame(minHeight: 44)
                            .opacity(isEditing ? 1 : 0)
                            .disabled(!isEditing)
                            .accessibilityHidden(!isEditing)
                            .accessibilityIdentifier("run_goal_finish_edit")
                    }
                    TextField(kind == .duration ? "30 or 23:45" : unit, text: kind == .duration ? $minutes : $distance)
                        .keyboardType(kind == .duration ? .numbersAndPunctuation : .decimalPad)
                        .focused($isEditing)
                        .appTextRole(.sectionTitle)
                        .padding(AppSpacing.row)
                        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }
                        .accessibilityLabel(kind == .duration ? "Goal in minutes, or minutes and seconds separated by a colon" : "Goal distance in \(unit)")
                        .accessibilityIdentifier("run_goal_value")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.compact) {
                        ForEach(presets, id: \.self) { value in
                            Button("\(Int(value)) \(kind == .duration ? "min" : unit)") {
                                if kind == .duration { minutes = String(Int(value)) } else { distance = String(Int(value)) }
                                isEditing = false
                            }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityIdentifier("run_goal_preset_\(Int(value))")
                        }
                    }
                    Text(plan == nil ? validationText : (kind == .duration
                         ? "Pauses won't count toward this active-time target. Reaching the goal won't end your recording."
                         : "Only measured GPS distance counts. Reaching the goal won't end your recording."))
                        .appTextRole(.secondary)
                        .foregroundStyle(plan == nil ? AppPalette.caution : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("run_goal_validation")
                }
                .appSurface(.quiet)
            }
        } actions: {
            if !isEditing {
                Button("Review goal") { if let plan { onReview(plan) } }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(plan == nil)
                    .accessibilityIdentifier("run_goal_review")
            }
        }
        .onChange(of: kind) { _, _ in isEditing = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }.accessibilityIdentifier("run_goal_keyboard_done")
            }
        }
    }

    private var unit: String { metric ? "km" : "mi" }
    private var presets: [Double] { kind == .duration ? [20, 30, 45, 60] : [1, 3, 5, 10] }
    private var validationText: String { kind == .duration ? "Enter minutes or mm:ss, from 0:01 to 360:00. Seconds must be 00–59." : "Choose a distance from 0.1 to 100 \(unit)." }

    private var plan: RunWorkoutPlan? {
        let goal: RunWorkoutStep.Goal
        let name: String
        if kind == .duration {
            guard let value = RunQuickGoalRules.durationSeconds(minutes) else { return nil }
            goal = .duration(seconds: value)
            name = value.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(value / 60)) min run" : "\(RunFormat.durationText(seconds: value)) run"
        } else {
            let normalized = distance.trimmed.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
            guard let value = Double(normalized), value.isFinite, (0.1...100).contains(value) else { return nil }
            let meters = value * (metric ? 1000 : RunFormat.metersPerMile)
            goal = .distance(meters: meters)
            name = "\(RunFormat.distanceText(meters: meters, metric: metric)) run"
        }
        return RunWorkoutPlan(id: goalID, name: name, subtitle: kind == .duration ? "Time goal" : "Distance goal", steps: [
            RunWorkoutStep(id: "goal", kind: .hard, title: "Run", goal: goal, target: RunWorkoutTarget(cue: "Choose your own effort"))
        ])
    }
}

private struct RunWorkoutPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: RunWorkoutPlan
    let metric: Bool
    let onStart: () -> Void
    let onEdit: (() -> Void)?
    var favorite: Bool = false
    var onFavorite: (() -> Void)?
    var favoriteError: String?

    var body: some View {
        AppEditorScaffold(title: plan.name, dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Text("Start recording when you're ready on the next screen.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(plan.subtitle).appTextRole(.secondary).foregroundStyle(.secondary)
                    Text(summary).appTextRole(.control)
                        .accessibilityIdentifier("run_plan_summary")
                    if plan.totalDistanceMeters > 0 && plan.estimatedDurationSeconds > 0 {
                        Text("Time covers timed steps only. Distance steps add time at your running pace.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Label("Outdoor GPS · pace in \(metric ? "min/km" : "min/mi")", systemImage: "location")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                .appSurface(.quiet)

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Session steps")
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text("Step \(index + 1) of \(plan.steps.count) · \(step.title)")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            Text(goalText(step)).appTextRole(.control)
                            if let target = step.targetText(metric: metric) {
                                Text(target).appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(.quiet)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("run_plan_step_\(index + 1)")
                    }
                }
                if let onEdit {
                    Button("Edit workout", action: onEdit)
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("run_plan_edit")
                }
                if let onFavorite {
                    Button(favorite ? "Remove favorite" : "Save as favorite", systemImage: favorite ? "star.fill" : "star", action: onFavorite)
                        .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("run_plan_favorite")
                    if let favoriteError { Text(favoriteError).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
                }
            }
        } actions: {
            Button("Use workout", action: onStart)
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(plan.steps.isEmpty)
                .accessibilityIdentifier("run_plan_start")
        }
    }

    private var summary: String {
        var parts = ["\(plan.steps.count) \(plan.steps.count == 1 ? "step" : "steps")"]
        if plan.estimatedDurationSeconds > 0 {
            parts.append("\(RunFormat.durationText(seconds: plan.estimatedDurationSeconds)) timed")
        }
        if plan.totalDistanceMeters > 0 {
            parts.append("\(RunFormat.distanceText(meters: plan.totalDistanceMeters, metric: metric)) distance blocks")
        }
        return parts.joined(separator: " · ")
    }

    private func goalText(_ step: RunWorkoutStep) -> String {
        switch step.goal {
        case .duration(let seconds): return "Run for \(RunFormat.durationText(seconds: seconds))"
        case .distance(let meters): return "Run \(RunFormat.distanceText(meters: meters, metric: metric))"
        case .open: return "Continue this step manually when you are ready"
        }
    }
}

private struct TreadmillRunEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var trainingFuelPlanStore: TrainingFuelPlanStore
    let metric: Bool
    let onSaved: () -> Void
    private let ownerID: String?
    private let recorderStore = RunRecorderStore()
    private let submissionStore = TreadmillRunSubmissionStore()

    @State private var distanceInput: String
    @State private var minutesInput = "30"
    @State private var secondsInput = "00"
    @State private var endedAt = Date()
    @State private var isSaving = false
    @State private var pendingSubmission: TreadmillRunSubmission?
    @State private var submissionMessage: String?
    @State private var submissionRecoveryBlocked = false
    @State private var didRestoreSubmission = false
    @State private var didRecordCompletion = false
    @State private var showingShortRunReview = false
    @FocusState private var focusedField: String?
    private var entryMetric: Bool { pendingSubmission?.metric ?? metric }

    init(metric: Bool, onSaved: @escaping () -> Void) {
        self.metric = metric
        self.onSaved = onSaved
        self.ownerID = DIContainer.shared.authService.currentUserID
        _distanceInput = State(initialValue: metric ? "5.00" : "3.00")
    }

    var body: some View {
        AppEditorScaffold(
            title: "Log treadmill",
            subtitle: "Enter the treadmill's distance and active time, excluding breaks.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let submissionMessage {
                    Label(submissionMessage, systemImage: "arrow.clockwise.circle")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .appSurface(.quiet)
                        .accessibilityIdentifier("treadmill_pending_submission")
                }
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    HStack {
                        AppSectionHeader(title: "Run details")
                        if focusedField != nil {
                            Button("Done") { focusedField = nil }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("treadmill_finish_edit")
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                    treadmillField("Distance (\(entryMetric ? "km" : "mi"))", text: $distanceInput, field: "distance", keyboard: .decimalPad)
                    treadmillField("Minutes", text: $minutesInput, field: "minutes", keyboard: .numberPad)
                    treadmillField("Seconds", text: $secondsInput, field: "seconds", keyboard: .numberPad)
                    AppDateField("Ended", selection: $endedAt, displayedComponents: [.date, .hourAndMinute])
                    Text(validationMessage ?? "Your exact distance and time will be saved.")
                        .appTextRole(.caption)
                        .foregroundStyle(validationMessage == nil ? Color.secondary : AppPalette.caution)
                        .accessibilityIdentifier("treadmill_validation")
                    }
                    .appTextRole(.body)
                    .appSurface(.emphasized)
                    .disabled(pendingSubmission != nil || submissionRecoveryBlocked)
                }

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Calculated summary",
                        subtitle: "Average pace uses active time. Calories are estimated from distance and your weight."
                    )
                    AppMetricStrip(items: [
                        AppMetricItem(
                            label: "Active time",
                            value: movingSeconds.map(RunFormat.durationText(seconds:)) ?? "—",
                            accent: AppPalette.effort
                        ),
                        AppMetricItem(
                            label: "Average pace",
                            value: averagePaceText,
                            accent: AppPalette.effort
                        ),
                        AppMetricItem(
                            label: "Active calories",
                            value: validationMessage == nil ? "\(Int(estimatedCalories.rounded())) cal" : "—",
                            accent: AppPalette.caution
                        )
                    ])
                    .appSurface(.quiet)
                    .accessibilityIdentifier("treadmill_summary")
                    Text("Breaks and total elapsed time weren't entered. Exact pause events can't be reconstructed for Apple Health.")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("treadmill_timing_note")
                }

                Label(
                    "The completed workout is saved to MyFitPlate and sent to Apple Health when permission is available.",
                    systemImage: "heart.text.clipboard"
                )
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .appSurface(.quiet)
            }
        } actions: {
            if focusedField == nil {
            Button {
                if pendingSubmission == nil, RunSaveReviewRules.requirement(activeSeconds: movingSeconds ?? 0, distanceMeters: distanceMeters) == .shortRecording {
                    showingShortRunReview = true
                } else { save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Label(pendingSubmission == nil ? "Save run" : "Retry save", systemImage: pendingSubmission == nil ? "checkmark" : "arrow.clockwise")
                }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(isSaving || validationMessage != nil || submissionRecoveryBlocked)
            .accessibilityIdentifier("treadmill_save")
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("Save short treadmill run?", isPresented: $showingShortRunReview) {
            Button("Save recording") { save(confirmShortRecording: true) }
                .accessibilityIdentifier("treadmill_confirm_short_save")
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("\(RunFormat.durationText(seconds: movingSeconds ?? 0)) active time · \(RunFormat.distanceText(meters: distanceMeters, metric: entryMetric)). Only the time and distance you entered will be saved.")
        }
        .disabled(isSaving)
        .onAppear { restoreSubmission() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .accessibilityIdentifier("treadmill_keyboard_done")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("treadmill_entry")
    }

    private func treadmillField(_ title: String, text: Binding<String>, field: String, keyboard: UIKeyboardType) -> some View {
        // Keep the narrow input's hit target separate from its visible label.
        // LabeledContent can expose the entire row as the rounded text field.
        HStack(spacing: AppSpacing.row) {
            Text(title)
            Spacer(minLength: AppSpacing.compact)
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .focused($focusedField, equals: field)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
                .frame(minHeight: 44)
                .accessibilityLabel(title)
                .accessibilityIdentifier("treadmill_\(field)")
        }
    }

    private var enteredDistanceMeters: Double? {
        let normalized = distanceInput.trimmed.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0, value <= (entryMetric ? 80 : 50) else { return nil }
        return value * (entryMetric ? 1000 : RunFormat.metersPerMile)
    }
    private var distanceMeters: Double { enteredDistanceMeters ?? 0 }

    private var movingSeconds: Double? {
        guard let minutes = Int(minutesInput.trimmed), let seconds = Int(secondsInput.trimmed),
              (0...360).contains(minutes), (0..<60).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return (Int(RunSaveReviewRules.minimumActiveSeconds)...21_600).contains(total) ? Double(total) : nil
    }

    private var validationMessage: String? {
        guard enteredDistanceMeters != nil else { return "Enter a distance from \(entryMetric ? "0 to 80 km" : "0 to 50 mi")." }
        guard movingSeconds != nil else { return "Enter 1 second to 6 hours, with seconds from 0 to 59." }
        guard endedAt <= Date().addingTimeInterval(60) else { return "Choose an end time that has already passed." }
        return nil
    }

    private var averagePaceText: String {
        guard validationMessage == nil, distanceMeters >= 100, let movingSeconds else { return "—" }
        let secondsPerKm = movingSeconds / (distanceMeters / 1000)
        return RunFormat.paceText(secondsPerKm: secondsPerKm, metric: entryMetric) ?? "—"
    }

    private var estimatedCalories: Double {
        pendingSubmission?.completion.run.activeCalories ?? RunEnergy.estimateKcal(distanceMeters: distanceMeters, weightLbs: goalSettings.weight)
    }

    private func restoreSubmission() {
        guard !didRestoreSubmission, let ownerID,
              ownerID == DIContainer.shared.authService.currentUserID else { return }
        didRestoreSubmission = true
        do {
            guard let submission = try submissionStore.load(userID: ownerID) else { return }
            let run = submission.completion.run
            // A completed local commit can outlive an interrupted receipt cleanup.
            if RunFallbackStore.shared.containsRecording(id: run.recordingID ?? run.id, for: ownerID) {
                _ = try submissionStore.complete(submission, userID: ownerID)
                onSaved()
                dismiss()
                return
            }
            pendingSubmission = submission
            distanceInput = submission.distanceInput
            minutesInput = submission.minutesInput
            secondsInput = submission.secondsInput
            endedAt = run.endDate
            submissionMessage = "Your reviewed run is kept. Retry saves this same recording, including its original time and distance."
        } catch {
            submissionRecoveryBlocked = true
            submissionMessage = "Your submitted run could not be read. Close and reopen this screen to retry recovery; the saved copy stays unchanged."
        }
    }

    private func save(confirmShortRecording: Bool = false) {
        guard !isSaving, !submissionRecoveryBlocked, validationMessage == nil, let movingSeconds,
              let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        let submission: TreadmillRunSubmission
        if let pendingSubmission {
            submission = pendingSubmission
        } else {
            guard var run = ManualRunEntryRules.buildIndoorRun(
                startDate: endedAt.addingTimeInterval(-movingSeconds),
                distanceMeters: distanceMeters, movingSeconds: movingSeconds, metric: entryMetric,
                activeCalories: estimatedCalories, confirmShortRecording: confirmShortRecording
            ) else {
                ToastManager.shared.showToast(message: "Review your run's distance and time.")
                return
            }
            run.shoeID = RunningShoeStore().defaultShoe()?.id
            submission = TreadmillRunSubmission(run: run, weightLbs: goalSettings.weight, metric: entryMetric,
                distanceInput: distanceInput.trimmed.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."),
                minutesInput: minutesInput.trimmed, secondsInput: secondsInput.trimmed)
        }
        do {
            // Keep the accepted identity/measurements before either save can begin.
            // A failed or uncertain Health write must survive leaving this sheet.
            try submissionStore.prepare(submission, userID: ownerID)
        } catch {
            submissionMessage = "Your reviewed run could not be kept safely. Your entries are here; try saving again."
            return
        }
        pendingSubmission = submission
        let run = submission.completion.run
        isSaving = true
        submissionMessage = nil
        let localSaved = RunFallbackStore.shared.save(run, for: ownerID)
        if localSaved {
            try? submissionStore.complete(submission, userID: ownerID)
            RunningShoeStore().tagRun(runID: run.id, withShoeID: run.shoeID)
            acceptSavedRun(run, ownerID: ownerID, message: "Saved in MyFitPlate. Syncing to Apple Health…")
        }
        RunHealthExportCoordinator(writer: recorderStore).export(run: run,
            weightLbs: submission.completion.weightLbs, userID: ownerID, locations: []) { outcome in
            isSaving = false
            var savedRun = run
            var fullLocalCopySaved = localSaved
            switch outcome {
            case .saved(let savedID), .savedRoutePending(let savedID):
                savedRun = run.reidentified(as: savedID)
                if localSaved { _ = RunFallbackStore.shared.reidentify(id: run.id, as: savedID, for: ownerID) } else { fullLocalCopySaved = RunFallbackStore.shared.save(savedRun, for: ownerID) }
            case .savedAwaitingReadAccess, .confirmationRequired:
                if !localSaved { fullLocalCopySaved = RunFallbackStore.shared.save(run, for: ownerID) }
            case .failed: break
            }
            if fullLocalCopySaved { try? submissionStore.complete(submission, userID: ownerID) }
            guard ownerID == DIContainer.shared.authService.currentUserID else { return }
            guard fullLocalCopySaved else {
                submissionMessage = outcome == .failed
                    ? "Saving is unavailable. Your reviewed run is kept, even if you close the app. Retry saves the same recording."
                    : "Your reviewed recording is kept, but its full MyFitPlate copy still needs saving. Retry also checks any pending Apple Health sync."
                HapticManager.instance.notification(.error)
                return
            }
            switch outcome {
            case .saved(let savedID), .savedRoutePending(let savedID):
                RunningShoeStore().tagRun(runID: savedID, withShoeID: run.shoeID)
                if !localSaved { acceptSavedRun(savedRun, ownerID: ownerID, message: "Treadmill run saved.") } else { onSaved() }
            case .savedAwaitingReadAccess, .confirmationRequired:
                let message = outcome == .confirmationRequired
                    ? "Saved in MyFitPlate. Apple Health sync has not been confirmed."
                    : "Saved in MyFitPlate and Apple Health. Health confirmation is pending."
                if !localSaved { acceptSavedRun(run, ownerID: ownerID, message: message) } else {
                    ToastManager.shared.showToast(message: message)
                    onSaved()
                }
            case .failed:
                ToastManager.shared.showToast(message: "Your run is saved in MyFitPlate. Apple Health sync is unavailable.")
                onSaved()
            }
        }
    }

    private func acceptSavedRun(_ run: Run, ownerID: String, message: String) {
        guard !didRecordCompletion, ownerID == DIContainer.shared.authService.currentUserID else { return }
        didRecordCompletion = true
        ActivationFunnel.recordTrainingCompletion(.treadmillRun)
            let today = dailyLogService.currentDailyLog.flatMap { log in
                Calendar.current.isDate(log.date, inSameDayAs: run.endDate) ? log : nil
            }
            if trainingFuelPlanStore.recordRunCompletion(
                run,
                selectedPlanID: nil,
                source: .treadmillRun,
                today: today,
                goals: TodayFuelPlanGoals(
                    calories: goalSettings.calories ?? 0,
                    protein: goalSettings.protein,
                    carbs: goalSettings.carbs,
                    fats: goalSettings.fats
                ),
                for: ownerID
            ) {
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
                    parameters: ["outcome": "completed", "source": "treadmill_run"]
                )
            }
            HapticManager.instance.notification(.success)
            ToastManager.shared.showToast(message: message)
            onSaved()
            dismiss()
    }
}

private enum RunWorkoutEditorRoute: Identifiable {
    case repeatTemplate
    case stepTemplate
    case edit(RunWorkoutPlan)

    var id: String {
        switch self {
        case .repeatTemplate:
            return "repeat"
        case .stepTemplate:
            return "step"
        case .edit(let plan):
            return "edit-\(plan.id)"
        }
    }
}

private enum RunWorkGoalMode: String, Codable, CaseIterable, Identifiable {
    case duration
    case distance
    case open

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duration: return "Time"
        case .distance: return "Distance"
        case .open: return "Open"
        }
    }
}

private struct RunBuilderDraft<Value: Codable & Equatable>: Codable, Equatable {
    var operationID = UUID().uuidString
    var planID: String
    var original: RunWorkoutPlan?
    var metric: Bool
    var value: Value
}

@MainActor
private final class RunBuilderState<Value: Codable & Equatable>: ObservableObject {
    @Published var draft: RunBuilderDraft<Value>
    @Published var message: String?
    @Published private(set) var isBlocked = false
    let wasRestored: Bool
    private let ownerID: String?
    private let scope: String
    private let drafts = EditorDraftStore()
    private let plans: RunWorkoutPlanStore
    private var didSave = false

    init(value: Value, metric: Bool, original: RunWorkoutPlan?, scope: String, plans: RunWorkoutPlanStore) {
        self.ownerID = DIContainer.shared.authService.currentUserID
        self.scope = scope
        self.plans = plans
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.arguments.contains("-screenshot-mode"),
           ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-run-builder"),
           let ownerID, ownerID == ScreenshotDemoData.userID {
            try? EditorDraftStore().remove(userID: ownerID, scope: scope)
        }
        #endif
        var initial = RunBuilderDraft(planID: original?.id ?? UUID().uuidString, original: original, metric: metric, value: value)
        var restored = false
        var readError: String?
        if let ownerID {
            do {
                if let checkpoint = try EditorDraftStore().load(RunBuilderDraft<Value>.self, userID: ownerID, scope: scope) {
                    initial = checkpoint.value
                    restored = true
                }
            } catch { readError = "Your earlier draft could not be read. It has been kept unchanged; reopen the editor to retry." }
        }
        draft = initial
        wasRestored = restored
        message = readError
        isBlocked = readError != nil
    }

    func checkpoint() {
        guard !didSave, !isBlocked else { return }
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else {
            message = "Your account changed. Reopen this editor in the correct account."
            isBlocked = true
            return
        }
        do { try drafts.save(draft, userID: ownerID, scope: scope) } catch {
            message = "This draft could not be kept on this device. Keep the editor open and try again."
        }
    }

    func reviewOnce(_ build: (RunBuilderDraft<Value>) -> RunWorkoutPlan) -> RunWorkoutPlan? {
        guard !isBlocked, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return nil }
        let frozen = draft
        do {
            let plan = build(frozen)
            try RunWorkoutPlanStore.validate(plan)
            try drafts.save(frozen, userID: ownerID, scope: scope)
            return plan
        } catch { message = error.localizedDescription; return nil }
    }

    func save(_ build: (RunBuilderDraft<Value>) -> RunWorkoutPlan, asNew: Bool = false) -> Bool {
        guard !isBlocked, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return false }
        if asNew {
            draft.planID = UUID().uuidString
            draft.operationID = UUID().uuidString
            draft.original = nil
        }
        let frozen = draft
        do {
            try drafts.save(frozen, userID: ownerID, scope: scope)
            _ = try plans.saveReviewed(build(frozen), replacing: frozen.original, operationID: frozen.operationID, userID: ownerID)
            didSave = true
            do { _ = try drafts.removeIfUnchanged(RunBuilderDraft<Value>.self, userID: ownerID, scope: scope, fingerprint: PlanFingerprint.make(frozen)) } catch {
                ToastManager.shared.showToast(message: "Workout saved. Its draft cleanup will be retried when reopened.")
            }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}

private struct RunRepeatEditorValue: Codable, Equatable {
    var name = "Custom intervals"
    var repetitions = 6
    var warmupMinutes = 10
    var workMode: RunWorkGoalMode = .duration
    var workSeconds = 60
    var workMeters = 400
    var recoveryMode: RunWorkGoalMode = .duration
    var recoverySeconds = 90
    var recoveryMeters = 200
    var includeFinalRecovery = false
    var cooldownMinutes = 5
    var cue = "Controlled effort"
    var usePaceTarget = false
    var fastestPaceSeconds = 300
    var slowestPaceSeconds = 330
}

private struct RunWorkoutNameField: View {
    @Binding var name: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            TextField("Workout name", text: $name)
                .appTextRole(.control)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .frame(minHeight: 44)
                .accessibilityIdentifier("run_workout_name")
            if isFocused && !name.isEmpty {
                Button {
                    name = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear workout name")
                .accessibilityIdentifier("run_workout_name_clear")
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
    }
}

private struct RunWorkoutTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor: RunBuilderState<RunRepeatEditorValue>
    let onUseOnce: (RunWorkoutPlan) -> Void

    init(metric: Bool, plans: RunWorkoutPlanStore, onUseOnce: @escaping (RunWorkoutPlan) -> Void) {
        self.onUseOnce = onUseOnce
        _editor = StateObject(wrappedValue: RunBuilderState(value: RunRepeatEditorValue(), metric: metric,
            original: nil, scope: "run-builder.repeats.v1", plans: plans))
    }

    private var metric: Bool { editor.draft.metric }
    private var form: RunRepeatEditorValue { editor.draft.value }
    private var validationMessage: String? {
        if form.name.trimmed.isEmpty { return "Name this workout before saving." }
        if form.usePaceTarget && form.fastestPaceSeconds > form.slowestPaceSeconds {
            return "The slowest pace must be at least the fastest pace."
        }
        return nil
    }

    var body: some View {
        AppEditorScaffold(title: "Create repeats", subtitle: "Repeat one work-and-recovery pair, then finish with a cooldown.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if editor.wasRestored {
                    Label("Draft restored", systemImage: "arrow.clockwise")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("run_builder_restored")
                }
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Workout")
                    RunWorkoutNameField(name: $editor.draft.value.name)
                }
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    Stepper("Repeats: \(form.repetitions)", value: $editor.draft.value.repetitions, in: 1...50)
                    Stepper("Warm up: \(form.warmupMinutes) min", value: $editor.draft.value.warmupMinutes, in: 0...30)
                    Divider()
                    Picker("Work goal", selection: $editor.draft.value.workMode) {
                        ForEach(RunWorkGoalMode.allCases.filter { $0 != .open }) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    if form.workMode == .duration {
                        Stepper("Work: \(form.workSeconds) sec", value: $editor.draft.value.workSeconds, in: 15...3600, step: 15)
                    } else {
                        Stepper("Work: \(RunFormat.distanceText(meters: Double(form.workMeters), metric: metric))", value: $editor.draft.value.workMeters, in: 50...10_000, step: 50)
                    }
                    Divider()
                    Picker("Recovery goal", selection: $editor.draft.value.recoveryMode) {
                        ForEach(RunWorkGoalMode.allCases.filter { $0 != .open }) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    if form.recoveryMode == .duration {
                        Stepper("Recovery: \(form.recoverySeconds) sec", value: $editor.draft.value.recoverySeconds, in: 0...1800, step: 15)
                    } else {
                        Stepper("Recovery: \(RunFormat.distanceText(meters: Double(form.recoveryMeters), metric: metric))", value: $editor.draft.value.recoveryMeters, in: 50...3000, step: 50)
                        Text("Distance recovery advances only when GPS measures that distance. You can skip the step if location becomes unavailable.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Recovery after final repeat", isOn: $editor.draft.value.includeFinalRecovery)
                    Stepper("Cool down: \(form.cooldownMinutes) min", value: $editor.draft.value.cooldownMinutes, in: 0...30)
                }.appTextRole(.control).appSurface(.emphasized)
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: "Effort guidance")
                    TextField("Effort cue", text: $editor.draft.value.cue)
                    Toggle("Use a pace range", isOn: $editor.draft.value.usePaceTarget)
                    if form.usePaceTarget {
                        Stepper("Fastest: \(paceText(form.fastestPaceSeconds))", value: $editor.draft.value.fastestPaceSeconds, in: 180...1200, step: 5)
                        Stepper("Slowest: \(paceText(form.slowestPaceSeconds))", value: $editor.draft.value.slowestPaceSeconds, in: 180...1200, step: 5)
                    }
                }.appTextRole(.control).appSurface(.emphasized)
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Session preview", subtitle: form.includeFinalRecovery ? "Includes recovery after the last repeat." : "The last repeat goes directly to the cooldown.")
                    AppMetricStrip(items: [
                        AppMetricItem(label: "Steps", value: makePlan(editor.draft).steps.count.formatted(), accent: AppPalette.effort),
                        AppMetricItem(label: "Timed steps", value: RunFormat.durationText(seconds: makePlan(editor.draft).estimatedDurationSeconds), accent: AppPalette.recovery)
                    ])
                    if form.workMode == .distance || form.recoveryMode == .distance {
                        Text("Plus \(RunFormat.distanceText(meters: makePlan(editor.draft).totalDistanceMeters, metric: metric)) of distance steps.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }.appSurface(.interpreted)
                if let message = validationMessage ?? editor.message {
                    Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("run_builder_validation")
                }
                Button("Review and use once") {
                    if let plan = editor.reviewOnce(makePlan) { onUseOnce(plan); dismiss() }
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .disabled(validationMessage != nil || editor.isBlocked)
                .accessibilityIdentifier("run_workout_use_once")
                Text("Saved on this device for this account. Closing the editor keeps your draft.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        } actions: {
            Button { if editor.save(makePlan) { dismiss() } } label: { Label("Save workout", systemImage: "checkmark") }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(validationMessage != nil || editor.isBlocked)
                .accessibilityIdentifier("run_workout_save")
        }
        .onAppear { editor.checkpoint() }
        .onChange(of: editor.draft) { _, _ in editor.checkpoint() }
        .onDisappear { editor.checkpoint() }
    }

    private func makePlan(_ draft: RunBuilderDraft<RunRepeatEditorValue>) -> RunWorkoutPlan {
        let value = draft.value
        let multiplier = draft.metric ? 1.0 : RunFormat.metersPerMile / 1000
        let target = RunWorkoutTarget(cue: value.cue,
            fastestSecondsPerKm: value.usePaceTarget ? Double(value.fastestPaceSeconds) / multiplier : nil,
            slowestSecondsPerKm: value.usePaceTarget ? Double(value.slowestPaceSeconds) / multiplier : nil)
        let group = RunWorkoutRepeatGroup(id: "\(draft.planID).repeats", repetitions: value.repetitions,
            workGoal: value.workMode == .duration ? .duration(seconds: Double(value.workSeconds)) : .distance(meters: Double(value.workMeters)),
            recoveryGoal: value.recoveryMode == .duration ? .duration(seconds: Double(value.recoverySeconds)) : .distance(meters: Double(value.recoveryMeters)),
            includeFinalRecovery: value.includeFinalRecovery, workTarget: target)
        return RunWorkoutPlan.repeated(id: draft.planID, name: value.name.trimmed,
            warmupSeconds: Double(value.warmupMinutes * 60), group: group, cooldownSeconds: Double(value.cooldownMinutes * 60))
    }

    private func paceText(_ seconds: Int) -> String {
        RunFormat.paceText(secondsPerKm: Double(seconds) / (metric ? 1 : RunFormat.metersPerMile / 1000), metric: metric) ?? "—"
    }
}

private struct RunStepEditorValue: Codable, Equatable {
    var name: String
    var steps: [RunWorkoutStepDraft]
    var outline: [RunOutlineDraft]?
}

private struct RunWorkoutStepTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor: RunBuilderState<RunStepEditorValue>
    @State private var showingOutline = false
    let onUseOnce: (RunWorkoutPlan) -> Void
    private var metric: Bool { editor.draft.metric }
    private var name: String { editor.draft.value.name }
    private var steps: [RunWorkoutStepDraft] {
        get { editor.draft.value.steps }
        nonmutating set { editor.draft.value.steps = newValue }
    }

    init(metric: Bool, initialPlan: RunWorkoutPlan?, plans: RunWorkoutPlanStore, duplicate: Bool = false, onUseOnce: @escaping (RunWorkoutPlan) -> Void) {
        self.onUseOnce = onUseOnce
        let value = RunStepEditorValue(name: initialPlan?.name ?? "Custom workout",
            steps: initialPlan?.steps.map { RunWorkoutStepDraft(step: $0, metric: metric) } ?? Self.defaultSteps(),
            outline: initialPlan?.outline?.map { RunOutlineDraft(item: $0, metric: metric) })
        _editor = StateObject(wrappedValue: RunBuilderState(value: value, metric: metric, original: duplicate ? nil : initialPlan,
            scope: "run-builder.steps.\(duplicate ? "copy." : "")\(initialPlan?.id ?? "new").v1", plans: plans))
    }

    private var validationMessage: String? {
        if let outline = editor.draft.value.outline {
            do {
                _ = try RunWorkoutOutline.expanded(outline.map { $0.item(metric: metric) })
                try RunWorkoutPlanStore.validate(makePlan())
                return nil
            } catch { return error.localizedDescription }
        }
        if name.trimmed.isEmpty || steps.isEmpty { return "Add a workout name and at least one step." }
        if let index = steps.firstIndex(where: { $0.usePaceTarget && $0.fastestPaceSeconds > $0.slowestPaceSeconds }) {
            return "Step \(index + 1): the slowest pace must be at least the fastest pace."
        }
        return nil
    }

    var body: some View {
        AppEditorScaffold(
            title: editor.draft.original == nil ? "Create workout" : "Edit workout",
            subtitle: "Arrange the session from warm-up through cooldown, with an optional cue for every step.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if editor.wasRestored {
                    Label("Draft restored", systemImage: "arrow.clockwise")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("run_builder_restored")
                }
                if let message = validationMessage ?? editor.message {
                    Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("run_builder_validation")
                }
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Workout name")
                    RunWorkoutNameField(name: $editor.draft.value.name)
                }

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Session steps"
                    )

                    Button {
                        if editor.draft.value.outline == nil { editor.draft.value.outline = steps.map(RunOutlineDraft.init(step:)) }
                        showingOutline = true
                    } label: { Label("Arrange steps and repeat groups", systemImage: "list.bullet.indent") }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("run_workout_outline")

                    if let outline = editor.draft.value.outline {
                        Text("\(outline.count) outline items · \(makePlan().steps.count) executed steps")
                            .appTextRole(.secondary)
                        Text("Repeat groups keep their hierarchy. Edit any step or group, including open warm-ups and mixed time/distance recoveries.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    } else {
                    ForEach($editor.draft.value.steps) { $step in
                        stepEditor(step: $step)
                            .appSurface(.emphasized)
                    }

                    Button {
                        steps.append(RunWorkoutStepDraft(kind: .hard, title: "Work"))
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .disabled(steps.count >= 150)
                    }
                }

                AppMetricStrip(items: [
                    AppMetricItem(label: "Steps", value: makePlan().steps.count.formatted(), accent: AppPalette.effort),
                    AppMetricItem(
                        label: "Timed steps",
                        value: RunFormat.durationText(seconds: makePlan().estimatedDurationSeconds),
                        accent: AppPalette.recovery
                    )
                ])
                .appSurface(.interpreted)
                Button("Review and use once") {
                    if let plan = editor.reviewOnce(frozenPlan) { onUseOnce(plan); dismiss() }
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .disabled(validationMessage != nil || editor.isBlocked)
                .accessibilityIdentifier("run_workout_use_once")
                Text("Saved on this device for this account. Closing keeps your draft; completed recordings keep their original steps.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if editor.draft.original != nil {
                    Button("Save as a new workout") {
                        if editor.save(frozenPlan, asNew: true) { dismiss() }
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .disabled(validationMessage != nil || editor.isBlocked)
                }
            }
        } actions: {
            Button {
                if editor.save(frozenPlan) { dismiss() }
            } label: {
                Label("Save workout", systemImage: "checkmark")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(validationMessage != nil || editor.isBlocked)
            .accessibilityIdentifier("run_workout_save")
        }
        .sheet(isPresented: $showingOutline) {
            RunOutlineEditorSheet(items: Binding(get: { editor.draft.value.outline ?? [] },
                set: { editor.draft.value.outline = $0 }), metric: metric)
        }
        .onAppear { editor.checkpoint() }
        .onChange(of: editor.draft) { _, _ in editor.checkpoint() }
        .onDisappear { editor.checkpoint() }
    }

    @ViewBuilder
    private func stepEditor(step: Binding<RunWorkoutStepDraft>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack {
                Picker("Type", selection: step.kind) {
                    ForEach(RunWorkoutStep.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .appTextRole(.control)
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: AppSpacing.compact)
                Menu {
                    Button("Move earlier", systemImage: "arrow.up") { moveStep(id: step.wrappedValue.id, offset: -1) }
                        .disabled(steps.first?.id == step.wrappedValue.id)
                    Button("Move later", systemImage: "arrow.down") { moveStep(id: step.wrappedValue.id, offset: 1) }
                        .disabled(steps.last?.id == step.wrappedValue.id)
                    Button("Duplicate step", systemImage: "plus.square.on.square") { duplicateStep(id: step.wrappedValue.id) }
                        .disabled(steps.count >= 150)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Arrange \(step.wrappedValue.title) step")

                Button(role: .destructive) {
                    removeStep(id: step.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(steps.count <= 1)
                .accessibilityLabel("Delete \(step.wrappedValue.title) step")
            }

            TextField("Step title", text: step.title)
                .appTextRole(.control)
                .padding(AppSpacing.row)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            Picker("Goal", selection: step.goalMode) {
                ForEach(RunWorkGoalMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if step.wrappedValue.goalMode == .duration {
                Stepper(
                    "Duration: \(RunFormat.durationText(seconds: Double(step.wrappedValue.seconds)))",
                    value: step.seconds,
                    in: 15...7200,
                    step: 15
                )
            } else if step.wrappedValue.goalMode == .distance {
                Stepper(
                    "Distance: \(RunFormat.distanceText(meters: Double(step.wrappedValue.meters), metric: metric))",
                    value: step.meters,
                    in: 50...10_000,
                    step: 50
                )
            } else {
                Text("No time or distance target. Tap Continue step during the run when you are ready.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }

            TextField("Effort cue", text: step.cue)
                .appTextRole(.control)
                .padding(AppSpacing.row)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            Toggle("Use a pace range", isOn: step.usePaceTarget)
            if step.wrappedValue.usePaceTarget {
                Stepper(
                    "Fastest: \(paceText(secondsPerUnit: step.wrappedValue.fastestPaceSeconds))",
                    value: step.fastestPaceSeconds,
                    in: 180...1200,
                    step: 5
                )
                Stepper(
                    "Slowest: \(paceText(secondsPerUnit: step.wrappedValue.slowestPaceSeconds))",
                    value: step.slowestPaceSeconds,
                    in: 180...1200,
                    step: 5
                )
            }
        }
        .appTextRole(.control)
    }

    private func makePlan() -> RunWorkoutPlan { frozenPlan(editor.draft) }

    private func frozenPlan(_ draft: RunBuilderDraft<RunStepEditorValue>) -> RunWorkoutPlan {
        if let outline = draft.value.outline {
            let items = outline.map { $0.item(metric: draft.metric) }
            let expanded = (try? RunWorkoutOutline.expanded(items)) ?? []
            return RunWorkoutPlan(id: draft.planID, name: draft.value.name.trimmed,
                subtitle: "\(expanded.count) steps · structured workout", steps: expanded, outline: items)
        }
        let workCount = draft.value.steps.filter { $0.kind == .hard }.count
        return RunWorkoutPlan(id: draft.planID, name: draft.value.name.trimmed,
            subtitle: "\(workCount) work steps · \(draft.value.steps.count) total",
            steps: draft.value.steps.map { $0.step(metric: draft.metric) })
    }

    private func moveStep(id: String, offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
    }

    private func duplicateStep(id: String) {
        guard steps.count < 150, let index = steps.firstIndex(where: { $0.id == id }) else { return }
        var copy = steps[index]
        copy.id = UUID().uuidString
        copy.originalStep = nil
        steps.insert(copy, at: index + 1)
    }

    private func removeStep(id: String) {
        guard steps.count > 1 else { return }
        steps.removeAll { $0.id == id }
    }

    private func paceText(secondsPerUnit: Int) -> String {
        let secondsPerKm = metric ? Double(secondsPerUnit) : Double(secondsPerUnit) / (RunFormat.metersPerMile / 1000)
        return RunFormat.paceText(secondsPerKm: secondsPerKm, metric: metric) ?? RunFormat.durationText(seconds: Double(secondsPerUnit))
    }

    private static func defaultSteps() -> [RunWorkoutStepDraft] {
        [
            RunWorkoutStepDraft(kind: .warmup, title: "Warm up", seconds: 600, cue: "Easy start"),
            RunWorkoutStepDraft(kind: .hard, title: "Work", seconds: 300, cue: "Controlled effort"),
            RunWorkoutStepDraft(kind: .cooldown, title: "Cool down", seconds: 300, cue: "Easy finish")
        ]
    }
}

private struct RunWorkoutStepDraft: Codable, Identifiable, Equatable {
    var id: String
    var originalStep: RunWorkoutStep?
    var kind: RunWorkoutStep.Kind
    var title: String
    var goalMode: RunWorkGoalMode
    var seconds: Int
    var meters: Int
    var cue: String
    var usePaceTarget: Bool
    var fastestPaceSeconds: Int
    var slowestPaceSeconds: Int

    init(
        id: String = UUID().uuidString,
        kind: RunWorkoutStep.Kind,
        title: String,
        goalMode: RunWorkGoalMode = .duration,
        seconds: Int = 60,
        meters: Int = 400,
        cue: String = "",
        usePaceTarget: Bool = false,
        fastestPaceSeconds: Int = 300,
        slowestPaceSeconds: Int = 330
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.goalMode = goalMode
        self.seconds = seconds
        self.meters = meters
        self.cue = cue
        self.usePaceTarget = usePaceTarget
        self.fastestPaceSeconds = fastestPaceSeconds
        self.slowestPaceSeconds = slowestPaceSeconds
    }

    init(step: RunWorkoutStep, metric: Bool) {
        originalStep = step
        id = step.id
        kind = step.kind
        title = step.title
        switch step.goal {
        case .duration(let seconds):
            goalMode = .duration
            self.seconds = max(15, Int(seconds.rounded()))
            meters = 400
        case .distance(let meters):
            goalMode = .distance
            seconds = 60
            self.meters = max(50, Int(meters.rounded()))
        case .open:
            goalMode = .open
            seconds = 60
            meters = 400
        }
        cue = step.target?.cue ?? ""
        let unitMultiplier = metric ? 1.0 : RunFormat.metersPerMile / 1000
        if let fastest = step.target?.fastestSecondsPerKm,
           let slowest = step.target?.slowestSecondsPerKm {
            usePaceTarget = true
            fastestPaceSeconds = Int((fastest * unitMultiplier).rounded())
            slowestPaceSeconds = Int((slowest * unitMultiplier).rounded())
        } else {
            usePaceTarget = false
            fastestPaceSeconds = 300
            slowestPaceSeconds = 330
        }
    }

    func step(metric: Bool) -> RunWorkoutStep {
        if let originalStep, self == RunWorkoutStepDraft(step: originalStep, metric: metric) { return originalStep }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal: RunWorkoutStep.Goal
        switch goalMode {
        case .duration: goal = .duration(seconds: Double(seconds))
        case .distance: goal = .distance(meters: Double(meters))
        case .open: goal = .open
        }
        let multiplier = metric ? 1.0 : RunFormat.metersPerMile / 1000
        let target = RunWorkoutTarget(cue: cue,
            fastestSecondsPerKm: usePaceTarget ? Double(fastestPaceSeconds) / multiplier : nil,
            slowestSecondsPerKm: usePaceTarget ? Double(slowestPaceSeconds) / multiplier : nil)

        return RunWorkoutStep(
            id: id,
            kind: kind,
            title: trimmedTitle.isEmpty ? kind.displayName : trimmedTitle,
            goal: goal,
            target: target
        )
    }
}

private struct RunRow: View {
    let run: Run
    let metric: Bool

    private var subtitle: String {
        var parts = [RunFormat.distanceText(meters: run.distanceMeters, metric: metric)]
        if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: metric) {
            parts.append(pace)
        }
        parts.append("\(RunFormat.durationText(seconds: run.movingSeconds)) active")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        runIdentity
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.group)
            .padding(.vertical, AppSpacing.row)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }

    private var runIdentity: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: run.isIndoor ? "figure.run.treadmill" : "figure.run")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                sourceLabel
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sourceLabel: some View {
        Text("\(run.isIndoor ? "Indoor" : "Outdoor") · \(run.source.displayName)")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Detail

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published var routeSegments: [[CLLocationCoordinate2D]] = []
    @Published var routePaceSlices: [RunRoutePaceSlice] = []
    var routeCoordinates: [CLLocationCoordinate2D] { routeSegments.flatMap { $0 } }
    @Published var splits: [RunSplit] = []
    @Published var averageHeartRate: Double?
    @Published var isLoadingRoute = true
    @Published var ghostPaceComparison: RunStats.GhostPaceComparison?
    @Published var comparableRuns: [Run] = []
    /// Seconds in each HR zone [Z1…Z5], or nil when the run carried no heart-rate series.
    @Published var heartRateZoneSeconds: [Double]?
    @Published var zoneSettings = RunHeartRateZoneSettings.estimated(age: 30)
    @Published var zoneReview: RunHeartRateZoneReview?
    @Published var heartRateEvidenceDescription = "Checking workout-associated heart-rate samples…"
    @Published var zoneSettingsError: String?
    private var heartRateSamples: [RunHeartRateSample] = []
    private var usesRecordingHeartRate = false
    private var heartRateRun: Run?
    private var heartRateRequest = UUID()
    @Published var workoutResult: RunWorkoutResult?
    @Published var exportJob: RunHealthExportJob?
    @Published var isSyncingHealth = false
    @Published var exportMessage: String?
    private var exportOwnerID: String?

    private let importer = RunImportService()
    private let workoutResultStore = RunWorkoutResultStore()

    func loadHeartRateZones(run: Run, age: Int) {
        guard let ownerID = exportOwnerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        let evidence = (try? RunReviewStore().originalEvidence(for: run, userID: ownerID)) ?? run
        heartRateRun = evidence
        let request = UUID()
        heartRateRequest = request
        do {
            zoneSettings = try RunHeartRateZoneStore().settings(userID: ownerID, age: age)
            zoneSettingsError = nil
        } catch {
            zoneSettingsError = "Your zone settings could not be read. They have been kept unchanged."
        }
        importer.fetchWorkoutHeartRate(for: run) { [weak self] series in
            guard let self, ownerID == DIContainer.shared.authService.currentUserID, self.heartRateRequest == request else { return }
            let recordingSamples = evidence.sensors?.heartRate ?? []
            self.usesRecordingHeartRate = series.count < 2 && !recordingSamples.isEmpty
            self.heartRateSamples = self.usesRecordingHeartRate ? recordingSamples : series
            self.recalculateZones()
        }
    }

    func applyZoneSettings(_ settings: RunHeartRateZoneSettings) -> Bool {
        guard let ownerID = exportOwnerID, ownerID == DIContainer.shared.authService.currentUserID else { return false }
        do {
            try RunHeartRateZoneStore().saveSettings(settings, userID: ownerID)
            zoneSettings = settings
            zoneSettingsError = nil
            recalculateZones()
            return zoneSettingsError == nil
        } catch {
            zoneSettingsError = "Zone settings could not be saved. Your entries are kept; try again."
            return false
        }
    }

    private func recalculateZones() {
        guard let run = heartRateRun else { return }
        let coverage = RunHeartRateEvidence.coverage(samples: heartRateSamples, run: run, settings: zoneSettings)
        heartRateZoneSeconds = zoneSettingsError == nil && coverage.coveredSeconds > 0 ? coverage.zoneSeconds : nil
        if let average = coverage.averageBPM { averageHeartRate = average }
        if coverage.coveredSeconds > 0 {
            heartRateEvidenceDescription = "\(RunFormat.durationText(seconds: coverage.coveredSeconds)) of sample coverage · \(coverage.sourceNames.joined(separator: ", ")). \(usesRecordingHeartRate ? "Readings captured during the original recording" : "Workout-associated Health samples"); missing time, source changes and original known pauses are excluded."
            if let ownerID = exportOwnerID, ownerID == DIContainer.shared.authService.currentUserID, zoneSettingsError == nil {
                do {
                    zoneReview = try RunHeartRateZoneStore().review(runID: run.recordingID ?? run.id, settings: zoneSettings, userID: ownerID)
                } catch { zoneSettingsError = "Your zone display could not be checkpointed. Earlier method history stays unchanged." }
            }
        } else {
            heartRateEvidenceDescription = "No usable workout-associated or recording-captured heart-rate series is available. A phone alone does not measure heart rate; missing readings are not estimated."
        }
    }

    func load(run: Run, metric: Bool) {
        exportOwnerID = DIContainer.shared.authService.currentUserID
        if let exportOwnerID {
            exportJob = try? RunHealthExportJobStore().load(recordingID: run.recordingID ?? run.id, userID: exportOwnerID)
        }
        splits = run.splits
        averageHeartRate = run.averageHeartRate
        workoutResult = run.workoutResult ?? workoutResultStore.result(forRunID: run.id)
            ?? run.recordingID.flatMap { workoutResultStore.result(forRunID: $0) }

        let ownerID = DIContainer.shared.authService.currentUserID
        if let ownerID {
            importer.fetchLifetimeRuns(userID: ownerID) { [weak self] result in
                guard ownerID == DIContainer.shared.authService.currentUserID else { return }
                if case .success(let history) = result {
                    let eligible = RunComparisonRules.eligible(for: run, among: history)
                    self?.comparableRuns = eligible
                    self?.ghostPaceComparison = RunStats.ghostPaceComparison(for: run, against: eligible)
                }
            }
        }
        importer.fetchRouteSegments(for: run, userID: ownerID) { [weak self] segments in
            guard let self, ownerID == DIContainer.shared.authService.currentUserID else { return }
            let orderedFixes = segments.flatMap { $0 }.sorted { $0.timestamp < $1.timestamp }
            self.routePaceSlices = RunRoutePaceOverlay.slices(segments)
            self.routeSegments = segments.filter { $0.count > 1 }.map { segment in
                segment.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            }
            // Imports carry no splits — replay the GPS trace through the same engine the
            // live recorder uses. Historical splits retain elapsed gaps so their times
            // reconcile with the HealthKit workout summary after weak/indoor GPS periods.
            if self.splits.isEmpty, segments.count == 1, orderedFixes.count > 1 {
                let replay = RunSession(metric: metric, timeAccounting: .elapsed)
                replay.start(at: run.startDate)
                orderedFixes.forEach { replay.ingest($0) }
                if let replayed = replay.finish(at: run.endDate) {
                    self.splits = replayed.splits
                }
            }
            self.isLoadingRoute = false
        }

    }

    func retryHealth(run: Run, metric: Bool) {
        guard !isSyncingHealth, let ownerID = exportOwnerID,
              ownerID == DIContainer.shared.authService.currentUserID, let job = exportJob else { return }
        isSyncingHealth = true
        RunHealthExportCoordinator().export(run: job.run, weightLbs: job.weightLbs, userID: ownerID) { [weak self] outcome in
            guard let self, ownerID == DIContainer.shared.authService.currentUserID else { return }
            self.isSyncingHealth = false
            switch outcome {
            case .saved: self.exportMessage = "Apple Health sync confirmed."
            case .savedRoutePending: self.exportMessage = "The workout is saved. Route sync is still unavailable; no second workout was created."
            case .savedAwaitingReadAccess: self.exportMessage = "Health confirmation is unavailable. No new workout was written."
            case .confirmationRequired: self.exportMessage = "The previous Health result is unknown. No new workout was written."
            case .failed: self.exportMessage = "Your run stays saved in MyFitPlate. Health sync could not finish."
            }
            self.load(run: run, metric: metric)
        }
    }

}

/// Shared by saved run detail and the recorder's save receipt. Unknown histories
/// never turn elapsed-minus-active into invented pause events.
struct RunTimingSummaryCard: View {
    let run: Run
    let accessibilityPrefix: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summary: RunPauseTimeline.Summary? {
        run.pauseTimeline?.summary(startDate: run.startDate, endDate: run.endDate, activeSeconds: run.movingSeconds)
    }

    private var manualTiming: Bool { run.isIndoor && run.source == .recorded && summary == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Time and pauses")
            timingRow("Active time", value: duration(run.movingSeconds), key: "active")
            timingRow("Elapsed time", value: manualTiming ? "Not recorded" : duration(run.endDate.timeIntervalSince(run.startDate)), key: "elapsed")
            if let summary {
                timingRow(summary.completeness == .complete ? "Paused" : "Known pauses", value: duration(summary.explicitPauseSeconds), key: "paused")
                if summary.recoveryGapSeconds > 0 {
                    timingRow("Time away", value: duration(summary.recoveryGapSeconds), key: "recovery")
                }
            } else {
                timingRow("Pause history", value: "Not recorded", key: "paused")
            }
            Text(timingNote)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityPrefix + "_note")
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityPrefix)
    }

    private func timingRow(_ title: String, value: String, key: String) -> some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
         : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.row))) {
            Text(title).appTextRole(.secondary).foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: AppSpacing.compact) }
            Text(value).appTextRole(.control).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityIdentifier(accessibilityPrefix + "_" + key)
    }

    private var timingNote: String {
        if let summary {
            if summary.completeness == .partial {
                return "Active time excludes breaks. These are the known pauses; part of the pause history is missing, so exact full pause timing can't be exported to Apple Health."
            }
            if summary.recoveryGapSeconds > 0 {
                return "Active time and average pace exclude pauses and time away. Time away is the gap excluded when an interrupted recording was recovered. Its timing is retained for Apple Health."
            }
            return "Active time and average pace exclude pauses. Elapsed time spans start to finish. Recorded pause timing is available for Apple Health."
        }
        if manualTiming {
            return "Only the treadmill's active time was entered. Breaks and total elapsed time weren't recorded; exact pause events can't be reconstructed for Apple Health."
        }
        return "Active time is the saved workout duration; elapsed time spans start to finish. Pause history wasn't recorded or supplied by the source. Exact pause events can't be reconstructed for Apple Health."
    }

    private func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Unavailable" }
        return RunFormat.durationText(seconds: seconds)
    }
}

private struct RunPacingReviewCard: View {
    let analysis: RunPacingAnalysis.Result
    let metric: Bool
    let structured: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Pacing review", subtitle: analysis.source == .routeReplay ? "Route-derived estimate" : "From your saved splits")
            Label(structured ? "Structured session" : "Steady or open run", systemImage: structured ? "repeat" : "figure.run")
                .appTextRole(.control)
            Text(structured ? "Changes of pace are part of this workout. Review each effort and recovery before interpreting whole-run consistency."
                 : "Use evenness and the finish as observations about this run. Terrain, stops and your chosen effort can explain differences.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            AppMetricStrip(items: [
                AppMetricItem(label: "First half", value: RunFormat.paceText(secondsPerKm: analysis.firstHalfPaceSecondsPerKm, metric: metric) ?? "—", accent: AppPalette.effort),
                AppMetricItem(label: "Second half", value: RunFormat.paceText(secondsPerKm: analysis.secondHalfPaceSecondsPerKm, metric: metric) ?? "—", accent: AppPalette.effort)
            ])
            Text("Each half covers \(RunFormat.distanceText(meters: analysis.halfDistanceMeters, metric: metric)).")
                .appTextRole(.caption).foregroundStyle(.secondary)
            Text(finishSummary)
                .appTextRole(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("run_pacing_finish")
            if let fastest = analysis.fastestCompleteSplitIndex {
                Text("Fastest full split: \(fastest)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("run_pacing_fastest")
            }
            if let spread = analysis.completeSplitPaceSpreadSecondsPerKm {
                Text("Pace spread across \(analysis.completeSplitCount) equal full splits: \(differenceText(spread))")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            Text(analysis.source == .routeReplay
                 ? "Estimated from route timestamps. GPS gaps can affect these splits; pause gaps are not treated as measured active pace."
                 : "Halves are split by distance, including a partial final split. Fastest and spread compare equal full splits only. Planned intervals can change pace on purpose.")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("run_pacing_note")
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("run_detail_pacing")
    }

    private var finishSummary: String {
        let delta = analysis.finishDeltaSecondsPerKm
        let displayedSeconds = abs(delta) * (metric ? 1 : RunFormat.metersPerMile / 1000)
        guard displayedSeconds >= 1 else { return "The half paces were within 1 s/\(metric ? "km" : "mi")." }
        return "Second half was \(differenceText(delta)) \(delta > 0 ? "faster" : "slower")."
    }

    private func differenceText(_ secondsPerKm: Double) -> String {
        RunFormat.paceDiffText(secondsPerKmDiff: abs(secondsPerKm), metric: metric)
            .trimmingCharacters(in: CharacterSet(charactersIn: "+"))
    }
}

struct RunDetailView: View {
    private let originalRun: Run
    @State private var reviewedRun: Run?
    @Environment(\.dismiss) private var dismiss
    private var run: Run { reviewedRun ?? originalRun }
    init(run: Run) {
        originalRun = run
        _projectionOwner = State(initialValue: DIContainer.shared.authService.currentUserID)
    }
    @EnvironmentObject private var accountState: AppState
    @State private var projectionOwner: String?
    @State private var projectionInvalidated = false
    @StateObject private var viewModel = RunDetailViewModel()
    @StateObject private var shoeStore = RunningShoeStore()
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingStoryPoster = false
    @State private var showingSummaryExport = false
    @State private var showingRunReview = false
    @State private var dismissAfterRunReview = false
    @State private var runReviewNotice: String?
    @State private var showingZoneSettings = false
    @State private var routeOverlay = false
    @State private var repeatPreview: RunWorkoutPlan?
    @State private var repeatedPlan: RunWorkoutPlan?
    @State private var pendingRepeatedPlan: RunWorkoutPlan?
    @State private var repeatEditor: RunWorkoutPlan?
    @State private var previewAfterEditor: RunWorkoutPlan?
    @StateObject private var repeatPlans = RunWorkoutPlanStore()
    @State private var showingPauseEditor = false
    @State private var showingImportedNote = false
    @State private var showingPermanentExclusion = false
    @State private var exclusionError: String?
    @State private var shoeAssignmentReceipt: RunShoeAssignmentReceipt?
    @State private var shoeAssignmentError: String?
    @EnvironmentObject private var trainingFuelPlanStore: TrainingFuelPlanStore

    var body: some View {
        lifecycleContent
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                statsSummary
                reviewStatus
                RunTimingSummaryCard(run: run, accessibilityPrefix: "run_detail_timing")
                if !viewModel.splits.isEmpty { splitsCard }
                if let laps = run.manualLaps, !laps.isEmpty { RunManualLapsCard(laps: laps, metric: useMetric) }
                routeHeader
                healthSyncCard
                analysisCards
                workoutResultSection
                runFuelSection

                if let comparison = viewModel.ghostPaceComparison {
                    ghostPaceCard(comparison)
                }
                comparableRunsCard

                shoeTagCard

                Label("Recorded with \(run.source.displayName)", systemImage: "heart.text.clipboard")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("run_detail_source")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
    }

    // Keep large presentation chains behind explicit type-erasure boundaries.
    // This also limits Release specialization of nested SwiftUI destinations.
    private var baseContent: some View {
        AnyView(detailScroll)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("run_detail_screen")
        .opacity(projectionInvalidated ? 0 : 1)
        .allowsHitTesting(!projectionInvalidated)
        .accessibilityHidden(projectionInvalidated)
        .onReceive(accountState.$isUserLoggedIn) { _ in
            guard projectionOwner != DIContainer.shared.authService.currentUserID else { return }
            projectionInvalidated = true
            showingRunReview = false; showingSummaryExport = false; showingStoryPoster = false
            showingZoneSettings = false
            showingPauseEditor = false; showingImportedNote = false; showingPermanentExclusion = false
            repeatPreview = nil; repeatEditor = nil; repeatedPlan = nil; pendingRepeatedPlan = nil; previewAfterEditor = nil
            dismiss()
        }
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Share story image", systemImage: "photo") { showingStoryPoster = true }
                    Button("Export run summary", systemImage: "tablecells") { showingSummaryExport = true }
                    Button("Review or hide run", systemImage: "pencil.circle") { showingRunReview = true }
                    if !Calendar.current.isDateInToday(run.endDate), linkedFuelReview == nil {
                        openFuelPlannerButton
                    }
                    if run.source == .recorded, run.pauseTimeline?.completeness == .complete {
                        Button("Review pause times", systemImage: "pause.circle") { showingPauseEditor = true }
                    }
                    if run.source != .recorded {
                        Button("Add or edit personal note", systemImage: "note.text") { showingImportedNote = true }
                        Button("Use as workout draft", systemImage: "doc.on.doc") { repeatEditor = importedWorkoutDraft }
                        Button("Remove from MyFitPlate", systemImage: "trash", role: .destructive) { showingPermanentExclusion = true }
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundColor(.brandForeground) }
                .accessibilityLabel("Run options").accessibilityIdentifier("run_detail_options")
            }
        }
    }

    private var reviewPresentationContent: some View {
        AnyView(baseContent)
        .sheet(isPresented: $showingZoneSettings) {
            RunHeartRateZoneSettingsSheet(initial: viewModel.zoneSettings, age: dailyLogService.goalSettings?.age ?? 30,
                error: viewModel.zoneSettingsError, onSave: viewModel.applyZoneSettings)
        }
        .sheet(isPresented: $showingPauseEditor) {
            RunPauseEditorSheet(run: run, metric: useMetric) { updated in reviewedRun = updated; viewModel.load(run: updated, metric: useMetric) }
        }
        .sheet(isPresented: $showingImportedNote) {
            RunImportedNoteSheet(run: run) { updated in reviewedRun = updated }
        }
        .confirmationDialog("Permanently remove this imported run from MyFitPlate?", isPresented: $showingPermanentExclusion, titleVisibility: .visible) {
            Button("Remove from MyFitPlate permanently", role: .destructive) {
                guard let owner = projectionOwner, owner == DIContainer.shared.authService.currentUserID else { return }
                do {
                    let store = RunReviewStore()
                    let review = try store.review(run: run, mutation: .excludeImportPermanently, userID: owner)
                    _ = try store.commit(review, currentUserID: owner)
                    dismiss()
                } catch { exclusionError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(run.startDate.formatted(date: .abbreviated, time: .shortened)) · \(RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric)). This has no Undo and prevents future imports of this record into MyFitPlate. Its audit reference, Apple Health record, diary activity and training completion stay intact. Delete the source workout in its original app or Apple Health separately if needed.")
        }
        .alert("Run could not be removed", isPresented: Binding(get: { exclusionError != nil }, set: { if !$0 { exclusionError = nil } })) {
            Button("OK") { exclusionError = nil }
        } message: { Text(exclusionError ?? "") }
    }

    private var shareAndRepeatContent: some View {
        AnyView(reviewPresentationContent)
        .sheet(item: $repeatPreview, onDismiss: {
            repeatedPlan = pendingRepeatedPlan; pendingRepeatedPlan = nil
        }) { plan in
            RunWorkoutPreviewSheet(plan: plan, metric: useMetric, onStart: {
                pendingRepeatedPlan = plan; repeatPreview = nil
            }, onEdit: nil)
        }
        .fullScreenCover(item: $repeatedPlan) { plan in RunRecorderView(plan: plan) }
        .sheet(item: $repeatEditor, onDismiss: {
            repeatPreview = previewAfterEditor; previewAfterEditor = nil
        }) { draft in
            RunWorkoutStepTemplateEditorSheet(metric: useMetric, initialPlan: draft, plans: repeatPlans, duplicate: true) { plan in
                previewAfterEditor = plan; repeatEditor = nil
            }
        }
        .sheet(isPresented: $showingRunReview, onDismiss: {
            if dismissAfterRunReview { dismiss() } else { refreshRunReviewNotice() }
        }) {
            RunReviewSheet(run: run, metric: useMetric, onChanged: { updated in
                reviewedRun = updated
                viewModel.load(run: updated, metric: useMetric)
            }, onHidden: { dismissAfterRunReview = true })
        }
        .sheet(isPresented: $showingSummaryExport) { RunSummaryExportView(run: run) }
        .sheet(isPresented: $showingStoryPoster) {
            RunStoryPosterView(run: run, routeSegments: viewModel.routeSegments, useMetric: useMetric)
        }
    }

    private var lifecycleContent: some View {
        AnyView(shareAndRepeatContent)
        .onAppear {
            guard refreshAcceptedProjection() else { return }
            trainingFuelPlanStore.load(for: projectionOwner)
            viewModel.load(run: run, metric: useMetric)
            refreshRunReviewNotice()
            let age = dailyLogService.goalSettings?.age ?? 30
            viewModel.loadHeartRateZones(run: run, age: age)
        }
        .onReceive(NotificationCenter.default.publisher(for: .runLibrariesChanged)) { notification in
            guard let owner = projectionOwner, notification.object as? String == owner,
                  owner == DIContainer.shared.authService.currentUserID else { return }
            let earlier = run
            if refreshAcceptedProjection(), earlier != run { viewModel.load(run: run, metric: useMetric) }
        }
    }

    private func refreshAcceptedProjection() -> Bool {
        guard let owner = projectionOwner, owner == DIContainer.shared.authService.currentUserID else { return false }
        do {
            guard let latest = try RunReviewStore().projecting([originalRun], userID: owner).first else { dismiss(); return false }
            if latest != run { reviewedRun = latest }
            return true
        } catch {
            runReviewNotice = "Your latest run review could not be read. Existing evidence is kept."
            return false
        }
    }

    @ViewBuilder private var routeHeader: some View {
        if !viewModel.routeCoordinates.isEmpty {
            routeMap
        } else if run.isIndoor {
            Label("Indoor run", systemImage: "figure.run.treadmill")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .appSurface(.quiet, padding: AppSpacing.compact, radius: AppRadius.control)
        }
    }

    @ViewBuilder private var reviewStatus: some View {
        if let runReviewNotice {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(runReviewNotice).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                Button("Open pending review") { showingRunReview = true }
            }.appSurface(.interpreted)
        }
        if let correction = run.reviewAnnotation { annotationCard(correction) }
    }

    private func annotationCard(_ correction: RunReviewAnnotation) -> some View {
        let title: String
        let explanation: String
        if correction.note != nil {
            title = "Your note"
            explanation = "Personal annotation in MyFitPlate. The imported workout's measurements stay unchanged."
        } else {
            title = correction.originalPauseTimeline == nil ? "Totals reviewed" : "Pauses reviewed"
            let distance = RunFormat.distanceText(meters: correction.originalDistanceMeters, metric: useMetric)
            let time = RunFormat.durationText(seconds: correction.originalMovingSeconds)
            explanation = "Original: \(distance) · \(time) active. GPS distance, measured splits, workout steps and sensor evidence keep their original values. Apple Health retains the original record; Undo is in Run reviews."
        }
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(title, systemImage: "pencil.circle").appTextRole(.control)
            Text(correction.note ?? correction.reason).appTextRole(.secondary)
            Text(explanation).appTextRole(.caption).foregroundStyle(.secondary)
        }.appSurface(.interpreted)
    }

    @ViewBuilder private var healthSyncCard: some View {
        if let job = viewModel.exportJob {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label("Apple Health sync", systemImage: "heart.text.clipboard").appTextRole(.secondary)
                Text(viewModel.exportMessage ?? job.statusText).appTextRole(.caption).foregroundStyle(.secondary)
                if job.phase != .complete {
                    Button(viewModel.isSyncingHealth ? "Checking…" : "Check Health sync") {
                        viewModel.retryHealth(run: run, metric: useMetric)
                    }.buttonStyle(AppActionButtonStyle(.secondary)).disabled(viewModel.isSyncingHealth)
                        .accessibilityIdentifier("run_detail_retry_health")
                    if job.expectsRoute {
                        Text("Private route recovery is kept for up to 30 days and 20 recent recordings. Your saved run totals remain in history.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
            }.appSurface(.quiet).accessibilityIdentifier("run_detail_health_receipt")
        }
    }

    @ViewBuilder private var analysisCards: some View {
        if let pacing = RunPacingAnalysis.analyze(run: run, splits: viewModel.splits,
                                                 source: run.splits.isEmpty ? .routeReplay : .saved) {
            RunPacingReviewCard(analysis: pacing, metric: useMetric, structured: RunComparisonRules.effort(run) == .structured)
        }
        if let zones = viewModel.heartRateZoneSeconds {
            heartRateZonesCard(zones)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack {
                    Text("Heart rate").appTextRole(.control)
                    Spacer(minLength: AppSpacing.compact)
                    Button("Zone settings") { showingZoneSettings = true }
                        .appTextRole(.secondary)
                        .accessibilityIdentifier("run_zone_settings")
                }
                DisclosureGroup {
                    Text(viewModel.heartRateEvidenceDescription)
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .padding(.top, AppSpacing.compact)
                } label: {
                    Text("About available readings").accessibilityIdentifier("run_heart_rate_evidence")
                }
                .appTextRole(.secondary).tint(AppPalette.text)
                if let error = viewModel.zoneSettingsError { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }.appSurface(.quiet)
        }
    }

    @ViewBuilder private var workoutResultSection: some View {
        if let workoutResult = viewModel.workoutResult {
            RunWorkoutResultCard(result: workoutResult, metric: useMetric)
            if let snapshot = RunResultPresentation.repeatPlan(workoutResult, metric: useMetric) {
                Button("Repeat workout", systemImage: "repeat") { repeatPreview = snapshot }
                    .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("run_repeat_workout")
                if !(workoutResult.goalRevisions ?? []).isEmpty {
                    Text("Repeat uses your final reviewed target in a new workout copy. The original prescription and goal-change receipts stay in this run.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            } else if let draft = RunResultPresentation.observedStepsDraft(workoutResult) {
                Button("Copy observed steps to a draft", systemImage: "doc.on.doc") { repeatEditor = draft }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                Text("The full original plan or its goal-change chain is unavailable. Review the observed steps before saving; unstarted steps cannot be recovered.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshRunReviewNotice() {
        guard let owner = DIContainer.shared.authService.currentUserID else { runReviewNotice = nil; return }
        do {
            let pending = try RunDiaryCorrectionCoordinator(service: dailyLogService).pending(run: run, userID: owner)
            runReviewNotice = pending == nil ? nil : "A linked diary correction is still pending. The run keeps its last accepted totals until this exact review is confirmed."
        } catch { runReviewNotice = "The pending run review could not be read. Its saved evidence is kept unchanged." }
    }

    @ViewBuilder private var comparableRunsCard: some View {
        if viewModel.comparableRuns.isEmpty {
            Label("No comparable run in this distance range", systemImage: "chart.line.uptrend.xyaxis")
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .accessibilityIdentifier("run_eligible_comparisons")
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Similar runs", subtitle: "Earlier \(run.isIndoor ? "indoor" : "outdoor") runs within 20% of this distance, with the same session type.")
                ForEach(Array(viewModel.comparableRuns.prefix(3))) { previous in
                    NavigationLink {
                        RunDetailView(run: previous)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(previous.startDate.formatted(date: .abbreviated, time: .omitted)).appTextRole(.control)
                            Text("\(RunFormat.distanceText(meters: previous.distanceMeters, metric: useMetric)) · \(RunFormat.paceText(secondsPerKm: previous.averagePaceSecondsPerKm, metric: useMetric) ?? "—")")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                }
                Text("\(viewModel.comparableRuns.count) eligible runs. Routes, weather and effort are not matched; these are observations, not a fitness prediction.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.appSurface(.quiet).accessibilityIdentifier("run_eligible_comparisons")
        }
    }

    private var importedWorkoutDraft: RunWorkoutPlan {
        let goal: RunWorkoutStep.Goal = run.distanceMeters >= 100 ? .distance(meters: run.distanceMeters) : .duration(seconds: max(1, run.movingSeconds))
        return RunWorkoutPlan(name: "Run inspired by \(run.startDate.formatted(date: .abbreviated, time: .omitted))",
            subtitle: "New workout draft · imported evidence unchanged", steps: [
                RunWorkoutStep(kind: .hard, title: "Run", goal: goal, target: RunWorkoutTarget(cue: "Choose your own effort"))
            ])
    }

    private var shoeTagCard: some View {
        let store = shoeStore
        let currentShoe = store.explicitShoeID(for: run).flatMap { store.shoe(for: $0) }
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    shoeIdentity(currentShoe)
                    shoeSelectionMenu(store: store, currentShoe: currentShoe)
                        .padding(.leading, 50)
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    shoeIdentity(currentShoe)
                    Spacer(minLength: AppSpacing.compact)
                    shoeSelectionMenu(store: store, currentShoe: currentShoe)
                }
            }
            }
            if let receipt = shoeAssignmentReceipt {
                Button("Undo shoe assignment") {
                    do { try store.undoAssignment(receipt); shoeAssignmentReceipt = nil; shoeAssignmentError = nil } catch { shoeAssignmentError = error.localizedDescription }
                }.accessibilityIdentifier("run_detail_shoe_undo")
            }
            if let message = shoeAssignmentError { Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_gear")
    }

    private func shoeIdentity(_ currentShoe: RunningShoe?) -> some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: "shoeprints.fill")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(Color.accentProtein)
                .frame(width: 40, height: 40)
                .background(Color.accentProtein.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(shoeStore.explicitShoeID(for: run) == nil ? "Unassigned" : "Gear tagged")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Text(currentShoe.map { "\($0.brand) · \($0.name)" }
                     ?? (shoeStore.explicitShoeID(for: run) == nil ? "Assign a shoe" : "Saved shoe unavailable"))
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shoeSelectionMenu(store: RunningShoeStore, currentShoe: RunningShoe?) -> some View {
        Menu {
            Button("None") { assignShoe(nil, store: store) }
            ForEach(store.shoes) { shoe in
                Button {
                    HapticManager.instance.feedback(.light)
                    assignShoe(shoe.id, store: store)
                } label: {
                    HStack {
                        Text("\(shoe.brand) · \(shoe.name)")
                        if currentShoe?.id == shoe.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Change", systemImage: "chevron.up.chevron.down")
                .appTextRole(.caption)
                .foregroundStyle(AppPalette.brandText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("Change running shoe")
    }

    private func assignShoe(_ shoeID: String?, store: RunningShoeStore) {
        guard let ownerID = DIContainer.shared.authService.currentUserID else { return }
        do {
            let review = try store.reviewAssignment(runs: [run], shoeID: shoeID, userID: ownerID)
            shoeAssignmentReceipt = try store.commitAssignment(review)
            shoeAssignmentError = nil
        } catch { shoeAssignmentError = error.localizedDescription }
    }

    private func ghostPaceCard(_ comparison: RunStats.GhostPaceComparison) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        ghostPaceIcon(comparison)
                        ghostPaceCopy(comparison)
                    }

                    if let prPace = RunFormat.paceText(secondsPerKm: comparison.prPaceSecondsPerKm, metric: useMetric) {
                        Divider()
                        HStack(alignment: .firstTextBaseline) {
                            Text("Distance best")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: AppSpacing.group)
                            Text(prPace)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.brandText)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    ghostPaceIcon(comparison)
                    ghostPaceCopy(comparison)
                    Spacer(minLength: AppSpacing.compact)

                    if let prPace = RunFormat.paceText(secondsPerKm: comparison.prPaceSecondsPerKm, metric: useMetric) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Distance best")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                            Text(prPace)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.brandText)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_ghost_pace")
    }

    private func ghostPaceIcon(_ comparison: RunStats.GhostPaceComparison) -> some View {
        Image(systemName: comparison.isPR ? "trophy.fill" : "figure.run")
            .appFont(size: 20, weight: .semibold)
            .foregroundStyle(comparison.isPR ? AppPalette.achievement : AppPalette.brandText)
            .frame(width: 42, height: 42)
            .background(
                (comparison.isPR ? AppPalette.achievement : AppPalette.brand).opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func ghostPaceCopy(_ comparison: RunStats.GhostPaceComparison) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(comparison.isPR ? "Best among similar runs" : "Similar runs")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text("Compared with \(comparison.matchingRunsCount) \(run.isIndoor ? "indoor" : "outdoor") runs within 5% of this distance and the same known workout-step pattern. Routes and conditions can differ.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let diffText = RunFormat.paceDiffText(secondsPerKmDiff: comparison.paceDifferenceVsAverage, metric: useMetric)
            Text("\(diffText) vs similar-distance average")
                .appTextRole(.secondary)
                .foregroundStyle(comparison.paceDifferenceVsAverage < 0 ? AppPalette.positive : AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var routeMap: some View {
        VStack(spacing: 8) {
            if !viewModel.routePaceSlices.isEmpty {
                Toggle("Pace overlay", isOn: $routeOverlay).appTextRole(.control)
                    .accessibilityIdentifier("run_route_pace_overlay")
            }
            Map(interactionModes: []) {
                ForEach(Array(viewModel.routeSegments.enumerated()), id: \.offset) { _, coordinates in
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.brandPrimary, lineWidth: 4)
                }
                if routeOverlay {
                    ForEach(viewModel.routePaceSlices) { slice in
                        MapPolyline(coordinates: slice.fixes.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .stroke(slice.secondsPerKm < (run.averagePaceSecondsPerKm ?? slice.secondsPerKm) ? AppPalette.effort : AppPalette.recovery, lineWidth: 5)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
            .accessibilityLabel("Route map of this run")
            .accessibilityIdentifier("run_detail_route")
            if viewModel.routeSegments.count > 1 {
                Text("Gaps show pauses, interruptions or missing GPS. No route is drawn between recorded segments.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            if routeOverlay {
                HStack {
                    Label("Faster", systemImage: "circle.fill").foregroundStyle(AppPalette.effort)
                    Label("Slower", systemImage: "circle.fill").foregroundStyle(AppPalette.recovery)
                }.appTextRole(.caption)
                Text("Relative to this run's average pace. Short GPS windows are estimates; gaps and invalid fixes have no overlay.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Training zone of the run's *average* HR (not time-in-zone — that needs a per-sample
    /// HR series we don't capture yet). Max HR is age-predicted from the user's profile.
    private var hrZoneText: String? {
        guard viewModel.zoneSettingsError == nil, let bpm = viewModel.averageHeartRate, bpm.isFinite else { return nil }
        guard let zone = viewModel.zoneSettings.zone(for: bpm) else { return nil }
        return "Z\(zone.number) · \(zone.name)"
    }

    private var statsSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Run summary")
            AppMetricStrip(items: statItems)
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("run_detail_metrics")
    }

    private var statItems: [AppMetricItem] {
        var items = [
            AppMetricItem(
                id: "distance",
                label: "Distance",
                value: RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric),
                accent: AppPalette.effort
            )
        ]

        if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: useMetric) {
            items.append(AppMetricItem(id: "pace", label: "Avg pace", value: pace, accent: AppPalette.effort))
        }
        if let bpm = viewModel.averageHeartRate, bpm.isFinite {
            items.append(
                AppMetricItem(
                    id: "heart-rate",
                    label: "Avg heart rate",
                    value: "\(Int(bpm.rounded())) bpm",
                    accent: AppPalette.effort
                )
            )
            if let zone = hrZoneText {
                items.append(AppMetricItem(id: "heart-rate-zone", label: "Avg HR zone", value: zone, accent: AppPalette.effort))
            }
        }
        if let calories = run.activeCalories {
            items.append(
                AppMetricItem(
                    id: "calories",
                    label: "Calories",
                    value: "\(Int(calories.rounded()).formatted()) cal",
                    accent: AppPalette.energy
                )
            )
        }

        return items
    }

    /// Measured time in heart-rate zones uses the conventional cool-to-hot data palette
    /// alongside labeled zones. Only shown when the run carried a real HR series.
    private func heartRateZonesCard(_ seconds: [Double]) -> some View {
        let total = max(seconds.reduce(0, +), 1)
        let colors: [Color] = [AppPalette.recovery, AppPalette.positive, AppPalette.brand, AppPalette.effort, AppPalette.caution]
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack {
                Text("Heart-rate zones").appTextRole(.control).foregroundStyle(AppPalette.text)
                Spacer()
                Button("Settings") { showingZoneSettings = true }.accessibilityIdentifier("run_zone_settings")
            }
            Text(viewModel.zoneSettings.description).appTextRole(.caption).foregroundStyle(.secondary)
            Text(viewModel.heartRateEvidenceDescription).appTextRole(.caption).foregroundStyle(.secondary)
            if let review = viewModel.zoneReview, review.originalMethod != review.displayedMethod {
                Text("Recalculated display. First reviewed with \(review.originalMethod.description.lowercased()).")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if let error = viewModel.zoneSettingsError { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }

            ForEach(Array(HeartRateZones.zones.enumerated()), id: \.offset) { index, zone in
                let secs = index < seconds.count ? seconds[index] : 0
                heartRateZoneRow(
                    zone: zone,
                    seconds: secs,
                    total: total,
                    color: colors[index]
                )
                Text(viewModel.zoneSettings.rangeDescription(zoneNumber: zone.number))
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_heart_rate_zones")
    }

    private func heartRateZoneRow(
        zone: HeartRateZone,
        seconds: Double,
        total: Double,
        color: Color
    ) -> some View {
        let duration = seconds > 0 ? RunFormat.durationText(seconds: seconds) : "–"
        let ratio = max(0, min(1, seconds / total))

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        Text("Z\(zone.number)")
                            .appTextRole(.caption)
                            .foregroundStyle(color)
                        Text(zone.name)
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: AppSpacing.compact)
                        Text(duration)
                            .appTextRole(.secondary)
                            .foregroundStyle(seconds > 0 ? AppPalette.text : Color.secondary)
                            .monospacedDigit()
                    }
                    zoneProgress(ratio: ratio, color: color)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Z\(zone.number)")
                        .appTextRole(.caption)
                        .foregroundStyle(color)
                        .frame(width: 24, alignment: .leading)
                    Text(zone.name)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    zoneProgress(ratio: ratio, color: color)
                    Text(duration)
                        .appTextRole(.caption)
                        .foregroundStyle(seconds > 0 ? AppPalette.text : Color.secondary)
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(zone.number), \(zone.name), \(duration)")
    }

    private func zoneProgress(ratio: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14))
                Capsule().fill(color)
                    .frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var linkedFuelReview: RunFuelReviewRequest? {
        guard let owner = projectionOwner else { return nil }
        return RunFuelReviewRequest.make(run: run, history: trainingFuelPlanStore.history,
            conflictingPlanIDs: trainingFuelPlanStore.conflictingPlanIDs, ownerID: owner)
    }

    @ViewBuilder private var runFuelSection: some View {
        let request = linkedFuelReview
        if request != nil || Calendar.current.isDateInToday(run.endDate) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(title: "Fuel and recovery")
                if let request {
                    Text("Meals and targets for \(request.day.displayDate.formatted(date: .abbreviated, time: .omitted)).")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Button("Review linked fuel plan", systemImage: "fork.knife") {
                        if accountState.openRunFuelReview(request) { dismiss() }
                    }.buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("run_detail_recovery_action")
                } else {
                    Text("Plan meals for your next run using your daily targets.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    openFuelPlannerButton.buttonStyle(AppActionButtonStyle(.secondary))
                }
            }
            .appSurface(.quiet).accessibilityIdentifier("run_detail_recovery")
        }
    }

    private var openFuelPlannerButton: some View {
        Button("Open Training Fuel", systemImage: "fork.knife") {
            if let owner = projectionOwner, let request = RunFuelReviewRequest.planning(ownerID: owner),
               accountState.openRunFuelReview(request) { dismiss() }
        }.accessibilityIdentifier("run_detail_open_fuel_planner")
    }

    private var splitsCard: some View {
        let analysis = RunPacingAnalysis.analyze(run: run, splits: viewModel.splits,
                                                source: run.splits.isEmpty ? .routeReplay : .saved)
        let maxPace = viewModel.splits.compactMap { $0.paceSecondsPerKm }.max() ?? 300
        let minPace = viewModel.splits.compactMap { $0.paceSecondsPerKm }.min() ?? 240

        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Splits", subtitle: run.splits.isEmpty ? "Route-derived elapsed-time estimates" : nil)

            if run.isIndoor && run.source == .recorded {
                Text("Treadmill split pace is estimated from the total distance and moving time you entered.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }

            ForEach(viewModel.splits, id: \.index) { split in
                let isBest = split.index == analysis?.fastestCompleteSplitIndex
                let pace = split.paceSecondsPerKm
                let barRatio = pace.map {
                    min(1.0, max(0.15, 1.0 - (($0 - minPace) / (max(1, maxPace - minPace) * 1.5))))
                } ?? 0.5
                splitRow(split, isBest: isBest, barRatio: barRatio)
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_detail_splits")
    }

    private func splitRow(_ split: RunSplit, isBest: Bool, barRatio: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        splitIdentity(split, isBest: isBest)
                        splitPace(split, isBest: isBest)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        splitIdentity(split, isBest: isBest)
                        Spacer(minLength: AppSpacing.compact)
                        splitPace(split, isBest: isBest)
                    }
                }
            }

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isBest ? AppPalette.achievement : AppPalette.effort.opacity(0.60))
                    .frame(width: geometry.size.width * barRatio, height: 4)
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func splitIdentity(_ split: RunSplit, isBest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
            Text("\(split.index)")
                .appTextRole(.secondary)
                .foregroundStyle(isBest ? AppPalette.achievement : Color.secondary)
                .frame(minWidth: 24, alignment: .leading)
            Text(splitDistanceText(split))
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
            if isBest {
                Label("Fastest full", systemImage: "medal.fill")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.achievement)
            }
        }
    }

    private func splitPace(_ split: RunSplit, isBest: Bool) -> some View {
        Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: useMetric) ?? RunFormat.durationText(seconds: split.seconds))
            .appTextRole(.secondary)
            .foregroundStyle(isBest ? AppPalette.achievement : AppPalette.text)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private func splitDistanceText(_ split: RunSplit) -> String {
        RunFormat.distanceText(meters: split.distanceMeters, metric: useMetric)
    }
}

// MARK: - Records

struct RunRecordsCard: View {
    let records: RunStats.PersonalRecords
    let metric: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasAnything: Bool {
        records.longestRun != nil || records.best5KSeconds != nil || records.best10KSeconds != nil
    }

    var body: some View {
        if hasAnything {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(title: "Records")

                if let longest = records.longestRun {
                    recordRow("Longest run", RunFormat.distanceText(meters: longest.distanceMeters, metric: metric))
                }
                if let best5K = records.best5KSeconds {
                    recordRow("Estimated 5K", RunFormat.durationText(seconds: best5K))
                }
                if let best10K = records.best10KSeconds {
                    recordRow("Estimated 10K", RunFormat.durationText(seconds: best10K))
                }

                Text("5K and 10K times are estimated from each run's average pace.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appSurface(.quiet)
            .accessibilityIdentifier("run_history_records")
        }
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    recordLabel(label)
                    recordValue(value)
                        .padding(.leading, 32)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    recordLabel(label)
                    Spacer(minLength: AppSpacing.compact)
                    recordValue(value)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private func recordLabel(_ label: String) -> some View {
        Label(label, systemImage: "medal.fill")
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func recordValue(_ value: String) -> some View {
        Text(value)
            .appTextRole(.secondary)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - All-routes map

/// Every recent outdoor route on one map — the Strava-wall feel. Routes are decimated
/// (RouteSimplify, tested) and capped so thirty runs render as smoothly as three; the
/// latest run draws at full strength, history fades behind it.
struct RunMapView: View {
    let runs: [Run]
    @State private var scope: RunHistoryScope
    @State private var selectedID: String?
    @State private var segments: [[CLLocationCoordinate2D]] = []
    @State private var isLoading = false
    @State private var routeNotice: String?
    @State private var capturedOwner: String?
    @State private var invalidated = false
    @EnvironmentObject private var accountState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    init(runs: [Run], scope: RunHistoryScope = RunHistoryScope()) {
        self.runs = runs
        _scope = State(initialValue: scope)
        _selectedID = State(initialValue: scope.filtered(runs).first?.id)
        _capturedOwner = State(initialValue: DIContainer.shared.authService.currentUserID)
    }
    private var filtered: [Run] { scope.filtered(runs) }
    private var selected: Run? { filtered.first { $0.id == selectedID } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.group) {
                RunHistoryFilterControls(scope: $scope, sources: RunHistoryScope.sources(in: runs))
                if !segments.isEmpty {
                    Map(initialPosition: .automatic) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, coordinates in
                            MapPolyline(coordinates: coordinates).stroke(Color.brandPrimary, lineWidth: 4)
                        }
                        if let first = segments.first?.first { Marker("Start", systemImage: "flag", coordinate: first) }
                        if let last = segments.last?.last { Marker("Finish", systemImage: "flag.checkered", coordinate: last) }
                    }.id(selectedID).frame(height: 280).clipShape(RoundedRectangle(cornerRadius: AppRadius.surface))
                        .accessibilityLabel("Selected run route. Pauses and recovery gaps stay separate.")
                }
                if isLoading { ProgressView("Loading selected route…") }
                if let routeNotice { Text(routeNotice).appTextRole(.caption).foregroundStyle(.secondary) }
                if let selected, !isLoading, segments.isEmpty, !selected.isIndoor {
                    Button("Retry selected route") { Task { await loadSelectedRoute() } }
                }
                AppSectionHeader(title: "Choose a run", subtitle: "\(filtered.count) available in this selection. Only the selected route is loaded.")
                if filtered.isEmpty { Text("No runs match these filters.").appTextRole(.secondary) }
                ForEach(filtered) { run in
                    HStack(spacing: AppSpacing.row) {
                        Button {
                            selectedID = run.id
                        } label: {
                            HStack {
                                Image(systemName: run.id == selectedID ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                    Text("\(RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric)) · \(run.source.displayName)\(run.isIndoor ? " · Indoor" : "")")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.frame(minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("run_route_select_\(run.id)")
                        NavigationLink(destination: RunDetailView(run: run)) { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("Open run details")
                    }.appTextRole(.secondary).appSurface(.quiet)
                }
            }.padding(AppSpacing.screenHorizontal)
        }
        .background(AppPalette.canvas.ignoresSafeArea()).navigationTitle("Route map")
        .navigationBarTitleDisplayMode(.inline)
        .opacity(invalidated ? 0 : 1).allowsHitTesting(!invalidated).accessibilityHidden(invalidated)
        .onReceive(accountState.$isUserLoggedIn) { _ in
            guard capturedOwner != DIContainer.shared.authService.currentUserID else { return }
            invalidated = true; segments = []; dismiss()
        }
        .onChange(of: scope) { _, _ in
            if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id }
        }
        .task(id: selectedID) { await loadSelectedRoute() }
    }

    @MainActor private func loadSelectedRoute() async {
        segments = []; routeNotice = nil
        guard !invalidated, let run = selected, let owner = capturedOwner,
              owner == DIContainer.shared.authService.currentUserID else { isLoading = false; return }
        if run.isIndoor { isLoading = false; routeNotice = "Indoor entry: no outdoor route was recorded."; return }
        if run.distanceMeters == 0 { isLoading = false; routeNotice = "No distance was recorded. A stationary run may have no route to draw."; return }
        isLoading = true
        let fixes = await withCheckedContinuation { (continuation: CheckedContinuation<[[RunLocationFix]], Never>) in
            RunImportService().fetchRouteSegments(for: run, userID: owner) { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled, selectedID == run.id, owner == DIContainer.shared.authService.currentUserID else { return }
        let drawable = fixes.filter { $0.count > 1 }
        let perSegment = max(2, 6_000 / max(1, drawable.count))
        segments = drawable.map { RouteSimplify.decimate($0, maxPoints: perSegment).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
        isLoading = false
        routeNotice = segments.isEmpty
            ? "No route is available to this app. Health read access, an unfinished export or an expired private route copy can limit availability. Your run totals are unchanged."
            : "\(segments.count) recorded segment\(segments.count == 1 ? "" : "s"). Pauses and recovery gaps are never connected. This preview simplifies points; the private source stays unchanged."
    }
}

/// Opens the exact account-owned scheduled run through review and readiness. The
/// captured plan/day are revalidated again at the actual Start button, never inferred
/// from recommendation wording or whichever workout was last browsed.
struct ScheduledRunReviewView: View {
    let accountID: String
    let commitment: TrainingRunCommitment
    var onStarted: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var isValid = false
    @State private var message: String?
    @State private var showingRecorder = false
    @State private var startedRecordingID: String?

    var body: some View {
        Group {
            if isValid {
                RunWorkoutPreviewSheet(plan: commitment.plan, metric: useMetric, onStart: {
                    if validate(requireNoDraft: true) { showingRecorder = true }
                }, onEdit: nil)
            } else {
                NavigationStack {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        Text(message ?? "Checking your scheduled run…").appTextRole(.secondary)
                        Button("Review current schedule") { dismiss() }
                            .buttonStyle(AppActionButtonStyle(.primary))
                    }
                    .padding(AppSpacing.screenHorizontal)
                    .navigationTitle("Scheduled run")
                }
            }
        }
        .accessibilityIdentifier("scheduled_run_review")
        .onAppear { isValid = validate(requireNoDraft: true) }
        .fullScreenCover(isPresented: $showingRecorder, onDismiss: {
            if startedRecordingID != nil { dismiss() }
        }) {
            RunRecorderView(plan: commitment.plan, validateStart: { validate(requireNoDraft: false) }, onStarted: { recordingID in
                startedRecordingID = recordingID
                onStarted(recordingID)
            }, scheduledContext: RunScheduledContext(commitment: commitment))
        }
        .alert("Scheduled run changed", isPresented: Binding(get: { message != nil && isValid }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "Review the current schedule before starting.") }
    }

    private func validate(requireNoDraft: Bool) -> Bool {
        do {
            guard DIContainer.shared.authService.currentUserID == accountID,
                  let current = try TrainingRunCommitmentStore().entries(userID: accountID).first(where: { $0.id == commitment.id }),
                  current.day == commitment.day, current.plan == commitment.plan,
                  current.blockID == commitment.blockID, current.slotID == commitment.slotID,
                  current.revisionID == commitment.revisionID else {
                message = "This session was changed or removed. Open the current schedule to review it."
                return false
            }
            if requireNoDraft, try RunRecordingDraftStore().load(userID: accountID) != nil {
                message = "A recording is already saved. Resume or finish it from Running before opening another scheduled run."
                return false
            }
            return true
        } catch {
            message = "The scheduled run could not be checked. Your plan is kept; close this screen and try again."
            return false
        }
    }
}

private struct RunHeartRateZoneSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let age: Int
    let error: String?
    let onSave: (RunHeartRateZoneSettings) -> Bool
    @State private var method: RunHeartRateZoneSettings.Method
    @State private var maximum: Int
    @State private var thresholds: [Int]

    init(initial: RunHeartRateZoneSettings, age: Int, error: String?, onSave: @escaping (RunHeartRateZoneSettings) -> Bool) {
        self.age = age
        self.error = error
        self.onSave = onSave
        _method = State(initialValue: initial.method)
        _maximum = State(initialValue: initial.isValid ? Int(initial.maximumBPM.rounded()) : 190)
        let selectedMaximum = initial.isValid ? initial.maximumBPM : 190
        _thresholds = State(initialValue: (initial.thresholdsBPM ?? [0.6, 0.7, 0.8, 0.9].map { selectedMaximum * $0 }).map { Int($0.rounded()) })
    }

    var body: some View {
        AppEditorScaffold(title: "Heart-rate zones", subtitle: "Choose your reference for the five zones.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Picker("Maximum heart rate", selection: $method) {
                    Text("Age-estimated").tag(RunHeartRateZoneSettings.Method.ageEstimate)
                    Text("Enter my maximum").tag(RunHeartRateZoneSettings.Method.enteredMaximum)
                    Text("Custom boundaries").tag(RunHeartRateZoneSettings.Method.enteredThresholds)
                }.pickerStyle(.menu)
                if method == .enteredMaximum {
                    Stepper("Maximum: \(maximum) bpm", value: $maximum, in: 60...240)
                } else if method == .enteredThresholds {
                    ForEach(0..<4, id: \.self) { index in
                        Stepper("Zone \(index + 2) starts at \(thresholds[index]) bpm", value: $thresholds[index], in: 31...239)
                    }
                    if !settings.isValid {
                        Text("Each boundary must be higher than the previous one.").appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    }
                } else {
                    Text("Estimated maximum: \(Int(HeartRateZones.estimatedMaxHR(age: age))) bpm for age \(age), using 220 − age with a 140 bpm minimum. This is an estimate, not a measurement.")
                        .appTextRole(.secondary)
                }
                Text(method == .enteredThresholds
                     ? "Enter boundaries from your own chosen reference. Below the first boundary is Zone 1; each boundary belongs to the higher zone. MyFitPlate does not measure or validate your physiological thresholds."
                     : "Zones use 50%, 60%, 70%, 80% and 90% of the selected maximum. An entered maximum is your own reference; MyFitPlate does not measure or validate it. Changing this setting recalculates the display and retains the first review method.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if let error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }.appSurface(.emphasized)
        } actions: {
            Button("Apply zone settings") {
                if onSave(settings) { dismiss() }
            }.buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!settings.isValid)
                .accessibilityIdentifier("run_zone_settings_save")
        }
    }

    private var settings: RunHeartRateZoneSettings {
        method == .ageEstimate ? .estimated(age: age)
            : RunHeartRateZoneSettings(method: method, maximumBPM: Double(maximum),
                                       thresholdsBPM: method == .enteredThresholds ? thresholds.map(Double.init) : nil)
    }
}

private struct RunOutlineDraft: Codable, Equatable, Identifiable {
    var id: String
    var step: RunWorkoutStepDraft?
    var repetitions: Int
    var children: [RunOutlineDraft]

    init(step: RunWorkoutStepDraft) {
        id = step.id
        self.step = step
        repetitions = 1
        children = []
    }

    init(item: RunWorkoutOutlineItem, metric: Bool) {
        switch item {
        case .step(let value):
            let draft = RunWorkoutStepDraft(step: value, metric: metric)
            id = draft.id
            step = draft
            repetitions = 1
            children = []
        case .group(let group):
            id = group.id
            step = nil
            repetitions = group.repetitions
            children = group.children.map { RunOutlineDraft(item: $0, metric: metric) }
        }
    }

    static func repeatedPair() -> Self {
        var group = Self(step: RunWorkoutStepDraft(kind: .hard, title: "Work"))
        group.id = UUID().uuidString
        group.step = nil
        group.repetitions = 3
        group.children = [Self(step: RunWorkoutStepDraft(kind: .hard, title: "Work")),
                          Self(step: RunWorkoutStepDraft(kind: .recovery, title: "Recover"))]
        return group
    }

    func item(metric: Bool) -> RunWorkoutOutlineItem {
        if let step { return .step(step.step(metric: metric)) }
        return .group(RunWorkoutOutlineGroup(id: id, repetitions: repetitions, children: children.map { $0.item(metric: metric) }))
    }

    func duplicated() -> Self {
        var copy = self
        copy.id = UUID().uuidString
        if var step = copy.step { step.id = copy.id; step.originalStep = nil; copy.step = step }
        copy.children = copy.children.map { $0.duplicated() }
        return copy
    }
}

private struct RunOutlineSelection: Identifiable { let id: String }

/// Each nested editor changes the original durable draft binding. Dismissal keeps
/// its edits, and relaunch restores exactly that outline without flattening it.
private struct RunOutlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [RunOutlineDraft]
    let metric: Bool
    var depth = 0
    @State private var selection: RunOutlineSelection?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button { selection = RunOutlineSelection(id: item.id) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.step?.title ?? "Repeat group").font(.headline)
                                        Text(summary(item)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Menu {
                                    Button("Move earlier", systemImage: "arrow.up") { move(item.id, by: -1) }
                                        .disabled(items.first?.id == item.id)
                                    Button("Move later", systemImage: "arrow.down") { move(item.id, by: 1) }
                                        .disabled(items.last?.id == item.id)
                                    Button("Duplicate", systemImage: "plus.square.on.square") {
                                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                                            items.insert(item.duplicated(), at: index + 1)
                                        }
                                    }
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        items.removeAll { $0.id == item.id }
                                    }.disabled(items.count <= 1)
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            }
                            if item.step == nil {
                                Stepper("Repeat \(item.repetitions) times", value: $item.repetitions, in: 1...50)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Reorder with Edit or an item's Move actions. Open steps wait for Continue step during the run.")
                        .appTextRole(.caption)
                }
                Section {
                    Button("Add step", systemImage: "plus") {
                        items.append(RunOutlineDraft(step: RunWorkoutStepDraft(kind: .hard, title: "Work")))
                    }
                    Button("Add repeat group", systemImage: "repeat") { items.append(.repeatedPair()) }
                        .disabled(depth >= 3)
                        .accessibilityIdentifier("run_outline_add_group_\(depth)")
                }
            }
            .appFormStyle()
            .navigationTitle(depth == 0 ? "Workout outline" : "Inside repeat group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selection) { selected in
                if let index = items.firstIndex(where: { $0.id == selected.id }) {
                    if items[index].step != nil {
                        let original = items[index].step ?? RunWorkoutStepDraft(kind: .hard, title: "Work")
                        RunOutlineStepSheet(step: Binding(get: { items.first(where: { $0.id == selected.id })?.step ?? original },
                            set: { updated in
                                guard let current = items.firstIndex(where: { $0.id == selected.id }) else { return }
                                items[current].step = updated
                            }), metric: metric)
                    } else {
                        AnyView(RunOutlineEditorSheet(items: $items[index].children, metric: metric, depth: depth + 1))
                    }
                }
            }
        }
    }

    private func summary(_ item: RunOutlineDraft) -> String {
        if let step = item.step { return "\(step.kind.displayName) · \(step.step(metric: metric).goalText(metric: metric))" }
        return "\(item.children.count) items · \(item.repetitions) repeats"
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }
}

private struct RunOutlineStepSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var step: RunWorkoutStepDraft
    let metric: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Step") {
                    TextField("Step title", text: $step.title)
                    Picker("Type", selection: $step.kind) {
                        ForEach(RunWorkoutStep.Kind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Goal", selection: $step.goalMode) {
                        ForEach(RunWorkGoalMode.allCases) { Text($0.label).tag($0) }
                    }
                    if step.goalMode == .duration {
                        Stepper("Duration: \(RunFormat.durationText(seconds: Double(step.seconds)))", value: $step.seconds, in: 15...7200, step: 15)
                    } else if step.goalMode == .distance {
                        Stepper("Distance: \(RunFormat.distanceText(meters: Double(step.meters), metric: metric))", value: $step.meters, in: 50...10_000, step: 50)
                    } else {
                        Text("Advance this step when you are ready during the run.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Guidance") {
                    TextField("Effort cue", text: $step.cue)
                    Toggle("Use a pace range", isOn: $step.usePaceTarget)
                    if step.usePaceTarget {
                        Stepper("Fastest: \(pace(step.fastestPaceSeconds))", value: $step.fastestPaceSeconds, in: 180...1200, step: 5)
                        Stepper("Slowest: \(pace(step.slowestPaceSeconds))", value: $step.slowestPaceSeconds, in: 180...1200, step: 5)
                        if step.fastestPaceSeconds > step.slowestPaceSeconds {
                            Text("The slowest pace must be at least the fastest pace.").foregroundStyle(AppPalette.caution)
                        }
                    }
                }
            }
            .appFormStyle()
            .navigationTitle("Edit step").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func pace(_ seconds: Int) -> String {
        RunFormat.paceText(secondsPerKm: Double(seconds) / (metric ? 1 : RunFormat.metersPerMile / 1000), metric: metric) ?? "—"
    }
}

private struct RunMeasuredRecordsCard: View {
    let summary: RunMeasuredRecords.Summary
    let runs: [Run]
    let metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Measured split records", subtitle: "Best among \(summary.eligibleRuns) eligible measured runs in the available history")
            if summary.records.isEmpty {
                Text("No eligible measured splits yet. An uninterrupted MyFitPlate outdoor run with saved full splits can qualify.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            ForEach(summary.records) { record in
                if let run = runs.first(where: { $0.id == record.runID }) {
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.distanceMeters == RunFormat.metersPerMile ? "1 mile" : RunFormat.distanceText(meters: record.distanceMeters, metric: true))
                                    .appTextRole(.control)
                                Text("Splits \(record.firstSplit)–\(record.lastSplit) · \(run.startDate.formatted(date: .abbreviated, time: .omitted))")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(RunFormat.durationText(seconds: record.seconds)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Exact saved split boundaries only. Paused, recovered, discontinuous, imported and treadmill runs are excluded; no time is scaled from average pace. This is the best available full-split window, not a search of every route point.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("run_measured_records")
    }
}

private struct RunCorrectionDraft: Codable, Equatable {
    var metric: Bool
    var distance: String
    var minutes: String
    var seconds: String
    var reason = ""
    var operationID = UUID().uuidString
}

private struct RunReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: DailyLogService
    @EnvironmentObject private var accountState: AppState
    @State private var projectionInvalidated = false
    let run: Run
    private var metric: Bool { form.metric }
    let onChanged: (Run) -> Void
    let onHidden: () -> Void
    @State private var ownerID: String?
    @State private var form: RunCorrectionDraft
    @State private var originalForm: RunCorrectionDraft
    @State private var pendingReview: RunReviewStore.Review?
    @State private var error: String?
    @State private var didLoad = false
    @State private var isBlocked = false
    @State private var didFinish = false
    @State private var showingHide = false
    @State private var restoringForm = false
    @State private var isWorking = false
    @State private var hasSubmitted = false
    private var coordinator: RunDiaryCorrectionCoordinator { RunDiaryCorrectionCoordinator(service: service) }

    init(run: Run, metric: Bool, onChanged: @escaping (Run) -> Void, onHidden: @escaping () -> Void) {
        self.run = run
        self.onChanged = onChanged
        self.onHidden = onHidden
        _ownerID = State(initialValue: DIContainer.shared.authService.currentUserID)
        let seconds = run.movingSeconds.isFinite ? min(172_800, max(0, run.movingSeconds)) : 0
        let value = RunCorrectionDraft(metric: metric, distance: String(format: "%.3f", run.distanceMeters / (metric ? 1000 : RunFormat.metersPerMile)),
            minutes: String(Int(seconds) / 60), seconds: String(Int(seconds) % 60))
        _form = State(initialValue: value)
        _originalForm = State(initialValue: value)
    }

    private var scope: String { "run.correction.draft.\(RunReviewStore.identity(run))" }

    var body: some View {
        AppEditorScaffold(title: "Review run", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text(run.startDate.formatted(date: .complete, time: .shortened)).appTextRole(.control)
                Text("\(RunFormat.distanceText(meters: run.distanceMeters, metric: metric)) · \(RunFormat.durationText(seconds: run.movingSeconds)) active")
                if RunReviewStore.canCorrectManual(run) {
                    Text("Correct treadmill totals").appTextRole(.sectionTitle)
                    TextField(metric ? "Distance (km)" : "Distance (mi)", text: $form.distance)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).disabled(isWorking || hasSubmitted || isBlocked)
                    HStack {
                        TextField("Minutes", text: $form.minutes).keyboardType(.numberPad)
                        Text("min")
                        TextField("Seconds", text: $form.seconds).keyboardType(.numberPad)
                        Text("sec")
                    }.textFieldStyle(.roundedBorder).disabled(isWorking || hasSubmitted || isBlocked)
                    TextField("Reason for correction", text: $form.reason, axis: .vertical).textFieldStyle(.roundedBorder)
                        .disabled(isWorking || hasSubmitted || isBlocked)
                    Text("Review your treadmill totals and the linked diary activity together. Calories are re-estimated using the weight saved with this run. Original evidence stays in the receipt; Apple Health keeps its original record.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    if let pendingReview, case .correctManual(let meters, let seconds, _) = pendingReview.mutation {
                        LabeledContent("Reviewed totals", value: "\(RunFormat.distanceText(meters: meters, metric: metric)) · \(RunFormat.durationText(seconds: seconds))")
                            .appSurface(.interpreted)
                        if let link = pendingReview.diaryCorrection {
                            LabeledContent("Diary estimate", value: "\(Int(link.after.caloriesBurned.rounded())) kcal · \(link.after.durationMinutes ?? 0) min")
                            Text("Diary day: \(link.day.originalDate.formatted(date: .abbreviated, time: .omitted)). These totals are accepted only after its linked activity confirms the change.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Measured distance, timing, routes and sensor samples retain their original evidence. You can hide this run from Running history, records and gear summaries, then restore it from Run reviews. Diary calories, Apple Health and training completion remain unchanged.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Button("Hide from Running", role: .destructive) { showingHide = true }
                    .frame(minHeight: 44).disabled(isBlocked || isWorking || hasSubmitted)
                if hasSubmitted {
                    Text("This exact correction is kept for retry. Its fields stay locked until both the diary and run receipt confirm it.")
                        .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                }
                if isWorking { ProgressView("Checking linked activity…") }
                if let error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }
        } actions: {
            if RunReviewStore.canCorrectManual(run) {
                Button(pendingReview == nil ? "Review correction" : hasSubmitted ? "Retry exact correction" : "Apply reviewed correction") {
                    Task { if let pendingReview { await commit(pendingReview) } else { await prepareCorrection() } }
                }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(isBlocked || isWorking)
                .accessibilityIdentifier("run_correction_review")
            }
        }
        .confirmationDialog("Hide this run from Running?", isPresented: $showingHide, titleVisibility: .visible) {
            Button("Hide this run", role: .destructive) {
                guard let ownerID else { return }
                Task {
                    do { await commit(try RunReviewStore().review(run: run, mutation: .hide, userID: ownerID)) } catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the run from Running history, records and gear summaries. Diary activity calories, Apple Health and completed training-plan receipts stay intact. Undo is available in Running → Options → Run reviews.")
        }
        .opacity(projectionInvalidated ? 0 : 1)
        .allowsHitTesting(!projectionInvalidated)
        .accessibilityHidden(projectionInvalidated)
        .onReceive(accountState.$isUserLoggedIn) { _ in
            guard ownerID != DIContainer.shared.authService.currentUserID else { return }
            projectionInvalidated = true; showingHide = false; dismiss()
        }
        .onAppear(perform: restore)
        .onChange(of: form) { old, new in
            guard !hasSubmitted else { return }
            pendingReview = nil
            if restoringForm { restoringForm = false } else if old.distance != new.distance || old.minutes != new.minutes || old.seconds != new.seconds || old.reason != new.reason {
                form.operationID = UUID().uuidString
            }
            checkpoint()
        }
    }

    private func prepareCorrection() async {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { error = "Your account changed. Reopen this review."; return }
        let distance: Double
        if form.distance == originalForm.distance { distance = run.distanceMeters } else {
            guard let entered = Double(form.distance.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")), entered.isFinite else {
                error = "Enter a valid distance."; return
            }
            distance = entered * (metric ? 1000 : RunFormat.metersPerMile)
        }
        let duration: Double
        if form.minutes == originalForm.minutes, form.seconds == originalForm.seconds { duration = run.movingSeconds } else {
            guard let minutes = Int(form.minutes), let seconds = Int(form.seconds), (0...2880).contains(minutes), (0...59).contains(seconds) else {
                error = "Enter whole minutes and seconds from 0 to 59."; return
            }
            duration = Double(minutes * 60 + seconds)
        }
        isWorking = true
        defer { isWorking = false }
        do {
            pendingReview = try await coordinator.prepare(run: run, distanceMeters: distance, movingSeconds: duration,
                reason: form.reason.trimmed, userID: ownerID, operationID: form.operationID)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func commit(_ review: RunReviewStore.Review) async {
        guard let current = DIContainer.shared.authService.currentUserID else { error = "Sign back into the account that owns this run."; return }
        guard current == ownerID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await coordinator.commit(review)
            let projected = try RunReviewStore().projecting([run], userID: current).first
            didFinish = true
            try? EditorDraftStore().removeIfUnchanged(RunCorrectionDraft.self, userID: current, scope: scope, fingerprint: PlanFingerprint.make(form))
            if let projected { onChanged(projected) } else { onHidden() }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            do {
                if let operation = try coordinator.pending(run: run, userID: current) {
                    pendingReview = operation.review
                    hasSubmitted = true
                }
            } catch { isBlocked = true; self.error = "The pending correction could not be read. It has been preserved unchanged." }
        }
    }

    private func restore() {
        guard !didLoad, let ownerID else { return }
        didLoad = true
        do {
            if let draft = try EditorDraftStore().load(RunCorrectionDraft.self, userID: ownerID, scope: scope) {
                restoringForm = true
                originalForm.metric = draft.value.metric
                originalForm.distance = String(format: "%.3f", run.distanceMeters / (draft.value.metric ? 1000 : RunFormat.metersPerMile))
                form = draft.value
            }
            if let operation = try coordinator.pending(run: run, userID: ownerID) {
                pendingReview = operation.review
                hasSubmitted = true
            }
        } catch { isBlocked = true; self.error = "Your earlier correction draft or pending review could not be read. It has been kept unchanged." }
    }

    private func checkpoint() {
        guard didLoad, !didFinish, !isBlocked, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do { try EditorDraftStore().save(form, userID: ownerID, scope: scope) } catch { self.error = "This draft could not be kept for next time. Keep the review open and try again." }
    }
}

private struct RunImportedNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let run: Run
    let onChanged: (Run) -> Void
    @State private var note: String
    @State private var owner: String?
    @State private var review: RunReviewStore.Review?
    @State private var error: String?
    @State private var loaded = false
    @State private var blocked = false
    private var scope: String { "run.note.draft.\(RunReviewStore.identity(run))" }

    init(run: Run, onChanged: @escaping (Run) -> Void) {
        self.run = run; self.onChanged = onChanged
        _note = State(initialValue: run.reviewAnnotation?.note ?? "")
        _owner = State(initialValue: DIContainer.shared.authService.currentUserID)
    }
    var body: some View {
        AppEditorScaffold(title: "Personal run note", subtitle: "Add context to this imported run without changing its measurements.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened)).appTextRole(.control)
                TextField("How did this run feel?", text: $note, axis: .vertical)
                    .lineLimit(4...10).textFieldStyle(.roundedBorder).disabled(blocked)
                    .accessibilityIdentifier("run_import_note")
                Text("\(note.count)/1,000 characters · original source: \(run.source.displayName)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if review != nil { Text("Ready to save this exact note. Apple Health, diary calories and training completion remain unchanged.").appTextRole(.secondary) }
                if let error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }
        } actions: {
            Button(review == nil ? "Review note" : "Save reviewed note") {
                guard let owner, owner == DIContainer.shared.authService.currentUserID else { error = "Your account changed. Reopen this note."; return }
                do {
                    let store = RunReviewStore()
                    if let review {
                        _ = try store.commit(review, currentUserID: owner)
                        if let value = try store.projecting([run], userID: owner).first { onChanged(value) }
                        try? EditorDraftStore().removeIfUnchanged(String.self, userID: owner, scope: scope, fingerprint: PlanFingerprint.make(note))
                        dismiss()
                    } else { review = try store.review(run: run, mutation: .annotate(note: note.trimmed), userID: owner) }
                } catch { self.error = error.localizedDescription }
            }.buttonStyle(AppActionButtonStyle(.primary)).disabled(blocked || note.trimmed.isEmpty || note.count > 1000)
                .accessibilityIdentifier("run_import_note_save")
        }
        .onAppear {
            guard !loaded, let owner else { return }; loaded = true
            do { if let draft = try EditorDraftStore().load(String.self, userID: owner, scope: scope) { note = draft.value } } catch { blocked = true; self.error = "Your earlier note draft could not be read and has been preserved." }
        }
        .onChange(of: note) { _, _ in
            review = nil
            guard loaded, !blocked, let owner, owner == DIContainer.shared.authService.currentUserID else { return }
            do { try EditorDraftStore().save(note, userID: owner, scope: scope) } catch { self.error = "Your note draft could not be kept. Leave this screen open and try again." }
        }
    }
}

private struct RunPauseEditInterval: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var start: Date
    var end: Date
    let origin: RunPauseInterval.Origin
}
private struct RunPauseEditDraft: Codable, Equatable {
    var operationID = UUID().uuidString
    var intervals: [RunPauseEditInterval]
    var reason = ""
    var timeline: RunPauseTimeline {
        RunPauseTimeline(completeness: .complete, intervals: intervals.map { RunPauseInterval(startDate: $0.start, endDate: $0.end, origin: $0.origin) })
    }
}

private struct RunPauseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: DailyLogService
    let run: Run
    let metric: Bool
    let onChanged: (Run) -> Void
    @State private var original: Run
    @State private var draft: RunPauseEditDraft
    @State private var owner: String?
    @State private var pending: RunReviewStore.Review?
    @State private var error: String?
    @State private var loaded = false
    @State private var blocked = false
    @State private var working = false
    @State private var submitted = false
    private var scope: String { "run.pause.draft.\(RunReviewStore.identity(run))" }
    private var coordinator: RunDiaryCorrectionCoordinator { RunDiaryCorrectionCoordinator(service: service) }
    private var projection: RunPauseCorrectionRules.Review? { RunPauseCorrectionRules.review(original: original, timeline: draft.timeline) }

    init(run: Run, metric: Bool, onChanged: @escaping (Run) -> Void) {
        self.run = run; self.metric = metric; self.onChanged = onChanged
        _original = State(initialValue: run)
        _owner = State(initialValue: DIContainer.shared.authService.currentUserID)
        _draft = State(initialValue: RunPauseEditDraft(intervals: (run.pauseTimeline?.intervals ?? []).map {
            RunPauseEditInterval(start: $0.startDate, end: $0.endDate, origin: $0.origin)
        }))
    }
    var body: some View {
        AppEditorScaffold(title: "Review pause times", subtitle: "Adjust the active-time display while retaining the original recording.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                Text("\(run.startDate.formatted(date: .abbreviated, time: .standard)) – \(run.endDate.formatted(date: .omitted, time: .standard))")
                    .appTextRole(.control)
                Text("Original distance, measured splits, laps, interval results and sensor samples stay unchanged. Only active-time totals and the linked diary estimate change. Apple Health keeps its original record. Recovery gaps cannot be removed.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                ForEach($draft.intervals) { $interval in
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(interval.origin == .recoveryGap ? "Recovery gap · preserved" : "Explicit pause").appTextRole(.control)
                        DatePicker("From", selection: $interval.start, in: run.startDate...run.endDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Until", selection: $interval.end, in: run.startDate...run.endDate, displayedComponents: [.date, .hourAndMinute])
                        Text("\(interval.start.formatted(date: .omitted, time: .standard)) – \(interval.end.formatted(date: .omitted, time: .standard))")
                            .appTextRole(.caption).monospacedDigit()
                        if interval.origin == .explicitPause {
                            Stepper("Adjust start by one second", onIncrement: { interval.start = min(run.endDate, interval.start.addingTimeInterval(1)) },
                                onDecrement: { interval.start = max(run.startDate, interval.start.addingTimeInterval(-1)) })
                            Stepper("Adjust end by one second", onIncrement: { interval.end = min(run.endDate, interval.end.addingTimeInterval(1)) },
                                onDecrement: { interval.end = max(run.startDate, interval.end.addingTimeInterval(-1)) })
                            Button("Remove this pause", role: .destructive) { draft.intervals.removeAll { $0.id == interval.id } }
                        }
                    }.disabled(interval.origin == .recoveryGap || working || submitted || blocked).appSurface(.quiet)
                }
                Button("Add a pause", systemImage: "plus") {
                    draft.intervals.append(RunPauseEditInterval(start: run.startDate,
                        end: min(run.endDate, run.startDate.addingTimeInterval(30)), origin: .explicitPause))
                }.disabled(working || submitted || blocked || draft.intervals.count >= RunPauseTimeline.maximumIntervals)
                TextField("Reason for correction", text: $draft.reason, axis: .vertical).textFieldStyle(.roundedBorder)
                    .disabled(working || submitted || blocked)
                if let projection {
                    LabeledContent("Reviewed active time", value: RunFormat.durationText(seconds: projection.activeSeconds))
                    LabeledContent("Paused or interrupted", value: RunFormat.durationText(seconds: projection.excludedSeconds))
                } else { Text("Each pause must fall within the recording and end after it starts. At least one second of active time must remain.").appTextRole(.caption).foregroundStyle(AppPalette.caution) }
                if let link = pending?.diaryCorrection {
                    LabeledContent("Reviewed diary estimate", value: "\(Int(link.after.caloriesBurned.rounded())) kcal")
                    Text("Diary day: \(link.day.originalDate.formatted(date: .abbreviated, time: .omitted))").appTextRole(.caption)
                }
                if submitted { Text("This exact review is saved for retry. Editing stays locked until its linked diary and run receipt confirm.").appTextRole(.caption) }
                if working { ProgressView("Checking linked activity…") }
                if let error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            }
        } actions: {
            Button(pending == nil ? "Review pause correction" : submitted ? "Retry exact correction" : "Apply reviewed correction") {
                Task { await save() }
            }.buttonStyle(AppActionButtonStyle(.primary))
                .disabled(working || blocked || projection == nil || draft.reason.trimmed.isEmpty || draft.reason.count > 500)
                .accessibilityIdentifier("run_pause_correction_save")
        }
        .onAppear(perform: restore)
        .onChange(of: draft) { old, new in
            guard loaded, !submitted, !blocked else { return }
            pending = nil
            if old.operationID == new.operationID { draft.operationID = UUID().uuidString }
            checkpoint()
        }
    }
    private func restore() {
        guard !loaded, let owner, owner == DIContainer.shared.authService.currentUserID else { return }
        loaded = true
        do {
            original = try RunReviewStore().originalEvidence(for: run, userID: owner)
            if let saved = try EditorDraftStore().load(RunPauseEditDraft.self, userID: owner, scope: scope) { draft = saved.value }
            if let operation = try coordinator.pending(run: run, userID: owner) {
                guard case .correctPauses = operation.review.mutation else { blocked = true; error = "Complete the pending totals correction from Run reviews first."; return }
                pending = operation.review; submitted = true
            }
        } catch { blocked = true; self.error = "The original evidence or earlier review could not be read and has been preserved." }
    }
    private func checkpoint() {
        guard let owner, owner == DIContainer.shared.authService.currentUserID else { return }
        do { try EditorDraftStore().save(draft, userID: owner, scope: scope) } catch { self.error = "Your pause draft could not be kept. Leave this screen open and try again." }
    }
    private func save() async {
        guard let owner, owner == DIContainer.shared.authService.currentUserID, !working else { return }
        working = true; defer { working = false }
        do {
            if let pending {
                submitted = true
                _ = try await coordinator.commit(pending)
                if let updated = try RunReviewStore().projecting([run], userID: owner).first { onChanged(updated) }
                try? EditorDraftStore().removeIfUnchanged(RunPauseEditDraft.self, userID: owner, scope: scope, fingerprint: PlanFingerprint.make(draft))
                dismiss()
            } else {
                checkpoint()
                pending = try await coordinator.preparePauses(run: run, timeline: draft.timeline, reason: draft.reason.trimmed,
                    userID: owner, operationID: draft.operationID)
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct RunReviewHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: DailyLogService
    @EnvironmentObject private var accountState: AppState
    @State private var projectionOwner: String
    @State private var projectionInvalidated = false
    let ownerID: String
    let onChanged: () -> Void
    @State private var receipts: [RunReviewStore.Receipt] = []
    @State private var isWorking = false
    @State private var error: String?

    init(ownerID: String, onChanged: @escaping () -> Void) {
        self.ownerID = ownerID; self.onChanged = onChanged
        _projectionOwner = State(initialValue: ownerID)
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                if receipts.isEmpty { Text("No run reviews yet.").foregroundStyle(.secondary) }
                ForEach(receipts) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.review.original.startDate.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(description(receipt)).font(.subheadline).foregroundStyle(.secondary)
                        if receipt.review.mutation != .restoreOriginal && receipt.review.mutation != .excludeImportPermanently {
                            Button("Undo this change") { Task { await undo(receipt) } }.disabled(isWorking)
                                .accessibilityIdentifier("run_review_undo_\(receipt.id)")
                        }
                    }.padding(.vertical, 4)
                }
            }
            .appFormStyle()
            .navigationTitle("Run reviews").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear(perform: load)
            .opacity(projectionInvalidated ? 0 : 1)
            .allowsHitTesting(!projectionInvalidated)
            .accessibilityHidden(projectionInvalidated)
            .onReceive(accountState.$isUserLoggedIn) { _ in
                guard projectionOwner != DIContainer.shared.authService.currentUserID else { return }
                projectionInvalidated = true; receipts = []; dismiss()
            }
        }
    }

    private func description(_ receipt: RunReviewStore.Receipt) -> String {
        switch receipt.review.mutation {
        case .hide: return "Hidden from Running history, records and gear summaries. Diary and Health records are unchanged."
        case .restoreOriginal: return "Original MyFitPlate summary restored."
        case .correctManual(_, _, let reason): return "Treadmill totals corrected · \(reason)"
        case .correctPauses(_, let reason): return "Pause display corrected · \(reason). Original GPS, measured steps and Health evidence retained."
        case .annotate(let note): return "Personal note · \(note)"
        case .excludeImportPermanently: return "Permanently excluded from MyFitPlate and future imports. No Undo. Apple Health, diary and training receipts are unchanged."
        }
    }

    private func load() {
        guard ownerID == projectionOwner, ownerID == DIContainer.shared.authService.currentUserID else { receipts = []; error = "Your account changed. Reopen Run reviews."; return }
        do { receipts = try RunReviewStore().latestReceipts(userID: ownerID); error = nil } catch { self.error = "Run reviews could not be read. Original records stay unchanged." }
    }

    private func undo(_ receipt: RunReviewStore.Receipt) async {
        guard let current = DIContainer.shared.authService.currentUserID else { return }
        guard current == projectionOwner, current == ownerID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do { _ = try await RunDiaryCorrectionCoordinator(service: service).undo(receipt, userID: current); load(); onChanged() } catch { self.error = error.localizedDescription }
    }
}

private struct RunHistoryFilterControls: View {
    @Binding var scope: RunHistoryScope
    let sources: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            TextField("Search runs", text: $scope.query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(AppSpacing.row).background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                .accessibilityLabel("Search runs by workout, source or date")
                .accessibilityIdentifier("run_history_search")
            DisclosureGroup("Filter history") {
                Picker("Period", selection: $scope.period) {
                    Text("All available").tag(RunHistoryScope.Period.all)
                    Text("Selected week").tag(RunHistoryScope.Period.week)
                    Text("This month").tag(RunHistoryScope.Period.month)
                    Text("This year").tag(RunHistoryScope.Period.year)
                }.accessibilityIdentifier("run_history_period")
                if scope.period == .week {
                    DatePicker("Week containing", selection: $scope.selectedWeek, in: ...Date(), displayedComponents: .date)
                }
                Picker("Setting", selection: $scope.environment) {
                    Text("All").tag(RunHistoryScope.Environment.all)
                    Text("Outdoor").tag(RunHistoryScope.Environment.outdoor)
                    Text("Indoor").tag(RunHistoryScope.Environment.indoor)
                }.pickerStyle(.segmented)
                Picker("Source", selection: $scope.source) {
                    Text("All sources").tag(String?.none)
                    ForEach(sources, id: \.self) { source in Text(source).tag(String?.some(source)) }
                }
                Button("Clear filters") { scope = RunHistoryScope(selectedWeek: scope.selectedWeek) }
            }
        }.appTextRole(.secondary).appSurface(.quiet)
    }
}

struct RunManualLapsCard: View {
    let laps: [RunManualLap]
    let metric: Bool
    var body: some View {
        DisclosureGroup("Manual laps · \(laps.count)") {
            LazyVStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Deliberate boundaries in accepted distance and active time. Pauses and time away stay excluded; GPS gaps are not reconstructed. Automatic splits and workout steps stay separate.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                ForEach(Array(laps.enumerated()), id: \.element.id) { offset, lap in
                    let previous = offset == 0 ? nil : laps[offset - 1]
                    LabeledContent("Lap \(lap.index)") {
                        Text("\(RunFormat.distanceText(meters: lap.distanceMeters - (previous?.distanceMeters ?? 0), metric: metric)) · \(RunFormat.durationText(seconds: lap.activeElapsedSeconds - (previous?.activeElapsedSeconds ?? 0)))")
                            .monospacedDigit()
                    }.appTextRole(.secondary)
                }
            }.padding(.top, AppSpacing.compact)
        }.appSurface(.quiet).accessibilityIdentifier("run_manual_laps")
    }
}

#if DEBUG
/// Presentation-only entry points for the disposable simulator design gallery.
/// Opening a route never starts a recording or requests Health/location access.
struct TrainingDesignGallery: View {
    let screen: String
    @StateObject private var plans = RunWorkoutPlanStore()
    @State private var outline: [RunOutlineDraft] = [.repeatedPair()]
    @State private var step = RunWorkoutStepDraft(kind: .hard, title: "Steady effort")

    private var samplePlan: RunWorkoutPlan { RunWorkoutPlan.builtinTemplates(metric: true)[0] }

    @ViewBuilder var body: some View {
        switch screen {
        case "run-picker":
            RunWorkoutPickerSheet(metric: true, onStart: { _ in }, onLogTreadmill: {})
        case "run-goal":
            RunGoalSetupSheet(metric: true, onReview: { _ in })
        case "run-preview":
            RunWorkoutPreviewSheet(plan: samplePlan, metric: true, onStart: {}, onEdit: {})
        case "run-repeats":
            RunWorkoutTemplateEditorSheet(metric: true, plans: plans, onUseOnce: { _ in })
        case "run-steps":
            RunWorkoutStepTemplateEditorSheet(metric: true, initialPlan: samplePlan, plans: plans, onUseOnce: { _ in })
        case "run-outline":
            RunOutlineEditorSheet(items: $outline, metric: true)
        case "run-step":
            RunOutlineStepSheet(step: $step, metric: true)
        case "run-zones":
            RunHeartRateZoneSettingsSheet(initial: .estimated(age: 30), age: 30, error: nil, onSave: { _ in false })
        case "run-treadmill":
            TreadmillRunEntrySheet(metric: true, onSaved: {})
        case "run-sync":
            RunCloudSyncView()
        case "run-block":
            RunTrainingBlockView()
        case "strength-equipment":
            StrengthEquipmentSetupView(exerciseName: "Dumbbell bench press", equipment: nil, onSave: { _ in })
        case "strength-gyms":
            StrengthGymLibraryView()
        case "strength-prescription":
            WorkoutPrescriptionEditorView(exerciseType: .strength, set: ExerciseSet(), onSave: { _ in })
        case "strength-report":
            NavigationStack { WorkoutEvidenceReportView() }
        default:
            ContentUnavailableView("Unknown training preview", systemImage: "rectangle.stack")
        }
    }
}
#endif
