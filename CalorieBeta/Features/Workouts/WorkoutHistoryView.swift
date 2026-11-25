import MyFitPlateCore

import Foundation
import Combine
import SwiftUI

struct WorkoutHistoryView: View {
    @EnvironmentObject private var workoutService: WorkoutService
    @StateObject private var history: WorkoutHistoryLoader
    @State private var searchText = ""
    @State private var selectedRange: WorkoutHistoryRange = .all
    @State private var selectedExercise: String?
    @State private var selectedProgram = ""
    @State private var selectedBlock = ""
    @State private var selectedSetup = ""
    @State private var selectedType = ""
    @State private var showingContextFilters = false
    init(fixtureLogs: [WorkoutSessionLog]? = nil) {
        _history = StateObject(wrappedValue: WorkoutHistoryLoader(fixtureLogs: fixtureLogs))
    }

    private var logs: [WorkoutSessionLog] { history.logs }
    private var isLoading: Bool { history.isLoading }
    private var isLoadingMore: Bool { history.isLoadingMore }
    private var loadError: String? { history.loadError }
    private var hasCompleteCoverage: Bool { history.hasCompleteCoverage }

    private var rangeFilteredLogs: [WorkoutSessionLog] {
        logs.filter { selectedRange.contains($0.date) }
    }

    private var filteredLogs: [WorkoutSessionLog] {
        rangeFilteredLogs.filter { log in
            matchesSelectedExercise(log) && matchesSearch(log)
                && WorkoutReportScope(programID: selectedProgram.isEmpty ? nil : selectedProgram, blockID: selectedBlock.isEmpty ? nil : selectedBlock, exerciseType: ExerciseType(rawValue: selectedType), setupKey: selectedSetup.isEmpty ? nil : selectedSetup).contains(log, now: .distantFuture)
        }
    }

    private var exerciseStats: [WorkoutExerciseHistoryStat] {
        WorkoutHistoryInsights.exerciseStats(for: rangeFilteredLogs)
    }

    private var highlights: WorkoutHistoryHighlights {
        WorkoutHistoryInsights.highlights(for: filteredLogs, allLogs: logs)
    }

