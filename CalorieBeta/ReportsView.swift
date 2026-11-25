import MyFitPlateCore

import SwiftUI
import Charts
import Combine

struct ReportsView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject private var appState: AppState
    @State private var projectedOwner: String?
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var workoutService: WorkoutService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var selectedFocus: ReportFocus = .nutrition
    private struct DiaryDestination: Identifiable {
        let day: DiaryDayContext
        let log: DailyLog
        var id: String { day.userID + "|" + day.dayKey }
    }
    @State private var diaryDestination: DiaryDestination?
    @State private var intakeDay: Date?
    @State private var showsProtein = false
    @State private var showsMaiaInsight = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    @State private var showingDetailedInsights = false
    @State private var showingWeeklyReport = false
    @State private var didLogWeekInMotion = false
    @ObservedObject private var weeklyRecapLoader: WeeklyRecapLoader

    init(dailyLogService: DailyLogService, weeklyRecapLoader: WeeklyRecapLoader) {
        _viewModel = StateObject(wrappedValue: ReportsViewModel(dailyLogService: dailyLogService))
        _weeklyRecapLoader = ObservedObject(wrappedValue: weeklyRecapLoader)
    }

    private var selectedTrendRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start: Date
        let requestedEnd: Date

        switch selectedTimeframe {
        case .week:
            requestedEnd = Date()
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: requestedEnd)) ?? requestedEnd
        case .month:
            requestedEnd = Date()
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: requestedEnd)) ?? requestedEnd
        case .custom:
            start = calendar.startOfDay(for: customStartDate)
            requestedEnd = customEndDate
        }

        let endOfRequestedDay = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: calendar.startOfDay(for: requestedEnd)
        ) ?? requestedEnd
        return start...max(start, endOfRequestedDay)
    }

    private var selectedTrendTitle: String {
        "Weight trend (\(selectedTimeframe.rawValue.lowercased()))"
    }

    private func fetchDataForCurrentSelection() {
        if selectedTimeframe == .custom {
            if customEndDate < customStartDate {
                viewModel.errorMessage = "End date cannot be before start date."
                return
            }
            viewModel.fetchData(for: .custom, startDate: customStartDate, endDate: customEndDate)
        } else {
            viewModel.fetchData(for: selectedTimeframe)
        }
    }

    static let reportsTourSteps: [SpotlightTourStep] = [
        SpotlightTourStep(id: "reports-trend", title: "Weight trend",
                          text: "See your measured weights and a descriptive trend across the selected dates."),
        SpotlightTourStep(id: "reports-overview", title: "Explore your progress",
                          text: "Explore nutrition, training and recovery. Each view shows the dates its evidence covers.")
    ]

    var body: some View {
        SpotlightTourScaffold(steps: ReportsView.reportsTourSteps) { isActive in
        VStack(spacing: 0) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.row))
                : AnyLayout(HStackLayout(spacing: AppSpacing.row))
            headerLayout {
                Text("Reports").appTextRole(.screenTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("reports_screen_header")
                timeframePicker
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.compact)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    Picker("Report focus", selection: $selectedFocus) {
                        ForEach(ReportFocus.allCases) { focus in
                            Text(focus.title).tag(focus)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("reports_focus")
                    .featureSpotlight(isActive: isActive("reports-overview"))

                    if selectedTimeframe == .custom {
                        customDateControls.appSurface(.quiet)
                    }

                    if selectedFocus == .nutrition {
                        if hasLoadedSelectedPeriod {
                            ReportNutritionSummary(summary: viewModel.summary, period: selectedPeriodLabel,
                                calories: viewModel.calorieTrend, protein: viewModel.proteinTrend, range: selectedTrendRange,
                                showsProtein: $showsProtein, selectedDate: $intakeDay) { date in
                                    guard let owner = projectedOwner, owner == DIContainer.shared.authService.currentUserID,
                                          let day = DiaryDayContext(userID: owner, date: date), !day.isFuture() else { return }
                                    let entry = viewModel.diaryEntry(for: day) ?? DailyLog(id: day.dayKey, date: day.startOfDay, meals: [])
                                    diaryDestination = DiaryDestination(day: day, log: entry)
                                }
                        }
                    }

                    contentStateView(highlightsTrend: isActive("reports-trend"))
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            projectedOwner = DIContainer.shared.authService.currentUserID
            viewModel.setup(goals: goalSettings, healthKitViewModel: healthKitViewModel)
            fetchDataForCurrentSelection()
            insightsService.generateDailySmartInsight()
            if let userID = DIContainer.shared.authService.currentUserID {
                viewModel.fetchMealScoreHistory(for: userID)
            }
            if healthKitViewModel.isAuthorized {
                 healthKitViewModel.fetchLastSevenDaysSleep()
            }
        }
        .onReceive(appState.$isUserLoggedIn) { _ in
            let owner = DIContainer.shared.authService.currentUserID
            guard projectedOwner != owner else { return }
            diaryDestination = nil; intakeDay = nil; showsProtein = false
            projectedOwner = owner; viewModel.invalidateAccountProjection()
            showingDetailedInsights = false; showingWeeklyReport = false; showsMaiaInsight = false
            guard let owner, goalSettings.isActiveAccount(owner) else { return }
            viewModel.setup(goals: goalSettings, healthKitViewModel: healthKitViewModel)
            fetchDataForCurrentSelection(); viewModel.fetchMealScoreHistory(for: owner)
        }
        .onReceive(goalSettings.$calories.dropFirst()) { _ in
            Task { @MainActor in
                guard let owner = projectedOwner, owner == DIContainer.shared.authService.currentUserID,
                      goalSettings.isActiveAccount(owner) else { return }
                viewModel.setup(goals: goalSettings, healthKitViewModel: healthKitViewModel)
                fetchDataForCurrentSelection()
            }
        }
        .task { await loadWeekInMotion() }
        .onChange(of: selectedTrendRange) { _, _ in intakeDay = nil }
        .onChange(of: selectedTimeframe) { _, _ in
            fetchDataForCurrentSelection()
        }
        .onChange(of: customStartDate) { _, _ in
            if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: customEndDate) { _, _ in
             if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: healthKitViewModel.sleepSamples) { _, _ in
            // The global seven-day snapshot cannot replace a selected month or historical range.
            fetchDataForCurrentSelection()
        }
        #if !TARGET_IS_WIDGET_EXTENSION
        .navigationDestination(isPresented: $showingDetailedInsights) {
            DetailedInsightsView(insightsService: insightsService)
        }
        .sheet(item: $diaryDestination) { destination in
            NavigationStack { ReportDiaryDayView(day: destination.day, log: destination.log) }
        }
        .sheet(isPresented: $showingWeeklyReport) {
            WeeklyRecapView(initialRecap: weeklyRecapLoader.recap)
        }
        #endif
        }
    }

    @ViewBuilder
    private var weekInMotionSection: some View {
        VStack(spacing: AppSpacing.group) {
            if weeklyRecapLoader.isLoading || weeklyRecapLoader.recap != nil {
                ZStack(alignment: .topLeading) {
                    if let recap = weeklyRecapLoader.recap {
                        let observation = WeekInMotionBuilder.build(from: recap).observation
                        WeekInMotionView(recap: recap) {
                            HapticManager.instance.feedback(.light)
                            DIContainer.shared.analyticsManager?.logEvent(
                                ProductAnalytics.Event.weekInMotionDetailOpened.rawValue,
                                parameters: [
                                    "observation_kind": observation.kind.rawValue,
                                    "observation_tone": observation.tone.rawValue
                                ]
                            )
                            showingWeeklyReport = true
                        }
                        .transition(.opacity)
                    } else {
                        WeekInMotionLoadingView()
                    }
                }
                .animation(AppMotion.standard, value: weeklyRecapLoader.recap != nil)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your week isn't available yet")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    Text(weeklyRecapLoader.loadMessage ?? "Your detailed reports remain available below.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await loadWeekInMotion(force: true) } }
                        .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appSurface(.quiet)
            }

            Divider()
        }
    }

    @MainActor
    private func loadWeekInMotion(force: Bool = false) async {
        await weeklyRecapLoader.load(
            dailyLogService: viewModel.dailyLogService,
            workoutService: workoutService,
            goalSettings: goalSettings,
            force: force
        )
        guard !didLogWeekInMotion, let recap = weeklyRecapLoader.recap else { return }
        didLogWeekInMotion = true
        let motion = WeekInMotionBuilder.build(from: recap)
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.weekInMotionViewed.rawValue, parameters: [
            "days_logged": recap.daysLogged,
            "training_days": recap.trainingDays,
            "recovery_eligible": recap.recoveryFuelAdherence.eligible,
            "trust_eligible": recap.trustReview.eligible,
            "observation_kind": motion.observation.kind.rawValue,
            "observation_tone": motion.observation.tone.rawValue
        ])
    }

    private func contentStateView(highlightsTrend: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            if viewModel.isLoading {
                ProgressView("Loading selected dates…")
                    .appTextRole(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.quiet)
                    .accessibilityIdentifier("reports_period_loading")
            } else if let errorMessage = viewModel.errorMessage {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Label("Selected dates unavailable", systemImage: "exclamationmark.triangle")
                        .appTextRole(.control)
                    Text(errorMessage).appTextRole(.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry these dates", action: fetchDataForCurrentSelection)
                        .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
                }
                .appSurface(.quiet)
                .accessibilityIdentifier("reports_period_error")
            }
            reportsContentSection(highlightsTrend: highlightsTrend)
        }
    }

    private var hasLoadedSelectedPeriod: Bool {
        !viewModel.isLoading && viewModel.errorMessage == nil
    }

    private var selectedPeriodLabel: String {
        let range = selectedTrendRange
        return "\(range.lowerBound.formatted(.dateTime.month(.abbreviated).day())) – \(range.upperBound.formatted(.dateTime.month(.abbreviated).day()))"
    }

    @ViewBuilder
    private func reportsContentSection(highlightsTrend: Bool) -> some View {
        switch selectedFocus {
        case .nutrition: AnyView(nutritionReports(highlightsTrend: highlightsTrend))
        case .training: AnyView(trainingReports)
        case .recovery: AnyView(recoveryReports)
        }
    }

    private func nutritionReports(highlightsTrend: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            if hasLoadedSelectedPeriod {
                mealDistributionDestination
            }
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                TrendDashboardView(
                    weightHistory: goalSettings.weightHistory,
                    dateRange: selectedTrendRange,
                    title: selectedTrendTitle,
                    compactPresentation: true
                )
                .featureSpotlight(isActive: highlightsTrend)
                weightDestination
            }
            #if !TARGET_IS_WIDGET_EXTENSION
            NavigationLink(destination: MetabolismDashboardView()) {
                MetabolismReportCard()
            }
            .buttonStyle(AnimatedCardButtonStyle())
            .accessibilityIdentifier("reports_metabolism")
            #endif

            DisclosureGroup("Maia insights · last 7 days", isExpanded: $showsMaiaInsight) {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    if let insight = insightsService.smartSuggestion {
                        SmartReportInsightCard(insight: insight)
                    }
                    Text("These insights use recent context rather than the selected report dates.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Button("Review insights") {
                        insightsService.generateAndFetchInsights(forLastDays: 7, requestConsentIfNeeded: true)
                        showingDetailedInsights = true
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .padding(.top, AppSpacing.row)
            }
            .appTextRole(.secondary).tint(AppPalette.text)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports_nutrition_content")
    }

    private var trainingReports: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            ReportSectionHeader(title: "Training", subtitle: selectedPeriodLabel)
            if hasLoadedSelectedPeriod, let workoutReport = viewModel.weeklyWorkoutReport {
                WorkoutReportCard(report: workoutReport)
            } else if hasLoadedSelectedPeriod {
                Text("No diary workouts recorded for these dates.").appTextRole(.secondary).foregroundStyle(.secondary)
            }
            #if !TARGET_IS_WIDGET_EXTENSION
            NavigationLink {
                WorkoutEvidenceReportView(initialDates: selectedTrendRange)
            } label: {
                AppListRow(icon: "dumbbell", iconColor: AppPalette.effort,
                    title: "Strength performance", subtitle: "Sets, loads and muscle groups") {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.appSurface(.quiet, padding: 0)
            }
            .buttonStyle(.plain).accessibilityIdentifier("reports_strength_performance")
            #endif
            ReportSectionHeader(title: "Weekly review", subtitle: "Last 7 days · independent of the selected dates")
            weekInMotionSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports_training_content")
    }

    private var recoveryReports: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            ReportSectionHeader(title: "Sleep history", subtitle: selectedPeriodLabel)
            if let report = viewModel.enhancedSleepReport {
                let nightCount = report.dailySleepData.count
                if nightCount > 0 {
                    Text(Duration.seconds(report.averageTimeAsleep).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .appTextRole(.display).monospacedDigit()
                    Text("Average recorded sleep · " + nightCount.formatted() + (nightCount == 1 ? " night" : " nights"))
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                NavigationLink {
                    SleepHistoryDetailView(report: report)
                } label: {
                    AppListRow(icon: "moon.fill", iconColor: AppPalette.recovery,
                        title: report.nightEvidence.isEmpty ? "Sleep history" : "Sleep windows & night details", subtitle: report.dateRange) {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.appSurface(.quiet, padding: 0)
                }.buttonStyle(.plain).accessibilityIdentifier("reports_sleep_history")
            } else if hasLoadedSelectedPeriod || viewModel.sleepHistoryNotice != nil {
                Text(viewModel.sleepHistoryNotice ?? "No readable sleep records for the selected dates. Missing nights are not zero sleep.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            ReportSectionHeader(title: "Recovery", subtitle: "Recent evidence · independent of the selected dates")
            if let wellnessScore = viewModel.wellnessScore, wellnessScore.hasNutrition || wellnessScore.sleepScore != nil {
                Text("Yesterday’s fully logged food day and recent sleep are separate habit summaries. Heart-rate readings are context only.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: viewModel.mealScore,
                    sleepReport: nil
                )
            }
            Text("Apple Health snapshot · last 7 days")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            ComprehensiveHealthCard(
                weeklySteps: healthKitViewModel.weeklySteps,
                weeklyActiveEnergy: healthKitViewModel.weeklyActiveEnergy,
                weeklyRestingHeartRate: healthKitViewModel.weeklyRestingHeartRate,
                weeklyHRV: healthKitViewModel.weeklyHRV
            )
            if goalSettings.gender.lowercased() == "female" {
                CycleTrackingCard()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports_recovery_content")
    }

    @ViewBuilder
    private var mealDistributionDestination: some View {
        #if !TARGET_IS_WIDGET_EXTENSION
        NavigationLink(destination: CalorieTrackingView(viewModel: viewModel, reportDates: selectedTrendRange)) {
            mealDistributionCard
        }
        .buttonStyle(AnimatedCardButtonStyle())
        .accessibilityIdentifier("reports_nutrition_detail")
        #else
        mealDistributionCard
        #endif
    }

    @ViewBuilder
    private var weightDestination: some View {
        #if !TARGET_IS_WIDGET_EXTENSION
        NavigationLink(destination: WeightTrackingView(reportDates: selectedTrendRange)) {
            WeightCardReport
        }
        .buttonStyle(AnimatedCardButtonStyle())
        .accessibilityIdentifier("reports_weight_detail")
        #else
        WeightCardReport
        #endif
    }

    private var timeframePicker: some View {
        Picker("Report dates", selection: $selectedTimeframe) {
            Text("7 days").tag(ReportTimeframe.week)
            Text("30 days").tag(ReportTimeframe.month)
            Label("Custom range", systemImage: "calendar").labelStyle(.iconOnly).tag(ReportTimeframe.custom)
        }
        .pickerStyle(.segmented)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 195)
        .accessibilityIdentifier("reports_timeframe")
    }

    @ViewBuilder
    private var customDateControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                DatePicker(
                    "Start date",
                    selection: $customStartDate,
                    in: ...customEndDate,
                    displayedComponents: .date
                )
                DatePicker(
                    "End date",
                    selection: $customEndDate,
                    in: customStartDate...,
                    displayedComponents: .date
                )
            }
        } else {
            Grid(alignment: .leading) {
                GridRow {
                    Text("Start")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    DatePicker(
                        "Start date",
                        selection: $customStartDate,
                        in: ...customEndDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("End")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    DatePicker(
                        "End date",
                        selection: $customEndDate,
                        in: customStartDate...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var WeightCardReport: some View {
        let progress = goalSettings.calculateWeightProgress()
        return HStack {
            Text("Weight history").appTextRole(.control)
            Spacer()
            if let progress, progress.isFinite {
                Text(min(max(progress, 0), 100).formatted(.number.precision(.fractionLength(0))) + "% of current goal")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").appTextRole(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }

    private var mealDistributionCard: some View {
        let meals = viewModel.mealDistributionData.filter { $0.totalCalories > 0 }.sorted {
            if $0.totalCalories == $1.totalCalories { return $0.mealName < $1.mealName }
            return $0.totalCalories > $1.totalCalories
        }
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack {
                Text("Calories by meal").appTextRole(.sectionTitle)
                Spacer()
                Image(systemName: "chevron.right").appTextRole(.caption).foregroundStyle(.secondary)
            }
            if meals.isEmpty {
                Text("No meals logged for these dates.").appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                Text("Average per day with food recorded").appTextRole(.secondary).foregroundStyle(.secondary)
                ForEach(meals) { meal in
                    HStack(alignment: .firstTextBaseline) {
                        Text(meal.mealName).appTextRole(.body)
                        Spacer()
                        Text(meal.totalCalories.formatted(.number.precision(.fractionLength(0))) + " cal")
                            .appTextRole(.control).monospacedDigit()
                    }
                }
            }
            Text("View nutrition trends").appTextRole(.secondary).foregroundStyle(AppPalette.brandText)
        }
        .appSurface(.quiet)
    }
}
