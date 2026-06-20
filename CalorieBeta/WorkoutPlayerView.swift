import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import ActivityKit

// MARK: - Timers

/// Manages the total elapsed time for the workout session.
class TotalWorkoutTimer: ObservableObject {
    @Published var totalTimeElapsed: TimeInterval = 0
    private var timer: Timer?
    private var startTime: Date?
    private let userDefaultsKey: String

    init(routineId: String) {
        self.userDefaultsKey = "totalWorkoutTimer_\(routineId)"
        loadTimerState()
    }

    func start() {
        guard timer == nil else { return }
        if startTime == nil {
            startTime = Date().addingTimeInterval(-totalTimeElapsed)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTotalTime()
        }
        saveTimerState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        totalTimeElapsed = 0
        clearTimerState()
    }

    private func updateTotalTime() {
        guard let startTime = startTime else { return }
        totalTimeElapsed = Date().timeIntervalSince(startTime)
    }

    private func saveTimerState() {
        guard let startTime = startTime else { return }
        UserDefaults.standard.set(startTime, forKey: userDefaultsKey)
    }

    private func loadTimerState() {
        if let savedStartTime = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date {
            self.startTime = savedStartTime
            updateTotalTime()
            start()
        }
    }

    private func clearTimerState() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    func formattedTime() -> String {
        let hours = Int(totalTimeElapsed) / 3600
        let minutes = (Int(totalTimeElapsed) % 3600) / 60
        let seconds = Int(totalTimeElapsed) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Manages the rest timer between sets and syncs with Live Activities.
class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    private var timer: Timer?
    private var endTime: Date?

    // Starts the timer AND the Live Activity
    func start(duration: TimeInterval, routineName: String) {
        guard timeRemaining == 0 else { return }
        self.timeRemaining = duration
        self.endTime = Date().addingTimeInterval(duration)

        // Update Live Activity on Lock Screen
        LiveActivityManager.shared.startRestTimer(duration: duration)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    // Stops the timer AND removes the Live Activity
    func stop() {
        timer?.invalidate()
        timer = nil
        endTime = nil
        timeRemaining = 0

        // End Rest state on Live Activity
        LiveActivityManager.shared.endRestTimer()
    }

    private func updateTimer() {
        guard let endTime = endTime else {
            stop()
            return
        }

        let remaining = endTime.timeIntervalSinceNow
        self.timeRemaining = max(0, remaining)

        if self.timeRemaining == 0 {
            stop()
        }
    }

    func formattedTime() -> String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }
}


// MARK: - Main View

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
                        ForEach($routine.exercises) { $exercise in
                            ExerciseCardView(
                                exercise: $exercise,
                                restTimer: restTimer,
                                isAutoRestEnabled: $isAutoRestTimerEnabled,
                                routineName: routine.name,
                                previousPerformance: previousPerformance[exercise.name],
                                onAddNote: {
                                    self.exerciseForNote = $exercise
                                    self.noteText = $exercise.wrappedValue.notes ?? PinnedNotesManager.shared.getPinnedNote(for: $exercise.wrappedValue.name) ?? ""
                                    self.isNotePinned = PinnedNotesManager.shared.isNotePinned(for: $exercise.wrappedValue.name)
                                    self.showingNoteEditor = true
                                },
                                onSwap: {
                                    self.swappableExercise = SwappableExercise(id: exercise.id, binding: $exercise)
                                },
                                onViewHistory: {
                                    self.showingHistoryFor = exercise
                                }
                            )
                        }
                        .onMove(perform: moveExercise)

                    }
                    .padding()
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
            dailyLogService.addExerciseToLog(for: userID, exercise: loggedExercise)
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

private struct WorkoutSessionControlBar: View {
    let completedSets: Int
    let totalSets: Int
    let remainingSets: Int
    @Binding var isAutoRestEnabled: Bool
    let onPlateCalculator: () -> Void
    let onFinish: () -> Void

