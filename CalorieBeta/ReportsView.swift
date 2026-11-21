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
                            ReportNutritionSummary(summary: viewModel.summary, period: selectedPeriodLabel)
                        }
                        TrendDashboardView(
                            weightHistory: goalSettings.weightHistory,
                            dateRange: selectedTrendRange,
                            title: selectedTrendTitle,
                            compactPresentation: true
                        )
                        .featureSpotlight(isActive: isActive("reports-trend"))
                    }

                    contentStateView
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
                    WeekInMotionLoadingView()
                        .opacity(weeklyRecapLoader.recap == nil ? 1 : 0)
                        .accessibilityHidden(weeklyRecapLoader.recap != nil)

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

    private var contentStateView: some View {
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
            reportsContentSection
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
    private var reportsContentSection: some View {
        switch selectedFocus {
        case .nutrition: AnyView(nutritionReports)
        case .training: AnyView(trainingReports)
        case .recovery: AnyView(recoveryReports)
        }
    }

    private var nutritionReports: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            if hasLoadedSelectedPeriod {
                reportPair
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
        .accessibilityIdentifier("reports_nutrition_content")
    }

    private var trainingReports: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            ReportSectionHeader(title: "Training", subtitle: selectedPeriodLabel)
            if hasLoadedSelectedPeriod, let workoutReport = viewModel.weeklyWorkoutReport {
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: WorkoutAnalyticsView(viewModel: viewModel)) {
                    WorkoutReportCard(report: workoutReport)
                }
                .buttonStyle(AnimatedCardButtonStyle())
                .accessibilityIdentifier("reports_workout_detail")
                #else
                WorkoutReportCard(report: workoutReport)
                #endif
            } else if hasLoadedSelectedPeriod {
                ReportsMessageState(icon: "dumbbell", title: "Build your training picture",
                    message: "Workouts recorded during these dates appear here.", color: .secondary)
            }
            ReportSectionHeader(title: "Weekly review", subtitle: "Last 7 days · independent of the selected dates")
            weekInMotionSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports_training_content")
    }

    private var recoveryReports: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            ReportSectionHeader(title: "Recovery", subtitle: "Recent evidence · independent of the selected dates")
            if let wellnessScore = viewModel.wellnessScore {
                Text("Yesterday’s fully logged food day and recent sleep are separate habit summaries. Heart-rate readings are context only.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: viewModel.mealScore,
                    sleepReport: nil
                )
            }
            ReportSectionHeader(title: "Sleep history", subtitle: "Selected report dates")
            if let report = viewModel.enhancedSleepReport {
                NavigationLink {
                    SleepHistoryDetailView(report: report)
                } label: {
                    AppListRow(icon: "moon.fill", iconColor: AppPalette.recovery,
                        title: "Inspect \(report.dailySleepData.count) recorded nights", subtitle: report.dateRange) {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.appSurface(.quiet, padding: 0)
                }.buttonStyle(.plain).accessibilityIdentifier("reports_sleep_history")
            } else {
                Text(viewModel.sleepHistoryNotice ?? "No readable sleep records for the selected dates. Missing nights are not zero sleep.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
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
        .accessibilityIdentifier("reports_recovery_content")
    }

    @ViewBuilder
    private var reportPair: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.row) {
                mealDistributionDestination
                weightDestination
            }
        } else {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                mealDistributionDestination
                weightDestination
            }
        }
    }

    @ViewBuilder
    private var mealDistributionDestination: some View {
        #if !TARGET_IS_WIDGET_EXTENSION
        NavigationLink(destination: CalorieTrackingView(viewModel: viewModel)) {
            mealDistributionCard
        }
        .buttonStyle(AnimatedCardButtonStyle())
        #else
        mealDistributionCard
        #endif
    }

    @ViewBuilder
    private var weightDestination: some View {
        #if !TARGET_IS_WIDGET_EXTENSION
        NavigationLink(destination: WeightTrackingView()) {
            WeightCardReport
        }
        .buttonStyle(AnimatedCardButtonStyle())
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
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 210)
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
        let progress = goalSettings.calculateWeightProgress().map { min(max($0, 0), 100) } ?? 0
        let progressFraction = (progress / 100.0) * (5.0 / 6.0)

        return VStack(alignment: .center, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                        .appTextRole(.control)
                    Text("Current goal · all entries")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            ZStack {
                Circle()
                    .trim(from: 0, to: 5/6)
                    .stroke(Color(UIColor.secondarySystemFill), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: 105, height: 105)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(progress >= 100 ? AppPalette.positive : AppPalette.effort, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: 105, height: 105)
                    .animation(AppMotion.standard, value: goalSettings.weight)
                VStack {
                    Text("\(Int(progress.rounded()).formatted())%")
                        .appTextRole(.sectionTitle)
                    Text("Progress")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(AppPalette.text)
        .appSurface(.quiet)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }

    @ViewBuilder private var mealDistributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calories")
                        .appTextRole(.control)
                    Text("By meal")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .foregroundColor(.textPrimary)

            if !viewModel.mealDistributionData.isEmpty {
                let groupedMeals = Dictionary(grouping: viewModel.mealDistributionData, by: { $0.mealName })
                let orderedMealNames = ["Breakfast", "Lunch", "Dinner", "Snacks"]

                let processedData: [(meal: String, totalCalories: Double)] = orderedMealNames.compactMap { mealName in
                    let totalCals = groupedMeals[mealName]?.reduce(0) { $0 + $1.totalCalories } ?? 0
                    return totalCals > 0 ? (mealName, totalCals) : nil
                }

                let mealColors: [String: Color] = [
                    "Breakfast": AppPalette.caution,
                    "Lunch": AppPalette.recovery,
                    "Dinner": AppPalette.effort,
                    "Snacks": AppPalette.fat
                ]
                let totalCalories = processedData.reduce(0) { $0 + $1.totalCalories }

                ZStack {
                    Chart(processedData, id: \.meal) { dp in
                        SectorMark(
                            angle: .value("Calories", dp.totalCalories),
                            innerRadius: .ratio(0.64),
                            angularInset: 2
                        )
                        .foregroundStyle(mealColors[dp.meal, default: .gray])
                        .cornerRadius(5)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 112)
                    .animation(AppMotion.standard, value: processedData.map { $0.totalCalories })

                    VStack(spacing: 0) {
                        Text(Int(totalCalories.rounded()).formatted())
                            .appTextRole(.sectionTitle)
                            .foregroundStyle(AppPalette.text)
                        Text("cal")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(processedData, id: \.meal) { dp in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(mealColors[dp.meal, default: .gray])
                                .frame(width: 8, height: 8)
                            Text(dp.meal)
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } else if !viewModel.isLoading {
                VStack(spacing: 6) {
                    Image(systemName: "fork.knife")
                        .appFont(size: 24)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text("No meals logged")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.text)
                    Text("Log a meal to see your daily split.")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .appSurface(.quiet)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }
}
