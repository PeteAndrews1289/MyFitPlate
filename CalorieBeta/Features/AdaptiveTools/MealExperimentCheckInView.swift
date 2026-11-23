import MyFitPlateCore
import SwiftUI

struct MealExperimentCheckInView: View {
    let experiment: MealExperiment
    let trial: MealExperimentTrial
    let sessions: [WorkoutSessionLog]
    var preferredSessionID: String?
    let onSave: (WorkoutSessionLog?, Int, Int, Int, [String], String, Bool) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sessionID = ""
    @State private var energy = 0
    @State private var comfort = 0
    @State private var timing = 90
    @State private var flags = Set<String>()
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var confirmedLegacySession = false
    @State private var initialized = false

    private var needsLegacyConfirmation: Bool {
        guard !sessionID.isEmpty else { return false }
        if let session = sessions.first(where: { $0.id == sessionID }) { return session.programContext == nil }
        return trial.observation?.sourceProgramID == nil
    }

    private let conditions = ["Different meal or portion", "Unusual sleep or stress", "Different caffeine",
                              "Illness or discomfort before training", "Workout load or rest changed", "Other unusual conditions"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Meal \(trial.side.rawValue) · \(experiment.food(for: trial.side).name)").appTextRole(.sectionTitle)
                    Text("Use what actually happened. Changed conditions stay in your record and are left out of the comparison averages.")
                        .appTextRole(.secondary)
                }
                Section("Completed workout") {
                    if sessions.isEmpty, trial.observation == nil {
                        Text("No unused \(experiment.routineName) sessions since this comparison started. Complete the workout in Train, then refresh your comparison.")
                            .appTextRole(.body).accessibilityIdentifier("experiment_no_session")
                    } else {
                        Picker("Workout session", selection: $sessionID) {
                            Text("Choose the completed session").tag("")
                            if let observation = trial.observation, !sessions.contains(where: { $0.id == observation.sessionID }) {
                                Text("Recorded \(observation.sessionDate.formatted(date: .abbreviated, time: .shortened))").tag(observation.sessionID)
                            }
                            ForEach(sessions, id: \.id) { session in
                                Text(session.date.formatted(date: .abbreviated, time: .shortened)).tag(session.id ?? "")
                            }
                        }.accessibilityIdentifier("experiment_session")
                        Text(trial.observation == nil ? "Recorded sets and effort come directly from this workout."
                             : "Rating corrections keep the original recorded metrics. Your workout log is never edited here.").appTextRole(.secondary)
                        if needsLegacyConfirmation {
                            Text("This older workout has no saved program/slot link, so the app cannot establish that match for you.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("How did it feel?") {
                    rating("Energy", selection: $energy, help: "1 = very low · 5 = very high")
                    rating("Stomach comfort", selection: $comfort, help: "1 = very uncomfortable · 5 = very comfortable")
                    Stepper("Meal timing: \(timing) minutes before", value: $timing, in: 0...360, step: 15)
                        .accessibilityIdentifier("experiment_timing")
                }
                Section("Anything different?") {
                    ForEach(conditions, id: \.self) { condition in
                        Toggle(condition, isOn: Binding(
                            get: { flags.contains(condition) },
                            set: { if $0 { flags.insert(condition) } else { flags.remove(condition) } }))
                    }
                    TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...4)
                }
                if let errorMessage { Text(errorMessage).appTextRole(.secondary).foregroundStyle(.secondary) }
                Section {
                    if needsLegacyConfirmation {
                        MealExperimentConfirmation(label: "I confirm this workout belongs to this program and session", isConfirmed: $confirmedLegacySession)
                            .accessibilityIdentifier("experiment_confirm_legacy")
                    }
                    Button(trial.observation == nil ? "Save check-in" : "Save correction") {
                        do {
                            let session = sessions.first(where: { $0.id == sessionID })
                            guard session != nil || trial.observation?.sessionID == sessionID else { throw MealExperimentError.wrongSession }
                            try onSave(session, energy, comfort, timing, Array(flags), note, confirmedLegacySession || !needsLegacyConfirmation)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(sessionID.isEmpty || energy == 0 || comfort == 0 || (needsLegacyConfirmation && !confirmedLegacySession))
                    .accessibilityIdentifier("experiment_save_checkin")
                }
            }.appFormStyle()
            .scrollContentBackground(.hidden).background(AppPalette.canvas)
            .navigationTitle("Meal check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: sessionID) { _, _ in confirmedLegacySession = false }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let observation = trial.observation {
                    sessionID = observation.sessionID; energy = observation.energy; comfort = observation.comfort
                    timing = observation.minutesBefore; note = observation.note
                    flags = Set(observation.confounders.filter { conditions.contains($0) })
                } else {
                    timing = experiment.minutesBefore
                    if let preferredSessionID, sessions.contains(where: { $0.id == preferredSessionID }) { sessionID = preferredSessionID } else if sessions.count == 1, let session = sessions.first, session.programContext?.slotIndex == trial.slot { sessionID = session.id ?? "" }
                }
            }
        }
    }

    private func rating(_ title: String, selection: Binding<Int>, help: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(title).appTextRole(.body)
            Picker(title, selection: selection) {
                Text("—").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier(title == "Energy" ? "checkin_energy" : "checkin_comfort")
            Text(help).appTextRole(.secondary).foregroundStyle(.secondary)
        }
    }
}

struct AdaptiveToolsLinks: View {
    @EnvironmentObject private var workoutService: WorkoutService
    @EnvironmentObject private var experimentStore: MealExperimentStore
    @State private var showingRescue = false
    @State private var showingExperiment = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Button { showingRescue = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Rescue my week", systemImage: "calendar.badge.clock")
                    if let program = workoutService.activeProgram,
                       let date = program.date(forSlot: program.currentProgressIndex ?? 0),
                       date < Calendar.current.startOfDay(for: Date()), program.weekRescue == nil {
                        Text("Your next session is overdue. Review a schedule that fits this week.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("open_week_rescue")
            Button { showingExperiment = true } label: {
                Label("What works for me?", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("open_meal_experiments")
            if let experiment = experimentStore.active,
               let trial = experiment.trials.first(where: { $0.observation == nil && !$0.skipped }) {
                Text(trial.date <= Date()
                     ? "After \(experiment.routineName), add your check-in for \(experiment.food(for: trial.side).name)."
                     : "Next comparison: \(experiment.food(for: trial.side).name), before \(experiment.routineName).")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .appTextRole(.body).tint(AppPalette.brandText)
        .appSurface(.quiet)
        .sheet(isPresented: $showingRescue) { NavigationStack { WeekRescueView() } }
        .sheet(isPresented: $showingExperiment) {
            NavigationStack {
                MealExperimentsView(openCheckIn: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingExperiment = false } } }
            }
        }
    }
}

struct AdaptiveProgramRequirementView: View {
    @EnvironmentObject private var workoutService: WorkoutService

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if workoutService.isLoadingPrograms {
                ProgressView("Loading your saved program")
            } else if !workoutService.hasLoadedPrograms || workoutService.preferredProgramUnavailable || workoutService.loadErrorMessage != nil {
                Label("Couldn't load your saved program", systemImage: "icloud.slash").appTextRole(.sectionTitle)
                Text("Retry to check your existing plan and progress.").appTextRole(.secondary).foregroundStyle(.secondary)
                Button("Retry loading") { workoutService.retryPendingSaves() }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("adaptive_program_retry")
            } else {
                Label("Choose an active strength program in Train to get started.", systemImage: "calendar.badge.plus")
                    .appTextRole(.body)
            }
        }
    }
}
