import SwiftUI
import Charts
import FirebaseAuth

struct NutritionProgressView: View {
    var dailyLog: DailyLog
    @ObservedObject var goal: GoalSettings
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dailyLogService: DailyLogService
    var insight: UserInsight?

    @GestureState private var dragOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 50
    private let totalViews = 3

    var body: some View {
        let totalCalories = max(0, dailyLog.totalCalories())
        let totalMacros = dailyLog.totalMacros()
        let protein = max(0, totalMacros.protein)
        let fats = max(0, totalMacros.fats)
        let carbs = max(0, totalMacros.carbs)
        let caloriesGoal = max(goal.calories ?? 1, 1)
        let proteinGoal = max(goal.protein, 1)
        let fatsGoal = max(goal.fats, 1)
        let carbsGoal = max(goal.carbs, 1)
        let caloriesPercentage = min(totalCalories / caloriesGoal, 1.0)
        let proteinPercentage = min(protein / proteinGoal, 1.0)
        let fatsPercentage = min(fats / fatsGoal, 1.0)
        let carbsPercentage = min(carbs / carbsGoal, 1.0)
        
        VStack(spacing: 16) {
            ZStack {
                 switch goal.nutritionViewIndex {
                 case 0:
                     bubblesView(calories: totalCalories, caloriesGoal: caloriesGoal, caloriesPercentage: caloriesPercentage, protein: protein, proteinGoal: proteinGoal, proteinPercentage: proteinPercentage, fats: fats, fatsGoal: fatsGoal, fatsPercentage: fatsPercentage, carbs: carbs, carbsGoal: carbsGoal, carbsPercentage: carbsPercentage)
                     .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 case 1:
                     HorizontalBarChartView(dailyLog: dailyLog, goal: goal)
                      .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 case 2:
                     MicronutrientProgressView(dailyLog: dailyLog, goalSettings: goal)
                         .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 default: EmptyView()
                 }
             }
            .padding(.horizontal, 8)
            .frame(minHeight: 180)
            .background(colorScheme == .dark ? Color(.secondarySystemBackground).opacity(0.5) : Color.white.opacity(0.8))
            .cornerRadius(12)
            .clipped()
            .gesture( DragGesture().updating($dragOffset) { value, state, _ in state = value.translation.width }.onEnded { value in let swipeDistance = value.translation.width; if abs(swipeDistance) > swipeThreshold { withAnimation(.easeInOut(duration: 0.3)) { if swipeDistance < 0 { goal.nutritionViewIndex = (goal.nutritionViewIndex + 1) % totalViews } else { goal.nutritionViewIndex = (goal.nutritionViewIndex - 1 + totalViews) % totalViews } } } } )
            .offset(x: dragOffset / 3)

            DotIndicator(goalSettings: goal)
                .padding(.top, -4)
                .padding(.bottom, 4)

            WaterTrackingCardView(date: dailyLog.date, insight: insight)
                .padding(.horizontal)

        }.padding(.bottom, 8)
    }

    @ViewBuilder
    private func bubblesView(calories: Double, caloriesGoal: Double, caloriesPercentage: Double, protein: Double, proteinGoal: Double, proteinPercentage: Double, fats: Double, fatsGoal: Double, fatsPercentage: Double, carbs: Double, carbsGoal: Double, carbsPercentage: Double) -> some View {
         HStack(spacing: 15) {
             ProgressBubble(value: calories, goal: caloriesGoal, percentage: caloriesPercentage, label: "Calories", unit: "cal", color: .red)
             ProgressBubble(value: protein, goal: proteinGoal, percentage: proteinPercentage, label: "Protein", unit: "g", color: .blue)
             ProgressBubble(value: fats, goal: fatsGoal, percentage: fatsPercentage, label: "Fats", unit: "g", color: .green)
             ProgressBubble(value: carbs, goal: carbsGoal, percentage: carbsPercentage, label: "Carbs", unit: "g", color: .orange)
         }.padding(.horizontal, 8).frame(maxWidth: .infinity)
    }
}

struct ProgressBubble: View {
    let value: Double
    let goal: Double
    let percentage: Double
    let label: String
    let unit: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(lineWidth: 6).opacity(0.2).foregroundColor(color)
                Circle().trim(from: 0, to: CGFloat(percentage)).stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)).foregroundColor(color).rotationEffect(.degrees(-90)).animation(.easeInOut, value: percentage)
                VStack {
                    Text("\(String(format: "%.0f", value))")
                        .font(.callout.weight(.medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Text("/ \(String(format: "%.0f", goal)) \(unit)")
                         .font(.caption2)
                        .foregroundColor(.gray)
                }
            }.frame(width: 70, height: 70)
            Text(label).font(.caption).foregroundColor(colorScheme == .dark ? .white : .black).lineLimit(1)
        }
    }
}

private struct DotIndicator: View {
    @ObservedObject var goalSettings: GoalSettings
    let totalDots: Int = 3
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalDots, id: \.self) { index in
                Circle()
                    .frame(width: index == goalSettings.nutritionViewIndex ? 10 : 6, height: index == goalSettings.nutritionViewIndex ? 10 : 6)
                    .foregroundColor(index == goalSettings.nutritionViewIndex ? Color.accentColor : Color.gray.opacity(0.5))
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            goalSettings.nutritionViewIndex = index
                        }
                    }
            }
        }
    }
}
