import SwiftUI

struct WeeklyCheckInView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @Environment(\.dismiss) var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits: Bool = Locale.current.measurementSystem != .us
    @State private var hasLoggedProposalView = false

    private var goalProposal: AdaptiveGoalService.WeeklyGoalProposal? {
        adaptiveGoalService.currentWeeklyGoalProposal(
            currentCalories: goalSettings.calories,
            goal: goalSettings.goal,
            gender: goalSettings.gender,
            proteinPercentage: goalSettings.proteinPercentage,
            carbsPercentage: goalSettings.carbsPercentage,
            fatsPercentage: goalSettings.fatsPercentage
        )
    }

    private var averageIntakeText: String {
        guard let average = adaptiveGoalService.last21DaysCalorieAverage else { return "--" }
        return "\(Int(average.rounded()).formatted()) cal/day"
    }

    private var weightTrendValueText: String {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay else { return "--" }
        let weeklyRate = BodyUnits.weightDisplayValue(lbs: rate * 7, metric: useMetricBodyUnits)
        return weeklyRate.formatted(.number.precision(.fractionLength(2)))
    }

    private var weightTrendUnitText: String {
        "\(BodyUnits.weightUnit(metric: useMetricBodyUnits)) / week"
    }

    private var calculatedTDEEText: String {
        guard let tdee = adaptiveGoalService.calculatedTDEE else { return "--" }
        return Int(tdee.rounded()).formatted()
    }

    private var targetDeltaText: String {
        if let goalProposal {
            return goalProposal.summary
        }
        guard let current = goalSettings.calories,
              let calculated = adaptiveGoalService.calculatedTDEE else {
            return "MyFitPlate will switch your targets to the latest adaptive estimate."
        }

        let delta = Int((calculated - current).rounded())
        if abs(delta) < 50 {
            return "Your current target is already close to the latest estimate."
        }

        return delta > 0
            ? "The adaptive estimate is \(delta) calories higher than your current target."
            : "The adaptive estimate is \(abs(delta)) calories lower than your current target."
    }

    private var coachingReasonText: String {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay,
              let average = adaptiveGoalService.last21DaysCalorieAverage else {
            return "This recommendation uses your recent weigh-ins and logged intake once enough data is available."
        }

        let weeklyRate = rate * 7
        let trend: String
        if weeklyRate > 0.15 {
            trend = "weight has been trending up"
        } else if weeklyRate < -0.15 {
            trend = "weight has been trending down"
        } else {
            trend = "weight has been mostly stable"
        }

        return "Over the last 21 days, your average logged intake was \(Int(average.rounded()).formatted()) calories and your \(trend)."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    if adaptiveGoalService.dataConfidence == .high || adaptiveGoalService.dataConfidence == .medium {
                        statsSection
                        TrendDashboardView(weightHistory: goalSettings.weightHistory)
                        recommendationSection
                        actionSection
                    } else {
                        needsDataSection
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Weekly check-in")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: logProposalViewedIfNeeded)
            .toolbar {
                // Toolbar empty to enforce rigid check-in
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .appFont(size: 32, weight: .bold)
                .foregroundColor(AppPalette.caution)
                .padding()
                .background(Color(UIColor.secondarySystemFill), in: Circle())
            
            Text("Time for your check-in")
                .appFont(size: 21, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We've analyzed your weight and nutrition data from the past 3 weeks to adjust your metabolism estimate.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 16)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your data")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(adaptiveGoalService.dataConfidence.rawValue)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.12), in: Capsule())
            }
            
            HStack(spacing: 16) {
                WeeklyCheckInStatCard(
                    title: "Avg intake",
                    value: averageIntakeText,
                    subtitle: "last 21 days",
                    icon: "fork.knife",
                    color: AppPalette.energy
                )
                
                WeeklyCheckInStatCard(
                    title: "Weight trend",
                    value: weightTrendValueText,
                    subtitle: weightTrendUnitText,
                    icon: "scalemass.fill",
                    color: AppPalette.effort
                )
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Calculated TDEE")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(calculatedTDEEText)
                        .appFont(size: 48, weight: .heavy)
                        .foregroundColor(.textPrimary)
                    Text(" cal/day")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .appSurface(.interpreted)
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: acceptTargets) {
                Text("Use adaptive targets")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(AppPalette.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button(action: skipCheckIn) {
                Text("Keep current targets")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "target")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(AppPalette.caution)
                    .frame(width: 42, height: 42)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Why this target")
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(coachingReasonText)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(targetDeltaText)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(AppPalette.caution)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppPalette.caution.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let goalProposal {
                proposalDetails(goalProposal)
            }

            Text("Accepting keeps the app in adaptive mode. Keeping current targets simply delays the change; your data will keep updating.")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .appSurface(.interpreted)
    }

    private func proposalDetails(_ proposal: AdaptiveGoalService.WeeklyGoalProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.title)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("\(Int(proposal.proposedCalories.rounded()).formatted()) cal/day")
                        .appFont(size: 28, weight: .heavy)
                        .foregroundColor(.brandForeground)
                }

                Spacer()

                Text(deltaText(for: proposal.calorieDelta))
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(proposal.shouldAdjust ? AppPalette.caution : .accentPositive)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((proposal.shouldAdjust ? AppPalette.caution : AppPalette.positive).opacity(0.10), in: Capsule())
            }

            HStack(spacing: 8) {
                proposalMacroChip("P", value: proposal.macroGoals.protein, color: .accentProtein)
                proposalMacroChip("C", value: proposal.macroGoals.carbs, color: .accentCarbs)
                proposalMacroChip("F", value: proposal.macroGoals.fats, color: .accentFats)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(proposal.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "checkmark.circle.fill")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func proposalMacroChip(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(size: 10, weight: .bold)
                .foregroundColor(color)
            Text("\(Int(value.rounded()))g")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var needsDataSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .appFont(size: 40)
                .foregroundColor(.gray)
            
            Text("Needs more data")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We need at least 7 days of weight data and 10 days of food logs to confidently adjust your TDEE.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            
            Button(action: skipCheckIn) {
                Text("Check back later")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .appSurface(.emphasized)
    }
    
    private func acceptTargets() {
        HapticManager.instance.feedback(.light)
        logProposalDecision("accepted")
        goalSettings.calorieGoalMethod = .dynamicTDEE
        goalSettings.lastCheckInDate = Date()
        goalSettings.recalculateAllGoals()
        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
    
    private func skipCheckIn() {
        HapticManager.instance.feedback(.light)
        logProposalDecision("kept_current")
        goalSettings.lastCheckInDate = Date()
        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }

    private func deltaText(for delta: Double) -> String {
        guard abs(delta) >= 1 else { return "No change" }
        return delta > 0
            ? "+\(Int(delta.rounded()).formatted()) cal"
            : "-\(Int(abs(delta.rounded())).formatted()) cal"
    }

    private func logProposalViewedIfNeeded() {
        guard !hasLoggedProposalView, let proposal = goalProposal else { return }
        hasLoggedProposalView = true
        DIContainer.shared.analyticsManager?.logEvent("weekly_goal_proposal_viewed", parameters: [
            "confidence": proposal.confidence.rawValue,
            "should_adjust": proposal.shouldAdjust,
            "delta": Int(proposal.calorieDelta.rounded()),
            "training_load": proposal.trainingLoadLabel
        ])
    }

    private func logProposalDecision(_ decision: String) {
        guard let proposal = goalProposal else { return }
        DIContainer.shared.analyticsManager?.logEvent("weekly_goal_proposal_decision", parameters: [
            "decision": decision,
            "confidence": proposal.confidence.rawValue,
            "should_adjust": proposal.shouldAdjust,
            "delta": Int(proposal.calorieDelta.rounded()),
            "training_load": proposal.trainingLoadLabel
        ])
    }
}

private struct WeeklyCheckInStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .padding(8)
                .background(color.opacity(0.12), in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
import Charts

struct TrendDashboardView: View {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var dateRange: ClosedRange<Date>?
    var title: String

    init(
        weightHistory: [(id: String, date: Date, weight: Double)],
        dateRange: ClosedRange<Date>? = nil,
        title: String = "Weight trend (21 days)"
    ) {
        self.weightHistory = weightHistory
        self.dateRange = dateRange
        self.title = title
    }
    
    private var chartData: [(date: Date, weight: Double)] {
        let range = dateRange ?? {
            let calendar = Calendar.current
            let end = Date()
            let start = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: end)) ?? end
            return start...end
        }()
        let recent = weightHistory.filter { range.contains($0.date) }.sorted { $0.date < $1.date }
        return recent.map { (date: $0.date, weight: $0.weight) }
    }

    // Exponential moving average — the actual "smoothed trend" the caption promises.
    private var smoothedData: [(date: Date, weight: Double)] {
        let raw = chartData
        guard let first = raw.first else { return [] }
        let alpha = 0.4
        var ema = first.weight
        return raw.map { point in
            ema = alpha * point.weight + (1 - alpha) * ema
            return (date: point.date, weight: ema)
        }
    }

    private var yAxisDomain: ClosedRange<Double> {
        let weights = chartData.map { $0.weight } + smoothedData.map { $0.weight }
        let minW = weights.min() ?? 150.0
        let maxW = weights.max() ?? 150.0
        let padding = max(1.5, (maxW - minW) * 0.4)
        return (minW - padding)...(maxW + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("Your smoothed weight trend, adjusted for day-to-day fluctuations.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.bottom, 8)

            if chartData.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .appFont(size: 28)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text("Log a few more weigh-ins")
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Text("Your trend line appears once you have at least two recent entries.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            } else {
                Chart {
                    // Real weigh-ins as subtle dots
                    ForEach(chartData, id: \.date) { item in
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                        .symbolSize(28)
                    }
                    // Smoothed trend: area + line
                    ForEach(smoothedData, id: \.date) { item in
                        AreaMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
                .chartYScale(domain: yAxisDomain)
                .chartXScale(range: .plotDimension(padding: 18))
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month().day())
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .clipped()
            }
        }
        .padding(20)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
