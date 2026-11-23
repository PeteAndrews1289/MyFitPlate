import MyFitPlateCore
import SwiftUI

struct FuelExperimentContext {
    let planID: String
    let sessionTitle: String
    let scheduledAt: Date
    let feedback: TrainingFuelFeedback
    let linkedFoods: [String]
}

struct MealExperimentConfirmation: View {
    let label: String
    @Binding var isConfirmed: Bool

    var body: some View {
        Button {
            isConfirmed.toggle()
        } label: {
            HStack(spacing: AppSpacing.compact) {
                Image(systemName: isConfirmed ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isConfirmed ? AppPalette.brandText : Color.secondary)
                    .accessibilityHidden(true)
                Text(label)
                    .multilineTextAlignment(.leading)
            }
            .appTextRole(.body)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isConfirmed ? .isSelected : [])
    }
}

struct MealExperimentsView: View {
    var openCheckIn = false
    var preferredSessionID: String?
    var reminderTarget: ReminderTarget?
    var fuelContext: FuelExperimentContext?
    @EnvironmentObject private var workoutService: WorkoutService
    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var experimentStore: MealExperimentStore
    @State private var recentFoods: [FoodItem] = []
    @State private var mealAID = ""
    @State private var mealBID = ""
    @State private var routineID = ""
    @State private var minutesBefore = 90
    @State private var familiar = false
    @State private var startsWithA = Bool.random()
    @State private var logs: [WorkoutSessionLog] = []
    @State private var message: String?
    @State private var loading = true
    @State private var selectedTrial: MealExperimentTrial?
    @State private var showingDelete = false
    @State private var deletingExperimentID: String?
    @State private var ownerID: String?
    @State private var selectedExperimentID = ""
    @State private var showingReminderReview = false
    @State private var reminderValidated = false

