import Charts
import MyFitPlateCore
import SwiftUI

struct CalorieTrackingView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: ReportsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var caloriePoints: [DateValuePoint] {
        NutritionTrendRules.validPoints(viewModel.calorieTrend)
    }

    private var proteinPoints: [DateValuePoint] {
        NutritionTrendRules.validPoints(viewModel.proteinTrend)
    }

    private var carbPoints: [DateValuePoint] {
        NutritionTrendRules.validPoints(viewModel.carbTrend)
    }

    private var fatPoints: [DateValuePoint] {
        NutritionTrendRules.validPoints(viewModel.fatTrend)
    }

    private var trendSummary: NutritionTrendSummary {
        NutritionTrendRules.summary(
            calories: caloriePoints,
            protein: proteinPoints,
            carbs: carbPoints,
            fat: fatPoints
        )
    }

    private var hasMacroData: Bool {
        !proteinPoints.isEmpty || !carbPoints.isEmpty || !fatPoints.isEmpty
    }

    private var chartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 270 : 220
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Reports",
                    title: "Nutrition Trends",
                    subtitle: "Daily calories, macros, and the nutrients your food sources actually report."
                )

                summarySection
                calorieTrendSection
                macroTrendSection
                micronutrientSection
                sourceNote
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Nutrition Trends")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppPalette.brand)
    }

    private var summarySection: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Days Shown",
                value: trendSummary.observedDays.formatted(),
                accent: AppPalette.brand
            ),
            AppMetricItem(
                label: "Avg Calories",
                value: formatted(trendSummary.averageCalories, unit: "cal"),
                accent: AppPalette.energy
            ),
            AppMetricItem(
                label: "Avg Protein",
                value: formatted(trendSummary.averageProtein, unit: "g"),
                accent: .accentProtein
            ),
            AppMetricItem(
                label: "Avg Carbs",
                value: formatted(trendSummary.averageCarbs, unit: "g"),
                accent: .accentCarbs
            ),
            AppMetricItem(
                label: "Avg Fat",
                value: formatted(trendSummary.averageFat, unit: "g"),
                accent: .accentFats
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("nutrition_trends_summary")
    }

    private var calorieTrendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Calories",
                subtitle: "Each point is a logged daily total. The dashed line is your current goal."
            )

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                ReportLegend(items: [
                    ReportLegendItem(label: "Daily total", color: AppPalette.energy, isDashed: false),
                    ReportLegendItem(
                        label: calorieGoalLabel,
                        color: Color(UIColor.secondaryLabel),
                        isDashed: true
                    )
                ])

                if caloriePoints.isEmpty {
                    ReportChartEmptyState(message: "Log food on more days to build a calorie trend.")
                } else {
                    Chart {
                        ForEach(caloriePoints) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Calories", point.value)
                            )
                            .foregroundStyle(AppPalette.energy)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Calories", point.value)
                            )
                            .foregroundStyle(AppPalette.energy)
                            .symbolSize(24)
                        }

                        if let goal = NutritionTrendRules.validGoal(goalSettings.calories) {
                            RuleMark(y: .value("Calorie goal", goal))
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(AppPalette.separator)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(AppPalette.separator)
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(Int(amount.rounded()).formatted())
                                }
                            }
                        }
                    }
                    .frame(height: chartHeight)
                    .accessibilityLabel("Daily calorie trend")
                }
            }
            .appSurface(.quiet)
            .accessibilityIdentifier("nutrition_trends_calorie_chart")
        }
    }

    private var macroTrendSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Macros",
                subtitle: "Daily protein, carbohydrate, and fat totals in grams."
            )

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                ReportLegend(items: [
                    ReportLegendItem(label: "Protein", color: .accentProtein, isDashed: false),
                    ReportLegendItem(label: "Carbs", color: .accentCarbs, isDashed: false),
                    ReportLegendItem(label: "Fat", color: .accentFats, isDashed: false)
                ])

                if !hasMacroData {
                    ReportChartEmptyState(message: "Log meals with macro data to build this trend.")
                } else {
                    Chart {
                        macroSeries(proteinPoints, name: "Protein", color: .accentProtein)
                        macroSeries(carbPoints, name: "Carbs", color: .accentCarbs)
                        macroSeries(fatPoints, name: "Fat", color: .accentFats)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(AppPalette.separator)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(AppPalette.separator)
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(Int(amount.rounded()).formatted())
                                }
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: chartHeight)
                    .accessibilityLabel("Daily macro trend")
                }
            }
            .appSurface(.quiet)
            .accessibilityIdentifier("nutrition_trends_macro_chart")
        }
    }

    @ChartContentBuilder
    private func macroSeries(
        _ points: [DateValuePoint],
        name: String,
        color: Color
    ) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value(name, point.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", point.date, unit: .day),
                y: .value(name, point.value)
            )
            .foregroundStyle(color)
            .symbolSize(18)
        }
    }

    private var micronutrientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Micronutrient Coverage",
                subtitle: "Averages exclude days when no logged source reported that nutrient."
            )

            if viewModel.micronutrientAverages.isEmpty {
                ReportChartEmptyState(message: "No reported micronutrient data is available for this period.")
                    .appSurface(.quiet)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.micronutrientAverages.enumerated()), id: \.element.id) { index, nutrient in
                        ReportMicronutrientRow(nutrient: nutrient)

                        if index < viewModel.micronutrientAverages.count - 1 {
                            Divider().padding(.leading, AppSpacing.group)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
                .accessibilityIdentifier("nutrition_trends_micros")
            }
        }
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label("Goal Method", systemImage: "book.closed")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text("Calorie and nutrient goals use the profile settings you selected, including Mifflin-St Jeor and Dietary Reference Intake guidance where applicable.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: "https://www.nal.usda.gov/human-nutrition-and-food-safety/dri-calculator") {
                Link("USDA Dietary Reference Intakes", destination: url)
                    .appTextRole(.caption)
            }
        }
    }

    private var calorieGoalLabel: String {
        guard let goal = NutritionTrendRules.validGoal(goalSettings.calories) else {
            return "Goal unavailable"
        }
        return "Goal \(Int(goal.rounded()).formatted()) cal"
    }

    private func formatted(_ value: Double?, unit: String) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()).formatted()) \(unit)"
    }
}

