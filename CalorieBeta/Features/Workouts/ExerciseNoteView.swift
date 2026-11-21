import MyFitPlateCore
import SwiftUI

struct ExerciseNoteView: View {
    let exercise: RoutineExercise
    let routineID: String
    let ownerID: String
    let onSave: (WorkoutCueSnapshot) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scope = WorkoutCueScope.session
    @State private var baseline: WorkoutScopedCue?
    @State private var errorMessage: String?
    @State private var didRestore = false
    private let drafts = EditorDraftStore()
    private struct Draft: Codable { var text: String; var scope: WorkoutCueScope; var baseline: WorkoutScopedCue? }
    private var draftScope: String { "cue-editor-\(routineID)-\(exercise.id)" }
    var body: some View {
        NavigationStack {
            Form {
                Section(exercise.name) {
                    Picker("Cue applies to", selection: $scope) { ForEach(WorkoutCueScope.allCases) { Text($0.title).tag($0) } }
                        .accessibilityIdentifier("exercise_note_scope")
                    Text(WorkoutSetMath.contextLabel(exercise)).appTextRole(.caption).foregroundStyle(.secondary)
                    Text("Routine and setup cues take precedence over a broad variant cue. A session snapshot keeps the cue used today even if future notes change.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Your cue") {
                    TextEditor(text: $text).frame(minHeight: 180).accessibilityIdentifier("exercise_note_text")
                    if let legacy = PinnedNotesManager.shared.getPinnedNote(for: exercise.name), !legacy.isEmpty {
                        DisclosureGroup("Legacy name pin · review its scope") {
                            Text(legacy).textSelection(.enabled)
                            Button("Use this text in selected scope") { text = legacy }.frame(minHeight: 44)
                            Text("The old name pin is retained. It is not automatically merged into a canonical movement or different setup.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Exercise cue").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Keep draft & close") { if checkpoint() { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Save cue", action: save).accessibilityIdentifier("exercise_note_save") }
            }
            .onAppear(perform: restore)
            .onChange(of: text) { _, _ in if didRestore { _ = checkpoint() } }
            .onChange(of: scope) { _, value in
                guard didRestore else { return }
                do { baseline = value == .session ? nil : try WorkoutScopedCueStore().load(exercise: exercise, routineID: routineID, scope: value, userID: ownerID); _ = checkpoint() } catch { errorMessage = error.localizedDescription }
            }
        }
    }
    private func restore() {
        guard !didRestore else { return }
        do {
            if let saved = try drafts.load(Draft.self, userID: ownerID, scope: draftScope)?.value { text = saved.text; scope = saved.scope; baseline = saved.baseline } else { text = exercise.cueSnapshot?.text ?? exercise.notes ?? "" }
            didRestore = true
        } catch { errorMessage = "The previous cue draft is kept; it could not reopen. \(error.localizedDescription)" }
    }
    private func checkpoint() -> Bool {
        guard DIContainer.shared.authService.currentUserID == ownerID else { return false }
        do { try drafts.save(Draft(text: text, scope: scope, baseline: baseline), userID: ownerID, scope: draftScope); return true } catch { errorMessage = "This cue could not checkpoint. Keep the editor open and retry."; return false }
    }
    private func save() {
        guard DIContainer.shared.authService.currentUserID == ownerID, text.count <= 8_000 else { return }
        do {
            let snapshot: WorkoutCueSnapshot
            if scope == .session { snapshot = WorkoutCueSnapshot(text: text, scope: .session) } else {
                let saved = try WorkoutScopedCueStore().save(text: text, exercise: exercise, routineID: routineID, scope: scope, expected: baseline, userID: ownerID)
                snapshot = saved?.snapshot ?? WorkoutCueSnapshot(text: "", scope: scope)
                baseline = saved
            }
            try onSave(snapshot)
            try drafts.remove(userID: ownerID, scope: draftScope)
            dismiss()
        } catch { errorMessage = "Your cue is kept. Review a concurrent change or retry the save. \(error.localizedDescription)" }
    }
}
