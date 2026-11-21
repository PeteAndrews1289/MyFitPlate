import MyFitPlateCore
import SwiftUI

/// Pending requests remain reachable after the source program is archived or deleted.
struct WorkoutMigrationRecoveryLink: View {
    @ObservedObject var workoutService: WorkoutService
    @State private var pending: [WorkoutMigrationRollbackCommand] = []
    @State private var selected: WorkoutMigrationRollbackCommand?
    var body: some View {
        ForEach(pending) { command in
            Button("Resume original-rotation restore review") { selected = command }
                .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("migration_resume_pending")
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .workoutSyncStateChanged)) { _ in refresh() }
        .sheet(item: $selected, onDismiss: refresh) { command in
            if let expected = try? command.expected() {
                WorkoutMigrationRestoreView(program: expected, migration: command.migration, workoutService: workoutService, onChanged: { _ in })
            }
        }
    }
    private func refresh() {
        guard let owner = DIContainer.shared.authService.currentUserID else { pending = []; return }
        pending = (try? EditorDraftStore().valuesMatchingScope(WorkoutMigrationRollbackCommand.self, userID: owner,
            scopeForValue: { WorkoutMigrationRollbackDraftStore.scope(programID: $0.programID) })) ?? []
    }
}

struct WorkoutMigrationHistoryView: View {
    let program: WorkoutProgram
    @ObservedObject var workoutService: WorkoutService
    let onChanged: (WorkoutProgram) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var records: [WorkoutLegacyMigrationRecord] = []
    @State private var selection: WorkoutLegacyMigrationRecord?
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Original rotation snapshots are saved when a legacy program first adopts authored weeks. Restoring requires a separate review and keeps current progress and workout logs.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if loading { ProgressView("Checking saved originals…") }
                    if let message { Text(message).foregroundStyle(AppPalette.caution) }
                    if !loading && records.isEmpty {
                        Text("No original snapshot is available. Older adoptions made before version history was introduced cannot be reconstructed.")
                    }
                    Button("Refresh saved originals") { Task { await load() } }
                }
                ForEach(records) { record in
                    Button { selection = record } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((try? record.original().name) ?? "Original rotation").font(.headline)
                            Text(record.recordedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                            Text(record.restoredByOperationID == nil ? "Review original and restore options" : "Original restored · independent copy available")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("migration_history_\(record.id)")
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("migration_history")
            .navigationTitle("Original rotations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .sheet(item: $selection, onDismiss: { Task { await load() } }) { record in
                WorkoutMigrationRestoreView(program: program, migration: record, workoutService: workoutService, onChanged: onChanged)
            }
        }
    }

    @MainActor private func load() async {
        guard !loading, let id = program.id, DIContainer.shared.authService.currentUserID == program.userID else { return }
        loading = true; defer { loading = false }
        do {
            let saved = try await workoutService.fetchLegacyMigrations(programID: id)
            guard DIContainer.shared.authService.currentUserID == program.userID else { records = []; return }
            records = saved; message = nil
            if let pending = try WorkoutMigrationRollbackDraftStore().load(userID: program.userID, programID: id) {
                selection = pending.migration
            }
        } catch { self.message = error.localizedDescription }
    }
}