private struct ReportLegendItem: Identifiable {
    let label: String
    let color: Color
    let isDashed: Bool

    var id: String { label }
}

private struct ReportLegend: View {
    let items: [ReportLegendItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.group) {
                ForEach(items) { item in legendItem(item) }
            }

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ForEach(items) { item in legendItem(item) }
            }
        }
    }

    private func legendItem(_ item: ReportLegendItem) -> some View {
        HStack(spacing: 6) {
            if item.isDashed {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1))
                    path.addLine(to: CGPoint(x: 20, y: 1))
                }
                .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 20, height: 2)
            } else {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
            }

            Text(item.label)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReportChartEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(message)
                .appTextRole(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct ReportMicronutrientRow: View {
    let nutrient: MicroAverageDataPoint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var average: Double? {
        NutritionTrendRules.finiteNonnegative(nutrient.averageValue)
    }

    private var goal: Double? {
        NutritionTrendRules.validGoal(nutrient.goalValue)
    }

    private var progress: Double {
        guard let average, let goal else { return 0 }
        return min(max(average / goal, 0), 1)
    }

    private var percentageText: String {
        guard let average, let goal else { return "Not available" }
        return "\(Int((average / goal * 100).rounded()).formatted())%"
    }

    private var valueText: String {
        guard let average, let goal else { return "No valid value" }
        let precision = nutrient.unit == "mcg" ? 0 : 1
        let averageText = average.formatted(.number.precision(.fractionLength(0...precision)))
        let goalText = goal.formatted(.number.precision(.fractionLength(0...precision)))
        return "\(averageText) of \(goalText) \(nutrient.unit)"
    }

    private var coverageText: String {
        guard nutrient.totalDayCount > 0 else { return "Coverage unavailable" }
        return "Reported on \(nutrient.reportedDayCount) of \(nutrient.totalDayCount) days"
    }

    private var tint: Color {
        if nutrient.name == "Sodium" {
            return progress >= 1 ? AppPalette.caution : AppPalette.effort
        }
        return progress >= 1 ? .accentPositive : AppPalette.effort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) { heading; percentage }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        heading
                        Spacer(minLength: AppSpacing.compact)
                        percentage
                    }
                }
            }

            ProgressView(value: progress)
                .tint(tint)

            Text("\(valueText) | \(coverageText)")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.name), \(percentageText), \(valueText), \(coverageText)")
    }

    private var heading: some View {
        Text(nutrient.name)
            .appTextRole(.control)
            .foregroundStyle(AppPalette.text)
    }

    private var percentage: some View {
        Text(percentageText)
            .appTextRole(.control)
            .foregroundStyle(tint)
            .monospacedDigit()
    }
}
