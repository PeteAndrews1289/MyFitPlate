import MyFitPlateCore
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
    @EnvironmentObject private var workoutService: WorkoutService
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @State private var ownerID: String?
    @State private var isOpeningAction = false
    @State private var actionMessage: String?
    @State private var actionOutcome: CoachingActionOutcome?
    @State private var actionHistory: [CoachingActionOutcome] = []
    @State private var feedbackHistory: [CoachingFeedback] = []
    private struct FeedbackReview: Identifiable {
        let id = UUID()
        let ownerID: String
        let plan: AdaptiveCoachingPlan
        let actionReviewID: UUID?
    }
    @State private var feedbackReview: FeedbackReview?
    @State private var workoutReview: WorkoutNextSessionContext?
    @State private var lighterWeekReview: CoachingActionReview?
    @State private var foodIDsBeforeReview = Set<String>()
    @State private var nextScheduledRun: TrainingRunCommitment?
    private struct ScheduledRunReview: Identifiable {
        let id = UUID()
        let ownerID: String
        let commitment: TrainingRunCommitment
    }
    @State private var scheduledRunReview: ScheduledRunReview?

    private var displayedPlan: AdaptiveCoachingPlan {
        CoachingFeedbackRules.applying(feedbackHistory, to: basePlan,
            userID: DIContainer.shared.authService.currentUserID ?? "")
    }

    private var basePlan: AdaptiveCoachingPlan {
        if let plan = insightsService.currentCoachingPlan {
            return plan
        }

        return InsightsRules.adaptiveCoachingPlan(
            today: dailyLogService.currentDailyLog,
            recentLogs: dailyLogService.currentDailyLog.map { [$0] } ?? [],
            recovery: healthKitViewModel.coachingRecoveryEvidence(),
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
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    let action = coachAction(for: displayedPlan)
                    AdaptiveCoachPlanCard(
                        plan: displayedPlan,
                        action: action,
                        onPrimaryAction: {
                            handleCoachAction(action, plan: displayedPlan)
                        }
                    )
                    .disabled(isOpeningAction)
                    Button("Does this fit today?", systemImage: "bubble.left") {
                        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
                        feedbackReview = .init(ownerID: ownerID, plan: displayedPlan, actionReviewID: actionOutcome?.id)
                    }
                    .accessibilityIdentifier("coaching_feedback")
                    if isOpeningAction { ProgressView("Opening your review…") }
                    if let actionMessage {
                        Text(actionMessage).appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("coaching_action_status")
                    }
                    if workoutService.activeProgram != nil || nextScheduledRun != nil {
                    DisclosureGroup {
                    if workoutService.activeProgram != nil {
                        Button("Review a lighter week", systemImage: "calendar") { openLighterWeek(plan: displayedPlan) }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .disabled(isOpeningAction)
                            .accessibilityIdentifier("coaching_review_lighter_week")
                    }
                    if let run = nextScheduledRun {
                        Button("Review scheduled run", systemImage: "figure.run") { openScheduledRun(run, plan: displayedPlan) }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .disabled(isOpeningAction)
                            .accessibilityIdentifier("coaching_review_scheduled_run")
                    }
                    } label: {
                        Text("Other training options")
                            .accessibilityIdentifier("coaching_training_options")
                    }
                    }
                    if !actionHistory.isEmpty {
                        DisclosureGroup("Recent actions · on this device") {
                            ForEach(actionHistory.prefix(5)) { outcome in
                                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                    Text(outcomeTitle(outcome)).appTextRole(.secondary)
                                    Text(outcome.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, AppSpacing.compact)
                            }
                        }.accessibilityIdentifier("coaching_action_history")
                    }

                    if !feedbackHistory.isEmpty {
                        DisclosureGroup("Your feedback · on this device") {
                            ForEach(feedbackHistory.prefix(8)) { feedback in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feedback.actionTitle).appTextRole(.control)
                                    Text("\(feedback.disposition.title) · \(feedback.barrier.title)").appTextRole(.secondary)
                                    if feedback.result != .notRecorded {
                                        Text("Self-reported result: \(feedback.result.title)").appTextRole(.caption)
                                    }
                                    Text(feedback.recordedAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.caption)
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                    AppSectionHeader(
                        title: "Your recent patterns",
                        subtitle: "The evidence behind today's suggestion."
                    )
                    content
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Daily strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        DIContainer.shared.analyticsManager.logEvent(
                            "adaptive_coach_refresh_tapped",
                            parameters: nil
                        )
                        insightsService.generateAndFetchInsights(requestConsentIfNeeded: true, forceRefresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(insightsService.isLoadingInsights)
                    .accessibilityLabel("Refresh coaching")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                ownerID = DIContainer.shared.authService.currentUserID
                loadActionHistory()
                loadScheduledRun()
                workoutService.fetchRoutinesAndPrograms()
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
            .sheet(item: $feedbackReview) { request in
                CoachingFeedbackSheet(ownerID: request.ownerID, plan: request.plan,
                    actionReviewID: request.actionReviewID) { loadActionHistory() }
            }
            .sheet(item: $workoutReview, onDismiss: closeActionReview) { context in
                WorkoutNextSessionReviewView(context: context, workoutService: workoutService) { accepted in
                    acceptAction(operationID: "program-\(accepted.id ?? context.programID)-\((try? WorkoutBlockRules.structureFingerprint(accepted)) ?? context.structureFingerprint)")
                }
            }
            .sheet(item: $scheduledRunReview, onDismiss: closeActionReview) { request in
                ScheduledRunReviewView(accountID: request.ownerID, commitment: request.commitment) { recordingID in
                    acceptAction(operationID: "run-recording-\(recordingID)")
                }
            }
            .sheet(item: $lighterWeekReview, onDismiss: closeActionReview) { review in
                NavigationStack {
                    WeekRescueView(initialReason: .lighterWeek, coachingReview: review) { operationID in
                        acceptAction(operationID: operationID)
                    }
                }
            }
            .sheet(isPresented: $showingFoodSearch, onDismiss: closeActionReview) {
                FoodSearchView(
                    dailyLog: $dailyLogService.currentDailyLog,
                    onFoodItemLogged: {
                        if let id = dailyLogService.currentDailyLog?.meals.flatMap(\.foodItems).map(\.id)
                            .first(where: { !foodIDsBeforeReview.contains($0) }) {
                            acceptAction(operationID: "food-\(id)")
                        }
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
        switch plan.actionKind {
        case .logFood: return CoachAction(title: "Log food", icon: "plus.circle", route: .foodLog)
        case .reviewMeal: return CoachAction(title: "Review a meal", icon: "fork.knife", route: .meal)
        case .reviewTraining: return CoachAction(title: "Review next targets", icon: "figure.strengthtraining.traditional", route: .targets)
        }
    }

    private func actionDay(for plan: AdaptiveCoachingPlan) throws -> DiaryDayContext {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID,
              let day = DiaryDayContext(userID: ownerID, date: plan.generatedAt) else {
            throw CoachingActionReviewError.accountChanged
        }
        let age = Date().timeIntervalSince(plan.generatedAt)
        guard age >= -1, age <= 1_800, day.isToday() else { throw CoachingActionReviewError.stale }
        return day
    }

    private func handleCoachAction(_ action: CoachAction, plan: AdaptiveCoachingPlan) {
        guard !isOpeningAction else { return }
        do {
            let day = try actionDay(for: plan)
            switch action.route {
            case .foodLog:
                let review = CoachingActionReview(kind: .foodLog, day: day, evidence: plan.dataPoints)
                isOpeningAction = true
                dailyLogService.fetchLog(for: day.userID, day: day) { result in
                    isOpeningAction = false
                    do {
                        try review.validate(userID: DIContainer.shared.authService.currentUserID)
                        let log = try result.get()
                        foodIDsBeforeReview = Set(log.meals.flatMap(\.foodItems).map(\.id))
                        try beginAction(review)
                        showingFoodSearch = true
                    } catch { actionMessage = error.localizedDescription }
                }
            case .meal:
                isOpeningAction = true
                Task { @MainActor in
                    defer { isOpeningAction = false }
                    do {
                        let current = try await mealPlannerService.fetchPlanResult(for: day.originalDate, userID: day.userID).get()
                        _ = try actionDay(for: plan)
                        let logged = Set(dailyLogService.currentDailyLog.flatMap {
                            day.calendar.isDate($0.date, inSameDayAs: day.originalDate) ? $0.meals.flatMap(\.foodItems).map(\.id) : nil
                        } ?? [])
                        let meal = current.flatMap { MealPlanEditingRules.sorted($0.meals).first {
                            !PlannedMealLoggingRules.isLogged($0, date: day.originalDate, loggedFoodIDs: logged)
                        } }
                        let review = CoachingActionReview(kind: .meal, day: day, targetID: meal?.id,
                            targetFingerprint: meal.flatMap { try? PlanFingerprint.make($0) }, evidence: plan.dataPoints)
                        try beginAction(review)
                        guard appState.openMealPlanner(.init(userID: day.userID, date: day.originalDate, meal: meal,
                                                             coachingReview: review)) else { throw CoachingActionReviewError.accountChanged }
                        dismiss()
                    } catch { actionMessage = error.localizedDescription }
                }
            case .targets:
                guard let program = workoutService.activeProgram,
                      let context = try WorkoutNextSessionContext.next(for: program, ownerID: day.userID) else {
                    actionMessage = "There is no upcoming program session to review. Open Train to choose your next block or workout."
                    return
                }
                let review = CoachingActionReview(kind: .sessionTargets, day: day, targetID: context.programID,
                    targetFingerprint: context.structureFingerprint, evidence: plan.dataPoints)
                try beginAction(review)
                workoutReview = context
            }
        } catch { actionMessage = error.localizedDescription }
    }

    private func openLighterWeek(plan: AdaptiveCoachingPlan) {
        do {
            let day = try actionDay(for: plan)
            guard let program = workoutService.activeProgram, program.userID == day.userID,
                  let id = program.id else { throw CoachingActionReviewError.changed }
            let review = CoachingActionReview(kind: .lighterWeek, day: day, targetID: id,
                targetFingerprint: try WorkoutBlockRules.structureFingerprint(program), evidence: plan.dataPoints)
            try beginAction(review)
            lighterWeekReview = review
        } catch { actionMessage = error.localizedDescription }
    }

    private func beginAction(_ review: CoachingActionReview) throws {
        let outcome = CoachingActionOutcome(review: review)
        try CoachingActionHistory().record(outcome, currentUserID: DIContainer.shared.authService.currentUserID)
        actionOutcome = outcome
        actionMessage = nil
        loadActionHistory()
    }

    private func loadScheduledRun() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { nextScheduledRun = nil; return }
        do {
            nextScheduledRun = try TrainingRunCommitmentStore().entries(userID: ownerID)
                .filter { $0.day.date().map { $0 >= Calendar.current.startOfDay(for: Date()) } == true }
                .sorted { ($0.day.date() ?? .distantFuture) < ($1.day.date() ?? .distantFuture) }.first
        } catch { nextScheduledRun = nil }
    }

    private func openScheduledRun(_ run: TrainingRunCommitment, plan: AdaptiveCoachingPlan) {
        do {
            let day = try actionDay(for: plan)
            let review = CoachingActionReview(kind: .scheduledRun, day: day, targetID: run.id,
                targetFingerprint: try PlanFingerprint.make(run), evidence: plan.dataPoints)
            let current = try TrainingRunCommitmentStore().entries(userID: day.userID).first { $0.id == run.id }
            try review.validate(userID: DIContainer.shared.authService.currentUserID,
                currentTargetID: current?.id, currentFingerprint: current.map { try PlanFingerprint.make($0) })
            try beginAction(review)
            scheduledRunReview = .init(ownerID: day.userID, commitment: run)
        } catch { actionMessage = error.localizedDescription; loadScheduledRun() }
    }

    private func acceptAction(operationID: String) {
        guard var outcome = actionOutcome, outcome.review.day.isOwned(by: DIContainer.shared.authService.currentUserID) else { return }
        do {
            try outcome.accept(operationID: operationID)
            try CoachingActionHistory().record(outcome, currentUserID: DIContainer.shared.authService.currentUserID)
            actionOutcome = outcome
            switch outcome.review.kind {
            case .foodLog: actionMessage = "Food accepted on this device."
            case .scheduledRun: actionMessage = "Run started. Recording is in progress."
            default: actionMessage = "Reviewed change saved."
            }
            loadActionHistory()
        } catch { actionMessage = "The operation finished, but its coaching history couldn't be updated." }
    }

    private func closeActionReview() {
        guard var outcome = actionOutcome else { return }
        outcome.close()
        do { try CoachingActionHistory().record(outcome, currentUserID: DIContainer.shared.authService.currentUserID) } catch { actionMessage = "Coaching history couldn't be updated." }
        actionOutcome = nil
        loadActionHistory()
    }

    private func loadActionHistory() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { actionHistory = []; return }
        do {
            actionHistory = try CoachingActionHistory().outcomes(userID: ownerID)
            feedbackHistory = try CoachingFeedbackStore().history(userID: ownerID)
        } catch { actionMessage = "Coaching history is unavailable. Your original logs and plans are unchanged." }
    }

    private func outcomeTitle(_ outcome: CoachingActionOutcome) -> String {
        let title: String
        switch outcome.review.kind {
        case .foodLog: title = "Food"
        case .meal: title = "Meal plan"
        case .sessionTargets: title = "Session targets"
        case .lighterWeek: title = "Lighter week"
        case .scheduledRun: title = "Scheduled run"
        }
        switch outcome.state {
        case .opened: return "\(title) · review opened"
        case .closed: return "\(title) · review closed"
        case .accepted: return outcome.review.kind == .scheduledRun ? "\(title) · recording started" : "\(title) · accepted change"
        }
    }

    @ViewBuilder
    private var content: some View {
        if insightsService.isLoadingInsights && insightsService.currentInsights.isEmpty {
            HStack(spacing: 12) {
                ProgressView().tint(AppPalette.effort)
                Text("Reviewing your recent data")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
            .appSurface(.quiet)
        } else if insightsService.currentInsights.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .appFont(size: 28)
                    .foregroundColor(AppPalette.achievement)
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
            .appSurface(.quiet)
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
        case .hydration: return ("drop.fill", AppPalette.recovery)
        case .macroBalance: return ("chart.pie.fill", AppPalette.effort)
        case .microNutrient, .fiberIntake: return ("leaf.fill", AppPalette.positive)
        case .mealTiming: return ("clock.fill", AppPalette.caution)
        case .consistency: return ("flame.fill", AppPalette.caution)
        case .postWorkout, .exerciseSynergy: return ("figure.strengthtraining.traditional", AppPalette.effort)
        case .foodVariety: return ("square.grid.3x3.fill", AppPalette.positive)
        case .positiveReinforcement: return ("star.fill", AppPalette.achievement)
        case .sugarAwareness: return ("cube.fill", AppPalette.caution)
        case .saturatedFat: return ("drop.triangle.fill", AppPalette.caution)
        case .smartSuggestion: return ("lightbulb.fill", AppPalette.achievement)
        case .sleep: return ("moon.zzz.fill", AppPalette.recovery)
        case .calorieFluctuation: return ("waveform.path.ecg", AppPalette.caution)
        case .weekendTrends: return ("calendar", AppPalette.effort)
        default: return ("fork.knife", AppPalette.effort)
        }
    }
}

private enum CoachActionRoute: String {
    case foodLog = "food_log"
    case meal
    case targets
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
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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

                }
            }

            Text(plan.primaryAction).appTextRole(.control)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onPrimaryAction) {
                Label(action.title, systemImage: action.icon)
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityLabel(action.title)
            .accessibilityIdentifier("coaching_primary_action")

            DisclosureGroup("Food, training & recovery") {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    CoachMoveRow(icon: "fork.knife", title: "Food", text: plan.mealMove, color: .secondary)
                    CoachMoveRow(icon: "figure.strengthtraining.traditional", title: "Training", text: plan.trainingMove, color: AppPalette.effort)
                    CoachMoveRow(icon: "moon.zzz.fill", title: "Recovery", text: plan.recoveryMove, color: AppPalette.recovery)
                }.padding(.top, AppSpacing.compact)
            }
            .appTextRole(.secondary)
            .accessibilityIdentifier("coaching_supporting_moves")

            if !plan.dataPoints.isEmpty {
                DisclosureGroup("Why this suggestion") {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        if !plan.patternNote.isEmpty {
                            Text(plan.patternNote).appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        ForEach(plan.dataPoints, id: \.self) { point in
                            Text(point)
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Recorded food may be incomplete. Sleep and HRV provide context; they do not determine whether a hard workout is right for you.")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, AppSpacing.compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppSpacing.compact)
                }
                .appTextRole(.secondary)
                .accessibilityIdentifier("coaching_evidence")
            }

        }
        .appSurface(.interpreted)
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

private struct CoachingFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let ownerID: String
    let plan: AdaptiveCoachingPlan
    let actionReviewID: UUID?
    let onSaved: () -> Void
    @State private var disposition: CoachingFeedback.Disposition = .tried
    @State private var barrier: CoachingFeedback.Barrier = .none
    @State private var result: CoachingFeedback.Result = .notRecorded
    @State private var note = ""
    @State private var pending: CoachingFeedback?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("The suggestion") { Text(plan.primaryAction) }
                Section("Your experience") {
                    Picker("Response", selection: $disposition) {
                        ForEach(CoachingFeedback.Disposition.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("coaching_feedback_disposition")
                    Picker("What got in the way?", selection: $barrier) {
                        ForEach(CoachingFeedback.Barrier.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if disposition == .tried {
                        Picker("Result", selection: $result) {
                            ForEach(CoachingFeedback.Result.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("coaching_feedback_note")
                }
                .disabled(pending != nil)
                Section {
                    Text("Your feedback helps Maia tailor the next suggestion. Logs and targets stay unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(AppPalette.caution) }
                    Button(pending == nil ? "Save feedback" : "Retry feedback") { save() }
                        .accessibilityIdentifier("coaching_feedback_save")
                        .disabled(note.count > 500)
                }
            }
            .appFormStyle()
            .navigationTitle("Coaching feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        do {
            guard ownerID == DIContainer.shared.authService.currentUserID else { throw CoachingFeedbackError.accountChanged }
            let feedback: CoachingFeedback
            if let pending { feedback = pending } else {
                feedback = try CoachingFeedback(userID: ownerID, plan: plan,
                    disposition: disposition, barrier: barrier,
                    result: disposition == .tried ? result : .notRecorded, note: note, actionReviewID: actionReviewID)
                pending = feedback
            }
            try CoachingFeedbackStore().record(feedback, currentUserID: DIContainer.shared.authService.currentUserID)
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
