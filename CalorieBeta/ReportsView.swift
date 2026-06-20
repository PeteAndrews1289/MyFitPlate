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

                if let insight = insightsService.smartSuggestion {
                    SmartReportInsightCard(insight: insight)
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
                        message: "Log meals, workouts, weight, or sleep for this period and this tab will turn it into trends.",
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
            
            if let workoutReport = viewModel.weeklyWorkoutReport {
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: WorkoutAnalyticsView(viewModel: viewModel)) {
                    WorkoutReportCard(report: workoutReport)
                }
                .buttonStyle(.plain)
                #else
                WorkoutReportCard(report: workoutReport)
                #endif
            }
            
            HStack(spacing: 12) {
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: CalorieTrackingView(viewModel: viewModel)) {
                    mealDistributionCard
                }
                .buttonStyle(.plain)
                #else
                mealDistributionCard
                #endif
                
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: WeightTrackingView()) {
                    WeightCardReport
                }
                .buttonStyle(.plain)
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
                title: "Period",
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
                    .font(.system(size: 12, weight: .bold))
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
        VStack(alignment: .leading, spacing: 12) {
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .foregroundColor(.textPrimary)

            if !viewModel.mealDistributionData.isEmpty {
                let groupedMeals = Dictionary(grouping: viewModel.mealDistributionData, by: { $0.mealName })
                let orderedMealNames = ["Breakfast", "Lunch", "Dinner", "Snacks"]
                
                let processedData: [(meal: String, totalCalories: Double)] = orderedMealNames.compactMap { mealName in
                    let totalCals = groupedMeals[mealName]?.reduce(0) { $0 + $1.totalCalories } ?? 0
                    if totalCals > 0 {
                        return (mealName, totalCals)
                    } else {
                        return nil
                    }
                }
                
                let colorMapping: [String: Color] = [
                    "Breakfast": .red, "Lunch": .orange, "Dinner": .blue, "Snacks": .green
                ]
                
                Spacer()
                Chart(processedData, id: \.meal) { dp in
                    SectorMark(
                        angle: .value("Calories", dp.totalCalories),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(colorMapping[dp.meal, default: .gray])
                    .annotation(position: .overlay) {
                        VStack(spacing: 0) {
                            Text(dp.meal)
                                .appFont(size: 10, weight: .bold)
                            Text("\(dp.totalCalories, specifier: "%.0f") cal")
                                .appFont(size: 10, weight: .regular)
                        }
                        .foregroundColor(.white)
                    }
                }
                .chartLegend(.hidden)
                .frame(maxWidth: .infinity, maxHeight: 105)
                Spacer()
            } else if !viewModel.isLoading {
                Spacer()
                Text("No meal data available.")
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            }
        }
        .asCard()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }
}

private struct ReportsOverviewCard: View {
    let selectedTimeframe: ReportTimeframe
    let customStartDate: Date
    let customEndDate: Date
    let summary: ReportSummary?
    let wellnessScore: WellnessScore?
    let workoutReport: WorkoutReport?
    let sleepReport: EnhancedSleepReport?
    let onOpenInsights: () -> Void

    private var periodTitle: String {
        if selectedTimeframe == .custom {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
        return selectedTimeframe.rawValue
    }

    private var overviewMessage: String {
        if let wellnessScore {
            return wellnessScore.summary
        }
        if let summary, summary.daysLogged > 0 {
            return "\(summary.daysLogged) logged \(summary.daysLogged == 1 ? "day" : "days") in this period."
        }
        if workoutReport != nil || sleepReport != nil {
            return "Activity or sleep data is available for this period."
        }
        return "Start logging to build a useful report."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Report")
                        .appFont(size: 25, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(periodTitle)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.brandPrimary)

                    Text(overviewMessage)
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onOpenInsights) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.brandPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.brandPrimary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Generate detailed insights")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ReportMetricTile(
                    title: "Wellness",
                    value: wellnessScore.map { "\($0.overallScore)" } ?? "--",
                    subtitle: "overall score",
                    icon: "heart.fill",
                    color: wellnessScore?.color ?? .brandPrimary
                )

                ReportMetricTile(
                    title: "Avg Calories",
                    value: summary.map { "\(Int($0.averageCalories.rounded()))" } ?? "--",
                    subtitle: "per logged day",
                    icon: "flame.fill",
                    color: .orange
                )

                ReportMetricTile(
                    title: "Workouts",
                    value: workoutReport.map { "\($0.totalWorkouts)" } ?? "--",
                    subtitle: "sessions",
                    icon: "figure.run",
                    color: .blue
                )

                ReportMetricTile(
                    title: "Sleep",
                    value: sleepReport.map { "\($0.averageSleepScore)" } ?? "--",
                    subtitle: "avg score",
                    icon: "bed.double.fill",
                    color: .purple
                )
            }
        }
        .asCard()
    }
}

private struct ReportMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())
                Spacer()
            }

            Text(value)
                .appFont(size: 23, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SmartReportInsightCard: View {
    let insight: UserInsight

    private var title: String {
        insight.title.lowercased() == "have a great day!" ? "Have a Great Day!" : insight.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.brandPrimary)
                .frame(width: 38, height: 38)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)

                Text(insight.message)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .asCard()
    }
}

private struct ReportsLoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.brandPrimary)
            Text("Building your report")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.textPrimary)
            Text("Pulling nutrition, activity, sleep, and weight trends into one view.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .asCard()
    }
}

private struct ReportsMessageState: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 62, height: 62)
                .background(color.opacity(0.12), in: Circle())

            Text(title)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)

            Text(message)
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .asCard()
    }
}

private struct ReportSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
