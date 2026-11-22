import MyFitPlateCore
import SwiftUI

struct StrengthSessionToolsView: View {
    let routineID: String
    let history: [WorkoutSessionLog]
    let historyAvailable: Bool
    let onApply: (StrengthSessionChange) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [RoutineExercise]
    @State private var mode = 0
    @State private var profile: StrengthGymProfile?
    @State private var mappings: [String: String] = [:]
    @State private var showingGyms = false
    @State private var savedGyms: [StrengthGymProfile] = []
    @State private var gymLibraryError: String?
    @State private var lighter = false
    @State private var selectedExerciseIDs = Set<String>()
    @State private var reviewedPlans: [String: ProgressionPlan] = [:]
    @State private var editingTargets: RoutineExercise?
    @State private var errorMessage: String?
    private let ownerID = DIContainer.shared.authService.currentUserID

    init(routineID: String, exercises: [RoutineExercise], history: [WorkoutSessionLog], historyAvailable: Bool,
         onApply: @escaping (StrengthSessionChange) throws -> Void) {
        self.routineID = routineID; self.history = history; self.historyAvailable = historyAvailable; self.onApply = onApply
        _exercises = State(initialValue: exercises)
        _selectedExerciseIDs = State(initialValue: Set(exercises.filter {
            ProgressionRules.plan(for: $0, history: history, routineID: routineID) != nil
                && $0.sets.contains { !$0.isCompleted && $0.resolvedSetType == .normal }
        }.map(\.id)))
    }

