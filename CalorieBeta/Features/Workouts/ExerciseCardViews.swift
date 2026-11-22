import MyFitPlateCore

import SwiftUI
import ActivityKit

struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    @Binding var isAutoRestEnabled: Bool
    var routineName: String
    var previousPerformance: CompletedExercise?
    var progressionHistory: [WorkoutSessionLog] = []
    var onAddNote: () -> Void
    var onSwap: (ExercisePickerDraft) -> Void
    var onBrowseSwaps: () -> Void
    var onViewHistory: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onRemove: (() -> Void)?
    var supersetPosition: SupersetRules.Position = .standalone
    var onToggleSupersetWithNext: (() -> Void)?
    var routineID: String?
    var activeSetID: String?
    var onCompletedSet: ((String) -> Void)?
    var onReopenedSet: ((String) -> Void)?
    var onApplyWarmup: ((StrengthWarmupPlan) throws -> Void)?
    var restDurationForSet: ((String) -> Int?)?
    var onDeferPartnerRound: (() -> Void)?
    var onRestoreDeferred: (() -> Void)?
    var isParked = false
    var onChangeParked: ((Bool) -> Void)?
    @State private var swapSuggestions: [WorkoutSubstitutionSuggestion] = []

    /// True when this exercise is supersetted with the one after it — the point of a
    /// superset is that you don't rest here, you go straight to the paired lift.
    private var isLinkedToNext: Bool { supersetPosition.isInSuperset && !supersetPosition.isLastInGroup }
    private var authoredRest: Int? { exercise.groupPlan?.transitionRestSeconds[exercise.id] }
    private var suppressAutoRest: Bool { authoredRest.map { $0 == 0 } ?? isLinkedToNext }

    @State private var showingTargetRepsEditor = false
    @State private var targetRepsInput = ""
    @State private var showingWarmupRamp = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var completedSetCount: Int {
        exercise.sets.filter(\.isCompleted).count
    }

    private var totalSetCount: Int {
        exercise.sets.count
    }

    private var exerciseProgress: Double {
        guard totalSetCount > 0 else { return 0 }
        return min(Double(completedSetCount) / Double(totalSetCount), 1)
    }

    private var typeChip: (title: String, icon: String, role: AppSignalRole) {
        switch exercise.type {
        case .strength:
            return ("Strength", "dumbbell.fill", .effort)
        case .cardio:
            return ("Cardio", "heart.fill", .effort)
        case .flexibility:
            return ("Mobility", "figure.cooldown", .recovery)
        }
    }

    private var displayedNote: String? {
        if let snapshot = exercise.cueSnapshot { return snapshot.text.isEmpty ? nil : snapshot.text }
        if let sessionNote = exercise.notes, !sessionNote.isEmpty {
            return sessionNote
        }
        return PinnedNotesManager.shared.getPinnedNote(for: exercise.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                exerciseIdentity

                AppProgressTrack(progress: exerciseProgress, role: typeChip.role, height: 6)

                if let note = displayedNote {
                    HStack(spacing: 4) {
                        if exercise.cueSnapshot?.scope != .session && exercise.cueSnapshot != nil {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if let snapshot = exercise.cueSnapshot {
                                Text("\(snapshot.scope.title) · \(snapshot.updatedAt.formatted(date: .abbreviated, time: .omitted))").appTextRole(.caption).foregroundStyle(.secondary)
                            } else if exercise.notes?.isEmpty != false {
                                Text("Saved cue · review scope").appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            Text(note)
                        }
                    }
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppPalette.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                }
            }

            if isParked, exercise.sets.contains(where: { !$0.isCompleted }), let onChangeParked {
                Button("Resume exercise", systemImage: "arrow.uturn.backward") { onChangeParked(false) }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("resume_parked_" + exercise.id)
            }
            if exercise.sets.contains(where: { $0.isDeferred == true && !$0.isCompleted }) {
                Text("Partner sets deferred · restore from the movement menu or review them when you finish.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            switch exercise.type {
            case .strength:
                StrengthExerciseView(
                    exercise: $exercise,
                    previousPerformance: previousPerformance,
                    progressionHistory: progressionHistory,
                    routineID: routineID,
                    activeSetID: activeSetID,
                    onSetReopen: { index in
                        let setID = exercise.sets[index].id
                        restTimer.cancelRestForReopenedSet(setID)
                        onReopenedSet?(setID)
                    },
                    onSetComplete: { completedIndex in
                        // Auto-fill logic
                        let nextIndex = completedIndex + 1
                        if nextIndex < exercise.sets.count {
                            let completedSet = exercise.sets[completedIndex]
                            if !exercise.sets[nextIndex].isCompleted && exercise.sets[nextIndex].weight == 0 && exercise.sets[nextIndex].reps == 0,
                               exercise.sets[nextIndex].resolvedSetType == completedSet.resolvedSetType {
                                exercise.sets[nextIndex].weight = completedSet.weight
                                exercise.sets[nextIndex].reps = completedSet.reps
                            }
                        }

                        // Auto-start rest timer — but not between the exercises inside a
                        // superset; you go straight to the paired lift and rest after the last.
                        if isAutoRestEnabled {
                            let set = exercise.sets[completedIndex]
                            let seconds = set.resolvedSetType == .warmup ? set.generatedWarmup?.restSeconds ?? exercise.restTimeInSeconds
                                : restDurationForSet?(set.id) ?? authoredRest ?? (suppressAutoRest ? 0 : exercise.restTimeInSeconds)
                            restTimer.startAfterCompletedSet(duration: TimeInterval(seconds), routineName: routineName,
                                                             exerciseID: exercise.id, setID: set.id)
                        }
                        onCompletedSet?(exercise.sets[completedIndex].id)
                    }
                )
            case .cardio:
                CardioExerciseView(exercise: $exercise, onCompletedSet: onCompletedSet)
            case .flexibility:
                FlexibilityExerciseView(exercise: $exercise, onCompletedSet: onCompletedSet)
            }

            Button {
                exercise.sets.append(ExerciseSet())
            } label: {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .appSurface(.quiet, padding: AppSpacing.group, radius: AppRadius.hero)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .stroke(supersetPosition.isInSuperset ? AppPalette.brand.opacity(0.45) : typeChip.role.color.opacity(0.08),
                        lineWidth: supersetPosition.isInSuperset ? 1.5 : 1)
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exercise_card_\(exercise.id)")
        .task(id: exercise.id) {
            swapSuggestions = WorkoutSubstitutionRanking.suggestions(for: exercise, limit: 5)
        }
        .sheet(isPresented: $showingTargetRepsEditor) {
            TargetRepsEditorSheet(initialTarget: targetRepsInput) { newTarget in
                exercise.targetReps = newTarget
                for index in exercise.sets.indices where !exercise.sets[index].isCompleted {
                    exercise.sets[index].target = newTarget
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingWarmupRamp) {
            StrengthWarmupRampView(exercise: exercise) { plan in
                if let onApplyWarmup { try onApplyWarmup(plan) } else { exercise = try StrengthWarmupRules.applying(plan, to: exercise) }
            }
        }
    }

    private var exerciseMenu: some View {
        HStack(spacing: 8) {
            if restTimer.timeRemaining <= 0 {
                Button {
                    restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName, exerciseID: exercise.id)
                } label: {
                    Image(systemName: "timer")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(AppPalette.recovery)
                        .frame(width: 44, height: 44)
                        .background(AppPalette.recovery.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start rest for \(exercise.name)")
                .accessibilityHint("\(exercise.restTimeInSeconds) seconds")
            }

            Menu {
                if !isParked, exercise.sets.contains(where: { !$0.isCompleted }), let onChangeParked {
                    Button("Do Later", systemImage: "clock.arrow.circlepath") { onChangeParked(true) }
                }
                Button("History & technique", action: onViewHistory)
                if exercise.type == .strength {
                    Button("Review warm-up ramp") { showingWarmupRamp = true }
                        .accessibilityIdentifier("warmup_review_\(exercise.id)")
                }
                Button("Add empty warm-up") {
                    let newWarmupSet = ExerciseSet(isWarmup: true)
                    exercise.sets.insert(newWarmupSet, at: 0)
                }
                Button("Add/Edit Note", action: onAddNote)
                if exercise.type == .strength {
                    Button {
                        targetRepsInput = exercise.targetReps
                        showingTargetRepsEditor = true
                    } label: {
                        Label("Edit Target Reps", systemImage: "pencil")
                    }
                }
                Toggle("Auto-Rest Timer", isOn: $isAutoRestEnabled)
                if let onDeferPartnerRound, supersetPosition.isInSuperset {
                    Button("Skip this partner's next set for now", action: onDeferPartnerRound)
                }
                if let onRestoreDeferred, exercise.sets.contains(where: { $0.isDeferred == true && !$0.isCompleted }) {
                    Button("Restore deferred partner sets", action: onRestoreDeferred)
                }
                if let onToggleSupersetWithNext {
                    Button(action: onToggleSupersetWithNext) {
                        Label(isLinkedToNext ? "Break superset" : "Superset with next", systemImage: "link")
                    }
                }
                if onMoveUp != nil || onMoveDown != nil {
                    Divider()
                    if let onMoveUp {
                        Button(action: onMoveUp) {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                    }
                    if let onMoveDown {
                        Button(action: onMoveDown) {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                    }
                }
                if let onRemove {
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label("Review unfinished removal", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 44, height: 44)
                    .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
            }
            .accessibilityLabel("Options for \(exercise.name)")
            .accessibilityIdentifier("exercise_options_\(exercise.id)")
        }
    }

    private var exerciseIdentity: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if exercise.sets.contains(where: { !$0.isCompleted }) {
                WorkoutSwapMenu(source: exercise, title: exercise.name, suggestions: swapSuggestions,
                    onChoose: onSwap, onBrowse: onBrowseSwaps)
            } else {
                Text(exercise.name).appTextRole(.control).foregroundStyle(AppPalette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .center, spacing: AppSpacing.compact) {
                exerciseIcon
                Text("\(typeChip.title) · \(completedSetCount) of \(totalSetCount) sets")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                exerciseMenu
            }
            supersetBadge
        }
    }

    private var exerciseIcon: some View {
        Image(systemName: exercise.type.icon)
            .appFont(size: 15, weight: .medium)
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var supersetBadge: some View {
        if supersetPosition.isInSuperset, let label = supersetPosition.groupLabel {
            Label("Superset \(label)", systemImage: "link")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(.brandForeground)
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.compact)
                .padding(.vertical, 4)
                .background(Color.brandPrimary.opacity(0.12), in: Capsule())
        }
    }
}

private struct TargetRepsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var target: String
    let onSave: (String) -> Void

    private let presets = ["5", "6-8", "8-12", "12-15", "AMRAP"]

    init(initialTarget: String, onSave: @escaping (String) -> Void) {
        _target = State(initialValue: initialTarget)
        self.onSave = onSave
    }

    var body: some View {
        AppEditorScaffold(
            title: "Target Reps",
            subtitle: "Updates this exercise and every unfinished set. Completed work stays unchanged.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                TextField("For example, 8-12", text: $target)
                    .appTextRole(.control)
                    .textInputAutocapitalization(.characters)
                    .padding(AppSpacing.row)
                    .background(
                        AppPalette.control,
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(AppPalette.separator, lineWidth: 0.5)
                    }
                    .accessibilityLabel("Target reps")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.compact) {
                        ForEach(presets, id: \.self) { preset in
                            Button(preset) {
                                target = preset
                            }
                            .appTextRole(.secondary)
                            .foregroundStyle(target == preset ? AppPalette.onBrand : AppPalette.text)
                            .padding(.horizontal, AppSpacing.row)
                            .frame(minHeight: 40)
                            .background(
                                target == preset ? AppPalette.brand : AppPalette.control,
                                in: Capsule()
                            )
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(target == preset ? .isSelected : [])
                        }
                    }
                }
            }
        } actions: {
            Button {
                let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(normalized)
                dismiss()
            } label: {
                Label("Update Target", systemImage: "checkmark")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct StrengthExerciseView: View {
    @Binding var exercise: RoutineExercise
    var previousPerformance: CompletedExercise?
    var progressionHistory: [WorkoutSessionLog] = []
    var routineID: String?
    var activeSetID: String?
    var onSetReopen: ((Int) -> Void)?
    var onSetComplete: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingEquipment = false
    @State private var equipmentAccount: String?
    @State private var showingTargets = false
    @State private var targetUndo: (before: RoutineExercise, applied: RoutineExercise)?

    private var suggestedPlan: ProgressionPlan? {
        ProgressionRules.plan(for: exercise, history: progressionHistory, routineID: routineID)
    }

    private var equipmentIsLocked: Bool { exercise.sets.contains(where: \.isCompleted) }

    private var equipmentTitle: String {
        exercise.loadEquipment.map { $0.name ?? "Equipment set up" } ?? "Set up equipment"
    }

    private var equipmentHint: String {
        if equipmentIsLocked {
            return "Equipment stays fixed for this session after a set is completed."
        }
        return "Choose your available weights and how you log the load. Target suggestions use history recorded with this setup."
    }

    var body: some View {
        VStack(spacing: 10) {
            setupAndTargets
            if let receipt = targetUndo {
                HStack {
                    Text("Targets applied").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Undo targets") {
                        exercise = ProgressionRules.undo(before: receipt.before, applied: receipt.applied, current: exercise)
                        targetUndo = nil
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("progression_undo_\(exercise.id)")
                }
                .appTextRole(.secondary)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("Set").frame(width: 54)
                    Text("Load (\(exercise.loadEquipment?.unit.rawValue ?? "lb"))").frame(maxWidth: .infinity)
                    Text("Reps").frame(maxWidth: .infinity)
                    Text("Log").frame(width: 48)
                }
                .appTextRole(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).accessibilityHidden(true)
            }

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                StrengthSetRow(
                    set: $exercise.sets[index],
                    setIndex: index + 1,
                    previousSet: ProgressionRules.previousSet(for: exercise.sets[index].id, exercise: exercise, previous: compatiblePreviousPerformance),
                    equipment: exercise.loadEquipment,
                    requiresManualLoad: exercise.substitution != nil && exercise.loadEquipment == nil
                        && (exercise.movementIdentity?.ownerID != nil || ExerciseList.equipment(for: exercise.name) != .bodyweight),
                    isActive: activeSetID == exercise.sets[index].id,
                    onReopen: { onSetReopen?(index) },
                    onComplete: {
                        onSetComplete(index)
                    }
                )
            }
            .onDelete(perform: deleteStrengthSet)
        }
        .sheet(isPresented: $showingEquipment) {
            StrengthEquipmentSetupView(exerciseName: exercise.name, equipment: exercise.loadEquipment,
                                       hasCompletedSets: exercise.sets.contains(where: \.isCompleted)) { equipment in
                guard let equipmentAccount, DIContainer.shared.authService.currentUserID == equipmentAccount,
                      !exercise.sets.contains(where: \.isCompleted) else { throw StrengthEquipmentPreferenceStore.StoreError.invalidIdentity }
                if let routineID {
                    try StrengthEquipmentPreferenceStore().save(equipment, userID: equipmentAccount,
                        routineID: routineID, exerciseID: exercise.id, exerciseName: exercise.name)
                }
                exercise.loadEquipment = equipment
                targetUndo = nil
            }
        }
        .sheet(isPresented: $showingTargets) {
            if let plan = suggestedPlan {
                ProgressionTargetsReview(exercise: exercise, history: progressionHistory, routineID: routineID, initialPlan: plan) { reviewed in
                    let before = exercise
                    exercise = ProgressionRules.applying(reviewed, to: exercise)
                    targetUndo = (before, exercise)
                }
            }
        }
        .onChange(of: exercise.name) { _, _ in targetUndo = nil }
    }

    private var setupAndTargets: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.compact))) {
            Button {
                equipmentAccount = DIContainer.shared.authService.currentUserID
                showingEquipment = true
            } label: {
                setupSummary(title: equipmentIsLocked ? "Equipment locked" : "Equipment",
                             detail: exercise.loadEquipment.map { "\($0.name ?? $0.kind.title) · \($0.loadingMeaning.title)" } ?? "Set up · lb",
                             icon: equipmentIsLocked ? "lock" : "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("strength_equipment_\(exercise.id)")
            .accessibilityLabel("\(equipmentTitle), \(exercise.loadEquipment?.unit.rawValue ?? "lb")\(exercise.loadEquipment.map { ", " + $0.loadingMeaning.title } ?? "")")
            .accessibilityValue(equipmentIsLocked ? "Locked for this session" : "Editable")
            .accessibilityHint(equipmentHint)
            .disabled(equipmentIsLocked)

            if let plan = suggestedPlan, exercise.sets.contains(where: { !$0.isCompleted && $0.resolvedSetType == .normal }) {
                Button { showingTargets = true } label: {
                    setupSummary(title: "Review targets", detail: plan.headline, icon: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progression_review_\(exercise.id)")
                .accessibilityLabel("Review targets. \(plan.headline)")
                .accessibilityHint("Review the suggested loads and reps before applying them.")
            }
        }
    }

    private func setupSummary(title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).appTextRole(.secondary).foregroundStyle(AppPalette.text)
                Spacer(minLength: 0)
                Image(systemName: icon).appTextRole(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(detail).appTextRole(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, AppSpacing.compact)
        .padding(.vertical, 4)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .contentShape(Rectangle())
    }

    private var compatiblePreviousPerformance: CompletedExercise? {
        guard let previousPerformance else { return nil }
        let log = WorkoutSessionLog(date: Date(), routineID: routineID ?? "", completedExercises: [previousPerformance])
        return ProgressionRules.performance(for: exercise, in: log)
    }

    private func deleteStrengthSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: IndexSet(offsets.filter { exercise.sets.indices.contains($0) && !exercise.sets[$0].isCompleted }))
    }
}

struct ProgressionTargetsReview: View {
    let exercise: RoutineExercise
    private var unit: StrengthEquipment.Unit { exercise.loadEquipment?.unit ?? .lb }
    let history: [WorkoutSessionLog]
    let routineID: String?
    let onApply: (ProgressionPlan) -> Void
    let forFutureSession: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var plan: ProgressionPlan
    @State private var increment: Double
    @State private var lighterSession = false
    @State private var showingLighterWeek = false
    @State private var weights: [String: String] = [:]
    @State private var reps: [String: String] = [:]
    private enum TargetField: Hashable { case weight(String), reps(String) }
    @State private var editedFields: Set<TargetField> = []
    @FocusState private var focusedField: TargetField?

    private var reviewedPlan: ProgressionPlan? {
        var reviewed = plan
        for index in reviewed.targets.indices {
            let id = reviewed.targets[index].id
            guard let weight = StrengthSetEntryRules.weight(from: weights[id] ?? ""),
                  let count = StrengthSetEntryRules.reps(from: reps[id] ?? "") else { return nil }
            let originalText = unit.displayWeight(reviewed.targets[index].weight)
                .formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
            if weights[id] != originalText { reviewed.targets[index].weight = unit.storedWeight(weight) }
            reviewed.targets[index].reps = count
        }
        return reviewed.isValid ? reviewed : nil
    }

    init(exercise: RoutineExercise, history: [WorkoutSessionLog], routineID: String? = nil, initialPlan: ProgressionPlan,
         forFutureSession: Bool = false,
         onApply: @escaping (ProgressionPlan) -> Void) {
        self.exercise = exercise
        self.history = history
        self.routineID = routineID
        self.onApply = onApply
        self.forFutureSession = forFutureSession
        var review = initialPlan
        review.targets.removeAll { target in exercise.sets.contains { $0.id == target.id && $0.isCompleted } }
        _plan = State(initialValue: review)
        _increment = State(initialValue: initialPlan.increment)
        _weights = State(initialValue: Dictionary(uniqueKeysWithValues: review.targets.map { ($0.id, (exercise.loadEquipment?.unit ?? .lb).displayWeight($0.weight).formatted(.number.grouping(.never).precision(.fractionLength(0...3)))) }))
        _reps = State(initialValue: Dictionary(uniqueKeysWithValues: review.targets.map { ($0.id, String($0.reps)) }))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.name).appTextRole(.control)
                    Text(plan.rationale).foregroundStyle(.secondary)
                    Text("Based on \(plan.sessionCount) recent \(plan.sessionCount == 1 ? "session" : "sessions"). Only unfinished regular sets will change.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if forFutureSession {
                        Text("These values are staged for one future session. Review and save the program change before they become its targets.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                if let trend = plan.trend {
                    Section("Longer-term progress") {
                        Text(trend.title).appTextRole(.control)
                        Text(trend.detail).appTextRole(.secondary).foregroundStyle(.secondary)
                        if trend.reviewLighterWeek && !forFutureSession {
                            Button("Review a lighter week") { showingLighterWeek = true }
                                .accessibilityIdentifier("progression_lighter_week")
                        }
                    }
                }
                Section("Adjust the suggestion") {
                    Picker("Smallest load increase", selection: $increment) {
                        ForEach(Array(Set([0.5, 1, 1.25, 2.5, 5, 10, 20].map { unit.storedWeight($0) } + [increment])).sorted(), id: \.self) { value in
                            Text("\(unit.displayWeight(value).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue)").tag(value)
                        }
                    }
                    .accessibilityIdentifier("progression_increment")
                    LabeledContent(forFutureSession ? "Lighter future session" : "Lighter session today") {
                        Toggle(forFutureSession ? "Lighter future session" : "Lighter session today", isOn: $lighterSession)
                            .labelsHidden()
                            .accessibilityLabel(forFutureSession ? "Lighter future session" : "Lighter session today")
                            .accessibilityIdentifier("progression_lighter")
                    }
                    .accessibilityElement(children: .contain)
                    Text(editedFields.isEmpty
                         ? "Choose the increase your equipment allows. These options refresh the suggested targets."
                         : "Your edited targets stay fixed. These options refresh the other suggestions.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("progression_edit_status")
                    Button {
                        editedFields.removeAll()
                        refreshTargets()
                    } label: {
                        Text("Reset edited targets")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(editedFields.isEmpty)
                    .accessibilityIdentifier("progression_reset_edits")
                }
                Section("Review each target") {
                    ForEach(plan.targets) { target in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text("Set \(target.setNumber)").fontWeight(.semibold)
                            Text(exercise.sets.first(where: { $0.id == target.id })?.target ?? exercise.targetReps)
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            LabeledContent("Weight (\(unit.rawValue))") {
                                TextField("Weight", text: Binding(get: { weights[target.id] ?? "" }, set: {
                                    weights[target.id] = $0
                                    editedFields.insert(.weight(target.id))
                                }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .weight(target.id))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityLabel("Set \(target.setNumber) target weight in \(unit.rawValue)")
                                    .accessibilityIdentifier("progression_weight_\(target.setNumber)")
                            }
                            .accessibilityElement(children: .contain)
                            LabeledContent("Reps") {
                                TextField("Reps", text: Binding(get: { reps[target.id] ?? "" }, set: {
                                    reps[target.id] = $0
                                    editedFields.insert(.reps(target.id))
                                }))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .reps(target.id))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityLabel("Set \(target.setNumber) target reps")
                                    .accessibilityIdentifier("progression_reps_\(target.setNumber)")
                            }
                            .accessibilityElement(children: .contain)
                        }
                    }
                }
                Section {
                    // Keep Form row identities stable as each keystroke changes
                    // validity, so inserting an error cannot drop the text responder.
                    Text(reviewedPlan == nil
                         ? (exercise.loadEquipment == nil ? "Enter a valid weight and 1–100 reps for each target." : "Choose an available equipment weight and 1–100 reps for each target.")
                         : "Review each weight and rep count before using these targets.")
                        .appTextRole(.secondary)
                        .foregroundStyle(reviewedPlan == nil ? AppPalette.caution : Color.secondary)
                        .accessibilityIdentifier("progression_validation")
                    Text("Warmups, drop sets, failure sets and completed work stay as recorded. You can still edit each set during your workout.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
            }
            .appFormStyle()
            .accessibilityIdentifier("progression_targets_form")
            .buttonStyle(AppListButtonStyle())
            .sheet(isPresented: $showingLighterWeek) {
                NavigationStack { WeekRescueView(initialReason: .lighterWeek) }
            }
            .navigationTitle(forFutureSession ? "Future set targets" : "Next set targets")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if focusedField == nil {
                    Button(forFutureSession ? "Use in review" : "Use these targets") {
                        guard let reviewedPlan else { return }
                        onApply(reviewedPlan)
                        dismiss()
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(reviewedPlan == nil)
                    .accessibilityIdentifier("progression_apply")
                    .padding(AppSpacing.row)
                    .background(AppPalette.surface)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if focusedField != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { focusedField = nil }
                            .accessibilityIdentifier("progression_finish_edit")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onChange(of: increment) { _, _ in refreshTargets() }
            .onChange(of: lighterSession) { _, _ in refreshTargets() }
        }
    }

    private func refreshTargets() {
        guard var updated = ProgressionRules.plan(for: exercise, history: history, routineID: routineID, increment: increment, lighterSession: lighterSession) else { return }
        updated.targets.removeAll { target in exercise.sets.contains { $0.id == target.id && $0.isCompleted } }
        plan = updated
        weights = Dictionary(uniqueKeysWithValues: updated.targets.map { target in
            (target.id, editedFields.contains(.weight(target.id)) ? weights[target.id] ?? ""
             : unit.displayWeight(target.weight).formatted(.number.grouping(.never).precision(.fractionLength(0...3))))
        })
        reps = Dictionary(uniqueKeysWithValues: updated.targets.map { target in
            (target.id, editedFields.contains(.reps(target.id)) ? reps[target.id] ?? "" : String(target.reps))
        })
    }
}

struct CardioExerciseView: View {
    @Binding var exercise: RoutineExercise
    var onCompletedSet: ((String) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Target").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Distance").frame(maxWidth: .infinity, alignment: .center)
                    Text("Time").frame(maxWidth: .infinity, alignment: .center)
                    Image(systemName: "checkmark").frame(width: 44)
                }
                .appTextRole(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                CardioSetRow(set: $exercise.sets[index], setIndex: index + 1, onCompletedSet: onCompletedSet)
            }
            .onDelete(perform: deleteCardioSet)
        }
    }

    private func deleteCardioSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: IndexSet(offsets.filter { exercise.sets.indices.contains($0) && !exercise.sets[$0].isCompleted }))
    }
}

struct FlexibilityExerciseView: View {
    @Binding var exercise: RoutineExercise
    var onCompletedSet: ((String) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Target").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Seconds").frame(maxWidth: .infinity, alignment: .center)
                    Image(systemName: "checkmark").frame(width: 44)
                }
                .appTextRole(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                FlexibilitySetRow(set: $exercise.sets[index], setIndex: index + 1, onCompletedSet: onCompletedSet)
            }
            .onDelete(perform: deleteFlexibilitySet)
        }
    }

    private func deleteFlexibilitySet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: IndexSet(offsets.filter { exercise.sets.indices.contains($0) && !exercise.sets[$0].isCompleted }))
    }
}

