import MyFitPlateCore

import SwiftUI

struct ProgramCreatorView: View {
    @ObservedObject var workoutService: WorkoutService
    var programToEdit: WorkoutProgram?
    var isPresentedModally = false
    var proposedEdits: WorkoutProgram?
    /// Returns an unsaved proposal to its owning review; never publishes a program.
    var onReviewDraft: ((WorkoutProgram) throws -> Void)?
    var reviewDraftScope: String?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var routines: [WorkoutRoutine] = []
    @State private var startDate = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    @State private var routineToEdit: WorkoutRoutine?
    @State private var didSetUp = false
    @State private var isSaving = false
    @State private var mergeReview: WorkoutProgramMergeReview?
    @State private var mergeChoices: [String: WorkoutEditorConflictChoice] = [:]
    @State private var submittedEditCommand: WorkoutProgramEditCommand?
    @State private var runCommitments: [TrainingRunCommitment] = []

    @State private var saveError: String?
    @State private var stableID = UUID().uuidString
    @State private var createdAt = Date()
    @State private var originalDraft: Data?
    @State private var confirmingDiscard = false
    @State private var routineToDelete: WorkoutRoutine?
    @State private var showingRoutineLibrary = false
    @State private var baseline: WorkoutProgram?
    @State private var pendingRoutine: WorkoutRoutine?
    @State private var draftMessage: String?
    @State private var ownerID = ""
    @State private var isClosing = false
    @State private var trainingBlock: WorkoutProgramBlock?
    private let draftStore = EditorDraftStore()

    private var isEditMode: Bool { programToEdit != nil }
    private var draftScope: String { reviewDraftScope ?? "program-\(programToEdit?.id ?? "new")" }
    private func routineScope(_ routine: WorkoutRoutine) -> String { "\(draftScope)-routine-\(routine.id)" }

    private var canSave: Bool {
        (submittedEditCommand != nil || validationMessage == nil) && !isSaving
    }

    private var latestCanonicalProgram: WorkoutProgram? {
        guard isEditMode else { return nil }
        return workoutService.userPrograms.first { $0.id == stableID }
            ?? (workoutService.activeProgram?.id == stableID ? workoutService.activeProgram : nil)
            ?? programToEdit
    }

    private var authoritativeBlock: WorkoutProgramBlock? {
        if let canonical = latestCanonicalProgram { return canonical.trainingBlock }
        return trainingBlock
    }

    private var validationMessage: String? {
        if didSetUp, let canonical = latestCanonicalProgram {
            do { try WorkoutProgramEditRules.validateOrdinarySave(draft, against: canonical) } catch { return error.localizedDescription }
        }
        if pendingRoutine != nil { return "Finish or discard the routine draft before saving this plan." }
        if name.trimmed.isEmpty { return "Name your program before saving." }
        if routines.isEmpty { return "Add at least one routine to the rotation." }
        if routines.contains(where: { $0.name.trimmed.isEmpty || $0.exercises.isEmpty || $0.exercises.contains(where: { $0.sets.isEmpty }) }) {
            return "Each routine needs a name, exercises, and set targets."
        }
        if selectedDaysOfWeek.isEmpty { return "Choose at least one training day." }
        if let trainingBlock = authoritativeBlock, selectedDaysOfWeek.count != trainingBlock.sessionsPerWeek {
            return "Keep \(trainingBlock.sessionsPerWeek) training days for this authored block."
        }
        return nil
    }

    private var draft: WorkoutProgram {
        var value = WorkoutProgram(
            id: stableID, userID: ownerID,
            name: name.trimmed, dateCreated: createdAt,
            routines: routines, startDate: startDate, daysOfWeek: selectedDaysOfWeek.sorted(),
            currentProgressIndex: programToEdit?.currentProgressIndex ?? 0, skippedIndices: programToEdit?.skippedIndices,
            trainingBlock: authoritativeBlock
        )
        value.progressEpoch = isEditMode ? latestCanonicalProgram?.progressEpoch : stableID
        value.slotDateSnapshots = latestCanonicalProgram?.slotDateSnapshots
        if startDate == latestCanonicalProgram?.startDate && selectedDaysOfWeek.sorted() == latestCanonicalProgram?.daysOfWeek?.sorted() {
            value.scheduleAnchorDay = latestCanonicalProgram?.scheduleAnchorDay
        } else { value.scheduleAnchorDay = TrainingCalendarDay(startDate) }
        return value
    }

