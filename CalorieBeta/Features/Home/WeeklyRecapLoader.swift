import MyFitPlateCore
import SwiftUI

@MainActor
final class WeeklyRecapLoader: ObservableObject {
    @Published private(set) var recap: WeeklyRecap?
    @Published private(set) var revision: WeeklyRecapRevision?
    @Published private(set) var isLoading: Bool
    @Published private(set) var loadMessage: String?
    @Published private(set) var coverageMessage: String?
    @Published private(set) var wasUpdated = false

    private var generation = UUID()
    private var loadedUserID: String?
    private var loadedWindow: WeeklyRecapWindow?
    private var acceptsInitialRecap: Bool

    init(initialRecap: WeeklyRecap? = nil) {
        recap = initialRecap; isLoading = initialRecap == nil
        acceptsInitialRecap = initialRecap != nil
    }

    private func isCurrentRequest(_ requestID: UUID, userID: String) -> Bool {
        guard generation == requestID else { return false }
        guard DIContainer.shared.authService.currentUserID == userID else {
            recap = nil; revision = nil; coverageMessage = nil; loadedUserID = nil
            loadedWindow = nil; isLoading = false; return false
        }
        return true
    }

    func load(dailyLogService: DailyLogService, workoutService: WorkoutService,
              goalSettings: GoalSettings, weekEnding: Date = Date(), force: Bool = false) async {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            generation = UUID(); recap = nil; revision = nil; isLoading = false
            loadedUserID = nil; loadedWindow = nil; acceptsInitialRecap = false
            coverageMessage = nil; loadMessage = "Sign in to build your weekly report."; return
        }
        let now = Date(), calendar = Calendar.current
        let window = WeeklyRecapWindow(endingOn: min(weekEnding, now), calendar: calendar)
        let previousWindow = window.preceding(calendar: calendar)
        let matchesInitial = acceptsInitialRecap && recap.map {
            calendar.isDate($0.weekEnd, inSameDayAs: window.lastDay)
        } == true
        let isSameScope = loadedUserID == userID && loadedWindow == window
        // A supplied Home recap can paint immediately, but still fetch its revision and provenance.
        guard force || revision == nil || !isSameScope else { return }
        if !isSameScope && !matchesInitial { recap = nil; revision = nil }
        acceptsInitialRecap = false
        let requestID = UUID(); generation = requestID
        isLoading = true; loadMessage = nil; coverageMessage = nil; wasUpdated = false
        let goalSnapshot = GoalSnapshot(calories: goalSettings.calories, protein: goalSettings.protein,
            weight: goalSettings.weight, age: goalSettings.age, weightHistory: goalSettings.weightHistory)
        // Include the day after the selected window so a late-night run's recovery meal is available.
        let foodEnd = min(now, window.endExclusive)
        async let foodResult = confirmedFoodHistory(userID: userID,
            startDate: previousWindow.start, endDate: foodEnd)
        async let completeStrength = strengthHistory(userID: userID)
        async let targets = targetHistory(userID: userID)
        let (foodRead, strengthRead, targetRead) = await (foodResult, completeStrength, targets)
        guard isCurrentRequest(requestID, userID: userID) else { return }
        let logs: [DailyLog], sessions: [WorkoutSessionLog]
        do { logs = try foodRead.get(); sessions = try strengthRead.get() } catch {
            isLoading = false
            loadMessage = recap == nil ? "Your complete weekly data could not load. Retry when connected."
                : "The previous report is still shown. Refresh could not confirm complete data."
            return
        }
        let importer = RunImportService()
        var runs: [Run], zones: [Double]?
        var queryHealth = true
        var runCoverage = "All running history currently available from Apple Health and this account's device records. Health may hide sources without read access."
        #if DEBUG
        if ScreenshotDemoMode.isEnabled {
            runs = ScreenshotDemoData.runningDemoRuns; queryHealth = false
            zones = [180, 1_020, 2_040, 1_080, 240]
        } else {
            let result = await lifetimeRuns(userID: userID, importer: importer)
            runs = (try? result.get()) ?? RunFallbackStore.shared.runs(since: .distantPast, for: userID)
            if case .failure = result { runCoverage = "Apple Health could not refresh. Running totals cover only this account's saved device records." }
        }
        #else
        let result = await lifetimeRuns(userID: userID, importer: importer)
        runs = (try? result.get()) ?? RunFallbackStore.shared.runs(since: .distantPast, for: userID)
        if case .failure = result { runCoverage = "Apple Health could not refresh. Running totals cover only this account's saved device records." }
        #endif
        guard isCurrentRequest(requestID, userID: userID) else { return }
        let shoeStore = RunningShoeStore()
        runs = shoeStore.applyTags(to: runs).filter { $0.startDate <= now }
        if queryHealth {
            runs = await confirmingRoutes(in: runs, weekStart: window.start, weekEnd: window.endExclusive, importer: importer)
            zones = await aggregateHeartRateZones(for: runs.filter { window.contains($0.startDate) },
                importer: importer, maxHR: HeartRateZones.estimatedMaxHR(age: goalSnapshot.age))
        }
        guard isCurrentRequest(requestID, userID: userID) else { return }
        let resultStore = RunWorkoutResultStore()
        let results = runs.filter { $0.startDate >= previousWindow.start && $0.startDate < window.endExclusive }
            .compactMap { resultStore.result(forRunID: $0.id) }
        let decisions = targetRead.values
        func build(_ selected: WeeklyRecapWindow, zones: [Double]?) -> WeeklyRecap {
            WeeklyRecapBuilder.build(weekEnding: selected.lastDay, calendar: calendar,
                dailyLogs: logs, sessionLogs: sessions, priorSessionLogs: sessions,
                weightHistory: goalSnapshot.weightHistory, runs: runs,
                calorieGoal: nil, proteinGoal: nil, bodyWeightLbs: goalSnapshot.weight,
                heartRateZoneSeconds: zones, runWorkoutResults: results, shoes: shoeStore.shoes,
                dailyTargets: WeeklyRecapTargetRules.days(in: selected, decisions: decisions,
                    userID: userID, now: now, calendar: calendar), requireHistoricalRecoveryWeight: true, now: now)
        }
        let built = build(window, zones: zones), prior = build(previousWindow, zones: nil)
        let coverage = "Complete saved strength history. " + runCoverage + " " + targetRead.coverage
            + " Recovery targets use the last recorded body weight before each run; unavailable weight is excluded. Nutrition averages use explicitly complete days. Days before a confirmed target or containing a target change are excluded from target adherence."
        do {
            struct SourceEvidence: Codable {
                struct Weight: Codable { let id: String; let date: Date; let weight: Double }
                let logs: [DailyLog]; let sessions: [WorkoutSessionLog]; let runs: [Run]
                let weights: [Weight]; let targets: [WeeklyTargetDecision]; let results: [RunWorkoutResult]
            }
            let source = SourceEvidence(logs: logs.sorted { $0.date < $1.date },
                sessions: sessions.filter { $0.date < window.endExclusive && $0.date <= now }.sorted { ($0.id ?? "") < ($1.id ?? "") },
                runs: runs.filter { $0.startDate < window.endExclusive }.sorted { $0.id < $1.id },
                weights: goalSnapshot.weightHistory.filter { $0.date < window.endExclusive && $0.date <= now }.map { .init(id: $0.id, date: $0.date, weight: $0.weight) }
                    .sorted { $0.date < $1.date }, targets: decisions.filter { $0.decidedAt < window.endExclusive && $0.decidedAt <= now }.sorted { $0.id.uuidString < $1.id.uuidString },
                results: results.sorted { $0.runID < $1.runID })
            let newRevision = try WeeklyRecapRevision(ownerID: userID, window: window,
                sourceFingerprint: PlanFingerprint.make(source), recap: built, prior: prior, coverage: coverage, now: now)
            let journal = WeeklyRecapJournal()
            let existing = try journal.revisions(ownerID: userID, window: window)
            wasUpdated = existing.contains { $0.id != newRevision.id }
            try journal.remember(newRevision, currentUserID: DIContainer.shared.authService.currentUserID)
            revision = newRevision
        } catch {
            revision = nil
            loadMessage = "This report is shown, but its device revision could not be retained. Refresh before preparing a share."
        }
        recap = built; loadedUserID = userID; loadedWindow = window
        coverageMessage = coverage; isLoading = false
    }

    private func confirmedFoodHistory(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        do {
            guard DIContainer.shared.authService.currentUserID == userID else { throw WeeklyRecapJournalError.changedAccount }
            let values = try await DIContainer.shared.nutritionRepository.fetchDailyHistoryForReview(
                userID: userID, startDate: startDate, endDate: endDate)
            guard DIContainer.shared.authService.currentUserID == userID else { throw WeeklyRecapJournalError.changedAccount }
            return .success(values)
        } catch { return .failure(error) }
    }
    private func strengthHistory(userID: String) async -> Result<[WorkoutSessionLog], Error> {
        do { return .success(try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: userID)) } catch { return .failure(error) }
    }
    private func targetHistory(userID: String) async -> (values: [WeeklyTargetDecision], coverage: String) {
        do {
            let values = try await DIContainer.shared.settingsRepository.fetchWeeklyTargetDecisions(userID: userID)
            return (values, "Target evidence comes from confirmed account decisions.")
        } catch {
            let values = (try? WeeklyTargetReviewStore().history(userID: userID)) ?? []
            return (values, "Target history could not refresh; only confirmed decisions retained on this device are available.")
        }
    }
    private func lifetimeRuns(userID: String, importer: RunImportService) async -> Result<[Run], Error> {
        await withCheckedContinuation { continuation in
            importer.fetchLifetimeRuns(userID: userID) { continuation.resume(returning: $0) }
        }
    }

    private func confirmingRoutes(
        in runs: [Run],
        weekStart: Date, weekEnd: Date,
        importer: RunImportService
    ) async -> [Run] {
        var enriched = runs
        for index in enriched.indices where
            enriched[index].startDate >= weekStart && enriched[index].startDate < weekEnd &&
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
