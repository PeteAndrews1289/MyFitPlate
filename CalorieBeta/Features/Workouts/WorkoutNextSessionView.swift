import MyFitPlateCore
import SwiftUI

/// The completion card and coach share this destination. Reviewing stages values;
/// the existing block editor owns the final durable, checked program save.
struct WorkoutNextSessionReviewView: View {
    let context: WorkoutNextSessionContext
    @ObservedObject var workoutService: WorkoutService
    var onAccepted: ((WorkoutProgram) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var program: WorkoutProgram?
    @State private var history: [WorkoutSessionLog] = []
    @State private var rows: [WorkoutNextSessionRecommendation] = []
    @State private var reviewed: [String: ProgressionPlan] = [:]
    @State private var selected: WorkoutNextSessionRecommendation?
    @State private var proposal: NextSessionBlockProposal?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isPreparing = false
    @State private var hasExistingDraft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    if let program, currentOwner == context.ownerID {
                        Text(program.routine(forSlot: context.slotIndex)?.name ?? "Future session").appTextRole(.sectionTitle)
                        if let date = program.date(forSlot: context.slotIndex) {
                            Text(date.formatted(date: .complete, time: .omitted)).appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        Text("Review suggested loads and reps from comparable sessions.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(rows) { row in
                            WorkoutNextTargetRow(row: row, reviewed: reviewed[row.id]) {
                                selected = row
                            }
                        }
                        if rows.isEmpty {
                            Text("This session has no strength targets to review.").appTextRole(.secondary)
                        }
                        if program.trainingBlock == nil {
                            Text("Saving creates a week-specific target for this occurrence. Your routine rotation, passed sessions and PHUL position stay intact.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("next_session_legacy_review")
                        }
                    } else if isLoading {
                        ProgressView("Loading comparable sessions")
                    }
                    if let errorMessage {
                        Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .accessibilityIdentifier("next_session_error")
                    }
                    if hasExistingDraft {
                        Button("Open unfinished review") { openExistingDraft() }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityIdentifier("next_session_existing_draft")
                    }
                }
                .padding(AppSpacing.screenHorizontal)
            }
            .accessibilityIdentifier("next_session_review")
            .background(AppPalette.canvas)
            .navigationTitle("Next-session targets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.accessibilityIdentifier("next_session_close")
            } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Only reviewed movements change when you save.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Button(isPreparing ? "Checking targets…" : "Review save") { Task { await prepareSave() } }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(reviewed.isEmpty || isLoading || isPreparing || currentOwner != context.ownerID)
                        .accessibilityIdentifier("next_session_review_save")
                }
                .padding(AppSpacing.row).background(.bar)
            }
            .sheet(item: $selected) { row in
                if let plan = reviewed[row.id] ?? row.plan, currentOwner == context.ownerID {
                    ProgressionTargetsReview(exercise: row.exercise, history: history, routineID: context.routineID,
                                             initialPlan: plan, forFutureSession: true) { plan in
                        do {
                            let latest = try currentProgram()
                            try WorkoutNextSessionRules.validate(context, program: latest, ownerID: context.ownerID,
                                protectedSlots: workoutService.protectedBlockSlots(in: latest))
                            reviewed[row.id] = plan
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
            .sheet(item: $proposal) { proposal in
                NavigationStack {
                    WorkoutBlockEditorView(program: proposal.program, workoutService: workoutService,
                                           initialBlock: proposal.block,
                                           initialNextSessionContext: proposal.block == nil ? nil : context,
                                           initialNextSessionHistoryFingerprint: proposal.historyFingerprint) { saved in
                        guard currentOwner == context.ownerID else { return }
                        // An unrelated restored draft is a separate reviewed action.
                        if proposal.block != nil { onAccepted?(saved) }
                        dismiss()
                    }
                }
            }
            .task { await load() }
        }
    }

    private var currentOwner: String? { DIContainer.shared.authService.currentUserID }

    private func currentProgram() throws -> WorkoutProgram {
        guard currentOwner == context.ownerID, let active = workoutService.activeProgram,
              active.id == context.programID else { throw WorkoutBlockError.accountChanged }
        return try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(active))
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let latest = try currentProgram()
            let values = try await NextSessionHistory.load(program: latest, service: workoutService)
            let protection = try workoutService.protectedBlockSlots(in: latest)
            let current = try currentProgram()
            rows = try WorkoutNextSessionRules.recommendations(for: context, program: current,
                history: values, ownerID: context.ownerID, protectedSlots: protection)
            history = values; program = current
        } catch { errorMessage = error.localizedDescription }
    }

    private func prepareSave() async {
        guard !isPreparing else { return }
        isPreparing = true; errorMessage = nil
        defer { isPreparing = false }
        do {
            let latest = try currentProgram()
            let refreshed = try await NextSessionHistory.load(program: latest, service: workoutService)
            // Corrected or newly arrived evidence requires a new review. Manual edits
            // are never silently recalculated against a different history snapshot.
            guard try NextSessionHistory.fingerprint(refreshed) == NextSessionHistory.fingerprint(history) else {
                throw WorkoutBlockError.changed
            }
            let current = try currentProgram()
            let block = try WorkoutNextSessionRules.proposedBlock(context: context, program: current,
                reviewedPlans: rows.compactMap { reviewed[$0.id] }, history: refreshed, ownerID: context.ownerID,
                protectedSlots: workoutService.protectedBlockSlots(in: current))
            hasExistingDraft = try WorkoutBlockEditorView.hasUnfinishedDraft(programID: context.programID, userID: context.ownerID)
            guard !hasExistingDraft else {
                errorMessage = "You have an unfinished block review. Finish or discard it before adding these targets. Your staged values stay here."
                return
            }
            proposal = NextSessionBlockProposal(program: current, block: block, historyFingerprint: try NextSessionHistory.fingerprint(refreshed))
        } catch { errorMessage = error.localizedDescription }
    }

    private func openExistingDraft() {
        do {
            let current = try currentProgram()
            try WorkoutNextSessionRules.validate(context, program: current, ownerID: context.ownerID,
                protectedSlots: workoutService.protectedBlockSlots(in: current))
            proposal = NextSessionBlockProposal(program: current, block: nil)
        } catch { errorMessage = error.localizedDescription }
    }
}

