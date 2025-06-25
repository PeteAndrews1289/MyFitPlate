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
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEndDate: Date = Date()
    
    @State private var showingDetailedInsights = false

    init(dailyLogService: DailyLogService) {
        _viewModel = StateObject(wrappedValue: ReportsViewModel(dailyLogService: dailyLogService))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // The body is now much simpler, composed of logical sections.
                headerSection
                insightsActionSection
                reportsContentSection
                Spacer()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

    // MARK: - View Sections

    /// Section for the smart insight and timeframe pickers.
    @ViewBuilder
    private var headerSection: some View {
        if let insight = insightsService.smartSuggestion {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text(insight.title)
                        .font(.headline)
                }
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(15)
            .shadow(radius: 1)
        }
        
        timeframeSelectorAndPickers
    }

    /// Section for the "Generate Insights" button and its NavigationLink.
    @ViewBuilder
    private var insightsActionSection: some View {
        Button {
            insightsService.generateAndFetchInsights(forLastDays: 7)
            showingDetailedInsights = true
        } label: {
            Label("Generate Weekly Insights", systemImage: "sparkles.square.filled.on.square")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .padding(.vertical)
        
        NavigationLink(isActive: $showingDetailedInsights) {
            DetailedInsightsView(insightsService: insightsService)
        } label: { EmptyView() }
    }
    
    /// Section that conditionally displays loading, error, or the main report content.
    @ViewBuilder
    private var reportsContentSection: some View {
        if viewModel.isLoading {
            ProgressView("Loading Reports...")
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            // This block, which contains all the cards, is now cleanly separated.
            VStack(spacing: 20) {
                summaryCard
                if let sleepReport = viewModel.weeklySleepReport {
                    SleepReportCard(report: sleepReport)
                }
                calorieChartCard
                macroChartCard
                micronutrientReportCard
                mealDistributionCard
                citationSection
            }
        }
    }

    // MARK: - Subviews & Helper Functions

    private var timeframeSelectorAndPickers: some View {
        VStack {
            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(ReportTimeframe.allCases) { tf in
                    Text(tf.rawValue).tag(tf)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.bottom, selectedTimeframe == .custom ? 0 : 10)

            if selectedTimeframe == .custom {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                    Button("View Custom Report") {
                        fetchDataForCurrentSelection()
                    }
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                .animation(.easeInOut(duration: 0.2), value: selectedTimeframe)
            }
        }
    }
    
    private var citationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source Information")
                .font(.headline)
            Text("Calorie and micronutrient goals are based on established dietary guidelines, including the Mifflin-St Jeor equation and Dietary Reference Intakes (DRIs).")
                .font(.caption)
                .foregroundColor(.secondary)
            if let url = URL(string: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator") {
                Link("Source: USDA Dietary Reference Intakes", destination: url)
                    .font(.caption)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(15)
        .shadow(radius: 1)
    }
    
    private func fetchDataForCurrentSelection() {
        if selectedTimeframe == .custom {
            if customEndDate < customStartDate {
                viewModel.errorMessage = "End date cannot be before start date."
                viewModel.isLoading = false
                viewModel.summary = nil; viewModel.calorieTrend = []; viewModel.proteinTrend = []
                viewModel.carbTrend = []; viewModel.fatTrend = []; viewModel.micronutrientAverages = []
                viewModel.mealDistributionData = []
                return
            }
            viewModel.fetchData(for: .custom, startDate: customStartDate, endDate: customEndDate)
        } else {
            viewModel.fetchData(for: selectedTimeframe)
        }
    }

    @ViewBuilder private var summaryCard: some View {
        if let summary = viewModel.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(summary.timeframe) Averages").font(.headline)
                Text("Based on \(summary.daysLogged) day(s) logged").font(.caption).foregroundColor(.gray).padding(.bottom, 5)
                HStack {
                    averageStatBox(value: summary.averageCalories, label: "Calories", unit: "cal", goal: goalSettings.calories)
                    averageStatBox(value: summary.averageProtein, label: "Protein", unit: "g", goal: goalSettings.protein)
                }
                HStack {
                    averageStatBox(value: summary.averageCarbs, label: "Carbs", unit: "g", goal: goalSettings.carbs)
                    averageStatBox(value: summary.averageFats, label: "Fats", unit: "g", goal: goalSettings.fats)
                }
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(15)
            .shadow(radius: 1)
        }
    }

    @ViewBuilder private func averageStatBox(value: Double, label: String, unit: String, goal: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundColor(.gray)
            Text("\(value, specifier: "%.0f") \(unit)").font(.title3).fontWeight(.medium)
            if let g = goal, g > 0 {
                let pct = (value / g) * 100
                Text("Goal: \(g, specifier: "%.0f") (\(pct, specifier: "%.0f")%)").font(.caption2).foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder private var calorieChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily Calorie Trend").font(.headline).padding(.bottom, 5)
            if !viewModel.calorieTrend.isEmpty {
                Chart(viewModel.calorieTrend) { dp in
                    LineMark(x: .value("Date", dp.date, unit: .day), y: .value("Calories", dp.value))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                    if let goal = goalSettings.calories {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(.gray)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal: \(goal, specifier: "%.0f")")
                                    .font(.caption2).foregroundColor(.gray)
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
                    .foregroundColor(.gray).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .padding().background(cardBackground).cornerRadius(15).shadow(radius: 1)
    }

    @ViewBuilder private var macroChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily Macro Trend (g)").font(.headline).padding(.bottom, 5)
            if !viewModel.proteinTrend.isEmpty || !viewModel.carbTrend.isEmpty || !viewModel.fatTrend.isEmpty {
                Chart {
                    RuleMark(y: .value("P Goal", goalSettings.protein)).foregroundStyle(.blue.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("P Goal").font(.caption2).foregroundColor(.blue.opacity(0.7)) }
                    RuleMark(y: .value("C Goal", goalSettings.carbs)).foregroundStyle(.orange.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("C Goal").font(.caption2).foregroundColor(.orange.opacity(0.7)) }
                    RuleMark(y: .value("F Goal", goalSettings.fats)).foregroundStyle(.green.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("F Goal").font(.caption2).foregroundColor(.green.opacity(0.7)) }
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
                .chartForegroundStyleScale([ "Protein": Color.blue, "Carbs": Color.orange, "Fats": Color.green ])
                .chartLegend(position: .top, alignment: .center)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("Not enough data for trend.")
                    .foregroundColor(.gray).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .padding().background(cardBackground).cornerRadius(15).shadow(radius: 1)
    }

    @ViewBuilder private var micronutrientReportCard: some View {
        VStack(alignment: .leading) {
            Text("Avg. Micronutrient Intake (% Goal)").font(.headline).padding(.bottom, 5)
            if !viewModel.micronutrientAverages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    ForEach(viewModel.micronutrientAverages) { micro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(micro.name).font(.caption).bold(); Spacer(); Text("\(micro.percentageMet, specifier: "%.0f")%").font(.caption).bold()
                            }
                            ProgressView(value: micro.progressViewValue).tint(micro.name == "Sodium" ? (micro.percentageMet >= 100 ? .red : .orange) : (micro.percentageMet >= 100 ? .green : .accentColor)).scaleEffect(x: 1, y: 1.5, anchor: .center)
                            Text("\(micro.averageValue, specifier: micro.unit == "mcg" ? "%.0f" : "%.1f") / \(micro.goalValue, specifier: "%.0f") \(micro.unit)").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if !viewModel.isLoading {
                Text("No micronutrient data available for this period.").foregroundColor(.gray).padding()
            }
        }
        .padding().background(cardBackground).cornerRadius(15).shadow(radius: 1)
    }

    @ViewBuilder private var mealDistributionCard: some View {
        VStack(alignment: .leading) {
            Text("Avg. Calorie Distribution by Meal").font(.headline).padding(.bottom, 5)
            if !viewModel.mealDistributionData.isEmpty {
                Chart(viewModel.mealDistributionData) { dp in
                    SectorMark(
                        angle: .value("Calories", dp.totalCalories),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Meal", dp.mealName))
                    .annotation(position: .overlay) {
                        Text("\(dp.totalCalories, specifier: "%.0f")")
                            .font(.caption).bold()
                            .foregroundStyle(.white).blendMode(.difference)
                    }
                    .cornerRadius(5)
                }
                .chartLegend(position: .bottom, alignment: .center)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("No meal data available for calorie distribution.")
                    .foregroundColor(.gray).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .padding().background(cardBackground).cornerRadius(15).shadow(radius: 1)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white
    }
}