    private var hasActiveFilters: Bool {
        selectedRange != .all || selectedExercise != nil || !searchText.trimmedForHistory.isEmpty || !selectedProgram.isEmpty || !selectedBlock.isEmpty || !selectedSetup.isEmpty || !selectedType.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.group) {
                WorkoutSyncNotice(service: workoutService)
                if let loadError {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(loadError).appTextRole(.body)
                        Button("Try again") { Task { await loadHistory(force: true) } }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                    }
                    .appSurface(.quiet)
                }
                if isLoading && logs.isEmpty {
                    WorkoutHistoryLoadingState()
                        .padding(.top, 60)
                } else if logs.isEmpty && loadError == nil {
                    WorkoutHistoryEmptyState()
                        .padding(.top, 50)
                } else if !logs.isEmpty {
                    WorkoutHistoryFilterCard(
                        searchText: $searchText,
                        selectedRange: $selectedRange
                    )

                    DisclosureGroup(isExpanded: $showingContextFilters) {
                        Picker("Program", selection: $selectedProgram) {
                            Text("All programs").tag("")
                            ForEach(workoutService.userPrograms) { Text($0.name).tag($0.id ?? "") }
                        }.onChange(of: selectedProgram) { _, _ in selectedBlock = "" }
                        Picker("Block", selection: $selectedBlock) {
                            Text("All blocks").tag("")
                            ForEach(Array(Set(logs.filter { selectedProgram.isEmpty || $0.programContext?.programID == selectedProgram }.compactMap { $0.programContext?.blockSession?.blockID })).sorted(), id: \.self) { Text("Block \($0.prefix(8))").tag($0) }
                        }
                        Picker("Setup", selection: $selectedSetup) {
                            Text("All setups").tag("")
                            ForEach((try? WorkoutEvidenceReportRules.snapshot(logs: logs, scope: WorkoutReportScope(), now: .distantFuture))?.setups ?? []) { Text("\($0.name) · \($0.context)").tag($0.id) }
                        }
                        Picker("Session content", selection: $selectedType) {
                            Text("All types").tag("")
                            ForEach(ExerciseType.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        if !exerciseStats.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text("Exercise").appTextRole(.secondary)
                                WorkoutHistoryExerciseRail(
                                    stats: exerciseStats,
                                    selectedExercise: $selectedExercise
                                )
                            }
                            .padding(.vertical, AppSpacing.compact)
                        }
                        NavigationLink("Training report", destination: WorkoutEvidenceReportView(initialProgramID: selectedProgram.isEmpty ? nil : selectedProgram))
                            .frame(minHeight: 44)
                    } label: {
                        HStack {
                            Label("More filters", systemImage: "line.3.horizontal.decrease")
                                .appTextRole(.secondary)
                            Spacer()
                            let count = [selectedProgram, selectedBlock, selectedSetup, selectedType].filter { !$0.isEmpty }.count + (selectedExercise == nil ? 0 : 1)
                            if count > 0 {
                                Text("\(count) active").appTextRole(.caption).foregroundStyle(AppPalette.brandText)
                            }
                        }
                        .accessibilityIdentifier("workout_history_context_filters")
                    }
                    .tint(AppPalette.text)
                    .appSurface(.quiet)

                    if filteredLogs.isEmpty {
                        WorkoutHistoryNoMatchesState {
                            searchText = ""
                            selectedRange = .all
                            selectedExercise = nil
                            selectedProgram = ""; selectedBlock = ""; selectedSetup = ""; selectedType = ""
                        }
                    } else {
                        let count = filteredLogs.count
                        let sessionCount = "\(count) \(count == 1 ? "session" : "sessions")"
                        let coverage = hasCompleteCoverage ? nil : "More history available"
                        if let selectedExercise {
                            AppSectionHeader(title: selectedExercise, subtitle: [sessionCount, coverage].compactMap { $0 }.joined(separator: " · "))
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sessionCount).appTextRole(.control)
                                if let coverage { Text(coverage).appTextRole(.secondary).foregroundStyle(.secondary) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                                NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                                    WorkoutHistoryRow(
                                        log: log,
                                        routineName: log.displayName(routines: workoutService.userRoutines, programs: workoutService.userPrograms),
                                        programPosition: log.programPosition(in: workoutService.userPrograms),
                                        personalRecordCount: WorkoutHistoryInsights.personalRecordCount(for: log, allLogs: logs)
                                    )
                                }
                                .buttonStyle(.plain)

                                if index < filteredLogs.count - 1 {
                                    Divider()
                                        .padding(.leading, 76)
                                }
                            }
                        }
                        .appSurface(.quiet, padding: 0)
                        .accessibilityIdentifier("workout_history_list")
                    }

                    historyCoverage

                    DisclosureGroup("History highlights") {
                        WorkoutHistoryHeaderCard(
                            sessionCount: filteredLogs.count,
                            totalSessionCount: logs.count,
                            totalVolume: highlights.totalVolume,
                            totalSets: highlights.totalSets,
                            latestDate: filteredLogs.first?.date,
                            hasCompleteCoverage: hasCompleteCoverage
                        )
                        .padding(.top, AppSpacing.row)
                        WorkoutHistoryHighlightsCard(highlights: highlights)
                            .padding(.top, AppSpacing.row)
                    }
                    .appTextRole(.secondary)
                    .tint(AppPalette.text)

                    Color.clear.frame(height: AppSpacing.group)

                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("workout_history_screen")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await loadHistory(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading || isLoadingMore)
                .accessibilityLabel("Refresh workout history")
            }
        }
        .refreshable {
            await loadHistory(force: true)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .task {
            await loadHistory(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutSessionCorrected)) { note in
            guard note.object as? String == DIContainer.shared.authService.currentUserID else { return }
            Task { await loadHistory(force: true) }
        }
    }

    private func matchesSelectedExercise(_ log: WorkoutSessionLog) -> Bool {
        guard let selectedExercise else { return true }
        return log.completedExercises.contains { $0.exerciseName == selectedExercise }
    }

    private func matchesSearch(_ log: WorkoutSessionLog) -> Bool {
        let query = searchText.trimmedForHistory.lowercased()
        guard !query.isEmpty else { return true }

        if log.date.formatted(date: .abbreviated, time: .omitted).lowercased().contains(query) {
            return true
        }

        return log.completedExercises.contains { exercise in
            exercise.exerciseName.lowercased().contains(query)
        }
    }

    private var historyCoverage: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                if isLoadingMore { ProgressView().accessibilityLabel("Loading remaining workout history") }
                Image(systemName: hasCompleteCoverage ? "checkmark.circle" : "clock.arrow.circlepath")
                    .foregroundStyle(hasCompleteCoverage ? AppPalette.positive : AppPalette.brandText)
                Text(history.coverageText)
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if history.canLoadEarlier && !isLoading && !isLoadingMore {
                Button("Load all earlier sessions") { Task { await history.loadRemaining() } }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("workout_history_load_more")
            }
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_history_coverage")
    }

    @MainActor
    private func loadHistory(force: Bool) async { await history.load(force: force) }

}