private struct WorkoutMigrationRestoreView: View {
    let program: WorkoutProgram
    let migration: WorkoutLegacyMigrationRecord
    @ObservedObject var workoutService: WorkoutService
    let onChanged: (WorkoutProgram) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed: WorkoutMigrationRollbackCommand?
    @State private var pending: WorkoutMigrationRollbackCommand?
    @State private var copy: WorkoutProgram?
    @State private var busy = false
    @State private var message: String?
    @State private var completed = false
    @State private var acknowledged = false
    private let drafts = WorkoutMigrationRollbackDraftStore()
    private var latest: WorkoutProgram {
        workoutService.userPrograms.first { $0.id == program.id }
            ?? (workoutService.activeProgram?.id == program.id ? workoutService.activeProgram : nil) ?? program
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Original rotation") {
                    if let original = try? migration.original() {
                        Text(original.name).font(.headline)
                        Text("\(original.routines.count) routines · \(original.daysOfWeek?.count ?? 0) training days each week")
                        Text(original.routines.map(\.name).joined(separator: " → "))
                        Text("Original snapshot: \(original.currentProgressIndex ?? 0) of \(original.totalSlots) slots passed. This number is evidence only; restoring keeps your current pointer, skips and saved logs.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("Restore review") {
                    Text("Return to the original repeating rotation by removing authored weeks, including their future target and date variations. The program ID, original routine rotation, start date, current progress and workout history stay attached to this program.")
                    if let original = try? migration.original() {
                        Text("Schedule length: \(latest.totalSlots) current slots → \(original.totalSlots) original slots. Passed slots keep the same work and dates.")
                        DisclosureGroup("Review target and date differences") {
                            let changes = restoreDifferences(original: original)
                            if changes.isEmpty { Text("Every current slot has the same routine targets and date in the original rotation.") }
                            ForEach(Array(changes.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline) }
                        }
                    }
                    Text("Later program edits or performed authored variations can prevent an exact restore. An active workout must be finished or discarded first.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if migration.restoredByOperationID != nil { Text("This adoption was already restored.").foregroundStyle(.secondary) }
                    if let pending {
                        Label("A frozen restore request is saved on this device.", systemImage: "arrow.clockwise.circle")
                            .accessibilityIdentifier("migration_restore_pending")
                        Text("Check its saved status or retry the exact request. Cancel creates a server fence, so a late response cannot apply a cancelled restore.")
                        Button("Retry exact restore") { submit(pending) }.accessibilityIdentifier("migration_restore_retry")
                        Button("Check saved status") { resolve(pending, cancel: false) }.accessibilityIdentifier("migration_restore_status")
                        Button("Cancel pending restore", role: .destructive) { resolve(pending, cancel: true) }.accessibilityIdentifier("migration_restore_cancel")
                    } else if !completed && migration.restoredByOperationID == nil {
                        if let reviewed {
                            Text("Reviewed current progress: \((try? reviewed.expected().currentProgressIndex) ?? 0) slots passed.")
                            Toggle("I reviewed restoring the original rotation", isOn: $acknowledged)
                            Button("Restore original rotation") { submit(reviewed) }
                                .disabled(!acknowledged).accessibilityIdentifier("migration_restore_confirm")
                        } else {
                            Button("Review restore against current program") { review() }.accessibilityIdentifier("migration_restore_review")
                        }
                    }
                    if let message { Text(message).foregroundStyle(completed ? .secondary : AppPalette.caution).accessibilityIdentifier("migration_restore_message") }
                    if completed {
                        Button("Back to original rotations") { dismiss() }
                            .accessibilityIdentifier("migration_restore_done")
                    }
                    if busy { ProgressView("Checking saved program…") }
                }
                Section("Independent original copy") {
                    Text("Open the original rotation as a new program draft. Review its name, schedule and targets before saving. Your current program stays in place and activation is a separate choice.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Review original as a new copy") {
                        do { copy = try WorkoutMigrationRollbackRules.independentCopy(of: migration) } catch { message = error.localizedDescription }
                    }.disabled(pending != nil).accessibilityIdentifier("migration_independent_copy")
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle()).disabled(busy)
            .accessibilityElement(children: .contain).accessibilityIdentifier("migration_restore_review_screen")
            .navigationTitle("Review original").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .task { restorePending() }
            .sheet(item: $copy) { proposal in
                NavigationStack {
                    ProgramCreatorView(workoutService: workoutService, isPresentedModally: true, proposedEdits: proposal,
                        reviewDraftScope: "migration-original-copy-\(migration.programID)-\(migration.id)")
                }
            }
        }
    }

    private func checkOwner() throws {
        guard DIContainer.shared.authService.currentUserID == migration.userID else { throw WorkoutMigrationError.accountChanged }
    }
    private func restoreDifferences(original: WorkoutProgram) -> [String] {
        let current = latest
        return (0..<max(current.totalSlots, original.totalSlots)).compactMap { slot in
            let before = current.routine(forSlot: slot), after = original.routine(forSlot: slot)
            let sameRoutine = (try? before.map { try WorkoutBlockRules.fingerprint($0) }) == (try? after.map { try WorkoutBlockRules.fingerprint($0) })
            guard !sameRoutine || current.date(forSlot: slot) != original.date(forSlot: slot) else { return nil }
            func describe(_ routine: WorkoutRoutine?, date: Date?) -> String {
                guard let routine else { return "Outside this schedule" }
                let targets = routine.exercises.map { exercise in
                    "\(exercise.name): \(exercise.sets.map { $0.prescription?.targetText ?? $0.target ?? "Manual target" }.joined(separator: ", "))"
                }.joined(separator: "; ")
                return "\(routine.name), \(date?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled"). \(targets)"
            }
            return "Slot \(slot + 1)\nCurrent: \(describe(before, date: current.date(forSlot: slot)))\nOriginal: \(describe(after, date: original.date(forSlot: slot)))"
        }
    }
    private func restorePending() {
        do { try checkOwner(); pending = try drafts.load(userID: migration.userID, programID: migration.programID) } catch { message = error.localizedDescription }
    }
    private func review() {
        do {
            try checkOwner()
            let command = try WorkoutMigrationRollbackCommand(migration: migration, expected: latest)
            _ = try WorkoutMigrationRollbackRules.applying(command, to: latest, record: migration,
                protectedSlots: workoutService.protectedBlockSlots(in: latest))
            reviewed = command; message = nil; acknowledged = false
        } catch { message = error.localizedDescription }
    }
    private func submit(_ command: WorkoutMigrationRollbackCommand) {
        do { try checkOwner(); try drafts.freeze(command); pending = command } catch { message = error.localizedDescription; return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let saved = try await workoutService.restoreLegacyMigration(command)
                try finish(command, saved: saved, text: "Original rotation restored. Current progress and logs were kept.")
            } catch { message = error.localizedDescription }
        }
    }
    private func resolve(_ command: WorkoutMigrationRollbackCommand, cancel: Bool) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try checkOwner()
                switch try await workoutService.resolveLegacyMigration(command, cancelPending: cancel) {
                case .pending: message = "No saved outcome yet. The exact pending request is kept."
                case .accepted(let saved): try finish(command, saved: saved, text: "Restore was saved. Current program and logs are kept.")
                case .cancelled: try finish(command, saved: nil, text: "Pending restore cancelled. Your program was kept.")
                }
            } catch { message = error.localizedDescription }
        }
    }
    private func finish(_ command: WorkoutMigrationRollbackCommand, saved: WorkoutProgram?, text: String) throws {
        try checkOwner()
        guard try drafts.removeIfUnchanged(command) else { throw WorkoutMigrationError.changed }
        if let saved { onChanged(saved) }
        pending = nil; reviewed = nil; completed = true; message = text
    }
}
