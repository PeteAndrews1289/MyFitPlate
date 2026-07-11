import MyFitPlateCore
import SwiftUI

enum TrainingFuelDestination: String {
    case foodSearch = "food_search"
    case fastFoodBuilder = "fast_food_builder"
    case maiaIdea = "maia_idea"
    case mealPlan = "meal_plan"
}

struct TrainingFuelPlannerCard: View {
    let suggestedSession: TrainingFuelSessionCandidate?
    let savedPlan: TrainingFuelConfirmedPlan?
    let progress: TrainingFuelPlanProgress?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: iconName)
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(iconColor)
                        .frame(width: 40, height: 40)
                        .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Training Fuel")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(iconColor)

                        Text(title)
                            .appFont(size: 17, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .padding(.top, 12)
                }

                if let savedPlan, let progress {
                    VStack(spacing: 7) {
                        ForEach(progress.phases) { phase in
                            HStack(spacing: 8) {
                                Image(systemName: phase.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundColor(
                                        phase.isComplete ? .accentPositive : Color(UIColor.secondaryLabel)
                                    )

                                Text(phase.allocation.phase == .beforeTraining ? "Before" : "After")
                                    .appFont(size: 12, weight: .bold)
                                    .foregroundColor(.textPrimary)

                                Spacer()

                                Text(phaseSummary(phase, status: progress.status))
                                    .appFont(size: 12, weight: .semibold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                    }
                    .padding(.top, 1)
                    .accessibilityLabel("Saved fuel plan for \(savedPlan.draft.sessionTitle)")
                }
            }
            .padding(15)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                Color(UIColor.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(iconColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's training fuel planner.")
    }

    private var title: String {
        if let savedPlan { return savedPlan.draft.sessionTitle }
        return suggestedSession?.title ?? "Plan Today's Session"
    }

    private var subtitle: String {
        if let savedPlan, let progress {
            let time = savedPlan.draft.scheduledAt.formatted(date: .omitted, time: .shortened)
            return "\(statusTitle(progress.status)) - \(time)"
        }
        if let suggestedSession {
            return "\(suggestedSession.detail). Confirm time and effort."
        }
        return "Set a workout or run, then review a target inside today's goals."
    }

    private var iconName: String {
        guard let savedPlan else {
            return suggestedSession?.kind == .run ? "figure.run" : "bolt.heart"
        }
        return savedPlan.draft.kind == .run ? "figure.run" : "figure.strengthtraining.traditional"
    }

    private var iconColor: Color {
        switch progress?.status {
        case .complete:
            return .accentPositive
        case .skipped:
            return Color(UIColor.secondaryLabel)
        case .stale, .overTarget, .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
            return .orange
        default:
            return .brandPrimary
        }
    }

    private func phaseSummary(
        _ phase: TrainingFuelPhaseProgress,
        status: TrainingFuelPlanProgress.Status
    ) -> String {
        switch status {
        case .awaitingOutcome: return "Confirm session outcome"
        case .awaitingRecoveryData: return "Preparing recovery"
        case .skipped: return "Session skipped"
        case .stale: return "Plan expired"
        case .overTarget: return "Daily target reached"
        case .invalidDiary: return "Unavailable"
        case .invalidTargets: return "Targets unavailable"
        case .budgetUsedElsewhere: return "No room remains"
        default: break
        }
        if phase.isComplete { return "Logged" }
        if phase.allocation.phase == .afterTraining && status == .upcoming {
            return "Available after session"
        }
        if status == .inSession {
            return phase.allocation.phase == .beforeTraining ? "Window passed" : "Available after session"
        }
        if phase.allocation.phase == .beforeTraining && status != .upcoming { return "Window passed" }
        if !phase.hasMeaningfulUnloggedTarget { return "No action needed" }
        if !phase.hasActionableTarget { return "Budget used elsewhere" }
        let protein = phase.remainingProteinGrams
        let carbs = phase.remainingCarbGrams
        if protein > 0 && carbs > 0 { return "\(protein)g protein + \(carbs)g carbs left" }
        if protein > 0 { return "\(protein)g protein left" }
        return "\(carbs)g carbs left"
    }

    private func statusTitle(_ status: TrainingFuelPlanProgress.Status) -> String {
        switch status {
        case .upcoming: return "Upcoming"
        case .inSession: return "Training now"
        case .awaitingOutcome: return "Confirm completion"
        case .awaitingRecoveryData: return "Preparing recovery"
        case .recovery: return "Recovery"
        case .complete: return "Targets logged"
        case .skipped: return "Session skipped"
        case .stale: return "Review expired plan"
        case .overTarget: return "Daily target reached"
        case .invalidDiary: return "Check today's log"
        case .invalidTargets: return "Check daily targets"
        case .budgetUsedElsewhere: return "Budget used elsewhere"
        }
    }
}

struct TrainingFuelPlannerSheet: View {
    let candidates: [TrainingFuelSessionCandidate]
    let savedPlan: TrainingFuelConfirmedPlan?
    let savedProgress: TrainingFuelPlanProgress?
    let today: DailyLog?
    let goals: TodayFuelPlanGoals
    let now: Date
    let onConfirm: (TrainingFuelPlanDraft, TrainingFuelPlannerPlan) -> Void
    let onUseTarget: (
        TrainingFuelPlanDraft,
        TrainingFuelPlannerPlan,
        TrainingFuelTarget,
        TrainingFuelDestination
    ) -> Void
    let onUseSavedTarget: (TrainingFuelTarget, TrainingFuelDestination) -> Void
    let onMarkComplete: () -> Void
    let onSkip: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draftID: String
    @State private var sessionKind: TrainingFuelSession.Kind
    @State private var selectedCandidateID: String
    @State private var scheduledAt: Date
    @State private var durationMinutes: Int
    @State private var intensity: TrainingFuelSession.Intensity
    @State private var strengthFocus: TrainingFuelSession.StrengthFocus
    @State private var wantsBefore: Bool
    @State private var wantsAfter: Bool
    @State private var showingSkipConfirmation = false

    init(
        candidates: [TrainingFuelSessionCandidate],
        savedPlan: TrainingFuelConfirmedPlan?,
        savedProgress: TrainingFuelPlanProgress?,
        today: DailyLog?,
        goals: TodayFuelPlanGoals,
        now: Date = Date(),
        onConfirm: @escaping (TrainingFuelPlanDraft, TrainingFuelPlannerPlan) -> Void,
        onUseTarget: @escaping (
            TrainingFuelPlanDraft,
            TrainingFuelPlannerPlan,
            TrainingFuelTarget,
            TrainingFuelDestination
        ) -> Void,
        onUseSavedTarget: @escaping (TrainingFuelTarget, TrainingFuelDestination) -> Void,
        onMarkComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.savedPlan = savedPlan
        self.savedProgress = savedProgress
        self.today = today
        self.goals = goals
        self.now = now
        self.onConfirm = onConfirm
        self.onUseTarget = onUseTarget
        self.onUseSavedTarget = onUseSavedTarget
        self.onMarkComplete = onMarkComplete
        self.onSkip = onSkip
        self.onRemove = onRemove

        let fallback = candidates.first ?? TrainingFuelSessionAdapter.manualCandidate(kind: .strength)
        let savedDraft = savedPlan?.draft
        let initialKind = savedDraft?.kind ?? fallback.kind
        let initialCandidate = savedDraft.map(Self.savedCandidate(from:)) ?? fallback

        _draftID = State(initialValue: savedDraft?.id ?? UUID().uuidString)
        _sessionKind = State(initialValue: initialKind)
        _selectedCandidateID = State(initialValue: initialCandidate.id)
        _scheduledAt = State(initialValue: savedDraft?.scheduledAt ?? Self.defaultStartTime(now: now))
        _durationMinutes = State(
            initialValue: savedDraft?.durationMinutes ?? initialCandidate.suggestedDurationMinutes ?? 45
        )
        _intensity = State(initialValue: savedDraft?.intensity ?? initialCandidate.suggestedIntensity)
        _strengthFocus = State(
            initialValue: savedDraft?.strengthFocus ?? initialCandidate.suggestedStrengthFocus
        )
        _wantsBefore = State(initialValue: savedDraft?.preference.wantsPreSessionFuel ?? true)
        _wantsAfter = State(initialValue: savedDraft?.preference.wantsPostSessionFuel ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let savedPlan, let savedProgress {
                        savedPlanSection(plan: savedPlan, progress: savedProgress)
                    }

                    if savedPlan?.outcome == nil {
                        sessionSection
                        timingSection
                        preferenceSection
                        previewSection
                    } else {
                        closedPlanActions
                    }

                    Text("Targets stay inside today's calorie, protein, and carbohydrate goals. Fat is not prescribed, and Maia ideas remain optional suggestions.")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(savedPlan == nil ? "Plan Training Fuel" : "Review Training Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Skip this session?",
                isPresented: $showingSkipConfirmation,
                titleVisibility: .visible
            ) {
                Button("Skip Session", role: .destructive) { onSkip() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The saved fuel targets will be closed without changing your food log.")
            }
        }
    }

    private var currentCandidate: TrainingFuelSessionCandidate {
        availableCandidates.first(where: { $0.id == selectedCandidateID }) ??
            availableCandidates.first(where: { $0.kind == sessionKind }) ??
            TrainingFuelSessionAdapter.manualCandidate(kind: sessionKind)
    }

    private var availableCandidates: [TrainingFuelSessionCandidate] {
        guard let savedDraft = savedPlan?.draft else { return candidates }
        let saved = Self.savedCandidate(from: savedDraft)
        return [saved] + candidates.filter {
            !($0.source == saved.source &&
                $0.sourceID == saved.sourceID &&
                $0.title == saved.title)
        }
    }

    private var draft: TrainingFuelPlanDraft {
        TrainingFuelPlanDraft(
            id: draftID,
            candidate: currentCandidate,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            intensity: intensity,
            strengthFocus: strengthFocus,
            preference: TrainingFuelPreference(
                wantsPreSessionFuel: wantsBefore,
                wantsPostSessionFuel: wantsAfter
            )
        )
    }

    private var preview: TrainingFuelPlannerPlan {
        TrainingFuelPlannerRules.makePlan(
            session: draft.session,
            today: today,
            goals: goals,
            preference: draft.preference,
            now: now
        )
    }

    private var filteredCandidates: [TrainingFuelSessionCandidate] {
        availableCandidates.filter { $0.kind == sessionKind }
    }

    private var sessionSection: some View {
        plannerSection(title: "Session") {
            Picker("Training type", selection: $sessionKind) {
                Text("Strength").tag(TrainingFuelSession.Kind.strength)
                Text("Run").tag(TrainingFuelSession.Kind.run)
            }
            .pickerStyle(.segmented)
            .onChange(of: sessionKind) { _, kind in
                guard let candidate = availableCandidates.first(where: { $0.kind == kind }) else { return }
                apply(candidate)
            }

            if filteredCandidates.count > 1 {
                candidateMenu
            } else {
                LabeledContent("Workout", value: currentCandidate.title)
                    .appFont(size: 14, weight: .semibold)
            }

            Text(currentCandidate.detail)
                .appFont(size: 12, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))

            if currentCandidate.assumptions.contains(.durationNeedsReview) {
                Label("Duration could not be derived from this plan. Review it below.", systemImage: "exclamationmark.circle")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(.orange)
            } else if currentCandidate.assumptions.contains(.durationEstimated) {
                Label("Duration, effort, and focus are editable estimates.", systemImage: "slider.horizontal.3")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
    }

    private var timingSection: some View {
        plannerSection(title: "Timing and Effort") {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Start Time")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    startTimePicker
                        .labelsHidden()
                }

                Stepper(value: $durationMinutes, in: 15...240, step: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        Text("\(durationMinutes) minutes")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }
                }
                .dynamicTypeSize(.small ... .accessibility1)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Effort")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    intensityPicker
                }

                if sessionKind == .strength {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Training Focus")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        focusMenu
                    }
                }
            } else {
                startTimePicker

                Stepper(value: $durationMinutes, in: 15...240, step: 5) {
                    LabeledContent("Duration", value: "\(durationMinutes) min")
                }

                intensityPicker

                if sessionKind == .strength {
                    focusMenu
                }
            }
        }
    }

    private var preferenceSection: some View {
        plannerSection(title: "Fuel Windows") {
            Toggle(isOn: $wantsBefore) {
                Label("Before Training", systemImage: "bolt.fill")
            }
            .tint(.accentProtein)
            Toggle(isOn: $wantsAfter) {
                Label("After Training", systemImage: "arrow.clockwise.heart.fill")
            }
            .tint(.accentProtein)

            if !wantsBefore && !wantsAfter {
                Text("Choose at least one window to create a fuel target.")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(.orange)
            }
        }
    }

    private var closedPlanActions: some View {
        plannerSection(title: "Plan Options") {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove Plan", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var candidateMenu: some View {
        Menu {
            ForEach(filteredCandidates) { candidate in
                Button {
                    apply(candidate)
                } label: {
                    if candidate.id == selectedCandidateID {
                        Label(candidate.title, systemImage: "checkmark")
                    } else {
                        Text(candidate.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentCandidate.title)
                    .appFont(size: 15, weight: .bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(size: 12, weight: .bold)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .dynamicTypeSize(.small ... .accessibility1)
        .accessibilityLabel("Workout, \(currentCandidate.title)")
    }

    private var startTimePicker: some View {
        DatePicker(
            "Start Time",
            selection: $scheduledAt,
            in: dayStart...dayEnd,
            displayedComponents: .hourAndMinute
        )
        .dynamicTypeSize(.small ... .accessibility1)
    }

    private var intensityPicker: some View {
        Picker("Effort", selection: $intensity) {
            Text("Easy").tag(TrainingFuelSession.Intensity.easy)
            Text("Moderate").tag(TrainingFuelSession.Intensity.moderate)
            Text("Hard").tag(TrainingFuelSession.Intensity.hard)
        }
        .pickerStyle(.segmented)
        .dynamicTypeSize(.small ... .accessibility1)
    }

    private var focusMenu: some View {
        Menu {
            Button("Upper Body") { strengthFocus = .upperBody }
            Button("Lower Body") { strengthFocus = .lowerBody }
            Button("Full Body") { strengthFocus = .fullBody }
            Button("Mixed") { strengthFocus = .mixed }
            Button("Not Sure") { strengthFocus = .unknown }
        } label: {
            HStack(spacing: 8) {
                Text(strengthFocusTitle)
                    .appFont(size: 14, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(size: 11, weight: .bold)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .dynamicTypeSize(.small ... .accessibility1)
        .accessibilityLabel("Training focus, \(strengthFocusTitle)")
    }

    @ViewBuilder
    private var previewSection: some View {
        plannerSection(title: "Today's Allocation") {
            if preview.status == .ready || preview.status == .deferredRecovery {
                if preview.allocations.isEmpty,
                   preview.notes.contains(.postSessionFallsNextDay) {
                    Label(
                        "Recovery will be calculated after completion using the next day's live goals and diary.",
                        systemImage: "moon.stars.fill"
                    )
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                }

                ForEach(preview.allocations, id: \.phase) { allocation in
                    allocationRow(
                        allocation: allocation,
                        target: TrainingFuelTarget(
                            id: "\(draft.id):\(allocation.phase.rawValue)",
                            planID: draft.id,
                            sessionTitle: draft.sessionTitle,
                            phase: allocation.phase,
                            proteinGrams: allocation.proteinGrams,
                            carbGrams: allocation.carbGrams
                        ),
                        isAvailable: previewActionIsAvailable(for: allocation.phase)
                    ) { target, destination in
                        onUseTarget(draft, preview, target, destination)
                    }
                }

                if savedPlan == nil {
                    Button {
                        onConfirm(draft, preview)
                    } label: {
                        Label("Save plan", systemImage: "checkmark.circle.fill")
                            .appFont(size: 15, weight: .bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                } else {
                    Button {
                        onConfirm(draft, preview)
                    } label: {
                        Label("Update plan", systemImage: "arrow.triangle.2.circlepath")
                            .appFont(size: 15, weight: .bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPrimary)
                }
            } else {
                plannerStatusView(preview.status)
            }

            if savedPlan != nil {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove Plan", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func savedPlanSection(
        plan: TrainingFuelConfirmedPlan,
        progress: TrainingFuelPlanProgress
    ) -> some View {
        plannerSection(title: "Current Plan") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.draft.sessionTitle)
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("\(progressStatusTitle(progress.status)) at \(plan.draft.scheduledAt.formatted(date: .omitted, time: .shortened))")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
            }

            if progress.status != .awaitingOutcome {
                ForEach(progress.phases) { phase in
                    if isActionable(progress.status, phase: phase.allocation.phase),
                       let target = progress.target(for: phase.allocation.phase, plan: plan) {
                        allocationRow(allocation: phase.allocation, target: target) { target, destination in
                            onUseSavedTarget(target, destination)
                        }
                    } else {
                        HStack {
                            Label(
                                phase.allocation.phase == .beforeTraining ? "Before Training" : "After Training",
                                systemImage: phase.isComplete ? "checkmark.circle.fill" : "pause.circle.fill"
                            )
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(inactivePhaseColor(phase, status: progress.status))
                            Spacer()
                            Text(inactivePhaseTitle(phase, status: progress.status))
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .padding(10)
                        .background(
                            inactivePhaseColor(phase, status: progress.status).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
            }

            if plan.defersPostSession(), plan.outcome == nil {
                Label(
                    "Recovery will be calculated after completion so it uses the correct day's remaining goals.",
                    systemImage: "moon.stars.fill"
                )
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            }

            if canRecordOutcome(for: plan, status: progress.status) {
                Button(action: onMarkComplete) {
                    Label("Mark complete", systemImage: "checkmark.circle.fill")
                        .appFont(size: 14, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentPositive)

                Button {
                    showingSkipConfirmation = true
                } label: {
                    Label("Skip session", systemImage: "forward.end.fill")
                        .appFont(size: 14, weight: .bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color(UIColor.secondaryLabel))
            }

            if progress.status == .overTarget {
                Label("Today's calorie target has been reached. Review the day instead of adding fuel.", systemImage: "exclamationmark.triangle.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
            } else if progress.status == .stale {
                Label("This session window has passed. Update or remove the plan.", systemImage: "clock.badge.exclamationmark")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
            } else if progress.status == .budgetUsedElsewhere {
                Label("Food logged elsewhere used the remaining daily budget, so this target was paused.", systemImage: "equal.circle.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
            } else if progress.status == .invalidDiary {
                Label("Today's diary contains a value that cannot be verified. Fix the log before using this plan.", systemImage: "exclamationmark.triangle.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
            } else if progress.status == .invalidTargets {
                Label("Today's nutrition targets cannot be verified. Update them before using this plan.", systemImage: "target")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
            } else if progress.status == .awaitingOutcome {
                Label("Confirm whether the session was completed or skipped before recovery guidance appears.", systemImage: "checkmark.circle")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.accentSignal)
            } else if progress.status == .awaitingRecoveryData {
                Label("Recovery will appear after today's diary finishes loading.", systemImage: "arrow.clockwise")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            } else if progress.status == .skipped {
                Label("This session was skipped. No fuel target remains active.", systemImage: "forward.end.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
    }

    private func allocationRow(
        allocation: TrainingFuelAllocation,
        target: TrainingFuelTarget,
        isAvailable: Bool = true,
        action: @escaping (TrainingFuelTarget, TrainingFuelDestination) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(allocation.phase == .beforeTraining ? "Before Training" : "After Training")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text(timingTitle(allocation.timing))
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                Spacer()
                Text("\(target.calories) cal")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
            }

            HStack(spacing: 8) {
                targetMetric("Protein", value: "\(target.proteinGrams)g", color: .accentProtein)
                targetMetric("Carbs", value: "\(target.carbGrams)g", color: .accentCarbs)
            }

            if isAvailable {
                Menu {
                    Button { action(target, .foodSearch) } label: {
                        Label("Search and Recent Foods", systemImage: "magnifyingglass")
                    }
                    Button { action(target, .fastFoodBuilder) } label: {
                        Label("Fast Food Builder", systemImage: "takeoutbag.and.cup.and.straw")
                    }
                    Button { action(target, .maiaIdea) } label: {
                        Label("Ask Maia for an Idea", systemImage: "sparkles")
                    }
                    Button { action(target, .mealPlan) } label: {
                        Label("Open Meal Plan", systemImage: "calendar")
                    }
                } label: {
                    Label("Choose Food", systemImage: "fork.knife")
                        .appFont(size: 13, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundColor(.textPrimary)
            } else {
                Label(
                    allocation.phase == .afterTraining ? "Available After Training" : "Window Passed",
                    systemImage: "clock"
                )
                    .appFont(size: 13, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(11)
        .background(
            Color(UIColor.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func targetMetric(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func plannerStatusView(_ status: TrainingFuelPlannerPlan.Status) -> some View {
        let content = statusContent(status)
        return Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .appFont(size: 14, weight: .bold)
                Text(content.detail)
                    .appFont(size: 12, weight: .medium)
            }
        } icon: {
            Image(systemName: content.icon)
        }
        .foregroundColor(content.color)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(content.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func plannerSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
            content()
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: now)
    }

    private static func savedCandidate(
        from draft: TrainingFuelPlanDraft
    ) -> TrainingFuelSessionCandidate {
        TrainingFuelSessionCandidate(
            id: "saved:\(draft.id)",
            source: draft.source,
            sourceID: draft.sourceID,
            sessionReferenceID: draft.sessionReferenceID,
            title: draft.sessionTitle,
            detail: "Current saved plan",
            kind: draft.kind,
            scheduledDay: Calendar.current.startOfDay(for: draft.scheduledAt),
            suggestedDurationMinutes: draft.durationMinutes,
            suggestedIntensity: draft.intensity,
            suggestedStrengthFocus: draft.strengthFocus,
            assumptions: []
        )
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var strengthFocusTitle: String {
        switch strengthFocus {
        case .upperBody: return "Upper Body"
        case .lowerBody: return "Lower Body"
        case .fullBody: return "Full Body"
        case .mixed: return "Mixed"
        case .unknown: return "Not Sure"
        }
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? now
    }

    private func apply(_ candidate: TrainingFuelSessionCandidate) {
        if let savedPlan, candidate.id == "saved:\(savedPlan.id)" {
            draftID = savedPlan.id
        } else if candidate.id != selectedCandidateID {
            draftID = UUID().uuidString
        }
        selectedCandidateID = candidate.id
        durationMinutes = candidate.suggestedDurationMinutes ?? 45
        intensity = candidate.suggestedIntensity
        strengthFocus = candidate.suggestedStrengthFocus
    }

    private func timingTitle(_ timing: TrainingFuelAllocation.Timing) -> String {
        switch timing {
        case .within30Minutes: return "Within 30 minutes"
        case .thirtyTo120Minutes: return "30 to 120 minutes before"
        case .overTwoHours: return "More than 2 hours before"
        case .afterSession: return "After the session"
        }
    }

    private func progressStatusTitle(_ status: TrainingFuelPlanProgress.Status) -> String {
        switch status {
        case .upcoming: return "Upcoming"
        case .inSession: return "Training now"
        case .awaitingOutcome: return "Awaiting completion"
        case .awaitingRecoveryData: return "Preparing recovery"
        case .recovery: return "Recovery"
        case .complete: return "Targets logged"
        case .skipped: return "Skipped"
        case .stale: return "Expired"
        case .overTarget: return "Daily target reached"
        case .invalidDiary: return "Diary needs review"
        case .invalidTargets: return "Targets need review"
        case .budgetUsedElsewhere: return "Budget used elsewhere"
        }
    }

    private func isActionable(
        _ status: TrainingFuelPlanProgress.Status,
        phase: TrainingFuelAllocation.Phase
    ) -> Bool {
        switch status {
        case .upcoming:
            return phase == .beforeTraining
        case .inSession:
            return false
        case .recovery:
            return phase == .afterTraining
        default:
            return false
        }
    }

    private func canRecordOutcome(
        for plan: TrainingFuelConfirmedPlan,
        status: TrainingFuelPlanProgress.Status
    ) -> Bool {
        guard plan.outcome == nil else { return false }
        switch status {
        case .upcoming, .inSession, .awaitingOutcome, .overTarget,
             .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
            return true
        case .awaitingRecoveryData, .recovery, .complete, .skipped, .stale:
            return false
        }
    }

    private func inactivePhaseTitle(
        _ phase: TrainingFuelPhaseProgress,
        status: TrainingFuelPlanProgress.Status
    ) -> String {
        if phase.isComplete { return "Logged" }
        switch status {
        case .upcoming:
            return phase.allocation.phase == .afterTraining ? "Available Later" : "No Further Action"
        case .inSession:
            return phase.allocation.phase == .afterTraining ? "Available After" : "Window Passed"
        case .awaitingOutcome:
            return "Confirm Session"
        case .awaitingRecoveryData:
            return "Loading Diary"
        case .recovery:
            return phase.allocation.phase == .beforeTraining ? "Window Passed" : "No Further Action"
        case .skipped:
            return "Session Skipped"
        case .stale:
            return "Plan Expired"
        case .overTarget:
            return "Target Reached"
        case .invalidDiary:
            return "Review Diary"
        case .invalidTargets:
            return "Review Targets"
        case .budgetUsedElsewhere:
            return "No Room Left"
        default:
            return "No Further Action"
        }
    }

    private func inactivePhaseColor(
        _ phase: TrainingFuelPhaseProgress,
        status: TrainingFuelPlanProgress.Status
    ) -> Color {
        if phase.isComplete { return .accentPositive }
        switch status {
        case .skipped:
            return Color(UIColor.secondaryLabel)
        case .stale, .overTarget, .invalidDiary, .invalidTargets, .budgetUsedElsewhere:
            return .orange
        default:
            return Color(UIColor.secondaryLabel)
        }
    }

    private func previewActionIsAvailable(
        for phase: TrainingFuelAllocation.Phase
    ) -> Bool {
        switch phase {
        case .beforeTraining:
            return now < scheduledAt
        case .afterTraining:
            let end = scheduledAt.addingTimeInterval(Double(durationMinutes * 60))
            return now >= end
        }
    }

    private func statusContent(
        _ status: TrainingFuelPlannerPlan.Status
    ) -> (title: String, detail: String, icon: String, color: Color) {
        switch status {
        case .deferredRecovery:
            return (
                "Recovery Saved for Tomorrow",
                "The target will be calculated from tomorrow's live diary after completion.",
                "moon.stars.fill",
                .accentSignal
            )
        case .needsSessionTime:
            return ("Choose a Start Time", "The planner will not invent one.", "clock", .orange)
        case .noFuelRequested:
            return ("Choose a Fuel Window", "Turn on before training, after training, or both.", "fork.knife", .orange)
        case .outsideToday:
            return ("Outside Today's Plan", "Choose a time that keeps this fuel inside today.", "calendar.badge.exclamationmark", .orange)
        case .staleSession:
            return ("Start Time Has Passed", "Update the time before creating a new allocation.", "clock.badge.exclamationmark", .orange)
        case .overTargetReview:
            return ("Daily Target Reached", "Review today's log instead of creating extra fuel.", "checkmark.circle", .accentPositive)
        case .insufficientBudget:
            return ("No Actionable Budget", "Today's remaining targets are too small for a useful allocation.", "equal.circle", .orange)
        case .invalidDiaryData:
            return ("Check Today's Log", "A nutrition value could not be verified, so no target was created.", "exclamationmark.triangle", .orange)
        case .invalidCalorieTarget:
            return ("Set a Calorie Goal", "A valid daily calorie target is required.", "target", .orange)
        case .ready:
            return ("Ready", "", "checkmark.circle", .accentPositive)
        }
    }

    private static func defaultStartTime(now: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .minute, value: 60, to: now) ?? now
        let minute = calendar.component(.minute, from: start)
        let rounded = minute < 30 ? 30 - minute : 60 - minute
        let candidate = calendar.date(byAdding: .minute, value: rounded, to: start) ?? start
        let end = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: calendar.startOfDay(for: now)
        ) ?? candidate
        return min(candidate, end)
    }
}