    private var foods: [FoodItem] {
        var seen = Set<String>()
        let recipeFoods = recipeService.userRecipes.compactMap { recipe -> FoodItem? in
            // Picker identity belongs to the saved recipe, not a fresh diary-entry UUID on every render.
            guard let sourceID = recipe.id ?? (try? PlanFingerprint.make(recipe)) else { return nil }
            return try? RecipePortionRules.foodItem(for: recipe, selection: RecipePortionRules.defaultSelection(for: recipe),
                entryID: "experiment-recipe-" + sourceID)
        }
        return (recipeFoods + recentFoods)
            .filter { $0.calories > 0 && seen.insert($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }
    private var current: MealExperiment? {
        if let reminderTarget { return experimentStore.experiments.first { $0.id == reminderTarget.experimentID } }
        return experimentStore.experiments.first { $0.id == selectedExperimentID } ?? experimentStore.active ?? experimentStore.experiments.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(eyebrow: "Fuel experiments", title: "What works for me?",
                                subtitle: "Compare two familiar meals before the same workout.")
                if let context = fuelContext {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("From your Fuel observation").appTextRole(.control)
                        Text("\(context.sessionTitle) · \(context.scheduledAt.formatted(date: .abbreviated, time: .omitted))")
                        Text("Energy \(context.feedback.energy)/5 · comfort \(context.feedback.comfort)/5 · practicality \(context.feedback.practicality)/5")
                            .appTextRole(.secondary)
                        if !context.linkedFoods.isEmpty { Text(context.linkedFoods.joined(separator: ", ")).appTextRole(.secondary) }
                        Text("Explore this with two familiar meals. This earlier rating is context, not a trial result.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }.appSurface(.quiet).accessibilityIdentifier("experiment_fuel_context")
                }
                if experimentStore.experiments.count > 1 {
                    Picker("Comparison", selection: Binding(get: { current?.id ?? "" }, set: { selectedExperimentID = $0 })) {
                        ForEach(experimentStore.experiments) { experiment in
                            Text("\(experiment.routineName) · \(experiment.createdAt.formatted(date: .abbreviated, time: .shortened))").tag(experiment.id)
                        }
                    }.pickerStyle(.menu)
                }
                if let error = experimentStore.errorMessage {
                    Text(error).appTextRole(.body).appSurface(.quiet)
                } else if let experiment = current {
                    experimentContent(experiment).disabled(reminderTarget != nil && !reminderValidated)
                    if experiment.isFinished && reminderTarget == nil { setup }
                } else if reminderTarget == nil { setup }
                if loading { ProgressView("Loading your workouts") }
                if let message {
                    Text(message).appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("experiment_status")
                }
                Text(experimentStore.hasCloudSync ? "Privately saved to your account. Offline changes sync when you return or refresh." : "Saved on this device for your account.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                if let status = experimentStore.syncMessage {
                    Text(status).appTextRole(.secondary).accessibilityIdentifier("experiment_sync_status")
                    Button(experimentStore.isSyncing ? "Syncing…" : "Sync now") { Task { await experimentStore.synchronize() } }
                        .disabled(experimentStore.isSyncing).frame(minHeight: 44)
                }
                if !experimentStore.experiments.isEmpty || experimentStore.errorMessage != nil {
                    Button(current == nil ? "Delete comparison data" : "Delete this comparison", role: .destructive) {
                        deletingExperimentID = current?.id; showingDelete = true
                    }
                        .frame(minHeight: 44).accessibilityIdentifier("experiment_delete")
                }
            }.padding(AppSpacing.screenHorizontal)
        }
        .background(AppPalette.canvas)
        .navigationTitle("What works for me?")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showingReminderReview) {
            ReminderScheduleEditor(kind: .experimentCheckIn, reminders: .shared)
        }
        .sheet(item: $selectedTrial) { trial in
            if let experiment = current {
                MealExperimentCheckInView(experiment: experiment, trial: trial, sessions: candidates(for: experiment, trial: trial),
                    preferredSessionID: preferredSessionID) { session, energy, comfort, timing, flags, note, legacyConfirmed in
                    try saveCheckIn(experiment: experiment, trial: trial, session: session, energy: energy,
                                    comfort: comfort, timing: timing, flags: flags, note: note, confirmedLegacySession: legacyConfirmed)
                }
            }
        }
        .confirmationDialog(deletingExperimentID == nil ? "Delete all meal comparisons from your account?" : "Delete this comparison from your account?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete comparison data", role: .destructive) {
                do {
                    guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { throw MealExperimentError.noAccount }
                    if let deletingExperimentID { try experimentStore.delete(experimentID: deletingExperimentID, for: ownerID) } else { try experimentStore.deleteAll(for: ownerID) }
                } catch { message = error.localizedDescription }
            }
        } message: { Text("Your food log, recipes and completed workouts are kept.") }
        .accessibilityElement(children: .contain)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text(current == nil ? "Choose your comparison" : "Start another comparison").appTextRole(.sectionTitle)
            Text("Six sessions, with meals A and B mixed across the schedule. Keep the portions and timing similar each time.")
                .appTextRole(.body)
            if let program = workoutService.activeProgram {
                let proposed = try? proposal(program)
                Text("Workout").appTextRole(.control)
                Picker("Workout", selection: $routineID) {
                    Text("Choose a routine").tag("")
                    ForEach(program.routines.filter { !$0.exercises.isEmpty && $0.exercises.allSatisfy { $0.type == .strength } }) {
                        Text($0.name).tag($0.id)
                    }
                }.pickerStyle(.menu).frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("experiment_routine")
                if !routineID.isEmpty {
                    let slots = MealExperimentEvidenceRules.eligibleSlots(in: program, routineID: routineID,
                        protectedSlots: (try? workoutService.protectedBlockSlots(in: program)) ?? [])
                    Text(slots.count >= 6 ? "\(slots.count) eligible future sessions. Skipped, completed and active sessions are excluded."
                         : "Only \(slots.count) eligible sessions remain. This comparison needs six; choose another routine or continue into a new block.")
                        .appTextRole(.secondary).foregroundStyle(.secondary).accessibilityIdentifier("experiment_eligible_sessions")
                }
                mealPicker("Meal A", selection: $mealAID)
                mealPicker("Meal B", selection: $mealBID)
                if foods.count < 2 {
                    Text("Save two recipes or log familiar meals first; they will appear here.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                } else if !mealAID.isEmpty, mealAID == mealBID {
                    Text("Choose a different meal for A or B.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Text("Eat before training").appTextRole(.control)
                Picker("Eat before training", selection: $minutesBefore) {
                    ForEach([60, 90, 120, 150], id: \.self) { Text("About \($0) minutes").tag($0) }
                }
                if let proposed {
                    Text("Your six planned sessions").appTextRole(.sectionTitle)
                    ForEach(proposed.trials, id: \.slot) { trial in
                        HStack {
                            Text(trial.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("Meal \(trial.side.rawValue)")
                        }.appTextRole(.secondary)
                    }
                }
                MealExperimentConfirmation(label: "I already eat both meals comfortably and want to compare them", isConfirmed: $familiar)
                .accessibilityIdentifier("experiment_consent")
                .onChange(of: [mealAID, mealBID]) { _, _ in familiar = false }
                Button("Start comparison") { start(program) }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!familiar || proposed == nil || loading)
                    .accessibilityIdentifier("experiment_start")
            } else {
                AdaptiveProgramRequirementView()
            }
            Text("This is a personal observation, not proof that a meal caused a change. We look for a repeatable pattern in energy and comfort; training performance is context.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }.appSurface(.quiet).disabled(loading)
    }

    private func mealPicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title).appTextRole(.control)
            Picker(title, selection: selection) {
                Text("Choose a familiar meal").tag("")
                ForEach(foods) { food in
                    Text("\(food.name) · \(food.servingSize)").tag(food.id)
                }
            }.accessibilityIdentifier(title == "Meal A" ? "experiment_meal_a" : "experiment_meal_b")
        }
    }

