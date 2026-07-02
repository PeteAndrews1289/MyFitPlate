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
            LazyVStack(spacing: 16) {
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

                        ForEach(Array(filteredLogs.enumerated()), id: \.offset) { _, log in
                            NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                                WorkoutHistoryRow(
                                    log: log,
                                    personalRecordCount: WorkoutHistoryInsights.personalRecordCount(for: log, allLogs: logs)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Color.clear
                        .frame(height: 104)
                }
            }
            .padding()
        }
        .navigationTitle("Workout History")
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
        .background(Color.backgroundPrimary.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Log")
                        .appFont(size: 24, weight: .black)
                        .foregroundColor(.textPrimary)

                    Text(latestDate.map { "Last workout: \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No matching workouts")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                VStack(spacing: 0) {
                    Text("\(sessionCount)")
                        .appFont(size: 18, weight: .black)
                        .foregroundColor(.brandPrimary)
                    Text(totalSessionCount == sessionCount ? "shown" : "of \(totalSessionCount)")
                        .appFont(size: 9, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }

            HStack(spacing: 10) {
                WorkoutHistoryMetric(title: "Sessions", value: "\(sessionCount)", color: .brandPrimary)
                WorkoutHistoryMetric(title: "Sets", value: "\(totalSets)", color: .accentPositive)
                WorkoutHistoryMetric(title: "Volume", value: totalVolume > 0 ? totalVolume.formattedWorkoutVolume : "0", color: .orange)
            }
        }
        .asCard()
    }
}

private struct WorkoutHistoryFilterCard: View {
    @Binding var searchText: String
    @Binding var selectedRange: WorkoutHistoryRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                TextField("Search exercise or date", text: $searchText)
                    .appFont(size: 14, weight: .semibold)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear workout history search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("Range", selection: $selectedRange) {
                ForEach(WorkoutHistoryRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
        .asCard()
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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 13, weight: .bold)
                    .lineLimit(1)
                Text(subtitle)
                    .appFont(size: 10, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: title == "All" ? 92 : 142, alignment: .leading)
            .background(
                isSelected ? Color.brandPrimary : Color.backgroundSecondary,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutHistoryHighlightsCard: View {
    let highlights: WorkoutHistoryHighlights

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkoutHistorySectionHeader(
                title: "Highlights",
                subtitle: "\(highlights.sessionCount) \(highlights.sessionCount == 1 ? "session" : "sessions") in view"
            )

            LazyVGrid(columns: columns, spacing: 10) {
                WorkoutHistoryHighlightTile(
                    title: "Best Set",
                    value: highlights.bestSetTitle,
                    subtitle: highlights.bestSetSubtitle,
                    icon: "bolt.fill",
                    color: .orange
                )
                WorkoutHistoryHighlightTile(
                    title: "Top Move",
                    value: highlights.topExerciseTitle,
                    subtitle: highlights.topExerciseSubtitle,
                    icon: "figure.strengthtraining.traditional",
                    color: .brandPrimary
                )
                WorkoutHistoryHighlightTile(
                    title: "PR Signals",
                    value: "\(highlights.personalRecordCount)",
                    subtitle: highlights.personalRecordCount == 1 ? "new high" : "new highs",
                    icon: "rosette",
                    color: .accentPositive
                )
                WorkoutHistoryHighlightTile(
                    title: "Avg Sets",
                    value: highlights.sessionCount == 0 ? "0" : "\(highlights.totalSets / max(highlights.sessionCount, 1))",
                    subtitle: "per session",
                    icon: "checklist.checked",
                    color: .blue
                )
            }
        }
    }
}

private struct WorkoutHistoryHighlightTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12), in: Circle())

                Text(title)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Text(value)
                .appFont(size: 16, weight: .black)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct WorkoutHistoryRow: View {
    let log: WorkoutSessionLog
    let personalRecordCount: Int

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 3) {
                    Text(log.date.formatted(.dateTime.day()))
                        .appFont(size: 21, weight: .black)
                        .foregroundColor(.brandPrimary)
                    Text(log.date.formatted(.dateTime.month(.abbreviated)))
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)
                }
                .frame(width: 48, height: 56)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(exercisePreview)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(log.date.formatted(date: .omitted, time: .shortened))
                        if let topSetText {
                            Text(topSetText)
                        }
                    }
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if personalRecordCount > 0 {
                    Text("PR")
                        .appFont(size: 11, weight: .black)
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.accentPositive, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
                WorkoutHistoryPill(title: "\(log.completedExercises.count)", subtitle: "exercises", icon: "dumbbell.fill", color: .brandPrimary)
                WorkoutHistoryPill(title: "\(completedSetCount)", subtitle: "sets", icon: "checkmark.seal.fill", color: .accentPositive)

                if totalVolume > 0 {
                    WorkoutHistoryPill(title: totalVolume.formattedWorkoutVolume, subtitle: "lbs", icon: "chart.bar.fill", color: .orange)
                }

                if personalRecordCount > 1 {
                    WorkoutHistoryPill(title: "\(personalRecordCount)", subtitle: "PRs", icon: "rosette", color: .accentPositive)
                }
            }
        }
        .padding()
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkoutHistorySectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Text(subtitle)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
    }
}

private struct WorkoutHistoryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct WorkoutHistoryPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .appFont(size: 9, weight: .bold)
            Text(title)
                .appFont(size: 11, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .appFont(size: 10, weight: .semibold)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }
}

private struct WorkoutHistoryNoMatchesState: View {
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .appFont(size: 34, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 64, height: 64)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No Matches")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)

            Button("Clear Filters", action: onClear)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brandPrimary, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkoutHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .appFont(size: 42, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 74, height: 74)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No Workout History")
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Finish a routine and your training log will start filling in here.")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
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
