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
        
        // Start Live Activity on Lock Screen
        LiveActivityManager.shared.startRestTimer(routineName: routineName, duration: duration)
        
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
        
        // End Live Activity
        LiveActivityManager.shared.endActivity()
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
    // FIX: Changed from WorkoutAnalytics? to WorkoutSessionLog?
    @State private var completedSessionLog: WorkoutSessionLog? = nil
    
    var onWorkoutComplete: () -> Void

    init(routine: WorkoutRoutine, onWorkoutComplete: @escaping () -> Void) {
        _routine = State(initialValue: routine)
        _totalWorkoutTimer = StateObject(wrappedValue: TotalWorkoutTimer(routineId: routine.id))
        self.onWorkoutComplete = onWorkoutComplete
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Top Bar: Timer & Close
                HStack {
                    Text(totalWorkoutTimer.formattedTime())
                        .padding(8)
                        .background(.thinMaterial)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Text(routine.name)
                        .appFont(size: 18, weight: .bold)
                    
                    Spacer()
                    
                    Button("Close") {
                        // Ensure we kill the Live Activity before dismissing
                        restTimer.stop()
                        totalWorkoutTimer.stop()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

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
                        
                        // Complete Button
                        Button("Mark Workout as Complete") {
                            // 1. Log the data
                            guard let sessionLog = logAllCompletedExercises() else {
                                // Nothing logged? Just exit.
                                restTimer.stop()
                                totalWorkoutTimer.stop()
                                onWorkoutComplete()
                                dismiss()
                                return
                            }
                            
                            // 2. Stop timers immediately
                            restTimer.stop()
                            totalWorkoutTimer.stop()
                            
                            // 3. Store the log and show the sheet
                            // FIX: Pass log directly, don't generate old analytics
                            self.completedSessionLog = sessionLog
                            self.showingAnalyticsSheet = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top)
                    }
                    .padding()
                }

                // Bottom Bar
                HStack {
                    Button {
                        showingPlateCalculator = true
                    } label: {
                        Label("Plate Calculator", systemImage: "square.stack.3d.up.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
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
        // Summary Sheet
        .sheet(isPresented: $showingAnalyticsSheet, onDismiss: {
            onWorkoutComplete()
            dismiss()
        }) {
            // FIX: Pass the log directly to the new view
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
        
        return sessionLog
    }
}

// MARK: - Subviews

private struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    @Binding var isAutoRestEnabled: Bool
    var routineName: String
    var previousPerformance: CompletedExercise?
    var onAddNote: () -> Void
    var onSwap: () -> Void
    var onViewHistory: () -> Void
    
    private var displayedNote: String? {
        if let sessionNote = exercise.notes, !sessionNote.isEmpty {
            return sessionNote
        }
        return PinnedNotesManager.shared.getPinnedNote(for: exercise.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(exercise.name)
                        .appFont(size: 20, weight: .bold)
                    Spacer()

                    if restTimer.timeRemaining > 0 {
                        Text(restTimer.formattedTime())
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .padding(8)
                            .background(.thinMaterial)
                            .cornerRadius(8)
                    } else {
                        Button {
                            restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName)
                        } label: {
                            Image(systemName: "timer")
                        }
                        .tint(.brandPrimary)
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
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
                
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
        .background(Color.backgroundSecondary)
        .cornerRadius(15)
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
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
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
    
    private let weightIncrement: Double = 2.5

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

            Button(action: fillFromPrevious) {
                Text(previousSet != nil ? "\(String(format: "%g", previousSet!.weight)) lbs x \(previousSet!.reps)" : "No Prior Data")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(previousSet == nil ? .secondary : .brandPrimary)
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(previousSet == nil)

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
                
                Button(action: {
                    set.isCompleted.toggle()
                    if set.isCompleted {
                        HapticManager.instance.feedback(.medium)
                        onComplete()
                    }
                }) {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                        .font(.title2)
                }
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
        .foregroundColor(.brandPrimary)
        .onChange(of: set.weight) { newWeight in
            let currentInputWeight = Double(weightInput) ?? 0
            if newWeight != currentInputWeight {
                weightInput = newWeight > 0 ? String(format: "%g", newWeight) : ""
            }
        }
        .onChange(of: set.reps) { newReps in
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

            Button(action: { set.isCompleted.toggle() }) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
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

            Button(action: { set.isCompleted.toggle() }) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
        }
        .appFont(size: 14)
    }
}