    private var draftData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(draft)
    }

    private var hasChanges: Bool {
        didSetUp && (originalDraft != draftData || pendingRoutine != nil)
    }

    private var exerciseCount: Int {
        routines.reduce(0) { $0 + $1.exercises.count }
    }

    private var totalSetCount: Int {
        routines.reduce(0) { partial, routine in
            partial + routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let submittedEditCommand {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Submitted changes are frozen").appTextRole(.sectionTitle)
                        Text("Check the permanent receipt, retry the same review or cancel it safely. Later saved changes and completed workouts stay intact.").appTextRole(.secondary)
                        Button("Check save status") { resolveEdit(submittedEditCommand, cancel: false) }.frame(minHeight: 44)
                        Button("Cancel pending save") { resolveEdit(submittedEditCommand, cancel: true) }.frame(minHeight: 44)
                    }.appSurface(.emphasized).accessibilityIdentifier("program_edit_pending")
                }
                if let mergeReview {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Review changed fields & sessions").appTextRole(.sectionTitle)
                        ForEach(mergeReview.conflicts) { conflict in
                            Text(conflict.title).appTextRole(.control)
                            Text("Your draft\n" + conflict.localSummary).appTextRole(.secondary)
                            Text("Saved version\n" + conflict.savedSummary).appTextRole(.secondary).foregroundStyle(.secondary)
                            Picker("Keep version", selection: Binding(get: { mergeChoices[conflict.id] }, set: { mergeChoices[conflict.id] = $0 })) {
                                Text("Choose explicitly").tag(Optional<WorkoutEditorConflictChoice>.none)
                                Text("My draft").tag(Optional(WorkoutEditorConflictChoice.mine))
                                Text("Saved version").tag(Optional(WorkoutEditorConflictChoice.saved))
                            }
                        }
                        Button("Resolve reviewed choices") { resolveMerge(mergeReview) }.frame(minHeight: 44)
                            .disabled(mergeReview.conflicts.contains { mergeChoices[$0.id] == nil })
                    }.appSurface(.quiet).accessibilityIdentifier("program_edit_conflicts")
                }
                ProgramDetailsSection(name: $name)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("program_builder_details")
                    .disabled(submittedEditCommand != nil)

                if let draftMessage {
                    Label(draftMessage, systemImage: "doc.badge.clock")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("program_draft_status")
                }

                if let pendingRoutine {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Unfinished routine").appTextRole(.control)
                        HStack {
                            Button("Continue editing") { routineToEdit = pendingRoutine }
                                .accessibilityIdentifier("program_continue_routine")
                            Spacer()
                            Button("Discard", role: .destructive) { discardPendingRoutine() }
                        }
                        .frame(minHeight: 44)
                    }
                    .appSurface(.quiet)
                }

                if authoritativeBlock == nil { RoutineSelectionList(
                    routines: routines,
                    onEdit: openRoutine,
                    onDelete: { routineToDelete = $0 },
                    onMove: moveRoutine,
                    onAdd: addRoutine
                )
                .accessibilityIdentifier("program_builder_routines")
                .disabled(submittedEditCommand != nil)
                } else {
                    Text("This program has authored weeks. Open its training block to edit individual sessions and targets.")
                        .appTextRole(.secondary).foregroundStyle(.secondary).appSurface(.quiet)
                }

                if !routines.isEmpty {
                    Text("\(routines.count) routines · \(exerciseCount) exercises · \(totalSetCount) sets")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }

                if authoritativeBlock == nil && !workoutService.userRoutines.isEmpty {
                    Button { showingRoutineLibrary = true } label: {
                        Label("Use a saved routine", systemImage: "folder")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("program_builder_saved_routine")
                    .disabled(submittedEditCommand != nil)
                }
                ProgramScheduleSection(
                    startDate: $startDate,
                    selectedDaysOfWeek: $selectedDaysOfWeek
                )
                .accessibilityIdentifier("program_builder_schedule")
                .disabled(submittedEditCommand != nil)
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(isEditMode ? "Review upcoming dates" : "First two weeks").appTextRole(.sectionTitle)
                    Text("Completed dates stay fixed. This edits upcoming sessions of the existing block; use Repeat / adjust next block to create a separate phase. Overlapping runs are shown for your decision.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    let changes = WorkoutScheduleComparison.changes(from: latestCanonicalProgram, to: draft, runs: runCommitments)
                    Text("\(changes.count) future slot dates change.").appTextRole(.secondary)
                    ForEach(Array(changes.prefix(14))) { change in
                        Text("Slot \(change.slotIndex + 1) · \(change.title): \(change.oldDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled") → \(change.proposedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled")")
                            .appTextRole(.secondary)
                        if !change.runCollisions.isEmpty { Text("Also planned: " + change.runCollisions.joined(separator: ", ")).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
                    }
                    if changes.count > 14 {
                        DisclosureGroup("All affected future dates") {
                            ForEach(Array(changes.dropFirst(14))) { change in
                                Text("Slot \(change.slotIndex + 1): \(change.oldDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled") → \(change.proposedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled")")
                                    .appTextRole(.secondary)
                            }
                        }
                    }
                }.appSurface(.quiet).accessibilityIdentifier("program_schedule_date_review")

            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("program_builder")
        .background(AppPalette.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .disabled(isSaving)
        .navigationTitle(onReviewDraft != nil ? "Edit proposal" : isEditMode ? "Edit Program" : "New Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(AppPalette.text)
                    .accessibilityLabel("Close program builder")
                    .accessibilityIdentifier("program_builder_close")
                    .disabled(isSaving)
                }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(hasChanges || isSaving)
        .safeAreaInset(edge: .bottom) {
            ProgramSaveBar(
                isEditMode: isEditMode,
                isSaving: isSaving,
                isEnabled: canSave,
                message: saveError ?? validationMessage,
                reviewOnly: onReviewDraft != nil,
                action: saveProgram
            )
        }
        .onAppear(perform: setupView)
        .onChange(of: draftData) { _, _ in checkpoint() }
        .confirmationDialog("Keep your program draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Keep draft & close") { if checkpoint() { isClosing = true; dismiss() } }
            Button("Discard Changes", role: .destructive) { discardAndClose() }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Remove routine from this plan?", isPresented: Binding(
            get: { routineToDelete != nil }, set: { if !$0 { routineToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Routine", role: .destructive) {
                if let routine = routineToDelete { deleteRoutine(routine) }
                routineToDelete = nil
            }
        } message: {
            Text("Workout history and routines in your library are kept.")
        }
        .sheet(isPresented: $showingRoutineLibrary) {
            NavigationStack {
                List(workoutService.userRoutines.filter { !$0.exercises.isEmpty }) { routine in
                    Button {
                        guard let copy = routine.deepCopy() else { return }
                        copy.id = UUID().uuidString
                        routines.append(copy)
                        showingRoutineLibrary = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(routine.name)
                            Text("\(routine.exercises.count) exercises").foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Saved routines")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingRoutineLibrary = false } } }
            }
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                draftScope: routineScope(routine),
                onKeepDraft: { pendingRoutine = $0; checkpoint() },
                onDiscard: { pendingRoutine = nil; checkpoint() },
                onSave: updateRoutine
            )
        }
    }

    private func setupView() {
        guard !didSetUp else { return }
        ownerID = DIContainer.shared.authService.currentUserID ?? ""
        if let program = programToEdit {
            stableID = program.id ?? stableID
            createdAt = program.dateCreated
            name = program.name
            routines = program.routines.compactMap { $0.deepCopy() }
            startDate = program.startDate ?? Date()
            selectedDaysOfWeek = program.daysOfWeek ?? []
            trainingBlock = program.trainingBlock
        }
        baseline = draft
        originalDraft = draftData
        if let proposedEdits {
            if onReviewDraft != nil { stableID = proposedEdits.id ?? stableID; createdAt = proposedEdits.dateCreated }
            name = proposedEdits.name; routines = proposedEdits.routines.compactMap { $0.deepCopy() }
            startDate = proposedEdits.startDate ?? startDate; selectedDaysOfWeek = proposedEdits.daysOfWeek ?? selectedDaysOfWeek
            if onReviewDraft != nil { baseline = draft; originalDraft = draftData }
        }
        do { runCommitments = try TrainingRunCommitmentStore().entries(userID: ownerID) } catch { draftMessage = "Planned run collisions could not refresh. Your draft is kept." }

        do {
            if let saved = try draftStore.load(ProgramEditorDraft.self, userID: ownerID, scope: draftScope) {
                let restored = saved.value
                stableID = restored.program.id ?? stableID
                createdAt = restored.program.dateCreated
                name = restored.program.name
                routines = restored.program.routines
                startDate = restored.program.startDate ?? startDate
                selectedDaysOfWeek = restored.program.daysOfWeek ?? []
                trainingBlock = restored.program.trainingBlock
                baseline = restored.baseline
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                originalDraft = try encoder.encode(restored.baseline)
                pendingRoutine = restored.pendingRoutine
                routineToEdit = restored.pendingRoutine
                draftMessage = "Restored your unfinished draft."
            }
        } catch { draftMessage = "Couldn't restore the previous draft. It has been kept on this device." }
        do { submittedEditCommand = try draftStore.load(WorkoutProgramEditCommand.self, userID: ownerID, scope: "program-edit-command-\(stableID)")?.value } catch { saveError = "The submitted edit could not reopen; its checkpoint is kept. \(error.localizedDescription)" }
        didSetUp = true
    }

    private func openRoutine(_ routine: WorkoutRoutine) {
        guard pendingRoutine == nil || pendingRoutine?.id == routine.id else {
            saveError = "Finish the unfinished routine first."
            return
        }
        pendingRoutine = routine
        checkpoint()
        routineToEdit = routine
    }

    private func addRoutine() {
        let routine = WorkoutRoutine(
            userID: DIContainer.shared.authService.currentUserID ?? "",
            name: "",
            dateCreated: Date()
        )
        openRoutine(routine)
    }

    private func updateRoutine(_ updatedRoutine: WorkoutRoutine) throws {
        if let index = routines.firstIndex(where: { $0.id == updatedRoutine.id }) { routines[index] = updatedRoutine } else { routines.append(updatedRoutine) }
        pendingRoutine = nil
        guard checkpoint() else { throw CocoaError(.fileWriteUnknown) }
    }

    private func deleteRoutine(_ routine: WorkoutRoutine) {
        routines.removeAll { $0.id == routine.id }
    }

    private func moveRoutine(_ index: Int, _ offset: Int) {
        let target = index + offset
        guard routines.indices.contains(index), routines.indices.contains(target) else { return }
        routines.swapAt(index, target)
    }

    private func saveProgram() {
        guard DIContainer.shared.authService.currentUserID == ownerID, !isSaving else { return }
        if let command = submittedEditCommand { submitEdit(command); return }
        guard canSave else { return }
        saveError = nil
        if let onReviewDraft {
            do {
                try onReviewDraft(draft)
                try draftStore.remove(userID: ownerID, scope: draftScope)
                isClosing = true; dismiss()
            } catch { saveError = error.localizedDescription }
            return
        }
        if let latest = latestCanonicalProgram, let baseline {
            do {
                let review = try WorkoutProgramMergeRules.review(baseline: baseline, local: draft, saved: latest)
                if !review.conflicts.isEmpty { mergeReview = review; mergeChoices = [:]; return }
                let proposed = try WorkoutProgramMergeRules.resolving(review, choices: [:], latest: latest)
                let command = try WorkoutProgramEditCommand(expected: latest, proposed: proposed,
                    protectedSlots: workoutService.protectedBlockSlots(in: latest))
                try draftStore.save(command, userID: ownerID, scope: "program-edit-command-\(stableID)")
                submittedEditCommand = command; submitEdit(command)
            } catch { saveError = error.localizedDescription }
            return
        }
        isSaving = true
        let program = draft
        Task { @MainActor in
            if await workoutService.saveProgram(program) != nil { finishAcceptedEdit() } else { saveError = "Could not save. Your plan is still here; try again." }
            isSaving = false
        }
    }
    private func resolveMerge(_ review: WorkoutProgramMergeReview) {
        do {
            guard let latest = latestCanonicalProgram else { throw WorkoutBlockError.unavailable }
            let merged = try WorkoutProgramMergeRules.resolving(review, choices: mergeChoices, latest: latest)
            name = merged.name; routines = merged.routines; startDate = merged.startDate ?? Date(); selectedDaysOfWeek = merged.daysOfWeek ?? []
            baseline = latest; mergeReview = nil; mergeChoices = [:]; _ = checkpoint()
        } catch { saveError = error.localizedDescription }
    }
    private func submitEdit(_ command: WorkoutProgramEditCommand) {
        isSaving = true
        Task { @MainActor in
            do {
                _ = try await workoutService.saveReviewedProgramEdit(command)
                guard DIContainer.shared.authService.currentUserID == ownerID else { throw WorkoutBlockError.accountChanged }
                finishAcceptedEdit()
            } catch { saveError = "This exact proposal is kept. Check status or cancel before editing again. \(error.localizedDescription)" }
            isSaving = false
        }
    }
    private func resolveEdit(_ command: WorkoutProgramEditCommand, cancel: Bool) {
        guard !isSaving, DIContainer.shared.authService.currentUserID == ownerID else { return }
        isSaving = true
        Task { @MainActor in
            do {
                let result = try await DIContainer.shared.workoutRepository.resolveProgramEdit(userID: ownerID, command: command, cancelPending: cancel)
                guard DIContainer.shared.authService.currentUserID == ownerID else { throw WorkoutBlockError.accountChanged }
                switch result {
                case .accepted: finishAcceptedEdit()
                case .cancelled:
                    try draftStore.remove(userID: ownerID, scope: "program-edit-command-\(stableID)")
                    submittedEditCommand = nil; saveError = "Pending save cancelled. Review the latest saved version before submitting a new edit."
                case .pending: saveError = "No acceptance is recorded yet. Retry this exact proposal or cancel it safely."
                }
            } catch { saveError = error.localizedDescription }
            isSaving = false
        }
    }
    private func finishAcceptedEdit() {
        do {
            try draftStore.remove(userID: ownerID, scope: "program-edit-command-\(stableID)")
            try draftStore.remove(userID: ownerID, scope: draftScope)
            submittedEditCommand = nil; isClosing = true; dismiss()
        } catch { saveError = "Your checked save was accepted. Check status again to clear its local draft." }
    }

    @discardableResult
    private func checkpoint() -> Bool {
        guard didSetUp, !isClosing, DIContainer.shared.authService.currentUserID == ownerID else { return false }
        if submittedEditCommand != nil { return true }
        do {
            if !hasChanges {
                // An untouched editor must not become a stale draft that masks a later saved edit.
                // Validate before cleanup so an unreadable checkpoint is preserved for recovery.
                _ = try draftStore.load(ProgramEditorDraft.self, userID: ownerID, scope: draftScope)
                try draftStore.remove(userID: ownerID, scope: draftScope)
                draftMessage = nil
                return true
            }
            try draftStore.save(ProgramEditorDraft(program: draft, baseline: baseline ?? draft, pendingRoutine: pendingRoutine),
                                userID: ownerID, scope: draftScope)
            draftMessage = "Draft saved on this device."
            return true
        } catch {
            draftMessage = "Couldn't save this draft on your device. Keep the editor open and try again."
            return false
        }
    }

    private func discardPendingRoutine() {
        guard let pendingRoutine else { return }
        do {
            try draftStore.remove(userID: ownerID, scope: routineScope(pendingRoutine))
            self.pendingRoutine = nil
            checkpoint()
        } catch { saveError = "Couldn't discard the routine draft. Try again." }
    }

    private func discardAndClose() {
        do {
            if let pendingRoutine { try draftStore.remove(userID: ownerID, scope: routineScope(pendingRoutine)) }
            try draftStore.remove(userID: ownerID, scope: draftScope)
            isClosing = true
            dismiss()
        } catch { saveError = "Couldn't discard the draft. Try again." }
    }
}

private struct ProgramDetailsSection: View {
    @Binding var name: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROGRAM NAME")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)

                TextField("12 Week Strength", text: $name, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal)
                    .lineLimit(1...4)
                    .appTextRole(.control)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .accessibilityIdentifier("program_builder_name")
            }
            .appSurface(.quiet)
        }
    }
}

