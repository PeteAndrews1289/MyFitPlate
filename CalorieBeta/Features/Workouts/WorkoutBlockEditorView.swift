import MyFitPlateCore
import SwiftUI

private struct WorkoutBlockEditorDraft: Codable {
    var baseline: WorkoutProgram
    var block: WorkoutProgramBlock
    var pendingSlot: Int?
    var pendingRoutine: WorkoutRoutine?
    var submitted: Bool?
    var frozenSubmission: Data?
    var nextSessionContext: WorkoutNextSessionContext?
    var nextSessionHistoryFingerprint: String?
}

private struct WorkoutBlockSubmission: Codable {
    let baseline: WorkoutProgram
    let block: WorkoutProgramBlock
}

private struct WorkoutBlockSlotEdit: Identifiable {
    let index: Int
    let routine: WorkoutRoutine
    var id: Int { index }
}

struct WorkoutBlockEditorView: View {
    let program: WorkoutProgram
    @ObservedObject var workoutService: WorkoutService
    var onSaveLocalDraft: ((WorkoutProgram) throws -> Void)?
    var initialBlock: WorkoutProgramBlock?
    var initialNextSessionContext: WorkoutNextSessionContext?
    var initialNextSessionHistoryFingerprint: String?
    let onSave: (WorkoutProgram) -> Void
    private var isLocalDraft: Bool { onSaveLocalDraft != nil }
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: WorkoutProgram?
    @State private var block: WorkoutProgramBlock?
    @State private var protectedSlots = Set<Int>()
    @State private var activeSlot: WorkoutBlockSlotEdit?
    @State private var pendingSlot: WorkoutBlockSlotEdit?
    @State private var selectedWeek = 0
    @State private var isSaving = false
    @State private var isReady = false
    @State private var isClosing = false
    @State private var errorMessage: String?
    @State private var draftMessage: String?
    @State private var ownerID = ""
    @State private var confirmingDiscard = false
    @State private var initialBlockData: Data?
    @State private var restoredDraft = false
    @State private var submissionData: Data?
    @State private var nextSessionContext: WorkoutNextSessionContext?
    @State private var nextSessionHistoryFingerprint: String?
    @State private var didAccept = false
    @State private var acceptedProgram: WorkoutProgram?
    @State private var cancellationConfirmed = false
    @State private var confirmingCancel = false
    @State private var showingWeekCopy = false
    @State private var showingDayReuse = false
    @State private var deloadReview: WorkoutDeloadReview?
    @State private var mergeReview: WorkoutBlockMergeReview?
    @State private var mergeChoices: [String: WorkoutEditorConflictChoice] = [:]
    private var submitted: Bool { submissionData != nil }
    private let store = EditorDraftStore()
    private var scope: String { "program-block-\(program.id ?? "unknown")" }

    private var proposal: WorkoutProgram? {
        guard var baseline, let block else { return nil }
        baseline.trainingBlock = block
        return baseline
    }

    private var draftData: Data? {
        guard let baseline, let block else { return nil }
        let draft = WorkoutBlockEditorDraft(baseline: baseline, block: block,
            pendingSlot: pendingSlot?.index, pendingRoutine: pendingSlot?.routine,
            submitted: submitted, frozenSubmission: submissionData,
            nextSessionContext: nextSessionContext, nextSessionHistoryFingerprint: nextSessionHistoryFingerprint)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(draft)
    }

    private var blockData: Data? {
        guard let block else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(block)
    }

