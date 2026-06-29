import SwiftUI
import Charts

struct MetabolismDashboardView: View {
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing 21-Day Metabolism Trends...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    dashboardContent
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Adaptive Metabolism")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let userID = DIContainer.shared.authService.currentUserID else {
                isLoading = false
                return
            }
            await adaptiveGoalService.fetchAndCalculate(userID: userID, goalSettings: goalSettings, dailyLogService: dailyLogService)
            isLoading = false
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Your True TDEE")
                    .appFont(size: 20, weight: .semibold)
                    .foregroundColor(.textPrimary)
                
                Text("Total Daily Energy Expenditure is the actual number of calories your body burns, calculated by analyzing your weight trend and food intake over the last 3 weeks.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if adaptiveGoalService.dataConfidence == .insufficient {
                let weighInsLeft = max(0, 7 - adaptiveGoalService.recentWeighInCount)
                let logsLeft = max(0, 10 - adaptiveGoalService.recentLogCount)
                let daysToGo = max(weighInsLeft, logsLeft)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .foregroundColor(.brandPrimary)
                        Text("Building your estimate")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }

                    Text(daysToGo > 0
                         ? "About \(daysToGo) more day\(daysToGo == 1 ? "" : "s") of logging until your first estimate appears."
                         : "Almost there — keep logging to unlock your estimate.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    AdaptiveProgressRow(label: "Weight check-ins", current: adaptiveGoalService.recentWeighInCount, goal: 7, icon: "scalemass.fill")
                    AdaptiveProgressRow(label: "Days of food logged", current: adaptiveGoalService.recentLogCount, goal: 10, icon: "fork.knife")

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .appFont(size: 12)
                            .foregroundColor(.orange)
                        Text("Weigh in regularly (ideally daily, around the same time) and log your food honestly — your estimate is only as accurate as the data you give it.")
                            .appFont(size: 13)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .background(Color.brandPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            // Calculation Card
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(adaptiveGoalService.dataConfidence.rawValue)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.1), in: Capsule())
                        
                        if let tdee = adaptiveGoalService.calculatedTDEE {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(tdee))")
                                    .appFont(size: 48, weight: .heavy)
                                    .foregroundColor(.textPrimary)
                                Text(" kcal")
                                    .appFont(size: 20, weight: .bold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        } else {
                            Text("Needs Data")
                                .appFont(size: 32, weight: .heavy)
                                .foregroundColor(.textPrimary)
                        }
                    }
                    
                    Spacer()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avg Intake (21d)")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        Text(adaptiveGoalService.last21DaysCalorieAverage != nil ? "\(Int(adaptiveGoalService.last21DaysCalorieAverage!)) kcal" : "--")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Weight Trend")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        if let rate = adaptiveGoalService.weightChangeRatePerDay {
                            let isLosing = rate < 0
                            Text("\(isLosing ? "" : "+")\(String(format: "%.2f", BodyUnits.weightDisplayValue(lbs: rate * 7, metric: useMetric))) \(BodyUnits.weightUnit(metric: useMetric))/wk")
                                .appFont(size: 16, weight: .bold)
                                .foregroundColor(isLosing ? .brandPrimary : .orange)
                        } else {
                            Text("--")
                                .appFont(size: 16, weight: .bold)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)

            // Action Button
            Button(action: {
                HapticManager.instance.feedback(.light)
                goalSettings.calorieGoalMethod = .dynamicTDEE
                goalSettings.recalculateAllGoals()
                dismiss()
            }) {
                Text("Use Adaptive TDEE for Goals")
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        adaptiveGoalService.dataConfidence == .insufficient ? Color.gray : Color.brandPrimary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .disabled(adaptiveGoalService.dataConfidence == .insufficient)
            .opacity(adaptiveGoalService.dataConfidence == .insufficient ? 0.6 : 1.0)
            .buttonStyle(.plain)

            // Explainer
            VStack(alignment: .leading, spacing: 10) {
                Label("Why is this better?", systemImage: "sparkles")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                
                Text("Standard calculators (like the Mifflin-St Jeor equation) guess your metabolism based on height, weight, and age. \n\nAdaptive TDEE looks at what you actually eat and how your weight actually responds, finding your exact metabolic rate. The more consistently you log, the more accurate this becomes.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.accentPositive.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct AdaptiveProgressRow: View {
    let label: String
    let current: Int
    let goal: Int
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.brandPrimary)
                Text(label)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(min(current, goal)) / \(goal)")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(current >= goal ? .accentPositive : Color(UIColor.secondaryLabel))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.brandPrimary.opacity(0.12))
                    Capsule().fill(current >= goal ? Color.accentPositive : Color.brandPrimary)
                        .frame(width: geo.size.width * CGFloat(min(Double(current) / Double(max(goal, 1)), 1.0)))
                }
            }
            .frame(height: 7)
        }
    }
}

struct MetabolismReportCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.brandPrimary)
                    Text("Adaptive Metabolism")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                }
                
                Text("Analyze your true TDEE and metabolism trend.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(16)
        .asCard()
    }
}