private struct RoutineSelectionList: View {
    let routines: [WorkoutRoutine]
    let onEdit: (WorkoutRoutine) -> Void
    let onDelete: (WorkoutRoutine) -> Void
    let onMove: (Int, Int) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Routine Rotation",
                subtitle: "Workouts repeat in this order on your selected training days."
            ) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add routine")
            }

            if routines.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Image(systemName: "list.number")
                        .appFont(size: 24, weight: .semibold)
                        .foregroundStyle(AppPalette.brandText)
                        .accessibilityHidden(true)

                    Text("Start the rotation")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text("Add your first workout day, then choose exercises and set targets.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)

                    Button(action: onAdd) {
                        Label("Add First Routine", systemImage: "plus")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .appSurface(.quiet)
            } else {
                VStack(spacing: AppSpacing.compact) {
                    ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                        ProgramRoutineRow(
                            position: index + 1,
                            routine: routine,
                            onEdit: { onEdit(routine) },
                            onDelete: { onDelete(routine) },
                            onMoveUp: index > 0 ? { onMove(index, -1) } : nil,
                            onMoveDown: index < routines.count - 1 ? { onMove(index, 1) } : nil
                        )
                    }
                }
            }
        }
    }
}

private struct ProgramRoutineRow: View {
    let position: Int
    let routine: WorkoutRoutine
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    private var setCount: Int {
        routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
    }

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Text("\(position)")
                .appTextRole(.control)
                .monospacedDigit()
                .foregroundStyle(AppPalette.text)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name.trimmed.isEmpty ? "Untitled Routine" : routine.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(routine.exercises.count) exercises • \(setCount) sets")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit Routine", systemImage: "pencil", action: onEdit)
                if let onMoveUp { Button("Move Earlier", systemImage: "arrow.up", action: onMoveUp) }
                if let onMoveDown { Button("Move Later", systemImage: "arrow.down", action: onMoveDown) }
                Button("Remove from Plan", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Options for \(routine.name.trimmed.isEmpty ? "untitled routine" : routine.name)")
        }
        .padding(AppSpacing.row)
        .appSurface(.quiet, padding: 0)
    }
}

private struct ProgramScheduleSection: View {
    @Binding var startDate: Date
    @Binding var selectedDaysOfWeek: [Int]

    private var frequencyDescription: String {
        switch selectedDaysOfWeek.count {
        case 0: "Choose at least one training day"
        case 1: "1 workout each week"
        default: "\(selectedDaysOfWeek.count) workouts each week"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Weekly Schedule",
                subtitle: frequencyDescription
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppDateField("Start Date", selection: $startDate)
                    .appTextRole(.control)

                Divider()

                WeekDaySelector(selectedDays: $selectedDaysOfWeek)
            }
            .appSurface(.quiet)
        }
    }
}

private struct ProgramSaveBar: View {
    let isEditMode: Bool
    let isSaving: Bool
    let isEnabled: Bool
    let message: String?
    let reviewOnly: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let message {
                Text(message).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("program_builder_feedback")
            }
            Button(action: action) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Saving program")
                } else {
                    Label(reviewOnly ? "Use reviewed proposal" : isEditMode ? "Save Changes" : "Create Program", systemImage: "checkmark")
                }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("program_builder_save")
            .disabled(!isEnabled)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.compact)
        .padding(.bottom, AppSpacing.compact)
        .background(.bar)
    }
}
