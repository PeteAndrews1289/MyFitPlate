import MyFitPlateCore

import Foundation
import SwiftUI

struct WorkoutHistoryView: View {
    @StateObject private var analyticsService = WorkoutAnalyticsService()
    @State private var logs: [WorkoutSessionLog] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedRange: WorkoutHistoryRange = .all
    @State private var selectedExercise: String?
    private let fixtureLogs: [WorkoutSessionLog]?

    init(fixtureLogs: [WorkoutSessionLog]? = nil) {
        self.fixtureLogs = fixtureLogs
        _logs = State(initialValue: fixtureLogs ?? [])
        _isLoading = State(initialValue: fixtureLogs == nil)
    }

    private var rangeFilteredLogs: [WorkoutSessionLog] {
        logs.filter { selectedRange.contains($0.date) }
    }

    private var filteredLogs: [WorkoutSessionLog] {
        rangeFilteredLogs.filter { log in
            matchesSelectedExercise(log) && matchesSearch(log)
        }
    }

    private var exerciseStats: [WorkoutExerciseHistoryStat] {
        WorkoutHistoryInsights.exerciseStats(for: rangeFilteredLogs)
    }

    private var highlights: WorkoutHistoryHighlights {
        WorkoutHistoryInsights.highlights(for: filteredLogs, allLogs: logs)
    }

