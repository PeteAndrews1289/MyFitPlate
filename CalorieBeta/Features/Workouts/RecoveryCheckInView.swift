import MyFitPlateCore
import SwiftUI

struct RecoveryCheckInRequest: Identifiable {
    let id = UUID()
    let userID: String
    let group: RecoveryMuscleGroup
    let existing: RecoveryCheckIn?
}

private struct RecoveryCheckInDraft: Codable {
    let owner: String
    var expected: RecoveryCheckIn?
    var observation: RecoveryCheckIn
}

struct RecoveryCheckInView: View {
    let request: RecoveryCheckInRequest
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecoveryCheckInDraft?
    @State private var fingerprint: String?
    @State private var errorMessage: String?
    @State private var isReady = false
    private let store = EditorDraftStore()
    private var scope: String { "recovery-check-in-editor-\(request.group.rawValue)" }
    var body: some View {
        Form {
            Section {
                Text("A dated observation for planning, not an injury assessment. Saved on this device for this account.")
                    .foregroundStyle(.secondary)
                if let draft {
                    DatePicker("Observed", selection: field(\.observedAt, fallback: Date()), in: ...Date())
                    Picker("Soreness", selection: field(\.soreness, fallback: nil)) {
                        Text("Unknown / not recorded").tag(RecoveryRating?.none)
                        ForEach(RecoveryRating.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Fatigue", selection: field(\.fatigue, fallback: nil)) {
                        Text("Unknown / not recorded").tag(RecoveryRating?.none)
                        ForEach(RecoveryRating.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    Toggle("Pain or injury concern", isOn: field(\.painOrInjury, fallback: false))
                    TextField("Optional note", text: field(\.note, fallback: ""), axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("recovery_check_in_note")
                    if draft.observation.needsPainReview {
                        Label("Stop or change painful movements. A check-in cannot clear an injury; seek qualified help for persistent or concerning symptoms.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppPalette.caution).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: { Text(request.group.displayName) }
        }
        .appFormStyle()
        .accessibilityElement(children: .contain).accessibilityIdentifier("recovery_check_in_form")
        .navigationTitle("Recovery check-in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                if let errorMessage { Text(errorMessage).foregroundStyle(AppPalette.critical).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recovery_check_in_error") }
                Button("Save check-in") { save() }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!isReady || draft == nil).accessibilityIdentifier("recovery_check_in_save")
            }.padding().background(AppPalette.canvas)
                .accessibilityElement(children: .contain).accessibilityIdentifier("recovery_check_in_footer")
        }
        .onAppear(perform: restore)
    }
    private func field<Value>(_ path: WritableKeyPath<RecoveryCheckIn, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { draft?.observation[keyPath: path] ?? fallback }, set: { value in
            guard isReady, var updated = draft else { return }
            updated.observation[keyPath: path] = value
            persist(updated)
        })
    }
    private func restore() {
        guard !isReady else { return }
        guard DIContainer.shared.authService.currentUserID == request.userID else { errorMessage = RecoveryCheckInError.accountChanged.localizedDescription; return }
        do {
            let saved = try store.load(RecoveryCheckInDraft.self, userID: request.userID, scope: scope)?.value
            if let saved {
                guard saved.owner == request.userID, saved.observation.group == request.group else { throw RecoveryCheckInError.changed }
                draft = saved; fingerprint = try PlanFingerprint.make(saved)
            } else {
                let value = RecoveryCheckInDraft(owner: request.userID, expected: request.existing,
                    observation: request.existing ?? RecoveryCheckIn(group: request.group))
                try store.save(value, userID: request.userID, scope: scope)
                draft = value; fingerprint = try PlanFingerprint.make(value)
            }
            isReady = true
        } catch { errorMessage = "The earlier check-in review is preserved. " + error.localizedDescription }
    }
    private func persist(_ value: RecoveryCheckInDraft) {
        do {
            guard DIContainer.shared.authService.currentUserID == request.userID,
                  try store.load(RecoveryCheckInDraft.self, userID: request.userID, scope: scope).map({ try PlanFingerprint.make($0.value) }) == fingerprint else { throw RecoveryCheckInError.changed }
            try store.save(value, userID: request.userID, scope: scope)
            draft = value; fingerprint = try PlanFingerprint.make(value); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func save() {
        guard let draft else { return }
        do {
            guard try store.load(RecoveryCheckInDraft.self, userID: request.userID, scope: scope).map({ try PlanFingerprint.make($0.value) }) == fingerprint else { throw RecoveryCheckInError.changed }
            _ = try RecoveryCheckInStore().save(draft.observation, expected: draft.expected, userID: request.userID)
            if let fingerprint { _ = try store.removeIfUnchanged(RecoveryCheckInDraft.self, userID: request.userID, scope: scope, fingerprint: fingerprint) }
            onSaved(); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RecoveryBlockEditRequest: Identifiable {
    let id = UUID()
    let program: WorkoutProgram
    let block: WorkoutProgramBlock
}

struct RecoveryPlanningActionsView: View {
    let evidence: RecoveryRegionEvidence
    @ObservedObject var workoutService: WorkoutService
    @State private var selectedWeek = 0
    @State private var review: WorkoutDeloadReview?
    @State private var reviewedProgram: WorkoutProgram?
    @State private var blockRequest: RecoveryBlockEditRequest?
    @State private var showingProgram = false
    @State private var message: String?
    private var availableWeeks: [Int] {
        guard let program = workoutService.activeProgram, let block = program.trainingBlock else { return [] }
        let protected = (try? workoutService.protectedBlockSlots(in: program)) ?? Set(0..<block.totalSlots)
        return block.weeks.indices.filter { week in
            let slots = (week * block.sessionsPerWeek)..<((week + 1) * block.sessionsPerWeek)
            return !slots.contains { $0 < max(program.currentProgressIndex ?? 0, 0) || protected.contains($0) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Choose your next step").appTextRole(.control)
            Text("These options open a review. Completed sessions, active workouts and program progress stay protected.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            Button("Keep my plan") { review = nil; message = "Plan kept. No targets or workout records were changed." }
                .frame(minHeight: 44).accessibilityIdentifier("recovery_keep_plan")
            if let program = workoutService.activeProgram {
                if let block = program.trainingBlock, !availableWeeks.isEmpty {
                    Picker("Future week to review", selection: $selectedWeek) {
                        ForEach(availableWeeks, id: \.self) { Text(block.weeks[$0].name).tag($0) }
                    }
                    Button("Review a lighter week") { prepareLighten(program) }
                        .frame(minHeight: 44).accessibilityIdentifier("recovery_review_lighten")
                } else {
                    Text("No wholly future editable week is available. Open your program to review upcoming movements; active work is never adjusted here.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if let review {
                    Text(review.summary).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("This reviews the whole selected future week, not only \(evidence.group.displayName.lowercased()). Loads target 90% and normal sets 75%, rounded to supported equipment.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Button("Open lighter week editor") { openReviewedBlock() }
                        .frame(minHeight: 44).accessibilityIdentifier("recovery_open_lighten_editor")
                }
                Button("Review movement substitutions") { showingProgram = true }
                    .frame(minHeight: 44).accessibilityIdentifier("recovery_review_substitution")
                Text("In your program, choose the future session and replace the movement that needs a change. Review and save in the block editor.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            } else {
                Text("Choose a saved program from Train to review future sessions.").appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if let message { Text(message).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recovery_plan_feedback") }
        }
        .onAppear { selectedWeek = availableWeeks.first ?? 0 }
        .onChange(of: selectedWeek) { _, _ in review = nil }
        .sheet(item: $blockRequest) { request in
            NavigationStack { WorkoutBlockEditorView(program: request.program, workoutService: workoutService, initialBlock: request.block) { _ in
                message = "Reviewed future targets saved. Logged sessions and progress are unchanged."
                review = nil
            } }
        }
        .sheet(isPresented: $showingProgram) {
            if let program = workoutService.activeProgram { NavigationStack { ProgramDetailView(program: program) } }
        }
    }
    private func prepareLighten(_ program: WorkoutProgram) {
        do {
            guard availableWeeks.contains(selectedWeek) else { throw WorkoutBlockError.progressChanged }
            review = try WorkoutDeloadRules.review(program: program, week: selectedWeek, loadPercent: 90, setPercent: 75,
                protectedSlots: workoutService.protectedBlockSlots(in: program))
            reviewedProgram = program; message = nil
        } catch { message = error.localizedDescription; review = nil }
    }
    private func openReviewedBlock() {
        do {
            guard let review, let program = reviewedProgram,
                  workoutService.activeProgram?.id == program.id else { throw WorkoutBlockError.changed }
            let block = try WorkoutDeloadRules.applying(review, to: program, protectedSlots: workoutService.protectedBlockSlots(in: program))
            blockRequest = .init(program: program, block: block)
        } catch { message = error.localizedDescription }
    }
}
