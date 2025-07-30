import SwiftUI
import Charts
import FirebaseAuth

enum ReportTimeframe: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case custom = "Custom Range"
    var id: String { self.rawValue }
}

struct ReportsView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    
    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEndDate: Date = Date()
    
    @State private var showingDetailedInsights = false

    init(dailyLogService: DailyLogService) {
        _viewModel = StateObject(wrappedValue: ReportsViewModel(dailyLogService: dailyLogService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                
                if viewModel.isLoading {
                    ProgressView("Loading Reports...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 50)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 50)
                } else if !viewModel.calorieTrend.isEmpty {
                     reportsContentSection
                } else {
                    VStack {
                        Spacer()
                        Text("No food or exercise logged in the selected period.")
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setup(goals: goalSettings)
            fetchDataForCurrentSelection()
            insightsService.generateDailySmartInsight()
            if healthKitViewModel.isAuthorized {
                viewModel.processSleepData(samples: healthKitViewModel.sleepSamples)
            }
        }
        .onChange(of: selectedTimeframe) { newValue in
            if newValue != .custom {
                fetchDataForCurrentSelection()
            }
        }
        .onChange(of: healthKitViewModel.sleepSamples) { newSamples in
            viewModel.processSleepData(samples: newSamples)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        if let insight = insightsService.smartSuggestion {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.brandPrimary)
                    Text(insight.title.lowercased() == "have a great day!" ? "Have a Great Day!" : insight.title)
                        .appFont(size: 17, weight: .semibold)
                }
                Text(insight.message)
                    .appFont(size: 15)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .asCard()
        }
        
        timeframeSelectorAndPickers
        
        VStack(spacing: 12) {
            insightsActionSection
            
            NavigationLink(destination: WeightTrackingView()) {
                Label("View Weight Tracking", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(SecondaryButtonStyle())
            
            NavigationLink(destination: CycleTrackingView()) {
                Label("View Cycle Tracking", systemImage: "timer.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
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
        
        NavigationLink(isActive: $showingDetailedInsights) {
            DetailedInsightsView(insightsService: insightsService)
        } label: { EmptyView() }
    }
    
    @ViewBuilder
    private var reportsContentSection: some View {
        VStack(spacing: 16) {
            summaryCard
            if let sleepReport = viewModel.weeklySleepReport {
                SleepReportCard(report: sleepReport)
            }
            if let workoutReport = viewModel.weeklyWorkoutReport {
                WorkoutReportCard(report: workoutReport)
            }
            calorieChartCard
            macroChartCard
            micronutrientReportCard
            mealDistributionCard
            citationSection
        }
    }

    private var timeframeSelectorAndPickers: some View {
        VStack {
            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(ReportTimeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if selectedTimeframe == .custom {
                VStack(spacing: 12) {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Start Date").gridColumnAlignment(.leading)
                            DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        GridRow {
                            Text("End Date").gridColumnAlignment(.leading)
                            DatePicker("End Date", selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    
                    Button("View Custom Report") {
                        fetchDataForCurrentSelection()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                .animation(.easeInOut(duration: 0.2), value: selectedTimeframe)
            }
        }
    }
    
    private var citationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source Information")
                .appFont(size: 17, weight: .semibold)
            Text("Calorie and micronutrient goals are based on established dietary guidelines, including the Mifflin-St Jeor equation and Dietary Reference Intakes (DRIs).")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
            if let url = URL(string: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator") {
                Link("Source: USDA Dietary Reference Intakes", destination: url)
                    .appFont(size: 12)
            }
        }
        .asCard()
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

    @ViewBuilder private var summaryCard: some View {
        if let summary = viewModel.summary {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(summary.timeframe) Averages")
                    .appFont(size: 17, weight: .semibold)
                Text("Based on \(summary.daysLogged) day(s) logged")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.bottom, 5)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    averageStatBox(value: summary.averageCalories, label: "Calories", unit: "cal", goal: goalSettings.calories)
                    averageStatBox(value: summary.averageProtein, label: "Protein", unit: "g", goal: goalSettings.protein)
                    averageStatBox(value: summary.averageCarbs, label: "Carbs", unit: "g", goal: goalSettings.carbs)
                    averageStatBox(value: summary.averageFats, label: "Fats", unit: "g", goal: goalSettings.fats)
                }
            }
            .asCard()
        }
    }

    @ViewBuilder private func averageStatBox(value: Double, label: String, unit: String, goal: Double?) -> some View {
       VStack(alignment: .leading) {
           Text(label).appFont(size: 12).foregroundColor(Color(UIColor.secondaryLabel))
           Text("\(value, specifier: "%.0f") \(unit)").appFont(size: 22, weight: .medium)
           if let g = goal, g > 0 {
               let pct = (value / g) * 100
               Text("Goal: \(g, specifier: "%.0f") (\(pct, specifier: "%.0f")%)").appFont(size: 10).foregroundColor(Color(UIColor.secondaryLabel))
           }
       }
       .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder private var calorieChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily Calorie Trend").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.calorieTrend.isEmpty {
                Chart(viewModel.calorieTrend) { dp in
                    LineMark(x: .value("Date", dp.date, unit: .day), y: .value("Calories", dp.value))
                        .foregroundStyle(Color.brandPrimary)
                        .interpolationMethod(.catmullRom)
                    if let goal = goalSettings.calories {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal: \(goal, specifier: "%.0f")")
                                    .appFont(size: 10).foregroundColor(Color(UIColor.secondaryLabel))
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day(), centered: false)
                    }
                }
                .chartYAxis { AxisMarks(preset: .aligned, position: .leading) }
                .chartYAxisLabel("Calories (cal)", position: .leading, alignment: .center, spacing: 10)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("Not enough data for trend.")
                    .foregroundColor(Color(UIColor.secondaryLabel)).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .asCard()
    }

    @ViewBuilder private var macroChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily Macro Trend (g)").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.proteinTrend.isEmpty || !viewModel.carbTrend.isEmpty || !viewModel.fatTrend.isEmpty {
                Chart {
                    RuleMark(y: .value("P Goal", goalSettings.protein)).foregroundStyle(Color.accentProtein.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("P Goal").appFont(size: 10).foregroundColor(Color.accentProtein.opacity(0.7)) }
                    RuleMark(y: .value("C Goal", goalSettings.carbs)).foregroundStyle(Color.accentCarbs.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("C Goal").appFont(size: 10).foregroundColor(Color.accentCarbs.opacity(0.7)) }
                    RuleMark(y: .value("F Goal", goalSettings.fats)).foregroundStyle(Color.accentFats.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("F Goal").appFont(size: 10).foregroundColor(Color.accentFats.opacity(0.7)) }
                    ForEach(viewModel.proteinTrend) {
                        LineMark(x: .value("Date", $0.date, unit: .day), y: .value("Protein", $0.value)).foregroundStyle(by: .value("Macro", "Protein"))
                        PointMark(x: .value("Date", $0.date, unit: .day), y: .value("Protein", $0.value)).foregroundStyle(by: .value("Macro", "Protein")).symbolSize(10)
                    }
                    ForEach(viewModel.carbTrend) {
                        LineMark(x: .value("Date", $0.date, unit: .day), y: .value("Carbs", $0.value)).foregroundStyle(by: .value("Macro", "Carbs"))
                        PointMark(x: .value("Date", $0.date, unit: .day), y: .value("Carbs", $0.value)).foregroundStyle(by: .value("Macro", "Carbs")).symbolSize(10)
                    }
                    ForEach(viewModel.fatTrend) {
                        LineMark(x: .value("Date", $0.date, unit: .day), y: .value("Fats", $0.value)).foregroundStyle(by: .value("Macro", "Fats"))
                        PointMark(x: .value("Date", $0.date, unit: .day), y: .value("Fats", $0.value)).foregroundStyle(by: .value("Macro", "Fats")).symbolSize(10)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day(), centered: false)
                    }
                }
                .chartYAxis { AxisMarks(preset: .aligned, position: .leading) }
                .chartYAxisLabel("Grams (g)", position: .leading, alignment: .center, spacing: 10)
                .chartForegroundStyleScale([ "Protein": Color.accentProtein, "Carbs": Color.accentCarbs, "Fats": Color.accentFats ])
                .chartLegend(position: .top, alignment: .center)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("Not enough data for trend.")
                    .foregroundColor(Color(UIColor.secondaryLabel)).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .asCard()
    }

    @ViewBuilder private var micronutrientReportCard: some View {
        VStack(alignment: .leading) {
            Text("Avg. Micronutrient Intake (% Goal)").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.micronutrientAverages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    ForEach(viewModel.micronutrientAverages) { micro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(micro.name).appFont(size: 12, weight: .bold)
                                Spacer()
                                Text("\(micro.percentageMet, specifier: "%.0f")%").appFont(size: 12, weight: .bold)
                            }
                            ProgressView(value: micro.progressViewValue).tint(micro.name == "Sodium" ? (micro.percentageMet >= 100 ? .red : .orange) : (micro.percentageMet >= 100 ? .accentPositive : .brandPrimary)).scaleEffect(x: 1, y: 1.5, anchor: .center)
                            Text("\(micro.averageValue, specifier: micro.unit == "mcg" ? "%.0f" : "%.1f") / \(micro.goalValue, specifier: "%.0f") \(micro.unit)").appFont(size: 10).foregroundColor(Color(UIColor.secondaryLabel)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if !viewModel.isLoading {
                Text("No micronutrient data available for this period.").foregroundColor(Color(UIColor.secondaryLabel)).padding()
            }
        }
        .asCard()
    }

    @ViewBuilder private var mealDistributionCard: some View {
        VStack(alignment: .leading) {
            Text("Avg. Calorie Distribution by Meal").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.mealDistributionData.isEmpty {
                let chartColors: [Color] = [.brandPrimary, .brandSecondary, .accentCarbs, .accentFats, .accentProtein]
                Chart(viewModel.mealDistributionData) { dp in
                    SectorMark(
                        angle: .value("Calories", dp.totalCalories),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Meal", dp.mealName))
                    .annotation(position: .overlay) {
                        Text("\(dp.totalCalories, specifier: "%.0f")")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.white)
                    }
                    .cornerRadius(5)
                }
                .chartForegroundStyleScale(domain: viewModel.mealDistributionData.map { $0.mealName }, range: chartColors)
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("No meal data available for calorie distribution.")
                    .foregroundColor(Color(UIColor.secondaryLabel)).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .asCard()
    }
}
