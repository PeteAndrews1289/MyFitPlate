import SwiftUI

// DESIGN.md rule 1: this screen answers "is my weight moving the right way?" — the hero is
// the current weight + trend chart. "Log weight" is the single filled CTA. The goal card,
// milestones, and period stats are supporting cast in neutral cards.
struct WeightTrackingView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var showingWeightEntrySheet = false
    @State private var showingTargetWeightSheet = false
    @State private var targetWeightInput: String = ""
    @State private var showingCaloricCalculatorSheet = false

    @State private var selectedChartTimeframe: WeightChartTimeframe = .month

    @State private var showingChartDeleteAlert = false
    @State private var chartEntryToDeleteID: String?
    @State private var chartEntryToDeleteDetails: String = ""

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var unit: String { BodyUnits.weightUnit(metric: useMetric) }

    private func display(_ lbs: Double) -> String {
        numberFormatter.string(from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: lbs, metric: useMetric))) ?? "—"
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

    /// Change vs. the most recent entry at least 7 days old — the same "am I trending" signal
    /// the Home card shows, so the two surfaces never disagree.
    private var sevenDayDelta: Double? {
        let history = goalSettings.weightHistory.sorted { $0.date < $1.date }
        guard let current = history.last?.weight else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        guard let prior = history.last(where: { $0.date <= weekAgo })?.weight else { return nil }
        return current - prior
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
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard

                Button(action: { showingWeightEntrySheet = true }) {
                    Label("Log weight", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                if let target = goalSettings.targetWeight, let initial = initialWeightForCurrentGoalPeriod {
                    goalCard(target: target, initial: initial)
                } else {
                    Button("Set a target weight") {
                        targetWeightInput = display(goalSettings.weight)
                        showingCaloricCalculatorSheet = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if let initialWt = initialWeightForCurrentGoalPeriod,
                   let targetWt = goalSettings.targetWeight,
                   abs(initialWt - targetWt) > 0.01 {
                    MilestoneView(
                        initialWeight: initialWt,
                        currentWeight: goalSettings.weight,
                        targetWeight: targetWt
                    )
                }

                periodStatsCard
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingWeightEntrySheet) {
            CurrentWeightView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingTargetWeightSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Target weight")) {
                        TextField("Target weight (\(unit))", text: $targetWeightInput)
                            .keyboardType(.decimalPad)
                    }
                    Button("Save target") {
                        if let targetValue = Double(targetWeightInput), targetValue > 0 {
                            goalSettings.targetWeight = BodyUnits.weightToLbs(targetValue, metric: useMetric)
                            if let userID = DIContainer.shared.authService.currentUserID {
                                goalSettings.saveUserGoals(userID: userID)
                            }
                        }
                        showingTargetWeightSheet = false
                    }
                    .disabled(Double(targetWeightInput) == nil || (Double(targetWeightInput) ?? 0) <= 0)
                }
                .navigationTitle("Set target")
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
        .alert("Delete this entry?", isPresented: $showingChartDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let idToDelete = chartEntryToDeleteID {
                    confirmDeleteChartEntry(entryID: idToDelete)
                }
            }
            Button("Cancel", role: .cancel) {
                chartEntryToDeleteID = nil
            }
        } message: {
            Text("\(chartEntryToDeleteDetails) will be removed from your history.")
        }
        .onAppear {
            goalSettings.loadWeightHistory()
            if let target = goalSettings.targetWeight {
                targetWeightInput = display(target)
            } else {
                targetWeightInput = display(goalSettings.weight)
            }
        }
    }

    // MARK: - Hero: current weight + trend chart

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current weight")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(goalSettings.weight > 0 ? display(goalSettings.weight) : "—")
                            .appFont(size: 36, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: goalSettings.weight)

                        Text(unit)
                            .appFont(size: 15, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }

                Spacer()

                if let delta = sevenDayDelta, abs(delta) >= 0.05 {
                    let down = delta < 0
                    HStack(spacing: 4) {
                        Image(systemName: down ? "arrow.down.right" : "arrow.up.right")
                            .appFont(size: 11, weight: .bold)
                        Text("\(display(abs(delta))) \(unit) · 7 days")
                            .appFont(size: 12, weight: .semibold)
                    }
                    .foregroundColor(down ? .accentPositive : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
                }
            }

            Picker("Timeframe", selection: $selectedChartTimeframe.animation()) {
                ForEach(WeightChartTimeframe.allCases) { timeframe in
                    Text(timeframe.rawValue).tag(timeframe)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            if !filteredDataForLineChart.isEmpty {
                WeightChartView(
                    weightHistory: filteredDataForLineChart,
                    currentWeight: goalSettings.weight,
                    onEntrySelected: { entryId in
                        if let entry = goalSettings.weightHistory.first(where: { $0.id == entryId }) {
                            self.chartEntryToDeleteID = entryId
                            let weightString = display(entry.weight)
                            let dateString = alertItemFormatter.string(from: entry.date)
                            self.chartEntryToDeleteDetails = "\(weightString) \(unit) on \(dateString)"
                            self.showingChartDeleteAlert = true
                        }
                    }
                )
                .frame(height: 230)

                Text("Tap a point to remove a mistaken entry.")
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .appFont(size: 22, weight: .semibold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text("No entries in this period yet")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text("Log your weight and the trend appears here.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 230)
            }
        }
        .asCard()
    }

    // MARK: - Goal card

    private func goalCard(target: Double, initial: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight goal")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                Button("Edit") {
                    targetWeightInput = display(target)
                    showingTargetWeightSheet = true
                }
                .appFont(size: 14, weight: .semibold)
                .tint(.brandPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(UIColor.secondarySystemFill))
                    Capsule().fill(Color.brandPrimary)
                        .frame(width: max(8, geo.size.width * CGFloat(min(max(currentProgress, 0), 1))))
                }
            }
            .frame(height: 10)

            HStack {
                Text("Started at \(display(initial)) \(unit)")
                Spacer()
                Text("Goal \(display(target)) \(unit)")
            }
            .appFont(size: 12)
            .foregroundColor(Color(UIColor.secondaryLabel))

            Divider()

            HStack(spacing: 15) {
                StatBox(
                    value: totalLossOrGain.map { String(format: "%+.1f %@", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric), unit) } ?? "—",
                    label: "Total change"
                )
                StatBox(
                    value: goalSettings.calculateWeightProgress().map { String(format: "%.0f%%", $0) } ?? "—",
                    label: "Progress"
                )
                StatBox(
                    value: weightRemaining.map { String(format: "%.1f %@", abs(BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)), unit) } ?? "—",
                    label: "To go"
                )
            }
        }
        .asCard()
    }

    // MARK: - Period stats

    private var periodStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period stats")
                .appFont(size: 17, weight: .semibold)

            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 15) {
                GridRow {
                    SmallStatCard(
                        title: "Daily rate",
                        value: chartStats.dailyRate.map { String(format: "%+.2f %@/day", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric), unit) } ?? "—",
                        iconName: chartStats.dailyRate.map { $0 == 0 ? "arrow.left.arrow.right" : ($0 < 0 ? "arrow.down.right" : "arrow.up.right") } ?? "scalemass",
                        iconColor: chartStats.dailyRate.map { $0 == 0 ? Color(UIColor.secondaryLabel) : ($0 < 0 ? .accentPositive : .orange) } ?? Color(UIColor.secondaryLabel)
                    )
                    SmallStatCard(
                        title: "Trend",
                        value: chartStats.trend.map { String(format: "%+.1f %@", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric), unit) } ?? "—",
                        iconName: chartStats.trend.map { $0 == 0 ? "arrow.left.arrow.right" : ($0 < 0 ? "arrow.down.right" : "arrow.up.right") } ?? "chart.line.uptrend.xyaxis",
                        iconColor: chartStats.trend.map { $0 == 0 ? Color(UIColor.secondaryLabel) : ($0 < 0 ? .accentPositive : .orange) } ?? Color(UIColor.secondaryLabel)
                    )
                }
                GridRow {
                    SmallStatCard(
                        title: "Highest",
                        value: chartStats.highest.map { "\(display($0)) \(unit)" } ?? "—",
                        iconName: "arrow.up.to.line",
                        iconColor: Color(UIColor.secondaryLabel)
                    )
                    SmallStatCard(
                        title: "Lowest",
                        value: chartStats.lowest.map { "\(display($0)) \(unit)" } ?? "—",
                        iconName: "arrow.down.to.line",
                        iconColor: Color(UIColor.secondaryLabel)
                    )
                }
            }
        }
        .asCard()
    }

    private func confirmDeleteChartEntry(entryID: String) {
        goalSettings.deleteWeightEntry(entryID: entryID) { error in
            if let error {
                AppLog.app.error("Failed to delete weight entry: \(error.localizedDescription, privacy: .public)")
            }
        }
        chartEntryToDeleteID = nil
    }
}

struct StatBox: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .appFont(size: 11, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
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
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Spacer()
            }
            Text(value)
                .appFont(size: 16, weight: .semibold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundPrimary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
