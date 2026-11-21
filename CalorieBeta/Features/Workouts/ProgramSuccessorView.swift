import MyFitPlateCore
import SwiftUI

struct ProgramSuccessorView: View {
    let source: WorkoutProgram
    @ObservedObject var workoutService: WorkoutService
    let onActivate: (WorkoutProgram) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var session: WorkoutSuccessorSaveSession?
    @State private var openingError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ProgramSuccessorContent(session: session, workoutService: workoutService, onActivate: onActivate)
                } else if let openingError {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Your next-block draft is kept").appTextRole(.sectionTitle)
                        Text(openingError).appTextRole(.secondary).foregroundStyle(.secondary)
                    }.padding(AppSpacing.screenHorizontal)
                } else { ProgressView("Opening next block") }
            }
            .navigationTitle("Next block").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.disabled(session?.isWorking == true)
                    .accessibilityIdentifier("successor_close")
            } }
            .background(AppPalette.canvas)
            .interactiveDismissDisabled(true)
            .task {
                guard session == nil, openingError == nil else { return }
                do { session = try WorkoutSuccessorSaveSession(source: source) } catch { openingError = error.localizedDescription }
            }
        }
    }
}

private struct ProgramSuccessorContent: View {
    @ObservedObject var session: WorkoutSuccessorSaveSession
    @ObservedObject var workoutService: WorkoutService
    let onActivate: (WorkoutProgram) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingTargets = false
    @State private var hasTargetsDraft = false
    @State private var confirmingDiscard = false
    @State private var confirmingCancel = false

