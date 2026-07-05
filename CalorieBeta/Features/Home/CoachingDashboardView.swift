import SwiftUI

struct CoachingDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var appState: AppState
    @State private var lastLoggedPlanSignature: String?
    @State private var showingFoodSearch = false

    private var displayedPlan: AdaptiveCoachingPlan {
        if let plan = insightsService.currentCoachingPlan {
            return plan
        }

        let sleepHours = healthKitViewModel.sleepSamples.map { sample in
            sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
        return InsightsRules.adaptiveCoachingPlan(
            today: dailyLogService.currentDailyLog,
            recentLogs: dailyLogService.currentDailyLog.map { [$0] } ?? [],
            sleepHours: sleepHours,
            goals: InsightsRules.GoalSnapshot(
                calories: goalSettings.calories ?? 0,
                protein: goalSettings.protein,
                weightGoal: goalSettings.goal
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .appFont(size: 24, weight: .bold)
                                .foregroundColor(.purple)
                            Text("Maia's strategy")
                                .appFont(size: 22, weight: .bold)
                        }

                        Text("What I'm seeing in your recent nutrition, sleep, and activity.")
                            .appFont(size: 15)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.bottom, 10)

                        let action = coachAction(for: displayedPlan)
                        AdaptiveCoachPlanCard(
                            plan: displayedPlan,
                            action: action,
                            onPrimaryAction: {
                                handleCoachAction(action, plan: displayedPlan)
                            }
                        )

                        content
                    }
                    .padding(20)
                    .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Coaching dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        DIContainer.shared.analyticsManager.logEvent(
                            "adaptive_coach_refresh_tapped",
                            parameters: nil
                        )
                        insightsService.generateAndFetchInsights()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(insightsService.isLoadingInsights)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                insightsService.generateDailySmartInsight()
                if insightsService.currentInsights.isEmpty && !insightsService.isLoadingInsights {
                    insightsService.generateAndFetchInsights()
                }
                logDisplayedPlanIfNeeded(displayedPlan)
            }
            .onChange(of: insightsService.currentCoachingPlan) { _, newPlan in
                if let newPlan {
                    logDisplayedPlanIfNeeded(newPlan)
                }
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(
                    dailyLog: $dailyLogService.currentDailyLog,
                    onFoodItemLogged: {
                        showingFoodSearch = false
                    },
                    searchContext: "adaptive_coach"
                )
            }
        }
    }

    private func logDisplayedPlanIfNeeded(_ plan: AdaptiveCoachingPlan) {
        let signature = "\(plan.title)|\(plan.confidence)|\(plan.dataPoints.joined(separator: ","))"
        guard signature != lastLoggedPlanSignature else { return }
        lastLoggedPlanSignature = signature

        DIContainer.shared.analyticsManager.logEvent(
            "adaptive_coach_plan_viewed",
            parameters: [
                "title": plan.title,
                "confidence": plan.confidence,
                "data_point_count": plan.dataPoints.count,
                "has_pattern_note": !plan.patternNote.isEmpty
            ]
        )
    }

    private func coachAction(for plan: AdaptiveCoachingPlan) -> CoachAction {
        let combined = "\(plan.title) \(plan.primaryAction) \(plan.trainingMove)".lowercased()
        if combined.contains("workout") || combined.contains("run/walk") || combined.contains("scheduled") {
            return CoachAction(
                title: "Open workouts",
                icon: "figure.strengthtraining.traditional",
                route: .workouts
            )
        }

        if plan.title.localizedCaseInsensitiveContains("baseline") {
            return CoachAction(title: "Log first food", icon: "plus.circle.fill", route: .foodLog)
        }

        if plan.title.localizedCaseInsensitiveContains("protein") {
            return CoachAction(title: "Log protein meal", icon: "fork.knife.circle.fill", route: .foodLog)
        }

        return CoachAction(title: "Log next meal", icon: "fork.knife.circle.fill", route: .foodLog)
    }

    private func handleCoachAction(_ action: CoachAction, plan: AdaptiveCoachingPlan) {
        DIContainer.shared.analyticsManager.logEvent(
            "adaptive_coach_primary_action_tapped",
            parameters: [
                "title": plan.title,
                "route": action.route.rawValue,
                "confidence": plan.confidence
            ]
        )

        switch action.route {
        case .foodLog:
            showingFoodSearch = true
        case .workouts:
            dismiss()
            appState.selectedTab = 2
        }
    }

    @ViewBuilder
    private var content: some View {
        if insightsService.isLoadingInsights && insightsService.currentInsights.isEmpty {
            HStack(spacing: 12) {
                ProgressView().tint(.blue)
                Text("Reviewing your recent data")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
        } else if insightsService.currentInsights.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .appFont(size: 28)
                    .foregroundColor(.purple)
                Text("Keep logging and I'll build your strategy")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text("A few days of meals, workouts, and sleep give me enough to spot patterns and tailor your targets.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(insightsService.currentInsights.sorted { $0.priority > $1.priority }) { insight in
                    let style = Self.style(for: insight.category)
                    CoachingInsightRow(
                        icon: style.icon,
                        title: insight.title,
                        description: insight.message,
                        color: style.color
                    )
                }
            }
        }
    }

    private static func style(for category: UserInsight.InsightCategory) -> (icon: String, color: Color) {
        switch category {
        case .hydration: return ("drop.fill", .blue)
        case .macroBalance: return ("chart.pie.fill", .purple)
        case .microNutrient, .fiberIntake: return ("leaf.fill", .accentPositive)
        case .mealTiming: return ("clock.fill", .orange)
        case .consistency: return ("flame.fill", .red)
        case .postWorkout, .exerciseSynergy: return ("figure.strengthtraining.traditional", .accentPositive)
        case .foodVariety: return ("square.grid.3x3.fill", .teal)
        case .positiveReinforcement: return ("star.fill", .yellow)
        case .sugarAwareness: return ("cube.fill", .pink)
        case .saturatedFat: return ("drop.triangle.fill", .orange)
        case .smartSuggestion: return ("lightbulb.fill", .yellow)
        case .sleep: return ("moon.zzz.fill", .indigo)
        case .calorieFluctuation: return ("waveform.path.ecg", .orange)
        case .weekendTrends: return ("calendar", .blue)
        default: return ("fork.knife", .blue)
        }
    }
}

