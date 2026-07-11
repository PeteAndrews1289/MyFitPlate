import SwiftUI
import MapKit
import Charts
import MyFitPlateCore

// Running history + detail. Runs come straight from HealthKit (any watch whose app
// syncs to Apple Health), filtered and de-duplicated by RunImportRules — HealthKit is
// the single source of truth, so there's nothing to sync and nothing to drift.

@MainActor
final class RunHistoryViewModel: ObservableObject {
    @Published var runs: [Run] = []
    @Published var isLoading = true

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
        HealthKitManager.shared.requestAuthorization { [weak self] _, _ in
            guard let self else { return }
            let since = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
            self.importer.fetchRuns(since: since) { runs in
                self.runs = RunningShoeStore().applyTags(to: runs)
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

    var records: RunStats.PersonalRecords {
        RunStats.personalRecords(from: runs)
    }
}

struct RunHistoryView: View {
    @StateObject private var viewModel: RunHistoryViewModel
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var showingRecorder = false
    @State private var showingRunStartSheet = false
    @State private var activeRunPlan: RunWorkoutPlan?
    @State private var showingGearManager = false
    @State private var showingTreadmillEntry = false

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
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    showingRunStartSheet = true
                } label: {
                    Label("Start run", systemImage: "figure.run")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                if !viewModel.runs.isEmpty {
                    weekHero
                    RunRecordsCard(records: viewModel.records, metric: useMetric)
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.runs) { run in
                            NavigationLink(destination: RunDetailView(run: run)) {
                                RunRow(run: run, metric: useMetric)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Running")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingGearManager = true
                    } label: {
                        Image(systemName: "shoeprints.fill")
                            .foregroundColor(.brandPrimary)
                    }
                    .accessibilityLabel("Shoe Gear Manager")

                    NavigationLink(destination: RunMapView(runs: viewModel.runs)) {
                        Image(systemName: "map")
                            .foregroundColor(.brandPrimary)
                    }
                    .accessibilityLabel("Route map")
                }
            }
        }
        .onAppear { viewModel.load() }
        .fullScreenCover(isPresented: $showingRecorder, onDismiss: { viewModel.load() }) {
            RunRecorderView(plan: activeRunPlan)
        }
        .sheet(isPresented: $showingRunStartSheet) {
            RunWorkoutPickerSheet(
                metric: useMetric,
                onStart: { plan in
                    activeRunPlan = plan
                    showingRunStartSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showingRecorder = true
                    }
                },
                onLogTreadmill: {
                    showingRunStartSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showingTreadmillEntry = true
                    }
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

    // DESIGN.md rule 1: the question is "how is my running week going?"
    private var weekHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RunFormat.distanceText(meters: viewModel.thisWeekMeters, metric: useMetric))
                    .appFont(size: 28, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .contentTransition(.numericText())
                Text(viewModel.thisWeekCount == 1 ? "1 run" : "\(viewModel.thisWeekCount) runs")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asCard()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🏃")
                .font(.system(size: 42))
                .accessibilityHidden(true)
            Text("No runs yet")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Record one right here with Start run, or finish a run on any watch that syncs to Apple Health — Apple Watch, Garmin, Polar, Coros — and it shows up automatically.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct RunWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planStore = RunWorkoutPlanStore()
    @State private var editorRoute: RunWorkoutEditorRoute?
    let metric: Bool
    let onStart: (RunWorkoutPlan?) -> Void
    let onLogTreadmill: () -> Void

    private var templates: [RunWorkoutPlan] {
        RunWorkoutPlan.builtinTemplates(metric: metric)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        onStart(nil)
                    } label: {
                        startCard(
                            title: "Open run",
                            subtitle: "GPS, splits, pace, route",
                            icon: "figure.run",
                            detail: nil
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onLogTreadmill()
                    } label: {
                        startCard(
                            title: "Log treadmill",
                            subtitle: "Indoor distance and time",
                            icon: "figure.run.treadmill",
                            detail: nil
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        editorRoute = .repeatTemplate
                    } label: {
                        startCard(
                            title: "Create repeats",
                            subtitle: "Build a saved repeat workout",
                            icon: "plus.circle.fill",
                            detail: nil
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        editorRoute = .stepTemplate
                    } label: {
                        startCard(
                            title: "Create step-by-step",
                            subtitle: "Build any saved run workout",
                            icon: "list.bullet.rectangle",
                            detail: nil
                        )
                    }
                    .buttonStyle(.plain)

                    if !planStore.customPlans.isEmpty {
                        Text("Saved")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .textCase(.uppercase)
                            .padding(.top, 6)

                        ForEach(planStore.customPlans) { plan in
                            Button {
                                onStart(plan)
                            } label: {
                                startCard(
                                    title: plan.name,
                                    subtitle: plan.subtitle,
                                    icon: "bookmark.fill",
                                    detail: detailText(for: plan)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editorRoute = .edit(plan)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    planStore.deletePlan(id: plan.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Text("Templates")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)
                        .padding(.top, 6)

                    ForEach(templates) { plan in
                        Button {
                            onStart(plan)
                        } label: {
                            startCard(
                                title: plan.name,
                                subtitle: plan.subtitle,
                                icon: icon(for: plan),
                                detail: detailText(for: plan)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Start run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $editorRoute) { route in
                switch route {
                case .repeatTemplate:
                    RunWorkoutTemplateEditorSheet(metric: metric) { plan in
                        planStore.addPlan(plan)
                    }
                case .stepTemplate:
                    RunWorkoutStepTemplateEditorSheet(metric: metric, initialPlan: nil) { plan in
                        planStore.addPlan(plan)
                    }
                case .edit(let plan):
                    RunWorkoutStepTemplateEditorSheet(metric: metric, initialPlan: plan) { plan in
                        planStore.updatePlan(plan)
                    }
                }
            }
        }
    }

    private func startCard(title: String, subtitle: String, icon: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 40, height: 40)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                if let detail {
                    Text(detail)
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .asCard()
    }

    private func detailText(for plan: RunWorkoutPlan) -> String {
        var parts: [String] = ["\(plan.steps.count) steps"]
        if plan.estimatedDurationSeconds > 0 {
            parts.append(RunFormat.durationText(seconds: plan.estimatedDurationSeconds))
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

private struct TreadmillRunEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalSettings: GoalSettings
    let metric: Bool
    let onSaved: () -> Void

    @State private var distanceValue: Double
    @State private var durationMinutes = 30
    @State private var endedAt = Date()
    @State private var isSaving = false

    init(metric: Bool, onSaved: @escaping () -> Void) {
        self.metric = metric
        self.onSaved = onSaved
        _distanceValue = State(initialValue: metric ? 5.0 : 3.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Treadmill") {
                    Stepper(
                        "Distance: \(distanceText)",
                        value: $distanceValue,
                        in: metric ? 0.1...80 : 0.1...50,
                        step: 0.1
                    )
                    Stepper(
                        "Duration: \(RunFormat.durationText(seconds: Double(durationMinutes * 60)))",
                        value: $durationMinutes,
                        in: 1...360,
                        step: 1
                    )
                    DatePicker("Ended", selection: $endedAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    HStack {
                        Text("Average pace")
                        Spacer()
                        Text(averagePaceText)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Estimated calories")
                        Spacer()
                        Text("\(Int(estimatedCalories.rounded())) cal")
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Treadmill run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving" : "Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || distanceMeters < 100 || durationMinutes < 1)
                }
            }
        }
    }

    private var distanceMeters: Double {
        metric ? distanceValue * 1000 : distanceValue * RunFormat.metersPerMile
    }

    private var distanceText: String {
        metric ? String(format: "%.1f km", distanceValue) : String(format: "%.1f mi", distanceValue)
    }

    private var averagePaceText: String {
        let secondsPerKm = Double(durationMinutes * 60) / (distanceMeters / 1000)
        return RunFormat.paceText(secondsPerKm: secondsPerKm, metric: metric) ?? "—"
    }

    private var estimatedCalories: Double {
        RunEnergy.estimateKcal(distanceMeters: distanceMeters, weightLbs: goalSettings.weight)
    }

    private func save() {
        let movingSeconds = Double(durationMinutes * 60)
        let startDate = endedAt.addingTimeInterval(-movingSeconds)
        guard let run = ManualRunEntryRules.buildIndoorRun(
            startDate: startDate,
            distanceMeters: distanceMeters,
            movingSeconds: movingSeconds,
            metric: metric,
            activeCalories: estimatedCalories
        ) else {
            ToastManager.shared.showToast(message: "Enter at least 0.1 km and 1 minute.")
            return
        }

        ActivationFunnel.recordTrainingCompletion(.treadmillRun)
        isSaving = true
        RunRecorderStore().save(run: run, locations: [], weightLbs: goalSettings.weight) { savedID in
            if let savedID {
                let shoeStore = RunningShoeStore()
                shoeStore.tagRun(runID: savedID, withShoeID: shoeStore.defaultShoe()?.id)
            } else {
                ToastManager.shared.showToast(message: "Saved locally, but Health sync failed.")
            }
            HapticManager.instance.notification(.success)
            ToastManager.shared.showToast(message: "Treadmill run saved.")
            onSaved()
            dismiss()
        }
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

private enum RunWorkGoalMode: String, CaseIterable, Identifiable {
    case duration
    case distance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duration: return "Time"
        case .distance: return "Distance"
        }
    }
}

private struct RunWorkoutTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: Bool
    let onSave: (RunWorkoutPlan) -> Void

    @State private var name = "Custom intervals"
    @State private var repetitions = 6
    @State private var warmupMinutes = 10
    @State private var workMode: RunWorkGoalMode = .duration
    @State private var workSeconds = 60
    @State private var workMeters = 400
    @State private var recoverySeconds = 90
    @State private var cooldownMinutes = 5
    @State private var cue = "Controlled effort"
    @State private var usePaceTarget = false
    @State private var fastestPaceSeconds = 300
    @State private var slowestPaceSeconds = 330

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                    Stepper("Repeats: \(repetitions)", value: $repetitions, in: 1...20)
                    Picker("Work goal", selection: $workMode) {
                        ForEach(RunWorkGoalMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Timing") {
                    Stepper("Warm up: \(warmupMinutes) min", value: $warmupMinutes, in: 0...30, step: 1)
                    if workMode == .duration {
                        Stepper("Work: \(workSeconds) sec", value: $workSeconds, in: 15...600, step: 15)
                    } else {
                        Stepper("Work: \(RunFormat.distanceText(meters: Double(workMeters), metric: metric))", value: $workMeters, in: 100...3000, step: 50)
                    }
                    Stepper("Recovery: \(recoverySeconds) sec", value: $recoverySeconds, in: 0...600, step: 15)
                    Stepper("Cool down: \(cooldownMinutes) min", value: $cooldownMinutes, in: 0...30, step: 1)
                }

                Section("Target") {
                    TextField("Cue", text: $cue)
                    Toggle("Pace range", isOn: $usePaceTarget)
                    if usePaceTarget {
                        Stepper("Fastest: \(paceText(secondsPerUnit: fastestPaceSeconds))", value: $fastestPaceSeconds, in: 180...1200, step: 5)
                        Stepper("Slowest: \(paceText(secondsPerUnit: slowestPaceSeconds))", value: $slowestPaceSeconds, in: 180...1200, step: 5)
                    }
                }
            }
            .navigationTitle("Custom run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(makePlan())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func makePlan() -> RunWorkoutPlan {
        let goal: RunWorkoutStep.Goal = workMode == .duration
            ? .duration(seconds: Double(workSeconds))
            : .distance(meters: Double(workMeters))
        return RunWorkoutPlan.repeatTemplate(
            name: name,
            warmupSeconds: Double(warmupMinutes * 60),
            repetitions: repetitions,
            workGoal: goal,
            recoverySeconds: Double(recoverySeconds),
            cooldownSeconds: Double(cooldownMinutes * 60),
            workTarget: workTarget
        )
    }

    private var workTarget: RunWorkoutTarget {
        guard usePaceTarget else { return RunWorkoutTarget(cue: cue) }
        return RunWorkoutTarget.paceRange(
            cue: cue,
            fastestSecondsPerUnit: Double(fastestPaceSeconds),
            slowestSecondsPerUnit: Double(slowestPaceSeconds),
            metric: metric
        )
    }

    private func paceText(secondsPerUnit: Int) -> String {
        let secondsPerKm = metric ? Double(secondsPerUnit) : Double(secondsPerUnit) / (RunFormat.metersPerMile / 1000)
        return RunFormat.paceText(secondsPerKm: secondsPerKm, metric: metric) ?? RunFormat.durationText(seconds: Double(secondsPerUnit))
    }
}

private struct RunWorkoutStepTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let metric: Bool
    let onSave: (RunWorkoutPlan) -> Void

    private let planID: String?
    @State private var name: String
    @State private var steps: [RunWorkoutStepDraft]

    init(metric: Bool, initialPlan: RunWorkoutPlan?, onSave: @escaping (RunWorkoutPlan) -> Void) {
        self.metric = metric
        self.onSave = onSave
        self.planID = initialPlan?.id
        _name = State(initialValue: initialPlan?.name ?? "Custom workout")
        _steps = State(initialValue: initialPlan?.steps.map { RunWorkoutStepDraft(step: $0, metric: metric) } ?? Self.defaultSteps())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                }

                Section("Steps") {
                    ForEach($steps) { $step in
                        stepEditor(step: $step)
                    }

                    Button {
                        steps.append(RunWorkoutStepDraft(kind: .hard, title: "Work"))
                    } label: {
                        Label("Add step", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(planID == nil ? "Step workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(makePlan())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(steps.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func stepEditor(step: Binding<RunWorkoutStepDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Type", selection: step.kind) {
                    ForEach(RunWorkoutStep.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Button(role: .destructive) {
                    removeStep(id: step.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(steps.count <= 1)
                .accessibilityLabel("Delete step")
            }

            TextField("Title", text: step.title)

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
            } else {
                Stepper(
                    "Distance: \(RunFormat.distanceText(meters: Double(step.wrappedValue.meters), metric: metric))",
                    value: step.meters,
                    in: 50...10_000,
                    step: 50
                )
            }

            TextField("Cue", text: step.cue)

            Toggle("Pace range", isOn: step.usePaceTarget)
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
        .padding(.vertical, 4)
    }

    private func makePlan() -> RunWorkoutPlan {
        RunWorkoutPlan(
            id: planID ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom workout" : name,
            subtitle: subtitle,
            steps: steps.map { $0.step(metric: metric) }
        )
    }

    private var subtitle: String {
        let workSteps = steps.filter { $0.kind == .hard }.count
        if workSteps > 0 {
            return "\(workSteps) work steps · \(steps.count) total"
        }
        return "\(steps.count) steps"
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

private struct RunWorkoutStepDraft: Identifiable, Equatable {
    let id: String
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal: RunWorkoutStep.Goal = goalMode == .duration
            ? .duration(seconds: Double(seconds))
            : .distance(meters: Double(meters))
        let target = usePaceTarget
            ? RunWorkoutTarget.paceRange(
                cue: cue,
                fastestSecondsPerUnit: Double(fastestPaceSeconds),
                slowestSecondsPerUnit: Double(slowestPaceSeconds),
                metric: metric
            )
            : RunWorkoutTarget(cue: cue)

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
        parts.append(RunFormat.durationText(seconds: run.movingSeconds))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(run.isIndoor ? "🏃‍♂️" : "🏃")
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(run.source.displayName)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.secondarySystemFill), in: Capsule())
        }
        .asCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

@MainActor
final class RunDetailViewModel: ObservableObject {
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var splits: [RunSplit] = []
    @Published var averageHeartRate: Double?
    @Published var isLoadingRoute = true
    @Published var ghostPaceComparison: RunStats.GhostPaceComparison?
    /// Seconds in each HR zone [Z1…Z5], or nil when the run carried no heart-rate series.
    @Published var heartRateZoneSeconds: [Double]?
    @Published var workoutResult: RunWorkoutResult?

    private let importer = RunImportService()
    private let workoutResultStore = RunWorkoutResultStore()

    /// Pull the run's HR series and reduce it to time-in-zone. Kept separate from `load`
    /// because it needs the user's max HR, which the view derives from their age.
    func loadHeartRateZones(start: Date, end: Date, maxHR: Double) {
        importer.fetchHeartRateSeries(start: start, end: end) { [weak self] series in
            guard let self else { return }
            let seconds = HeartRateZones.timeInZones(samples: series, maxHR: maxHR)
            self.heartRateZoneSeconds = seconds.reduce(0, +) > 0 ? seconds : nil
        }
    }

    func load(run: Run, metric: Bool) {
        splits = run.splits
        averageHeartRate = run.averageHeartRate
        workoutResult = workoutResultStore.result(forRunID: run.id)

        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        importer.fetchRuns(since: since) { [weak self] history in
            self?.ghostPaceComparison = RunStats.ghostPaceComparison(for: run, against: history)
        }

        importer.fetchRoute(forRunID: run.id) { [weak self] fixes in
            guard let self else { return }
            self.routeCoordinates = fixes.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            // Imports carry no splits — replay the GPS trace through the same engine the
            // live recorder uses, so a Garmin run gets real per-km splits anyway.
            if self.splits.isEmpty, fixes.count > 1 {
                let replay = RunSession(metric: metric)
                replay.start(at: fixes[0].timestamp)
                fixes.forEach { replay.ingest($0) }
                if let replayed = replay.finish(at: fixes[fixes.count - 1].timestamp) {
                    self.splits = replayed.splits
                }
            }
            self.isLoadingRoute = false
        }

        if run.averageHeartRate == nil {
            importer.fetchAverageHeartRate(start: run.startDate, end: run.endDate) { [weak self] bpm in
                self?.averageHeartRate = bpm
            }
        }
    }
}

enum MapDisplayMode: String, CaseIterable {
    case standard = "Standard Map"
    case heatmap = "Pace Heatmap"
}

struct RunDetailView: View {
    let run: Run
    @StateObject private var viewModel = RunDetailViewModel()
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var mapDisplayMode: MapDisplayMode = .standard
    @State private var showingStoryPoster = false
    @State private var showingRecoveryFoodSearch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !viewModel.routeCoordinates.isEmpty {
                    routeMap
                } else if run.isIndoor {
                    Text("Indoor run")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(UIColor.secondarySystemFill), in: Capsule())
                }

                statsGrid

                if let zones = viewModel.heartRateZoneSeconds {
                    heartRateZonesCard(zones)
                }

                if let workoutResult = viewModel.workoutResult {
                    RunWorkoutResultCard(result: workoutResult, metric: useMetric)
                }

                glycogenImpactCard

                if !viewModel.splits.isEmpty {
                    splitsCard
                }

                if let comparison = viewModel.ghostPaceComparison {
                    ghostPaceCard(comparison)
                }

                shoeTagCard
                
                Text("Recorded with \(run.source.displayName)")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.instance.feedback(.light)
                    showingStoryPoster = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.brandPrimary)
                }
                .accessibilityLabel("Share Run Story")
            }
        }
        .sheet(isPresented: $showingStoryPoster) {
            RunStoryPosterView(run: run, routeCoordinates: viewModel.routeCoordinates, useMetric: useMetric)
        }
        .sheet(isPresented: $showingRecoveryFoodSearch) {
            FoodSearchView(
                dailyLog: $dailyLogService.currentDailyLog,
                onFoodItemLogged: {
                    showingRecoveryFoodSearch = false
                },
                searchContext: "run_recovery"
            )
        }
        .onAppear {
            viewModel.load(run: run, metric: useMetric)
            let age = dailyLogService.goalSettings?.age ?? 30
            viewModel.loadHeartRateZones(start: run.startDate, end: run.endDate, maxHR: HeartRateZones.estimatedMaxHR(age: age))
        }
    }

    private var shoeTagCard: some View {
        let store = RunningShoeStore()
        let currentShoe = store.shoeID(forRunID: run.id).flatMap { store.shoe(for: $0) } ?? store.defaultShoe()
        return HStack {
            Image(systemName: "shoeprints.fill")
                .foregroundColor(.accentProtein)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Gear Tagged")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(currentShoe.map { "\($0.brand) · \($0.name)" } ?? "Select Shoe")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            Menu {
                ForEach(store.shoes.filter { !$0.isRetired }) { shoe in
                    Button {
                        HapticManager.instance.feedback(.light)
                        store.tagRun(runID: run.id, withShoeID: shoe.id)
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
                Text("Change")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.12), in: Capsule())
            }
        }
        .asCard()
    }

    private func ghostPaceCard(_ comparison: RunStats.GhostPaceComparison) -> some View {
        HStack(spacing: 14) {
            Image(systemName: comparison.isPR ? "trophy.fill" : "ghost.fill")
                .foregroundColor(comparison.isPR ? .yellow : .brandPrimary)
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(
                    (comparison.isPR ? Color.yellow : Color.brandPrimary).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comparison.isPR ? "🏆 New Route PR!" : "Ghost Pace Loop")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    if !comparison.isPR {
                        Text("vs \(comparison.matchingRunsCount) similar runs")
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }

                let diffText = RunFormat.paceDiffText(secondsPerKmDiff: comparison.paceDifferenceVsAverage, metric: useMetric)
                Text("\(diffText) vs average on this loop")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(comparison.paceDifferenceVsAverage < 0 ? .green : .textPrimary)
            }

            Spacer()

            if let prPace = RunFormat.paceText(secondsPerKm: comparison.prPaceSecondsPerKm, metric: useMetric) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Loop Best")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(prPace)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .monospacedDigit()
                }
            }
        }
        .asCard()
    }

    private var routeMap: some View {
        VStack(spacing: 8) {
            Picker("Map Mode", selection: $mapDisplayMode) {
                ForEach(MapDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Map(interactionModes: []) {
                if mapDisplayMode == .heatmap {
                    MapPolyline(coordinates: viewModel.routeCoordinates)
                        .stroke(Gradient(colors: [.yellow, .green, .brandPrimary, .cyan]), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else {
                    MapPolyline(coordinates: viewModel.routeCoordinates)
                        .stroke(Color.brandPrimary, lineWidth: 4)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Route map of this run")
        }
    }

    /// Training zone of the run's *average* HR (not time-in-zone — that needs a per-sample
    /// HR series we don't capture yet). Max HR is age-predicted from the user's profile.
    private var hrZoneText: String? {
        guard let bpm = viewModel.averageHeartRate else { return nil }
        let age = dailyLogService.goalSettings?.age ?? 30
        let maxHR = HeartRateZones.estimatedMaxHR(age: age)
        guard let zone = HeartRateZones.zone(forHeartRate: bpm, maxHR: maxHR) else { return nil }
        return "Z\(zone.number) · \(zone.name)"
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            RunStatTile(label: "Distance", value: RunFormat.distanceText(meters: run.distanceMeters, metric: useMetric))
            RunStatTile(label: "Time", value: RunFormat.durationText(seconds: run.movingSeconds))
            if let pace = RunFormat.paceText(secondsPerKm: run.averagePaceSecondsPerKm, metric: useMetric) {
                RunStatTile(label: "Avg pace", value: pace)
            }
            if let bpm = viewModel.averageHeartRate {
                RunStatTile(label: "Avg heart rate", value: "\(Int(bpm.rounded())) bpm")
                if let zone = hrZoneText {
                    RunStatTile(label: "HR zone (avg)", value: zone)
                }
            }
            if let calories = run.activeCalories {
                RunStatTile(label: "Calories", value: "\(Int(calories.rounded()).formatted()) cal")
            }
        }
    }

    /// Time-in-zone distribution. Uses the conventional HR heat gradient (cool→hot) rather
    /// than the brand palette because the color IS the information — same reason the pace
    /// heatmap does. Only shown when the run carried a real HR series.
    private func heartRateZonesCard(_ seconds: [Double]) -> some View {
        let total = max(seconds.reduce(0, +), 1)
        let colors: [Color] = [.blue, .green, .yellow, .orange, .red]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Heart-rate zones")
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.textPrimary)

            ForEach(Array(HeartRateZones.zones.enumerated()), id: \.offset) { index, zone in
                let secs = index < seconds.count ? seconds[index] : 0
                HStack(spacing: 10) {
                    Text("Z\(zone.number)")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(colors[index])
                        .frame(width: 24, alignment: .leading)
                    Text(zone.name)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 76, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(colors[index].opacity(0.14))
                            Capsule().fill(colors[index])
                                .frame(width: max(0, geo.size.width * CGFloat(secs / total)))
                        }
                    }
                    .frame(height: 8)
                    Text(secs > 0 ? RunFormat.durationText(seconds: secs) : "–")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(secs > 0 ? .textPrimary : Color(UIColor.tertiaryLabel))
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var glycogenImpactCard: some View {
        let carbsBurned = Int((run.activeCalories ?? (run.distanceMeters * 0.063)) * 0.65 / 4.0)
        let sweatMl = Int(run.distanceMeters * 0.08)
        let recovery = RunRecoveryRules.calculateTarget(for: run) ?? RunRecoveryTarget(targetCarbGrams: carbsBurned, targetProteinGrams: 25, rehydrateMilliLiters: sweatMl, runDistanceMeters: run.distanceMeters, activeCalories: run.activeCalories ?? 0, runID: run.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.batteryblock.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 18))
                Text("Glycogen & Fuel Impact")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carbs Depleted")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text("~\(carbsBurned)g")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.yellow)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. Sweat Loss")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text("~\(sweatMl) ml")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.blue)
                }
            }

            Text("Target: Eat \(recovery.targetCarbGrams)g Carbs + \(recovery.targetProteinGrams)g Protein within 45m for glycogen supercompensation.")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))

