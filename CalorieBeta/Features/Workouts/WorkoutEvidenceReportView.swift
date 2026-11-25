import MyFitPlateCore
import SwiftUI
import Charts

struct WorkoutEvidenceReportView: View {
    var initialProgramID: String?
    private let initialDates: ClosedRange<Date>?
    @EnvironmentObject private var workoutService: WorkoutService
    @State private var logs: [WorkoutSessionLog] = []
    @State private var programID = ""
    @State private var blockID = ""
    @State private var setup = ""
    @State private var metric = WorkoutTrendMetric.load
    @State private var range = 90
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var type = ""
    @State private var unit = StrengthEquipment.Unit.lb
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var updatedAt: Date?
    @State private var ownerID: String?
    @State private var evaluationDate = Date()
    @State private var showsAllSessions = false
    init(initialProgramID: String? = nil, initialDates: ClosedRange<Date>? = nil) {
        self.initialProgramID = initialProgramID
        self.initialDates = initialDates
        if let initialDates {
            _range = State(initialValue: -2)
            _customStart = State(initialValue: initialDates.lowerBound)
            _customEnd = State(initialValue: initialDates.upperBound)
        }
    }

    private var scope: WorkoutReportScope {
        let start: Date?
        let end: Date?
        switch range {
        case -2:
            start = initialDates?.lowerBound
            end = initialDates?.upperBound
        case -1:
            start = Calendar.current.startOfDay(for: customStart)
            end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customEnd))?.addingTimeInterval(-0.001)
        default:
            start = range == 0 ? nil : Calendar.current.date(byAdding: .day, value: 1 - range, to: Calendar.current.startOfDay(for: evaluationDate))
            end = evaluationDate
        }
        return WorkoutReportScope(startDate: start, endDate: end, programID: programID.isEmpty ? nil : programID,
            blockID: blockID.isEmpty ? nil : blockID, exerciseType: ExerciseType(rawValue: type), setupKey: setup.isEmpty ? nil : setup)
    }
    private var outcomeDocument: WorkoutOutcomeReportDocument? { try? WorkoutOutcomeReportDocument(logs: logs, scope: scope, now: evaluationDate) }
    private var snapshot: WorkoutEvidenceSnapshot? { outcomeDocument?.performance }
    private var sessionOutcomes: [WorkoutSessionOutcomeEvidence] { outcomeDocument?.sessionOutcomes ?? [] }
    private var selectedLogs: [WorkoutSessionLog] { Array(WorkoutEvidenceReportRules.filtered(logs, scope: scope, now: evaluationDate).reversed()) }
    private var points: [WorkoutReportPoint] { WorkoutEvidenceReportRules.points(logs: logs, scope: scope, setup: setup, metric: metric, now: evaluationDate) }
    private var availableSetups: [WorkoutReportSetup] {
        var allSetupsScope = scope; allSetupsScope.setupKey = nil
        return (try? WorkoutEvidenceReportRules.snapshot(logs: logs, scope: allSetupsScope, now: evaluationDate).setups) ?? []
    }
    private var metricTitle: String {
        let assisted = logs.flatMap(\.completedExercises).contains { WorkoutEvidenceReportRules.setupKey($0.exercise) == setup && $0.exercise.loadEquipment?.loadingMeaning == .assistance }
        return metric == .load && assisted ? "Least assistance recorded" : metric.title
    }
    private var blocks: [String] {
        Array(Set(logs.filter { programID.isEmpty || $0.programContext?.programID == programID }
            .compactMap { $0.programContext?.blockSession?.blockID })).sorted()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                filters
                if isLoading { ProgressView("Refreshing complete history") }
                if let errorMessage {
                    Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    Button("Retry complete history") { Task { await load() } }.buttonStyle(AppActionButtonStyle(.secondary))
                }
                if updatedAt != nil, errorMessage == nil, let comparison = StrengthPeriodComparison.make(logs: logs, scope: scope, now: evaluationDate) {
                    comparisonCard(comparison)
                    if let snapshot {
                        Text(snapshot.durationSummary).appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("report_session_duration")
                    }
                }
                if updatedAt != nil, let snapshot {
                    let sessions = selectedLogs
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Supporting sessions · \(sessions.count)").appTextRole(.sectionTitle)
                        ForEach(Array(sessions.prefix(showsAllSessions ? sessions.count : 3).enumerated()), id: \.offset) { _, log in
                            let outcome = WorkoutOutcomeEvidenceRules.session(log)
                            NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.displayName(routines: workoutService.userRoutines, programs: workoutService.userPrograms)).appTextRole(.control)
                                    Text("\(log.date.formatted(date: .abbreviated, time: .shortened)) · \(WorkoutSetMath.workingSetCount(log)) working sets")
                                        .appTextRole(.secondary).foregroundStyle(.secondary)
                                    Text(log.programPosition(in: workoutService.userPrograms))
                                        .appTextRole(.secondary).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            Text(outcome.title).appTextRole(.control)
                            if !outcome.substitutionExerciseIDs.isEmpty {
                                Text("\(outcome.substitutionExerciseIDs.count) recorded substitutions · replacement work remains separate")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("Set coverage details") {
                                Text(outcome.explanation).appTextRole(.secondary)
                                Text("Session ID · \(outcome.sessionID)").appTextRole(.caption).textSelection(.enabled)
                                if let slot = outcome.slotIndex, !outcome.isUnassigned {
                                    Text("Program position \(slot + 1) · frozen block \(outcome.blockID ?? "not recorded")")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(AppListButtonStyle()).frame(minHeight: 44)
                            Divider()
                        }
                        if sessions.count > 3 {
                            Button(showsAllSessions ? "Show latest three" : "Show all \(sessions.count) sessions") {
                                showsAllSessions.toggle()
                            }
                            .buttonStyle(.plain).foregroundStyle(AppPalette.brandText).frame(minHeight: 44)
                        }
                    }.appSurface(.quiet)
                    summary(snapshot)
                    if !availableSetups.isEmpty || !setup.isEmpty { trends(snapshot) }
                    muscleSets(snapshot)
                    if let document = outcomeDocument, let data = try? JSONEncoder().encode(document), let text = String(data: data, encoding: .utf8) {
                        ShareLink("Share reproducible report snapshot", item: text).frame(minHeight: 44)
                    }
                    Text("Snapshot \(snapshot.fingerprint.prefix(12)) · source refreshed \(updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "not yet"). A refresh incorporates saved corrections. Context is observational; this report does not infer causes from nutrition or recovery.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }.padding(AppSpacing.screenHorizontal)
        }
        .background(AppPalette.canvas).navigationTitle("Training report").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workout_evidence_report")
        .task { if ownerID == nil { ownerID = DIContainer.shared.authService.currentUserID; programID = initialProgramID ?? "" }; await load() }
        .refreshable { await load() }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Picker("Period", selection: $range) {
                if let initialDates {
                    Text((initialDates.lowerBound..<initialDates.upperBound).formatted(.interval.year().month(.abbreviated).day())).tag(-2)
                }
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("All").tag(0)
                Text("Custom").tag(-1)
            }
                .accessibilityIdentifier("report_period")
            if range == -1 { DatePicker("From", selection: $customStart, displayedComponents: .date); DatePicker("Through", selection: $customEnd, in: customStart..., displayedComponents: .date) }
            DisclosureGroup {
            Picker("Program", selection: $programID) {
                Text("All programs & unassigned").tag("")
                ForEach(workoutService.userPrograms) { Text($0.name).tag($0.id ?? "") }
            }.onChange(of: programID) { _, _ in blockID = ""; setup = "" }
            Picker("Block", selection: $blockID) { Text("All blocks").tag(""); ForEach(blocks, id: \.self) { Text("Block \($0.prefix(8))").tag($0) } }
            Picker("Session content", selection: $type) { Text("All types").tag(""); ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
            } label: {
                Text("Program & session filters").accessibilityIdentifier("report_context_filters")
            }
            .tint(AppPalette.text)
        }.appSurface(.quiet)
    }
    private func comparisonCard(_ comparison: StrengthPeriodComparison) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Strength comparison").appTextRole(.sectionTitle)
            Grid(alignment: .leading, horizontalSpacing: AppSpacing.group, verticalSpacing: AppSpacing.row) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Text("Working sets")
                    Text("Training days")
                }.appTextRole(.caption).foregroundStyle(.secondary)
                periodRow("Selected", comparison.current)
                Divider()
                periodRow("Previous", comparison.previous)
            }
            if comparison.programMixChanged || comparison.exerciseMixChanged {
                Text(comparison.programMixChanged ? "The linked programs differ between these periods." : "The exercise or equipment mix differs between these periods.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if comparison.includesPartialDay {
                Text("Through " + evaluationDate.formatted(date: .omitted, time: .shortened) + " on the last day of each period.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if comparison.current.workingSets == 0 || comparison.previous.workingSets == 0 {
                Text("Only saved strength sessions with working sets count here.").appTextRole(.caption).foregroundStyle(.secondary)
            }
        }.appSurface(.quiet).accessibilityIdentifier("strength_period_comparison")
    }

    private func periodRow(_ label: String, _ period: StrengthPeriodComparison.Period) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).appTextRole(.control)
                Text((period.dates.lowerBound..<period.dates.upperBound).formatted(.interval.year().month(.abbreviated).day()))
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(period.workingSets.formatted()).appTextRole(.sectionTitle).monospacedDigit()
            Text(period.trainingDays.formatted()).appTextRole(.sectionTitle).monospacedDigit()
        }
    }

    private func summary(_ snapshot: WorkoutEvidenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(snapshot.headline).appTextRole(.sectionTitle)
            if StrengthPeriodComparison.make(logs: logs, scope: scope, now: evaluationDate) == nil || errorMessage != nil {
                Text(snapshot.durationSummary).appTextRole(.secondary).accessibilityIdentifier("report_session_duration")
            }
            Text("Adherence & original set coverage").appTextRole(.control)
            Text("\(sessionOutcomes.filter { !$0.isUnassigned && $0.completion == .completed }.count) completed · \(sessionOutcomes.filter { !$0.isUnassigned && $0.completion == .partial }.count) partial · \(sessionOutcomes.filter { !$0.isUnassigned && $0.completion == .unknown }.count) coverage unknown · \(snapshot.unassignedSessions) unassigned receipts")
                .appTextRole(.secondary).accessibilityIdentifier("report_outcome_summary")
            Text("\(sessionOutcomes.filter { !$0.substitutionExerciseIDs.isEmpty }.count) receipts with substitutions · effort on \(snapshot.effortSets)/\(snapshot.workingSets) working sets. Compare performance separately below.")
                .appTextRole(.secondary)
            if let breaks = outcomeDocument?.recordedBreaks, !breaks.isEmpty {
                DisclosureGroup("\(breaks.count) recorded gaps longer than 21 days") {
                    ForEach(breaks) { gap in
                        Text("\(gap.from.formatted(date: .abbreviated, time: .omitted)) → \(gap.through.formatted(date: .abbreviated, time: .omitted)) · \(gap.days) days between saved receipts")
                            .appTextRole(.secondary)
                    }
                    Text("These are gaps between adjacent saved receipts in the chosen scope, not proof of inactivity or a cause of performance changes.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }.buttonStyle(AppListButtonStyle()).frame(minHeight: 44).accessibilityIdentifier("report_recorded_breaks")
            }
            if let program = workoutService.userPrograms.first(where: { $0.id == programID }), range == 0, blockID.isEmpty || blockID == program.trainingBlock?.id {
                let review = WorkoutBlockReview.make(program: program, logs: selectedLogs)
                Text("Plan evidence: \(review.completedSlots) completed-set positions, \(review.partialSlots) partial, \(review.unknownSlots) unknown, \(review.skippedSlots) declared skips, \(review.movedSlots) explicitly moved. \(review.totalSlots) planned positions; passed alone does not establish completion.")
                    .appTextRole(.secondary).accessibilityIdentifier("report_block_adherence")
            }
            DisclosureGroup("How sets and loads are counted") {
                Text("\(snapshot.completedLinkedSlots) distinct linked positions. Coverage uses each receipt's frozen original set identities and recorded roles; it does not mean rep, load or effort targets were achieved. Legacy or missing evidence stays Unknown. Coverage is session-wide, including when a movement filter is selected.")
                .appTextRole(.caption).foregroundStyle(.secondary)

                Text("External load volume stays separated by movement, implement and convention. Assistance and bodyweight are reported as sets/repetitions, not invented lifted mass. Duration is session-wide even when a movement filter is selected.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.tint(AppPalette.text).appTextRole(.secondary)
        }.appSurface(.emphasized)
    }
    private func trends(_ snapshot: WorkoutEvidenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Comparable movement trend").appTextRole(.sectionTitle)
            Picker("Movement & setup", selection: $setup) {
                Text("Choose a movement / setup").tag("")
                ForEach(availableSetups) { Text("\($0.name) · \($0.context)").tag($0.id) }
            }.accessibilityIdentifier("report_exercise_setup")
            Picker("Metric", selection: $metric) { ForEach(WorkoutTrendMetric.allCases) { Text($0 == metric ? metricTitle : $0.title).tag($0) } }
                .accessibilityIdentifier("report_metric")
            Picker("Load units", selection: $unit) { Text("lb").tag(StrengthEquipment.Unit.lb); Text("kg").tag(StrengthEquipment.Unit.kg) }
            if points.isEmpty { Text("No eligible points for this scope and metric. Select a setup; estimated strength needs 1–12 reps and a loaded convention. Effort requires recorded ratings.").appTextRole(.secondary).foregroundStyle(.secondary) } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metricTitle, displayValue(point.value)), series: .value("Comparable context", point.seriesID))
                        .foregroundStyle(AppPalette.brandText)
                    PointMark(x: .value("Date", point.date), y: .value(metricTitle, displayValue(point.value))).foregroundStyle(AppPalette.brandText)
                }.frame(height: 210).accessibilityLabel("\(metricTitle), \(points.count) eligible sessions. Exact values follow.")
                Text("Lines break for changed prescriptions or a training gap over 21 days. Changing setups creates a separate comparison. Less assistance means a harder effort.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Accessible data & receipt table") {
                    ForEach(points) { point in
                        if let log = selectedLogs.first(where: { ($0.id ?? "\($0.routineID)|\($0.date.timeIntervalSinceReferenceDate)") == point.sessionID }) {
                            NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                                Text("\(point.date.formatted(date: .abbreviated, time: .omitted)) · \(displayValue(point.value).formatted(.number.precision(.fractionLength(0...2)))) · \(point.context)")
                            }.frame(minHeight: 44)
                        }
                    }
                }
            }
        }.appSurface(.quiet)
    }
    private func muscleSets(_ snapshot: WorkoutEvidenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Working sets by catalog category").appTextRole(.sectionTitle)
            ForEach(snapshot.setsByMuscle.keys.sorted(), id: \.self) { key in Text("\(key): \(snapshot.setsByMuscle[key] ?? 0)") }
            Text("Uses the library's primary category; it does not count a compound lift as exact work for every involved muscle.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }.appSurface(.quiet)
    }
    private func displayValue(_ value: Double) -> Double { metric == .load || metric == .volume || metric == .estimatedStrength ? unit.displayWeight(value) : value }
    private func load() async {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let values = try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: ownerID)
            guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID else { return }
            let refreshedAt = Date(); logs = values; updatedAt = refreshedAt; evaluationDate = refreshedAt; errorMessage = nil
        } catch { errorMessage = "Complete history could not refresh. Previously loaded evidence is kept; retry before treating it as current." }
    }
}
