import SwiftUI


struct MacroProgressRow: View {
    let label: String
    let value: Double
    let goal: Double
    let unit: String
    let color: Color

    private var progress: Double {
    
        return goal > 0 ? (value / goal) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .appFont(size: 14, weight: .medium)
                Spacer()
                Text("\(Int(value)) / \(Int(goal)) \(unit)")
                    .appFont(size: 12, weight: .regular)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
    }
}



struct HorizontalBarChartView: View {
    var dailyLog: DailyLog
    @ObservedObject var goal: GoalSettings

    var body: some View {
      
        if goal.calories != nil {
            let totalMacros = dailyLog.totalMacros()
            
            VStack(spacing: 16) {
                MacroProgressRow(
                    label: "Calories",
                    value: dailyLog.totalCalories(),
                    goal: goal.calories ?? 1,
                    unit: "kcal",
                    color: .red
                )
                MacroProgressRow(
                    label: "Protein",
                    value: totalMacros.protein,
                    goal: goal.protein,
                    unit: "g",
                    color: .accentProtein
                )
                MacroProgressRow(
                    label: "Fats",
                    value: totalMacros.fats,
                    goal: goal.fats,
                    unit: "g",
                    color: .accentFats
                )
                MacroProgressRow(
                    label: "Carbs",
                    value: totalMacros.carbs,
                    goal: goal.carbs,
                    unit: "g",
                    color: .accentCarbs
                )
            }
            .padding(.vertical)
            
        } else {
           
            ProgressView("Loading Goals...")
                .frame(height: 180)
        }
    }
}
