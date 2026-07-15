import SwiftUI

struct WeightTrackingView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var showingWeightEntrySheet = false
    @State private var showingTargetWeightSheet = false
    @State private var showingCaloricCalculatorSheet = false
    @State private var targetWeightInput = ""
    @State private var selectedChartTimeframe: WeightChartTimeframe = .month
    @State private var showingChartDeleteAlert = false
    @State private var chartEntryToDeleteID: String?
    @State private var chartEntryToDeleteDetails = ""

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var unit: String { BodyUnits.weightUnit(metric: useMetric) }

    private func display(_ lbs: Double) -> String {
        numberFormatter.string(
            from: NSNumber(value: BodyUnits.weightDisplayValue(lbs: lbs, metric: useMetric))
        ) ?? "--"
    }

    private var currentProgress: Double {
        goalSettings.calculateWeightProgress().map { min(max($0 / 100, 0), 1) } ?? 0
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

    private var sevenDayDelta: Double? {
        let history = goalSettings.weightHistory.sorted { $0.date < $1.date }
        guard let current = history.last?.weight else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        guard let prior = history.last(where: { $0.date <= weekAgo })?.weight else { return nil }
        return current - prior
    }

    private var filteredDataForLineChart: [(id: String, date: Date, weight: Double)] {
        let now = Date()
        let allHistory = goalSettings.weightHistory.sorted { $0.date < $1.date }
        guard !allHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        let startDate: Date?
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

        guard let startDate else { return allHistory }
        return allHistory.filter { $0.date >= startDate }
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
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Body Trend",
                    title: "Weight Progress",
                    subtitle: "Follow the direction over time without overreacting to a single day."
                )

                trendSection

                goalSection

                if let initial = initialWeightForCurrentGoalPeriod,
                   let target = goalSettings.targetWeight,
                   abs(initial - target) > 0.01 {
                    MilestoneView(
                        initialWeight: initial,
                        currentWeight: goalSettings.weight,
                        targetWeight: target
                    )
                }

                periodStatsSection

                Color.clear.frame(height: 76)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("weight_tracking_screen")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingWeightEntrySheet = true
            } label: {
                Label("Log Weight", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.row)
            .padding(.bottom, AppSpacing.compact)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("weight_log_button")
        }
        .sheet(isPresented: $showingWeightEntrySheet) {
            CurrentWeightView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingTargetWeightSheet) {
            TargetWeightSheet(
                value: $targetWeightInput,
                unit: unit,
                onSave: saveTargetWeight
            )
        }
        .sheet(isPresented: $showingCaloricCalculatorSheet) {
            CaloricCalculatorView()
                .environmentObject(goalSettings)
        }
        .alert("Delete this entry?", isPresented: $showingChartDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = chartEntryToDeleteID {
                    confirmDeleteChartEntry(entryID: id)
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
            targetWeightInput = display(goalSettings.targetWeight ?? goalSettings.weight)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            currentWeightSummary

            timeframePicker

            if !filteredDataForLineChart.isEmpty {
                WeightChartView(
                    weightHistory: filteredDataForLineChart,
                    currentWeight: goalSettings.weight,
                    onEntrySelected: selectChartEntry
                )
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 270 : 230)

                Label("Tap a point to remove a mistaken entry.", systemImage: "hand.tap")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            } else {
                GuidanceEmptyState(
                    icon: "chart.xyaxis.line",
                    title: "No entries in this period",
                    message: "Log your weight and the trend will appear here."
                )
                .frame(minHeight: 220)
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("weight_trend_section")
    }

    @ViewBuilder
    private var timeframePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Timeframe", selection: $selectedChartTimeframe.animation(AppMotion.standard)) {
                ForEach(WeightChartTimeframe.allCases) { timeframe in
                    Text(timeframe.rawValue).tag(timeframe)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("weight_timeframe_picker")
        } else {
            Picker("Timeframe", selection: $selectedChartTimeframe.animation(AppMotion.standard)) {
                ForEach(WeightChartTimeframe.allCases) { timeframe in
                    Text(timeframe.rawValue).tag(timeframe)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("weight_timeframe_picker")
        }
    }

    @ViewBuilder
    private var currentWeightSummary: some View {
        let value = goalSettings.weight > 0 ? display(goalSettings.weight) : "--"

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                weightValue(value)
                sevenDayChange
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.group) {
                weightValue(value)
                Spacer(minLength: AppSpacing.compact)
                sevenDayChange
            }
        }
    }

    private func weightValue(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Current Weight")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                Text(value)
                    .appTextRole(.display)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(unit)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sevenDayChange: some View {
        if let delta = sevenDayDelta, abs(delta) >= 0.05 {
            let isDown = delta < 0
            Label(
                "\(display(abs(delta))) \(unit) in 7 days",
                systemImage: isDown ? "arrow.down.right" : "arrow.up.right"
            )
            .appTextRole(.caption)
            .foregroundStyle(isDown ? Color.accentPositive : AppPalette.caution)
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.compact)
            .background(AppPalette.control, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("7-day change will appear after enough entries")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var goalSection: some View {
        if let target = goalSettings.targetWeight,
           let initial = initialWeightForCurrentGoalPeriod {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Weight Goal",
                    subtitle: "Progress from \(display(initial)) \(unit) toward \(display(target)) \(unit)."
                ) {
                    Button("Edit") {
                        targetWeightInput = display(target)
                        showingTargetWeightSheet = true
                    }
                    .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
                }

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    ProgressView(value: currentProgress)
                        .tint(AppPalette.brand)
                        .accessibilityLabel("Weight goal progress")
                        .accessibilityValue("\(Int((currentProgress * 100).rounded())) percent")

                    AppMetricStrip(items: [
                        AppMetricItem(
                            label: "Total Change",
                            value: totalLossOrGain.map {
                                String(
                                    format: "%+.1f %@",
                                    BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric),
                                    unit
                                )
                            } ?? "--"
                        ),
                        AppMetricItem(
                            label: "Progress",
                            value: goalSettings.calculateWeightProgress().map {
                                String(format: "%.0f%%", $0)
                            } ?? "--"
                        ),
                        AppMetricItem(
                            label: "To Go",
                            value: weightRemaining.map {
                                String(
                                    format: "%.1f %@",
                                    abs(BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric)),
                                    unit
                                )
                            } ?? "--"
                        )
                    ])
                }
                .appSurface(.quiet)
            }
            .accessibilityIdentifier("weight_goal_section")
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Weight Goal",
                    subtitle: "Add a target to see progress and meaningful milestones."
                )

                Button {
                    targetWeightInput = display(goalSettings.weight)
                    showingCaloricCalculatorSheet = true
                } label: {
                    Label("Set a Target Weight", systemImage: "target")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
    }

    private var periodStatsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Period Signals",
                subtitle: "Calculated from the selected trend window."
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Daily Rate",
                    value: chartStats.dailyRate.map {
                        String(
                            format: "%+.2f %@/day",
                            BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric),
                            unit
                        )
                    } ?? "--",
                    accent: trendColor(chartStats.dailyRate)
                ),
                AppMetricItem(
                    label: "Net Trend",
                    value: chartStats.trend.map {
                        String(
                            format: "%+.1f %@",
                            BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric),
                            unit
                        )
                    } ?? "--",
                    accent: trendColor(chartStats.trend)
                ),
                AppMetricItem(
                    label: "Highest",
                    value: chartStats.highest.map { "\(display($0)) \(unit)" } ?? "--",
                    accent: AppPalette.caution
                ),
                AppMetricItem(
                    label: "Lowest",
                    value: chartStats.lowest.map { "\(display($0)) \(unit)" } ?? "--",
                    accent: AppPalette.effort
                )
            ])
            .appSurface(.quiet)
        }
        .accessibilityIdentifier("weight_period_signals")
    }

    private func trendColor(_ value: Double?) -> Color {
        guard let value else { return Color(UIColor.secondaryLabel) }
        if value < 0 { return .accentPositive }
        if value > 0 { return AppPalette.caution }
        return Color(UIColor.secondaryLabel)
    }

    private func selectChartEntry(_ entryID: String) {
        guard let entry = goalSettings.weightHistory.first(where: { $0.id == entryID }) else { return }
        chartEntryToDeleteID = entryID
        chartEntryToDeleteDetails = "\(display(entry.weight)) \(unit) on \(alertItemFormatter.string(from: entry.date))"
        showingChartDeleteAlert = true
    }

    private func saveTargetWeight() {
        guard let value = Double(targetWeightInput), value > 0 else { return }
        goalSettings.targetWeight = BodyUnits.weightToLbs(value, metric: useMetric)
        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
        }
        showingTargetWeightSheet = false
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

private struct TargetWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var value: String
    let unit: String
    let onSave: () -> Void
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        guard let value = Double(value) else { return false }
        return value > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Body Goal",
                        title: "Target Weight",
                        subtitle: "You can change this at any time as your plan evolves."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Target")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                            TextField("0.0", text: $value)
                                .keyboardType(.decimalPad)
                                .focused($isFocused)
                                .appTextRole(.metric)
                                .monospacedDigit()
                                .accessibilityLabel("Target weight in \(unit)")

                            Text(unit)
                                .appTextRole(.control)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Set Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Target") {
                    isFocused = false
                    onSave()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!isValid)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(AppPalette.separator).frame(height: 1)
                }
            }
            .onAppear { isFocused = true }
        }
        .tint(AppPalette.brand)
    }
}
