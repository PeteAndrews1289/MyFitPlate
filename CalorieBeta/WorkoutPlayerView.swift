import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import ActivityKit

struct WorkoutPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var achievementService: AchievementService

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

    @State private var previousPerformance: [String: CompletedExercise] = [:]

    // Auto-Rest Preference
    @AppStorage("isAutoRestTimerEnabled") private var isAutoRestTimerEnabled = false

    // Exercise Swapping
    struct SwappableExercise: Identifiable {
        let id: String
        let binding: Binding<RoutineExercise>
    }
    @State private var swappableExercise: SwappableExercise?

    // Analytics / Summary Sheet
    @State private var showingAnalyticsSheet = false
    @State private var completedSessionLog: WorkoutSessionLog? = nil
    @State private var showingFinishConfirmation = false

    var onWorkoutComplete: () -> Void

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

    private var completedExerciseCount: Int {
        routine.exercises.filter { exercise in
            !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
        }.count
    }

    private var currentExerciseName: String {
        routine.exercises.first { exercise in
            exercise.sets.contains { !$0.isCompleted }
        }?.name ?? "Ready to finish"
    }

    init(routine: WorkoutRoutine, onWorkoutComplete: @escaping () -> Void) {
        // Guarantee a fresh workout by deep copying the template and resetting all completed states.
        let activeRoutine = routine.deepCopy() ?? routine

        for i in 0..<activeRoutine.exercises.count {
            for j in 0..<activeRoutine.exercises[i].sets.count {
                activeRoutine.exercises[i].sets[j].isCompleted = false
                // Note: We don't reset weight/reps here because the user's template might have custom target weights saved,
                // but since this is a deep copy, mutations during the workout won't affect the master template.
            }
        }

        _routine = State(initialValue: activeRoutine)
        _totalWorkoutTimer = StateObject(wrappedValue: TotalWorkoutTimer(routineId: activeRoutine.id))
        self.onWorkoutComplete = onWorkoutComplete
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
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
                    onClose: closeWorkout,
                    onStopRest: restTimer.stop
                )
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 8)

                // Main Scroll Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseCardView(
                                exercise: $routine.exercises[index],
                                restTimer: restTimer,
                                isAutoRestEnabled: $isAutoRestTimerEnabled,
                                routineName: routine.name,
                                previousPerformance: previousPerformance[exercise.name],
                                onAddNote: {
                                    self.exerciseForNote = $routine.exercises[index]
                                    self.noteText = exercise.notes ?? PinnedNotesManager.shared.getPinnedNote(for: exercise.name) ?? ""
                                    self.isNotePinned = PinnedNotesManager.shared.isNotePinned(for: exercise.name)
                                    self.showingNoteEditor = true
                                },
                                onSwap: {
                                    self.swappableExercise = SwappableExercise(id: exercise.id, binding: $routine.exercises[index])
                                },
                                onViewHistory: {
                                    self.showingHistoryFor = exercise
                                },
                                onMoveUp: index > 0 ? { moveExercise(from: IndexSet(integer: index), to: index - 1) } : nil,
                                onMoveDown: index < routine.exercises.count - 1 ? { moveExercise(from: IndexSet(integer: index), to: index + 2) } : nil
                            )
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }

                WorkoutSessionControlBar(
                    completedSets: completedSetCount,
                    totalSets: totalSetCount,
                    remainingSets: remainingSetCount,
                    isAutoRestEnabled: $isAutoRestTimerEnabled,
                    onPlateCalculator: {
                        showingPlateCalculator = true
                    },
                    onFinish: requestCompleteWorkout
                )
                .padding()
            }
            .blur(radius: showingNoteEditor ? 20 : 0)
            .onAppear(perform: loadPreviousPerformance)

            // Note Editor Overlay
            if showingNoteEditor {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                ExerciseNoteView(
                    note: $noteText,
                    isPinned: $isNotePinned,
                    onSave: {
                        guard let exerciseBinding = exerciseForNote else { return }
                        let exerciseName = exerciseBinding.wrappedValue.name

                        if isNotePinned {
                            PinnedNotesManager.shared.setPinnedNote(for: exerciseName, note: noteText)
                            exerciseBinding.wrappedValue.notes = nil
                        } else {
                            PinnedNotesManager.shared.removePinnedNote(for: exerciseName)
                            exerciseBinding.wrappedValue.notes = noteText
                        }
                        showingNoteEditor = false
                    },
                    onCancel: {
                        showingNoteEditor = false
                    }
                )
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            totalWorkoutTimer.start()
            LiveActivityManager.shared.startWorkout(routineName: routine.name)
            AnalyticsManager.log(.workoutStarted, ["routine_name": routine.name])
        }
        .onDisappear {
            // Safety check: Kill Live Activity if user swipes away the app
            LiveActivityManager.shared.endActivity()
            Task {
                try? await workoutService.saveRoutine(routine)
            }
        }
        .sheet(item: $swappableExercise) { wrapper in
            SwapExerciseView(exercise: wrapper.binding)
        }
        .sheet(item: $showingHistoryFor) { exercise in
            ExerciseHistoryView(exerciseName: exercise.name)
        }
        .sheet(isPresented: $showingPlateCalculator) {
            PlateCalculatorView()
        }
        .confirmationDialog(
            completedSetCount == 0 ? "Close without logging this workout?" : "Finish with \(remainingSetCount) sets left?",
            isPresented: $showingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button(completedSetCount == 0 ? "Close Without Logging" : "Finish Anyway", role: .destructive) {
                completeWorkout()
            }
            Button("Keep Training", role: .cancel) {}
        } message: {
            if completedSetCount == 0 {
                Text("No completed sets will be saved and your program progress will not advance.")
            } else {
                Text("Completed sets will be saved, but unfinished sets will be skipped.")
            }
        }
        .sheet(isPresented: $showingAnalyticsSheet, onDismiss: {
            onWorkoutComplete()
            dismiss()
        }) {
            if let log = completedSessionLog {
                WorkoutCompleteAnalyticsView(log: log)
            } else {
                Text("Error loading analytics")
            }
        }
    }

    private func loadPreviousPerformance() {
        Task {
            for exercise in routine.exercises {
                if let performance = await workoutService.fetchPreviousPerformance(for: exercise.name) {
                    previousPerformance[exercise.name] = performance
                }
            }
        }
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        routine.exercises.move(fromOffsets: source, toOffset: destination)
    }

    private func closeWorkout() {
        restTimer.stop()
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
        guard let sessionLog = logAllCompletedExercises() else {
            restTimer.stop()
            totalWorkoutTimer.stop()
            dismiss()
            return
        }

        restTimer.stop()
        totalWorkoutTimer.stop()
        AnalyticsManager.log(.workoutCompleted, ["completed_sets": completedSetCount])
        self.completedSessionLog = sessionLog
        self.showingAnalyticsSheet = true
    }

    private func logAllCompletedExercises() -> WorkoutSessionLog? {
        guard let userID = Auth.auth().currentUser?.uid else { return nil }

        let completedExercisesForLog = routine.exercises.compactMap { exercise -> CompletedExercise? in
            let completedSets = exercise.sets.filter { $0.isCompleted }.map {
                CompletedSet(reps: $0.reps, weight: $0.weight, distance: $0.distance, durationInSeconds: $0.durationInSeconds)
            }
            return completedSets.isEmpty ? nil : CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: completedSets)
        }

        guard !completedExercisesForLog.isEmpty else { return nil }

        let newSessionID = UUID().uuidString

        let sessionLog = WorkoutSessionLog(
            id: newSessionID,
            date: Timestamp(date: Date()),
            routineID: routine.id,
            completedExercises: completedExercisesForLog
        )
        Task {
            await workoutService.saveWorkoutSessionLog(sessionLog)
            achievementService.checkWorkoutCountAchievements(userID: userID)
        }

        var totalCaloriesBurned: Double = 0
        var totalDurationInSeconds: Int = 0

        for exercise in routine.exercises {
            let completedSets = exercise.sets.filter { $0.isCompleted }
            if completedSets.isEmpty { continue }

            switch exercise.type {
            case .strength:
                let estimatedDurationMinutes = Double(completedSets.count) * 1.0
                let bodyweightKg = goalSettings.weight * 0.453592
                totalCaloriesBurned += (5.0 * 3.5 * bodyweightKg) / 200.0 * estimatedDurationMinutes
                totalDurationInSeconds += Int(estimatedDurationMinutes * 60)

            case .cardio:
                let duration = completedSets.reduce(0) { $0 + $1.durationInSeconds }
                totalDurationInSeconds += duration
                let durationMinutes = Double(duration) / 60.0
                let bodyweightKg = goalSettings.weight * 0.453592
                totalCaloriesBurned += (8.0 * 3.5 * bodyweightKg) / 200.0 * durationMinutes

            case .flexibility:
                let duration = completedSets.reduce(0) { $0 + $1.durationInSeconds }
                totalDurationInSeconds += duration
                let durationMinutes = Double(duration) / 60.0
                let bodyweightKg = goalSettings.weight * 0.453592
                totalCaloriesBurned += (2.5 * 3.5 * bodyweightKg) / 200.0 * durationMinutes
            }
        }

        if totalCaloriesBurned > 0 {
            let loggedExercise = LoggedExercise(
                name: routine.name,
                durationMinutes: totalDurationInSeconds / 60,
                caloriesBurned: totalCaloriesBurned,
                date: Date(),
                source: "routine",
                workoutID: routine.id,
                sessionID: newSessionID
            )
            dailyLogService.exerciseLogStore.addExerciseToLog(for: userID, exercise: loggedExercise)
        }

        applyProgressiveOverloadAndReset()

        return sessionLog
    }

    private func applyProgressiveOverloadAndReset() {
        for i in 0..<routine.exercises.count {
            let exercise = routine.exercises[i]

            if exercise.type == .strength {
                let nonWarmupSets = exercise.sets.filter { !$0.isWarmup }
                let completedNonWarmupSets = nonWarmupSets.filter { $0.isCompleted }
                let targetMaxReps = parseTargetMaxReps(exercise.targetReps)

                if completedNonWarmupSets.count >= exercise.targetSets, exercise.targetSets > 0, targetMaxReps > 0 {
                    let allSetsMetTarget = completedNonWarmupSets.allSatisfy { $0.reps >= targetMaxReps }
                    if allSetsMetTarget {
                        // Increase weight by 5 lbs for progression
                        for j in 0..<routine.exercises[i].sets.count {
                            if !routine.exercises[i].sets[j].isWarmup {
                                routine.exercises[i].sets[j].weight += 5.0
                            }
                        }
                    }
                }
            }

            // Reset for the next session
            for j in 0..<routine.exercises[i].sets.count {
                routine.exercises[i].sets[j].isCompleted = false
            }
        }
    }

    private func parseTargetMaxReps(_ target: String) -> Int {
        if let last = target.components(separatedBy: "-").last, let maxReps = Int(last.trimmingCharacters(in: .whitespaces)) {
            return maxReps
        }
        if let reps = Int(target.trimmingCharacters(in: .whitespaces)) {
            return reps
        }
        return 0
    }
}

// MARK: - Subviews

