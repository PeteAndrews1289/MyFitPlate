import SwiftUI
import FirebaseAuth

struct WeightTrackingView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var showingWeightEntrySheet = false
    @State private var showingTargetWeightSheet = false
    @State private var targetWeightInput: String = ""
    @State private var showingCaloricCalculatorSheet = false

    @State private var selectedChartTimeframe: WeightChartTimeframe = .month
    
    @State private var showingChartDeleteAlert = false
    @State private var chartEntryToDeleteID: String? = nil
    @State private var chartEntryToDeleteDetails: String = ""

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var currentProgress: Double {
        goalSettings.calculateWeightProgress().map { $0 / 100.0 } ?? 0.0
    }
    
    private var initialWeightForCurrentGoalPeriod: Double? {
        goalSettings.weightHistory.first?.weight ?? goalSettings.weight
    }
    
    private var totalLossOrGain: Double? {
        guard let initial = initialWeightForCurrentGoalPeriod else { return nil }
        return goalSettings.weight - initial
    }

    private var weightRemaining: Double? {
        guard let target = goalSettings.targetWeight else { return nil }
        return goalSettings.weight - target
    }

    var filteredDataForLineChart: [(id: String, date: Date, weight: Double)] {
        let now = Date()
        let allHistory = goalSettings.weightHistory.sorted { $0.date < $1.date }
        
        guard !allHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        var startDate: Date?

        switch selectedChartTimeframe {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: calendar.startOfDay(for: now))
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now))
        case .allTime:
            return allHistory
        }
        
        if let start = startDate {
            return allHistory.filter { $0.date >= start }
        }
        return allHistory
    }
    
    private var chartStats: (trend: Double?, highest: Double?, lowest: Double?, dailyRate: Double?) {
        goalSettings.getWeightStats(for: filteredDataForLineChart)
    }
    
    private let alertItemFormatter: DateFormatter = {
         let formatter = DateFormatter()
         formatter.dateStyle = .short
         formatter.timeStyle = .short
         return formatter
     }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Weight Tracking")
                    .appFont(size: 22, weight: .bold)
                    .padding(.top, 15)
                
                CircularWeightDisplayView(
                    currentWeight: goalSettings.weight,
                    lastUpdateDate: goalSettings.weightHistory.last?.date ?? Date(),
                    progress: currentProgress,
                    goalWeight: goalSettings.targetWeight,
                    initialWeightForGoal: initialWeightForCurrentGoalPeriod
                )
                .environmentObject(goalSettings)

                if let target = goalSettings.targetWeight, let initial = initialWeightForCurrentGoalPeriod {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Weight Goal")
                                .appFont(size: 17, weight: .semibold)
                            Spacer()
                            Button("Edit") {
                                targetWeightInput = numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: target, metric: useMetric))) ?? ""
                                showingTargetWeightSheet = true
                            }
                            .tint(.brandPrimary)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.brandPrimary.opacity(0.14))
                                Capsule().fill(Color.brandPrimary)
                                    .frame(width: max(8, geo.size.width * CGFloat(min(max(currentProgress, 0), 1))))
                            }
                        }
                        .frame(height: 10)
                        
                        HStack {
                            Text("Initial: \(numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: initial, metric: useMetric))) ?? "") \(BodyUnits.weightUnit(metric: useMetric))")
                            Spacer()
                            Text("Goal: \(numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: target, metric: useMetric))) ?? "") \(BodyUnits.weightUnit(metric: useMetric))")
                        }
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        
                        Divider()
                        
                        HStack(spacing: 15) {
                             StatBox(value: totalLossOrGain.map { String(format: "%+.1f \(BodyUnits.weightUnit(metric: useMetric))", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)) } ?? "N/A", label: "Total Change")
                             StatBox(value: goalSettings.calculateWeightProgress().map { String(format: "%.0f%%", $0) } ?? "N/A", label: "Progress")
                             StatBox(value: weightRemaining.map { String(format: "%.1f \(BodyUnits.weightUnit(metric: useMetric))", abs(BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric))) } ?? "N/A", label: "To Go")
                        }
                    }
                    .asCard()
                } else {
                    Button("Set Target Weight & Goals") {
                        targetWeightInput = numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric))) ?? ""
                        showingCaloricCalculatorSheet = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                Button(action: { showingWeightEntrySheet = true }) {
                    Label("Log Current Weight", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                if let initialWt = initialWeightForCurrentGoalPeriod,
                   let targetWt = goalSettings.targetWeight,
                   abs(initialWt - targetWt) > 0.01 {
                    MilestoneView(
                        initialWeight: initialWt,
                        currentWeight: goalSettings.weight,
                        targetWeight: targetWt
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Weight History (\(selectedChartTimeframe.displayName))")
                        .appFont(size: 17, weight: .semibold)
                        .padding(.horizontal)
                    
                    Picker("Timeframe", selection: $selectedChartTimeframe.animation()) {
                        ForEach(WeightChartTimeframe.allCases) { timeframe in
                            Text(timeframe.rawValue).tag(timeframe)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    if !filteredDataForLineChart.isEmpty {
                        WeightChartView(
                            weightHistory: filteredDataForLineChart,
                            currentWeight: goalSettings.weight,
                            onEntrySelected: { entryId in
                                 if let entry = goalSettings.weightHistory.first(where: { $0.id == entryId }) {
                                     self.chartEntryToDeleteID = entryId
                                     let weightString = numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: entry.weight, metric: useMetric))) ?? ""
                                     let dateString = alertItemFormatter.string(from: entry.date)
                                     self.chartEntryToDeleteDetails = "\(weightString) \(BodyUnits.weightUnit(metric: useMetric)) on \(dateString)"
                                     self.showingChartDeleteAlert = true
                                 }
                             }
                        )
                        .frame(height: 250)
                        .padding(.top, 5)
                    } else {
                        Text("No weight data for this period.")
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(height: 250, alignment: .center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(15)
                
                VStack(alignment: .leading, spacing: 10) {
                     Text("Period Stats")
                        .appFont(size: 17, weight: .semibold)
                        .padding(.horizontal)

                    Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                        GridRow {
                            SmallStatCard(title: "Daily Rate", value: chartStats.dailyRate.map { String(format: "%+.2f \(BodyUnits.weightUnit(metric: useMetric))/day", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)) } ?? "N/A", iconName: chartStats.dailyRate.map { $0 == 0 ? "arrow.left.arrow.right" : ($0 < 0 ? "arrow.down.right" : "arrow.up.right") } ?? "scalemass", iconColor: chartStats.dailyRate.map { $0 == 0 ? .gray : ($0 < 0 ? .accentPositive : .red) } ?? .gray)
                            SmallStatCard(title: "Trend", value: chartStats.trend.map { String(format: "%+.1f \(BodyUnits.weightUnit(metric: useMetric))", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)) } ?? "N/A", iconName: chartStats.trend.map { $0 == 0 ? "arrow.left.arrow.right" : ($0 < 0 ? "arrow.down.right" : "arrow.up.right") } ?? "chart.line.uptrend.xyaxis", iconColor: chartStats.trend.map { $0 == 0 ? .gray : ($0 < 0 ? .accentPositive : .red) } ?? .gray)
                        }
                        GridRow {
                            SmallStatCard(title: "Highest", value: chartStats.highest.map { (numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric))) ?? "") + " \(BodyUnits.weightUnit(metric: useMetric))" } ?? "N/A", iconName: "arrow.up.to.line", iconColor: .orange)
                            SmallStatCard(title: "Lowest", value: chartStats.lowest.map { (numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric))) ?? "") + " \(BodyUnits.weightUnit(metric: useMetric))" } ?? "N/A", iconName: "arrow.down.to.line", iconColor: .accentPositive)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color.backgroundSecondary)
                .cornerRadius(15)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showingWeightEntrySheet) {
            CurrentWeightView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingTargetWeightSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Set Target Weight")) {
                        TextField("Target weight (\(BodyUnits.weightUnit(metric: useMetric)))", text: $targetWeightInput)
                            .keyboardType(.decimalPad)
                    }
                    Button("Save Target") {
                        if let targetValue = Double(targetWeightInput), targetValue > 0 {
                            goalSettings.targetWeight = BodyUnits.weightToLbs(targetValue, metric: useMetric)
                            if let userID = Auth.auth().currentUser?.uid {
                                goalSettings.saveUserGoals(userID: userID)
                            }
                        }
                        showingTargetWeightSheet = false
                    }
                    .disabled(Double(targetWeightInput) == nil || (Double(targetWeightInput) ?? 0) <= 0)
                }
                .navigationTitle("Set Target")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingTargetWeightSheet = false }
                    }
                }
            }
            .tint(.brandPrimary)
        }
        .sheet(isPresented: $showingCaloricCalculatorSheet) {
            CaloricCalculatorView()
                .environmentObject(goalSettings)
        }
        .alert("Delete Weight Entry?", isPresented: $showingChartDeleteAlert) {
             Button("Delete", role: .destructive) {
                 if let idToDelete = chartEntryToDeleteID {
                     confirmDeleteChartEntry(entryID: idToDelete)
                 }
             }
             Button("Cancel", role: .cancel) {
                 chartEntryToDeleteID = nil
             }
         } message: {
             Text("Are you sure you want to delete the entry: \(chartEntryToDeleteDetails)?")
         }
        .onAppear {
            goalSettings.loadWeightHistory()
            if let target = goalSettings.targetWeight {
                targetWeightInput = numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: target, metric: useMetric))) ?? ""
            } else {
                 targetWeightInput = numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric))) ?? ""
            }
        }
    }
    
    private func confirmDeleteChartEntry(entryID: String) {
        goalSettings.deleteWeightEntry(entryID: entryID) { error in
            if let error {
                AppLog.app.error("Failed to delete weight entry: \(error.localizedDescription, privacy: .public)")
                
            } else {
                
            }
        }
        chartEntryToDeleteID = nil
    }
}

struct StatBox: View {
    var value: String
    var label: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SmallStatCard: View {
    var title: String
    var value: String
    var iconName: String
    var iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.footnote.weight(.medium))
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