    private func experimentContent(_ experiment: MealExperiment) -> some View {
        let summary = MealExperimentRules.summary(experiment)
        let nextTrial = experiment.endedAt == nil ? experiment.trials.first { $0.observation == nil && !$0.skipped && scheduledDate($0, experiment: experiment) <= Date() } : nil
        return VStack(alignment: .leading, spacing: AppSpacing.section) {
            Button("Review optional check-in reminders") { showingReminderReview = true }
                .appTextRole(.secondary).frame(minHeight: 44).accessibilityIdentifier("experiment_reminder_review")
            if let trial = nextTrial {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text("Next check-in").appTextRole(.sectionTitle)
                    Text("Meal \(trial.side.rawValue) · \(experiment.food(for: trial.side).name)").appTextRole(.body)
                    Button("Check in") { selectedExperimentID = experiment.id; selectedTrial = trial }
                        .buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("experiment_checkin_\(trial.slot)")
                }.appSurface(.quiet)
            }
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text(experiment.routineName).appTextRole(.sectionTitle)
                Text("A · \(experiment.mealA.name) · \(experiment.mealA.servingSize)").appTextRole(.body)
                Text("B · \(experiment.mealB.name) · \(experiment.mealB.servingSize)").appTextRole(.body)
                Text("About \(experiment.minutesBefore) minutes before training").appTextRole(.secondary).foregroundStyle(.secondary)
                Text(summary.headline).appTextRole(.sectionTitle).accessibilityIdentifier("experiment_result")
                summaryRow("Comparable sessions", a: "\(summary.a.count)", b: "\(summary.b.count)")
                summaryRow("Energy / 5", a: number(summary.a.energy), b: number(summary.b.energy))
                summaryRow("Comfort / 5", a: number(summary.a.comfort), b: number(summary.b.comfort))
                summaryRow("Energy range / 5", a: range(summary.a.energyRange), b: range(summary.b.energyRange))
                summaryRow("Comfort range / 5", a: range(summary.a.comfortRange), b: range(summary.b.comfortRange))
                Text("Ranges show how much your observations varied. Averages and six sessions cannot establish that a meal caused a change.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                summaryRow("Logged effort / 10", a: number(summary.a.meanRPE), b: number(summary.b.meanRPE))
                Text("Effort recorded in \(summary.a.effortCount) A sessions and \(summary.b.effortCount) B sessions. Missing effort is not treated as zero.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                Text(summary.hasEnoughObservations
                     ? "These averages describe your sessions. Training progression, expectation and other changes can affect them. Repeat the pattern before drawing a conclusion."
                     : "Aim for at least three comparable sessions per meal. No conclusion yet.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                if experiment.isFinished, experiment.endedAt == nil {
                    Button("Schedule another pair") {
                        do {
                            guard let program = workoutService.activeProgram else { throw MealExperimentError.invalidSetup }
                            try persist(MealExperimentRules.addingPair(to: experiment, program: program, protectedSlots: workoutService.protectedBlockSlots(in: program)))
                        } catch { message = error.localizedDescription }
                    }.buttonStyle(AppActionButtonStyle(.secondary))
                }
                if summary.excluded > 0 {
                    Text("\(summary.excluded) sessions with changed conditions or unresolved check-ins are kept below and excluded from these averages.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
            }.appSurface(.quiet)

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text("Your sessions").appTextRole(.sectionTitle)
                ForEach(experiment.trials) { trial in
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Meal \(trial.side.rawValue) · \(scheduledDate(trial, experiment: experiment).formatted(date: .abbreviated, time: .omitted))")
                            .appTextRole(.body)
                        if let observation = trial.observation {
                            Text("\(observation.sessionDate.formatted(date: .abbreviated, time: .omitted)) · Energy \(observation.energy)/5 · Comfort \(observation.comfort)/5 · \(observation.workingSets) working sets")
                                .appTextRole(.secondary)
                            Text("Logged volume: \(Int(observation.volume.rounded()).formatted()) lb × reps")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            if !observation.confounders.isEmpty {
                                Text(observation.confounders.joined(separator: " · "))
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                            if !(trial.conflictingObservations ?? []).isEmpty {
                                conflictReview(trial, experiment: experiment)
                            } else {
                                Button("Correct check-in") { selectedExperimentID = experiment.id; selectedTrial = trial }
                                    .frame(minHeight: 44).accessibilityIdentifier("experiment_correct_\(trial.slot)")
                            }
                            if let history = trial.observationHistory, !history.isEmpty {
                                DisclosureGroup("Earlier check-ins") {
                                    ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                                        Text("Energy \(value.energy)/5 · Comfort \(value.comfort)/5 · \(value.minutesBefore) minutes before")
                                            .appTextRole(.secondary)
                                    }
                                }
                            }
                            Text(observation.sourceProgramID == nil ? "Legacy workout match · manually reviewed" : "Linked to the saved program and session")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        } else if trial.skipped {
                            Text("Skipped · no result recorded").appTextRole(.secondary).foregroundStyle(.secondary)
                            if experiment.endedAt == nil {
                                Button("Restore session") { skip(trial, experiment: experiment, skipped: false) }.frame(minHeight: 44)
                            }
                        } else if experiment.endedAt == nil {
                            Text(experiment.food(for: trial.side).name).appTextRole(.secondary).foregroundStyle(.secondary)
                            HStack {
                                if trial.id != nextTrial?.id {
                                    Button("Check in") { selectedExperimentID = experiment.id; selectedTrial = trial }
                                        .buttonStyle(AppActionButtonStyle(.secondary))
                                        .accessibilityIdentifier("experiment_checkin_\(trial.slot)")
                                }
                                Button("Skip") { skip(trial, experiment: experiment) }.frame(minHeight: 44)
                            }
                        }
                    }
                    Divider()
                }
                if !experiment.isFinished {
                    Text("If a session moves, check in against the workout you actually completed. You choose the matching session; workouts are never assigned automatically.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Button("Stop comparison") { stop(experiment) }
                        .frame(minHeight: 44).accessibilityIdentifier("experiment_stop")
                }
                Button("Refresh workouts") { Task { await load() } }.frame(minHeight: 44)
                if let export = try? MealExperimentEvidenceRules.export(experiment) {
                    ShareLink(item: export) { Label("Export comparison", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44).accessibilityIdentifier("experiment_export")
                }
            }.appSurface(.quiet)
        }
    }

    private func summaryRow(_ title: String, a: String, b: String) -> some View {
        HStack {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text("A: \(a)").frame(minWidth: 50)
            Text("B: \(b)").frame(minWidth: 50)
        }.appTextRole(.secondary).monospacedDigit()
    }
    private func range(_ value: ClosedRange<Double>?) -> String {
        value.map { "\($0.lowerBound.formatted(.number.precision(.fractionLength(0...1))))–\($0.upperBound.formatted(.number.precision(.fractionLength(0...1))))" } ?? "—"
    }

    private func conflictReview(_ trial: MealExperimentTrial, experiment: MealExperiment) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Conflicting check-ins need your review").appTextRole(.control)
            Text("Both versions are kept and excluded from averages. Choose the observation that reflects what happened.")
                .appTextRole(.secondary)
            let options = [trial.observation].compactMap { $0 } + (trial.conflictingObservations ?? [])
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button("Use energy \(option.energy)/5, comfort \(option.comfort)/5, \(option.minutesBefore) minutes before") {
                    do {
                        guard let latest = experimentStore.experiments.first(where: { $0.id == experiment.id }) else { throw MealExperimentError.stale }
                        let resolved = try MealExperimentEvidenceRules.resolving(latest, trialID: trial.id,
                            chosenObservationID: MealExperimentEvidenceRules.identity(option), expectedFingerprint: PlanFingerprint.make(trial))
                        try persist(resolved)
                        message = "Check-in resolved. Earlier versions remain in your comparison history."
                    } catch { message = error.localizedDescription }
                }.frame(minHeight: 44).accessibilityIdentifier("experiment_conflict_use_\(trial.slot)_\(index)")
            }
        }.appSurface(.quiet)
    }

    private func number(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—" }

    private func scheduledDate(_ trial: MealExperimentTrial, experiment: MealExperiment) -> Date {
        guard trial.observation == nil, let program = workoutService.activeProgram,
              program.id == experiment.programID else { return trial.date }
        return program.date(forSlot: trial.slot) ?? trial.date
    }

    private func proposal(_ program: WorkoutProgram) throws -> MealExperiment {
        guard let mealA = foods.first(where: { $0.id == mealAID }), let mealB = foods.first(where: { $0.id == mealBID }) else {
            throw MealExperimentError.invalidSetup
        }
        return try MealExperimentRules.create(program: program, routineID: routineID, mealA: mealA, mealB: mealB,
                                               minutesBefore: minutesBefore, startsWithA: startsWithA,
                                               protectedSlots: workoutService.protectedBlockSlots(in: program))
    }

    private func start(_ program: WorkoutProgram) {
        do {
            guard familiar else { return }
            let experiment = try proposal(program)
            try persist(experiment)
            message = "Comparison saved. Your first meal is \(experiment.food(for: experiment.trials[0].side).name)."
            familiar = false
        } catch { message = error.localizedDescription }
    }
    private func persist(_ experiment: MealExperiment) throws {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { throw MealExperimentError.noAccount }
        try experimentStore.save(experiment, for: ownerID)
        NotificationCenter.default.post(name: .reminderEvidenceChanged, object: ownerID)
    }
    private func skip(_ trial: MealExperimentTrial, experiment: MealExperiment, skipped: Bool = true) {
        var updated = experiment
        guard let index = updated.trials.firstIndex(where: { $0.id == trial.id }) else { return }
        updated.trials[index].skipped = skipped
        do { try persist(updated) } catch { message = error.localizedDescription }
    }
    private func stop(_ experiment: MealExperiment) {
        var updated = experiment
        updated.endedAt = Date()
        do { try persist(updated) } catch { message = error.localizedDescription }
    }
    private func candidates(for experiment: MealExperiment, trial: MealExperimentTrial? = nil) -> [WorkoutSessionLog] {
        let used = Set(experiment.trials.filter { $0.id != trial?.id }.compactMap { $0.observation?.sessionID })
        return logs.filter {
            MealExperimentEvidenceRules.matches($0, experiment: experiment, trial: trial, allowLegacy: true)
                && !used.contains($0.id ?? "")
        }
    }
    private func saveCheckIn(experiment: MealExperiment, trial: MealExperimentTrial, session: WorkoutSessionLog?,
                             energy: Int, comfort: Int, timing: Int, flags: [String], note: String,
                             confirmedLegacySession: Bool) throws {
        guard let latest = experimentStore.experiments.first(where: { $0.id == experiment.id }) else { throw MealExperimentError.stale }
        if let reminderTarget {
            guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID,
                  let session, trial.id == reminderTarget.experimentTrialID,
                  ReminderExperimentEvidence.eligible(ownerID: ownerID, experiments: [latest], sessions: [session])
                    .contains(where: { $0.matches(reminderTarget, now: Date()) }) else { throw MealExperimentError.stale }
        }
        let updated: MealExperiment
        if let previous = trial.observation {
            if let session, session.id != previous.sessionID {
                updated = try MealExperimentEvidenceRules.correcting(latest, trialID: trial.id,
                    expectedObservationID: MealExperimentEvidenceRules.identity(previous), session: session,
                    energy: energy, comfort: comfort, minutesBefore: timing, confounders: flags, note: note,
                    confirmedLegacySession: confirmedLegacySession)
            } else {
                updated = try MealExperimentEvidenceRules.correctingRatings(latest, trialID: trial.id,
                    expectedObservationID: MealExperimentEvidenceRules.identity(previous), energy: energy, comfort: comfort,
                    minutesBefore: timing, confounders: flags, note: note, confirmedLegacySession: confirmedLegacySession)
            }
        } else {
            guard let session else { throw MealExperimentError.wrongSession }
            updated = try MealExperimentRules.recording(in: latest, trialID: trial.id, session: session, energy: energy,
                comfort: comfort, minutesBefore: timing, confounders: flags, note: note, confirmedLegacySession: confirmedLegacySession)
        }
        try persist(updated)
        selectedTrial = nil
        message = trial.observation == nil ? "Check-in saved with your completed workout." : "Check-in corrected. Its earlier version and workout history are kept."
    }
    @MainActor private func load() async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        ownerID = userID; reminderValidated = false
        experimentStore.activateAccount(userID)
        await experimentStore.synchronize()
        workoutService.fetchRoutinesAndPrograms()
        loading = true
        defer { loading = false }
        await recipeService.fetchUserRecipes()
        guard DIContainer.shared.authService.currentUserID == userID else { return }
        dailyLogService.fetchRecentFoodItems(for: userID) { result in
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            if case .success(let foods) = result { recentFoods = foods }
        }
        do {
            let result = try await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(userID: userID, sinceDays: 120)
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            logs = result.sorted { $0.date > $1.date }
            if let reminderTarget {
                guard reminderTarget.ownerID == userID,
                      let match = ReminderExperimentEvidence.eligible(ownerID: userID, experiments: experimentStore.experiments, sessions: logs)
                        .first(where: { $0.matches(reminderTarget, now: Date()) }),
                      let experiment = experimentStore.experiments.first(where: { $0.id == match.experimentID }),
                      let trial = experiment.trials.first(where: { $0.id == match.trialID }) else {
                    message = "This reminder's comparison or workout changed, was already checked in, or its two-day window ended. No check-in was recorded."
                    return
                }
                reminderValidated = true; selectedExperimentID = experiment.id; selectedTrial = trial
                return
            }
            if openCheckIn, let experiment = current, !candidates(for: experiment).isEmpty {
                selectedExperimentID = experiment.id
                if let preferredSessionID, let session = logs.first(where: { $0.id == preferredSessionID }),
                   let trial = experiment.trials.first(where: {
                       $0.observation == nil && !$0.skipped
                           && MealExperimentEvidenceRules.matches(session, experiment: experiment, trial: $0, allowLegacy: false)
                   }) { selectedTrial = trial } else if preferredSessionID == nil {
                    selectedTrial = experiment.trials.first { $0.observation == nil && !$0.skipped && $0.date <= Date() }
                }
            }
        } catch { message = "Saved workouts could not load. Pull to refresh before checking in." }
    }
}