private enum CoachActionRoute: String {
    case foodLog = "food_log"
    case workouts
}

private struct CoachAction {
    let title: String
    let icon: String
    let route: CoachActionRoute
}

private struct AdaptiveCoachPlanCard: View {
    let plan: AdaptiveCoachingPlan
    let action: CoachAction
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "target")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.accentPositive)
                    .frame(width: 42, height: 42)
                    .background(Color.accentPositive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(plan.title)
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text(plan.confidence)
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.secondarySystemFill), in: Capsule())
                    }

                    Text(plan.subtitle)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    if !plan.patternNote.isEmpty {
                        Text(plan.patternNote)
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CoachMoveRow(icon: "checkmark.circle.fill", title: "Next move", text: plan.primaryAction, color: .accentPositive)
                CoachMoveRow(icon: "fork.knife", title: "Food", text: plan.mealMove, color: .orange)
                CoachMoveRow(icon: "figure.strengthtraining.traditional", title: "Training", text: plan.trainingMove, color: .blue)
                CoachMoveRow(icon: "moon.zzz.fill", title: "Recovery", text: plan.recoveryMove, color: .indigo)
            }

            if !plan.dataPoints.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(plan.dataPoints, id: \.self) { point in
                        Text(point)
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.secondarySystemFill), in: Capsule())
                    }
                }
            }

            Button(action: onPrimaryAction) {
                Label(action.title, systemImage: action.icon)
                    .appFont(size: 14, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.title)
        }
        .padding(16)
        .background(Color.backgroundPrimary.opacity(0.65), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CoachMoveRow: View {
    let icon: String
    let title: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text(text)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return layout(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, items: [(index: Int, frame: CGRect)]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var items: [(Int, CGRect)] = []
        let maxWidth = max(width, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            items.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), items)
    }
}

private struct CoachingInsightRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(Color(UIColor.secondarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
    }
}