private enum WorkoutHistoryRange: String, CaseIterable, Identifiable {
    case all = "All"
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"

    var id: String { rawValue }

    func contains(_ date: Date) -> Bool {
        guard self != .all else { return true }
        let days: Int
        switch self {
        case .all:
            days = 0
        case .sevenDays:
            days = 7
        case .thirtyDays:
            days = 30
        case .ninetyDays:
            days = 90
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return date >= start
    }
}

private struct WorkoutExerciseHistoryStat: Identifiable {
    let name: String
    let sessions: Int
    let sets: Int
    let volume: Double
    let bestSet: CompletedSet?

    var id: String { name }

    var bestSetText: String {
        guard let bestSet, bestSet.weight > 0, bestSet.reps > 0 else { return "\(sets) sets" }
        return "\(Int(bestSet.weight)) x \(bestSet.reps)"
    }
}

private struct WorkoutHistoryHighlights {
    let totalVolume: Double
    let totalSets: Int
    let sessionCount: Int
    let bestSetTitle: String
    let bestSetSubtitle: String
    let topExerciseTitle: String
    let topExerciseSubtitle: String
    let personalRecordCount: Int

    static let empty = WorkoutHistoryHighlights(
        totalVolume: 0,
        totalSets: 0,
        sessionCount: 0,
        bestSetTitle: "No lift",
        bestSetSubtitle: "Add completed sets",
        topExerciseTitle: "No trend",
        topExerciseSubtitle: "Train to build history",
        personalRecordCount: 0
    )
}

private enum WorkoutHistoryInsights {
    static func exerciseStats(for logs: [WorkoutSessionLog]) -> [WorkoutExerciseHistoryStat] {
        var sessionIDsByExercise: [String: Set<String>] = [:]
        var setsByExercise: [String: Int] = [:]
        var volumeByExercise: [String: Double] = [:]
        var bestSetByExercise: [String: CompletedSet] = [:]

        for (index, log) in WorkoutSetMath.uniqueSessions(logs).enumerated() {
            let logID = stableLogIdentity(for: log, fallbackIndex: index)
            for exercise in log.completedExercises {
                sessionIDsByExercise[exercise.exerciseName, default: []].insert(logID)
                setsByExercise[exercise.exerciseName, default: 0] += WorkoutSetMath.workingSets(in: exercise).count
                volumeByExercise[exercise.exerciseName, default: 0] += volume(for: exercise)

                if let bestSet = bestSet(in: exercise),
                   estimatedOneRepMax(bestSet) > estimatedOneRepMax(bestSetByExercise[exercise.exerciseName]) {
                    bestSetByExercise[exercise.exerciseName] = bestSet
                }
            }
        }

        let ambiguous = WorkoutHistoryInsights.incompatibleNames(in: logs)
        return setsByExercise.map { name, sets in
            WorkoutExerciseHistoryStat(
                name: name,
                sessions: sessionIDsByExercise[name]?.count ?? 0,
                sets: sets,
                volume: volumeByExercise[name] ?? 0,
                bestSet: ambiguous.contains(WorkoutSetMath.normalizedName(name)) ? nil : bestSetByExercise[name]
            )
        }
        .sorted {
            if $0.sessions != $1.sessions { return $0.sessions > $1.sessions }
            if $0.sets != $1.sets { return $0.sets > $1.sets }
            return $0.name < $1.name
        }
    }

