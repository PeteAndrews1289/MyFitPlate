import MyFitPlateCore

import SwiftUI

struct MetabolismDashboardView: View {
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading: Bool

    private let loadsData: Bool

    init(loadsData: Bool = true) {
        self.loadsData = loadsData
        _isLoading = State(initialValue: loadsData)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing 21-day metabolism trends...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    dashboardContent
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Adaptive metabolism")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("adaptive_tdee_screen")
        .task {
            guard loadsData else {
                isLoading = false
                return
            }
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
            AppScreenHeader(
                eyebrow: "21-day evidence",
                title: "Adaptive TDEE estimate",
                subtitle: "Estimated from your logged food and weight trend. More consistent data usually produces a steadier estimate."
            )

            if adaptiveGoalService.dataConfidence == .insufficient {
                let weighInsLeft = max(0, 7 - adaptiveGoalService.recentWeighInCount)
                let logsLeft = max(0, 10 - adaptiveGoalService.recentValidLogCount)
                let daysToGo = max(weighInsLeft, logsLeft)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .foregroundColor(AppPalette.effort)
                        Text(adaptiveGoalService.tdeeGuardrailMessage == nil ? "Building your estimate" : "Check your food logs")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }

                    Text(adaptiveGoalService.tdeeGuardrailMessage ?? (daysToGo > 0
                         ? "About \(daysToGo) more complete day\(daysToGo == 1 ? "" : "s") of logging until your first estimate appears."
                         : "Almost there, keep logging to unlock your estimate."))
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    AdaptiveProgressRow(label: "Weight check-ins", current: adaptiveGoalService.recentWeighInCount, goal: 7, icon: "scalemass.fill")
                    AdaptiveProgressRow(label: "Complete food-log days", current: adaptiveGoalService.recentValidLogCount, goal: 10, icon: "fork.knife")

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .appFont(size: 12)
                            .foregroundColor(AppPalette.caution)
                        Text("Weigh in regularly (ideally daily, around the same time) and log your food honestly. Your estimate is only as accurate as the data you give it.")
                            .appFont(size: 13)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .appSurface(.quiet)
            }

            if let guardrailMessage = adaptiveGoalService.tdeeGuardrailMessage,
               adaptiveGoalService.dataConfidence != .insufficient {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("Estimate not ready to use", systemImage: "exclamationmark.shield.fill")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.caution)

                    Text(guardrailMessage)
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.group) {
                        Text("\(adaptiveGoalService.recentValidLogCount)/21 complete")
                        Text("\(adaptiveGoalService.partialLogCount) partial")
                        Text("\(adaptiveGoalService.recentWeighInCount) weigh-ins")
                    }
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppSpacing.compact)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityIdentifier("adaptive_tdee_guardrail")
            }

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(adaptiveGoalService.dataConfidence.rawValue)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.1), in: Capsule())
                        
                        if let tdee = validTDEE {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Int(tdee.rounded()).formatted())
                                    .appFont(size: 48, weight: .heavy)
                                    .foregroundColor(.textPrimary)
                                Text(" cal/day")
                                    .appFont(size: 20, weight: .bold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        } else {
                            Text("Needs data")
                                .appFont(size: 32, weight: .heavy)
                                .foregroundColor(.textPrimary)
                        }
                    }
                    
                    Spacer()
                }

                Divider()

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Average intake (21 days)",
                        value: averageIntakeText,
                        accent: .brandPrimary
                    ),
                    AppMetricItem(
                        label: "Weight trend",
                        value: weightTrendText,
                        accent: weightTrendAccent
                    )
                ])
            }
            .appSurface(.interpreted)

            Button(action: {
                HapticManager.instance.feedback(.light)
                goalSettings.calorieGoalMethod = .dynamicTDEE
                goalSettings.recalculateAllGoals()
                dismiss()
            }) {
                Text("Use adaptive TDEE")
            }
            .disabled(!canUseAdaptiveTDEE)
            .buttonStyle(AppActionButtonStyle(.primary))

            if !canUseAdaptiveTDEE {
                Text("Adaptive TDEE stays unavailable until the food-log and weigh-in evidence is consistent enough to trust.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Why use this estimate?", systemImage: "sparkles")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                
                Text("Standard equations estimate energy needs from measurements such as height, weight, and age. Adaptive TDEE also considers your logged intake and weight trend, which can make the estimate more personal over time. It is still an estimate, and missing or inconsistent logs can move it.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appSurface(.quiet)
        }
    }

    private var validTDEE: Double? {
        guard let value = adaptiveGoalService.calculatedTDEE, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    private var canUseAdaptiveTDEE: Bool {
        adaptiveGoalService.isEstimateActionable && validTDEE != nil
    }

    private var averageIntakeText: String {
        guard let value = adaptiveGoalService.last21DaysCalorieAverage,
              value.isFinite,
              value >= 0 else {
            return "--"
        }
        return "\(Int(value.rounded()).formatted()) cal"
    }

    private var weightTrendText: String {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay, rate.isFinite else {
            return "--"
        }
        let weeklyRate = BodyUnits.weightDisplayValue(lbs: rate * 7, metric: useMetric)
        let sign = weeklyRate > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", weeklyRate)) \(BodyUnits.weightUnit(metric: useMetric))/wk"
    }

    private var weightTrendAccent: Color {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay, rate.isFinite else {
            return Color(UIColor.secondaryLabel)
        }
        return AppPalette.effort
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
                    .foregroundColor(AppPalette.effort)
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
                    Capsule().fill(Color(UIColor.secondarySystemFill))
                    Capsule().fill(current >= goal ? AppPalette.positive : AppPalette.effort)
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
                        .foregroundColor(AppPalette.effort)
                    Text("Adaptive metabolism")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                }
                
                Text("Review your adaptive TDEE estimate and weight trend.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(AppSpacing.group)
        .appSurface(.quiet, padding: 0)
    }
}