    private var destination: WorkoutProgram? { try? session.draft.destination() }
    private var source: WorkoutProgram? { try? session.draft.source() }
    private var validationMessage: String? {
        guard !session.isSubmitted else { return nil }
        if hasTargetsDraft { return "Continue or discard the unfinished target edits before saving this block." }
        do {
            _ = try WorkoutProgramSuccessorCommand(source: session.draft.source(), destination: session.draft.destination())
            return nil
        } catch { return error.localizedDescription }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                overview
                if session.wasAccepted { acceptedReview } else if session.wasCancelled {
                    Text("Proposal cancelled. Your current plan and all workout history were kept.")
                        .appTextRole(.secondary).accessibilityIdentifier("successor_cancelled")
                } else {
                    configuration
                    if session.restored {
                        Text("Restored your next-block proposal from this device.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    if session.isSubmitted {
                        Text("This submitted proposal is fixed for safe retry. Close keeps it on this device; cancellation prevents a late save.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("successor_frozen")
                    }
                }
            }
            .padding(AppSpacing.screenHorizontal)
        }
        .accessibilityIdentifier("program_successor_scroll")
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { controls }
        .toolbar { ToolbarItem(placement: .primaryAction) {
            if !session.isSubmitted {
                Button("Discard") { confirmingDiscard = true }.disabled(session.isWorking)
                    .accessibilityIdentifier("successor_discard")
            }
        } }
        .sheet(isPresented: $showingTargets, onDismiss: refreshTargetsDraft) {
            if let destination {
                NavigationStack {
                    WorkoutBlockEditorView(program: destination, workoutService: workoutService,
                        onSaveLocalDraft: { try session.updateTargets($0) }, onSave: { _ in })
                }
            }
        }
        .confirmationDialog("Discard this next-block draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard proposal", role: .destructive) {
                do {
                    if let id = destination?.id {
                        try WorkoutBlockEditorView.discardLocalDraft(programID: id, userID: session.draft.userID)
                    }
                    if session.finish() { dismiss() }
                } catch { session.showError(error) }
            }
        } message: { Text("Only this unsaved proposal and its unfinished target edits will be removed. Your current plan and logs stay intact.") }
        .confirmationDialog("Cancel this pending proposal?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel pending proposal", role: .destructive) {
                Task { _ = await session.resolve(using: workoutService, cancelPending: true) }
            }
        } message: { Text("If it already saved, its current result will be shown. Otherwise the server will prevent a late retry from creating it.") }
        .task {
            refreshTargetsDraft()
            if session.isSubmitted && !session.isResolved { _ = await session.resolve(using: workoutService) }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(session.wasAccepted ? "Your next block is saved" : "Carry your training forward")
                .appTextRole(.sectionTitle)
            if let source {
                Text("From \(source.name)").appTextRole(.control)
                Text("\(max(source.currentProgressIndex ?? 0, 0)) of \(source.totalSlots) positions passed in the source plan")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("successor_source_progress")
                if (source.currentProgressIndex ?? 0) < source.totalSlots {
                    Text("The current block still has upcoming positions. Saving this proposal does not complete or replace it.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            Text("A separate plan starts at zero. Your existing plan, completed workouts and recoverable session stay with their original identities.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(destination?.lineage?.mode.title ?? "Repeat block").appTextRole(.control)
                .accessibilityIdentifier("successor_mode")
            TextField("New block name", text: Binding(get: { destination?.name ?? "" }, set: { value in
                do { try session.update { $0.name = value } } catch { session.showError(error) }
            }), axis: .vertical)
            .appTextRole(.control).accessibilityIdentifier("successor_name")
            DatePicker("Start on or after", selection: Binding(get: { destination?.startDate ?? Date() }, set: { value in
                do { try session.update { $0.startDate = Calendar.current.startOfDay(for: value) } } catch { session.showError(error) }
            }), displayedComponents: .date)
            .accessibilityIdentifier("successor_start_date")
            if let destination, let block = destination.trainingBlock {
                Text("\(block.weeks.count) weeks · \(block.sessionsPerWeek) sessions per week · \(destination.totalSlots) planned positions")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("successor_schedule_summary")
                if let first = destination.date(forSlot: 0) {
                    Text("First session: \(first.formatted(date: .abbreviated, time: .omitted))")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Button { showingTargets = true } label: {
                    Label(hasTargetsDraft ? "Continue target edits" : "Review or adjust weeks and targets", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                .accessibilityIdentifier("successor_edit_targets")
                Text("Repeat the reviewed pattern, or adjust its length, lighter weeks and individual targets before creating it. Equipment conventions stay with each exercise.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(session.isSubmitted || session.isWorking)
        .appSurface(.quiet)
    }

    private var acceptedReview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if let current = session.acceptedProgram {
                Text(current.name).appTextRole(.control)
                Text("\(current.trainingBlock?.weeks.count ?? 0) weeks · \(max(current.currentProgressIndex ?? 0, 0)) positions passed")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                Text(session.didActivate ? "This block is now active." : "Your current plan remains active until you choose Activate this block.")
                    .appTextRole(.secondary).foregroundStyle(AppPalette.brandText)
            } else {
                Text("This proposal saved earlier. Its new block has since been removed; the old program and history have not been changed.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet).accessibilityIdentifier("successor_accepted")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let message = session.errorMessage ?? validationMessage {
                Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("successor_error")
            }
            if session.isSubmitted && !session.isResolved {
                HStack {
                    Button { Task { _ = await session.resolve(using: workoutService) } } label: {
                        Text("Check status").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("successor_check_status")
                    Spacer()
                    Button { confirmingCancel = true } label: {
                        Text("Cancel pending").frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("successor_cancel_pending")
                }
                .appTextRole(.secondary).disabled(session.isWorking)
            }
            if session.wasAccepted && session.acceptedProgram != nil && !session.didActivate {
                Button {
                    Task {
                        if await session.activate(using: workoutService), let saved = session.acceptedProgram { onActivate(saved) }
                    }
                } label: { Text("Activate this block").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isWorking)
                .accessibilityIdentifier("successor_activate")
                Button { if session.finish() { dismiss() } } label: {
                    Text("Keep current plan").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain).disabled(session.isWorking).accessibilityIdentifier("successor_keep_current")
            } else {
                Button {
                    if session.isResolved { if session.finish() { dismiss() } } else { Task { _ = await session.submit(using: workoutService) } }
                } label: {
                    if session.isWorking { ProgressView("Saving block") } else { Text(session.isResolved ? "Done" : session.isSubmitted ? "Retry creation" : "Save new block") }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(session.isWorking || (!session.isSubmitted && validationMessage != nil))
                .accessibilityIdentifier("successor_save")
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.compact).background(.bar)
    }

    private func refreshTargetsDraft() {
        guard let id = destination?.id else { return }
        do { hasTargetsDraft = try WorkoutBlockEditorView.hasUnfinishedDraft(programID: id, userID: session.draft.userID) } catch { hasTargetsDraft = true; session.showError(error) }
    }
}