    static func highlights(for logs: [WorkoutSessionLog], allLogs: [WorkoutSessionLog]) -> WorkoutHistoryHighlights {
        guard !logs.isEmpty else { return .empty }

        let totalSets = logs.reduce(0) { partial, log in
            partial + WorkoutSetMath.workingSetCount(log)
        }
        let totalVolume = logs.reduce(0) { partial, log in
            partial + log.completedExercises.reduce(0) { $0 + volume(for: $1) }
        }
        let stats = exerciseStats(for: logs)
        let topExercise = stats.first
        let bestLift = bestLift(in: logs)
        let prCount = logs.reduce(0) { $0 + personalRecordCount(for: $1, allLogs: allLogs) }

        return WorkoutHistoryHighlights(
            totalVolume: totalVolume,
            totalSets: totalSets,
            sessionCount: logs.count,
            bestSetTitle: bestLift?.title ?? "No lift",
            bestSetSubtitle: bestLift?.subtitle ?? "Add completed sets",
            topExerciseTitle: topExercise?.name ?? "No trend",
            topExerciseSubtitle: topExercise.map { "\($0.sessions) sessions • \($0.sets) sets" } ?? "Train to build history",
            personalRecordCount: prCount
        )
    }

    static func personalRecordCount(for log: WorkoutSessionLog, allLogs: [WorkoutSessionLog]) -> Int {
        WorkoutSetMath.recordCount(in: log, history: allLogs)
    }

    static func stableLogIdentity(for log: WorkoutSessionLog, fallbackIndex: Int) -> String {
        log.id ?? "\(Int(log.date.timeIntervalSince1970))-\(log.routineID)-\(fallbackIndex)"
    }

    private static func incompatibleNames(in logs: [WorkoutSessionLog]) -> Set<String> {
        Dictionary(grouping: logs.flatMap(\.completedExercises), by: { WorkoutSetMath.normalizedName($0.exerciseName) })
            .reduce(into: Set<String>()) { result, group in
                if let first = group.value.first, !group.value.allSatisfy({ WorkoutSetMath.compatible(first, $0) }) { result.insert(group.key) }
            }
    }

    private static func bestLift(in logs: [WorkoutSessionLog]) -> (title: String, subtitle: String)? {
        let ambiguous = incompatibleNames(in: logs)
        var bestExerciseName: String?
        var topCompletedSet: CompletedSet?

        for log in logs {
            for exercise in log.completedExercises {
                guard !ambiguous.contains(WorkoutSetMath.normalizedName(exercise.exerciseName)), let candidate = bestSet(in: exercise) else { continue }
                if estimatedOneRepMax(candidate) > estimatedOneRepMax(topCompletedSet) {
                    bestExerciseName = exercise.exerciseName
                    topCompletedSet = candidate
                }
            }
        }

        guard let bestExerciseName, let topCompletedSet else { return nil }
        return (
            "\(Int(topCompletedSet.weight)) x \(topCompletedSet.reps)",
            bestExerciseName
        )
    }

    private static func bestSet(in exercise: CompletedExercise) -> CompletedSet? {
        WorkoutSetMath.bestSet(exercise)
    }

    private static func volume(for exercise: CompletedExercise) -> Double {
        WorkoutSetMath.volume(exercise)
    }

    private static func estimatedOneRepMax(_ set: CompletedSet?) -> Double {
        guard let set else { return 0 }
        return WorkoutSetMath.strengthScore(set)
    }
}

private struct WorkoutHistoryLoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.brandPrimary)
            Text("Loading workout history")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WorkoutHistoryHeaderCard: View {
    let sessionCount: Int
    let totalSessionCount: Int
    let totalVolume: Double
    let totalSets: Int
    let latestDate: Date?
    let hasCompleteCoverage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                title: "Your training",
                subtitle: latestDate.map {
                    "Last workout: \($0.formatted(date: .abbreviated, time: .omitted))"
                } ?? "No sessions match the current filters."
            )

            AppMetricStrip(items: [
                AppMetricItem(label: hasCompleteCoverage ? "Sessions" : "Loaded sessions", value: sessionCount.formatted()),
                AppMetricItem(label: hasCompleteCoverage ? "Sets" : "Loaded sets", value: totalSets.formatted(), accent: .accentPositive),
                AppMetricItem(
                    label: hasCompleteCoverage ? "Volume" : "Loaded volume",
                    value: totalVolume > 0 ? totalVolume.formattedWorkoutVolume : "0",
                    accent: AppPalette.caution
                )
            ])
            .appSurface(.emphasized)
        }
        .accessibilityIdentifier("workout_history_header")
    }
}

private struct WorkoutHistoryFilterCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var searchText: String
    @Binding var selectedRange: WorkoutHistoryRange

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("Search exercise or date")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
                HStack(spacing: AppSpacing.compact) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField(dynamicTypeSize.isAccessibilitySize ? "" : "Search exercise or date", text: $searchText)
                        .appTextRole(.body)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search exercise or date")
                        .accessibilityIdentifier("workout_history_search")

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear workout history search")
                    }
                }
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 48)
                .background(
                    AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

                Picker("Range", selection: $selectedRange) {
                    ForEach(WorkoutHistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
            .appSurface(.quiet)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_history_filters")
    }
}

private struct WorkoutHistoryExerciseRail: View {
    let stats: [WorkoutExerciseHistoryStat]
    @Binding var selectedExercise: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    WorkoutExerciseFilterChip(
                        title: "All",
                        subtitle: "\(stats.count) moves",
                        isSelected: selectedExercise == nil
                    ) {
                        selectedExercise = nil
                    }

                    ForEach(stats.prefix(18)) { stat in
                        WorkoutExerciseFilterChip(
                            title: stat.name,
                            subtitle: "\(stat.sessions)x • \(stat.bestSetText)",
                            isSelected: selectedExercise == stat.name
                        ) {
                            selectedExercise = selectedExercise == stat.name ? nil : stat.name
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

private struct WorkoutExerciseFilterChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(subtitle)
                    .appTextRole(.caption)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.text)
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.compact)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 220 : (title == "All" ? 92 : 196),
                alignment: .leading
            )
            .frame(minHeight: 52)
            .background(
                isSelected ? AppPalette.brand : AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutHistoryHighlightsCard: View {
    let highlights: WorkoutHistoryHighlights

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Highlights",
                subtitle: "\(highlights.sessionCount) \(highlights.sessionCount == 1 ? "session" : "sessions") in view"
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Best set · \(highlights.bestSetSubtitle)",
                    value: highlights.bestSetTitle,
                    accent: AppPalette.caution
                ),
                AppMetricItem(
                    label: "Top move · \(highlights.topExerciseSubtitle)",
                    value: highlights.topExerciseTitle
                ),
                AppMetricItem(
                    label: highlights.personalRecordCount == 1 ? "New high" : "New highs",
                    value: highlights.personalRecordCount.formatted(),
                    accent: .accentPositive
                ),
                AppMetricItem(
                    label: "Average sets / session",
                    value: highlights.sessionCount == 0
                        ? "0"
                        : (highlights.totalSets / max(highlights.sessionCount, 1)).formatted(),
                    accent: AppPalette.effort
                )
            ])
            .appSurface(.quiet)
        }
    }
}