    private var validationMessage: String? {
        guard let baseline, let block else { return "This block could not be opened. Its data has been kept." }
        if pendingSlot != nil { return "Finish or discard the unfinished session before saving the block." }
        do { _ = try WorkoutBlockRules.applying(block, to: baseline, expected: baseline, protectedSlots: protectedSlots) } catch { return error.localizedDescription }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                header
                if restoredDraft {
                    Label("Restored your unfinished block.", systemImage: "arrow.counterclockwise")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("block_restored_draft")
                }
                if block != nil {
                    configuration
                    weekOutline
                }
                if !isLocalDraft, !submitted, let baseline, proposal != nil,
                   let saved = workoutService.userPrograms.first(where: { $0.id == program.id }), saved.trainingBlock != nil {
                    Button("Compare draft with saved block") {
                        do {
                            guard let proposal else { throw WorkoutBlockError.invalid }
                            mergeReview = try WorkoutBlockMergeRules.review(baseline: baseline, local: proposal, saved: saved,
                                protectedSlots: workoutService.protectedBlockSlots(in: saved))
                            mergeChoices = [:]
                        } catch { errorMessage = error.localizedDescription }
                    }.frame(minHeight: 44).accessibilityIdentifier("block_review_conflicts")
                    if let mergeReview {
                        Text("Choose each conflicting session or field. Unchanged fields keep the saved version; passed/active targets are protected.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(mergeReview.conflicts) { item in
                            Text(item.title).appTextRole(.control)
                            Text("Draft\n" + item.localSummary).appTextRole(.secondary)
                            Text("Saved\n" + item.savedSummary).appTextRole(.secondary).foregroundStyle(.secondary)
                            Picker("Keep version", selection: Binding(get: { mergeChoices[item.id] }, set: { mergeChoices[item.id] = $0 })) {
                                Text("Choose").tag(Optional<WorkoutEditorConflictChoice>.none)
                                Text("My draft").tag(Optional(WorkoutEditorConflictChoice.mine))
                                Text("Saved version").tag(Optional(WorkoutEditorConflictChoice.saved))
                            }
                        }
                        Button("Use reviewed merge in draft") {
                            do {
                                let protection = try workoutService.protectedBlockSlots(in: saved)
                                let resolved = try WorkoutBlockMergeRules.resolving(mergeReview, choices: mergeChoices, latest: saved, protectedSlots: protection)
                                self.baseline = saved; self.block = resolved; protectedSlots = protection
                                self.mergeReview = nil; mergeChoices = [:]; _ = checkpoint()
                            } catch { errorMessage = error.localizedDescription }
                        }.frame(minHeight: 44).disabled(mergeReview.conflicts.contains { mergeChoices[$0.id] == nil })
                    }
                }
                if let pendingSlot {
                    Button("Continue unfinished session") { activeSlot = pendingSlot }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("block_continue_session")
                }
                if let draftMessage { Text(draftMessage).appTextRole(.secondary).foregroundStyle(.secondary) }
            }
            .disabled(isSaving || submitted)
            .padding(AppSpacing.screenHorizontal)
        }
        .accessibilityIdentifier("workout_block_editor_scroll")
        .scrollDismissesKeyboard(.interactively)
        .background(AppPalette.canvas)
        .navigationTitle(isLocalDraft ? "Next-block targets" : "Training block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                if !isReady || checkpoint() { isClosing = true; dismiss() }
            }.disabled(isSaving).accessibilityIdentifier("block_close")
        }
            ToolbarItem(placement: .primaryAction) {
                Button("Discard") { confirmingDiscard = true }
                    .disabled(isSaving || submitted).accessibilityIdentifier("block_discard")
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .interactiveDismissDisabled(true)
        .onAppear(perform: prepare)
        .onChange(of: draftData) { _, _ in _ = checkpoint() }
        .confirmationDialog("Discard this block draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Your saved program, progress and workout history stay intact.") }
        .confirmationDialog("Cancel this pending change?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel pending change", role: .destructive) { resolve(cancelPending: true) }
            Button("Keep pending", role: .cancel) {}
        } message: {
            Text("The server will prevent a late save of this proposal. If it already saved, its current result will be shown instead.")
        }
        .sheet(isPresented: $showingDayReuse) {
            if let proposal {
                WorkoutDayReuseView(program: proposal, sourceWeek: selectedWeek, protectedSlots: protectedSlots) { review in
                    guard ownerID == DIContainer.shared.authService.currentUserID, var current = self.proposal else { throw WorkoutBlockError.accountChanged }
                    let latest = workoutService.userPrograms.first { $0.id == program.id }
                    current.currentProgressIndex = max(current.currentProgressIndex ?? 0, latest?.currentProgressIndex ?? 0)
                    let protection = try isLocalDraft ? protectedSlots : protectedSlots.union(workoutService.protectedBlockSlots(in: program))
                    let updated = try WorkoutDayReuseRules.applying(review, to: current, protectedSlots: protection)
                    let previous = block; block = updated
                    guard checkpoint() else { block = previous; throw CocoaError(.fileWriteUnknown) }
                }
            }
        }
        .sheet(isPresented: $showingWeekCopy) {
            if let proposal {
                WorkoutWeekCopyView(program: proposal, sourceWeek: selectedWeek, protectedSlots: protectedSlots) { review, linked in
                    guard ownerID == DIContainer.shared.authService.currentUserID, var current = self.proposal else {
                        throw WorkoutBlockError.accountChanged
                    }
                    let activeProtection = try isLocalDraft ? [] : workoutService.protectedBlockSlots(in: program)
                    let latest = workoutService.userPrograms.first { $0.id == program.id }
                        ?? (workoutService.activeProgram?.id == program.id ? workoutService.activeProgram : nil)
                    current.currentProgressIndex = max(current.currentProgressIndex ?? 0, latest?.currentProgressIndex ?? 0)
                    let copied = try WorkoutWeekCopyRules.applying(review, to: current, linked: linked,
                        protectedSlots: protectedSlots.union(activeProtection))
                    let previous = self.block
                    self.block = copied
                    guard checkpoint() else { self.block = previous; throw CocoaError(.fileWriteUnknown) }
                    selectedWeek = review.destinationWeekIndex
                }
            }
        }
        .sheet(item: $activeSlot) { slot in
            RoutineEditorView(workoutService: workoutService, routine: slot.routine,
                draftScope: "\(scope)-slot-\(slot.index)",
                onKeepDraft: { routine in
                    pendingSlot = WorkoutBlockSlotEdit(index: slot.index, routine: routine)
                    _ = checkpoint()
                }, onDiscard: { pendingSlot = nil; _ = checkpoint() },
                onSave: { routine in
                    guard ownerID == DIContainer.shared.authService.currentUserID, var current = proposal else { throw WorkoutBlockError.accountChanged }
                    current.trainingBlock = try WorkoutWeekLinkRules.freezingProtectedWeeks(in: current, protectedSlots: protectedSlots)
                    current.trainingBlock = try WorkoutWeekLinkRules.detaching(week: slot.index / max(current.trainingBlock?.sessionsPerWeek ?? 1, 1), in: current)
                    guard var block = current.trainingBlock else { throw WorkoutBlockError.invalid }
                    let id = block.overrides.first { $0.slotIndex == slot.index }?.id ?? UUID().uuidString
                    block.overrides.removeAll { $0.slotIndex == slot.index }
                    block.overrides.append(WorkoutBlockSlotOverride(id: id, slotIndex: slot.index, routine: routine))
                    block.overrides.sort { $0.slotIndex < $1.slotIndex }
                    self.block = block
                    pendingSlot = nil
                    guard checkpoint() else { throw CocoaError(.fileWriteUnknown) }
                })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(program.name).appTextRole(.sectionTitle)
            Text(isLocalDraft ? "These targets belong only to your unsaved next-block proposal. Your current plan stays intact."
                : "Plan each week's targets. Completed and active sessions keep their saved prescriptions.")
                .appFont(size: 13).foregroundStyle(.secondary)
            Text("\(max(program.currentProgressIndex ?? 0, 0).formatted()) sessions passed · progress stays intact")
                .appFont(size: 13).foregroundStyle(.secondary)
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            TextField("Block name", text: Binding(get: { block?.name ?? "" }, set: { block?.name = $0 }), axis: .vertical)
                .lineLimit(1...3)
                .appTextRole(.control).accessibilityIdentifier("block_name")
            let minimumWeeks = max(1, ((max(program.currentProgressIndex ?? 0, 0) - 1) / max(block?.sessionsPerWeek ?? 1, 1)) + 1)
            Stepper("\(block?.weeks.count ?? 12) weeks", value: Binding(
                get: { block?.weeks.count ?? 12 }, set: resizeWeeks), in: min(minimumWeeks, 24)...24)
                .appFont(size: 17, weight: .medium)
                .accessibilityIdentifier("block_week_count")
            Text("Select a session to customize its targets.")
                .appFont(size: 13).foregroundStyle(.secondary)
        }
        .appSurface(.quiet)
    }

    private var weekOutline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Picker("Week", selection: $selectedWeek) {
                ForEach(0..<(block?.weeks.count ?? 0), id: \.self) { index in Text("Week \(index + 1)").tag(index) }
            }
            .accessibilityIdentifier("block_week_picker")
            if let block, block.weeks.indices.contains(selectedWeek) {
                TextField("Week name", text: Binding(get: { self.block?.weeks[selectedWeek].name ?? "" },
                                                      set: { self.block?.weeks[selectedWeek].name = $0 }))
                    .appTextRole(.control).accessibilityIdentifier("block_week_name")
                ForEach(0..<block.sessionsPerWeek, id: \.self) { day in sessionRow(selectedWeek * block.sessionsPerWeek + day) }
                Divider()
                DisclosureGroup {
                Toggle("Lighter week", isOn: Binding(get: { self.block?.weeks[selectedWeek].isDeload ?? false },
                                                    set: { self.block?.weeks[selectedWeek].isDeload = $0 }))
                    .accessibilityIdentifier("block_deload")
                Text("This labels the week. Review its session targets to choose lighter work.")
                    .appFont(size: 13).foregroundStyle(.secondary)
                if let sourceID = block.weeks[selectedWeek].linkedSourceWeekID,
                   let sourceWeek = block.weeks.first(where: { $0.id == sourceID }) {
                    Text("Targets linked to \(sourceWeek.name). Editing one day makes this week independent.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("block_link_summary")
                    Button {
                        do {
                            guard let proposal else { throw WorkoutBlockError.invalid }
                            self.block = try WorkoutWeekLinkRules.detaching(week: selectedWeek, in: proposal)
                            _ = checkpoint()
                        } catch { errorMessage = error.localizedDescription }
                    } label: {
                        Text("Make this week independent").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("block_detach_week")
                }
                if let adjustment = block.weeks[selectedWeek].deloadAdjustment {
                    Text("Reviewed lighter targets · \(adjustment.loadPercent.formatted())% load / \(adjustment.setPercent.formatted())% working sets. Original targets are kept for conditional Undo.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Button("Undo reviewed lighter targets") {
                        do {
                            guard let proposal else { throw WorkoutBlockError.invalid }
                            self.block = try WorkoutDeloadRules.undo(in: proposal, week: selectedWeek, protectedSlots: protectedSlots)
                            _ = checkpoint()
                        } catch { errorMessage = "This week changed or started after the review. Its current targets are kept. \(error.localizedDescription)" }
                    }.frame(minHeight: 44).accessibilityIdentifier("block_undo_deload")
                }
                Button("Review a lighter week and return") {
                    do {
                        guard let proposal else { throw WorkoutBlockError.invalid }
                        deloadReview = try WorkoutDeloadRules.review(program: proposal, week: selectedWeek, protectedSlots: protectedSlots)
                    } catch { errorMessage = error.localizedDescription }
                }.frame(minHeight: 44).accessibilityIdentifier("block_review_deload")
                if let deloadReview, deloadReview.weekIndex == selectedWeek {
                    Text(deloadReview.summary).appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("block_deload_review_summary")
                    HStack {
                        Button("Cancel review") { self.deloadReview = nil }.frame(minHeight: 44)
                        Button("Use reviewed lighter targets") {
                            do {
                                guard let proposal else { throw WorkoutBlockError.invalid }
                                self.block = try WorkoutDeloadRules.applying(deloadReview, to: proposal, protectedSlots: protectedSlots)
                                self.deloadReview = nil; _ = checkpoint()
                            } catch { errorMessage = error.localizedDescription }
                        }.frame(minHeight: 44).accessibilityIdentifier("block_apply_deload")
                    }
                    Text("Save the block to publish these targets. Cancel or discard the draft to retain the saved plan.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Button("Copy or reorder one session") { showingDayReuse = true }
                    .frame(minHeight: 44).disabled(pendingSlot != nil).accessibilityIdentifier("block_reuse_day")
                if block.weeks.count > 1 {
                    Button { showingWeekCopy = true } label: {
                        Label("Copy this week", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                    .disabled(pendingSlot != nil)
                    .accessibilityIdentifier("block_copy_week")
                    if pendingSlot != nil {
                        Text("Finish the unfinished session before copying a week.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                } label: {
                    Text("Week tools").accessibilityIdentifier("block_week_tools")
                }
                .tint(AppPalette.text)
            }
        }
        .appSurface(.quiet)
    }

    private func sessionRow(_ index: Int) -> some View {
        let routine = proposal.flatMap { $0.routine(forSlot: index) }
        let locked = index < (program.currentProgressIndex ?? 0) || protectedSlots.contains(index)
        return Button { openSession(index) } label: {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(index % max(block?.sessionsPerWeek ?? 1, 1) + 1) · \(routine?.name ?? "Unavailable session")")
                        .appTextRole(.control)
                    Text(locked ? "Saved or active · targets protected" : sessionTargetLabel(index))
                        .appFont(size: 13).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: locked ? "lock" : "chevron.right").appFont(size: 15).accessibilityHidden(true)
            }
            .frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(AppPalette.text).disabled(locked || routine == nil)
        .accessibilityIdentifier("block_session_\(index)")
    }

    private func sessionTargetLabel(_ index: Int) -> String {
        if let block, block.weeks.indices.contains(index / block.sessionsPerWeek),
           block.weeks[index / block.sessionsPerWeek].linkedSourceWeekID != nil { return "Linked week targets" }
        return block?.overrides.contains { $0.slotIndex == index } == true ? "Week-specific targets" : "Uses routine rotation"
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let message = errorMessage ?? (submitted ? nil : validationMessage) {
                Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("block_save_error")
            }
            if submitted && !didAccept && !cancellationConfirmed {
                Text("This submitted proposal is fixed for safe retry. Close keeps it on this device.")
                    .appFont(size: 13).foregroundStyle(.secondary)
                HStack {
                    Button { resolve(cancelPending: false) } label: {
                        Text("Check status").frame(minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("block_check_status")
                    Spacer()
                    Button { confirmingCancel = true } label: {
                        Text("Cancel pending").frame(minHeight: 44).contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("block_cancel_pending")
                }
                .appFont(size: 15).frame(minHeight: 44).disabled(isSaving)
            }
            Button(action: save) {
                if isSaving { ProgressView().accessibilityLabel("Saving block") } else { Text(didAccept || cancellationConfirmed ? "Done" : submitted ? "Retry save" : isLocalDraft ? "Use these targets" : "Save block") }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(isSaving || !isReady || (!submitted && validationMessage != nil))
            .accessibilityIdentifier("block_save")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.compact).background(.bar)
    }

    private func prepare() {
        guard baseline == nil else { return }
        ownerID = DIContainer.shared.authService.currentUserID ?? ""
        do {
            guard ownerID == program.userID, program.id != nil else { throw WorkoutBlockError.accountChanged }
            protectedSlots = try isLocalDraft ? [] : workoutService.protectedBlockSlots(in: program)
            if let saved = try store.load(WorkoutBlockEditorDraft.self, userID: ownerID, scope: scope)?.value {
                guard saved.baseline.id == program.id, saved.baseline.userID == ownerID else { throw WorkoutBlockError.accountChanged }
                guard initialNextSessionContext == nil else { throw WorkoutBlockError.changed }
                nextSessionContext = saved.nextSessionContext
                nextSessionHistoryFingerprint = saved.nextSessionHistoryFingerprint
                baseline = saved.baseline; block = saved.block
                if saved.submitted == true {
                    guard !isLocalDraft else { throw WorkoutBlockError.changed }
                    guard let data = saved.frozenSubmission else { throw WorkoutBlockError.invalid }
                    let frozen = try JSONDecoder().decode(WorkoutBlockSubmission.self, from: data)
                    guard frozen.baseline.userID == ownerID, frozen.baseline.id == program.id else { throw WorkoutBlockError.accountChanged }
                    baseline = frozen.baseline; block = frozen.block; submissionData = data
                }
                restoredDraft = true
                if let index = saved.pendingSlot, let routine = saved.pendingRoutine { pendingSlot = WorkoutBlockSlotEdit(index: index, routine: routine) }
            } else {
                nextSessionContext = initialNextSessionContext
                nextSessionHistoryFingerprint = initialNextSessionHistoryFingerprint
                baseline = program
                block = try initialBlock ?? program.trainingBlock ?? WorkoutBlockRules.createRepeatingBlock(for: program)
                block?.revisionID = UUID().uuidString
            }
            initialBlockData = blockData
            let initialSlot = pendingSlot?.index ?? nextSessionContext?.slotIndex ?? max(program.currentProgressIndex ?? 0, 0)
            selectedWeek = min(initialSlot / max(block?.sessionsPerWeek ?? 1, 1), max((block?.weeks.count ?? 1) - 1, 0))
            isReady = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func resizeWeeks(_ count: Int) {
        guard var block else { return }
        if count > block.weeks.count {
            for index in block.weeks.count..<count { block.weeks.append(WorkoutBlockWeek(name: "Week \(index + 1)")) }
        } else if count < block.weeks.count {
            do {
                guard var current = proposal else { throw WorkoutBlockError.invalid }
                let removedIDs = Set(block.weeks.dropFirst(count).map(\.id))
                for index in 0..<count where block.weeks[index].linkedSourceWeekID.map({ removedIDs.contains($0) }) == true {
                    current.trainingBlock = try WorkoutWeekLinkRules.detaching(week: index, in: current)
                }
                guard let detached = current.trainingBlock else { throw WorkoutBlockError.invalid }
                block = detached
            } catch { errorMessage = error.localizedDescription; return }
            block.weeks = Array(block.weeks.prefix(count))
            block.overrides.removeAll { $0.slotIndex >= count * block.sessionsPerWeek }
        }
        selectedWeek = min(selectedWeek, count - 1); self.block = block
    }

    private func openSession(_ index: Int) {
        guard pendingSlot == nil || pendingSlot?.index == index else {
            errorMessage = "Continue the unfinished session before editing another day."; return
        }
        guard let routine = proposal?.routine(forSlot: index)?.deepCopy() else { return }
        let slot = pendingSlot ?? WorkoutBlockSlotEdit(index: index, routine: routine)
        pendingSlot = slot
        if checkpoint() { activeSlot = slot }
    }

    @discardableResult private func checkpoint(force: Bool = false) -> Bool {
        guard !isClosing else { return true }
        guard isReady, let baseline, let block, ownerID == DIContainer.shared.authService.currentUserID else { return false }
        do {
            if !force, !restoredDraft, initialBlock == nil, !submitted, pendingSlot == nil, initialBlockData == blockData {
                // Opening and closing an untouched editor must not mask a later
                // saved block behind a stale local proposal.
                try store.remove(userID: ownerID, scope: scope)
                draftMessage = nil
                return true
            }
            try store.save(WorkoutBlockEditorDraft(baseline: baseline, block: block,
                pendingSlot: pendingSlot?.index, pendingRoutine: pendingSlot?.routine,
                submitted: submitted, frozenSubmission: submissionData,
            nextSessionContext: nextSessionContext, nextSessionHistoryFingerprint: nextSessionHistoryFingerprint), userID: ownerID, scope: scope)
            draftMessage = "Draft saved on this device."
            return true
        } catch { errorMessage = "Couldn't save this block draft on your device. Keep it open and try again."; return false }
    }

    private func save() {
        if didAccept || cancellationConfirmed { finishResolved(); return }
        guard !isSaving else { return }
        isSaving = true; errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if let onSaveLocalDraft {
                    guard let proposal, validationMessage == nil else { return }
                    try onSaveLocalDraft(proposal)
                    acceptedProgram = proposal; didAccept = true
                    finishResolved()
                    return
                }
                if nextSessionContext != nil {
                    // A late acknowledgement remains resolvable even when its old
                    // evidence is stale. Never re-submit stale unaccepted targets.
                    if let submissionData {
                        let frozen = try JSONDecoder().decode(WorkoutBlockSubmission.self, from: submissionData)
                        if let outcome = try await workoutService.resolveProgramBlock(expected: frozen.baseline,
                            block: frozen.block, cancelPending: false) {
                            guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
                            switch outcome {
                            case .accepted(let program): acceptedProgram = program; didAccept = true
                            case .cancelled: cancellationConfirmed = true
                            }
                            finishResolved()
                            return
                        }
                    }
                    try await validateNextSessionSource()
                }
                let frozen: WorkoutBlockSubmission
                if let submissionData { frozen = try JSONDecoder().decode(WorkoutBlockSubmission.self, from: submissionData) } else {
                    guard let baseline, let block, validationMessage == nil else { return }
                    frozen = WorkoutBlockSubmission(baseline: baseline, block: block)
                    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                    submissionData = try encoder.encode(frozen)
                    guard checkpoint(force: true) else { submissionData = nil; return }
                }
                acceptedProgram = try await workoutService.saveProgramBlock(expected: frozen.baseline, block: frozen.block)
                guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
                didAccept = true
                finishResolved()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func validateNextSessionSource() async throws {
        guard let context = nextSessionContext else { return }
        guard let fingerprint = nextSessionHistoryFingerprint,
              ownerID == DIContainer.shared.authService.currentUserID,
              let active = workoutService.activeProgram, active.id == context.programID else { throw WorkoutBlockError.accountChanged }
        let history = try await NextSessionHistory.load(program: active, service: workoutService)
        guard ownerID == DIContainer.shared.authService.currentUserID,
              let latest = workoutService.activeProgram, latest.id == context.programID else { throw WorkoutBlockError.accountChanged }
        try WorkoutNextSessionRules.validate(context, program: latest, ownerID: ownerID,
            protectedSlots: workoutService.protectedBlockSlots(in: latest))
        guard try NextSessionHistory.fingerprint(history) == fingerprint else { throw WorkoutBlockError.changed }
    }

    private func resolve(cancelPending: Bool) {
        guard !isSaving, let submissionData else { return }
        do {
            let frozen = try JSONDecoder().decode(WorkoutBlockSubmission.self, from: submissionData)
            isSaving = true; errorMessage = nil
            Task { @MainActor in
                do {
                    let result = try await workoutService.resolveProgramBlock(expected: frozen.baseline, block: frozen.block,
                                                                               cancelPending: cancelPending)
                    guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
                    switch result {
                    case .accepted(let program)?:
                        acceptedProgram = program; didAccept = true
                        errorMessage = program == nil ? "This proposal saved earlier. The program has since been removed."
                            : "This proposal was already saved. The current program is ready."
                    case .cancelled?:
                        cancellationConfirmed = true
                        finishResolved()
                    case nil:
                        errorMessage = "No accepted save was found. Retry this fixed proposal or cancel the pending change."
                    }
                } catch { errorMessage = error.localizedDescription }
                isSaving = false
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func finishResolved() {
        guard didAccept || cancellationConfirmed, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            try store.remove(userID: ownerID, scope: scope)
            if let acceptedProgram { onSave(acceptedProgram) }
            isClosing = true; dismiss()
        } catch {
            errorMessage = didAccept ? "Your block was saved. Tap Done to finish clearing its local draft."
                : "Cancellation was saved. Tap Done to finish clearing its local draft."
        }
    }

    static func hasUnfinishedDraft(programID: String, userID: String) throws -> Bool {
        try EditorDraftStore().load(WorkoutBlockEditorDraft.self, userID: userID,
            scope: "program-block-\(programID)") != nil
    }

    static func discardLocalDraft(programID: String, userID: String) throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw WorkoutBlockError.accountChanged }
        let store = EditorDraftStore(); let scope = "program-block-\(programID)"
        if let saved = try store.load(WorkoutBlockEditorDraft.self, userID: userID, scope: scope) {
            guard saved.value.baseline.id == programID, saved.value.baseline.userID == userID,
                  saved.value.submitted != true else { throw WorkoutBlockError.changed }
            if let pendingSlot = saved.value.pendingSlot { try store.remove(userID: userID, scope: "\(scope)-slot-\(pendingSlot)") }
            try store.remove(userID: userID, scope: scope)
        }
    }

    private func discard() {
        guard !submitted, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            if let pendingSlot { try store.remove(userID: ownerID, scope: "\(scope)-slot-\(pendingSlot.index)") }
            try store.remove(userID: ownerID, scope: scope)
            isClosing = true; dismiss()
        } catch { errorMessage = "Couldn't discard this draft. It has been kept; try again." }
    }
}

private struct WorkoutWeekCopyView: View {
    let program: WorkoutProgram
    let sourceWeek: Int
    let protectedSlots: Set<Int>
    let onApply: (WorkoutWeekCopyReview, Bool) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destinationWeek = 0
    @State private var linkTargets = false
    @State private var review: WorkoutWeekCopyReview?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Text("Reuse a week's targets").appTextRole(.sectionTitle)
                    Text("Copy the sessions below into a future week. Its current targets will be replaced when you save the block.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if let block = program.trainingBlock {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("From Week \(sourceWeek + 1) · \(block.weeks[sourceWeek].name)")
                                .appTextRole(.control).accessibilityIdentifier("block_copy_source")
                            Picker("To week", selection: $destinationWeek) {
                                ForEach(block.weeks.indices.filter { $0 != sourceWeek }, id: \.self) { index in
                                    Text("Week \(index + 1) · \(block.weeks[index].name)").tag(index)
                                }
                            }
                            .accessibilityIdentifier("block_copy_destination")
                        }
                        .appSurface(.quiet)
                    }
                    if let review {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("Replace Week \(review.destinationWeekIndex + 1) with:").appTextRole(.control)
                            ForEach(Array(review.sessionNames.enumerated()), id: \.offset) { day, name in
                                Text("Day \(day + 1) · \(name)").appTextRole(.secondary)
                            }
                            Text(review.isDeload ? "Lighter-week label included." : "Lighter-week label will be off.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        .appSurface(.quiet).accessibilityIdentifier("block_copy_preview")
                    }
                    Toggle("Link future target edits", isOn: $linkTargets)
                        .appTextRole(.control).accessibilityIdentifier("block_copy_link")
                    Text(linkTargets
                        ? "Future target edits in the source update this linked week. Editing a linked day makes its whole week independent. Names and lighter-week labels stay independent; saved and active weeks keep frozen targets."
                        : "This creates an independent copy. Later edits to either week affect only that week. Saved and active sessions are protected. Your destination keeps its name.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .accessibilityIdentifier("block_copy_error")
                    }
                }
                .padding(AppSpacing.screenHorizontal)
            }
            .accessibilityIdentifier("block_copy_scroll")
            .background(AppPalette.canvas)
            .navigationTitle("Copy week").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.accessibilityIdentifier("block_copy_cancel")
            } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let review else { return }
                    do { try onApply(review, linkTargets); dismiss() } catch { errorMessage = error.localizedDescription }
                } label: {
                    Text("Use in Week \(destinationWeek + 1)").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(review == nil)
                .accessibilityIdentifier("block_copy_apply")
                .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.compact).background(.bar)
            }
            .onAppear {
                let choices = program.trainingBlock?.weeks.indices.filter { $0 != sourceWeek } ?? []
                destinationWeek = choices.first { !WorkoutWeekCopyRules.destinationIsProtected($0, in: program, protectedSlots: protectedSlots) }
                    ?? choices.first ?? 0
                updateReview()
            }
            .onChange(of: destinationWeek) { _, _ in updateReview() }
        }
    }

    private func updateReview() {
        do {
            review = try WorkoutWeekCopyRules.review(in: program, sourceWeek: sourceWeek,
                destinationWeek: destinationWeek, protectedSlots: protectedSlots)
            errorMessage = nil
        } catch {
            review = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkoutDayReuseView: View {
    let program: WorkoutProgram
    let sourceWeek: Int
    let protectedSlots: Set<Int>
    let onApply: (WorkoutDayReuseReview) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source = 0
    @State private var destination = 0
    @State private var mode = WorkoutDayReuseReview.Mode.copy
    @State private var review: WorkoutDayReuseReview?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reuse", selection: $mode) { ForEach(WorkoutDayReuseReview.Mode.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Source session", selection: $source) { ForEach(0..<program.totalSlots, id: \.self) { Text(label($0)).tag($0) } }
                    Picker("Destination session", selection: $destination) { ForEach(0..<program.totalSlots, id: \.self) { Text(label($0)).tag($0) } }
                    Text("Only future, inactive destinations may change. Swap also protects the source. The session identity stays with its destination; copied movement/set slots are new, and history remains with its original receipt.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Button("Review exact sessions") {
                        do { review = try WorkoutDayReuseRules.review(program: program, sourceSlot: source, destinationSlot: destination, mode: mode, protectedSlots: protectedSlots); errorMessage = nil } catch { review = nil; errorMessage = error.localizedDescription }
                    }.frame(minHeight: 44).accessibilityIdentifier("block_day_reuse_preview")
                }
                if let review {
                    Section("Proposed targets") {
                        ForEach(Array(review.summary.enumerated()), id: \.offset) { _, summary in Text(summary).appTextRole(.secondary) }
                        Button("Use reviewed session reuse") {
                            do { try onApply(review); dismiss() } catch { errorMessage = error.localizedDescription }
                        }.frame(minHeight: 44).accessibilityIdentifier("block_day_reuse_apply")
                        Text("This updates the local block draft. Its Save publishes the complete frozen review.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppPalette.caution) }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Reuse one session").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { source = min(sourceWeek * max(program.trainingBlock?.sessionsPerWeek ?? 1, 1), max(program.totalSlots - 1, 0)); destination = min(max(program.currentProgressIndex ?? 0, source + 1), max(program.totalSlots - 1, 0)) }
            .onChange(of: source) { _, _ in review = nil }
            .onChange(of: destination) { _, _ in review = nil }
            .onChange(of: mode) { _, _ in review = nil }
        }
    }
    private func label(_ slot: Int) -> String {
        let locked = slot < (program.currentProgressIndex ?? 0) || protectedSlots.contains(slot)
        return "\(slot + 1). \(program.routine(forSlot: slot)?.name ?? "Session")\(locked ? " · protected" : "")"
    }
}
