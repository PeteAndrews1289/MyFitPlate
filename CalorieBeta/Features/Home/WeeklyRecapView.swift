import SwiftUI
import MyFitPlateCore

struct WeeklyRecapView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var workoutService: WorkoutService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var recap: WeeklyRecap?
    @State private var isLoading = true
    @State private var loadMessage: String?
    @State private var shareImage: Image?
    @State private var csvURL: URL?

    private var weightUnit: String { BodyUnits.weightUnit(metric: useMetric) }

    private var weekRangeText: String {
        guard let recap else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: recap.weekStart)) - \(formatter.string(from: recap.weekEnd))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let recap {
                        reportContent(recap)
                    } else if isLoading {
                        WeeklyReportLoadingState()
                    } else {
                        WeeklyReportEmptyState(
                            message: loadMessage ?? "There is not enough data to build this report yet.",
                            retry: { Task { await loadRecap(force: true) } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Training & Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadRecap() }
        }
    }

    private func reportContent(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            storySection(recap)

            VStack(alignment: .leading, spacing: 12) {
                WeeklyReportSectionHeader(
                    title: "Training",
                    subtitle: "Work completed, with warmups kept out of progress totals."
                )
                strengthCard(recap)
                runningCard(recap)
            }

            VStack(alignment: .leading, spacing: 12) {
                WeeklyReportSectionHeader(
                    title: "Fueling",
                    subtitle: "Every result shows the days or runs it could actually assess."
                )
                fuelingCard(recap)
            }

            VStack(alignment: .leading, spacing: 12) {
                WeeklyReportSectionHeader(
                    title: "Context",
                    subtitle: "Outcome and data-quality signals, without a combined score."
                )
                contextCard(recap)
            }

            shareMenu
        }
    }

    private func storySection(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(weekRangeText)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .textCase(.uppercase)

                Text(recap.story.headline)
                    .appFont(size: 27, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("weekly_report_headline")
            }

            VStack(spacing: 0) {
                WeeklyStoryRow(
                    title: "Training",
                    text: recap.story.training,
                    icon: "figure.mixed.cardio",
                    color: .brandPrimary
                )
                Divider().padding(.leading, 48)
                WeeklyStoryRow(
                    title: "Fuel",
                    text: recap.story.fueling,
                    icon: "fork.knife",
                    color: .accentProtein
                )
                Divider().padding(.leading, 48)
                WeeklyStoryRow(
                    title: "Change",
                    text: recap.story.change,
                    icon: "chart.line.uptrend.xyaxis",
                    color: .accentCarbs
                )
            }
            .weeklyReportSurface()
        }
    }

    private func strengthCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportCardHeader(
                title: "Strength",
                subtitle: recap.workoutsCompleted == 0
                    ? "No strength sessions recorded"
                    : "\(recap.workoutsCompleted) \(recap.workoutsCompleted == 1 ? "session" : "sessions")",
                icon: "dumbbell.fill"
            )

            if recap.workoutsCompleted > 0 {
                WeeklyMetricLayout(metrics: [
                    WeeklyMetricValue(title: "Working sets", value: recap.workingSetCount.formatted()),
                    WeeklyMetricValue(title: "Volume", value: volumeText(recap.totalVolume)),
                    WeeklyMetricValue(title: "PRs", value: recap.personalRecords.formatted())
                ])

                Divider()

                WeeklyReportDetailRow(
                    icon: "gauge.with.dots.needle.50percent",
                    title: "Effort",
                    value: effortText(recap),
                    detail: effortDetail(recap)
                )

                WeeklyReportDetailRow(
                    icon: "flame",
                    title: "Hard days",
                    value: recap.demandingStrengthDays.formatted(),
                    detail: "8+ working sets or average RPE 8+"
                )

                if recap.personalRecords > 0 {
                    WeeklyReportCallout(
                        icon: "star.fill",
                        text: "\(recap.personalRecords) \(recap.personalRecords == 1 ? "lift beat" : "lifts beat") prior history.",
                        color: .accentPositive
                    )
                }
            }
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_strength")
    }

    private func runningCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportCardHeader(
                title: "Running",
                subtitle: recap.runCount == 0
                    ? "No runs recorded"
                    : "\(recap.runCount) \(recap.runCount == 1 ? "run" : "runs")",
                icon: "figure.run"
            )

            if recap.runCount > 0 {
                WeeklyMetricLayout(metrics: [
                    WeeklyMetricValue(title: "Distance", value: RunFormat.distanceText(meters: recap.runMeters, metric: useMetric)),
                    WeeklyMetricValue(title: "Time", value: RunFormat.durationText(seconds: recap.runMovingSeconds)),
                    WeeklyMetricValue(
                        title: "Avg pace",
                        value: RunFormat.paceText(secondsPerKm: recap.averageRunPaceSecondsPerKm, metric: useMetric) ?? "Not available"
                    )
                ])

                Divider()

                WeeklyReportDetailRow(
                    icon: "arrow.left.arrow.right",
                    title: "Prior 7 days",
                    value: runChangeText(recap),
                    detail: recap.priorRunMeters > 0
                        ? "Previously \(RunFormat.distanceText(meters: recap.priorRunMeters, metric: useMetric))"
                        : "No prior-week mileage baseline"
                )

                WeeklyReportDetailRow(
                    icon: "medal.fill",
                    title: "Records",
                    value: recap.runRecordCount.formatted(),
                    detail: recap.paceRecordCount == 0
                        ? "No similar-distance pace bests"
                        : "\(recap.paceRecordCount) similar-distance pace \(recap.paceRecordCount == 1 ? "best" : "bests")"
                )

                WeeklyReportDetailRow(
                    icon: "map.fill",
                    title: "Routes",
                    value: recap.outdoorRunCount > 0
                        ? "\(recap.routeRunCount) of \(recap.outdoorRunCount)"
                        : "Not applicable",
                    detail: recap.outdoorRunCount > 0 ? "Outdoor runs with a confirmed route" : "Indoor runs do not require a route"
                )

                if recap.guidedRunCount > 0 {
                    WeeklyReportDetailRow(
                        icon: "list.number",
                        title: "Guided runs",
                        value: recap.guidedRunCount.formatted(),
                        detail: "\(recap.guidedCompletedSteps) of \(recap.guidedRecordedSteps) recorded steps completed"
                    )
                }

                if let zones = recap.heartRateZoneSeconds {
                    Divider()
                    heartRateZones(zones)
                }

                if let shoe = recap.shoeContext {
                    Divider()
                    shoeRow(shoe)
                }
            }
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_running")
    }

    private func fuelingCard(_ recap: WeeklyRecap) -> some View {
        let trainingCoverage = WeeklyRecapProgress(
            completed: recap.trainingDaysLogged,
            eligible: recap.trainingDays
        )

        return VStack(alignment: .leading, spacing: 16) {
            WeeklyReportProgressRow(
                title: "Diary coverage",
                progress: WeeklyRecapProgress(completed: recap.daysLogged, eligible: 7),
                detail: "Days with at least one food logged",
                color: .brandPrimary
            )

            WeeklyReportProgressRow(
                title: "Training-day coverage",
                progress: trainingCoverage,
                detail: recap.trainingDays == 0 ? "No training days to assess" : "Training days with food in the diary",
                color: .accentPositive
            )

            WeeklyReportProgressRow(
                title: "Calories",
                progress: recap.calorieAdherence,
                detail: calorieDetail(recap),
                color: .orange
            )

            WeeklyReportProgressRow(
                title: "Protein",
                progress: recap.proteinAdherence,
                detail: proteinDetail(recap),
                color: .accentProtein
            )

            WeeklyReportProgressRow(
                title: "Hard-day fuel",
                progress: recap.demandingStrengthFuelAdherence,
                detail: hardDayFuelDetail(recap),
                color: .accentCarbs
            )

            WeeklyReportProgressRow(
                title: "Run recovery",
                progress: recap.recoveryFuelAdherence,
                detail: recoveryDetail(recap),
                color: .accentPositive
            )
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_fueling")
    }

    private func contextCard(_ recap: WeeklyRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyReportDetailRow(
                icon: "chart.line.flattrend.xyaxis",
                title: "Smoothed weight",
                value: smoothedWeightText(recap),
                detail: recap.smoothedWeightChange == nil
                    ? "At least two weigh-ins or a prior baseline are needed"
                    : "Exponential moving average, alpha 0.4"
            )

            Divider()

            WeeklyReportProgressRow(
                title: "Trust review",
                progress: recap.trustReview,
                detail: recap.trustReview.eligible == 0
                    ? "No logged foods required review"
                    : "Review-required food entries confirmed or corrected",
                color: .accentPositive
            )
        }
        .weeklyReportSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekly_report_context")
    }

    private func heartRateZones(_ seconds: [Double]) -> some View {
        let total = seconds.reduce(0, +)
        let colors: [Color] = [.gray, .blue, .accentPositive, .orange, .red]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart-rate zones")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(RunFormat.durationText(seconds: total))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            ForEach(Array(seconds.enumerated()), id: \.offset) { index, zoneSeconds in
                HStack(spacing: 10) {
                    Text("Z\(index + 1)")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(colors[index])
                        .frame(width: 24, alignment: .leading)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(UIColor.tertiarySystemFill))
                            Capsule()
                                .fill(colors[index])
                                .frame(width: geometry.size.width * (total > 0 ? zoneSeconds / total : 0))
                        }
                    }
                    .frame(height: 7)

                    Text(RunFormat.durationText(seconds: zoneSeconds))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(index + 1), \(RunFormat.durationText(seconds: zoneSeconds))")
            }
        }
    }

    private func shoeRow(_ shoe: WeeklyRecapShoeContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WeeklyReportDetailRow(
                icon: "shoeprints.fill",
                title: shoe.name,
                value: "\(Int((shoe.wearFraction * 100).rounded()).formatted())%",
                detail: shoe.isWornOut
                    ? "Replacement distance reached"
                    : "\(RunFormat.distanceText(meters: shoe.totalMeters, metric: useMetric)) tracked"
            )

            ProgressView(value: min(max(shoe.wearFraction, 0), 1))
                .tint(shoe.isWornOut ? .orange : .brandPrimary)
                .accessibilityLabel("Shoe wear")
                .accessibilityValue("\(Int((shoe.wearFraction * 100).rounded())) percent")
        }
    }

    @ViewBuilder
    private var shareMenu: some View {
        if let shareImage {
            Menu {
                ShareLink(
                    item: shareImage,
                    subject: Text("My weekly Training & Fuel report"),
                    message: Text(MyFitPlateLinks.shareMessage("My nutrition and training report from this week.")),
                    preview: SharePreview("Training & Fuel", image: shareImage)
                ) {
                    Label("Share summary image", systemImage: "photo")
                }

                if let csvURL {
                    ShareLink(
                        item: csvURL,
                        subject: Text("My weekly Training & Fuel data"),
                        message: Text("Aggregate weekly data from MyFitPlate. Routes, food names, account details, and raw heart-rate samples are not included.")
                    ) {
                        Label("Share data as CSV", systemImage: "tablecells")
                    }
                }
            } label: {
                Label("Share report", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                DIContainer.shared.analyticsManager?.logEvent("weekly_report_share_opened", parameters: nil)
            })
            .accessibilityIdentifier("weekly_report_share")
        }
    }

    @MainActor
    private func loadRecap(force: Bool = false) async {
        guard force || recap == nil else { return }
        isLoading = true
        loadMessage = nil

        guard let userID = DIContainer.shared.authService.currentUserID else {
            isLoading = false
            loadMessage = "Sign in to build your weekly report."
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let runHistoryStart = calendar.date(byAdding: .year, value: -2, to: weekStart) ?? weekStart

        async let logsResult = dailyLogService.fetchDailyHistory(
            for: userID,
            startDate: weekStart,
            endDate: now
        )
        async let sessionsResult = workoutService.fetchRecentSessionLogsResult(sinceDays: 365)

        let (dailyLogsResult, workoutLogsResult) = await (logsResult, sessionsResult)
        let dailyLogs: [DailyLog]
        let sessions: [WorkoutSessionLog]
        do {
            dailyLogs = try dailyLogsResult.get()
            sessions = try workoutLogsResult.get()
        } catch {
            AppLog.data.error("Weekly report data load failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            loadMessage = "We couldn't load all of your weekly data. Check your connection and try again."
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

        let shoeStore = RunningShoeStore()
        runs = shoeStore.applyTags(to: runs)

        if shouldQueryHealth {
            runs = await confirmingRoutes(
                in: runs,
                weekStart: weekStart,
                importer: importer
            )
            zoneSeconds = await aggregateHeartRateZones(
                for: runs.filter { $0.startDate >= weekStart && $0.startDate <= now },
                importer: importer,
                maxHR: HeartRateZones.estimatedMaxHR(age: goalSettings.age)
            )
        }

        let workoutResultStore = RunWorkoutResultStore()
        let weekRunIDs = runs.filter { $0.startDate >= weekStart && $0.startDate <= now }.map(\.id)
        let workoutResults = weekRunIDs.compactMap { workoutResultStore.result(forRunID: $0) }

        let built = WeeklyRecapBuilder.build(
            weekEnding: now,
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: sessions,
            priorSessionLogs: sessions,
            weightHistory: goalSettings.weightHistory,
            runs: runs,
            calorieGoal: goalSettings.calories,
            proteinGoal: goalSettings.protein,
            bodyWeightLbs: goalSettings.weight,
            heartRateZoneSeconds: zoneSeconds,
            runWorkoutResults: workoutResults,
            shoes: shoeStore.shoes
        )

        recap = built
        isLoading = false
        DIContainer.shared.analyticsManager?.logEvent("weekly_recap_viewed", parameters: [
            "days_logged": built.daysLogged,
            "training_days": built.trainingDays,
            "workouts": built.workoutsCompleted,
            "runs": built.runCount,
            "prs": built.personalRecords + built.runRecordCount
        ])
        renderShareImage(for: built)
        prepareCSV(for: built)
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

    @MainActor
    private func renderShareImage(for recap: WeeklyRecap) {
        let renderer = ImageRenderer(content: WeeklyRecapShareCard(
            recap: recap,
            weekRangeText: weekRangeText,
            useMetric: useMetric
        ))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }

    private func prepareCSV(for recap: WeeklyRecap) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "MyFitPlate-Training-Fuel-\(formatter.string(from: recap.weekEnd)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let csv = WeeklyRecapCSVExporter.csvString(for: recap, metric: useMetric)
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            csvURL = url
        } catch {
            csvURL = nil
            AppLog.data.error("Weekly report CSV could not be prepared: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func volumeText(_ poundsReps: Double) -> String {
        let unit = useMetric ? "kg-reps" : "lb-reps"
        guard poundsReps > 0 else { return "0 \(unit)" }
        let displayed = BodyUnits.weightDisplayValue(lbs: poundsReps, metric: useMetric)
        return "\(Int(displayed.rounded()).formatted()) \(unit)"
    }

    private func effortText(_ recap: WeeklyRecap) -> String {
        guard let effort = recap.averageEffortRPE else { return "Not logged" }
        return String(format: "%.1f RPE", effort)
    }

    private func effortDetail(_ recap: WeeklyRecap) -> String {
        guard let change = recap.effortChange else { return "No comparable prior-week effort" }
        if abs(change) < 0.05 { return "Level with the prior 7 days" }
        return String(format: "%+.1f vs the prior 7 days", change)
    }

    private func runChangeText(_ recap: WeeklyRecap) -> String {
        guard let change = recap.runDistanceChangeFraction else {
            return recap.runMeters > 0 ? "New baseline" : "Not available"
        }
        return String(format: "%+.0f%%", change * 100)
    }

    private func calorieDetail(_ recap: WeeklyRecap) -> String {
        guard let goal = recap.calorieGoal else { return "Set a calorie goal to assess consistency" }
        let average = recap.averageCalories.map { Int($0.rounded()).formatted() } ?? "No average"
        return "\(average) cal average; within 10% of \(Int(goal.rounded()).formatted())"
    }

    private func proteinDetail(_ recap: WeeklyRecap) -> String {
        guard let goal = recap.proteinGoal else { return "Set a protein goal to assess consistency" }
        let average = recap.averageProtein.map { Int($0.rounded()).formatted() } ?? "No average"
        return "\(average) g average; at least 90% of \(Int(goal.rounded()).formatted()) g"
    }

    private func hardDayFuelDetail(_ recap: WeeklyRecap) -> String {
        guard recap.demandingStrengthDays > 0 else { return "No hard strength days to assess" }
        guard recap.calorieGoal != nil, recap.proteinGoal != nil else { return "Both calorie and protein goals are needed" }
        guard recap.demandingStrengthFuelAdherence.eligible > 0 else {
            return "Nutrition values on hard days could not be assessed"
        }
        return "Both targets logged; food was present on \(recap.demandingStrengthDaysLogged) of \(recap.demandingStrengthDays) hard days"
    }

    private func recoveryDetail(_ recap: WeeklyRecap) -> String {
        guard recap.recoveryFuelAdherence.eligible > 0 else {
            return recap.recoveryFuelPendingRuns > 0
                ? "\(recap.recoveryFuelPendingRuns) recovery \(recap.recoveryFuelPendingRuns == 1 ? "window is" : "windows are") still open"
                : "No run required a formal recovery target"
        }
        let pending = recap.recoveryFuelPendingRuns > 0
            ? "; \(recap.recoveryFuelPendingRuns) still open"
            : ""
        return "\(recap.recoveryFuelAdherence.completed) met both targets; timed food logged after \(recap.recoveryFuelLoggedRuns) of \(recap.recoveryFuelAdherence.eligible) assessed runs\(pending)"
    }

    private func smoothedWeightText(_ recap: WeeklyRecap) -> String {
        guard let change = recap.smoothedWeightChange else { return "Not available" }
        let display = BodyUnits.weightDisplayValue(lbs: change, metric: useMetric)
        return String(format: "%+.1f %@", display, weightUnit)
    }
}

private struct WeeklyReportSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WeeklyStoryRow: View {
    let title: String
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(text)
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportCardHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 36, height: 36)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyMetricValue: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct WeeklyMetricLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: [WeeklyMetricValue]

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalMetrics
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(metrics) { metric in
                        metricView(metric)
                        if metric.id != metrics.last?.id {
                            Divider().frame(height: 42)
                        }
                    }
                }

                verticalMetrics
            }
        }
    }

    private var verticalMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(metrics) { metric in
                metricView(metric)
            }
        }
    }

    private func metricView(_ metric: WeeklyMetricValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.value)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
            Text(metric.title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportDetailRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Spacer(minLength: 8)
                    Text(value)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                Text(detail)
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportProgressRow: View {
    let title: String
    let progress: WeeklyRecapProgress
    let detail: String
    let color: Color

    private var valueText: String {
        progress.eligible > 0 ? "\(progress.completed) of \(progress.eligible)" : "Not available"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 8)
                Text(valueText)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(progress.eligible > 0 ? color : Color(UIColor.secondaryLabel))
                    .monospacedDigit()
            }

            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(color)
            }

            Text(detail)
                .appFont(size: 11)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(valueText)
    }
}

