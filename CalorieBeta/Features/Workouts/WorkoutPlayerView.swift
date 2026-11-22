import MyFitPlateCore

import SwiftUI
import ActivityKit

/// The cover receives the tapped routine and its origin together, including the
/// exact occurrence when a routine appears several times in the same program.
struct WorkoutPlayerLaunch: Identifiable {
    let id = UUID()
    let routine: WorkoutRoutine
    let programContext: WorkoutProgramSessionContext?

    init(standalone routine: WorkoutRoutine) {
        self.routine = routine
        programContext = nil
    }

    init(resuming draft: WorkoutSessionDraft) {
        routine = draft.routine
        programContext = draft.programContext
    }

    init?(routine: WorkoutRoutine, program: WorkoutProgram, slot: Int) {
        guard let context = WorkoutRules.sessionContext(for: program, routineID: routine.id, slotIndex: slot) else {
            return nil
        }
        self.routine = routine
        programContext = context
    }
}

struct WorkoutPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var trainingFuelPlanStore: TrainingFuelPlanStore

    @State private var routine: WorkoutRoutine
    @StateObject private var restTimer = RestTimer()
    @StateObject private var totalWorkoutTimer: TotalWorkoutTimer

    // Note Editor State
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    @State private var isNotePinned = false
    @State private var exerciseForNote: Binding<RoutineExercise>?

    // Sheet State
    @State private var showingHistoryFor: RoutineExercise?
    @State private var showingPlateCalculator = false
    @State private var showingSessionTools = false
    @State private var showingAdaptation = false
    @State private var adaptationMode = WorkoutSessionAdaptationView.Mode.shorten
    @State private var adaptationSourceID: String?

    @State private var previousPerformance: [String: CompletedExercise] = [:]
    @State private var progressionHistory: [WorkoutSessionLog] = []
    @State private var historyLoaded = false
    @State private var historyLoading = false
    @State private var historyLoadFailed = false

    // Auto-Rest Preference
    @AppStorage("isAutoRestTimerEnabled") private var isAutoRestTimerEnabled = false

    // Analytics / Summary Sheet
    @State private var completedSessionLog: WorkoutSessionLog?
    @State private var showingFinishConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var hasNotifiedWorkoutComplete = false
    @State private var setInputFocus: StrengthSetInput?
    @State private var setInputCommand: StrengthSetCommand?
    @State private var selectedSetID: String?
    @State private var scrollTarget: String?
    @State private var visibleExerciseID: String?
    @State private var currentSetScrollRequest = UUID()
    @State private var lastCompletedSetID: String?
    @State private var showingAddExercise = false
    @State private var browsingSwapFor: RoutineExercise?
    @State private var draft: WorkoutSessionDraft
    @State private var didStartSession = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var hasLeftSession = false
    @State private var showingExistingSession = false
    @State private var showingLegacyProgramReview = false
    @State private var pendingLegacyProgramChoice: LegacyProgramChoice?
    @State private var shouldApplyLegacyProgramChoice = false
    @State private var savedSessionNeedsCompletion = false
    @State private var resumedSession = false
    private let ownerID: String?
    private let freezesReviewedSetup: Bool
    private let draftStore = WorkoutDraftStore()

    var onWorkoutComplete: () -> Void

    private struct LegacyProgramChoice: Identifiable {
        let program: WorkoutProgram
        let context: WorkoutProgramSessionContext
        var id: String { "\(context.programID)|\(context.slotIndex)" }
        var title: String {
            let position = program.weekAndDay(forSlot: context.slotIndex)
            return "Count toward \(program.name) · Week \(position.week), Day \(position.day)"
        }
    }

    private var legacyProgramChoices: [LegacyProgramChoice] {
        guard let ownerID else { return [] }
        var seen = Set<String>()
        let programs = [workoutService.activeProgram].compactMap { $0 } + workoutService.userPrograms
        return programs.compactMap { program in
            guard let id = program.id, seen.insert(id).inserted,
                  let context = WorkoutRules.legacyProgramContextCandidate(for: draft, in: program, userID: ownerID) else { return nil }
            return LegacyProgramChoice(program: program, context: context)
        }
    }

    private var legacyProgramReviewMessage: String {
        if draft.completion != nil {
            return "This older workout already has a saved completion without a program link. Finish saving it as standalone; your plan position stays the same."
        }
        if !legacyProgramChoices.isEmpty {
            return "Choose whether to count this older saved workout toward a current plan session or save it as standalone. Your completed sets stay the same."
        }
        if !workoutService.hasLoadedPrograms || workoutService.preferredProgramUnavailable {
            return "Saved plans are still unavailable. Refresh them and finish again, or save this older workout as standalone without advancing a plan."
        }
        return "No current plan session matches this older saved workout. Save it as standalone to keep your history and leave plan progress unchanged."
    }

    private var totalSetCount: Int {
        routine.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private var completedSetCount: Int {
        routine.exercises.reduce(0) { partial, exercise in
            partial + exercise.sets.filter(\.isCompleted).count
        }
    }

    private var remainingSetCount: Int {
        max(totalSetCount - completedSetCount, 0)
    }

    private var workoutProgress: Double {
        guard totalSetCount > 0 else { return 0 }
        return min(Double(completedSetCount) / Double(totalSetCount), 1)
    }

    private var supersetPositions: [SupersetRules.Position] {
        SupersetRules.positions(for: routine.exercises)
    }

    /// Link this exercise with the next as a superset (or unlink if already paired).
    private func toggleSupersetWithNext(at index: Int) {
        guard index < routine.exercises.count - 1 else { return }
        // A quick legacy grouping action replaces any authored round touching these
        // partners, rather than leaving a hidden ordered group active behind the menu.
        let touched = Set([routine.exercises[index].groupPlan?.id, routine.exercises[index + 1].groupPlan?.id].compactMap { $0 })
        for member in routine.exercises.indices where routine.exercises[member].groupPlan.map({ touched.contains($0.id) }) == true {
            routine.exercises[member].groupPlan = nil
        }
        let current = routine.exercises[index].supersetGroupID
        let next = routine.exercises[index + 1].supersetGroupID
        if let current, current == next {
            routine.exercises[index + 1].supersetGroupID = nil
            // If that leaves the group with a single member, dissolve it entirely.
            if routine.exercises.filter({ $0.supersetGroupID == current }).count < 2 {
                for i in routine.exercises.indices where routine.exercises[i].supersetGroupID == current {
                    routine.exercises[i].supersetGroupID = nil
                }
            }
        } else {
            let groupID = current ?? UUID().uuidString
            routine.exercises[index].supersetGroupID = groupID
            routine.exercises[index + 1].supersetGroupID = groupID
        }
    }

    private var completedExerciseCount: Int {
        routine.exercises.filter { exercise in
            !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
        }.count
    }

    private var navigationExercises: [RoutineExercise] { draft.navigationExercises(routine.exercises) }

    private var parkedExercises: [RoutineExercise] {
        routine.exercises.filter { draft.parkedExerciseIDs?.contains($0.id) == true && $0.sets.contains { !$0.isCompleted } }
    }

    private var activeSetID: String? {
        let available = navigationExercises
        if let selectedSetID, available.contains(where: { $0.sets.contains { $0.id == selectedSetID && !$0.isCompleted && $0.isDeferred != true } }) {
            return selectedSetID
        }
        return WorkoutSetNavigation.firstUnfinished(in: available)?.setID
    }

    private var plateCalculatorContext: (target: Double?, equipment: StrengthEquipment?)? {
        guard let setID = setInputFocus?.setID ?? activeSetID,
              let exercise = routine.exercises.first(where: { $0.type == .strength && $0.sets.contains { $0.id == setID } }),
              let set = exercise.sets.first(where: { $0.id == setID }) else { return nil }
        return (set.weight.isFinite && set.weight > 0 ? set.weight : nil, exercise.loadEquipment)
    }

    private var currentExerciseName: String {
        if let activeSetID, let exercise = routine.exercises.first(where: { $0.sets.contains { $0.id == activeSetID } }) { return exercise.name }
        if !parkedExercises.isEmpty { return "Parked exercises remaining" }
        return remainingSetCount > 0 ? "Deferred sets remaining" : "Ready to finish"
    }

    private var focusedInputContext: String? {
        guard let input = setInputFocus,
              let exercise = routine.exercises.first(where: { $0.sets.contains { $0.id == input.setID } }),
              let index = exercise.sets.firstIndex(where: { $0.id == input.setID }) else { return nil }
        let field = input.field == .weight ? "Load in \(exercise.loadEquipment?.unit.rawValue ?? "lb")" : "Reps"
        return "\(exercise.name) · Set \(index + 1) · \(field)"
    }

    private var canMoveInputBackward: Bool {
        guard let input = setInputFocus else { return false }
        return input.field == .reps || WorkoutSetNavigation.previousInput(before: input.setID, in: navigationExercises) != nil
    }

    private var restExerciseName: String? {
        guard let exerciseID = restTimer.state?.exerciseID else { return nil }
        return routine.exercises.first(where: { $0.id == exerciseID })?.name
    }

    init(routine: WorkoutRoutine, programContext: WorkoutProgramSessionContext? = nil, initialSessionEdit: WorkoutSessionEditReceipt? = nil, freezesReviewedSetup: Bool = false, onWorkoutComplete: @escaping () -> Void) {
        // Guarantee a fresh workout by deep copying the template and resetting all completed states.
        let activeRoutine = routine.deepCopy() ?? routine

        var acceptedInitialEdit: WorkoutSessionEditReceipt?
        if let initialSessionEdit, let adjusted = try? WorkoutSessionAdaptationRules.applying(initialSessionEdit, to: activeRoutine.exercises) {
            activeRoutine.exercises = adjusted; acceptedInitialEdit = initialSessionEdit
        }
        for i in 0..<activeRoutine.exercises.count {
            for j in 0..<activeRoutine.exercises[i].sets.count {
                activeRoutine.exercises[i].sets[j].isCompleted = false
                if let target = activeRoutine.exercises[i].sets[j].prescription {
                    activeRoutine.exercises[i].sets[j] = target.seedingEmptyValues(
                        in: activeRoutine.exercises[i].sets[j], type: activeRoutine.exercises[i].type)
                }
                activeRoutine.exercises[i].sets[j].intervalTimer = nil
                activeRoutine.exercises[i].sets[j].isDeferred = nil
                // Note: We don't reset weight/reps here because the user's template might have custom target weights saved,
                // but since this is a deep copy, mutations during the workout won't affect the master template.
            }
        }

        _routine = State(initialValue: activeRoutine)
        var initialDraft = WorkoutSessionDraft(routine: activeRoutine, programContext: programContext)
        if let acceptedInitialEdit { initialDraft.sessionEdits = [acceptedInitialEdit] }
        _draft = State(initialValue: initialDraft)
        ownerID = DIContainer.shared.authService.currentUserID
        self.freezesReviewedSetup = freezesReviewedSetup
        _totalWorkoutTimer = StateObject(wrappedValue: TotalWorkoutTimer(routineId: activeRoutine.id))
        self.onWorkoutComplete = onWorkoutComplete
    }

    var body: some View {
        NavigationStack {
            sessionEditors
                .confirmationDialog(
                    completedSetCount == 0 ? "Close without logging this workout?" : "Finish with \(remainingSetCount) sets left?",
                    isPresented: $showingFinishConfirmation,
                    titleVisibility: .visible
                ) {
                    if let exercise = parkedExercises.first {
                        Button("Return to " + exercise.name) { setExerciseParked(false, id: exercise.id) }
                    }
                    Button(completedSetCount == 0 ? "Close Without Logging" : "Finish Anyway", role: .destructive) {
                        completeWorkout()
                    }
                    Button("Keep Training", role: .cancel) {}
                } message: {
                    if !parkedExercises.isEmpty {
                        Text("Parked for later: " + parkedExercises.map(\.name).joined(separator: ", ") + (completedSetCount == 0 ? ". Closing now logs no sets." : ". Finishing now saves only completed sets."))
                    } else if completedSetCount == 0 {
                        Text("No completed sets will be saved and your program progress will not advance.")
                    } else {
                        Text("Completed sets will be saved, but unfinished sets will be skipped.")
                    }
                }
                .confirmationDialog(
                    "Leave this workout?",
                    isPresented: $showingDiscardConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Save & Leave") {
                        guard persistDraft() else { return }
                        totalWorkoutTimer.pause()
                        hasLeftSession = true
                        dismiss()
                    }
                    if draft.completion == nil {
                        Button("Discard Workout", role: .destructive) {
                            closeWorkout()
                        }
                    }
                    Button("Keep Training", role: .cancel) {}
                } message: {
                    Text("Save your sets on this device and resume from Train.")
                }
                .sheet(item: $completedSessionLog, onDismiss: { dismiss() }) { log in
                    WorkoutCompleteAnalyticsView(log: log, isFreshCompletion: true)
                }
        }
    }

    private var sessionEditors: some View {
        sessionScreen
            .confirmationDialog("You have an unfinished workout", isPresented: $showingExistingSession, titleVisibility: .visible) {
                Button("Keep Saved Workout", role: .cancel) { hasLeftSession = true; dismiss() }
                if !savedSessionNeedsCompletion {
                    Button("Discard Saved Workout & Start New", role: .destructive) { beginFreshSession() }
                }
            } message: {
                Text(savedSessionNeedsCompletion
                     ? "Finish saving your previous workout from Train before starting another session."
                     : "Resume it from Train, or discard it to start this routine.")
            }
            .sheet(isPresented: $showingLegacyProgramReview, onDismiss: applyPendingLegacyProgramChoice) {
                legacyProgramReviewSheet
            }
            .sheet(isPresented: $showingNoteEditor) {
                if let exerciseBinding = exerciseForNote, let ownerID {
                    ExerciseNoteView(exercise: exerciseBinding.wrappedValue, routineID: routine.id, ownerID: ownerID) { snapshot in
                        guard DIContainer.shared.authService.currentUserID == ownerID,
                              let index = routine.exercises.firstIndex(where: { $0.id == exerciseBinding.wrappedValue.id }) else { throw WorkoutBlockError.changed }
                        var exercises = routine.exercises; exercises[index].cueSnapshot = snapshot
                        try saveReviewedExercises(exercises, receipt: draft.sessionToolsReceipt)
                    }
                }
            }
            .sheet(isPresented: $showingAdaptation) {
                WorkoutSessionAdaptationView(exercises: routine.exercises, history: progressionHistory,
                    initialExerciseID: adaptationSourceID, initialMode: adaptationMode, onApply: applySessionEdit)
            }
            .sheet(item: $browsingSwapFor) { source in
                ExercisePickerView(isReplacing: true) { selection in
                    swapExercise(source.id, to: selection)
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerView { draft in
                    addExercise(draft)
                    showingAddExercise = false
                }
            }
            .sheet(item: $showingHistoryFor) { exercise in
                ExerciseHistoryView(exercise: exercise, routineID: routine.id)
            }
            .sheet(isPresented: $showingPlateCalculator) {
                PlateCalculatorView(initialTargetWeight: plateCalculatorContext?.target,
                                    equipment: plateCalculatorContext?.equipment)
            }
            .sheet(isPresented: $showingSessionTools, onDismiss: refreshPreviousReferences) {
                StrengthSessionToolsView(routineID: routine.id, exercises: routine.exercises,
                    history: progressionHistory, historyAvailable: historyLoaded && !historyLoadFailed,
                    onApply: applySessionTools)
            }
    }

    private var sessionScreen: some View {
        ZStack {
            ScrollViewReader { proxy in
                workoutLayout(proxy)
            }
        }
        .environment(\.workoutSetFocus, $setInputFocus)
        .environment(\.workoutSetCommand, setInputCommand)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_player")
        .navigationBarHidden(!dynamicTypeSize.isAccessibilitySize)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: requestCloseWorkout) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close workout")
                }
                ToolbarItem(placement: .principal) {
                    Text(totalWorkoutTimer.formattedTime()).monospacedDigit()
                        .accessibilityLabel("Elapsed \(totalWorkoutTimer.formattedTime())")
                }
            }
        }
        .onAppear(perform: startSession)
        .onDisappear {
            if DIContainer.shared.authService.currentUserID != ownerID {
                totalWorkoutTimer.pause()
                restTimer.stop()
                LiveActivityManager.shared.endActivity(sessionID: draft.sessionID)
            } else {
                if !hasLeftSession { persistDraft(); totalWorkoutTimer.pause() }
                restTimer.suspendUpdates()
            }
        }
        .interactiveDismissDisabled(true)
        .onChange(of: restTimer.state) { _, _ in persistDraft() }
        .onChange(of: setInputFocus) { _, input in
            if let input { selectedSetID = input.setID }
        }
        .onReceive(routine.$exercises.dropFirst()) { exercises in
            persistDraft(exercises: exercises)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { restTimer.refresh() } else { persistDraft() }
        }
        .overlay {
            if isSaving {
                ProgressView("Saving workout…")
                    .padding(AppSpacing.section)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            }
        }
    }

    private func workoutLayout(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                sessionHeader(proxy)
                    .padding(.horizontal)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
            }
            if restTimer.state != nil || restTimer.completion != nil {
                WorkoutRestControlsView(timer: restTimer, context: restExerciseName,
                                        showsContextCaption: setInputFocus == nil)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.compact)
            }

            exerciseList(proxy)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .keyboard) { setKeyboardControls }
                }
                .onChange(of: scrollTarget) { _, target in
                    if let input = setInputFocus {
                        proxy.scrollTo(inputScrollAnchor(input), anchor: .center)
                    } else if let target {
                        withAnimation(AppMotion.standard) { proxy.scrollTo(target, anchor: .center) }
                    }
                }
                .onChange(of: currentSetScrollRequest) { _, _ in
                    if let activeSetID {
                        if reduceMotion { proxy.scrollTo(activeSetID, anchor: .center) } else {
                            withAnimation(AppMotion.standard) { proxy.scrollTo(activeSetID, anchor: .center) }
                        }
                    }
                }
                .onChange(of: setInputFocus) { _, input in
                    if let input { proxy.scrollTo(inputScrollAnchor(input), anchor: .center) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    // The keyboard changes the usable viewport after focus moves.
                    // Center the numeric field, not its possibly expanded inspector.
                if let input = setInputFocus { proxy.scrollTo(inputScrollAnchor(input), anchor: .center) }
            }
            if let focusedInputContext {
                Text(focusedInputContext)
                    .appFont(size: 11, weight: .semibold).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(focusedInputContext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.compact)
                    .background(AppPalette.canvas)
                    .accessibilityIdentifier("workout_input_context")
            }
            if let lastCompletedSetID,
               routine.exercises.contains(where: { $0.sets.contains { $0.id == lastCompletedSetID && $0.isCompleted } }) {
                HStack {
                    Text("Set completed").appFont(size: 13).foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Undo set", action: undoLastSet)
                        .appFont(size: 17, weight: .semibold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("workout_undo_set")
                }.padding(.horizontal, AppSpacing.screenHorizontal)
            }
            if setInputFocus == nil {
                if activeSetID == nil, let exercise = parkedExercises.first {
                    Button("Return to " + exercise.name) { setExerciseParked(false, id: exercise.id) }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("workout_return_parked")
                }
                WorkoutSessionControlBar(
                    completedSets: completedSetCount,
                    totalSets: totalSetCount,
                    remainingSets: remainingSetCount,
                    isAutoRestEnabled: $isAutoRestTimerEnabled,
                    canReturnToSet: activeSetID != nil,
                    onCurrentSet: {
                        finishInput()
                        currentSetScrollRequest = UUID()
                    },
                    onPlateCalculator: {
                        showingPlateCalculator = true
                    },
                    onFinish: requestCompleteWorkout
                )
            }
        }
        .disabled(isSaving || !didStartSession)
        .onAppear(perform: loadPreviousPerformance)
    }

    private var setKeyboardControls: some View {
        HStack(spacing: 0) {
            if let input = setInputFocus {
                Button { moveInputFocusBackward(from: input) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                    .tint(AppPalette.text)
                    .disabled(!canMoveInputBackward)
                    .accessibilityLabel("Previous field")
                    .accessibilityHint("Moves to earlier input without logging a set.")
                    .accessibilityIdentifier("workout_input_previous")
                Button { sendInputCommand(increase: false, input: input) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .tint(AppPalette.text)
                    .accessibilityLabel(input.field == .weight ? "Decrease weight" : "Decrease reps")
                    .accessibilityIdentifier("workout_input_decrease")
                Button { sendInputCommand(increase: true, input: input) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .tint(AppPalette.text)
                    .accessibilityLabel(input.field == .weight ? "Increase weight" : "Increase reps")
                    .accessibilityIdentifier("workout_input_increase")
                Button { moveInputFocus(from: input) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                    .tint(AppPalette.text)
                    .accessibilityLabel("Next field")
                    .accessibilityHint("Moves input without logging a set.")
                    .accessibilityIdentifier("workout_input_next")
                Spacer()
                Button { setInputCommand = StrengthSetCommand(setID: input.setID, action: .complete) } label: {
                    Image(systemName: "checkmark.circle").foregroundStyle(AppPalette.brandText)
                        .frame(width: 44, height: 44)
                }
                    .tint(AppPalette.brand)
                    .accessibilityLabel("Log set")
                    .accessibilityHint("Logs the entered load and reps. Next and Previous only move input.")
                    .accessibilityIdentifier("workout_input_complete")
            } else { Spacer() }
            Button(action: finishInput) {
                Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
            }
                .tint(AppPalette.text)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("workout_input_done")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func exerciseList(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if dynamicTypeSize.isAccessibilitySize { sessionHeader(proxy) }
                if resumedSession {
                    Label("Resumed your saved workout", systemImage: "arrow.counterclockwise")
                        .appTextRole(.secondary)
                        .accessibilityIdentifier("workout_resumed")
                }
                if let saveMessage {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(saveMessage).appTextRole(.secondary)
                        if draft.completion != nil {
                            Button("Retry saving", action: completeWorkout)
                                .buttonStyle(AppActionButtonStyle(.secondary))
                        }
                    }
                    .appSurface(.quiet)
                    .accessibilityIdentifier("workout_save_feedback")
                }
                WorkoutSyncNotice(service: workoutService)
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    sessionUtilities
                    if let receipt = draft.sessionToolsReceipt {
                        Text(receipt.title).appTextRole(.secondary).foregroundStyle(.secondary)
                        Button("Undo session targets", action: undoSessionTools)
                            .frame(minHeight: 44).disabled(draft.completion != nil)
                            .accessibilityIdentifier("workout_session_tools_undo")
                    }
                }
                if historyLoadFailed {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Previous workouts couldn’t load. You can still log your sets.")
                            .appTextRole(.secondary)
                        Button(historyLoading ? "Loading…" : "Retry previous workouts", action: loadPreviousPerformance)
                            .disabled(historyLoading)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("workout_history_retry")
                    }
                    .appSurface(.quiet)
                }
                if let receipt = draft.sessionEdits?.last {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(receipt.title).appTextRole(.control)
                        Text(receipt.explanation).appTextRole(.caption).foregroundStyle(.secondary)
                        Button(receipt.kind == .substitute ? "Undo swap" : "Undo reviewed session change") {
                            do {
                                let restored = try WorkoutSessionAdaptationRules.undo(receipt, in: routine.exercises)
                                try saveReviewedExercises(restored, receipt: draft.sessionToolsReceipt,
                                    edits: Array((draft.sessionEdits ?? []).dropLast()))
                                selectedSetID = WorkoutSetNavigation.firstUnfinished(in: navigationExercises)?.setID; persistDraft()
                            } catch { saveMessage = "This work changed after the review. Its logged sets stay intact; adjust the remaining work manually." }
                        }.frame(minHeight: 44)
                    }.appSurface(.quiet)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseCard(at: index, exercise: exercise)
                            .id(exercise.id)
                    }
                }
                .scrollTargetLayout()
                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.completion != nil)
            }
            .padding()
        }
        .scrollPosition(id: $visibleExerciseID, anchor: .top)
    }

    private func exerciseCard(at index: Int, exercise: RoutineExercise) -> some View {
        ExerciseCardView(
            exercise: $routine.exercises[index],
            restTimer: restTimer,
            isAutoRestEnabled: $isAutoRestTimerEnabled,
            routineName: routine.name,
            previousPerformance: previousPerformance[exercise.id],
            progressionHistory: progressionHistory,
            onAddNote: {
                self.exerciseForNote = $routine.exercises[index]
                self.noteText = exercise.notes ?? PinnedNotesManager.shared.getPinnedNote(for: exercise.name) ?? ""
                self.isNotePinned = PinnedNotesManager.shared.isNotePinned(for: exercise.name)
                self.showingNoteEditor = true
            },
            onSwap: { swapExercise(exercise.id, to: $0) },
            onBrowseSwaps: { browsingSwapFor = exercise },
            onViewHistory: {
                self.showingHistoryFor = exercise
            },
            onMoveUp: index > 0 ? { moveExercise(from: IndexSet(integer: index), to: index - 1) } : nil,
            onMoveDown: index < routine.exercises.count - 1 ? { moveExercise(from: IndexSet(integer: index), to: index + 2) } : nil,
            onRemove: routine.exercises[index].sets.contains(where: { !$0.isCompleted }) ? { adaptationSourceID = exercise.id; adaptationMode = .remove; showingAdaptation = true } : nil,
            supersetPosition: supersetPositions[index],
            onToggleSupersetWithNext: index < routine.exercises.count - 1 ? { toggleSupersetWithNext(at: index) } : nil,
            routineID: routine.id,
            activeSetID: activeSetID,
            onCompletedSet: didCompleteSet,
            onReopenedSet: didReopenSet,
            onApplyWarmup: applyWarmup,
            restDurationForSet: { WorkoutExerciseGroupRules.restAfterCompleting(setID: $0, in: navigationExercises) },
            onDeferPartnerRound: { deferPartner(exerciseID: exercise.id, restore: false) },
            onRestoreDeferred: { deferPartner(exerciseID: exercise.id, restore: true) },
            isParked: draft.parkedExerciseIDs?.contains(exercise.id) == true,
            onChangeParked: { setExerciseParked($0, id: exercise.id) }
        )
        .disabled(draft.completion != nil)
    }

    private var sessionUtilities: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
            Button {
                finishInput(); showingSessionTools = true
            } label: {
                Label("Gym setup", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Gym setup and session targets")
            .accessibilityIdentifier("workout_session_tools")
            Button {
                finishInput(); adaptationSourceID = nil; adaptationMode = .shorten; showingAdaptation = true
            } label: {
                Label("Adjust session", systemImage: "clock.arrow.2.circlepath")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Review changes to today's time or unfinished work.")
            .accessibilityIdentifier("workout_adapt_remaining")
        }
        .appTextRole(.secondary)
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.text)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .disabled(draft.completion != nil)
    }

    @ViewBuilder
    private func sessionHeader(_ proxy: ScrollViewProxy) -> some View {
        if setInputFocus != nil && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: AppSpacing.compact) {
                Text(routine.name)
                    .appFont(size: 13, weight: .semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("workout_routine_title")
                Text(totalWorkoutTimer.formattedTime())
                    .appFont(size: 13, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Elapsed \(totalWorkoutTimer.formattedTime())")
                    .accessibilityIdentifier("workout_elapsed_time")
                Button(action: requestCloseWorkout) { Image(systemName: "xmark") }
                    .buttonStyle(AppIconButtonStyle(.plain))
                    .accessibilityLabel("Close workout")
            }
            .appSurface(.quiet, padding: AppSpacing.compact)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout_focused_header")
        } else {
        WorkoutSessionHeaderCard(
            routineName: routine.name,
            elapsedTime: totalWorkoutTimer.formattedTime(),
            restTime: restTimer.timeRemaining > 0 ? restTimer.formattedTime() : nil,
            completedSets: completedSetCount,
            totalSets: totalSetCount,
            completedExercises: completedExerciseCount,
            totalExercises: routine.exercises.count,
            progress: workoutProgress,
            currentExerciseName: currentExerciseName,
            onClose: requestCloseWorkout,
            onStopRest: restTimer.stop,
            onAdjustRest: { restTimer.adjust(by: $0) },
            isCompact: true,
            showsClose: !dynamicTypeSize.isAccessibilitySize,
            showsRestAdjustments: false,
            showsRestStatus: false,
            exercises: routine.exercises,
            parkedExerciseIDs: draft.parkedExerciseIDs ?? [],
            onBrowseExercise: { exerciseID in
                withAnimation(reduceMotion ? nil : AppMotion.standard) {
                    if visibleExerciseID == exerciseID {
                        proxy.scrollTo(exerciseID, anchor: .top)
                    } else {
                        visibleExerciseID = exerciseID
                    }
                }
            }
        )
        }
    }

    private func inputScrollAnchor(_ input: StrengthSetInput) -> String {
        "strength_input_\(input.setID)_\(input.field == .weight ? "weight" : "reps")"
    }

    private func loadPreviousPerformance() {
        guard !historyLoading else { return }
        historyLoading = true
        Task {
            defer { historyLoading = false }
            // One bounded history fetch for the session, shared by every exercise and swap.
            if !historyLoaded {
                let result = await workoutService.fetchRecentSessionLogsResult(sinceDays: 90)
                guard ownerID == DIContainer.shared.authService.currentUserID, !hasLeftSession else { return }
                switch result {
                case .success(let logs):
                    progressionHistory = logs
                    historyLoaded = true
                    historyLoadFailed = false
                case .failure:
                    historyLoadFailed = true
                    return
                }
            }
            for exercise in routine.exercises {
                previousPerformance[exercise.id] = ProgressionRules.history(for: exercise, in: progressionHistory, routineID: routine.id)
                    .first.flatMap { ProgressionRules.performance(for: exercise, in: $0) }
            }
        }
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        routine.exercises.move(fromOffsets: source, toOffset: destination)
    }

    private func removeExercise(at index: Int) {
        guard routine.exercises.indices.contains(index) else { return }
        do {
            let review = try WorkoutSessionAdaptationRules.removingUnfinished(exerciseID: routine.exercises[index].id, from: routine.exercises)
            routine.exercises = try WorkoutSessionAdaptationRules.applying(review, to: routine.exercises)
            draft.sessionEdits = Array(((draft.sessionEdits ?? []) + [review]).suffix(16)); persistDraft()
        } catch { saveMessage = error.localizedDescription }
    }

    private func addExercise(_ draft: ExercisePickerDraft) {
        let defaultSets: Int
        let target: String
        switch draft.type {
        case .strength:    defaultSets = 3; target = "8-12"
        case .cardio:      defaultSets = 1; target = "20 min"
        case .flexibility: defaultSets = 1; target = "30 sec"
        }
        let newExercise = RoutineExercise(
            name: draft.name,
            type: draft.type,
            sets: (0..<defaultSets).map { _ in ExerciseSet(target: target) },
            restTimeInSeconds: 90,
            targetSets: defaultSets,
            targetReps: target
        )
        withAnimation { routine.exercises.append(newExercise) }
        loadPreviousPerformance()
    }

    private func requestCloseWorkout() {
        guard !isSaving else { return }
        showingDiscardConfirmation = true
    }

    private func closeWorkout() {
        if let ownerID {
            do { try draftStore.remove(userID: ownerID) } catch { saveMessage = "Could not discard the saved draft. Try again."; return }
        }
        hasLeftSession = true
        restTimer.stop()
        LiveActivityManager.shared.endActivity(sessionID: draft.sessionID)
        totalWorkoutTimer.stop()
        dismiss()
    }

    private func requestCompleteWorkout() {
        guard completedSetCount >= totalSetCount, completedSetCount > 0 else {
            showingFinishConfirmation = true
            return
        }

        completeWorkout()
    }

    private func completeWorkout() {
        guard !isSaving, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return }
        if draft.needsProgramLinkReview, completedSetCount > 0 {
            shouldApplyLegacyProgramChoice = false
            pendingLegacyProgramChoice = nil
            showingLegacyProgramReview = true
            return
        }
        draft.routine = routine
        draft.selectedSetID = selectedSetID
        draft.elapsed = totalWorkoutTimer.totalTimeElapsed
        guard draft.prepareCompletion(weightPounds: goalSettings.weight) else {
            closeWorkout()
            return
        }
        guard persistDraft(), let log = draft.completion, let exercise = draft.diaryExercise else { return }
        isSaving = true
        saveMessage = nil
        Task { @MainActor in
            let historyAccepted = await workoutService.saveWorkoutSessionLog(log)
            guard historyAccepted, DIContainer.shared.authService.currentUserID == ownerID else {
                isSaving = false
                saveMessage = "Your session is kept on this device. History could not save; try again."
                return
            }
            let diaryAccepted = await dailyLogService.saveWorkoutExercise(for: ownerID, exercise: exercise)
            guard diaryAccepted, DIContainer.shared.authService.currentUserID == ownerID else {
                isSaving = false
                saveMessage = "History is saved. Your diary still needs to save; retry to finish."
                return
            }
            let programAccepted = await workoutService.recordProgramCompletion(log)
            guard programAccepted, DIContainer.shared.authService.currentUserID == ownerID else {
                isSaving = false
                saveMessage = "History and diary are saved. Your plan still needs to update; retry to finish."
                return
            }
            do { try draftStore.remove(userID: ownerID) } catch {
                isSaving = false
                saveMessage = "Your workout is saved. Retry to finish clearing its draft."
                return
            }
            hasLeftSession = true
            restTimer.stop()
            totalWorkoutTimer.stop()
            LiveActivityManager.shared.endActivity(sessionID: draft.sessionID)
            recordCompletion(log, userID: ownerID)
            notifyWorkoutCompleteIfNeeded()
            isSaving = false
            completedSessionLog = log
        }
    }

    private var legacyProgramReviewSheet: some View {
        AppEditorScaffold(
            title: "Finish saved workout",
            subtitle: legacyProgramReviewMessage,
            dismiss: { showingLegacyProgramReview = false }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                ForEach(legacyProgramChoices) { choice in
                    Button {
                        pendingLegacyProgramChoice = choice
                        shouldApplyLegacyProgramChoice = true
                        showingLegacyProgramReview = false
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text("Count toward plan").appTextRole(.control)
                            Text(choice.program.name).appTextRole(.body).lineLimit(nil)
                            let position = choice.program.weekAndDay(forSlot: choice.context.slotIndex)
                            Text("Week \(position.week) · Day \(position.day)").appTextRole(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, AppSpacing.row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityLabel(choice.title)
                    .accessibilityIdentifier("workout_legacy_count_\(choice.context.programID)_\(choice.context.slotIndex)")
                }
                if draft.completion == nil && (!workoutService.hasLoadedPrograms || workoutService.preferredProgramUnavailable) {
                    Button("Refresh Saved Plans") { workoutService.retryPendingSaves() }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                }
            }
        } actions: {
            VStack(spacing: AppSpacing.compact) {
                Button("Save as Standalone") {
                    pendingLegacyProgramChoice = nil
                    shouldApplyLegacyProgramChoice = true
                    showingLegacyProgramReview = false
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("workout_legacy_save_standalone")
                Button("Keep Workout Open") { showingLegacyProgramReview = false }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("workout_legacy_keep_open")
            }
        }
    }

    private func applyPendingLegacyProgramChoice() {
        guard shouldApplyLegacyProgramChoice else { return }
        shouldApplyLegacyProgramChoice = false
        let choice = pendingLegacyProgramChoice
        pendingLegacyProgramChoice = nil
        resolveLegacyProgramLink(choice)
    }

    private func resolveLegacyProgramLink(_ choice: LegacyProgramChoice?) {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID,
              let copy = routine.deepCopy() else { return }
        if let choice {
            let latest = workoutService.userPrograms.first { $0.id == choice.context.programID }
                ?? (workoutService.activeProgram?.id == choice.context.programID ? workoutService.activeProgram : nil)
            guard let latest,
                  WorkoutRules.legacyProgramContextCandidate(for: draft, in: latest, userID: ownerID) == choice.context else {
                saveMessage = "Your plan changed. Finish again to review its current session; your sets are still saved."
                return
            }
        }
        var pending = draft
        pending.routine = copy
        pending.elapsed = totalWorkoutTimer.totalTimeElapsed
        pending.rest = pending.completion == nil ? restTimer.state : nil
        pending.updatedAt = Date()
        do {
            guard let resolved = try draftStore.saveLegacyProgramLinkDecision(in: pending, context: choice?.context, userID: ownerID) else { return }
            draft = resolved
            completeWorkout()
        } catch {
            saveMessage = "Your workout is still here. Its plan choice could not save; finish again to retry."
        }
    }

    private func startSession() {
        guard !didStartSession, let ownerID else { return }
        do {
            if let saved = try draftStore.load(userID: ownerID) {
                guard saved.routine.id == routine.id else {
                    savedSessionNeedsCompletion = saved.completion != nil
                    showingExistingSession = true
                    return
                }
                draft = saved
                routine = saved.routine
                if let id = saved.selectedSetID, routine.exercises.contains(where: { $0.sets.contains { $0.id == id && !$0.isCompleted && $0.isDeferred != true } }) { selectedSetID = id }
                resumedSession = true
                didStartSession = true
                totalWorkoutTimer.resume(elapsed: saved.elapsed)
                if saved.completion != nil { saveMessage = "This workout still needs to finish saving. Retry when ready." }
                LiveActivityManager.shared.startWorkout(routineName: routine.name, sessionID: draft.sessionID,
                                                       workoutStartTime: totalWorkoutTimer.activityStartTime)
                restTimer.restore(saved.completion == nil ? saved.rest : nil, sessionID: draft.sessionID)
                persistDraft()
                return
            }
            beginFreshSession()
        } catch {
            saveMessage = "Your previous workout draft could not be read. It has been kept on this device."
            showingExistingSession = true
        }
    }

    private func setExerciseParked(_ parked: Bool, id: String) {
        guard didStartSession, !hasLeftSession, let ownerID,
              DIContainer.shared.authService.currentUserID == ownerID, let copy = routine.deepCopy() else { return }
        var updated = draft
        updated.routine = copy
        guard updated.setParked(parked, exerciseID: id, currentSetID: activeSetID) else { return }
        updated.rest = restTimer.state
        updated.elapsed = totalWorkoutTimer.totalTimeElapsed
        updated.updatedAt = Date()
        do {
            try draftStore.save(updated, userID: ownerID)
            finishInput()
            draft = updated
            selectedSetID = updated.selectedSetID
            currentSetScrollRequest = UUID()
        } catch {
            saveMessage = "Couldn’t save this exercise change. Try again."
        }
    }

    private func deferPartner(exerciseID: String, restore: Bool) {
        do {
            guard let index = routine.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw WorkoutBlockError.changed }
            var exercises = routine.exercises
            let next: String?
            if restore {
                for set in exercises[index].sets.indices where !exercises[index].sets[set].isCompleted { exercises[index].sets[set].isDeferred = nil }
                next = exercises[index].sets.first(where: { !$0.isCompleted })?.id
            } else {
                guard let set = exercises[index].sets.firstIndex(where: { !$0.isCompleted && $0.isDeferred != true && $0.resolvedSetType == .normal }) else { throw WorkoutBlockError.invalid }
                let id = exercises[index].sets[set].id; exercises[index].sets[set].isDeferred = true
                next = WorkoutSetNavigation.nextAfterDeferring(setID: id, in: draft.navigationExercises(exercises))?.setID
            }
            try saveReviewedExercises(exercises, receipt: draft.sessionToolsReceipt)
            selectedSetID = next; scrollTarget = next; persistDraft()
        } catch { saveMessage = "The partner-set change could not save. Logged work stays intact. \(error.localizedDescription)" }
    }

    private func didCompleteSet(_ setID: String) {
        if let exercise = routine.exercises.firstIndex(where: { $0.sets.contains { $0.id == setID } }),
           let set = routine.exercises[exercise].sets.firstIndex(where: { $0.id == setID }) { routine.exercises[exercise].sets[set].isDeferred = nil }
        lastCompletedSetID = setID
        let next = WorkoutSetNavigation.next(after: setID, in: navigationExercises)
        selectedSetID = next?.setID
        scrollTarget = next?.setID
        persistDraft()
    }

    private func didReopenSet(_ setID: String) {
        selectedSetID = setID
        if lastCompletedSetID == setID { lastCompletedSetID = nil }
        if routine.exercises.contains(where: { $0.type == .strength && $0.sets.contains(where: { $0.id == setID }) }) {
            setInputFocus = StrengthSetInput(setID: setID, field: .reps)
        }
        persistDraft()
    }

    private func undoLastSet() {
        guard let lastCompletedSetID, draft.completion == nil,
              let exercise = routine.exercises.firstIndex(where: { $0.sets.contains { $0.id == lastCompletedSetID && $0.isCompleted } }),
              let set = routine.exercises[exercise].sets.firstIndex(where: { $0.id == lastCompletedSetID }) else { return }
        routine.exercises[exercise].sets[set].isCompleted = false
        restTimer.cancelRestForReopenedSet(lastCompletedSetID)
        selectedSetID = lastCompletedSetID
        if setInputFocus != nil, routine.exercises[exercise].type == .strength {
            setInputFocus = StrengthSetInput(setID: lastCompletedSetID, field: .reps)
        }
        scrollTarget = lastCompletedSetID
        self.lastCompletedSetID = nil
        persistDraft()
    }

    private func sendInputCommand(increase: Bool, input: StrengthSetInput) {
        let action: StrengthSetCommand.Action = input.field == .weight
            ? (increase ? .increaseWeight : .decreaseWeight) : (increase ? .increaseReps : .decreaseReps)
        setInputCommand = StrengthSetCommand(setID: input.setID, action: action)
    }

    private func moveInputFocus(from input: StrengthSetInput) {
        if input.field == .weight {
            setInputFocus = StrengthSetInput(setID: input.setID, field: .reps)
        } else {
            guard let next = WorkoutSetNavigation.nextInput(after: input.setID, in: navigationExercises) else {
                finishInput()
                return
            }
            selectedSetID = next.setID; scrollTarget = next.setID
            setInputFocus = StrengthSetInput(setID: next.setID, field: .weight)
        }
    }

    private func moveInputFocusBackward(from input: StrengthSetInput) {
        if input.field == .reps {
            setInputFocus = StrengthSetInput(setID: input.setID, field: .weight)
        } else if let previous = WorkoutSetNavigation.previousInput(before: input.setID, in: navigationExercises) {
            selectedSetID = previous.setID
            scrollTarget = previous.setID
            setInputFocus = StrengthSetInput(setID: previous.setID, field: .reps)
        }
    }

    private func finishInput() {
        setInputFocus = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func beginFreshSession() {
        guard !savedSessionNeedsCompletion else { return }
        if let ownerID {
            let preferences = StrengthEquipmentPreferenceStore()
            for index in routine.exercises.indices {
                if !freezesReviewedSetup {
                    routine.exercises[index].loadEquipment = preferences.load(userID: ownerID, routineID: routine.id,
                        exerciseID: routine.exercises[index].id, exerciseName: routine.exercises[index].name) ?? routine.exercises[index].loadEquipment
                }
                do {
                    routine.exercises[index].cueSnapshot = try WorkoutScopedCueStore().best(exercise: routine.exercises[index], routineID: routine.id, userID: ownerID)?.snapshot
                } catch { saveMessage = "A reusable cue could not load. Your authored notes and workout remain available." }
            }
        }
        didStartSession = true
        totalWorkoutTimer.resume(elapsed: 0)
        persistDraft()
        LiveActivityManager.shared.startWorkout(routineName: routine.name, sessionID: draft.sessionID,
                                               workoutStartTime: totalWorkoutTimer.activityStartTime)
        DIContainer.shared.analyticsManager.log(.workoutStarted, ["routine_name": routine.name])
    }

    private func swapExercise(_ sourceID: String, to selection: ExercisePickerDraft) {
        do {
            let edit = try WorkoutSessionAdaptationRules.swapping(exerciseID: sourceID, to: selection,
                in: routine.exercises, history: progressionHistory)
            try applySessionEdit(edit)
            HapticManager.instance.feedback(.light)
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func applySessionEdit(_ edit: WorkoutSessionEditReceipt) throws {
        guard DIContainer.shared.authService.currentUserID == ownerID else { throw WorkoutBlockError.accountChanged }
        let updated = try WorkoutSessionAdaptationRules.applying(edit, to: routine.exercises)
        let replacement = edit.kind == .substitute ? updated.first { candidate in
            !routine.exercises.contains { $0.id == candidate.id }
        } : nil
        let nextSet = replacement?.sets.first?.id ?? WorkoutSetNavigation.firstUnfinished(in: updated)?.setID
        try saveReviewedExercises(updated, receipt: draft.sessionToolsReceipt,
            edits: Array(((draft.sessionEdits ?? []) + [edit]).suffix(16)), nextSelectedSetID: nextSet)
        selectedSetID = nextSet
        if replacement != nil { finishInput(); scrollTarget = nextSet }
        refreshPreviousReferences()
    }

    private func applySessionTools(_ change: StrengthSessionChange) throws {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID, draft.completion == nil else {
            throw StrengthSessionToolsError.accountChanged
        }
        if let profile = change.profile {
            guard try StrengthGymProfileStore().profiles(userID: ownerID).first(where: { $0.id == profile.id }) == profile else {
                throw StrengthSessionToolsError.changed
            }
        }
        let exercises = try StrengthSessionToolsRules.applying(change, to: routine.exercises)
        try saveReviewedExercises(exercises, receipt: change)
        saveMessage = "\(change.title). Saved for this workout; logged sets stay intact."
    }

    private func applyWarmup(_ plan: StrengthWarmupPlan) throws {
        guard draft.completion == nil, let index = routine.exercises.firstIndex(where: { $0.id == plan.exerciseID }) else {
            throw StrengthSessionToolsError.changed
        }
        var exercises = routine.exercises
        exercises[index] = try StrengthWarmupRules.applying(plan, to: exercises[index])
        try saveReviewedExercises(exercises, receipt: draft.sessionToolsReceipt)
        finishInput()
        if let first = plan.sets.first { selectedSetID = first.id; scrollTarget = first.id }
        saveMessage = "Reviewed warm-ups saved for this workout. Manual and logged preparation stayed intact."
    }

    private func undoSessionTools() {
        guard draft.completion == nil, let receipt = draft.sessionToolsReceipt else { return }
        do {
            let exercises = StrengthSessionToolsRules.undo(receipt, current: routine.exercises)
            try saveReviewedExercises(exercises, receipt: nil)
            refreshPreviousReferences()
            saveMessage = "Session Undo reviewed. Later edits and completed work were kept."
        } catch { saveMessage = error.localizedDescription }
    }

    /// Write the complete recovery payload before acknowledging a reviewed session change.
    private func saveReviewedExercises(_ exercises: [RoutineExercise], receipt: StrengthSessionChange?, edits: [WorkoutSessionEditReceipt]? = nil, nextSelectedSetID: String? = nil) throws {
        guard didStartSession, !hasLeftSession, draft.completion == nil, let ownerID,
              DIContainer.shared.authService.currentUserID == ownerID, let copy = routine.deepCopy() else {
            throw StrengthSessionToolsError.accountChanged
        }
        copy.exercises = exercises
        var reviewed = draft
        reviewed.routine = copy; reviewed.sessionToolsReceipt = receipt
        if let edits { reviewed.sessionEdits = edits }
        reviewed.selectedSetID = nextSelectedSetID ?? selectedSetID
        reviewed.elapsed = totalWorkoutTimer.totalTimeElapsed
        reviewed.rest = restTimer.state; reviewed.updatedAt = Date()
        try draftStore.save(reviewed, userID: ownerID)
        draft = reviewed; routine.exercises = exercises
    }

    private func refreshPreviousReferences() {
        for exercise in routine.exercises {
            previousPerformance[exercise.id] = ProgressionRules.history(for: exercise, in: progressionHistory,
                routineID: routine.id).first.flatMap { ProgressionRules.performance(for: exercise, in: $0) }
        }
    }

    @discardableResult
    private func persistDraft(exercises: [RoutineExercise]? = nil) -> Bool {
        guard didStartSession, !hasLeftSession, let ownerID,
              DIContainer.shared.authService.currentUserID == ownerID else { return false }
        guard let copy = routine.deepCopy() else { return false }
        if let exercises { copy.exercises = exercises }
        draft.routine = copy
        draft.selectedSetID = selectedSetID
        draft.elapsed = totalWorkoutTimer.totalTimeElapsed
        draft.rest = draft.completion == nil ? restTimer.state : nil
        draft.updatedAt = Date()
        do { try draftStore.save(draft, userID: ownerID); return true } catch { saveMessage = "Could not save a recovery copy on this device. Keep this workout open and try again."; return false }
    }

    private func notifyWorkoutCompleteIfNeeded() {
        guard !hasNotifiedWorkoutComplete else { return }
        hasNotifiedWorkoutComplete = true
        onWorkoutComplete()
    }

    private func recordCompletion(_ sessionLog: WorkoutSessionLog, userID: String) {
        let today = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: sessionLog.date) ? log : nil
        }
        let matchedFuelPlan = trainingFuelPlanStore.recordStrengthCompletion(
            routineID: routine.id,
            routineName: routine.name,
            completedAt: sessionLog.date,
            today: today,
            goals: TodayFuelPlanGoals(
                calories: goalSettings.calories ?? 0,
                protein: goalSettings.protein,
                carbs: goalSettings.carbs,
                fats: goalSettings.fats
            ),
            for: userID,
            session: sessionLog
        )
        if matchedFuelPlan {
            DIContainer.shared.analyticsManager?.logEvent(
                ProductAnalytics.Event.trainingFuelSessionOutcome.rawValue,
                parameters: ["outcome": "completed", "source": "strength_workout"]
            )
        }
        achievementService.checkWorkoutCountAchievements(userID: userID)
        achievementService.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
        if let exercise = draft.diaryExercise {
            DIContainer.shared.analyticsManager?.logEvent("exercise_logged", parameters: [
                "source": exercise.source,
                "duration": exercise.durationMinutes ?? 0,
                "calories": exercise.caloriesBurned
            ])
        }
        DIContainer.shared.analyticsManager.log(.workoutCompleted, ["completed_sets": completedSetCount])
        ActivationFunnel.recordTrainingCompletion(.strength)
    }
}
