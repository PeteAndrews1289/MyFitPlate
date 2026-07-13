import MyFitPlateCore

import SwiftUI
import Charts

struct ReportsView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var workoutService: WorkoutService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedTimeframe: ReportTimeframe = .week
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

    private var hasReportContent: Bool {
        viewModel.summary != nil ||
        viewModel.enhancedSleepReport != nil ||
        viewModel.weeklyWorkoutReport != nil ||
        viewModel.wellnessScore != nil
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
                          text: "Track your real moving average smoothed over daily fluctuations."),
        SpotlightTourStep(id: "reports-overview", title: "Overview & insights",
                          text: "See weekly progress across calories, workouts, sleep, and AI-driven deep dives.")
    ]

    var body: some View {
        SpotlightTourScaffold(steps: ReportsView.reportsTourSteps) { isActive in
        VStack(spacing: 0) {
            AppScreenHeader(
                title: "Reports",
                subtitle: "Your week, trends, and underlying data."
            )
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.compact)
            .accessibilityIdentifier("reports_screen_header")

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    weekInMotionSection

                    // DESIGN.md rule 1: Reports answers "is it working?" — the timeframe picker
                    // is chrome and leads (it scopes everything below, including the overview);
                    // the headline trend is the hero, directly under it.
                    timeframeSelectorAndPickers

                    TrendDashboardView(
                        weightHistory: goalSettings.weightHistory,
                        dateRange: selectedTrendRange,
                        title: selectedTrendTitle
                    )
                    .featureSpotlight(isActive: isActive("reports-trend"))

                    ReportsOverviewCard(
                        selectedTimeframe: selectedTimeframe,
                        customStartDate: customStartDate,
                        customEndDate: customEndDate,
                        summary: viewModel.summary,
                        wellnessScore: viewModel.wellnessScore,
                        workoutReport: viewModel.weeklyWorkoutReport,
                        sleepReport: viewModel.enhancedSleepReport,
                        onOpenInsights: {
                            insightsService.generateAndFetchInsights(forLastDays: 7, requestConsentIfNeeded: true)
                            showingDetailedInsights = true
                        }
                    )
                    .featureSpotlight(isActive: isActive("reports-overview"))

                    if let insight = insightsService.smartSuggestion {
                        SmartReportInsightCard(insight: insight)
                    }

                    if goalSettings.gender.lowercased() == "female" {
                        CycleTrackingCard()
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
        .task { await loadWeekInMotion() }
        .onChange(of: selectedTimeframe) { _, newValue in
            if newValue != .custom {
                fetchDataForCurrentSelection()
            }
        }
        .onChange(of: customStartDate) { _, _ in
            if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: customEndDate) { _, _ in
             if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: healthKitViewModel.sleepSamples) { _, newSamples in
            viewModel.processAndScoreSleepData(samples: newSamples)
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
                .animation(.easeOut(duration: 0.18), value: weeklyRecapLoader.recap != nil)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Week in Motion is unavailable")
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

    @ViewBuilder
    private var contentStateView: some View {
        if viewModel.isLoading {
            ReportsLoadingState()
        } else if let errorMessage = viewModel.errorMessage {
            ReportsMessageState(
                icon: "exclamationmark.triangle.fill",
                title: "Reports need attention",
                message: errorMessage,
                color: .orange
            )
        } else if hasReportContent {
            reportsContentSection
        } else {
            ReportsMessageState(
                icon: "chart.line.uptrend.xyaxis",
                title: "No report data yet",
                message: "Log meals, workouts, weight, or sleep for this timeframe and this tab will turn it into trends.",
                color: Color(UIColor.secondaryLabel)
            )
        }
    }

    @ViewBuilder
    private var reportsContentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            ReportSectionHeader(
                title: "Report cards",
                subtitle: "Tap a card to inspect the underlying trends."
            )

            if let wellnessScore = viewModel.wellnessScore {
                #if !TARGET_IS_WIDGET_EXTENSION
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: viewModel.mealScore,
                    sleepReport: viewModel.enhancedSleepReport
                )
                #else
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: nil,
                    sleepReport: nil
                )
                .onTapGesture {}
                #endif
            }

            ComprehensiveHealthCard(
                weeklySteps: healthKitViewModel.weeklySteps,
                weeklyActiveEnergy: healthKitViewModel.weeklyActiveEnergy,
                weeklyRestingHeartRate: healthKitViewModel.weeklyRestingHeartRate,
                weeklyHRV: healthKitViewModel.weeklyHRV
            )

            if let workoutReport = viewModel.weeklyWorkoutReport {
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: MetabolismDashboardView()) {
                    MetabolismReportCard()
                }
                .buttonStyle(AnimatedCardButtonStyle())

                NavigationLink(destination: WorkoutAnalyticsView(viewModel: viewModel)) {
                    WorkoutReportCard(report: workoutReport)
                }
                .buttonStyle(AnimatedCardButtonStyle())
                #else
                WorkoutReportCard(report: workoutReport)
                #endif
            }

            reportPair

        }
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

    // Compact filter chrome, not a card with its own headline — DESIGN.md rule 4.
    private var timeframeSelectorAndPickers: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Trend window",
                subtitle: "Choose the period used by the detailed charts below."
            )

            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(ReportTimeframe.allCases) { tf in Text(tf.rawValue).tag(tf) }
            }
            .pickerStyle(SegmentedPickerStyle())

            if selectedTimeframe == .custom {
                VStack(spacing: AppSpacing.row) {
                    customDateControls

                    Button("View custom report") { fetchDataForCurrentSelection() }
                        .buttonStyle(AppActionButtonStyle(.primary))
                }
                .appSurface(.quiet)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                .animation(AppMotion.standard, value: selectedTimeframe)
            }
        }
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
                    Text("Goal progress")
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
                    .stroke(progress >= 100 ? Color.accentPositive : Color.blue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: 105, height: 105)
                    .animation(.easeInOut, value: goalSettings.weight)
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

                // Cohesive warm-to-cool palette (replaces the clashing red/blue/green).
                let mealColors: [String: Color] = [
                    "Breakfast": .orange, "Lunch": .teal, "Dinner": .blue, "Snacks": .purple
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
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: processedData.map { $0.totalCalories })

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