            Button {
                showingRecoveryFoodSearch = true
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Log Recovery Meal Now")
                }
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentProtein, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .asCard()
    }

    private var splitsCard: some View {
        let bestSplit = RunStats.fastestSplit(splits: viewModel.splits)
        let maxPace = viewModel.splits.compactMap { $0.paceSecondsPerKm }.max() ?? 300
        let minPace = viewModel.splits.compactMap { $0.paceSecondsPerKm }.min() ?? 240

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Splits")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                if RunStats.isNegativeSplit(splits: viewModel.splits),
                   let delta = RunStats.negativeSplitDeltaSecondsPerKm(splits: viewModel.splits) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("Negative Split! (-\(Int(delta.rounded()))s/km)")
                    }
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            ForEach(viewModel.splits, id: \.index) { split in
                let isBest = split.index == bestSplit?.index
                let barRatio = maxPace > 0 && split.paceSecondsPerKm != nil ? min(1.0, max(0.15, 1.0 - ((split.paceSecondsPerKm! - minPace) / (max(1, maxPace - minPace) * 1.5)))) : 0.5

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(split.index)")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(isBest ? .yellow : Color(UIColor.secondaryLabel))
                            .frame(width: 24, alignment: .leading)
                        Text(split.distanceMeters + 1 < (useMetric ? 1000 : RunFormat.metersPerMile)
                             ? RunFormat.distanceText(meters: split.distanceMeters, metric: useMetric)
                             : (useMetric ? "1 km" : "1 mi"))
                            .appFont(size: 13)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        if isBest {
                            Text("🏅 Fastest")
                                .appFont(size: 10, weight: .bold)
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                        Text(RunFormat.paceText(secondsPerKm: split.paceSecondsPerKm, metric: useMetric) ?? RunFormat.durationText(seconds: split.seconds))
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(isBest ? .yellow : .textPrimary)
                            .monospacedDigit()
                    }

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isBest ? Color.yellow : Color.brandPrimary.opacity(0.6))
                            .frame(width: geo.size.width * barRatio, height: 4)
                    }
                    .frame(height: 4)
                }
                .padding(.vertical, 2)
            }
        }
        .asCard()
    }
}

