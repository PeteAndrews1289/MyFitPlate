import SwiftUI
import Charts

struct HorizontalBarChartView: View {
    var dailyLog: DailyLog
    @ObservedObject var goal: GoalSettings

    var body: some View {
        if let caloriesGoal = goal.calories {
            let totalCalories = max(0, dailyLog.totalCalories())
            let totalMacros = dailyLog.totalMacros()
            let protein = max(0, totalMacros.protein)
            let fats = max(0, totalMacros.fats)
            let carbs = max(0, totalMacros.carbs)

            let proteinGoal = max(goal.protein, 1)
            let fatsGoal = max(goal.fats, 1)
            let carbsGoal = max(goal.carbs, 1)
            let effectiveCaloriesGoal = max(caloriesGoal, 1)

            let caloriesPercentage = min((totalCalories / effectiveCaloriesGoal) * 100, 100)
            let proteinPercentage = min((protein / proteinGoal) * 100, 100)
            let fatsPercentage = min((fats / fatsGoal) * 100, 100)
            let carbsPercentage = min((carbs / carbsGoal) * 100, 100)

            Chart {
                BarMark(
                    x: .value("Calories", caloriesPercentage),
                    y: .value("Type", "Calories")
                )
                .foregroundStyle(.red)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(Int(totalCalories)) / \(Int(caloriesGoal)) cal")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                BarMark(
                    x: .value("Protein", proteinPercentage),
                    y: .value("Type", "Protein")
                )
                .foregroundStyle(.blue)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(Int(protein)) / \(Int(goal.protein))g")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                BarMark(
                    x: .value("Fats", fatsPercentage),
                    y: .value("Type", "Fats")
                )
                .foregroundStyle(.green)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(Int(fats)) / \(Int(goal.fats))g")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                BarMark(
                    x: .value("Carbs", carbsPercentage),
                    y: .value("Type", "Carbs")
                )
                .foregroundStyle(.orange)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(Int(carbs)) / \(Int(goal.carbs))g")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartXAxisLabel("Percentage of Goal (%)", position: .bottom, alignment: .center, spacing: 10)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisTick()
                    AxisValueLabel(horizontalSpacing: 5)
                }
            }
            .chartXScale(domain: 0...100)
            .frame(height: 200)
            .padding()

        } else {
            Text("Loading data...")
                .foregroundColor(.gray)
                .frame(height: 200)
                .padding()
        }
    }
}