    private var validMappings: [String: String] {
        mappings.filter { entry in !entry.value.isEmpty && exercises.contains { $0.id == entry.key && !$0.sets.contains(where: \.isCompleted) } }
    }
    private var equipmentChange: StrengthSessionChange? {
        guard let profile else { return nil }
        return try? StrengthSessionToolsRules.equipmentChange(profile: profile, mappings: validMappings, exercises: exercises)
    }
    private func plan(for exercise: RoutineExercise) -> ProgressionPlan? {
        reviewedPlans[exercise.id] ?? ProgressionRules.plan(for: exercise, history: history, routineID: routineID, lighterSession: lighter)
    }
    private var progressionPlans: [ProgressionPlan] {
        exercises.filter { selectedExerciseIDs.contains($0.id) }.compactMap { plan(for: $0) }
    }
    private var change: StrengthSessionChange? {
        if mode == 0 { return equipmentChange }
        return try? StrengthSessionToolsRules.progressionChange(plans: progressionPlans, exercises: exercises)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Session review", selection: $mode) {
                        Text("Gym setup").tag(0); Text("Targets").tag(1)
                    }.pickerStyle(.segmented).accessibilityIdentifier("session_tools_mode")
                    Text("Updates this workout only.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if mode == 0 { gymSections } else { progressionSections }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution).accessibilityIdentifier("session_tools_error") } }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityIdentifier("session_tools_form")
            .navigationTitle("Gym & session targets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button(mode == 0 ? "Apply gym setup" : "Apply targets", action: apply)
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(change == nil || (mode == 1 && !historyAvailable))
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("session_tools_apply")
            }
            .onAppear(perform: reloadSavedGyms)
            .sheet(isPresented: $showingGyms, onDismiss: reloadSavedGyms) {
                StrengthGymLibraryView(onSelect: selectGym)
            }
            .sheet(item: $editingTargets) { exercise in
                if let plan = plan(for: exercise) {
                    ProgressionTargetsReview(exercise: exercise, history: history, routineID: routineID, initialPlan: plan) { reviewed in
                        reviewedPlans[exercise.id] = reviewed; selectedExerciseIDs.insert(exercise.id)
                    }
                }
            }
        }
    }

    @ViewBuilder private var gymSections: some View {
        Section {
            ForEach(quickGyms) { gym in
                Button { selectGym(gym) } label: {
                    HStack(spacing: AppSpacing.row) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gym.name).appTextRole(.control).foregroundStyle(AppPalette.text)
                            Text("\(gym.implements.count.formatted()) \(gym.implements.count == 1 ? "implement" : "implements")")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: AppSpacing.compact)
                        Image(systemName: profile?.id == gym.id ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(profile?.id == gym.id ? AppPalette.brandText : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Review \(gym.name)")
                .accessibilityValue(profile?.id == gym.id ? "Selected for review" : "Not selected")
                .accessibilityIdentifier("session_quick_gym_\(gym.id)")
            }
            Button(savedGyms.isEmpty ? "Add a gym" : "Manage all gyms", systemImage: savedGyms.isEmpty ? "plus" : "folder") {
                showingGyms = true
            }
            .frame(minHeight: 44).accessibilityIdentifier("session_choose_gym")
            if let gymLibraryError {
                Text(gymLibraryError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                Button("Retry saved gyms", action: reloadSavedGyms).frame(minHeight: 44)
            }
        } header: {
            Text("Saved gyms")
        } footer: {
            Text("Review the equipment and loads, then apply. Logged movements keep their setup.")
        }
        if let profile {
            ForEach(exercises.filter { $0.type == .strength }) { exercise in
                Section(exercise.name) {
                    if exercise.sets.contains(where: \.isCompleted) {
                        Label("Already logged · setup kept", systemImage: "lock").foregroundStyle(.secondary)
                    } else {
                        if profile.implements.count == 1, let implement = profile.implements.first {
                            Toggle("Use \(implement.name)", isOn: Binding(
                                get: { mappings[exercise.id] == implement.id },
                                set: { mappings[exercise.id] = $0 ? implement.id : nil }
                            ))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("session_gym_mapping_\(exercise.id)")
                        } else {
                            Picker("Implement", selection: Binding(get: { mappings[exercise.id] ?? "" }, set: { mappings[exercise.id] = $0 })) {
                                Text("Keep current setup").tag("")
                                ForEach(profile.implements) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("session_gym_mapping_\(exercise.id)")
                        }
                        if let proposed = equipmentChange?.after.first(where: { $0.id == exercise.id }),
                           let equipment = proposed.loadEquipment, validMappings[exercise.id] != nil {
                            Text(equipmentSummary(equipment)).appTextRole(.secondary).foregroundStyle(.secondary)
                            Text("An unknown or changed loading meaning clears all unfinished loads for manual review, including warm-ups and drop sets. It does not copy machine results or total loads into per-hand values.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            ForEach(proposed.sets) { target in
                                if let old = exercise.sets.first(where: { $0.id == target.id }), let equipment = proposed.loadEquipment {
                                    let unit = equipment.unit
                                    Text("\(setRole(target.resolvedSetType)): \(unit.displayWeight(old.weight).formatted(.number.precision(.fractionLength(0...3)))) → \(target.weight == 0 ? "Choose load" : unit.displayWeight(target.weight).formatted(.number.precision(.fractionLength(0...3))) + " " + unit.rawValue) · \(target.reps) reps")
                                        .appTextRole(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !validMappings.isEmpty, equipmentChange == nil {
                Section { Text("A selected implement cannot provide one of these loads. Review its inventory or keep that movement's setup.").foregroundStyle(AppPalette.caution) }
            }
        }
    }

    @ViewBuilder private var progressionSections: some View {
        Section {
            Toggle("Review lighter targets for today", isOn: $lighter).accessibilityIdentifier("session_targets_lighter")
            Text("Review each target below. Completed sets and percentage prescriptions stay unchanged.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if !reviewedPlans.isEmpty {
                Text("Your reviewed edits are kept when lighter targets are toggled.").foregroundStyle(.secondary)
                Button("Reset reviewed edits") { reviewedPlans = [:] }.frame(minHeight: 44)
            }
            if !historyAvailable { Text("Comparable history is still unavailable. Close and retry previous workouts before applying session targets.").foregroundStyle(AppPalette.caution) }
        }
        ForEach(exercises.filter { $0.type == .strength }) { exercise in
            Section(exercise.name) {
                if let plan = plan(for: exercise), exercise.sets.contains(where: { !$0.isCompleted && $0.resolvedSetType == .normal }) {
                    Toggle("Include movement", isOn: Binding(get: { selectedExerciseIDs.contains(exercise.id) }, set: {
                        if $0 { selectedExerciseIDs.insert(exercise.id) } else { selectedExerciseIDs.remove(exercise.id) }
                    })).accessibilityIdentifier("session_targets_include_\(exercise.id)")
                    Text(plan.headline).appTextRole(.control)
                    Text(plan.rationale).appTextRole(.secondary).foregroundStyle(.secondary)
                    Text("\(plan.sessionCount) comparable session\(plan.sessionCount == 1 ? "" : "s") used for this proposal")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    if let trend = plan.trend { Text("\(trend.title). \(trend.detail)").appTextRole(.secondary).foregroundStyle(.secondary) }
                    ForEach(plan.targets) { target in
                        if let current = exercise.sets.first(where: { $0.id == target.id }), !current.isCompleted {
                            let unit = exercise.loadEquipment?.unit ?? .lb
                            Text("Set \(target.setNumber): \(unit.displayWeight(current.weight).formatted(.number.precision(.fractionLength(0...3)))) × \(current.reps) → \(unit.displayWeight(target.weight).formatted(.number.precision(.fractionLength(0...3)))) \(unit.rawValue) × \(target.reps)")
                                .appTextRole(.secondary)
                        }
                    }
                    Button("Review exact targets") { editingTargets = exercise }.frame(minHeight: 44)
                        .accessibilityIdentifier("session_targets_edit_\(exercise.id)")
                } else {
                    Text(exercise.sets.allSatisfy(\.isCompleted) ? "Logged movement · no remaining targets" : "No compatible automatic proposal. Use manual targets; an authored percentage, changed setup, unsupported target or missing history may need your review.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickGyms: [StrengthGymProfile] {
        let currentIDs = Set(exercises.compactMap { $0.loadEquipment?.gymProfile?.profileID })
        return Array(savedGyms.sorted { first, second in
            let firstCurrent = currentIDs.contains(first.id)
            let secondCurrent = currentIDs.contains(second.id)
            if firstCurrent != secondCurrent { return firstCurrent }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }.prefix(3))
    }

    private func reloadSavedGyms() {
        do {
            guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID else {
                throw StrengthSessionToolsError.accountChanged
            }
            let latest = try StrengthGymProfileStore().profiles(userID: ownerID)
            savedGyms = latest; gymLibraryError = nil
            if let profile, !latest.contains(profile) {
                self.profile = nil; mappings = [:]
                errorMessage = "This gym changed. Choose it again to review the current equipment and loads."
            }
        } catch {
            savedGyms = []; profile = nil; mappings = [:]
            gymLibraryError = "Couldn't open your saved gyms. Your workout setup is unchanged."
        }
    }

    private func selectGym(_ selected: StrengthGymProfile) {
        do {
            guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID else {
                throw StrengthSessionToolsError.accountChanged
            }
            let store = StrengthGymProfileStore()
            guard try store.profiles(userID: ownerID).contains(selected) else { throw StrengthSessionToolsError.changed }
            let remembered = try store.mappings(profile: selected, routineID: routineID, userID: ownerID)
            profile = selected; mappings = remembered; errorMessage = nil
        } catch {
            profile = nil; mappings = [:]; errorMessage = error.localizedDescription
        }
    }

    private func setRole(_ type: SetType) -> String {
        switch type {
        case .warmup: "Warm-up"
        case .normal: "Working set"
        case .drop: "Drop set"
        case .failure: "Failure set"
        }
    }

    private func apply() {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID, let change else {
            errorMessage = StrengthSessionToolsError.accountChanged.localizedDescription; return
        }
        do {
            if let profile = change.profile {
                try StrengthGymProfileStore().rememberMappings(validMappings, profile: profile, routineID: routineID, userID: ownerID)
            }
            try onApply(change); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct StrengthWarmupRampView: View {
    let exercise: RoutineExercise
    let onApply: (StrengthWarmupPlan) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workingLoad: String
    @State private var formula = StrengthWarmupFormula.standard
    @State private var remember = false
    @State private var errorMessage: String?
    private let ownerID = DIContainer.shared.authService.currentUserID
    private var unit: StrengthEquipment.Unit { exercise.loadEquipment?.unit ?? .lb }
    private var preparation: Result<StrengthWarmupPlan, Error> {
        Result {
            guard let displayed = StrengthSetEntryRules.weight(from: workingLoad) else { throw StrengthSessionToolsError.invalid }
            return try StrengthWarmupRules.prepare(exercise: exercise, workingWeight: unit.storedWeight(displayed), formula: formula)
        }
    }
    private var plan: StrengthWarmupPlan? { try? preparation.get() }

    init(exercise: RoutineExercise, onApply: @escaping (StrengthWarmupPlan) throws -> Void) {
        self.exercise = exercise; self.onApply = onApply
        let value = exercise.sets.first { !$0.isCompleted && $0.resolvedSetType == .normal && $0.weight > 0 }?.weight
            ?? exercise.sets.first { $0.resolvedSetType == .normal && $0.weight > 0 }?.weight ?? 0
        _workingLoad = State(initialValue: value == 0 ? "" : (exercise.loadEquipment?.unit ?? .lb).displayWeight(value)
            .formatted(.number.grouping(.never).precision(.fractionLength(0...3))))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(exercise.name) {
                    LabeledContent("Working load (\(unit.rawValue))") {
                        TextField("Load", text: $workingLoad).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("warmup_working_load")
                    }
                    Text("A starting ramp, not a guarantee of readiness. Use the weights you can actually assemble and adjust preparation to how you feel.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                ForEach(formula.steps.indices, id: \.self) { index in
                    Section("Ramp step \(index + 1)") {
                        Stepper(value: $formula.steps[index].fraction, in: 0.05...0.95, step: 0.05) {
                            Text("\((formula.steps[index].fraction * 100).formatted(.number.precision(.fractionLength(0))))% of working load")
                        }
                        Stepper("\(formula.steps[index].reps) reps", value: $formula.steps[index].reps, in: 1...20)
                        Stepper("\(formula.steps[index].restSeconds) seconds rest", value: $formula.steps[index].restSeconds, in: 15...300, step: 15)
                    }
                }
                Section {
                    if formula.steps.count < 5 {
                        Button("Add ramp step") {
                            let fraction = min(0.95, (formula.steps.last?.fraction ?? 0.5) + 0.05)
                            formula.steps.append(StrengthWarmupStep(fraction: fraction, reps: 2, restSeconds: 90))
                        }.frame(minHeight: 44)
                    }
                    if formula.steps.count > 1 { Button("Remove last ramp step") { formula.steps.removeLast() }.frame(minHeight: 44) }
                    Toggle("Remember this ramp on this device", isOn: $remember)
                }
                if let plan {
                    Section("Review attainable warm-ups") {
                        ForEach(plan.sets) { set in
                            Text("\(unit.displayWeight(set.weight).formatted(.number.precision(.fractionLength(0...3)))) \(unit.rawValue) × \(set.reps) · \(set.generatedWarmup?.restSeconds ?? 0)s rest")
                                .accessibilityIdentifier("warmup_preview_\(set.id)")
                            if let equipment = exercise.loadEquipment, let plates = equipment.platePairs(for: set.weight) {
                                Text(plates.isEmpty ? "Empty configured bar" : "Per side: " + plates.map { unit.displayWeight($0).formatted(.number.precision(.fractionLength(0...3))) }.joined(separator: " + ") + " " + unit.rawValue)
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("\(plan.replacingIDs.count) untouched generated rows replaced · \(plan.retainedWarmupCount) manual, edited or logged warm-ups kept")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        if plan.sets.isEmpty { Text("These ramp steps are already present. No duplicate preparation will be added.").foregroundStyle(.secondary) }
                    }
                } else if case .failure(let error) = preparation {
                    Section { Text(error.localizedDescription).foregroundStyle(AppPalette.caution).accessibilityIdentifier("warmup_validation") }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution).accessibilityIdentifier("warmup_error") } }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityIdentifier("warmup_review_form")
            .navigationTitle("Warm-up ramp").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Apply reviewed warm-ups") {
                    guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID, let plan else { return }
                    do {
                        if remember { try StrengthWarmupPreferenceStore().save(formula, userID: ownerID) }
                        try onApply(plan); dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(plan?.sets.isEmpty != false)
                .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                .accessibilityIdentifier("warmup_apply")
            }
            .onAppear {
                do { if let ownerID, let saved = try StrengthWarmupPreferenceStore().load(userID: ownerID) { formula = saved } } catch { errorMessage = "Couldn't open your saved ramp. It has been kept; you can review a session-only ramp." }
            }
        }
    }
}