    private var hasActiveFilters: Bool {
        selectedRange != .all || selectedExercise != nil || !searchText.trimmedForHistory.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                if isLoading {
                    WorkoutHistoryLoadingState()
                        .padding(.top, 60)
                } else if logs.isEmpty {
                    WorkoutHistoryEmptyState()
                        .padding(.top, 50)
                } else {
                    WorkoutHistoryHeaderCard(
                        sessionCount: filteredLogs.count,
                        totalSessionCount: logs.count,
                        totalVolume: highlights.totalVolume,
                        totalSets: highlights.totalSets,
                        latestDate: filteredLogs.first?.date
                    )

                    WorkoutHistoryFilterCard(
                        searchText: $searchText,
                        selectedRange: $selectedRange
                    )

                    if !exerciseStats.isEmpty {
                        WorkoutHistoryExerciseRail(
                            stats: exerciseStats,
                            selectedExercise: $selectedExercise
                        )
                    }

                    WorkoutHistoryHighlightsCard(highlights: highlights)

                    if filteredLogs.isEmpty {
                        WorkoutHistoryNoMatchesState {
                            searchText = ""
                            selectedRange = .all
                            selectedExercise = nil
                        }
                    } else {
                        WorkoutHistorySectionHeader(
                            title: selectedExercise ?? "Recent Sessions",
                            subtitle: "\(filteredLogs.count) \(filteredLogs.count == 1 ? "session" : "sessions")"
                        )

                        VStack(spacing: 0) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                                NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                                    WorkoutHistoryRow(
                                        log: log,
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

                    Color.clear
                        .frame(height: 104)
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
                .disabled(isLoading)
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

    @MainActor
    private func loadHistory(force: Bool) async {
        guard fixtureLogs == nil else {
            isLoading = false
            return
        }
        guard force || logs.isEmpty else { return }
        guard let uid = DIContainer.shared.authService.currentUserID else {
            isLoading = false
            return
        }

        isLoading = true
        let fetchedLogs = await analyticsService.fetchWorkoutHistory(userID: uid, limit: 200)
        logs = fetchedLogs.sorted { $0.date > $1.date }
        isLoading = false
    }
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

        for (index, log) in logs.enumerated() {
            let logID = stableLogIdentity(for: log, fallbackIndex: index)
            for exercise in log.completedExercises {
                sessionIDsByExercise[exercise.exerciseName, default: []].insert(logID)
                setsByExercise[exercise.exerciseName, default: 0] += exercise.sets.count
                volumeByExercise[exercise.exerciseName, default: 0] += volume(for: exercise)

                if let bestSet = bestSet(in: exercise),
                   estimatedOneRepMax(bestSet) > estimatedOneRepMax(bestSetByExercise[exercise.exerciseName]) {
                    bestSetByExercise[exercise.exerciseName] = bestSet
                }
            }
        }

        return setsByExercise.map { name, sets in
            WorkoutExerciseHistoryStat(
                name: name,
                sessions: sessionIDsByExercise[name]?.count ?? 0,
                sets: sets,
                volume: volumeByExercise[name] ?? 0,
                bestSet: bestSetByExercise[name]
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
            partial + log.completedExercises.reduce(0) { $0 + $1.sets.count }
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
        let olderLogs = allLogs.filter { $0.date < log.date }
        guard !olderLogs.isEmpty else { return bestLift(in: [log]) == nil ? 0 : 1 }

        var previousBestByExercise: [String: Double] = [:]
        for olderLog in olderLogs {
            for exercise in olderLog.completedExercises {
                let best = exercise.sets.map(estimatedOneRepMax).max() ?? 0
                previousBestByExercise[exercise.exerciseName] = max(previousBestByExercise[exercise.exerciseName] ?? 0, best)
            }
        }

        var recordCount = 0
        for exercise in log.completedExercises {
            let currentBest = exercise.sets.map(estimatedOneRepMax).max() ?? 0
            let previousBest = previousBestByExercise[exercise.exerciseName] ?? 0
            if currentBest > 0, currentBest > previousBest + 0.1 {
                recordCount += 1
            }
        }
        return recordCount
    }

    static func stableLogIdentity(for log: WorkoutSessionLog, fallbackIndex: Int) -> String {
        log.id ?? "\(Int(log.date.timeIntervalSince1970))-\(log.routineID)-\(fallbackIndex)"
    }

    private static func bestLift(in logs: [WorkoutSessionLog]) -> (title: String, subtitle: String)? {
        var bestExerciseName: String?
        var topCompletedSet: CompletedSet?

        for log in logs {
            for exercise in log.completedExercises {
                guard let candidate = bestSet(in: exercise) else { continue }
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
        exercise.sets.max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }
    }

    private static func volume(for exercise: CompletedExercise) -> Double {
        exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    private static func estimatedOneRepMax(_ set: CompletedSet?) -> Double {
        guard let set, set.weight > 0, set.reps > 0 else { return 0 }
        return set.weight * (1 + Double(set.reps) / 30)
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Training Log",
                title: "Workout History",
                subtitle: latestDate.map {
                    "Last workout: \($0.formatted(date: .abbreviated, time: .omitted))"
                } ?? "No sessions match the current filters."
            ) {
                Text(totalSessionCount == sessionCount ? "\(sessionCount) shown" : "\(sessionCount) of \(totalSessionCount)")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brandText)
                    .padding(.horizontal, AppSpacing.row)
                    .frame(minHeight: 36)
                    .background(
                        AppPalette.brand.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Sessions", value: sessionCount.formatted()),
                AppMetricItem(label: "Sets", value: totalSets.formatted(), accent: .accentPositive),
                AppMetricItem(
                    label: "Volume",
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
    @Binding var searchText: String
    @Binding var selectedRange: WorkoutHistoryRange

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Find Sessions",
                subtitle: "Search by movement or date, then narrow the time range."
            )

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                HStack(spacing: AppSpacing.compact) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search exercise or date", text: $searchText)
                        .appTextRole(.body)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

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
        .accessibilityIdentifier("workout_history_filters")
    }
}

private struct WorkoutHistoryExerciseRail: View {
    let stats: [WorkoutExerciseHistoryStat]
    @Binding var selectedExercise: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkoutHistorySectionHeader(
                title: "Exercise Focus",
                subtitle: selectedExercise ?? "Tap a movement to filter"
            )

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
    let personalRecordCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var totalVolume: Double {
        log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }

    private var completedSetCount: Int {
        log.completedExercises.reduce(0) { $0 + $1.sets.count }
    }

    private var exercisePreview: String {
        let preview = log.completedExercises.prefix(2).map { $0.exerciseName }.joined(separator: ", ")
        guard !preview.isEmpty else { return "Workout" }
        return preview + (log.completedExercises.count > 2 ? "..." : "")
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
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            dateBadge
                            sessionIdentity
                        }
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
            Text(exercisePreview)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Text(
                [log.date.formatted(date: .omitted, time: .shortened), topSetText]
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

private struct WorkoutHistorySectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppSectionHeader(title: title, subtitle: subtitle)
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
