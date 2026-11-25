import MyFitPlateCore

import SwiftUI

struct RoutineEditorView: View {
    @ObservedObject var workoutService: WorkoutService
    @StateObject private var viewModel: RoutineEditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showingGroupEditor = false
    @State private var pendingStarter: RoutineEditorTemplate?
    @State private var starterUndo: WorkoutRoutine?
    @State private var starterAcceptedFingerprint: String?
    @State private var saveError: String?
    @State private var confirmingDiscard = false
    @State private var didRestore = false
    @State private var isClosing = false
    @State private var draftMessage: String?
    private let ownerID: String
    private let draftScope: String
    private let draftStore = EditorDraftStore()
    private let onKeepDraft: ((WorkoutRoutine) -> Void)?
    private let onDiscard: (() -> Void)?
    private let onSave: (WorkoutRoutine) async throws -> Void

    init(workoutService: WorkoutService, routine: WorkoutRoutine, draftScope: String? = nil,
         onKeepDraft: ((WorkoutRoutine) -> Void)? = nil, onDiscard: (() -> Void)? = nil,
         onSave: @escaping (WorkoutRoutine) async throws -> Void) {
        self.workoutService = workoutService
        self.onSave = onSave
        self.ownerID = DIContainer.shared.authService.currentUserID ?? ""
        self.draftScope = draftScope ?? "routine-\(routine.name.trimmed.isEmpty && routine.exercises.isEmpty ? "new" : routine.id)"
        self.onKeepDraft = onKeepDraft
        self.onDiscard = onDiscard
        self._viewModel = StateObject(wrappedValue: RoutineEditorViewModel(routine: routine, onSave: { _ in }))
    }