    private var progressText: String {
        totalSets == 0 ? "No sets planned" : "\(completedSets)/\(totalSets) sets complete"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isAutoRestEnabled ? .accentPositive : Color(UIColor.secondaryLabel))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto Rest")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text(isAutoRestEnabled ? "On after each set" : "Manual timer")
                            .appFont(size: 10, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Toggle("", isOn: $isAutoRestEnabled)
                        .labelsHidden()
                        .tint(.accentPositive)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button(action: onPlateCalculator) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Plates")
                            .appFont(size: 11, weight: .bold)
                    }
                    .foregroundColor(.brandPrimary)
                    .frame(width: 72, height: 58)
                    .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(action: onFinish) {
                HStack {
                    Label("Finish Workout", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Text(remainingSets == 0 ? "Ready" : "\(remainingSets) left")
                        .appFont(size: 12, weight: .bold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Text(progressText)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct WorkoutSessionHeaderCard: View {
    let routineName: String
    let elapsedTime: String
    let restTime: String?
    let completedSets: Int
    let totalSets: Int
    let completedExercises: Int
    let totalExercises: Int
    let progress: Double
    let currentExerciseName: String
    let onClose: () -> Void
    let onStopRest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Workout")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(routineName)
                        .appFont(size: 23, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text("Now: \(currentExerciseName)")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.brandPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                        .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close workout")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(completedSets) of \(max(totalSets, 0)) sets")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    Spacer()

                    Text("\(Int((progress * 100).rounded()))%")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPrimary.opacity(0.12))

                        Capsule()
                            .fill(Color.brandPrimary)
                            .frame(width: geometry.size.width * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.25), value: progress)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 10) {
                WorkoutHeaderMetric(title: "Elapsed", value: elapsedTime, icon: "clock.fill", color: .blue)
                WorkoutHeaderMetric(title: "Exercises", value: "\(completedExercises)/\(totalExercises)", icon: "list.bullet", color: .orange)

                if let restTime {
                    Button(action: onStopRest) {
                        WorkoutHeaderMetric(title: "Rest", value: restTime, icon: "timer", color: .accentPositive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop rest timer")
                } else {
                    WorkoutHeaderMetric(title: "Rest", value: "Ready", icon: "timer", color: .accentPositive)
                }
            }
        }
        .asCard()
    }
}

private struct WorkoutHeaderMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)

                Text(title)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Text(value)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    @Binding var isAutoRestEnabled: Bool
    var routineName: String
    var previousPerformance: CompletedExercise?
    var onAddNote: () -> Void
    var onSwap: () -> Void
    var onViewHistory: () -> Void

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

    private var typeChip: (title: String, icon: String, color: Color) {
        switch exercise.type {
        case .strength:
            return ("Strength", "dumbbell.fill", .brandPrimary)
        case .cardio:
            return ("Cardio", "heart.fill", .red)
        case .flexibility:
            return ("Mobility", "figure.cooldown", .blue)
        }
    }

    private var displayedNote: String? {
        if let sessionNote = exercise.notes, !sessionNote.isEmpty {
            return sessionNote
        }
        return PinnedNotesManager.shared.getPinnedNote(for: exercise.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 12) {
                    Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .background(typeChip.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Label(typeChip.title, systemImage: typeChip.icon)
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(typeChip.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(typeChip.color.opacity(0.10), in: Capsule())

                            Text("\(completedSetCount)/\(totalSetCount) sets")
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        Text(exercise.name)
                            .appFont(size: 20, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    exerciseMenu
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(typeChip.color.opacity(0.10))

                        Capsule()
                            .fill(typeChip.color)
                            .frame(width: geometry.size.width * CGFloat(exerciseProgress))
                            .animation(.easeInOut(duration: 0.2), value: exerciseProgress)
                    }
                }
                .frame(height: 6)

                if let note = displayedNote {
                    HStack(spacing: 4) {
                        if PinnedNotesManager.shared.isNotePinned(for: exercise.name) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                        }
                        Text(note)
                    }
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            switch exercise.type {
            case .strength:
                StrengthExerciseView(
                    exercise: $exercise,
                    previousPerformance: previousPerformance,
                    onSetComplete: { completedIndex in
                        // Auto-fill logic
                        let nextIndex = completedIndex + 1
                        if nextIndex < exercise.sets.count {
                            let completedSet = exercise.sets[completedIndex]
                            if !exercise.sets[nextIndex].isCompleted && exercise.sets[nextIndex].weight == 0 && exercise.sets[nextIndex].reps == 0 {
                                exercise.sets[nextIndex].weight = completedSet.weight
                                exercise.sets[nextIndex].reps = completedSet.reps
                            }
                        }

                        // Auto-start rest timer
                        if isAutoRestEnabled {
                            restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName)
                        }
                    }
                )
            case .cardio:
                CardioExerciseView(exercise: $exercise)
            case .flexibility:
                FlexibilityExerciseView(exercise: $exercise)
            }

            Button {
                exercise.sets.append(ExerciseSet())
            } label: {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(typeChip.color.opacity(0.08), lineWidth: 1)
        )
    }

    private var exerciseMenu: some View {
        HStack(spacing: 8) {
            if restTimer.timeRemaining > 0 {
                Text(restTimer.formattedTime())
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            } else {
                Button {
                    restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName)
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.brandPrimary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button("Add Warmup Sets") {
                    let newWarmupSet = ExerciseSet(isWarmup: true)
                    exercise.sets.insert(newWarmupSet, at: 0)
                }
                Button("Add/Edit Note", action: onAddNote)
                Button("Swap Exercise", action: onSwap)
                    .disabled(exercise.alternatives?.isEmpty ?? true)
                Button("View Demo & History", action: onViewHistory)
                Toggle("Auto-Rest Timer", isOn: $isAutoRestEnabled)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
            }
        }
    }
}

private struct StrengthExerciseView: View {
    @Binding var exercise: RoutineExercise
    var previousPerformance: CompletedExercise?
    var onSetComplete: (Int) -> Void

    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(minWidth: 25, alignment: .leading)
                Text("TARGET / LAST").frame(maxWidth: .infinity, alignment: .leading)
                Text("LBS").frame(maxWidth: .infinity, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                StrengthSetRow(
                    set: $exercise.sets[index],
                    setIndex: index + 1,
                    previousSet: previousPerformance?.sets.indices.contains(index) == true ? previousPerformance?.sets[index] : nil,
                    onComplete: {
                        onSetComplete(index)
                    }
                )
            }
            .onDelete(perform: deleteStrengthSet)
        }
    }

    private func deleteStrengthSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

