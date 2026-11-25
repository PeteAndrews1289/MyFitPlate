import SwiftUI

struct WeeklyCheckInView: View {
    /// The weekly check-in for people on adaptive targets, or the first offer to switch to them.
    enum Mode {
        case checkIn
        case adaptiveOffer
    }

    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @Environment(\.dismiss) var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits: Bool = Locale.current.measurementSystem != .us
    @State private var hasLoggedProposalView = false
    @State private var showingData = false
    @State private var showingDayReview = false
    @State private var checkpoint: WeeklyTargetCheckpoint?
    @State private var decisions: [WeeklyTargetDecision] = []
    @State private var legacyCompletion: Date?
    @State private var reviewError: String?
    @State private var historyNotice: String?
    @State private var isSaving = false
    @State private var ownerID: String?
    private let reviewStore = WeeklyTargetReviewStore()
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canUseEstimate: Bool {
        checkpoint != nil
    }

    private let mode: Mode
    private let onDeclineOffer: () -> Void

    init(mode: Mode = .checkIn, onDeclineOffer: @escaping () -> Void = {}) {
        self.mode = mode
        self.onDeclineOffer = onDeclineOffer
    }

    private var analyticsSurface: String {
        mode == .checkIn ? "weekly_check_in" : "adaptive_offer"
    }

    private var goalProposal: AdaptiveGoalService.WeeklyGoalProposal? { checkpoint?.proposal.explanation }
    private var reviewEvidence: AdaptiveGoalService.ExpenditureSnapshot {
        checkpoint?.proposal.evidence ?? adaptiveGoalService.currentExpenditureSnapshot
    }

    private var averageIntakeText: String {
        guard let average = reviewEvidence.last21DaysCalorieAverage else { return "--" }
        return "\(Int(average.rounded()).formatted()) cal/day"
    }

    private var weightTrendValueText: String {
        guard let rate = reviewEvidence.weightChangeRatePerDay else { return "--" }
        let weeklyRate = BodyUnits.weightDisplayValue(lbs: rate * 7, metric: useMetricBodyUnits)
        return weeklyRate.formatted(.number.precision(.fractionLength(2)))
    }

    private var weightTrendUnitText: String {
        "\(BodyUnits.weightUnit(metric: useMetricBodyUnits)) / week"
    }

    private var calculatedTDEEText: String {
        guard let tdee = reviewEvidence.calculatedTDEE else { return "--" }
        return Int(tdee.rounded()).formatted()
    }

    private var targetDeltaText: String {
        if let goalProposal {
            return goalProposal.summary
        }
        guard let current = goalSettings.calories,
              let calculated = reviewEvidence.calculatedTDEE else {
            return "MyFitPlate will switch your targets to the latest adaptive estimate."
        }

        let delta = Int((calculated - current).rounded())
        if abs(delta) < 50 {
            return "Your current target is already close to the latest estimate."
        }

        return delta > 0
            ? "The adaptive estimate is \(delta) calories higher than your current target."
            : "The adaptive estimate is \(abs(delta)) calories lower than your current target."
    }

