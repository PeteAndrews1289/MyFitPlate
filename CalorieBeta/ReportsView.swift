import SwiftUI
import Charts
import FirebaseAuth

struct ReportsView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel

    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()

    @State private var showingDetailedInsights = false

    init(dailyLogService: DailyLogService) {
        _viewModel = StateObject(wrappedValue: ReportsViewModel(dailyLogService: dailyLogService))
    }

    private var hasReportContent: Bool {
        viewModel.summary != nil ||
        viewModel.enhancedSleepReport != nil ||
        viewModel.weeklyWorkoutReport != nil ||
        viewModel.wellnessScore != nil
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ReportsOverviewCard(
                    selectedTimeframe: selectedTimeframe,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate,
                    summary: viewModel.summary,
                    wellnessScore: viewModel.wellnessScore,
                    workoutReport: viewModel.weeklyWorkoutReport,
                    sleepReport: viewModel.enhancedSleepReport,
                    onOpenInsights: {
                        insightsService.generateAndFetchInsights(forLastDays: 7)
                        showingDetailedInsights = true
                    }
                )

                TrendDashboardView(weightHistory: goalSettings.weightHistory)

                if let insight = insightsService.smartSuggestion {
                    SmartReportInsightCard(insight: insight)
                }

                if goalSettings.gender.lowercased() == "female" {
                    CycleTrackingCard()
                }

                timeframeSelectorAndPickers

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
                        color: .brandPrimary
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setup(goals: goalSettings, healthKitViewModel: healthKitViewModel)
            fetchDataForCurrentSelection()
            insightsService.generateDailySmartInsight()
            if let userID = Auth.auth().currentUser?.uid {
                viewModel.fetchMealScoreHistory(for: userID)
            }
            if healthKitViewModel.isAuthorized {
                 healthKitViewModel.fetchLastSevenDaysSleep()
            }
        }
        .onChange(of: selectedTimeframe) { _, newValue in
            if newValue != .custom {
                fetchDataForCurrentSelection()
            }
        }
        .onChange(of: customStartDate) {
            if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: customEndDate) {
             if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: healthKitViewModel.sleepSamples) { _, newSamples in
            viewModel.processAndScoreSleepData(samples: newSamples)
        }
    }

    @ViewBuilder
    private var insightsActionSection: some View {
        Button {
            insightsService.generateAndFetchInsights(forLastDays: 7)
            showingDetailedInsights = true
        } label: {
            Label("Generate Weekly Insights", systemImage: "wand.and.stars")
        }
        .buttonStyle(PrimaryButtonStyle())
        #if !TARGET_IS_WIDGET_EXTENSION
        .navigationDestination(isPresented: $showingDetailedInsights) {
            DetailedInsightsView(insightsService: insightsService)
        }
        #endif
    }

    @ViewBuilder
    private var reportsContentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReportSectionHeader(
                title: "Report Cards",
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

            HStack(spacing: 12) {
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: CalorieTrackingView(viewModel: viewModel)) {
                    mealDistributionCard
                }
                .buttonStyle(AnimatedCardButtonStyle())
                #else
                mealDistributionCard
                #endif

                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: WeightTrackingView()) {
                    WeightCardReport
                }
                .buttonStyle(AnimatedCardButtonStyle())
                #else
                WeightCardReport
                #endif
            }

            #if !TARGET_IS_WIDGET_EXTENSION
            insightsActionSection
                .padding(.top, 8)
            #endif
        }
    }

    private var timeframeSelectorAndPickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportSectionHeader(
                title: "Timeframe",
                subtitle: "Choose the window for every card below."
            )

            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(ReportTimeframe.allCases) { tf in Text(tf.rawValue).tag(tf) }
            }
            .pickerStyle(SegmentedPickerStyle())

            if selectedTimeframe == .custom {
                VStack(spacing: 12) {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Start")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .gridColumnAlignment(.leading)
                            DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        GridRow {
                            Text("End")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .gridColumnAlignment(.leading)
                            DatePicker("End Date", selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    Button("View Custom Report") { fetchDataForCurrentSelection() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                .animation(.easeInOut(duration: 0.2), value: selectedTimeframe)
            }
        }
        .asCard()
    }

    private var WeightCardReport: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                        .appFont(size: 16, weight: .bold)
                    Text("Goal progress")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }

            ZStack {
                Circle()
                    .trim(from: 0, to: 5/6)
                    .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: 105, height: 105)
                Circle()
                    .trim(from: 0, to: (goalSettings.calculateWeightProgress().map { $0 / 100.0 } ?? 0.0) * 5/6)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(120))
                    .frame(width: 105, height: 105)
                    .animation(.easeInOut, value: goalSettings.weight)
                VStack {
                    Text("\(Int(goalSettings.calculateWeightProgress() ?? 0))%")
                        .appFont(size: 24, weight: .bold)
                    Text("Progress")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
        }
        .foregroundColor(.textPrimary)
        .asCard()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }

    @ViewBuilder private var mealDistributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calories")
                        .appFont(size: 16, weight: .bold)
                    Text("By meal")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
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
                        Text("\(Int(totalCalories))")
                            .appFont(size: 22, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text("kcal")
                            .appFont(size: 10, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
                    ForEach(processedData, id: \.meal) { dp in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(mealColors[dp.meal, default: .gray])
                                .frame(width: 8, height: 8)
                            Text(dp.meal)
                                .appFont(size: 11, weight: .medium)
                                .foregroundColor(Color(UIColor.secondaryLabel))
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
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Text("Log a meal to see your daily split.")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .asCard()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }
}
