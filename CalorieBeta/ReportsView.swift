import SwiftUI
import Charts
import FirebaseAuth

// Main view for displaying reports and insights.
struct ReportsView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel

    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEndDate: Date = Date()
    
    @State private var showingDetailedInsights = false

    // Formatter for displaying numbers.
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        return formatter
    }

    // This is the "live" init. It's correct.
    init(dailyLogService: DailyLogService) {
        _viewModel = StateObject(wrappedValue: ReportsViewModel(dailyLogService: dailyLogService))
    }
    
    // Helper function to fetch data based on the selected timeframe.
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
            VStack(alignment: .leading, spacing: 16) {
                // Header section with timeframe picker and smart suggestion
                headerSection

                // Display loading, error, content, or no data message
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
                } else if viewModel.summary != nil || viewModel.enhancedSleepReport != nil || viewModel.weeklyWorkoutReport != nil || viewModel.wellnessScore != nil {
                     // The main content section with all the report cards
                     reportsContentSection
                } else {
                    // Message when no data is available for the period
                    VStack {
                        Spacer()
                        Text("No data available for the selected period.")
                            .foregroundColor(.secondary)
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
        // This onAppear/onChange logic is from your "live" version and is correct.
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
        .onChange(of: selectedTimeframe) { newValue in
            if newValue != .custom {
                fetchDataForCurrentSelection()
            }
        }
        .onChange(of: customStartDate) { _ in
            if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: customEndDate) { _ in
             if selectedTimeframe == .custom { fetchDataForCurrentSelection() }
        }
        .onChange(of: healthKitViewModel.sleepSamples) { newSamples in
            // This correctly calls the full sleep processing logic in your "live" VM
            viewModel.processAndScoreSleepData(samples: newSamples)
        }
    }

    // Header section containing smart insight and timeframe controls.
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
    }

    // Button to generate and navigate to detailed weekly insights.
    @ViewBuilder
    private var insightsActionSection: some View {
        Button {
            insightsService.generateAndFetchInsights(forLastDays: 7)
            showingDetailedInsights = true
        } label: {
            Label("Generate Weekly Insights", systemImage: "wand.and.stars")
        }
        .buttonStyle(PrimaryButtonStyle())
        
        // This NavigationLink must be wrapped to avoid compiling for the widget
        #if !TARGET_IS_WIDGET_EXTENSION
        NavigationLink(isActive: $showingDetailedInsights) {
            DetailedInsightsView(insightsService: insightsService)
        } label: { EmptyView() }
        #endif
    }
    
    // This section now matches the intern's new screenshot layout.
    @ViewBuilder
    private var reportsContentSection: some View {
        VStack(spacing: 12) {
            // Full-width Wellness Score card
            if let wellnessScore = viewModel.wellnessScore {
                // Pass the meal and sleep data to the card, so it can pass it to its sheet
                #if !TARGET_IS_WIDGET_EXTENSION
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: viewModel.mealScore,
                    sleepReport: viewModel.enhancedSleepReport
                )
                #else
                // The widget target just shows the card, no data passing needed
                WellnessScoreCardView(
                    wellnessScore: wellnessScore,
                    mealScore: nil,
                    sleepReport: nil
                )
                .onTapGesture {}
                #endif
            }
            
            // Full-width Workout Summary card (links to WorkoutAnalyticsView)
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
            
            // Two-column layout for Calorie and Weight reports
            HStack(spacing: 12){
                // Left card: Calorie Report
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: CalorieTrackingView(viewModel: viewModel)) {
                    mealDistributionCard
                }
                .buttonStyle(.plain)
                #else
                mealDistributionCard
                #endif
                
                // Right card: Weight Report
                #if !TARGET_IS_WIDGET_EXTENSION
                NavigationLink(destination: WeightTrackingView()){
                    WeightCardReport
                }
                .buttonStyle(.plain)
                #else
                WeightCardReport
                #endif
            }
            
            // "Generate Insights" button at the bottom
            #if !TARGET_IS_WIDGET_EXTENSION
            insightsActionSection
                .padding(.top, 8)
            #endif
        }
    }

    // Segmented control for timeframe and conditional date pickers.
    private var timeframeSelectorAndPickers: some View {
        VStack {
            Picker("Timeframe", selection: $selectedTimeframe) {
                ForEach(ReportTimeframe.allCases) { tf in Text(tf.rawValue).tag(tf) }
            }
            .pickerStyle(SegmentedPickerStyle())

            if selectedTimeframe == .custom {
                VStack(spacing: 12) {
                    Grid(alignment: .leading) {
                        GridRow { Text("Start Date").gridColumnAlignment(.leading); DatePicker("Start Date", selection: $customStartDate, in: ...customEndDate, displayedComponents: .date).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing) }
                        GridRow { Text("End Date").gridColumnAlignment(.leading); DatePicker("End Date", selection: $customEndDate, in: customStartDate..., displayedComponents: .date).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing) }
                    }
                    Button("View Custom Report") { fetchDataForCurrentSelection() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity), removal: .opacity))
                .animation(.easeInOut(duration: 0.2), value: selectedTimeframe)
            }
        }
    }
    
    // This is the Weight Report card, now color-corrected.
    private var WeightCardReport: some View {
        VStack(alignment: .center, spacing: 5){
            HStack{
                Text("Weight Report")
                    .appFont(size: 16, weight: .semibold)
                Spacer()
                Image(systemName:"ellipsis")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            Spacer()
            
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
                        .font(.title2.bold())
                    Text("Progress")
                        .font(.caption)
                }
            }
            Spacer()
        }
        .foregroundColor(.textPrimary) // Use dynamic text color
        .asCard()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }

    // This is the Calorie Report card, now color-corrected and with better labels.
    @ViewBuilder private var mealDistributionCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack{
                Text("Calorie Report")
                    .appFont(size: 16, weight: .semibold)
                Spacer()
                Image(systemName:"ellipsis")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .foregroundColor(.textPrimary) // Use dynamic text color

            if !viewModel.mealDistributionData.isEmpty {
                let groupedMeals = Dictionary(grouping: viewModel.mealDistributionData, by: { $0.mealName })
                let orderedMealNames = ["Breakfast", "Lunch", "Dinner", "Snacks"]
                
                let processedData: [(meal: String, totalCalories: Double)] = orderedMealNames.compactMap { mealName in
                    // Use flatMap to get all calories for a meal type and sum them
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
                            Text(dp.meal) // "Breakfast", "Lunch", etc.
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
                    .foregroundColor(.textPrimary) // Use dynamic text color
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            }
        }
        .asCard()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 180)
    }
}