private struct CardioExerciseView: View {
    @Binding var exercise: RoutineExercise

    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                Text("DISTANCE").frame(maxWidth: .infinity, alignment: .center)
                Text("TIME").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                CardioSetRow(set: $exercise.sets[index], setIndex: index + 1)
            }
            .onDelete(perform: deleteCardioSet)
        }
    }

    private func deleteCardioSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

private struct FlexibilityExerciseView: View {
    @Binding var exercise: RoutineExercise

    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                Text("SECONDS").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                FlexibilitySetRow(set: $exercise.sets[index], setIndex: index + 1)
            }
            .onDelete(perform: deleteFlexibilitySet)
        }
    }

    private func deleteFlexibilitySet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

private struct SwapExerciseView: View {
    @Binding var exercise: RoutineExercise
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Swap '\(exercise.name)' with:")) {
                    ForEach(exercise.alternatives ?? [], id: \.self) { alternativeName in
                        Button(alternativeName) {
                            let originalName = exercise.name
                            let originalAlternatives = exercise.alternatives ?? []

                            let newSets = exercise.sets.map { originalSet -> ExerciseSet in
                                return ExerciseSet(target: originalSet.target)
                            }

                            exercise.name = alternativeName
                            exercise.sets = newSets
                            exercise.alternatives = [originalName] + originalAlternatives.filter { $0 != alternativeName }

                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct StrengthSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var previousSet: CompletedSet?
    var onComplete: () -> Void

    @State private var weightInput: String
    @State private var repsInput: String
    @State private var isPersonalBest = false
    @State private var showingPlateMath = false

    private let weightIncrement: Double = 2.5

    private var targetText: String {
        self.set.target ?? "Work set"
    }

    init(set: Binding<ExerciseSet>, setIndex: Int, previousSet: CompletedSet?, onComplete: @escaping () -> Void) {
        self._set = set
        self.setIndex = setIndex
        self.previousSet = previousSet
        self.onComplete = onComplete

        self._weightInput = State(initialValue: set.wrappedValue.weight > 0 ? String(format: "%g", set.wrappedValue.weight) : "")
        self._repsInput = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        HStack {
            Text(set.isWarmup ? "W" : "\(setIndex)")
                .frame(minWidth: 25, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(targetText)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)

                Button(action: fillFromPrevious) {
                    Text(previousSet.map { "\(String(format: "%g", $0.weight)) lb x \($0.reps)" } ?? "No prior")
                        .foregroundColor(previousSet == nil ? .secondary : .brandPrimary)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                .buttonStyle(.plain)
                .disabled(previousSet == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Button(action: { adjustWeight(by: -weightIncrement) }) {
                    Image(systemName: "minus.circle")
                }.buttonStyle(.plain)

                TextField("0", text: $weightInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 45)
                    .onChange(of: weightInput) {
                        let newWeight = Double(weightInput) ?? 0
                        set.weight = newWeight
                        checkIfPersonalBest(newWeight: newWeight, newRps: set.reps)
                    }

                Button(action: { adjustWeight(by: weightIncrement) }) {
                    Image(systemName: "plus.circle")
                }.buttonStyle(.plain)

                Button(action: { showingPlateMath = true }) {
                    Image(systemName: "circle.grid.cross")
                        .foregroundColor(.brandPrimary)
                        .font(.system(size: 14, weight: .bold))
                }.buttonStyle(.plain).padding(.leading, 4)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .sheet(isPresented: $showingPlateMath) {
                PlateMathVisualizer(totalWeight: set.weight)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 2) {
                Button(action: { adjustReps(by: -1) }) {
                    Image(systemName: "minus.circle")
                }.buttonStyle(.plain)

                TextField("0", text: $repsInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 35)
                    .onChange(of: repsInput) {
                        let newReps = Int(repsInput) ?? 0
                        set.reps = newReps
                        checkIfPersonalBest(newWeight: set.weight, newRps: newReps)
                    }

                Button(action: { adjustReps(by: 1) }) {
                    Image(systemName: "plus.circle")
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)


            HStack(spacing: 2) {
                if isPersonalBest {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }

                Button(action: toggleCompletion) {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                        .font(.title2)
                }
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
        .foregroundColor(.brandPrimary)
        .onChange(of: set.weight) { _, newWeight in
            let currentInputWeight = Double(weightInput) ?? 0
            if newWeight != currentInputWeight {
                weightInput = newWeight > 0 ? String(format: "%g", newWeight) : ""
            }
        }
        .onChange(of: set.reps) { _, newReps in
            let currentInputReps = Int(repsInput) ?? 0
            if newReps != currentInputReps {
                repsInput = newReps > 0 ? "\(newReps)" : ""
            }
        }
    }

    private func fillFromPrevious() {
        guard let prev = previousSet else { return }
        self.weightInput = String(format: "%g", prev.weight)
        self.repsInput = "\(prev.reps)"
        HapticManager.instance.feedback(.light)
    }

    private func adjustWeight(by amount: Double) {
        let currentWeight = Double(weightInput) ?? 0
        let newWeight = max(0, currentWeight + amount)
        self.weightInput = String(format: "%g", newWeight)
        HapticManager.instance.feedback(.light)
    }

    private func adjustReps(by amount: Int) {
        let currentReps = Int(repsInput) ?? 0
        let newReps = max(0, currentReps + amount)
        self.repsInput = "\(newReps)"
        HapticManager.instance.feedback(.light)
    }

    private func toggleCompletion() {
        if !set.isCompleted {
            if set.weight == 0, let previousSet {
                set.weight = previousSet.weight
                weightInput = String(format: "%g", previousSet.weight)
            }

            if set.reps == 0, let targetReps = inferredReps(from: set.target) {
                set.reps = targetReps
                repsInput = "\(targetReps)"
            }
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
            onComplete()
        }
    }

    private func inferredReps(from target: String?) -> Int? {
        guard let target else { return nil }
        return target
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .first
    }

    private func checkIfPersonalBest(newWeight: Double, newRps: Int) {
        guard let previous = previousSet, newRps > 0, newWeight > 0 else {
            isPersonalBest = false
            return
        }

        if newWeight > previous.weight && newRps >= previous.reps {
            isPersonalBest = true
        } else if newWeight == previous.weight && newRps > previous.reps {
            isPersonalBest = true
        } else {
            isPersonalBest = false
        }
    }
}

private struct CardioSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int

    @State private var distanceInput: String
    @State private var timeInput: String

    init(set: Binding<ExerciseSet>, setIndex: Int) {
        self._set = set
        self.setIndex = setIndex
        self._distanceInput = State(initialValue: set.wrappedValue.distance > 0 ? String(format: "%g", set.wrappedValue.distance) : "")
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? "\(set.wrappedValue.durationInSeconds / 60)" : "")
    }

    var body: some View {
        HStack {
            Text("\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("miles", text: $distanceInput)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: distanceInput) {
                    set.distance = Double(distanceInput) ?? 0
                }

            TextField("min", text: $timeInput)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: timeInput) {
                    set.durationInSeconds = (Int(timeInput) ?? 0) * 60
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, set.durationInSeconds == 0, let inferredSeconds = inferredDurationSeconds(from: set.target) {
            set.durationInSeconds = inferredSeconds
            timeInput = "\(max(inferredSeconds / 60, 1))"
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
        }
    }

    private func inferredDurationSeconds(from target: String?) -> Int? {
        guard let target else { return nil }
        let lowercasedTarget = target.lowercased()
        guard let firstNumber = lowercasedTarget.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first else {
            return nil
        }

        return lowercasedTarget.contains("sec") || lowercasedTarget.contains("s") ? firstNumber : firstNumber * 60
    }
}

private struct FlexibilitySetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int

    @State private var timeInput: String

    init(set: Binding<ExerciseSet>, setIndex: Int) {
        self._set = set
        self.setIndex = setIndex
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? "\(set.wrappedValue.durationInSeconds)" : "")
    }

    var body: some View {
        HStack {
            Text("\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("seconds", text: $timeInput)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: timeInput) {
                    set.durationInSeconds = Int(timeInput) ?? 0
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, set.durationInSeconds == 0, let inferredSeconds = inferredDurationSeconds(from: set.target) {
            set.durationInSeconds = inferredSeconds
            timeInput = "\(inferredSeconds)"
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
        }
    }

    private func inferredDurationSeconds(from target: String?) -> Int? {
        guard let target else { return nil }
        let lowercasedTarget = target.lowercased()
        guard let firstNumber = lowercasedTarget.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first else {
            return nil
        }

        return lowercasedTarget.contains("min") ? firstNumber * 60 : firstNumber
    }
}

// MARK: - Plate Math Visualizer
struct PlateMathVisualizer: View {
    let totalWeight: Double
    let barWeight: Double = 45.0

    // Standard plates in lbs
    let availablePlates: [Double] = [45, 35, 25, 10, 5, 2.5]

    // Calculate plates per side
    var platesPerSide: [Double] {
        var remainingWeight = (totalWeight - barWeight) / 2.0
        var plates: [Double] = []

        if remainingWeight <= 0 { return [] }

        for plate in availablePlates {
            while remainingWeight >= plate {
                plates.append(plate)
                remainingWeight -= plate
            }
        }
        return plates
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Plate Math")
                .appFont(size: 20, weight: .bold)

            if totalWeight < barWeight {
                Text("Weight must be at least \(Int(barWeight)) lbs (the bar).")
                    .foregroundColor(.secondary)
            } else {
                Text("Load this on **EACH SIDE**")
                    .appFont(size: 14)
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    // The Barbell Sleeve
                    Rectangle()
                        .fill(Color(UIColor.systemGray3))
                        .frame(width: 40, height: 20)
                        .cornerRadius(2)

                    // The Collar
                    Rectangle()
                        .fill(Color(UIColor.systemGray2))
                        .frame(width: 10, height: 40)
                        .cornerRadius(2)

                    // The Plates
                    ForEach(0..<platesPerSide.count, id: \.self) { index in
                        PlateView(weight: platesPerSide[index])
                    }

                    if platesPerSide.isEmpty {
                        Text("Just the bar!")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)
            }
        }
        .padding()
    }
}

struct PlateView: View {
    let weight: Double

    private var plateColor: Color {
        switch weight {
        case 45: return .blue
        case 35: return .yellow
        case 25: return .green
        case 10: return .gray
        case 5: return .orange
        case 2.5: return .red
        default: return .gray
        }
    }

    private var plateHeight: CGFloat {
        switch weight {
        case 45: return 120
        case 35: return 100
        case 25: return 80
        case 10: return 60
        case 5: return 40
        case 2.5: return 30
        default: return 50
        }
    }

    private var plateWidth: CGFloat {
        switch weight {
        case 45: return 24
        case 35: return 22
        case 25: return 20
        case 10: return 18
        case 5: return 14
        case 2.5: return 12
        default: return 16
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(plateColor)
                .frame(width: plateWidth, height: plateHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )

            Text(weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : "\(weight, specifier: "%.1f")")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(-90))
        }
    }
}
