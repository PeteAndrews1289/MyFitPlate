import MyFitPlateCore
import SwiftUI

/// An explicit day agenda: planned slots and actual events are separate rows.
struct TrainingCalendarAgendaView: View {
    @State var program: WorkoutProgram
    let logs: [WorkoutSessionLog]
    @ObservedObject var workoutService: WorkoutService
    let onUpdate: (WorkoutProgram) -> Void
    let onStart: (WorkoutRoutine, Int) -> Void
    let onReview: (WorkoutSessionLog) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var commitments: [TrainingRunCommitment] = []
    @State private var runs: [Run] = []
    @State private var selectedSlot = -1
    @State private var moveDate = Date()
    @State private var moveReview: WorkoutScheduleMoveReview?
    @State private var proposedBlock: WorkoutProgramBlock?
    @State private var errorMessage: String?
    @State private var selectedRunPlanID = ""
    private let ownerID = DIContainer.shared.authService.currentUserID
    private var plans: [RunWorkoutPlan] {
        RunWorkoutPlan.builtinTemplates(metric: true) + RunWorkoutPlanStore().customPlans
    }
    private var slots: [Int] {
        (0..<program.totalSlots).filter { program.date(forSlot: $0).map { Calendar.current.isDate($0, inSameDayAs: day) } == true }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Agenda day", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.compact).accessibilityIdentifier("training_agenda_date")
                    Text("Planned commitments and actual receipts stay separate, including late completions. Browsing dates never starts a session.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Planned strength") {
                    ForEach(slots, id: \.self) { slot in
                        if let routine = program.routine(forSlot: slot) {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text("Slot \(slot + 1) · \(routine.name)").appTextRole(.control)
                                let skipped = (program.skippedIndices ?? []).contains(slot)
                                Text(skipped ? "Explicitly skipped" : slot < (program.currentProgressIndex ?? 0) ? "Passed · see actual receipts below" : "Planned")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                                if slot >= (program.currentProgressIndex ?? 0) {
                                    Button("Review move") { selectedSlot = slot; moveDate = program.date(forSlot: slot) ?? day; moveReview = nil }
                                        .frame(minHeight: 44).accessibilityIdentifier("training_move_\(slot)")
                                    Button("Start this session") { onStart(routine, slot); dismiss() }.frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    if slots.isEmpty { Text("No planned strength sessions on this day.").foregroundStyle(.secondary) }
                }
                if selectedSlot >= 0 {
                    Section("Move slot \(selectedSlot + 1) · future only") {
                        DatePicker("Proposed date", selection: $moveDate, in: Date()..., displayedComponents: .date)
                        Button("Review dates and collisions") { reviewMove() }.frame(minHeight: 44)
                            .accessibilityIdentifier("training_review_move")
                        if let review = moveReview {
                            Text("\(review.oldDate.formatted(date: .abbreviated, time: .omitted)) → \(review.newDate.formatted(date: .abbreviated, time: .omitted))")
                            Text(review.collisions.isEmpty ? "No other planned sessions on that day." : "Also planned: " + review.collisions.joined(separator: ", "))
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            Text("Overlaps are information. You decide whether to train twice or choose another day. The next screen freezes and saves this reviewed block change.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            Button("Review save") {
                                do {
                                    proposedBlock = try WorkoutScheduleReviewRules.applying(review, to: program,
                                        protectedSlots: workoutService.protectedBlockSlots(in: program))
                                } catch { errorMessage = error.localizedDescription }
                            }.frame(minHeight: 44).accessibilityIdentifier("training_apply_move")
                        }
                    }
                }
                Section("Recorded strength") {
                    ForEach(Array(logs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.enumerated()), id: \.offset) { _, log in
                        Button { onReview(log); dismiss() } label: {
                            VStack(alignment: .leading) {
                                Text(log.completedExercises.map(\.exerciseName).prefix(3).joined(separator: ", "))
                                if let slot = log.programContext?.slotIndex, let planned = program.date(forSlot: slot) {
                                    Text("Planned \(planned.formatted(date: .abbreviated, time: .omitted)) · actual \(log.date.formatted(date: .abbreviated, time: .shortened))")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(minHeight: 44)
                    }
                }
                Section("Planned runs") {
                    ForEach(commitments.filter { $0.day == TrainingCalendarDay(day) }) { item in
                        HStack {
                            Text(item.plan.name)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                do { guard let ownerID else { throw WorkoutBlockError.accountChanged }; try TrainingRunCommitmentStore().remove(id: item.id, userID: ownerID); loadCommitments() } catch { errorMessage = error.localizedDescription }
                            }.frame(minHeight: 44)
                        }
                    }
                    Picker("Run workout", selection: $selectedRunPlanID) {
                        Text("Choose a run").tag("")
                        ForEach(plans) { Text($0.name).tag($0.id) }
                    }
                    Button("Plan this run on selected day") {
                        do {
                            guard let ownerID, let plan = plans.first(where: { $0.id == selectedRunPlanID }) else { throw WorkoutBlockError.invalid }
                            try TrainingRunCommitmentStore().save(TrainingRunCommitment(date: day, plan: plan), userID: ownerID)
                            loadCommitments()
                        } catch { errorMessage = error.localizedDescription }
                    }.disabled(selectedRunPlanID.isEmpty).frame(minHeight: 44)
                }
                Section("Actual runs") {
                    ForEach(runs.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }) { run in
                        Text("Run · \(run.startDate.formatted(date: .omitted, time: .shortened))")
                    }
                    Text("Health and locally saved runs are receipts; planned runs are not automatically marked completed by a date match.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityIdentifier("training_calendar_agenda")
            .navigationTitle("Training agenda").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                loadCommitments()
                guard let ownerID else { return }
                RunImportService().fetchLifetimeRuns(userID: ownerID) { result in
                    guard DIContainer.shared.authService.currentUserID == ownerID else { return }
                    if case .success(let values) = result { runs = values } else { errorMessage = "Running history could not refresh. Planned sessions remain available." }
                }
            }
            .sheet(item: $proposedBlock) { block in
                NavigationStack {
                    WorkoutBlockEditorView(program: program, workoutService: workoutService, initialBlock: block) { saved in
                        program = saved; onUpdate(saved); proposedBlock = nil; moveReview = nil; selectedSlot = -1
                    }
                }
            }
        }
    }
    private func loadCommitments() {
        do { guard let ownerID else { throw WorkoutBlockError.accountChanged }; commitments = try TrainingRunCommitmentStore().entries(userID: ownerID) } catch { errorMessage = error.localizedDescription }
    }
    private func reviewMove() {
        do {
            moveReview = try WorkoutScheduleReviewRules.review(program: program, slot: selectedSlot, date: moveDate,
                runCommitments: commitments, protectedSlots: workoutService.protectedBlockSlots(in: program))
        } catch { errorMessage = error.localizedDescription }
    }
}
