import SwiftUI

struct WeightTrackingView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var showingWeightEntrySheet = false
    @State private var showingTargetWeightSheet = false
    @State private var showingCaloricCalculatorSheet = false
    @State private var targetWeightInput = ""
    private let reportDates: ClosedRange<Date>?
    @State private var selectedChartTimeframe: WeightChartTimeframe?

    init(reportDates: ClosedRange<Date>? = nil) {
        self.reportDates = reportDates
        _selectedChartTimeframe = State(initialValue: reportDates == nil ? .month : nil)
    }
    @State private var showingChartDeleteAlert = false
    @State private var chartEntryToDeleteID: String?
    @State private var chartEntryToDeleteDetails = ""
    @State private var deletedWeightEntry: (date: Date, weight: Double)?
    @State private var weightUndoTask: Task<Void, Never>?
    @State private var isUpdatingWeight = false
    @State private var weightSaveError: String?
    @State private var targetBaseline: GoalEditorDraft?
    @State private var targetOwnerID: String?
    @State private var targetSaveError: String?

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
        guard let initial = initialWeightForCurrentGoalPeriod, let target = goalSettings.targetWeight,
              abs(initial - target) > 0.01 else { return 0 }
        return min(max((goalSettings.weight - initial) / (target - initial), 0), 1)
    }

    private var initialWeightForCurrentGoalPeriod: Double? {
        guard let period = goalSettings.weightGoalPeriods.last else { return nil }
        return goalSettings.weightHistory.filter { $0.date >= period.recordedAt && $0.date <= Date() }
            .min(by: { $0.date < $1.date })?.weight
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
        let allHistory = goalSettings.weightHistory.filter { $0.date <= now && $0.weight.isFinite && $0.weight > 0 }.sorted { $0.date < $1.date }
        guard !allHistory.isEmpty else { return [] }

        let calendar = Calendar.current
        let startDate: Date?
        guard let selectedChartTimeframe else {
            return allHistory.filter { reportDates?.contains($0.date) == true }
        }
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

    private var chartTrend: WeightTrendRules.Projection {
        WeightTrendRules.project(filteredDataForLineChart.map { .init(id: $0.id, date: $0.date, pounds: $0.weight) })
    }

    private var chartStats: (trend: Double?, highest: Double?, lowest: Double?, dailyRate: Double?) {
        let weights = filteredDataForLineChart.map(\.weight).filter { $0.isFinite && $0 > 0 }
        return (chartTrend.change, weights.max(), weights.min(), chartTrend.ratePerDay)
    }

    @ViewBuilder private var goalPeriodSection: some View {
        if let current = goalSettings.weightGoalPeriods.last {
            WeightGoalPaceSummary(period: current, weightHistory: goalSettings.weightHistory, asOf: Date())
            DisclosureGroup("Goal history · \(goalSettings.weightGoalPeriods.count) \(goalSettings.weightGoalPeriods.count == 1 ? "period" : "periods")") {
                VStack(spacing: AppSpacing.row) {
                    ForEach(Array(goalSettings.weightGoalPeriods.enumerated()).reversed(), id: \.element.id) { index, period in
                        let end = index + 1 < goalSettings.weightGoalPeriods.count
                            ? goalSettings.weightGoalPeriods[index + 1].recordedAt.addingTimeInterval(-0.001) : Date()
                        NavigationLink {
                            ScrollView {
                                VStack(spacing: AppSpacing.group) {
                                    WeightGoalPaceSummary(period: period, weightHistory: goalSettings.weightHistory, asOf: max(end, period.recordedAt))
                                    TrendDashboardView(weightHistory: goalSettings.weightHistory,
                                        dateRange: period.recordedAt...max(period.recordedAt, end), title: "Measurements in this goal period")
                                }.padding(AppSpacing.screenHorizontal)
                            }.background(AppPalette.canvas).navigationTitle("Goal period")
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(period.selection.intent).appTextRole(.control)
                                Text("\(period.recordedAt.formatted(date: .abbreviated, time: .omitted)) · \(index == goalSettings.weightGoalPeriods.count - 1 ? "Current" : end.formatted(date: .abbreviated, time: .omitted))")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("weight_goal_period_\(index)")
                    }
                }.padding(.top, AppSpacing.row)
                Text("History is saved on this device. Earlier goal dates are unknown; measurements and accepted calorie targets are never rewritten.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.appSurface(.quiet).accessibilityIdentifier("weight_goal_history")
        }
        if let notice = goalSettings.weightGoalHistoryNotice {
            Text(notice).appTextRole(.caption).foregroundStyle(AppPalette.caution)
        }
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
                trendSection

                goalSection
                goalPeriodSection

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
            VStack(spacing: AppSpacing.compact) {
                if deletedWeightEntry != nil {
                    HStack(spacing: AppSpacing.row) {
                        Label("Weight entry removed", systemImage: "trash")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.text)

                        Spacer(minLength: AppSpacing.compact)

                        Button("Undo", action: restoreDeletedWeightEntry)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.brandText)
                            .disabled(isUpdatingWeight)
                    }
                    .padding(.horizontal, AppSpacing.group)
                    .padding(.vertical, AppSpacing.row)
                    .background(
                        AppPalette.surface,
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(AppPalette.separator, lineWidth: 1)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                }

                Button {
                    showingWeightEntrySheet = true
                } label: {
                    Label("Log weight", systemImage: "plus")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("weight_log_button")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.row)
            .padding(.bottom, AppSpacing.compact)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
            .animation(AppMotion.visibility, value: deletedWeightEntry != nil)
        }
        .sheet(isPresented: $showingWeightEntrySheet) {
            CurrentWeightView()
                .environmentObject(goalSettings)
        }
        .sheet(isPresented: $showingTargetWeightSheet) {
            TargetWeightSheet(
                value: $targetWeightInput,
                unit: unit,
                isSaving: isUpdatingWeight,
                errorMessage: targetSaveError,
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
        .alert("Couldn't update weight", isPresented: Binding(get: { weightSaveError != nil }, set: { if !$0 { weightSaveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(weightSaveError ?? "")
        }
        .onAppear {
            goalSettings.loadWeightHistory()
            targetWeightInput = display(goalSettings.targetWeight ?? goalSettings.weight)
            #if DEBUG
            if ScreenshotDemoMode.isEnabled {
                if ScreenshotDemoData.requestedScreen == "weight-target" { showingTargetWeightSheet = true }
                if ScreenshotDemoData.requestedScreen == "weight-entry" { showingWeightEntrySheet = true }
            }
            #endif
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            currentWeightSummary

            timeframePicker
            if selectedChartTimeframe == nil, let reportDates {
                Text("\(reportDates.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(reportDates.upperBound.formatted(date: .abbreviated, time: .omitted)) · \(filteredDataForLineChart.count) measurements")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("weight_report_scope")
            }

            if !filteredDataForLineChart.isEmpty {
                WeightChartView(
                    weightHistory: filteredDataForLineChart,
                    currentWeight: goalSettings.weight,
                    onEntrySelected: selectChartEntry
                )
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 270 : 230)

                Text("Estimated trend · measured dots · \(unit)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Chart details & corrections") {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(chartTrend.description)
                            .accessibilityIdentifier("weight_tracking_trend_coverage")
                        Label("Tap a point to remove a mistaken entry.", systemImage: "hand.tap")
                    }
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .padding(.top, AppSpacing.compact)
                }
                .appTextRole(.secondary)
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
        let picker = Picker("Timeframe", selection: $selectedChartTimeframe.animation(AppMotion.standard)) {
            if reportDates != nil { Text("Report dates").tag(nil as WeightChartTimeframe?) }
            ForEach(WeightChartTimeframe.allCases) { timeframe in
                Text(timeframe.rawValue).tag(Optional(timeframe))
            }
        }.accessibilityIdentifier("weight_timeframe_picker")
        if dynamicTypeSize.isAccessibilitySize || reportDates != nil {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
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
                        targetBaseline = goalSettings.makeGoalEditorDraft()
                        targetOwnerID = DIContainer.shared.authService.currentUserID
                        targetSaveError = nil
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
                subtitle: "Trend uses elapsed calendar days. High and low are recorded measurements."
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
        guard !isUpdatingWeight else { return }
        guard let entry = goalSettings.weightHistory.first(where: { $0.id == entryID }) else { return }
        chartEntryToDeleteID = entryID
        chartEntryToDeleteDetails = "\(display(entry.weight)) \(unit) on \(alertItemFormatter.string(from: entry.date))"
        showingChartDeleteAlert = true
    }

    private func saveTargetWeight() {
        guard !isUpdatingWeight, let value = Double(targetWeightInput), value.isFinite, value > 0,
              let baseline = targetBaseline, let owner = targetOwnerID else { return }
        var proposal = baseline
        proposal.targetWeight = BodyUnits.weightToLbs(value, metric: useMetric)
        isUpdatingWeight = true; targetSaveError = nil
        Task { @MainActor in
            do {
                try await goalSettings.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner)
                isUpdatingWeight = false; showingTargetWeightSheet = false
            } catch { isUpdatingWeight = false; targetSaveError = error.localizedDescription }
        }
    }

    private func confirmDeleteChartEntry(entryID: String) {
        guard !isUpdatingWeight, let entry = goalSettings.weightHistory.first(where: { $0.id == entryID }) else { return }
        isUpdatingWeight = true
        goalSettings.deleteWeightEntry(entryID: entryID) { error in
            isUpdatingWeight = false
            if error != nil {
                weightSaveError = "The entry couldn't be removed. Try again."
                return
            }
            deletedWeightEntry = (entry.date, entry.weight)
            weightUndoTask?.cancel()
            weightUndoTask = Task {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(AppMotion.visibility) {
                        deletedWeightEntry = nil
                    }
                }
            }
        }
        chartEntryToDeleteID = nil
    }

    private func restoreDeletedWeightEntry() {
        guard !isUpdatingWeight, let deletedWeightEntry else { return }
        weightUndoTask?.cancel()
        isUpdatingWeight = true
        goalSettings.updateUserWeight(
            deletedWeightEntry.weight,
            date: deletedWeightEntry.date,
            syncToHealthKit: false
        ) { accepted in
            isUpdatingWeight = false
            if accepted {
                withAnimation(AppMotion.visibility) {
                    self.deletedWeightEntry = nil
                }
            } else {
                weightSaveError = "The entry couldn't be restored. Undo is still available to retry."
            }
        }
    }
}

private struct TargetWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var value: String
    let unit: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: () -> Void
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        guard let value = Double(value) else { return false }
        return value.isFinite && value > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Text("Set a target for your current goal. You can adjust it as your plan evolves.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)

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
            .navigationTitle("Target weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                if let errorMessage { Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.critical) }
                Button(isSaving ? "Saving…" : "Save target") {
                    isFocused = false
                    onSave()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!isValid || isSaving)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(AppPalette.separator).frame(height: 1)
                }
                }
            }
            .onAppear { isFocused = true }
            .interactiveDismissDisabled(isSaving)
        }
        .tint(AppPalette.brand)
    }
}

private struct WeightGoalPaceSummary: View {
    let period: WeightGoalPeriod
    let weightHistory: [(id: String, date: Date, weight: Double)]
    let asOf: Date
    private var comparison: WeightGoalComparisonRules.Comparison {
        WeightGoalComparisonRules.evaluate(period: period,
            samples: weightHistory.map { .init(id: $0.id, date: $0.date, pounds: $0.weight) }, asOf: asOf)
    }
    private func weight(_ value: Double) -> String {
        BodyUnits.weightString(lbs: value, metric: period.selection.metricAtAcceptance)
    }
    private func rate(_ value: Double) -> String { (value > 0 ? "+" : "") + weight(value) + "/week" }
    var body: some View {
        let value = comparison
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Pace for this goal").appTextRole(.sectionTitle)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desired").appTextRole(.caption).foregroundStyle(.secondary)
                    Text(rate(value.desiredWeeklyChange)).appTextRole(.control).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Observed trend").appTextRole(.caption).foregroundStyle(.secondary)
                    Text(value.observedWeeklyChange.map(rate) ?? "More data needed")
                        .appTextRole(.control).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let target = period.selection.targetPounds { Text("Goal weight: " + weight(target)).appTextRole(.secondary) }
            Text("\(value.measuredDays) measured days across \(value.spanDays) days in this goal period")
                .appTextRole(.caption).foregroundStyle(.secondary)
            if let range = value.projectedPounds, let date = value.projectionDate {
                Text("14-day scenario · \(date.formatted(date: .abbreviated, time: .omitted))")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                Text("\(weight(range.lowerBound))–\(weight(range.upperBound))").appTextRole(.control)
            }
            Text(value.explanation).appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if period.source == .observed {
                Text("First observed \(period.recordedAt.formatted(date: .abbreviated, time: .omitted)). The original start date was not recorded.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }.appSurface(.quiet).accessibilityIdentifier("weight_goal_pace")
    }
}