struct WorkoutHistoryRow: View {
    let log: WorkoutSessionLog
    let routineName: String
    let programPosition: String
    let personalRecordCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var totalVolume: Double {
        log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + WorkoutSetMath.volume(exercise)
        }
    }

    private var completedSetCount: Int {
        log.completedExercises.reduce(0) { $0 + $1.sets.count }
    }

    // Split into typed steps: the previous single chained expression with inline
    // Epley arithmetic exceeded the CI compiler's type-check time budget.
    private var topSetText: String? {
        let allSets: [CompletedSet] = log.completedExercises.flatMap(\.sets)
        let workingSets: [CompletedSet] = allSets.filter { $0.weight > 0 && $0.reps > 0 }
        let topSet: CompletedSet? = workingSets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }

        guard let topSet else { return nil }
        return "\(Int(topSet.weight)) lb x \(topSet.reps)"
    }

    private func estimatedOneRepMax(_ set: CompletedSet) -> Double {
        set.weight * (1.0 + Double(set.reps) / 30.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(log.date.formatted(.dateTime.month(.abbreviated).day()))
                            .appTextRole(.caption).foregroundStyle(AppPalette.brandText)
                        sessionIdentity
                        recordBadge
                    }
                } else {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        dateBadge
                        sessionIdentity
                        Spacer(minLength: AppSpacing.compact)
                        recordBadge

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Exercises", value: log.completedExercises.count.formatted()),
                AppMetricItem(label: "Sets", value: completedSetCount.formatted(), accent: .accentPositive),
                AppMetricItem(
                    label: totalVolume > 0 ? "Volume (lb)" : "PR signals",
                    value: totalVolume > 0 ? totalVolume.formattedWorkoutVolume : personalRecordCount.formatted(),
                    accent: totalVolume > 0 ? AppPalette.effort : AppPalette.positive
                )
            ])
        }
        .padding(AppSpacing.group)
        .accessibilityElement(children: .combine)
    }

    private var dateBadge: some View {
        VStack(spacing: 2) {
            Text(log.date.formatted(.dateTime.day()))
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.brandText)
            Text(log.date.formatted(.dateTime.month(.abbreviated)))
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 52)
        .frame(minHeight: 56)
        .background(
            AppPalette.brand.opacity(0.10),
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .accessibilityHidden(true)
    }

    private var sessionIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routineName)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Text(
                [log.date.formatted(date: .omitted, time: .shortened), programPosition, topSetText]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    @ViewBuilder
    private var recordBadge: some View {
        if personalRecordCount > 0 {
            Label(
                personalRecordCount == 1 ? "PR" : "\(personalRecordCount) PRs",
                systemImage: "rosette"
            )
            .appTextRole(.caption)
            .foregroundStyle(Color.accentPositive)
        }
    }
}