private struct WeeklyReportCallout: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
            Text(text)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyReportLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView()
                .tint(.brandPrimary)
            Text("Building your weekly story")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Checking training, nutrition, recovery, and comparable history.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 80)
    }
}

private struct WeeklyReportEmptyState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal")
                .appFont(size: 30, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text("Report unavailable")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(message)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 80)
    }
}

private extension View {
    func weeklyReportSurface() -> some View {
        self
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

/// Fixed-size, aggregate-only card rendered for social sharing.
struct WeeklyRecapShareCard: View {
    let recap: WeeklyRecap
    let weekRangeText: String
    let useMetric: Bool

    private var weightUnit: String { BodyUnits.weightUnit(metric: useMetric) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("MyFitPlate")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                Text(weekRangeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }

            Text(recap.story.headline)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                shareRow(label: "Training days", value: "\(recap.trainingDays)")
                if recap.workoutsCompleted > 0 {
                    shareRow(label: "Strength", value: "\(recap.workingSetCount) working sets")
                }
                if recap.runCount > 0 {
                    shareRow(label: "Running", value: RunFormat.distanceText(meters: recap.runMeters, metric: useMetric))
                }
                shareRow(label: "Food logged", value: "\(recap.daysLogged) of 7 days")
                if recap.proteinAdherence.eligible > 0 {
                    shareRow(label: "Protein consistency", value: "\(recap.proteinAdherence.completed) of \(recap.proteinAdherence.eligible)")
                }
                if let change = recap.smoothedWeightChange {
                    let displayed = BodyUnits.weightDisplayValue(lbs: change, metric: useMetric)
                    shareRow(label: "Smoothed weight", value: String(format: "%+.1f %@", displayed, weightUnit))
                }
            }

            Spacer(minLength: 0)

            Text("Training & Fuel report")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(26)
        .frame(width: 360, height: 500, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.20, blue: 0.15))
    }

    private func shareRow(label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