private struct RunStatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .appFont(size: 11, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asCard()
    }
}

// MARK: - Records

struct RunRecordsCard: View {
    let records: RunStats.PersonalRecords
    let metric: Bool

    private var hasAnything: Bool {
        records.longestRun != nil || records.best5KSeconds != nil || records.best10KSeconds != nil
    }

    var body: some View {
        if hasAnything {
            VStack(alignment: .leading, spacing: 8) {
                Text("Records")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)

                if let longest = records.longestRun {
                    recordRow("Longest run", RunFormat.distanceText(meters: longest.distanceMeters, metric: metric))
                }
                if let best5K = records.best5KSeconds {
                    recordRow("Best 5K", RunFormat.durationText(seconds: best5K))
                }
                if let best10K = records.best10KSeconds {
                    recordRow("Best 10K", RunFormat.durationText(seconds: best10K))
                }

                Text("5K and 10K times are estimated from each run's average pace.")
                    .appFont(size: 10)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .asCard()
        }
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("🏅")
                .font(.system(size: 14))
                .accessibilityHidden(true)
            Text(label)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Spacer()
            Text(value)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
    }
}

// MARK: - All-routes map

/// Every recent outdoor route on one map — the Strava-wall feel. Routes are decimated
/// (RouteSimplify, tested) and capped so thirty runs render as smoothly as three; the
/// latest run draws at full strength, history fades behind it.
struct RunMapView: View {
    let runs: [Run]

