import MyFitPlateCore
import SwiftUI

struct RunTrainingBlockView: View {
    @EnvironmentObject private var workoutService: WorkoutService
    @Environment(\.dismiss) private var dismiss
    @State private var library = RunTrainingBlockLibrary()
    @State private var brief = RunTrainingBlockBrief()
    @State private var isLoaded = false
    @State private var errorMessage: String?
    @State private var review: RunTrainingBlockChange?
    @State private var adjustment: RunBlockSelection?
    @State private var scheduled: TrainingRunCommitment?
    @State private var preview: RunWorkoutPlan?
    @State private var baselineConfirmed = false
    private let ownerID = DIContainer.shared.authService.currentUserID
    private struct RunBlockSelection: Identifiable {
        let block: RunTrainingBlock
        let slot: RunTrainingBlockSlot
        var id: String { slot.id }
    }
    private var strengthDays: Set<TrainingCalendarDay> {
        guard let program = workoutService.activeProgram else { return [] }
        let skipped = Set(program.skippedIndices ?? [])
        return Set((max(0, program.currentProgressIndex ?? 0)..<max(0, program.totalSlots)).compactMap { slot in
            guard !skipped.contains(slot) else { return nil }
            return program.date(forSlot: slot).map { TrainingCalendarDay($0) }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Run around your strength schedule").appTextRole(.control)
                    Text("Choose your days and review each session. Missed runs wait for your decision.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if let pending = library.pendingReview {
                    Section {
                        Button("Resume saved review") { review = pending }.accessibilityIdentifier("run_block_resume_review")
                    }
                }
                ForEach(library.blocks) { block in blockSection(block) }
                briefSection
                if let errorMessage { Section { Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("run_block_error") } }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Running plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .accessibilityIdentifier("run_training_block_screen")
            .task { refresh(); isLoaded = true }
            .onReceive(NotificationCenter.default.publisher(for: .runLibrariesChanged)) { notification in
                guard let ownerID, notification.object as? String == ownerID,
                      ownerID == DIContainer.shared.authService.currentUserID else { return }
                do { library = try RunTrainingBlockStore().library(userID: ownerID) } catch { errorMessage = "The updated running library could not be read. Your current review stays unchanged." }
            }
            .onChange(of: brief) { _, value in
                guard isLoaded, let ownerID else { return }
                do { try RunTrainingBlockStore().saveBrief(value, userID: ownerID) } catch { errorMessage = error.localizedDescription }
            }
            .sheet(item: $review, onDismiss: { refresh() }) { value in
                RunBlockChangeReviewView(change: value, strengthDays: { strengthDays }) { review = nil; refresh() }
            }
            .sheet(item: $adjustment, onDismiss: {
                refresh()
                if let pending = library.pendingReview { review = pending }
            }) { selection in
                RunBlockAdjustmentView(block: selection.block, slot: selection.slot, strengthDays: { strengthDays }) {
                    adjustment = nil
                }
            }
            .sheet(item: $scheduled, onDismiss: { refresh() }) { commitment in
                if let ownerID { ScheduledRunReviewView(accountID: ownerID, commitment: commitment) }
            }
            .sheet(item: $preview) { plan in
                NavigationStack {
                    List {
                        Section { Text(plan.subtitle).appTextRole(.secondary) }
                        ForEach(plan.steps) { step in
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text(step.title + " · " + step.goalText(metric: true)).appTextRole(.control)
                                if let cue = step.target?.cue { Text(cue).appTextRole(.secondary).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .appFormStyle()
                    .navigationTitle(plan.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { preview = nil } } }
                }
            }
        }
    }
    private var briefSection: some View {
        Group {
        Section("Plan details") {
            Picker("Starting point", selection: $brief.ability) { ForEach(RunBlockAbility.allCases) { Text($0.title).tag($0) } }
            Picker("Goal", selection: $brief.goal) { ForEach(RunBlockGoal.allCases) { Text($0.title).tag($0) } }
            DatePicker("Start", selection: Binding(get: { brief.start.date() ?? Date() }, set: { brief.start = TrainingCalendarDay($0) }),
                in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            Stepper("\(brief.weeks) weeks", value: $brief.weeks, in: 4...8)
            if brief.goal != .consistency {
                Toggle("Set a goal date", isOn: Binding(get: { brief.targetDay != nil }, set: { enabled in
                    brief.targetDay = enabled ? TrainingCalendarDay(Calendar.current.date(byAdding: .day, value: brief.weeks * 7, to: brief.start.date() ?? Date()) ?? Date()) : nil
                }))
                if brief.targetDay != nil {
                    DatePicker("Goal date", selection: Binding(get: { brief.targetDay?.date() ?? Date() }, set: { brief.targetDay = TrainingCalendarDay($0) }), displayedComponents: .date)
                }
            }
        }
        Section("Recent running") {
            Stepper("Weekly time · \(Int(brief.recentWeeklyMinutes)) min", value: $brief.recentWeeklyMinutes, in: 20...900, step: 10)
                .accessibilityIdentifier("run_block_weekly_minutes")
            Stepper("Longest run · \(Int(brief.recentLongestMinutes)) min", value: $brief.recentLongestMinutes, in: 10...180, step: 5)
            Text("Include walk breaks. Use your recent running, rather than a future target.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            Toggle("These reflect my recent running", isOn: $baselineConfirmed).accessibilityIdentifier("run_block_confirm_baseline")
        }
        Section("Your schedule") {
            DisclosureGroup("Available days · \(brief.weekdays.count) selected") {
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(get: { brief.weekdays.contains(weekday) }, set: { selected in
                        brief.weekdays.removeAll { $0 == weekday }
                        if selected { brief.weekdays.append(weekday); brief.weekdays.sort() }
                        if !brief.weekdays.contains(brief.preferredLongWeekday), let first = brief.weekdays.first { brief.preferredLongWeekday = first }
                    })).accessibilityIdentifier("run_block_weekday_\(weekday)")
                }
            }
            Picker("Preferred longer day", selection: $brief.preferredLongWeekday) {
                ForEach(brief.weekdays.sorted(), id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
            }
            if brief.ability == .established { Toggle("Include controlled quality work", isOn: $brief.includeQuality) }
            Text("Existing strength dates stay protected. The preview shows lighter weeks and any session omitted because of a conflict.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            Button("Review running plan") { build() }.buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!isLoaded || !baselineConfirmed || library.pendingReview != nil).accessibilityIdentifier("run_block_build")
        }
        }
    }
    private func blockSection(_ block: RunTrainingBlock) -> some View {
        Section(block.brief.goal.title) {
            let recorded = block.slots.filter { $0.outcome?.state == .recorded }.count
            let skipped = block.slots.filter { $0.outcome?.state == .skipped }.count
            Text("\(recorded) recorded · \(skipped) skipped · \(block.slots.count) planned sessions")
                .appTextRole(.secondary).foregroundStyle(.secondary).accessibilityIdentifier("run_block_progress_\(block.id)")
            ForEach(0..<block.brief.weeks, id: \.self) { week in
                DisclosureGroup("Week \(week + 1) · \(Int(RunTrainingBlockRules.plannedMinutes(block, week: week))) min") {
                    ForEach(block.slots.filter { $0.weekIndex == week }) { slot in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text((slot.day.date()?.formatted(date: .abbreviated, time: .omitted) ?? "Saved date") + " · " + slot.role.title)
                                .appTextRole(.control)
                            Text(status(slot)).appTextRole(.secondary).foregroundStyle(.secondary)
                            if slot.canChange {
                                HStack {
                                    Button("Review change") { adjustment = .init(block: block, slot: slot) }
                                        .disabled(library.pendingReview != nil).accessibilityIdentifier("run_block_adjust_\(slot.id)")
                                    Spacer()
                                    if slot.day == TrainingCalendarDay(Date()), let commitment = block.commitment(for: slot) {
                                        Button("Start run") { scheduled = commitment }.accessibilityIdentifier("run_block_start_\(slot.id)")
                                    } else { Button("Preview") { preview = slot.plan } }
                                }
                            } else if slot.outcome?.state == .started {
                                Text("Resume the saved recording from Running.").appTextRole(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
    private func status(_ slot: RunTrainingBlockSlot) -> String {
        if let outcome = slot.outcome {
            switch outcome.state {
            case .recorded: return "Recorded \(Int((outcome.movingSeconds ?? 0) / 60)) min · prescribed \(Int(slot.plannedMinutes)) min"
            case .started: return "Recording started · prescription protected"
            case .skipped: return "Skipped · no catch-up added"
            case .abandoned: return "Recording discarded"
            }
        }
        let missed = slot.day.date().map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false
        return "\(Int(slot.plannedMinutes)) min · " + (missed ? "Missed date · review move or skip" : "Planned")
    }
    private func build() {
        do {
            guard let ownerID else { throw RunTrainingBlockError.accountChanged }
            let commitments = try TrainingRunCommitmentStore().entries(userID: ownerID)
            let block = try RunTrainingBlockRules.make(brief: brief, strengthDays: strengthDays, commitments: commitments)
            let value = RunTrainingBlockChange(ownerID: ownerID, before: nil, after: block,
                explanation: "Adopt only these reviewed run dates and prescriptions. Existing runs, strength progress and food logs stay intact.")
            try RunTrainingBlockStore().stage(value, userID: ownerID); review = value; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    private func refresh() {
        do {
            guard let ownerID else { throw RunTrainingBlockError.accountChanged }
            let store = RunTrainingBlockStore()
            for run in RunFallbackStore.shared.runs(since: .distantPast, for: ownerID) where run.scheduledContext?.blockID != nil {
                do { try store.recordCompleted(run: run, userID: ownerID) } catch { errorMessage = "A saved run's plan outcome needs review. The run and its original prescription remain saved." }
            }
            library = try store.library(userID: ownerID)
            if !isLoaded, let saved = library.brief { brief = saved }
            #if DEBUG
            if !isLoaded, library.brief == nil, ScreenshotDemoMode.isEnabled,
               ownerID == ScreenshotDemoData.userID, ProcessInfo.processInfo.arguments.contains("-ui-testing-run-block") {
                let future = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                brief = RunTrainingBlockBrief(start: future)
            }
            #endif
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RunBlockAdjustmentView: View {
    let block: RunTrainingBlock
    let slot: RunTrainingBlockSlot
    let strengthDays: () -> Set<TrainingCalendarDay>
    let didStage: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "Move"
    @State private var date = Date()
    @State private var minutes = 15.0
    @State private var error: String?
    private let ownerID = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(slot.plan.name).appTextRole(.sectionTitle)
                    Text("Every change is reviewed before it replaces a future prescription.").appTextRole(.secondary)
                    Picker("Change", selection: $kind) { ForEach(["Move", "Shorten", "Easier", "Skip", "Lighter week"], id: \.self) { Text($0).tag($0) } }
                    if kind == "Move" { DatePicker("New day", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date) }
                    if kind == "Shorten" { Stepper("\(Int(minutes)) minutes", value: $minutes, in: 8...max(8, slot.plannedMinutes - 1)) }
                    Button("Review change") { stage() }.buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("run_block_review_adjustment")
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .navigationTitle("Adjust planned run").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { date = max(Date(), slot.day.date() ?? Date()); minutes = max(8, floor(slot.plannedMinutes * 0.8)) }
        }
    }
    private func stage() {
        do {
            guard let ownerID else { throw RunTrainingBlockError.accountChanged }
            let adjustment: RunTrainingBlockRules.Adjustment
            switch kind {
            case "Shorten": adjustment = .shorten(minutes: minutes)
            case "Easier": adjustment = .easier
            case "Skip": adjustment = .skip
            case "Lighter week": adjustment = .lighterWeek(slot.weekIndex)
            default: adjustment = .move(TrainingCalendarDay(date))
            }
            let other = try TrainingRunCommitmentStore().entries(userID: ownerID).filter { $0.blockID != block.id }
            let proposal = try RunTrainingBlockRules.review(block: block, slotID: slot.id, adjustment: adjustment,
                ownerID: ownerID, strengthDays: strengthDays(), otherCommitments: other)
            try RunTrainingBlockStore().stage(proposal, userID: ownerID); didStage()
        } catch { self.error = error.localizedDescription }
    }
}

private struct RunBlockChangeReviewView: View {
    let change: RunTrainingBlockChange
    let strengthDays: () -> Set<TrainingCalendarDay>
    let didFinish: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section { Text(change.explanation).appTextRole(.secondary) }
                ForEach(change.after.notes, id: \.self) { Text($0).appTextRole(.caption).foregroundStyle(.secondary) }
                ForEach(0..<change.after.brief.weeks, id: \.self) { week in
                    Section("Week \(week + 1) · \(Int(RunTrainingBlockRules.plannedMinutes(change.after, week: week))) min") {
                        ForEach(change.after.slots.filter { $0.weekIndex == week }) { slot in
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text((slot.day.date()?.formatted(date: .abbreviated, time: .omitted) ?? "Saved day") + " · " + slot.plan.name)
                                Text("\(Int(slot.plannedMinutes)) min" + (slot.outcome?.state == .skipped ? " · skipped" : ""))
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution) } }
                Button("Discard review", role: .destructive) {
                    do { try RunTrainingBlockStore().discardReview(id: change.id, userID: change.ownerID); didFinish() } catch { self.error = error.localizedDescription }
                }
            }
            .appFormStyle()
            .navigationTitle("Review running plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep for later") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Use reviewed plan") {
                    do {
                        let other = try TrainingRunCommitmentStore().entries(userID: change.ownerID).filter { $0.blockID != change.after.id }
                        try RunTrainingBlockStore().accept(change, userID: change.ownerID, strengthDays: strengthDays(), otherCommitments: other)
                        didFinish()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(AppActionButtonStyle(.primary)).padding().background(AppPalette.canvas)
                    .accessibilityIdentifier("run_block_accept")
            }
        }
    }
}