struct StrengthSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var previousSet: CompletedSet?
    var onComplete: () -> Void
    var onReopen: (() -> Void)?
    var equipment: StrengthEquipment?
    var isActive: Bool
    @Environment(\.workoutSetFocus) private var inputFocus
    @Environment(\.workoutSetCommand) private var inputCommand

    @FocusState private var focusedField: StrengthSetInput.Field?
    @State private var weightInput: String
    @State private var repsInput: String
    @State private var editedFields: Set<StrengthSetInput.Field> = []
    @State private var isPersonalBest = false
    @State private var showingPlateMath = false
    @State private var showingDetails = false
    @State private var entryError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var usesDetailedLayout: Bool { (!set.isCompleted && showingDetails) || dynamicTypeSize.isAccessibilitySize }

    private var unit: StrengthEquipment.Unit { equipment?.unit ?? .lb }
    private var weightIncrement: Double { unit.storedWeight(unit == .kg ? 1.25 : 2.5) }

    private var weightBinding: Binding<String> {
        Binding(get: { weightInput }, set: {
            editedFields.insert(.weight)
            weightInput = $0
        })
    }

    private var repsBinding: Binding<String> {
        Binding(get: { repsInput }, set: {
            editedFields.insert(.reps)
            repsInput = $0
        })
    }

    /// Whether this row logs effort as RPE or RIR (the user's Settings choice).
    @AppStorage("liftingEffortMetric") private var effortMetricRaw: String = "rpe"
    private var effortScale: SetEffort.Scale { effortMetricRaw == "rir" ? .rir : .rpe }
    private var effortOptions: [Double] {
        effortScale == .rir ? [0, 1, 2, 3, 4, 5] : [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    }
    /// Convert any stored effort into the currently-selected scale, so a set logged as
    /// RPE still reads correctly when the user prefers RIR (and vice-versa).
    private func effortInScale(_ effort: SetEffort) -> Double {
        if effort.scale == effortScale { return effort.value }
        let rpe = effort.normalizedRPE
        return effortScale == .rpe ? rpe : max(0, 10 - rpe)
    }
    private var effortDisplayValue: Double? {
        guard let effort = set.effort else { return nil }
        return effortInScale(effort)
    }
    private func formatEffort(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
    private var setTypeBinding: Binding<SetType> {
        Binding(get: { set.resolvedSetType }, set: { if !set.isCompleted { set.setKind($0) } })
    }
    private var setTypeColor: Color {
        switch set.resolvedSetType {
        case .warmup: return AppPalette.caution
        case .drop: return AppPalette.brand
        case .failure: return AppPalette.critical
        case .normal: return AppPalette.text
        }
    }

    private var targetText: String {
        self.set.prescription?.summary ?? self.set.target ?? "Work set"
    }

    private var setLabel: String {
        switch set.resolvedSetType {
        case .warmup: return "Warm-up"
        case .drop: return "Drop set"
        case .failure: return "Failure"
        case .normal: return "Set \(setIndex)"
        }
    }

    private var targetSummary: String {
        let summary = targetTextBeforeProgression()
        return summary.isEmpty ? "Work set" : summary
    }

    private var targetGuidance: String? {
        let normalized = normalizedTargetText()
        guard let range = normalized.range(of: "Progression:", options: .caseInsensitive) else {
            return nil
        }

        let guidance = normalized[range.lowerBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return guidance.isEmpty ? nil : guidance
    }

    private var previousText: String {
        guard let previousSet else { return "No prior set" }
        var text = "Last \(formatWeight(unit.displayWeight(previousSet.weight))) \(unit.rawValue) x \(previousSet.reps)"
        if let effort = previousSet.effort {
            text += " · \(effortScale == .rir ? "RIR" : "RPE") \(formatEffort(effortInScale(effort)))"
        }
        return text
    }

    private var completionIcon: String {
        return set.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private let requiresManualLoad: Bool

    init(set: Binding<ExerciseSet>, setIndex: Int, previousSet: CompletedSet?, equipment: StrengthEquipment? = nil, requiresManualLoad: Bool = false, isActive: Bool = false, onReopen: (() -> Void)? = nil, onComplete: @escaping () -> Void) {
        self._set = set
        self.setIndex = setIndex
        self.previousSet = previousSet
        self.onComplete = onComplete
        self.onReopen = onReopen
        self.equipment = equipment
        self.requiresManualLoad = requiresManualLoad
        self.isActive = isActive

        self._weightInput = State(initialValue: set.wrappedValue.weight > 0 ? (equipment?.unit ?? .lb).displayWeight(set.wrappedValue.weight).formatted(.number.grouping(.never).precision(.fractionLength(0...3))) : "")
        self._repsInput = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        setEntry
            .onChange(of: focusedField) { _, field in
                if let field {
                    inputFocus?.wrappedValue = StrengthSetInput(setID: set.id, field: field)
                } else {
                    Task { @MainActor in
                        await Task.yield()
                        if focusedField == nil, inputFocus?.wrappedValue?.setID == set.id { inputFocus?.wrappedValue = nil }
                    }
                }
            }
            .onChange(of: inputFocus?.wrappedValue) { _, requested in
                focusedField = requested?.setID == set.id ? requested?.field : nil
            }
            .onChange(of: inputCommand) { _, command in
                guard let command, command.setID == set.id else { return }
                switch command.action {
                case .increaseWeight: adjustWeight(by: weightIncrement)
                case .decreaseWeight: adjustWeight(by: -weightIncrement)
                case .increaseReps: adjustReps(by: 1)
                case .decreaseReps: adjustReps(by: -1)
                case .complete:
                    if !set.isCompleted { toggleCompletion() } else { inputFocus?.wrappedValue = nil; focusedField = nil }
                }
            }
            .sheet(isPresented: $showingPlateMath) { PlateMathVisualizer(totalWeight: set.weight, equipment: equipment) }
    }

    private var setEntry: some View {
        setContent
            .onChange(of: weightInput) { _, input in
                guard !set.isCompleted else { return }
                if let weight = storedWeight(from: input) {
                    set.weight = weight
                    checkIfPersonalBest(newWeight: weight, newRps: set.reps)
                }
                entryError = nil
            }
            .onChange(of: repsInput) { _, input in
                guard !set.isCompleted else { return }
                if let reps = StrengthSetEntryRules.reps(from: input) {
                    set.reps = reps
                    checkIfPersonalBest(newWeight: set.weight, newRps: reps)
                }
                entryError = nil
            }
            .onChange(of: set.weight) { _, weight in
                if storedWeight(from: weightInput).map({ abs($0 - weight) > 0.00001 }) ?? true { weightInput = weightText(weight) }
            }
            .onChange(of: set.reps) { _, reps in
                if Int(repsInput) != reps { repsInput = reps > 0 ? "\(reps)" : "" }
            }
            .onAppear(perform: fillEmptyFieldsFromHistory)
            .onChange(of: previousSet?.id) { _, _ in fillEmptyFieldsFromHistory() }
            .onChange(of: equipment) { _, _ in weightInput = weightText(set.weight) }
    }

    private var setContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if usesDetailedLayout { detailedContent } else { compactContent }
            if let entryError {
                Text(entryError).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("set_entry_error_\(set.id)")
            }
        }
        .id(set.id)
        .padding(8)
        .background(set.isCompleted ? AppPalette.positive.opacity(0.06) : AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(isActive && !set.isCompleted ? AppPalette.brand : set.isCompleted ? AppPalette.positive.opacity(0.35) : AppPalette.separator, lineWidth: isActive ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(setLabel), \(set.isCompleted ? "logged" : "not logged")")
        .accessibilityIdentifier("strength_set_row_\(set.id)")
    }

    @ViewBuilder
    private var useLastButton: some View {
        if !set.isCompleted, previousSet != nil {
            Button("Use last", action: fillFromPrevious)
                .appTextRole(.caption)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Use last performance. \(previousText)")
                .accessibilityIdentifier("set_use_last_\(set.id)")
        }
    }

    private var compactContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                compactSetControls.frame(width: 54, height: 44)
                TextField("0", text: weightBinding)
                    .id("strength_input_\(set.id)_weight")
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .disabled(set.isCompleted)
                    .accessibilityLabel("Weight in \(unit.rawValue)")
                    .accessibilityIdentifier("set_weight_\(setIndex)")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: 8))
                TextField("0", text: repsBinding)
                    .id("strength_input_\(set.id)_reps")
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
                    .disabled(set.isCompleted)
                    .accessibilityLabel("Reps")
                    .accessibilityIdentifier("set_reps_\(setIndex)")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: 8))
                completeButton
            }
            .appTextRole(.control).monospacedDigit()
            HStack(spacing: AppSpacing.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target \(targetSummary)")
                        .accessibilityIdentifier("set_target_\(set.id)")
                    if previousSet != nil, isActive || focusedField != nil {
                        Text(previousText)
                            .accessibilityIdentifier("set_previous_\(set.id)")
                    }
                }
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if set.isCompleted {
                    Label("Logged", systemImage: "checkmark.circle.fill")
                        .appTextRole(.caption).foregroundStyle(AppPalette.positive)
                        .accessibilityIdentifier("set_logged_\(set.id)")
                } else if isActive || focusedField != nil {
                    useLastButton
                }
            }
        }
    }

    @ViewBuilder private var compactSetControls: some View {
        if set.isCompleted {
            setTypeMenu
        } else {
            Button { showingDetails = true } label: {
                HStack(spacing: 4) {
                    Text(set.resolvedSetType == .normal ? "\(setIndex)" : String(setLabel.prefix(1)))
                        .appTextRole(.secondary).foregroundStyle(setTypeColor)
                    Image(systemName: "slider.horizontal.3")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 54, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More controls for \(setLabel)")
            .accessibilityHint("Review set type, previous performance, effort and load adjustments.")
            .accessibilityIdentifier("set_details_\(set.id)")
        }
    }

    private var detailedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                setTypeMenu

                Text("Target \(targetSummary)")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityIdentifier("set_target_\(set.id)")

                Spacer(minLength: 4)

                if showingDetails && !dynamicTypeSize.isAccessibilitySize {
                    Button { showingDetails = false } label: {
                        Image(systemName: "chevron.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Collapse set controls")
                }

            }

            if let targetGuidance {
                Text(targetGuidance)
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
             : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
                Text(previousText)
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("set_previous_\(set.id)")
                HStack(spacing: AppSpacing.compact) {
                    useLastButton
                    Spacer(minLength: 0)
                    effortMenuChip
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                weightInputGroup
                repsInputGroup
                completeButton
            }
        }
    }

    private var weightInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(unit.rawValue)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Spacer(minLength: 0)

                Button(action: { showingPlateMath = true }) {
                    Label("Plates", systemImage: "circle.grid.cross")
                        .labelStyle(.iconOnly)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plate math")
                .accessibilityHint("Shows which plates to load for this weight.")
            }

            HStack(spacing: 6) {
                setAdjustButton(systemName: "minus", label: "Decrease weight") {
                    adjustWeight(by: -weightIncrement)
                }

                TextField("0", text: weightBinding)
                    .id("strength_input_\(set.id)_weight")
                    .accessibilityLabel("Weight in \(unit.rawValue)")
                    .accessibilityIdentifier("set_weight_\(setIndex)")
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .disabled(set.isCompleted)
                    .multilineTextAlignment(.center)
                    .appFont(size: 18, weight: .bold)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                setAdjustButton(systemName: "plus", label: "Increase weight") {
                    adjustWeight(by: weightIncrement)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var repsInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reps")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 6) {
                setAdjustButton(systemName: "minus", label: "Decrease reps") {
                    adjustReps(by: -1)
                }

                TextField("0", text: repsBinding)
                    .id("strength_input_\(set.id)_reps")
                    .accessibilityLabel("Reps")
                    .accessibilityIdentifier("set_reps_\(setIndex)")
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
                    .disabled(set.isCompleted)
                    .multilineTextAlignment(.center)
                    .appFont(size: 18, weight: .bold)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                setAdjustButton(systemName: "plus", label: "Increase reps") {
                    adjustReps(by: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var completeButton: some View {
        VStack(spacing: 6) {
            if usesDetailedLayout { Text(set.isCompleted ? "Saved" : "Log")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel)) }

            Button(action: toggleCompletion) {
                Group {
                    if set.isCompleted {
                        Label("Edit", systemImage: "pencil")
                            .appTextRole(.caption).foregroundStyle(AppPalette.text)
                    } else {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: completionIcon)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .font(.system(size: 34, weight: .semibold))
                            if isPersonalBest {
                                Image(systemName: "star.fill")
                                    .foregroundColor(AppPalette.achievement)
                                    .font(.caption2)
                                    .offset(x: 3, y: -4)
                                    .accessibilityLabel("Above previous set")
                            }
                        }
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set_complete_\(set.id)")
            .accessibilityLabel(set.isCompleted ? "Reopen \(setLabel)" : "Complete \(setLabel)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
            .accessibilityHint(set.isCompleted ? "Reopens this set so its recorded weight and reps can be edited." : "Saves this set and moves to the next one.")
        }
        .frame(width: 48)
    }

    private var setTypeMenu: some View {
        Menu {
            Picker("Set type", selection: setTypeBinding) {
                Label("Working set", systemImage: "circle.fill").tag(SetType.normal)
                Label("Warm-up", systemImage: "flame").tag(SetType.warmup)
                Label("Drop set", systemImage: "arrow.down.circle").tag(SetType.drop)
                Label("To failure", systemImage: "bolt.circle").tag(SetType.failure)
            }
        } label: {
            HStack(spacing: 3) {
                Text(usesDetailedLayout ? setLabel : set.resolvedSetType == .normal ? "\(setIndex)" : String(setLabel.prefix(1)))
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(setTypeColor)
                Image(systemName: "chevron.down")
                    .appFont(size: 9, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .accessibilityLabel("Set type: \(setLabel)")
        .accessibilityHint("Change between working, warm-up, drop, or failure set.")
        .accessibilityIdentifier("set_type_\(set.id)")
        .disabled(set.isCompleted)
        .frame(minHeight: 44)
    }

    private var effortMenuChip: some View {
        Menu {
            Button("Not logged") { updateEffort(nil) }
            ForEach(effortOptions, id: \.self) { value in
                Button(formatEffort(value)) {
                    updateEffort(SetEffort(scale: effortScale, value: value))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(effortScale == .rir ? "RIR" : "RPE")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Text(effortDisplayValue.map(formatEffort) ?? "–")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(effortDisplayValue == nil ? Color(UIColor.tertiaryLabel) : .textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(AppPalette.control, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effortScale == .rir ? "Reps in reserve" : "Rate of perceived exertion")
        .accessibilityValue(effortDisplayValue.map(formatEffort) ?? "Not logged")
        .accessibilityIdentifier("set_effort_\(set.id)")
        .disabled(set.isCompleted)
    }

    private func updateEffort(_ effort: SetEffort?) {
        guard !set.isCompleted else { return }
        set.effort = effort
    }

    private func setAdjustButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 44, height: 44)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .disabled(set.isCompleted)
    }

    private func fillEmptyFieldsFromHistory() {
        guard !set.isCompleted, let previousSet else { return }
        if StrengthSetEntryRules.canSeedFromHistory(input: weightInput,
                wasEdited: editedFields.contains(.weight), isFocused: focusedField == .weight),
           previousSet.weight.isFinite, previousSet.weight >= 0 {
            set.weight = previousSet.weight
            weightInput = weightText(previousSet.weight)
        }
        if StrengthSetEntryRules.canSeedFromHistory(input: repsInput,
                wasEdited: editedFields.contains(.reps), isFocused: focusedField == .reps), previousSet.reps > 0 {
            set.reps = previousSet.reps
            repsInput = "\(previousSet.reps)"
        }
    }

    private func fillFromPrevious() {
        guard !set.isCompleted, let prev = previousSet else { return }
        editedFields.formUnion([.weight, .reps])
        set.weight = prev.weight
        set.reps = prev.reps
        self.weightInput = weightText(prev.weight)
        self.repsInput = "\(prev.reps)"
        HapticManager.instance.feedback(.light)
    }

    private func normalizedTargetText() -> String {
        targetText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func targetTextBeforeProgression() -> String {
        let normalized = normalizedTargetText()
        guard let range = normalized.range(of: "Progression:", options: .caseInsensitive) else {
            return normalized
        }

        return normalized[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func weightText(_ pounds: Double) -> String {
        unit.displayWeight(pounds).formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }

    private func storedWeight(from input: String) -> Double? {
        // Displaying kg must never round and rewrite the original pounds-based history.
        if input == weightText(set.weight) { return set.weight }
        return StrengthSetEntryRules.weight(from: input).map { unit.storedWeight($0) }
    }

    private func adjustWeight(by amount: Double) {
        guard !set.isCompleted else { return }
        guard let currentWeight = storedWeight(from: weightInput.isEmpty ? "0" : weightInput) else { return }
        let next: Double?
        if let equipment {
            next = amount > 0 ? equipment.next(after: currentWeight) : equipment.previous(before: currentWeight)
        } else { next = max(0, currentWeight + amount) }
        guard let next else { return }
        editedFields.insert(.weight)
        set.weight = next
        weightInput = weightText(next)
        HapticManager.instance.feedback(.light)
    }

    private func adjustReps(by amount: Int) {
        guard !set.isCompleted else { return }
        editedFields.insert(.reps)
        let currentReps = Int(repsInput) ?? 0
        let newReps = max(0, currentReps + amount)
        self.repsInput = "\(newReps)"
        HapticManager.instance.feedback(.light)
    }

    private func toggleCompletion() {
        if !set.isCompleted {
            let reviewed: StrengthSetEntryRules.ReviewedEntry
            do {
                reviewed = try StrengthSetEntryRules.review(
                    weightInput: weightInput, repsInput: repsInput,
                    fallbackWeight: editedFields.contains(.weight) || (requiresManualLoad && set.weight == 0) ? nil : weightText(set.weight),
                    fallbackReps: editedFields.contains(.reps) ? nil
                        : set.reps > 0 ? set.reps : inferredReps(from: set.target))
            } catch {
                let field: StrengthSetInput.Field = (error as? StrengthSetEntryRules.EntryError) == .reps ? .reps : .weight
                entryError = field == .weight ? "Enter a valid load. Use 0 for no added weight." : "Enter at least one rep."
                focusedField = field
                inputFocus?.wrappedValue = StrengthSetInput(setID: set.id, field: field)
                return
            }
            // Reuse the exact stored quantity when its formatted display was not
            // changed, avoiding a pounds → rounded kg → pounds rewrite.
            guard let weight = storedWeight(from: reviewed.weightText) else { return }
            set.weight = weight
            set.reps = reviewed.reps
            weightInput = reviewed.weightText
            repsInput = reviewed.repsText
            entryError = nil
        }

        inputFocus?.wrappedValue = nil; focusedField = nil
        set.isCompleted.toggle()
        if set.isCompleted {
            showingDetails = false
            HapticManager.instance.feedback(.medium)
            onComplete()
        } else { onReopen?() }
    }

    private func inferredReps(from target: String?) -> Int? {
        guard let target else { return nil }
        return ProgressionRules.repRange(target)?.lowerBound
    }

    private func checkIfPersonalBest(newWeight: Double, newRps: Int) {
        guard let previous = previousSet, newRps > 0, newWeight > 0 else {
            isPersonalBest = false
            return
        }

        if equipment?.loadingMeaning == .assistance {
            isPersonalBest = newWeight < previous.weight && newRps >= previous.reps
        } else if equipment?.loadingMeaning == .bodyweightOnly { isPersonalBest = false } else if newWeight > previous.weight && newRps >= previous.reps {
            isPersonalBest = true
        } else if newWeight == previous.weight && newRps > previous.reps {
            isPersonalBest = true
        } else {
            isPersonalBest = false
        }
    }
}

struct CardioSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var onCompletedSet: ((String) -> Void)?

    @State private var distanceInput: String
    @State private var timeInput: String
    @State private var entryError: String?
    @AppStorage("useMetricBodyUnits") private var useMetric = BodyUnits.prefersMetric()
    @State private var canonicalDistanceText: String
    @State private var canonicalDistanceMiles: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(set: Binding<ExerciseSet>, setIndex: Int, onCompletedSet: ((String) -> Void)? = nil) {
        self.onCompletedSet = onCompletedSet
        self._set = set
        self.setIndex = setIndex
        let displayed = set.wrappedValue.distance * (BodyUnits.prefersMetric() ? 1.609344 : 1)
        let distanceText = displayed > 0 ? displayed.formatted(.number.precision(.fractionLength(0...6))) : ""
        self._distanceInput = State(initialValue: distanceText)
        self._canonicalDistanceText = State(initialValue: distanceText)
        self._canonicalDistanceMiles = State(initialValue: set.wrappedValue.distance)
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? String(format: "%g", Double(set.wrappedValue.durationInSeconds) / 60) : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            entryControls
            WorkoutIntervalControls(set: $set, isHold: false) { onCompletedSet?(set.id) }
            if let entryError {
                Text(entryError).appTextRole(.caption).foregroundStyle(AppPalette.caution)
            }
        }
        .onChange(of: useMetric) { _, value in
            let text = (set.distance * (value ? 1.609344 : 1)).formatted(.number.precision(.fractionLength(0...6)))
            canonicalDistanceMiles = set.distance; canonicalDistanceText = text; distanceInput = text
        }
        .onChange(of: set.durationInSeconds) { _, value in
            if set.intervalTimer?.completedAt != nil { timeInput = String(format: "%g", Double(value) / 60) }
        }
    }

    private var entryControls: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
            Text(dynamicTypeSize.isAccessibilitySize ? "Set \(setIndex)" : "\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.prescription?.summary ?? set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(useMetric ? "km" : "miles", text: $distanceInput)
                .accessibilityLabel("Distance in \(useMetric ? "kilometers" : "miles"), set \(setIndex)")
                .keyboardType(.decimalPad)
                .disabled(set.isCompleted || set.intervalTimer?.runningSince != nil)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 44)
                .onChange(of: distanceInput) {
                    if distanceInput == canonicalDistanceText { set.distance = canonicalDistanceMiles } else {
                        set.distance = (StrengthSetEntryRules.weight(from: distanceInput) ?? 0) / (useMetric ? 1.609344 : 1)
                        canonicalDistanceMiles = set.distance; canonicalDistanceText = distanceInput
                    }
                    entryError = nil
                }

            TextField("min", text: $timeInput)
                .accessibilityLabel("Duration in minutes, set \(setIndex)")
                .keyboardType(.decimalPad)
                .disabled(set.isCompleted || set.intervalTimer?.runningSince != nil)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 44)
                .onChange(of: timeInput) {
                    set.durationInSeconds = WorkoutDurationEntryRules.seconds(fromMinutes: timeInput) ?? 0
                    entryError = nil
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44)
            .accessibilityLabel("Complete set \(setIndex)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, timeInput.trimmed.isEmpty, let inferredSeconds = WorkoutDurationEntryRules.targetSeconds(set.target) {
            set.durationInSeconds = inferredSeconds
            timeInput = String(format: "%g", Double(inferredSeconds) / 60)
        }

        guard set.isCompleted || (set.durationInSeconds > 0 && (distanceInput.trimmed.isEmpty || StrengthSetEntryRules.weight(from: distanceInput) != nil)) else {
            entryError = "Enter a duration above zero and a valid distance, or leave distance blank."
            return
        }
        entryError = nil
        if set.isCompleted { set.intervalTimer = nil }
        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
            onCompletedSet?(set.id)
        }
    }

}

struct FlexibilitySetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var onCompletedSet: ((String) -> Void)?

    @State private var timeInput: String
    @State private var entryError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(set: Binding<ExerciseSet>, setIndex: Int, onCompletedSet: ((String) -> Void)? = nil) {
        self.onCompletedSet = onCompletedSet
        self._set = set
        self.setIndex = setIndex
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? "\(set.wrappedValue.durationInSeconds)" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            entryControls
            WorkoutIntervalControls(set: $set, isHold: true) { onCompletedSet?(set.id) }
            if let entryError {
                Text(entryError).appTextRole(.caption).foregroundStyle(AppPalette.caution)
            }
        }
        .onChange(of: set.durationInSeconds) { _, value in
            if set.intervalTimer?.completedAt != nil { timeInput = "\(value)" }
        }
    }

    private var entryControls: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
            Text(dynamicTypeSize.isAccessibilitySize ? "Set \(setIndex)" : "\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.prescription?.summary ?? set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("seconds", text: $timeInput)
                .accessibilityLabel("Duration in seconds, set \(setIndex)")
                .keyboardType(.numberPad)
                .disabled(set.isCompleted || set.intervalTimer?.runningSince != nil)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: 44)
                .onChange(of: timeInput) {
                    set.durationInSeconds = StrengthSetEntryRules.reps(from: timeInput) ?? 0
                    entryError = nil
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 44)
            .accessibilityLabel("Complete set \(setIndex)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, timeInput.trimmed.isEmpty, let inferredSeconds = WorkoutDurationEntryRules.targetSeconds(set.target, bareNumberIsSeconds: true) {
            set.durationInSeconds = inferredSeconds
            timeInput = "\(inferredSeconds)"
        }

        guard set.isCompleted || set.durationInSeconds > 0 else {
            entryError = "Enter a duration above zero to complete this set."
            return
        }
        entryError = nil
        if set.isCompleted { set.intervalTimer = nil }
        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
            onCompletedSet?(set.id)
        }
    }

}