    private struct LoadedRoute {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let isLatest: Bool
    }

    @State private var routes: [LoadedRoute] = []
    @State private var isLoading = true
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    private static let maxRoutes = 30

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(routes, id: \.id) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(
                        route.isLatest ? Color.brandPrimary : Color.brandPrimary.opacity(0.35),
                        lineWidth: route.isLatest ? 4 : 3
                    )
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if isLoading {
                    Label("Drawing your routes", systemImage: "map")
                        .appFont(size: 12, weight: .semibold)
                } else if routes.isEmpty {
                    Text("No routes yet — outdoor runs draw themselves here.")
                        .appFont(size: 12, weight: .semibold)
                } else {
                    Text(routes.count == 1 ? "Your latest route" : "Your last \(routes.count) routes")
                        .appFont(size: 12, weight: .semibold)
                }
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
        .navigationTitle("Route map")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRoutes() }
    }

    @MainActor
    private func loadRoutes() async {
        guard routes.isEmpty else { return }
        let importer = RunImportService()
        let candidates = runs.filter { !$0.isIndoor }.prefix(Self.maxRoutes)

        for (index, run) in candidates.enumerated() {
            let fixes = await withCheckedContinuation { (continuation: CheckedContinuation<[RunLocationFix], Never>) in
                importer.fetchRoute(forRunID: run.id) { continuation.resume(returning: $0) }
            }
            guard fixes.count > 1 else { continue }
            let coordinates = RouteSimplify.decimate(fixes, maxPoints: 200).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            routes.append(LoadedRoute(id: run.id, coordinates: coordinates, isLatest: index == 0))
        }
        isLoading = false
    }
}

// MARK: - Reports card

/// Weekly mileage over the last 8 weeks, shown in Reports only when there's any running
/// at all — non-runners never see an empty chart.
struct RunMileageCard: View {
    @State private var weeks: [RunStats.WeekMileage] = []
    @State private var loaded = false
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    private var totalMeters: Double { weeks.reduce(0) { $0 + $1.meters } }

    var body: some View {
        Group {
            if loaded && totalMeters > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Running")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("Last 8 weeks · \(RunFormat.distanceText(meters: totalMeters, metric: useMetric))")
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Chart(weeks, id: \.weekStart) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Distance", useMetric ? week.meters / 1000 : week.meters / RunFormat.metersPerMile)
                        )
                        .foregroundStyle(Color.brandPrimary)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                                .font(.system(size: 9))
                        }
                    }
                    .frame(height: 110)
                    .accessibilityLabel("Weekly running distance, last 8 weeks")
                }
                .asCard()
            }
        }
        .onAppear {
            guard !loaded else { return }
            let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
            RunImportService().fetchRuns(since: since) { runs in
                weeks = RunStats.weeklyMileage(runs: runs, weeks: 8)
                loaded = true
            }
        }
    }
}