    private var draftData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(viewModel.draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    RoutineBasicsCard(
                        routineName: $viewModel.routineName,
                        routineNotes: $viewModel.routineNotes
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("routine_builder_details")

                    if !viewModel.exercises.isEmpty {
                        Text("\(viewModel.exercises.count) exercises · \(viewModel.totalSetCount) sets · about \(viewModel.estimatedMinutes) min")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }

                    if let draftMessage {
                        Label(draftMessage, systemImage: "doc.badge.clock")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("routine_draft_status")
                    }

                    if viewModel.exercises.isEmpty { starterTemplates }
                    if let starterUndo, starterAcceptedFingerprint == (try? WorkoutBlockRules.fingerprint(viewModel.draft)) {
                        Button("Undo starter change") {
                            viewModel.routineName = starterUndo.name; viewModel.routineNotes = starterUndo.notes ?? ""; viewModel.exercises = starterUndo.exercises
                            self.starterUndo = nil
                        }.frame(minHeight: 44)
                    }
                    RoutineExerciseBuilderCard(
                        exercises: viewModel.exercises,
                        onAddExercise: { viewModel.showingExercisePicker = true },
                        onEdit: { viewModel.exerciseToEdit = $0 },
                        onDuplicate: { viewModel.duplicateExercise($0) },
                        onDelete: { viewModel.deleteExercise($0) },
                        onMove: { viewModel.moveExercise($0, direction: $1) },
                        onReorder: { viewModel.moveExercise(id: $0, to: $1) }
                    )
                    .accessibilityIdentifier("routine_builder_exercises")

                    if viewModel.exercises.filter({ $0.type == .strength }).count >= 2 {
                        Button("Rounds & rest", systemImage: "link") { showingGroupEditor = true }
                            .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("routine_author_group")
                    }
                    if !viewModel.exercises.isEmpty {
                        DisclosureGroup {
                            starterTemplates.padding(.top, AppSpacing.row)
                        } label: {
                            Text("Add from a starter").accessibilityIdentifier("routine_builder_starters")
                        }
                        .tint(AppPalette.text)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .accessibilityIdentifier("routine_builder")
            .background(AppPalette.canvas.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving)
            .navigationTitle(viewModel.routineName.trimmed.isEmpty ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if viewModel.hasChanges { confirmingDiscard = true } else { discardAndDismiss() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(AppPalette.text)
                    .accessibilityLabel("Close routine editor")
                    .accessibilityIdentifier("routine_builder_close")
                    .disabled(isSaving)
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let message = saveError ?? viewModel.validationMessage {
                        Text(message).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("routine_builder_feedback")
                    }
                    Button(action: saveAndDismiss) {
                        Label(isSaving ? "Saving routine…" : "Save Routine", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .accessibilityIdentifier("routine_builder_save")
                    .disabled(!viewModel.canSave || isSaving)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(.bar)
            }
            .interactiveDismissDisabled(viewModel.hasChanges || isSaving)
            .onAppear(perform: restoreDraft)
            .onChange(of: draftData) { _, _ in checkpoint() }
            .confirmationDialog("Use this starter?", isPresented: Binding(get: { pendingStarter != nil }, set: { if !$0 { pendingStarter = nil } }), titleVisibility: .visible) {
                if let template = pendingStarter {
                    Button("Append \(template.exercises.count) movements") { applyStarter(template, replace: false); pendingStarter = nil }
                    Button("Replace this draft", role: .destructive) { applyStarter(template, replace: true); pendingStarter = nil }
                        .disabled(viewModel.exercises.contains { $0.sets.contains(where: \.isCompleted) })
                }
                Button("Keep current routine", role: .cancel) { pendingStarter = nil }
            } message: {
                Text((pendingStarter?.exercises.map(\.name).joined(separator: ", ") ?? "") + ". Append retains existing movements; Replace changes this unsaved draft only. Recorded sets are protected.")
            }
            .confirmationDialog("Keep your routine draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Keep draft & close") {
                    if checkpoint() {
                        onKeepDraft?(viewModel.draft)
                        isClosing = true
                        dismiss()
                    }
                }
                Button("Discard Changes", role: .destructive) { discardAndDismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(isPresented: $viewModel.showingExercisePicker) {
                ExercisePickerView(onSelectMultiple: { drafts in
                    for draft in drafts { viewModel.addExercise(from: draft) }; viewModel.showingExercisePicker = false
                }) { draft in
                    viewModel.addExercise(from: draft)
                    viewModel.showingExercisePicker = false
                }
            }
            .sheet(isPresented: $showingGroupEditor) {
                WorkoutGroupEditorView(exercises: viewModel.exercises) { viewModel.exercises = $0 }
            }
            .sheet(item: $viewModel.exerciseToEdit) { exercise in
                ExerciseSetEditorView(
                    exercise: exercise,
                    onSave: { updatedExercise in
                        viewModel.updateExercise(updatedExercise)
                    }
                )
            }
        }
    }

    private var starterTemplates: some View {
        RoutineTemplateStrip(
            templates: RoutineEditorTemplate.templates,
            onApply: { template in
                if viewModel.exercises.isEmpty { applyStarter(template, replace: false) } else { pendingStarter = template }
            }
        )
        .accessibilityIdentifier("routine_builder_templates")
    }

    private func applyStarter(_ template: RoutineEditorTemplate, replace: Bool) {
        starterUndo = viewModel.draft.deepCopy()
        if replace { viewModel.exercises = [] }
        viewModel.applyTemplate(template)
        starterAcceptedFingerprint = try? WorkoutBlockRules.fingerprint(viewModel.draft)
    }

    private func saveAndDismiss() {
        guard viewModel.canSave, !isSaving, DIContainer.shared.authService.currentUserID == ownerID else { return }
        isSaving = true
        saveError = nil
        let draft = viewModel.draft
        Task { @MainActor in
            do {
                try await onSave(draft)
                try draftStore.remove(userID: ownerID, scope: draftScope)
                isClosing = true
                dismiss()
            } catch {
                saveError = "Could not save. Your changes are still here; try again."
            }
            isSaving = false
        }
    }

    private func restoreDraft() {
        guard !didRestore else { return }
        do {
            if let saved = try draftStore.load(RoutineEditorDraft.self, userID: ownerID, scope: draftScope) {
                viewModel.restore(saved.value)
                draftMessage = "Restored your unfinished routine."
            }
        } catch { draftMessage = "Couldn't restore the previous draft. It has been kept on this device." }
        didRestore = true
    }

    @discardableResult
    private func checkpoint() -> Bool {
        guard didRestore, !isClosing, DIContainer.shared.authService.currentUserID == ownerID else { return false }
        do {
            if !viewModel.hasChanges {
                _ = try draftStore.load(RoutineEditorDraft.self, userID: ownerID, scope: draftScope)
                try draftStore.remove(userID: ownerID, scope: draftScope)
                draftMessage = nil
                return true
            }
            try draftStore.save(viewModel.checkpoint, userID: ownerID, scope: draftScope)
            draftMessage = "Draft saved on this device."
            return true
        } catch {
            draftMessage = "Couldn't save this draft on your device. Keep the editor open and try again."
            return false
        }
    }

    private func discardAndDismiss() {
        do {
            try draftStore.remove(userID: ownerID, scope: draftScope)
            onDiscard?()
            isClosing = true
            dismiss()
        } catch { saveError = "Couldn't discard the routine draft. Try again." }
    }
}

private struct WorkoutGroupEditorView: View {
    let exercises: [RoutineExercise]
    let onSave: ([RoutineExercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var members: [String] = []
    @State private var restAfterRound = 90
    @State private var transitionRest = 0
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose partners in round order. Warm-ups stay with their movement; working rounds follow the order below, including unequal set counts.")
                        .appTextRole(.secondary)
                    ForEach(exercises.filter { $0.type == .strength }) { exercise in
                        Toggle(exercise.name, isOn: Binding(get: { members.contains(exercise.id) }, set: { enabled in
                            if enabled { members.append(exercise.id) } else { members.removeAll { $0 == exercise.id } }
                        }))
                    }
                }
                Section("Round order") {
                    ForEach(Array(members.enumerated()), id: \.element) { index, id in
                        HStack {
                            Text("\(index + 1). \(exercises.first { $0.id == id }?.name ?? "Movement")")
                            Spacer()
                            Button("Up") { members.swapAt(index, index - 1) }.disabled(index == 0)
                                .frame(minHeight: 44).accessibilityLabel("Move partner \(index + 1) up")
                        }
                    }
                    Stepper("Between partners: \(transitionRest) sec", value: $transitionRest, in: 0...300, step: 15)
                    Stepper("After round: \(restAfterRound) sec", value: $restAfterRound, in: 0...900, step: 15)
                }
                Section {
                    Button("Use this reviewed group") {
                        do {
                            let rest = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element, $0.offset == members.count - 1 ? restAfterRound : transitionRest) })
                            let group = WorkoutExerciseGroup(memberSlotIDs: members, transitionRestSeconds: rest)
                            onSave(try WorkoutExerciseGroupRules.applying(group, to: exercises)); dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled(members.count < 2 || members.count > 8).frame(minHeight: 44)
                        .accessibilityIdentifier("routine_apply_group")
                    Button("Clear authored groups") {
                        onSave(exercises.map { original in var value = original; value.groupPlan = nil; value.supersetGroupID = nil; return value }); dismiss()
                    }.frame(minHeight: 44)
                    Text("This updates the routine draft. Its normal Save publishes the complete reviewed session.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppPalette.caution) }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Rounds & rest").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
