import SwiftUI
import Charts

struct CalorieTrackingView: View {
    @StateObject private var viewModel: ReportsViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel

    @State private var selectedTimeframe: ReportTimeframe = .week
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    
    @State private var showingDetailedInsights = false

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    func safePercentage(user: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min((user / total) * 100, 100)
    }
    
    private func calculateProgress(consumed: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0) * 0.8
    }
    
    @ViewBuilder private var calorieChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily calorie trend").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.calorieTrend.isEmpty {
                Chart(viewModel.calorieTrend) { dp in
                    LineMark(x: .value("Date", dp.date, unit: .day), y: .value("Calories", dp.value))
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.catmullRom)
                    if let goal = goalSettings.calories {
                        let formattedGoal = numberFormatter.string(from: NSNumber(value: goal)) ?? ""
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("\(formattedGoal) cal goal")
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
                .chartYAxisLabel("Calories", position: .leading, alignment: .center, spacing: 10)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("Not enough data for trend")
                    .foregroundColor(Color(UIColor.secondaryLabel)).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .asCard()
    }
    
    @ViewBuilder private var macroChartCard: some View {
        VStack(alignment: .leading) {
            Text("Daily macro trend").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.proteinTrend.isEmpty || !viewModel.carbTrend.isEmpty || !viewModel.fatTrend.isEmpty {
                Chart {
                    RuleMark(y: .value("Protein goal", goalSettings.protein)).foregroundStyle(Color.accentProtein.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("Protein goal").appFont(size: 10).foregroundColor(Color.accentProtein.opacity(0.7)) }
                    RuleMark(y: .value("Carb goal", goalSettings.carbs)).foregroundStyle(Color.accentCarbs.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("Carb goal").appFont(size: 10).foregroundColor(Color.accentCarbs.opacity(0.7)) }
                    RuleMark(y: .value("Fat goal", goalSettings.fats)).foregroundStyle(Color.accentFats.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).annotation(position: .top, alignment: .trailing) { Text("Fat goal").appFont(size: 10).foregroundColor(Color.accentFats.opacity(0.7)) }
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
                .chartYAxisLabel("Grams", position: .leading, alignment: .center, spacing: 10)
                .chartForegroundStyleScale([ "Protein": Color.accentProtein, "Carbs": Color.accentCarbs, "Fats": Color.accentFats ])
                .chartLegend(position: .top, alignment: .center)
                .frame(height: 200)
            } else if !viewModel.isLoading {
                Text("Not enough data for trend")
                    .foregroundColor(Color(UIColor.secondaryLabel)).padding().frame(height: 200).frame(maxWidth: .infinity)
            }
        }
        .asCard()
    }
    
    init(viewModel: ReportsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    @ViewBuilder private var micronutrientReportCard: some View {
        VStack(alignment: .leading) {
            Text("Average micronutrient intake").appFont(size: 17, weight: .semibold).padding(.bottom, 5)
            if !viewModel.micronutrientAverages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    ForEach(viewModel.micronutrientAverages) { micro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(micro.name).appFont(size: 12, weight: .bold)
                                Spacer()
                                Text("\(micro.percentageMet, specifier: "%.0f")%").appFont(size: 12, weight: .bold)
                            }
                            ProgressView(value: micro.progressViewValue).tint(micro.name == "Sodium" ? (micro.percentageMet >= 100 ? .red : .orange) : (micro.percentageMet >= 100 ? .accentPositive : .blue)).scaleEffect(x: 1, y: 1.5, anchor: .center)
                            Text("\(micro.averageValue, specifier: micro.unit == "mcg" ? "%.0f" : "%.1f") / \(micro.goalValue, specifier: "%.0f") \(micro.unit)").appFont(size: 10).foregroundColor(Color(UIColor.secondaryLabel)).frame(maxWidth: .infinity, alignment: .leading)
                            if micro.totalDayCount > 0 {
                                Text("Reported on \(micro.reportedDayCount) of \(micro.totalDayCount) days")
                                    .appFont(size: 10)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                Text("Averages exclude days when food sources did not report that nutrient. Missing values are not counted as zero.")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.top, 8)
            } else if !viewModel.isLoading {
                Text("No micronutrient data available for this period").foregroundColor(Color(UIColor.secondaryLabel)).padding()
            }
        }
        .asCard()
    }
    
    private var citationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source information")
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

    var body: some View {
        ScrollView {
            VStack {
                calorieChartCard
                macroChartCard
                micronutrientReportCard
                citationSection
            }
            .padding()
        }
    }
}
