import SwiftUI
import Charts
import FirebaseAuth

struct NutritionProgressView: View {
    var dailyLog: DailyLog
    @ObservedObject var goal: GoalSettings
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var dailyLogService: DailyLogService
    var insight: UserInsight?

    private let swipeThreshold: CGFloat = 50
    private let totalViews = 4

    @State private var showingAudit = false

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
        let consistencyStatus = dailyLog.calorieConsistencyStatus()

        VStack(spacing: 16) {
            ZStack {
                 switch goal.nutritionViewIndex {
                 case 0:
                    summaryView(calories: totalCalories, caloriesGoal: caloriesGoal, caloriesPercentage: caloriesPercentage, protein: protein, proteinGoal: proteinGoal, fats: fats, fatsGoal: fatsGoal, carbs: carbs, carbsGoal: carbsGoal)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 case 1:
                     bubblesView(calories: totalCalories, caloriesGoal: caloriesGoal, caloriesPercentage: caloriesPercentage, protein: protein, proteinGoal: proteinGoal, proteinPercentage: proteinPercentage, fats: fats, fatsGoal: fatsGoal, fatsPercentage: fatsPercentage, carbs: carbs, carbsGoal: carbsGoal, carbsPercentage: carbsPercentage)
                     .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 case 2:
                     HorizontalBarChartView(dailyLog: dailyLog, goal: goal)
                      .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 case 3:
                     MicronutrientProgressView(dailyLog: dailyLog, goalSettings: goal)
                         .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                 default: EmptyView()
                 }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(minHeight: 190)
            .background(Color.backgroundSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        guard abs(horizontalDistance) > abs(verticalDistance) * 1.35,
                              abs(horizontalDistance) > swipeThreshold else {
                            return
                        }

                        withAnimation(.easeInOut(duration: 0.3)) {
                            if horizontalDistance < 0 {
                                goal.nutritionViewIndex = (goal.nutritionViewIndex + 1) % totalViews
                            } else {
                                goal.nutritionViewIndex = (goal.nutritionViewIndex - 1 + totalViews) % totalViews
                            }
                        }
                    }
            )

            DotIndicator(goalSettings: goal)
                .padding(.top, -4)
                .padding(.bottom, 4)

            if consistencyStatus.hasMeaningfulMismatch {
                Button {
                    showingAudit = true
                } label: {
                    NutritionConsistencyNoticeCard(status: consistencyStatus, style: .compact)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 8)
                .padding(.top, -6)
                .sheet(isPresented: $showingAudit) {
                    NutritionAuditView(dailyLog: dailyLog, dailyLogBinding: $dailyLogService.currentDailyLog, date: dailyLog.date)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func summaryView(calories: Double, caloriesGoal: Double, caloriesPercentage: Double, protein: Double, proteinGoal: Double, fats: Double, fatsGoal: Double, carbs: Double, carbsGoal: Double) -> some View {
        HStack(spacing: 16) {
            VStack {
                Text("Calories")
                    .appFont(size: 14, weight: .medium)
                ProgressBubble(
                    value: calories,
                    goal: caloriesGoal,
                    percentage: caloriesPercentage,
                    label: "",
                    unit: "cal",
                    color: .red
                )
            }

            VStack(spacing: 12) {
                MacroProgressRow(
                    label: "Protein",
                    value: protein,
                    goal: proteinGoal,
                    unit: "g",
                    color: .accentProtein
                )
                MacroProgressRow(
                    label: "Carbs",
                    value: carbs,
                    goal: carbsGoal,
                    unit: "g",
                    color: .accentCarbs
                )
                MacroProgressRow(
                    label: "Fats",
                    value: fats,
                    goal: fatsGoal,
                    unit: "g",
                    color: .accentFats
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 120)
    }

    @ViewBuilder
    private func bubblesView(calories: Double, caloriesGoal: Double, caloriesPercentage: Double, protein: Double, proteinGoal: Double, proteinPercentage: Double, fats: Double, fatsGoal: Double, fatsPercentage: Double, carbs: Double, carbsGoal: Double, carbsPercentage: Double) -> some View {
         HStack(spacing: 15) {
             ProgressBubble(value: calories, goal: caloriesGoal, percentage: caloriesPercentage, label: "Calories", unit: "cal", color: .red, isSmall: true)
             ProgressBubble(value: protein, goal: proteinGoal, percentage: proteinPercentage, label: "Protein", unit: "g", color: .accentProtein, isSmall: true)
             ProgressBubble(value: fats, goal: fatsGoal, percentage: fatsPercentage, label: "Fats", unit: "g", color: .accentFats, isSmall: true)
             ProgressBubble(value: carbs, goal: carbsGoal, percentage: carbsPercentage, label: "Carbs", unit: "g", color: .accentCarbs, isSmall: true)
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
    var isSmall: Bool = false

    private var remaining: Double {
        goal - value
    }

    private var remainingMagnitude: Double {
        abs(remaining)
    }

    private var remainingLabel: String {
        remaining >= 0 ? "Remaining" : "Over"
    }

    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(lineWidth: isSmall ? 6 : 10).opacity(0.15).foregroundColor(color)
                Circle()
                    .trim(from: 0, to: CGFloat(percentage))
                    .stroke(style: StrokeStyle(lineWidth: isSmall ? 6 : 10, lineCap: .round, lineJoin: .round))
                    .foregroundColor(color)
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.easeInOut(duration: 0.75), value: percentage)

                VStack {
                    if isSmall {
                        Text("\(String(format: "%.0f", value))")
                            .appFont(size: isSmall ? 15 : 24, weight: isSmall ? .medium : .bold)
                            .foregroundColor(.textPrimary)
                        Text("/ \(String(format: "%.0f", goal)) \(unit)")
                             .appFont(size: isSmall ? 10 : 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    } else {
                        Text("\(String(format: "%.0f", remainingMagnitude))")
                            .appFont(size: 28, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text(remainingLabel)
                            .appFont(size: 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
            .frame(width: isSmall ? 70 : 100, height: isSmall ? 70 : 100)

            if !isSmall {
                Text("\(String(format: "%.0f", value)) / \(String(format: "%.0f", goal)) \(unit)")
                     .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            } else if !label.isEmpty {
                Text(label)
                    .appFont(size: 12)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
        }
    }
}

struct NutritionConsistencyNoticeCard: View {
    enum Style {
        case compact
        case detail
    }

    let status: NutritionCalorieConsistency.Status
    var style: Style = .detail
    var messageOverride: String? = nil

    private var title: String {
        style == .compact ? "Calorie check" : "Calories and macros differ"
    }

    private var message: String {
        if let messageOverride {
            return messageOverride
        }
        let macroCalories = Int(status.macroDerivedCalories.rounded())
        let mismatch = Int(status.mismatchAmount.rounded())
        return "Macros imply \(macroCalories) cal, \(mismatch) cal \(status.directionText) than logged. Logged calories stay official."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: style == .compact ? 13 : 15, weight: .bold))
                .foregroundColor(.orange)
                .frame(width: style == .compact ? 24 : 30, height: style == .compact ? 24 : 30)
                .background(Color.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: style == .compact ? 12 : 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(message)
                    .font(.system(size: style == .compact ? 11 : 12, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(style == .compact ? 10 : 14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: style == .compact ? 14 : 18, style: .continuous))
    }
}

private struct DotIndicator: View {
    @ObservedObject var goalSettings: GoalSettings
    let totalDots: Int = 4
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalDots, id: \.self) { index in
                Circle()
                    .frame(width: index == goalSettings.nutritionViewIndex ? 10 : 6, height: index == goalSettings.nutritionViewIndex ? 10 : 6)
                    .foregroundColor(index == goalSettings.nutritionViewIndex ? Color.brandPrimary : Color(UIColor.secondaryLabel).opacity(0.5))
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            goalSettings.nutritionViewIndex = index
                        }
                    }
            }
        }
    }
}