    private var coachingReasonText: String {
        guard let rate = reviewEvidence.weightChangeRatePerDay,
              let average = reviewEvidence.last21DaysCalorieAverage else {
            return "This recommendation uses your recent weigh-ins and logged intake once enough data is available."
        }

        let weeklyRate = rate * 7
        let trend: String
        if weeklyRate > 0.15 {
            trend = "weight has been trending up"
        } else if weeklyRate < -0.15 {
            trend = "weight has been trending down"
        } else {
            trend = "weight has been mostly stable"
        }

        return "Over the last 21 days, your average on fully logged days was \(Int(average.rounded()).formatted()) calories and your \(trend)."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    headerSection
                    if let reviewError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(reviewError).foregroundStyle(AppPalette.caution)
                                .accessibilityIdentifier("weekly_checkin_error")
                            if let pending = checkpoint?.submittedDecision {
                                Button("Retry the same decision") { saveDecision(pending.choice) }
                                    .accessibilityIdentifier("weekly_checkin_retry")
                            } else {
                                Button("Refresh proposal") { Task { await refreshProposal() } }
                                    .accessibilityIdentifier("weekly_checkin_refresh")
                            }
                        }.appTextRole(.body).appSurface(.quiet)
                    }
                    if canUseEstimate {
                        recommendationSection
                        actionSection
                        DisclosureGroup("Review the underlying data", isExpanded: $showingData) {
                            statsSection
                            TrendDashboardView(weightHistory: goalSettings.weightHistory)
                        }
                        .accessibilityIdentifier("weekly_checkin_evidence")
                    } else {
                        needsDataSection
                    }
                    Button { showingDayReview = true } label: {
                        Label("Review food-log days", systemImage: "checklist").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("weekly_review_days")
                    decisionHistory
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(mode == .checkIn ? "Weekly check-in" : "Adaptive targets")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .task { await openReview() }
            .onChange(of: adaptiveGoalService.evidenceFingerprint) { _, _ in
                if checkpoint == nil, !isSaving { prepareProposal() }
            }
            .sheet(isPresented: $showingDayReview, onDismiss: {
                Task {
                    if let userID = DIContainer.shared.authService.currentUserID {
                        await adaptiveGoalService.fetchAndCalculate(userID: userID, goalSettings: goalSettings, dailyLogService: dailyLogService, requireServer: true)
                        if checkpoint?.submittedDecision == nil {
                            reviewError = "Food-log evidence was reviewed. Refresh the proposal to see its effect before deciding."
                        }
                    }
                }
            }) { NutritionDayReviewList() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: closeWithoutDecision).disabled(isSaving)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(!canUseEstimate ? "Keep building your estimate" : mode == .checkIn ? "Review your weekly target" : "Your adaptive targets are ready")
                .appFont(size: 21, weight: .bold)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(mode == .checkIn
                 ? "Your food logs and weight trend inform the suggestion. You choose what changes."
                 : "Estimate your daily energy needs from food logs and weight trends.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .padding(.vertical, AppSpacing.compact)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your data")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(reviewEvidence.dataConfidence.rawValue)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(reviewEvidence.dataConfidence.colorName))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(reviewEvidence.dataConfidence.colorName).opacity(0.12), in: Capsule())
            }
            
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))) {
                WeeklyCheckInStatCard(
                    title: "Avg intake",
                    value: averageIntakeText,
                    subtitle: "last 21 days",
                    icon: "fork.knife",
                    color: AppPalette.energy
                )
                
                WeeklyCheckInStatCard(
                    title: "Weight trend",
                    value: weightTrendValueText,
                    subtitle: weightTrendUnitText,
                    icon: "scalemass.fill",
                    color: AppPalette.effort
                )
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Estimated daily burn")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))) {
                    Text(calculatedTDEEText)
                        .appTextRole(.screenTitle)
                        .foregroundColor(.textPrimary)
                    Text(" cal/day")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .appSurface(.interpreted)
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: acceptTargets) {
                Text(mode == .checkIn && goalProposal?.shouldAdjust == false ? "Finish check-in" : "Use suggested target")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(AppPalette.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canUseEstimate || isSaving || checkpoint?.submittedDecision != nil)
            .accessibilityIdentifier("weekly_checkin_accept")
            
            Button(action: mode == .checkIn ? skipCheckIn : declineOffer) {
                Text(mode == .checkIn ? "Keep current targets" : "Not now")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || checkpoint?.submittedDecision != nil)
            .accessibilityIdentifier("weekly_checkin_keep")
            if mode == .checkIn {
                Button("Decide later") { saveDecision(.deferReview) }
                    .disabled(isSaving || checkpoint?.submittedDecision != nil)
                    .accessibilityIdentifier("weekly_checkin_defer")
            }
            if isSaving { ProgressView("Confirming your decision…") }
            if let pending = checkpoint?.submittedDecision, !isSaving, reviewError == nil {
                Button("Confirm pending decision") { saveDecision(pending.choice) }
                    .accessibilityIdentifier("weekly_checkin_retry")
            }
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if let goalProposal {
                proposalDetails(goalProposal)
            } else {
                Text(targetDeltaText).appTextRole(.control)
            }
            DisclosureGroup("Why this target") {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(coachingReasonText).appTextRole(.secondary).foregroundStyle(.secondary)
                    if let goalProposal {
                        ForEach(goalProposal.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "checkmark.circle")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.top, AppSpacing.compact)
            }.appTextRole(.secondary)
            Text(mode == .checkIn
                 ? "Applies these amounts today. Keeping current targets also completes this check-in."
                 : "You can switch back any time in Settings under Calorie goal method.")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.appSurface(.quiet)
    }

    private func proposalDetails(_ proposal: AdaptiveGoalService.WeeklyGoalProposal) -> some View {
        let target = checkpoint?.proposal.after
        let calories = target?.calories ?? proposal.proposedCalories
        let macros = target?.macros ?? proposal.macroGoals
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    if let before = checkpoint?.proposal.before {
                        Text("Current target · \(Int(before.calories.rounded()).formatted()) cal/day")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("weekly_current_calories")
                    }
                    Text(proposal.title)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("\(Int(calories.rounded()).formatted()) cal/day")
                        .appFont(size: 28, weight: .heavy)
                        .foregroundColor(.brandForeground)
                        .accessibilityIdentifier("weekly_proposed_calories")
                }

                Text(proposal.shouldAdjust ? deltaText(for: proposal.calorieDelta) : "No change needed")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(AppPalette.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AppPalette.control, in: Capsule())
            }

            if let frozen = checkpoint?.proposal {
                let date = checkpoint?.submittedDecision?.decidedAt ?? Date()
                Text("Starts " + date.formatted(date: .abbreviated, time: .omitted) + (checkpoint?.submittedDecision == nil ? " if accepted" : ""))
                    .appTextRole(.control)
                Text("Based on " + frozen.evidenceStart.formatted(date: .abbreviated, time: .omitted) + " – " + frozen.evidenceEnd.formatted(date: .abbreviated, time: .omitted))
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            AppMetricStrip(items: [
                .init(label: "Protein", value: "\(Int(macros.protein.rounded())) g", accent: .accentProtein),
                .init(label: "Carbs", value: "\(Int(macros.carbs.rounded())) g", accent: .accentCarbs),
                .init(label: "Fat", value: "\(Int(macros.fats.rounded())) g", accent: .accentFats)
            ])
        }
    }

    private var needsDataSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .appFont(size: 40)
                .foregroundColor(.gray)
            
            Text("Needs more data")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text(adaptiveGoalService.tdeeGuardrailMessage
                 ?? "Keep logging meals and weigh-ins. We need a consistent record before suggesting a target change.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            
            Text("\(adaptiveGoalService.recentValidLogCount) fully logged days · \(adaptiveGoalService.recentWeighInCount) weigh-ins in the last 21 days")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: closeWithoutDecision) {
                Text("Check back later")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .appSurface(.emphasized)
    }
    
    private func acceptTargets() {
        saveDecision(mode == .checkIn && goalProposal?.shouldAdjust == false ? .keep : .accept)
    }
    private func skipCheckIn() { saveDecision(.keep) }
    private func declineOffer() { saveDecision(.deferReview) }
    private func closeWithoutDecision() {
        guard !isSaving else { return }
        dismiss()
    }

    @MainActor
    private func openReview() async {
        guard ownerID == nil, let owner = DIContainer.shared.authService.currentUserID else { return }
        ownerID = owner
        do {
            checkpoint = try reviewStore.load(userID: owner)
            decisions = try reviewStore.history(userID: owner)
            legacyCompletion = try reviewStore.legacyCompletion(userID: owner)
            if checkpoint == nil { prepareProposal() }
            if let existing = checkpoint, existing.submittedDecision == nil {
                do {
                    try existing.proposal.validate(userID: owner, current: goalSettings.makeGoalEditorDraft(),
                                                   evidenceFingerprint: currentEvidenceFingerprint ?? "")
                } catch { reviewError = error.localizedDescription }
            }
        } catch { reviewError = error.localizedDescription }
        do {
            let remote = try await DIContainer.shared.settingsRepository.fetchWeeklyTargetDecisions(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            try reviewStore.mergeHistory(remote, currentUserID: owner)
            decisions = try reviewStore.history(userID: owner)
            if let legacy = try await DIContainer.shared.settingsRepository.fetchLegacyWeeklyCompletion(userID: owner),
               DIContainer.shared.authService.currentUserID == owner {
                try reviewStore.preserveLegacyCompletion(legacy, userID: owner)
                legacyCompletion = legacy
            }
        } catch { historyNotice = "Showing decisions saved on this device. History could not be refreshed." }
    }

    private var currentEvidenceFingerprint: String? {
        adaptiveGoalService.evidenceFingerprint
            ?? (try? PlanFingerprint.make(adaptiveGoalService.currentExpenditureSnapshot))
    }

    @MainActor
    private func prepareProposal() {
        guard let owner = ownerID, owner == DIContainer.shared.authService.currentUserID,
              checkpoint?.submittedDecision == nil, adaptiveGoalService.isEstimateActionable,
              let fingerprint = currentEvidenceFingerprint else { return }
        do {
            let proposal = try WeeklyTargetProposal(userID: owner, before: goalSettings.makeGoalEditorDraft(),
                evidence: adaptiveGoalService.currentExpenditureSnapshot, evidenceFingerprint: fingerprint)
            let value = WeeklyTargetCheckpoint(proposal: proposal)
            try reviewStore.save(value, currentUserID: owner)
            checkpoint = value; reviewError = nil
            logProposalViewedIfNeeded()
        } catch { reviewError = error.localizedDescription }
    }

    @MainActor
    private func refreshProposal() async {
        guard !isSaving, checkpoint?.submittedDecision == nil, let owner = ownerID,
              DIContainer.shared.authService.currentUserID == owner else { return }
        isSaving = true
        defer { isSaving = false }
        await adaptiveGoalService.fetchAndCalculate(userID: owner, goalSettings: goalSettings, dailyLogService: dailyLogService, requireServer: true)
        guard adaptiveGoalService.lastEvidenceRefreshSucceeded else {
            reviewError = "Could not refresh the evidence. Your current targets are unchanged."; return
        }
        guard adaptiveGoalService.isEstimateActionable else {
            reviewError = "The latest evidence is not ready for a target decision. Review your complete days and weigh-ins."; return
        }
        prepareProposal()
    }

    private func saveDecision(_ choice: WeeklyTargetDecision.Choice) {
        guard !isSaving, let frozen = checkpoint, let owner = ownerID else { return }
        isSaving = true; reviewError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                guard DIContainer.shared.authService.currentUserID == owner else { throw WeeklyTargetReviewError.accountChanged }
                var pending = frozen
                if pending.submittedDecision == nil {
                    await adaptiveGoalService.fetchAndCalculate(userID: owner, goalSettings: goalSettings, dailyLogService: dailyLogService, requireServer: true)
                    guard adaptiveGoalService.lastEvidenceRefreshSucceeded else { throw WeeklyTargetReviewError.unavailable }
                    try frozen.proposal.validate(userID: DIContainer.shared.authService.currentUserID,
                        current: goalSettings.makeGoalEditorDraft(), evidenceFingerprint: currentEvidenceFingerprint ?? "")
                }
                let decision = try pending.submit(choice)
                try reviewStore.save(pending, currentUserID: DIContainer.shared.authService.currentUserID)
                checkpoint = pending
                let accepted = try await goalSettings.saveWeeklyTargetDecision(decision)
                try reviewStore.finish(accepted, currentUserID: DIContainer.shared.authService.currentUserID)
                logProposalDecision(choice.rawValue)
                if choice != .deferReview, mode == .checkIn { AppReviewPromptQueue.shared.recordWeeklyCheckIn() }
                if choice == .deferReview, mode == .adaptiveOffer { onDeclineOffer() }
                HapticManager.instance.feedback(.light)
                dismiss()
            } catch { reviewError = error.localizedDescription }
        }
    }

    private var decisionHistory: some View {
        DisclosureGroup("Check-in history") {
            VStack(alignment: .leading, spacing: 14) {
                if let date = goalSettings.lastCheckInDate {
                    Text("Next weekly check-in: \((Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date).formatted(date: .abbreviated, time: .omitted)). You can review earlier whenever needed.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if decisions.isEmpty && legacyCompletion == nil {
                        Text("Previous check-in: \(date.formatted(date: .abbreviated, time: .omitted)). Detailed decision history was not recorded for that check-in.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                if let legacyCompletion {
                    Text("Legacy completion: \(legacyCompletion.formatted(date: .abbreviated, time: .omitted)). The app recorded completion then, without a detailed proposal.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if let historyNotice { Text(historyNotice).appTextRole(.caption).foregroundStyle(.secondary) }
                if decisions.isEmpty && goalSettings.lastCheckInDate == nil {
                    Text("Your confirmed decisions will appear here.").appTextRole(.secondary).foregroundStyle(.secondary)
                }
                ForEach(decisions) { decision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.choice.title).appTextRole(.control)
                        Text(decision.decidedAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.caption).foregroundStyle(.secondary)
                        Text("\(Int(decision.proposal.before.calories.rounded())) → \(Int(decision.effectiveTargets.calories.rounded())) cal/day")
                            .appTextRole(.body)
                        Text(decision.proposal.explanation.summary).appTextRole(.secondary).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 10)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("weekly_checkin_history")
    }

    private func deltaText(for delta: Double) -> String {
        guard abs(delta) >= 1 else { return "No change" }
        return delta > 0
            ? "+\(Int(delta.rounded()).formatted()) cal"
            : "-\(Int(abs(delta.rounded())).formatted()) cal"
    }

    private func logProposalViewedIfNeeded() {
        guard !hasLoggedProposalView, let proposal = goalProposal else { return }
        hasLoggedProposalView = true
        DIContainer.shared.analyticsManager?.logEvent("weekly_goal_proposal_viewed", parameters: [
            "surface": analyticsSurface,
            "confidence": proposal.confidence.rawValue,
            "should_adjust": proposal.shouldAdjust,
            "delta": Int(proposal.calorieDelta.rounded()),
            "training_load": proposal.trainingLoadLabel
        ])
    }

    private func logProposalDecision(_ decision: String) {
        guard let proposal = goalProposal else { return }
        DIContainer.shared.analyticsManager?.logEvent("weekly_goal_proposal_decision", parameters: [
            "surface": analyticsSurface,
            "decision": decision,
            "confidence": proposal.confidence.rawValue,
            "should_adjust": proposal.shouldAdjust,
            "delta": Int(proposal.calorieDelta.rounded()),
            "training_load": proposal.trainingLoadLabel
        ])
    }
}

private struct WeeklyCheckInStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .padding(8)
                .background(color.opacity(0.12), in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
import Charts

struct TrendDashboardView: View {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var dateRange: ClosedRange<Date>?
    var title: String
    var compactPresentation: Bool
    @AppStorage("useMetricBodyUnits") private var useMetricBodyUnits = Locale.current.measurementSystem != .us

    init(
        weightHistory: [(id: String, date: Date, weight: Double)],
        dateRange: ClosedRange<Date>? = nil,
        title: String = "Weight trend (21 days)",
        compactPresentation: Bool = false
    ) {
        self.weightHistory = weightHistory
        self.dateRange = dateRange
        self.title = title
        self.compactPresentation = compactPresentation
    }
    
    private var chartData: [(id: String, date: Date, weight: Double)] {
        let range = dateRange ?? {
            let calendar = Calendar.current
            let end = Date()
            let start = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: end)) ?? end
            return start...end
        }()
        let recent = weightHistory.filter { range.contains($0.date) && $0.date <= Date() }.sorted { $0.date < $1.date }
        return recent.filter { $0.weight.isFinite && $0.weight > 0 }
            .map { (id: $0.id, date: $0.date, weight: BodyUnits.weightDisplayValue(lbs: $0.weight, metric: useMetricBodyUnits)) }
    }

    private var trendProjection: WeightTrendRules.Projection {
        WeightTrendRules.project(chartData.map { point in
            AdaptiveWeightEvidence(id: point.id, date: point.date,
                pounds: BodyUnits.weightToLbs(point.weight, metric: useMetricBodyUnits))
        })
    }

    private var smoothedData: [(date: Date, weight: Double, segment: Int)] {
        trendProjection.points.map { (date: $0.date,
            weight: BodyUnits.weightDisplayValue(lbs: $0.pounds, metric: useMetricBodyUnits), segment: $0.segment) }
    }

    private var yAxisDomain: ClosedRange<Double> {
        let weights = chartData.map { $0.weight } + smoothedData.map { $0.weight }
        let minW = weights.min() ?? 150.0
        let maxW = weights.max() ?? 150.0
        let padding = max(1.5, (maxW - minW) * 0.4)
        return (minW - padding)...(maxW + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compactPresentation ? 8 : 12) {
            Text(title)
                .appFont(size: compactPresentation ? 15 : 18, weight: .bold)
                .foregroundColor(.textPrimary)
            
            if let first = smoothedData.first, let latest = smoothedData.last, smoothedData.count >= 2 {
                let change = latest.weight - first.weight
                let unit = BodyUnits.weightUnit(metric: useMetricBodyUnits)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(latest.weight.formatted(.number.precision(.fractionLength(1)))) \(unit)")
                        .appFont(size: 30, weight: .bold).monospacedDigit()
                    Text("\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) \(unit) in this period · \(trendProjection.measuredDays) measured days")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("reports_weight_outcome")
            }

            if trendProjection.measuredDays < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "scalemass")
                        .appFont(size: 28)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(trendProjection.measuredDays == 0 ? "Log your first weigh-in" : "Add a weigh-in on another day")
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    Text("Your trend line appears once you have measurements on at least two distinct days.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: compactPresentation ? 110 : 180)
            } else {
                Chart {
                    // Real weigh-ins as subtle dots
                    ForEach(chartData, id: \.id) { item in
                        PointMark(
                            x: .value("Date", item.date),
                            y: .value("Weight", item.weight)
                        )
                        .foregroundStyle(Color(UIColor.tertiaryLabel))
                        .symbolSize(28)
                    }
                    // Separate segments never bridge an unobserved gap longer than a week.
                    ForEach(smoothedData, id: \.date) { item in
                        LineMark(
                            x: .value("Date", item.date), y: .value("Trend estimate", item.weight),
                            series: .value("Observed interval", item.segment)
                        )
                        .foregroundStyle(AppPalette.effort)
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
                .chartYScale(domain: yAxisDomain)
                .chartXScale(range: .plotDimension(padding: 18))
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month().day())
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .appFont(size: 11)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .frame(height: compactPresentation ? 96 : 200)
                .clipped()
            }
            if compactPresentation {
                DisclosureGroup("Trend estimate · measured dots") {
                    trendExplanation
                }
                .appTextRole(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("weight_trend_method")
            } else {
                Text("Estimated trend · measured dots").appTextRole(.caption).foregroundStyle(.secondary)
                trendExplanation
            }
        }
        .appSurface(.quiet)
    }

    private var trendExplanation: some View {
        Text(trendProjection.description).appTextRole(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("weight_trend_coverage")
    }
}
