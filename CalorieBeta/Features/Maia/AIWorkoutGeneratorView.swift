import MyFitPlateCore

import SwiftUI
struct AIWorkoutGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings // Access user's goal settings

    // State for the generator form
    @State private var goal: String = ""
    @State private var daysPerWeek: Int = 3
    @State private var maximumSessionMinutes = 45
    @State private var fitnessLevel: FitnessLevel = .beginner
    @State private var equipment: Equipment = .fullGym
    @State private var details: String = "" // Optional notes

    // State for scheduling
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = [2, 4, 6]

    // View state
    @State private var isLoading = false
    @State private var generatedProgram: WorkoutProgram?
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var proposalAccepted = false
    @State private var proposal: WorkoutAIProposal?
    @State private var editingRequirements = false
    @State private var showingGyms = false
    @State private var gym: StrengthGymProfile?
    @State private var movementMappings: [String: String] = [:]
    @State private var showingAllowedMovements = false
    @State private var routineToEdit: WorkoutRoutine?
    @State private var outlineReview: AIProgramOutlineReview?
    @State private var restored = false
    @State private var preferredMovements: [String] = []
    @State private var avoidedMovements: [String] = []
    @State private var choosingMovementPreference = false
    @State private var choosingAvoidedMovement = false
    private let ownerID = DIContainer.shared.authService.currentUserID
    private var hasFrozenSubmission: Bool { proposal?.program?.trainingBlock != nil }

    // Enums to provide structured options in the Pickers
    enum FitnessLevel: String, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        var id: Self { self }
    }

    enum Equipment: String, CaseIterable, Identifiable {
        case fullGym = "Full Gym"
        case dumbbellsOnly = "Dumbbells Only"
        case bodyweight = "Bodyweight Only"
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            if var program = generatedProgram, !editingRequirements {
                GeneratedProgramPreviewView(
                    program: program,
                    requestSummary: "\(daysPerWeek) days/week · \(maximumSessionMinutes) min budget · \(equipment.rawValue)",
                    isSaving: isSaving,
                    saveError: errorMessage,
                    onBack: { editingRequirements = true },
                    onEditOutline: {
                        do {
                            guard let proposal else { throw WorkoutBlockError.changed }
                            let snapshot = try JSONDecoder().decode(WorkoutAIProposal.self, from: JSONEncoder().encode(proposal))
                            guard let program = snapshot.program else { throw WorkoutBlockError.changed }
                            outlineReview = AIProgramOutlineReview(program: program, requestID: snapshot.request.id,
                                fingerprint: try PlanFingerprint.make(Optional(snapshot)))
                        } catch { errorMessage = "The proposal could not open for editing. Its saved draft is kept. \(error.localizedDescription)" }
                    },
                    onEditRoutine: { routineToEdit = $0.deepCopy() },
                    onRegenerateRoutine: { regenerate(routine: $0, movementID: nil) },
                    onRegenerateMovement: { regenerate(routine: $0, movementID: $1) },
                    onSave: {
                        guard !isSaving, hasFrozenSubmission || selectedDaysOfWeek.count == daysPerWeek else { return }
                        if !hasFrozenSubmission {
                            program.startDate = Calendar.current.startOfDay(for: startDate)
                            program.daysOfWeek = selectedDaysOfWeek.sorted()
                        }
                        isSaving = true
                        errorMessage = nil
                        Task { @MainActor in
                            do {
                                guard let proposal, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { throw WorkoutBlockError.accountChanged }
                                try verifyCurrentGym(proposal.request, ownerID: ownerID)
                                program = try proposal.validatedProgram(program)
                                if program.trainingBlock == nil { program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program) }
                                try WorkoutBlockRules.validate(program)
                                // Freeze newly allocated week/block identities before the first write.
                                var submission = proposal; submission.program = program
                                try WorkoutAIProposalStore().save(submission)
                                self.proposal = submission; generatedProgram = program
                                guard await workoutService.saveProgram(program) != nil else { throw WorkoutBlockError.unavailable }
                                guard DIContainer.shared.authService.currentUserID == ownerID else { throw WorkoutBlockError.accountChanged }
                                try WorkoutAIProposalStore().remove(userID: ownerID)
                                proposalAccepted = true
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                            isSaving = false
                        }
                    }
                )
            } else {
                AppEditorScaffold(
                    title: "Build your program",
                    subtitle: "A training draft shaped around your goal and schedule.",
                    dismiss: { dismiss() }
                ) {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        goalSection
                        profileSection
                        scheduleSection
                        actualGymSection
                        DisclosureGroup {
                            preferenceSection.padding(.top, AppSpacing.row)
                        } label: {
                            Text("Additional details").accessibilityIdentifier("ai_program_additional_details")
                        }
                        .tint(AppPalette.text)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .appTextRole(.secondary)
                                .foregroundStyle(AppPalette.critical)
                                .fixedSize(horizontal: false, vertical: true)
                                .appSurface(.quiet)
                                .accessibilityIdentifier("ai_program_error")
                        }
                    }
                } actions: {
                    if generatedProgram != nil {
                        Button("Resume reviewed proposal") { editingRequirements = false }.frame(minHeight: 44)
                    }
                    if hasFrozenSubmission {
                        Text("Your program is ready to retry. Open the saved proposal to finish.")
                            .appTextRole(.secondary)
                    }
                    Button(action: generatePlan) {
                        Label("Generate program", systemImage: "sparkles")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isLoading || hasFrozenSubmission || goal.trimmed.isEmpty || selectedDaysOfWeek.count != daysPerWeek)
                    .accessibilityIdentifier("ai_program_generate")
                }
            }

            if isLoading {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    ProgressView()
                        .tint(AppPalette.brand)

                    AppSectionHeader(
                        title: "Building your program",
                        subtitle: "Balancing your goal, schedule, equipment, and recovery needs."
                    )

                    Button("Cancel generation", action: cancelGeneration)
                        .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .appSurface(.emphasized)
                .padding(AppSpacing.screenHorizontal)
                .accessibilityIdentifier("ai_program_loading")
            }
        }
        .tint(AppPalette.brand)
        .onAppear(perform: restoreProposal)
        .onDisappear {
            generationTask?.cancel()
            if !proposalAccepted, outlineReview == nil { checkpointProposal() }
        }
        .sheet(isPresented: $showingGyms) { StrengthGymLibraryView { gym = $0; movementMappings = [:]; checkpointProposal() } }
        .sheet(isPresented: $showingAllowedMovements) {
            ExercisePickerView { movement in
                movementMappings[movement.name] = gym?.implements.first?.id ?? ""
                checkpointProposal()
            }
        }
        .sheet(isPresented: $choosingMovementPreference) {
            ExercisePickerView { movement in
                guard WorkoutMovementCatalog.canonicalName(movement.name) == movement.name else { errorMessage = "Generation needs a canonical catalog movement. Keep custom movements for the normal editor."; return }
                if choosingAvoidedMovement { if !avoidedMovements.contains(movement.name) { avoidedMovements.append(movement.name) } } else if !preferredMovements.contains(movement.name) { preferredMovements.append(movement.name) }
                checkpointProposal()
            }
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(workoutService: workoutService, routine: routine, draftScope: "ai-proposal-routine-\(routine.id)") { edited in
                guard var proposal else { throw WorkoutBlockError.changed }
                let updated = try proposal.replacingRoutine(id: routine.id, with: edited)
                proposal.program = updated; self.proposal = proposal; generatedProgram = updated
                try WorkoutAIProposalStore().save(proposal)
            }
        }
        .sheet(item: $outlineReview) { review in
            NavigationStack {
                    ProgramCreatorView(workoutService: workoutService, proposedEdits: review.program,
                        onReviewDraft: { edited in
                            guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID,
                                  let current = self.proposal,
                                  (try? PlanFingerprint.make(Optional(current))) == review.fingerprint else { throw WorkoutBlockError.changed }
                            try verifyCurrentGym(current.request, ownerID: ownerID)
                            let updated = try current.replacingOutline(with: edited)
                            guard let checked = updated.program else { throw WorkoutBlockError.invalid }
                            try WorkoutAIProposalStore().save(updated)
                            self.proposal = updated; generatedProgram = checked
                            startDate = checked.startDate ?? startDate; selectedDaysOfWeek = checked.daysOfWeek ?? selectedDaysOfWeek
                        }, reviewDraftScope: "ai-proposal-outline-\(review.requestID)-\(review.fingerprint)")
            }
        }

    }

    private var actualGymSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Button(gym.map { "Gym: \($0.name)" } ?? "Use my actual gym inventory") { showingGyms = true }
                .frame(minHeight: 44).accessibilityIdentifier("ai_program_actual_gym")
            if let gym {
                Text("Only mapped movements plus supported floor work can be generated. Confirm benches and attachments yourself when choosing movements; a dumbbell rack alone does not imply a bench.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                ForEach(movementMappings.keys.sorted(), id: \.self) { name in
                    Picker(name, selection: Binding(get: { movementMappings[name] ?? "" }, set: { movementMappings[name] = $0; checkpointProposal() })) {
                        ForEach(gym.implements) { Text($0.name).tag($0.id) }
                    }
                    Button("Remove \(name)") { movementMappings.removeValue(forKey: name); checkpointProposal() }.frame(minHeight: 44)
                }
                Button("Confirm another available movement") { showingAllowedMovements = true }.frame(minHeight: 44)
                Button("Use equipment class instead") { self.gym = nil; movementMappings = [:]; checkpointProposal() }.frame(minHeight: 44)
            }
            DisclosureGroup("Movement preferences & exclusions") {
                Text("Preferences are optional. Avoid is enforced against generated exercises and alternatives. This records your choice; it does not diagnose injury.").appTextRole(.caption).foregroundStyle(.secondary)
                ForEach(preferredMovements.sorted(), id: \.self) { name in
                    Button("Prefer: \(name) · Remove") { preferredMovements.removeAll { $0 == name }; checkpointProposal() }.frame(minHeight: 44)
                }
                Button("Add a preferred movement") { choosingAvoidedMovement = false; choosingMovementPreference = true }.frame(minHeight: 44)
                ForEach(avoidedMovements.sorted(), id: \.self) { name in
                    Button("Avoid: \(name) · Remove") { avoidedMovements.removeAll { $0 == name }; checkpointProposal() }.frame(minHeight: 44)
                }
                Button("Choose a movement to avoid") { choosingAvoidedMovement = true; choosingMovementPreference = true }.frame(minHeight: 44)
            }
            if let active = workoutService.activeProgram {
                Text("Current program: \(active.name). Saving this proposal adds an independent plan; activate it deliberately from Saved plans when ready. Your current progress stays intact.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if proposal != nil {
                Text("Your reviewed proposal is saved on this device.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }.appSurface(.quiet)
    }
    private func requestSnapshot() -> WorkoutAIRequestSnapshot {
        WorkoutAIRequestSnapshot(goal: goal, daysPerWeek: daysPerWeek, maximumSessionMinutes: maximumSessionMinutes,
            experience: fitnessLevel.rawValue, equipmentClass: equipment.rawValue, details: details, gym: gym,
            movementMappings: movementMappings, startDate: startDate, weekdays: selectedDaysOfWeek,
            preferredMovements: preferredMovements, avoidedMovements: avoidedMovements)
    }
    private func restoreProposal() {
        guard !restored, let ownerID else { return }; restored = true
        do {
            guard let saved = try WorkoutAIProposalStore().load(userID: ownerID) else { return }
            proposal = saved; generatedProgram = saved.program
            let request = saved.pendingRequest ?? saved.request
            goal = request.goal; daysPerWeek = request.daysPerWeek; maximumSessionMinutes = request.maximumSessionMinutes
            fitnessLevel = FitnessLevel(rawValue: request.experience) ?? .beginner
            equipment = Equipment(rawValue: request.equipmentClass) ?? .fullGym; details = request.details
            gym = request.gym; movementMappings = request.movementMappings; startDate = request.startDate; selectedDaysOfWeek = request.weekdays
            preferredMovements = request.preferredMovements ?? []; avoidedMovements = request.avoidedMovements ?? []
            if saved.pendingRequest == nil, let program = saved.program {
                startDate = program.startDate ?? startDate; selectedDaysOfWeek = program.daysOfWeek ?? selectedDaysOfWeek
            }
        } catch { errorMessage = "The saved proposal could not reopen. It is retained on this device. \(error.localizedDescription)" }
    }
    private func checkpointProposal() {
        guard restored, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return }
        do {
            if var saved = proposal { saved.program = generatedProgram; saved.pendingRequest = requestSnapshot(); try WorkoutAIProposalStore().save(saved); proposal = saved } else { try WorkoutAIProposalStore().save(WorkoutAIProposal(ownerID: ownerID, request: requestSnapshot())) }
        } catch { errorMessage = "Could not checkpoint this proposal. Keep this screen open. \(error.localizedDescription)" }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Your goal"
            )

            TextField("Build muscle, improve endurance, return to training...", text: $goal)
                .textInputAutocapitalization(.sentences)
                .appTextRole(.control)
                .padding(AppSpacing.group)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityIdentifier("ai_program_goal")
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Training setup"
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Experience")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Experience", selection: $fitnessLevel) {
                        ForEach(FitnessLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Equipment")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .appTextRole(.control)
                    Text(WorkoutPlanningEquipment(request: equipment.rawValue)?.explanation ?? "Review equipment before training.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Stepper("Time budget: \(maximumSessionMinutes) min", value: $maximumSessionMinutes, in: 15...120, step: 5)
                    .appTextRole(.control).accessibilityIdentifier("ai_program_time_budget")
                Text("The planning estimate includes warm-up, setup and between-set rest. Your actual session time can vary.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            .appSurface(.emphasized)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Your schedule"
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Stepper(
                    "Training days: \(daysPerWeek)",
                    value: $daysPerWeek,
                    in: 2...6
                )
                .appTextRole(.control)

                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .appTextRole(.control)

                WeekDaySelector(selectedDays: $selectedDaysOfWeek)
                if selectedDaysOfWeek.count != daysPerWeek {
                    Text("Choose exactly \(daysPerWeek) training days; \(selectedDaysOfWeek.count) selected.")
                        .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                }
            }
            .appSurface(.emphasized)
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Preferences & constraints",
                subtitle: "Optional details help Maia avoid exercises or schedules that do not fit."
            )

            TextEditor(text: $details)
                .appTextRole(.body)
                .frame(minHeight: 120)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Example: Keep sessions near 30 minutes and avoid high-impact knee work.")
                            .appTextRole(.secondary)
                            .foregroundStyle(.tertiary)
                            .padding(AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func verifyCurrentGym(_ request: WorkoutAIRequestSnapshot, ownerID: String) throws {
        guard let frozenGym = request.gym else { return }
        guard let current = try StrengthGymProfileStore().profiles(userID: ownerID).first(where: { $0.id == frozenGym.id }),
              current == frozenGym else { throw StrengthSessionToolsError.changed }
    }

    /// Calls the WorkoutService to generate a plan using the form data.
    private func generatePlan() {
        guard selectedDaysOfWeek.count == daysPerWeek else {
            errorMessage = "Choose the requested number of training days before generating."; return
        }
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return }
        let request = requestSnapshot()
        let frozen = WorkoutAIProposal(ownerID: ownerID, request: request, program: generatedProgram)
        do { try verifyCurrentGym(request, ownerID: ownerID); try WorkoutAIProposalStore().save(frozen); proposal = frozen } catch { errorMessage = error.localizedDescription; return }
        isLoading = true
        errorMessage = nil
        generationTask?.cancel()
        generationTask = Task {
            let result = await workoutService.generateAIWorkoutPlan(
                goal: goal,
                daysPerWeek: daysPerWeek,
                fitnessLevel: fitnessLevel.rawValue,
                equipment: equipment.rawValue,
                details: request.details,
                goalSettings: goalSettings,
                maximumSessionMinutes: maximumSessionMinutes, gym: request.gym, confirmedMovements: request.movementMappings,
                preferredMovements: request.preferredMovements ?? [], avoidedMovements: request.avoidedMovements ?? []
            )

            guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID, proposal?.request.id == request.id else { return }
            isLoading = false
            switch result {
            case .success(var program):
                program.id = UUID().uuidString
                do {
                    program = try frozen.validatedProgram(program)
                    var accepted = frozen; accepted.program = program; accepted.acceptedRequestIDs.append(request.id)
                    try WorkoutAIProposalStore().save(accepted)
                    self.proposal = accepted; self.generatedProgram = program; editingRequirements = false
                } catch { errorMessage = error.localizedDescription }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func regenerate(routine: WorkoutRoutine, movementID: String?) {
        guard let frozen = proposal, let ownerID, DIContainer.shared.authService.currentUserID == ownerID, !isLoading else { return }
        isLoading = true; errorMessage = nil
        let originalFingerprint = frozen.program.flatMap { try? WorkoutBlockRules.structureFingerprint($0) }
        generationTask = Task {
            let target = movementID.flatMap { id in routine.exercises.first { $0.id == id } }
            let constraint = target.map { "Replace only \($0.name) with exactly one movement. Return one routine containing exactly that one exercise." }
                ?? "Regenerate only the session named \(routine.name). Return exactly one routine."
            let response = await workoutService.generateAIWorkoutPlan(goal: frozen.request.goal, daysPerWeek: 1,
                fitnessLevel: frozen.request.experience, equipment: frozen.request.equipmentClass,
                details: frozen.request.details + "\n" + constraint,
                goalSettings: goalSettings, maximumSessionMinutes: frozen.request.maximumSessionMinutes, gym: frozen.request.gym, confirmedMovements: frozen.request.movementMappings,
                preferredMovements: frozen.request.preferredMovements ?? [], avoidedMovements: frozen.request.avoidedMovements ?? [])
            guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID else { return }
            isLoading = false
            do {
                guard proposal?.request.id == frozen.request.id,
                      proposal?.program.flatMap({ try? WorkoutBlockRules.structureFingerprint($0) }) == originalFingerprint else { throw WorkoutBlockError.changed }
                let generated = try response.get()
                guard generated.routines.count == 1, let replacement = generated.routines.first,
                      let edited = routine.deepCopy() else { throw WorkoutBlockError.invalid }
                if let movementID {
                    guard replacement.exercises.count == 1, let index = edited.exercises.firstIndex(where: { $0.id == movementID }) else { throw WorkoutBlockError.invalid }
                    edited.exercises[index] = replacement.exercises[0]
                } else { edited.name = replacement.name; edited.exercises = replacement.exercises }
                var updated = frozen; updated.program = try frozen.replacingRoutine(id: routine.id, with: edited)
                updated.acceptedRequestIDs.append(UUID().uuidString)
                try WorkoutAIProposalStore().save(updated); proposal = updated; generatedProgram = updated.program
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isLoading = false
    }
}

/// A view to show the AI-generated program before the user saves it.
private struct AIProgramOutlineReview: Identifiable {
    let id = UUID()
    let program: WorkoutProgram
    let requestID: String
    let fingerprint: String
}

struct GeneratedProgramPreviewView: View {
    let program: WorkoutProgram
    var requestSummary: String?
    var isSaving = false
    var saveError: String?
    var onBack: () -> Void
    var onEditOutline: (() -> Void)?
    var onEditRoutine: ((WorkoutRoutine) -> Void)?
    var onRegenerateRoutine: ((WorkoutRoutine) -> Void)?
    var onRegenerateMovement: ((WorkoutRoutine, String) -> Void)?
    var onSave: () -> Void

    var body: some View {
        AppEditorScaffold(
            title: program.name,
            subtitle: "Review every session before adding this program to your training library.",
            dismiss: onBack
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                HStack {
                    Text("\(program.routines.count) sessions").appTextRole(.control)
                    Spacer()
                    Label("Maia draft", systemImage: "sparkles")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if let requestSummary {
                    Text(requestSummary).appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if let onEditOutline {
                    Button("Edit program details", action: onEditOutline)
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("ai_program_edit_outline")
                        .disabled(program.trainingBlock != nil)
                }
                if program.trainingBlock != nil {
                    Text("Your reviewed sessions and schedule are ready to retry.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Your sessions",
                        subtitle: "Review or edit each day before saving."
                    )

                    LazyVStack(spacing: AppSpacing.row) {
                        ForEach(program.routines) { routine in
                            VStack(alignment: .leading, spacing: AppSpacing.row) {
                                HStack(alignment: .center, spacing: AppSpacing.compact) {
                                    Text(routine.name)
                                        .appTextRole(.control)
                                        .foregroundStyle(AppPalette.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let onEditRoutine {
                                        Button { onEditRoutine(routine) } label: { Image(systemName: "pencil") }
                                            .buttonStyle(AppIconButtonStyle(.plain))
                                            .accessibilityLabel("Edit \(routine.name)")
                                            .disabled(program.trainingBlock != nil)
                                    }
                                    if onRegenerateRoutine != nil || onRegenerateMovement != nil {
                                        Menu {
                                            if let onRegenerateRoutine {
                                                Button("Regenerate session", systemImage: "arrow.clockwise") { onRegenerateRoutine(routine) }
                                            }
                                            if let onRegenerateMovement {
                                                Menu("Replace a movement") {
                                                    ForEach(routine.exercises) { exercise in
                                                        Button(exercise.name) { onRegenerateMovement(routine, exercise.id) }
                                                    }
                                                }
                                            }
                                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                        .accessibilityLabel("Options for \(routine.name)")
                                        .disabled(program.trainingBlock != nil)
                                    }
                                }
                                ForEach(routine.exercises) { exercise in
                                    HStack(spacing: AppSpacing.compact) {
                                        Circle()
                                            .fill(exercise.type.color)
                                            .frame(width: 6, height: 6)
                                            .accessibilityHidden(true)
                                        Text(exercise.name)
                                            .appTextRole(.body)
                                        Spacer(minLength: AppSpacing.compact)
                                        Text("\(exercise.sets.count) sets")
                                            .appTextRole(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .appSurface(.emphasized)
                        }
                    }
                }
                DisclosureGroup("Plan fit & equipment") {
                    ProgramPlanningReviewCard(program: program)
                        .padding(.top, AppSpacing.row)
                }
                .tint(AppPalette.text)
            }
        } actions: {
            if let saveError {
                Text(saveError).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button(isSaving ? "Saving program…" : "Save program", action: onSave)
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isSaving)
                .accessibilityIdentifier("ai_program_save")

            Button("Edit request", action: onBack)
                .buttonStyle(AppActionButtonStyle(.ghost))
                .disabled(isSaving)
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
    }
}

/// A reusable component for selecting days of the week.
struct WeekDaySelector: View {
    @Binding var selectedDays: [Int]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let days = [
        WeekDayChoice(day: 1, shortName: "S", fullName: "Sunday"),
        WeekDayChoice(day: 2, shortName: "M", fullName: "Monday"),
        WeekDayChoice(day: 3, shortName: "T", fullName: "Tuesday"),
        WeekDayChoice(day: 4, shortName: "W", fullName: "Wednesday"),
        WeekDayChoice(day: 5, shortName: "T", fullName: "Thursday"),
        WeekDayChoice(day: 6, shortName: "F", fullName: "Friday"),
        WeekDayChoice(day: 7, shortName: "S", fullName: "Saturday")
    ]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.compact) {
                    ForEach(days) { day in
                        dayButton(day, usesFullName: true)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(days) { day in
                            dayButton(day, usesFullName: false)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: AppSpacing.compact) {
                        ForEach(days) { day in
                            dayButton(day, usesFullName: true)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("weekday_selector")
    }

    private func dayButton(_ day: WeekDayChoice, usesFullName: Bool) -> some View {
        let isSelected = selectedDays.contains(day.day)
        return Button {
            if let index = selectedDays.firstIndex(of: day.day) {
                selectedDays.remove(at: index)
            } else {
                selectedDays.append(day.day)
            }
        } label: {
            Text(usesFullName ? day.fullName : day.shortName)
                .appTextRole(usesFullName ? .secondary : .control)
                .frame(width: usesFullName ? nil : 42)
                .frame(maxWidth: usesFullName ? .infinity : nil, minHeight: 44)
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.text)
                .background(
                    isSelected ? AppPalette.brand : AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppPalette.separator, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.fullName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct WeekDayChoice: Identifiable {
    let day: Int
    let shortName: String
    let fullName: String

    var id: Int { day }
}