private struct WorkoutHistoryNoMatchesState: View {
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .appFont(size: 34, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .accessibilityHidden(true)

            Text("No Matches")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text("Try a different movement, date, or time range.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onClear) {
                Label("Clear Filters", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private struct WorkoutHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "clock.arrow.circlepath")
                .appFont(size: 40, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .accessibilityHidden(true)

            Text("No Workout History")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text("Finish a routine and your training log will start filling in here.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension String {
    var trimmedForHistory: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    var formattedWorkoutVolume: String {
        let value = abs(self)
        if value >= 1_000_000 {
            return String(format: "%.1fM", self / 1_000_000)
        }
        if value >= 10_000 {
            return String(format: "%.0fK", self / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", self / 1_000)
        }
        return "\(Int(self))"
    }
}

/// Read-only progressive loading. Totals become complete only after the cursor is
/// exhausted by an online read; errors retain each already-confirmed page.
@MainActor
final class WorkoutHistoryLoader: ObservableObject {
    typealias PageFetcher = @MainActor (String, WorkoutHistoryCursor?, Int) async throws -> WorkoutHistoryPage
    @Published private(set) var logs: [WorkoutSessionLog]
    @Published private(set) var isLoading: Bool
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadError: String?
    @Published private(set) var hasCompleteCoverage: Bool
    @Published private(set) var cachedCoverage = false
    private(set) var nextCursor: WorkoutHistoryCursor?
    private var loadRequestID = UUID()
    private var loadedUserID: String?
    private var seenCursors = Set<String>()
    private let isFixture: Bool
    private let currentUserID: @MainActor () -> String?
    private let fetchPage: PageFetcher

    init(fixtureLogs: [WorkoutSessionLog]? = nil,
         currentUserID: @escaping @MainActor () -> String? = { DIContainer.shared.authService.currentUserID },
         fetchPage: @escaping PageFetcher = { uid, cursor, size in
             try await DIContainer.shared.workoutRepository.fetchWorkoutHistoryPage(userID: uid, cursor: cursor, pageSize: size)
         }) {
        logs = fixtureLogs ?? []; isFixture = fixtureLogs != nil
        isLoading = fixtureLogs == nil; hasCompleteCoverage = fixtureLogs != nil
        self.currentUserID = currentUserID; self.fetchPage = fetchPage
    }

    var canLoadEarlier: Bool { nextCursor != nil }
    var coverageText: String {
        if cachedCoverage { return "\(logs.count) cached sessions loaded. Reconnect and refresh to confirm complete history. Filters and totals cover only these loaded sessions." }
        if hasCompleteCoverage { return "All \(logs.count) dated sessions loaded. Filters and totals include your full loaded history. Refresh to include newly saved or backdated workouts." }
        if isLoadingMore { return "Loading complete history · \(logs.count) sessions loaded so far. Totals update as earlier sessions arrive." }
        return "\(logs.count) sessions loaded · earlier history is not yet confirmed complete. Filters and totals cover only the loaded sessions." }

    func load(force: Bool) async {
        guard !isFixture else { isLoading = false; return }
        guard let uid = currentUserID() else { clearForAccountChange(); return }
        if loadedUserID != uid { clearForAccountChange(); loadedUserID = uid }
        guard force || logs.isEmpty else { return }
        let requestID = UUID(); loadRequestID = requestID
        isLoading = true; isLoadingMore = false; hasCompleteCoverage = false; loadError = nil
        seenCursors = []
        defer { if requestID == loadRequestID { isLoading = false } }
        do {
            try Task.checkCancellation()
            let page = try await fetchPage(uid, nil, 50)
            guard accepts(userID: uid, requestID: requestID) else { return }
            try accept(page, userID: uid, replacing: true)
            isLoading = false
            if page.isFromCache && page.logs.isEmpty {
                loadError = "No online history read was confirmed. Reconnect and refresh; an empty cache does not mean your workouts are gone."
            }
            if !page.isFromCache { await drain(userID: uid, requestID: requestID) }
        } catch {
            guard accepts(userID: uid, requestID: requestID) else { return }
            loadError = error is CancellationError ? "History loading paused. Your loaded sessions are kept; refresh or continue loading when ready."
                : logs.isEmpty ? "Workout history could not load. Try again when connected."
                : "History could not refresh completely. Your loaded sessions are still shown."
        }
    }

    func loadRemaining() async {
        guard !isLoading, !isLoadingMore, let uid = currentUserID(), uid == loadedUserID, nextCursor?.userID == uid else { return }
        await drain(userID: uid, requestID: loadRequestID)
    }

    private func drain(userID: String, requestID: UUID) async {
        guard nextCursor != nil else { return }
        isLoadingMore = true; loadError = nil
        defer { if requestID == loadRequestID { isLoadingMore = false } }
        do {
            while let cursor = nextCursor {
                try Task.checkCancellation()
                let page = try await fetchPage(userID, cursor, 50)
                guard accepts(userID: userID, requestID: requestID) else { return }
                try accept(page, userID: userID, replacing: false)
                if page.isFromCache { break }
            }
        } catch {
            guard accepts(userID: userID, requestID: requestID) else { return }
            loadError = error is CancellationError ? "History loading paused. Your loaded sessions are kept; continue loading earlier sessions when ready."
                : "Earlier sessions could not load. Your current list and filters are kept; try Load all earlier sessions again."
        }
    }

    private func accept(_ page: WorkoutHistoryPage, userID: String, replacing: Bool) throws {
        if let cursor = page.nextCursor {
            try cursor.validate(userID: userID)
            let key = "\(cursor.lastSeconds)|\(cursor.lastNanoseconds)|\(cursor.lastDocumentID)"
            guard seenCursors.insert(key).inserted else { throw WorkoutHistoryReadError.invalidCursor }
        }
        logs = WorkoutSetMath.uniqueSessions(replacing ? page.logs : page.logs + logs).sorted {
            if $0.date != $1.date { return $0.date > $1.date }; return ($0.id ?? "") > ($1.id ?? "")
        }
        nextCursor = page.nextCursor
        cachedCoverage = replacing ? page.isFromCache : cachedCoverage || page.isFromCache
        hasCompleteCoverage = nextCursor == nil && !cachedCoverage
    }

    private func accepts(userID: String, requestID: UUID) -> Bool {
        guard requestID == loadRequestID else { return false }
        guard currentUserID() == userID else { clearForAccountChange(); return false }
        return true
    }
    private func clearForAccountChange() {
        loadRequestID = UUID(); loadedUserID = nil; logs = []; nextCursor = nil
        isLoading = false; isLoadingMore = false; cachedCoverage = false; hasCompleteCoverage = false
        loadError = nil; seenCursors = []
    }
}