/// A small, evidence-based handoff; suggestions remain separate from saved targets.
struct WorkoutNextTimeCard: View {
    let log: WorkoutSessionLog
    let ownerID: String?
    let hasPendingCorrection: Bool
    @ObservedObject var workoutService: WorkoutService
    @State private var context: WorkoutNextSessionContext?
    @State private var recommendations: [WorkoutNextSessionRecommendation] = []
    @State private var selectedContext: WorkoutNextSessionContext?
    @State private var nextBlock: WorkoutProgram?
    @State private var message: String?

    private var matchingProgram: WorkoutProgram? {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID,
              let program = workoutService.activeProgram, program.userID == ownerID,
              WorkoutRules.logBelongsToProgram(log, program: program) else { return nil }
        return program
    }

    private var refreshID: String {
        let program = matchingProgram
        return "\(log.id ?? "")-\(log.correctionRevisionID ?? "")-\(program?.id ?? "")-\(program?.currentProgressIndex ?? 0)-\(program?.trainingBlock?.revisionID ?? "")-\(hasPendingCorrection)"
    }

    var body: some View {
        Group {
            if let program = matchingProgram {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text("Targets for next time").appTextRole(.sectionTitle)
                    if hasPendingCorrection {
                        Text("Finish saving the session correction before reviewing future targets.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    } else if (program.currentProgressIndex ?? 0) >= program.totalSlots {
                        Text("This block is complete. Review the next block with your recorded performance in view.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        Button("Review next block") { openNextBlock() }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityIdentifier("workout_next_block_review")
                    } else if let context {
                        Text(program.routine(forSlot: context.slotIndex)?.name ?? "Next occurrence")
                            .appTextRole(.body)
                        if let row = recommendations.first(where: { $0.plan != nil }), let plan = row.plan {
                            Text(row.exercise.name).appTextRole(.secondary)
                            if let recorded = row.recorded, let date = row.recordedAt {
                                Text("\(date.formatted(date: .abbreviated, time: .omitted)) · \(NextSessionText.recorded(recorded, unit: row.exercise.loadEquipment?.unit ?? .lb))")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            Text("Suggested: \(NextSessionText.targets(plan, unit: row.exercise.loadEquipment?.unit ?? .lb))")
                                .appTextRole(.secondary).monospacedDigit()
                            Text(plan.rationale).appTextRole(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Your written prescription stays in place until you review a change.")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        Button("Review next targets") { openReview(context) }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityIdentifier("workout_next_targets_review")
                    } else if message == nil {
                        Text("No remaining occurrence of this routine needs new targets.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if let message {
                        Text(message).appTextRole(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("workout_next_targets_status")
                    }
                }
                .appSurface(.quiet)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workout_next_time")
            }
        }
        .task(id: refreshID) { await refresh() }
        .sheet(item: $selectedContext) { context in
            AnyView(WorkoutNextSessionReviewView(context: context, workoutService: workoutService) { _ in
                message = "Future targets saved. Your completed session stays unchanged."
                self.context = nil
            })
        }
        .sheet(item: $nextBlock) { program in
            AnyView(ProgramSuccessorView(source: program, workoutService: workoutService) { _ in nextBlock = nil })
        }
    }

    private func refresh() async {
        context = nil; recommendations = []
        guard let program = matchingProgram, let ownerID, !hasPendingCorrection,
              (program.currentProgressIndex ?? 0) < program.totalSlots else { return }
        do {
            let protection = try workoutService.protectedBlockSlots(in: program)
            guard let captured = try WorkoutNextSessionContext.next(for: program, ownerID: ownerID,
                evidenceSession: log, protectedSlots: protection) else { return }
            let history = try await NextSessionHistory.load(program: program, service: workoutService, evidenceSession: log)
            guard let latest = matchingProgram else { throw WorkoutBlockError.accountChanged }
            recommendations = try WorkoutNextSessionRules.recommendations(for: captured, program: latest,
                history: history, ownerID: ownerID, protectedSlots: workoutService.protectedBlockSlots(in: latest))
            context = captured
        } catch { message = "Future targets couldn't load. Your recorded session and plan are unchanged." }
    }

    private func openReview(_ context: WorkoutNextSessionContext) {
        do {
            guard let program = matchingProgram, let ownerID else { throw WorkoutBlockError.accountChanged }
            try WorkoutNextSessionRules.validate(context, program: program, ownerID: ownerID,
                protectedSlots: workoutService.protectedBlockSlots(in: program))
            selectedContext = context
        } catch { message = error.localizedDescription }
    }

    private func openNextBlock() {
        guard let program = matchingProgram, !hasPendingCorrection,
              (program.currentProgressIndex ?? 0) >= program.totalSlots else { return }
        do { nextBlock = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(program)) } catch { message = error.localizedDescription }
    }
}

private struct NextSessionBlockProposal: Identifiable {
    let id = UUID()
    let program: WorkoutProgram
    let block: WorkoutProgramBlock?
    var historyFingerprint: String?
}

private struct WorkoutNextTargetRow: View {
    let row: WorkoutNextSessionRecommendation
    let reviewed: ProgressionPlan?
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(row.exercise.name).appTextRole(.control)
            Text("Prescribed: \(row.exercise.sets.first?.prescription?.summary ?? row.exercise.sets.first?.target ?? row.exercise.targetReps)")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if let recorded = row.recorded, let date = row.recordedAt {
                Text("Recorded \(date.formatted(date: .abbreviated, time: .omitted)): \(NextSessionText.recorded(recorded, unit: row.exercise.loadEquipment?.unit ?? .lb))")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if let plan = reviewed ?? row.plan {
                Text("\(reviewed == nil ? "Suggested" : "Your reviewed targets"): \(NextSessionText.targets(plan, unit: row.exercise.loadEquipment?.unit ?? .lb))")
                    .appTextRole(.body).monospacedDigit()
                Text(plan.rationale).appTextRole(.caption).foregroundStyle(.secondary)
                Button(reviewed == nil ? "Review targets" : "Edit reviewed targets", action: onReview)
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("next_session_movement_\(row.id)")
            } else {
                Text("Keep the written prescription. There isn't enough compatible evidence for an automatic suggestion.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
    }
}

private enum NextSessionText {
    static func targets(_ plan: ProgressionPlan, unit: StrengthEquipment.Unit) -> String {
        plan.targets.map { "\(unit.displayWeight($0.weight).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) × \($0.reps)" }
            .joined(separator: " · ")
    }
    static func recorded(_ exercise: CompletedExercise, unit: StrengthEquipment.Unit) -> String {
        exercise.sets.filter { $0.resolvedSetType == .normal }.map {
            "\(unit.displayWeight($0.weight).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) × \($0.reps)"
        }.joined(separator: " · ")
    }
}

@MainActor
enum NextSessionHistory {
    #if DEBUG
    private static var fixtureHistory: [WorkoutSessionLog]?
    #endif
    static func load(program: WorkoutProgram, service: WorkoutService,
                     evidenceSession: WorkoutSessionLog? = nil) async throws -> [WorkoutSessionLog] {
        #if DEBUG
        if ScreenshotDemoMode.isEnabled {
            // The screenshot factory creates fresh nested IDs per call. Capture
            // one isolated receipt snapshot so freshness checks exercise real semantics.
            var history = fixtureHistory ?? ScreenshotDemoData.workoutHistoryLogs
            if let evidenceSession, let id = evidenceSession.id {
                history.removeAll { $0.id == id }
                history.insert(evidenceSession, at: 0)
            }
            fixtureHistory = history
            return history
        }
        #endif
        switch await service.fetchSessionLogsResult(for: program) {
        case .success(let logs): return logs
        case .failure(let error): throw error
        }
    }
    static func fingerprint(_ history: [WorkoutSessionLog]) throws -> String {
        try WorkoutBlockRules.fingerprint(history.map(WorkoutNextSessionRules.evidenceFingerprint).sorted())
    }
}
