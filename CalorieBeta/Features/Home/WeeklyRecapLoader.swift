import MyFitPlateCore
import SwiftUI

@MainActor
final class WeeklyRecapLoader: ObservableObject {
    @Published private(set) var recap: WeeklyRecap?
    @Published private(set) var isLoading: Bool
    @Published private(set) var loadMessage: String?

    private var generation = UUID()
    private var loadedUserID: String?
    private var loadedDay: Date?
    private var acceptsInitialRecap: Bool

    init(initialRecap: WeeklyRecap? = nil) {
        recap = initialRecap
        isLoading = initialRecap == nil
        acceptsInitialRecap = initialRecap != nil
    }

    func load(
        dailyLogService: DailyLogService,
        workoutService: WorkoutService,
        goalSettings: GoalSettings,
        force: Bool = false
    ) async {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            generation = UUID()
            recap = nil
            isLoading = false
            loadedUserID = nil
            loadedDay = nil
            acceptsInitialRecap = false
            loadMessage = "Sign in to build your weekly report."
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let hasCurrentRecap = recap != nil && (
            acceptsInitialRecap || (
                loadedUserID == userID &&
                loadedDay.map { calendar.isDate($0, inSameDayAs: today) } == true
            )
        )
        guard force || !hasCurrentRecap else { return }

        if loadedUserID != nil, loadedUserID != userID {
            recap = nil
            loadedDay = nil
        }
        acceptsInitialRecap = false

        let requestID = UUID()
        generation = requestID
        isLoading = recap == nil
        loadMessage = nil

        let weekStart = calendar.date(
            byAdding: .day,
            value: -6,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let runHistoryStart = calendar.date(byAdding: .year, value: -2, to: weekStart) ?? weekStart
        let goalSnapshot = GoalSnapshot(
            calories: goalSettings.calories,
            protein: goalSettings.protein,
            weight: goalSettings.weight,
            age: goalSettings.age,
            weightHistory: goalSettings.weightHistory
        )

        async let logsResult = dailyLogService.fetchDailyHistory(
            for: userID,
            startDate: weekStart,
            endDate: now
        )
        async let sessionsResult = workoutService.fetchRecentSessionLogsResult(sinceDays: 365)

        let (dailyLogsResult, workoutLogsResult) = await (logsResult, sessionsResult)
        guard generation == requestID else { return }

        let dailyLogs: [DailyLog]
        let sessions: [WorkoutSessionLog]
        do {
            dailyLogs = try dailyLogsResult.get()
            sessions = try workoutLogsResult.get()
        } catch {
            AppLog.data.error("Weekly report data load failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            loadMessage = recap == nil
                ? "We couldn't load all of your weekly data. Check your connection and try again."
                : "Your existing weekly report is still shown, but it could not refresh."
            return
        }

        let importer = RunImportService()
        var shouldQueryHealth = true
        var runs: [Run]
        var zoneSeconds: [Double]?

        #if DEBUG
        if ScreenshotDemoMode.isEnabled {
            runs = ScreenshotDemoData.runningDemoRuns
            zoneSeconds = [180, 1_020, 2_040, 1_080, 240]
            shouldQueryHealth = false
        } else {
            runs = await fetchRuns(since: runHistoryStart, importer: importer)
        }
        #else
        runs = await fetchRuns(since: runHistoryStart, importer: importer)
        #endif

        guard generation == requestID else { return }
        let shoeStore = RunningShoeStore()
        runs = shoeStore.applyTags(to: runs)

        if shouldQueryHealth {
            runs = await confirmingRoutes(in: runs, weekStart: weekStart, importer: importer)
            zoneSeconds = await aggregateHeartRateZones(
                for: runs.filter { $0.startDate >= weekStart && $0.startDate <= now },
                importer: importer,
                maxHR: HeartRateZones.estimatedMaxHR(age: goalSnapshot.age)
            )
        }

        guard generation == requestID else { return }
        let workoutResultStore = RunWorkoutResultStore()
        let weekRunIDs = runs.filter {
            $0.startDate >= weekStart && $0.startDate <= now
        }.map(\.id)
        let workoutResults = weekRunIDs.compactMap { workoutResultStore.result(forRunID: $0) }

        recap = WeeklyRecapBuilder.build(
            weekEnding: now,
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: sessions,
            priorSessionLogs: sessions,
            weightHistory: goalSnapshot.weightHistory,
            runs: runs,
            calorieGoal: goalSnapshot.calories,
            proteinGoal: goalSnapshot.protein,
            bodyWeightLbs: goalSnapshot.weight,
            heartRateZoneSeconds: zoneSeconds,
            runWorkoutResults: workoutResults,
            shoes: shoeStore.shoes
        )
        loadedUserID = userID
        loadedDay = today
        isLoading = false
        loadMessage = nil
    }

    private func fetchRuns(since: Date, importer: RunImportService) async -> [Run] {
        await withCheckedContinuation { continuation in
            importer.fetchRuns(since: since) { continuation.resume(returning: $0) }
        }
    }

    private func confirmingRoutes(
        in runs: [Run],
        weekStart: Date,
        importer: RunImportService
    ) async -> [Run] {
        var enriched = runs
        for index in enriched.indices where
            enriched[index].startDate >= weekStart &&
            !enriched[index].isIndoor &&
            !enriched[index].hasRoute {
            let fixes = await withCheckedContinuation { continuation in
                importer.fetchRoute(forRunID: enriched[index].id) {
                    continuation.resume(returning: $0)
                }
            }
            enriched[index].hasRoute = fixes.count > 1
        }
        return enriched
    }

    private func aggregateHeartRateZones(
        for runs: [Run],
        importer: RunImportService,
        maxHR: Double
    ) async -> [Double]? {
        var totals = [Double](repeating: 0, count: HeartRateZones.zones.count)
        for run in runs {
            let samples: [(date: Date, bpm: Double)] = await withCheckedContinuation { continuation in
                importer.fetchHeartRateSeries(start: run.startDate, end: run.endDate) {
                    continuation.resume(returning: $0)
                }
            }
            let zones = HeartRateZones.timeInZones(samples: samples, maxHR: maxHR)
            for index in totals.indices {
                totals[index] += zones[index]
            }
        }
        return totals.reduce(0, +) > 0 ? totals : nil
    }
}

private struct GoalSnapshot {
    let calories: Double?
    let protein: Double?
    let weight: Double
    let age: Int
    let weightHistory: [(id: String, date: Date, weight: Double)]
}
