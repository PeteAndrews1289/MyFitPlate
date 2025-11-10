import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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

/// Manages the rest timer between sets.
class RestTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval = 0
    private var timer: Timer?
    private var endTime: Date?

    func start(duration: TimeInterval) {
        guard timeRemaining == 0 else { return }
        self.timeRemaining = duration
        self.endTime = Date().addingTimeInterval(duration)
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endTime = nil
        timeRemaining = 0
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


/// The main view for actively performing a workout routine.
struct WorkoutPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var routine: WorkoutRoutine
    @StateObject private var restTimer = RestTimer()
    @StateObject private var totalWorkoutTimer: TotalWorkoutTimer
    
    // State for the exercise note editor
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    @State private var isNotePinned = false
    @State private var exerciseForNote: Binding<RoutineExercise>?
    
    // State for other sheets
    @State private var showingHistoryFor: RoutineExercise?
    @State private var showingPlateCalculator = false
    
    @State private var previousPerformance: [String: CompletedExercise] = [:]
    
    //
    // KEY LINE 1: The @AppStorage property is defined here in the main view.
    //
    @AppStorage("isAutoRestTimerEnabled") private var isAutoRestTimerEnabled = false
    
    // State for the exercise swap sheet
    struct SwappableExercise: Identifiable {
        let id: String
        let binding: Binding<RoutineExercise>
    }
    @State private var swappableExercise: SwappableExercise?
    
    var onWorkoutComplete: () -> Void

    init(routine: WorkoutRoutine, onWorkoutComplete: @escaping () -> Void) {
        _routine = State(initialValue: routine)
        _totalWorkoutTimer = StateObject(wrappedValue: TotalWorkoutTimer(routineId: routine.id))
        self.onWorkoutComplete = onWorkoutComplete
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with timer and close button
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
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                // List of exercises
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach($routine.exercises) { $exercise in
                            ExerciseCardView(
                                exercise: $exercise,
                                restTimer: restTimer,
                                //
                                // KEY LINE 2: The binding ($isAutoRestTimerEnabled) is passed into the ExerciseCardView.
                                //
                                isAutoRestEnabled: $isAutoRestTimerEnabled,
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
                        .onMove(perform: moveExercise) // Allows reordering exercises
                        
                        // Button to finish the workout
                        Button("Mark Workout as Complete") {
                            logAllCompletedExercises()
                            restTimer.stop()
                            totalWorkoutTimer.stop()
                            onWorkoutComplete()
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top)
                    }
                    .padding()
                }

                // Footer for utility buttons
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
            .blur(radius: showingNoteEditor ? 20 : 0) // Blur background when note editor is active
            .onAppear(perform: loadPreviousPerformance)

            // Exercise note editor overlay
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
            // Save any changes to the routine when the view is dismissed
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
    }
    
    /// Fetches the last performance for each exercise in the routine.
    private func loadPreviousPerformance() {
        Task {
            for exercise in routine.exercises {
                if let performance = await workoutService.fetchPreviousPerformance(for: exercise.name) {
                    previousPerformance[exercise.name] = performance
                }
            }
        }
    }
    
    /// Reorders exercises in the routine list.
    private func moveExercise(from source: IndexSet, to destination: Int) {
        routine.exercises.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Logs all completed sets to Firestore and the user's daily log.
    private func logAllCompletedExercises() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        let completedExercisesForLog = routine.exercises.compactMap { exercise -> CompletedExercise? in
            let completedSets = exercise.sets.filter { $0.isCompleted }.map {
                CompletedSet(reps: $0.reps, weight: $0.weight, distance: $0.distance, durationInSeconds: $0.durationInSeconds)
            }
            return completedSets.isEmpty ? nil : CompletedExercise(exerciseName: exercise.name, exercise: exercise, sets: completedSets)
        }

        let newSessionID = UUID().uuidString

        if !completedExercisesForLog.isEmpty {
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
        }

        for exercise in routine.exercises {
            let completedSets = exercise.sets.filter { $0.isCompleted }
            if completedSets.isEmpty { continue }
            
            // Calculate calories burned for the exercise
            let totalCaloriesBurned = completedSets.reduce(0.0) { partialResult, set in
                let bodyweightKg = goalSettings.weight * 0.453592
                // Estimate 1 minute per set for MET calculation (MET value of 5.0 for general strength training)
                return partialResult + (5.0 * 3.5 * bodyweightKg) / 200
            }

            if totalCaloriesBurned > 0 {
                let loggedExercise = LoggedExercise(
                    name: exercise.name,
                    durationMinutes: nil, // Duration is estimated via calories
                    caloriesBurned: totalCaloriesBurned,
                    date: Date(),
                    source: "routine",
                    workoutID: routine.id,
                    sessionID: newSessionID
                )
                dailyLogService.addExerciseToLog(for: userID, exercise: loggedExercise)
            }
        }
    }
}

/// A card view for a single exercise in the workout player.
private struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    //
    // KEY LINE 3: The @Binding property is defined here to receive the variable.
    //
    @Binding var isAutoRestEnabled: Bool
    var previousPerformance: CompletedExercise?
    var onAddNote: () -> Void
    var onSwap: () -> Void
    var onViewHistory: () -> Void
    
    /// Displays the pinned note or the session-specific note.
    private var displayedNote: String? {
        if let sessionNote = exercise.notes, !sessionNote.isEmpty {
            return sessionNote
        }
        return PinnedNotesManager.shared.getPinnedNote(for: exercise.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise title and options menu
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(exercise.name)
                        .appFont(size: 20, weight: .bold)
                    Spacer()

                    // Rest timer display
                    if restTimer.timeRemaining > 0 {
                        Text(restTimer.formattedTime())
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .padding(8)
                            .background(.thinMaterial)
                            .cornerRadius(8)
                    } else {
                        Button {
                            restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds))
                        } label: {
                            Image(systemName: "timer")
                        }
                        .tint(.brandPrimary)
                    }
                    
                    // Exercise options menu
                    Menu {
                        Button("Add Warmup Sets") {
                            let newWarmupSet = ExerciseSet(isWarmup: true)
                            exercise.sets.insert(newWarmupSet, at: 0)
                        }
                        Button("Add/Edit Note", action: onAddNote)
                        Button("Swap Exercise", action: onSwap)
                            .disabled(exercise.alternatives?.isEmpty ?? true)
                        Button("View Demo & History", action: onViewHistory)
                        // This Toggle now correctly uses the $isAutoRestEnabled binding
                        Toggle("Auto-Rest Timer", isOn: $isAutoRestEnabled)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
                
                // Display for pinned or session notes
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

            // Switch to the correct view based on exercise type
            switch exercise.type {
            case .strength:
                StrengthExerciseView(exercise: $exercise, previousPerformance: previousPerformance, onSetComplete: {
                    // The closure now correctly reads the 'isAutoRestEnabled' value
                    if isAutoRestEnabled {
                        restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds))
                    }
                })
            case .cardio:
                CardioExerciseView(exercise: $exercise)
            case .flexibility:
                FlexibilityExerciseView(exercise: $exercise)
            }

            // "Add Set" button for all exercise types
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

/// The view for logging Strength sets (Weight & Reps).
private struct StrengthExerciseView: View {
    @Binding var exercise: RoutineExercise
    var previousPerformance: CompletedExercise?
    var onSetComplete: () -> Void
    
    var body: some View {
        VStack {
            // Header row
            HStack {
                Text("SET").frame(minWidth: 25, alignment: .leading)
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                Text("LBS").frame(maxWidth: .infinity, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            // Rows for each set
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                StrengthSetRow(
                    set: $exercise.sets[index],
                    setIndex: index + 1,
                    previousSet: previousPerformance?.sets.indices.contains(index) == true ? previousPerformance?.sets[index] : nil,
                    onComplete: onSetComplete
                )
            }
        }
    }
}

/// The view for logging Cardio sets (Distance & Time).
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
        }
    }
}

/// The view for logging Flexibility sets (Time).
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
        }
    }
}

/// A view for swapping the current exercise with an alternative.
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
                            
                            // Create new sets, blanking out old data
                            let newSets = exercise.sets.map { originalSet -> ExerciseSet in
                                return ExerciseSet(target: originalSet.target)
                            }
                            
                            // Perform the swap
                            exercise.name = alternativeName
                            exercise.sets = newSets
                            // Add the original exercise as an alternative
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

/// A single interactive row for a strength set.
private struct StrengthSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var previousSet: CompletedSet?
    var onComplete: () -> Void
    
    // Local state for the text fields
    @State private var weightInput: String
    @State private var repsInput: String
    @State private var isPersonalBest = false
    
    private let weightIncrement: Double = 2.5 // Increment for weight steppers

    init(set: Binding<ExerciseSet>, setIndex: Int, previousSet: CompletedSet?, onComplete: @escaping () -> Void) {
        self._set = set
        self.setIndex = setIndex
        self.previousSet = previousSet
        self.onComplete = onComplete
        
        // Initialize state from the binding
        self._weightInput = State(initialValue: set.wrappedValue.weight > 0 ? String(format: "%.1f", set.wrappedValue.weight) : "")
        self._repsInput = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        HStack {
            // Set number (e.g., "1" or "W" for warmup)
            Text(set.isWarmup ? "W" : "\(setIndex)")
                .frame(minWidth: 25, alignment: .leading)

            // Previous set button (Tap-to-fill)
            Button(action: fillFromPrevious) {
                Text(previousSet != nil ? "\(Int(previousSet!.weight)) lbs x \(previousSet!.reps)" : "No Prior Data")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(previousSet == nil ? .secondary : .brandPrimary) // Make it look tappable
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(previousSet == nil)

            // Weight stepper/field
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
                        // Update the binding when text changes
                        let newWeight = Double(weightInput) ?? 0
                        set.weight = newWeight
                        checkIfPersonalBest(newWeight: newWeight, newRps: set.reps)
                    }
                
                Button(action: { adjustWeight(by: weightIncrement) }) {
                    Image(systemName: "plus.circle")
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Reps stepper/field
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
                        // Update the binding when text changes
                        let newReps = Int(repsInput) ?? 0
                        set.reps = newReps
                        checkIfPersonalBest(newWeight: set.weight, newRps: newReps)
                    }
                
                Button(action: { adjustReps(by: 1) }) {
                    Image(systemName: "plus.circle")
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)


            // Checkmark and PR star
            HStack(spacing: 2) {
                if isPersonalBest {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                
                Button(action: {
                    set.isCompleted.toggle()
                    if set.isCompleted {
                        onComplete() // Trigger rest timer if enabled
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
        .foregroundColor(.brandPrimary) // Color for the stepper buttons
    }
    
    /// Fills the input fields with data from the previous workout.
    private func fillFromPrevious() {
        guard let prev = previousSet else { return }
        self.weightInput = String(format: "%.1f", prev.weight)
        self.repsInput = "\(prev.reps)"
        HapticManager.instance.feedback(.light)
    }
    
    /// Modifies the weight input via the stepper buttons.
    private func adjustWeight(by amount: Double) {
        let currentWeight = Double(weightInput) ?? 0
        let newWeight = max(0, currentWeight + amount)
        self.weightInput = String(format: "%.1f", newWeight)
        HapticManager.instance.feedback(.light)
    }
    
    /// Modifies the rep input via the stepper buttons.
    private func adjustReps(by amount: Int) {
        let currentReps = Int(repsInput) ?? 0
        let newReps = max(0, currentReps + amount)
        self.repsInput = "\(newReps)"
        HapticManager.instance.feedback(.light)
    }
    
    /// Checks if the current set beats the previous performance.
    private func checkIfPersonalBest(newWeight: Double, newRps: Int) {
        guard let previous = previousSet, newRps > 0, newWeight > 0 else {
            isPersonalBest = false
            return
        }
        
        // Logic for determining a new Personal Record
        if newWeight > previous.weight && newRps >= previous.reps {
            isPersonalBest = true
        } else if newWeight == previous.weight && newRps > previous.reps {
            isPersonalBest = true
        } else {
            isPersonalBest = false
        }
    }
}

/// A single interactive row for a cardio set.
private struct CardioSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int

    @State private var distanceInput: String
    @State private var timeInput: String
    
    init(set: Binding<ExerciseSet>, setIndex: Int) {
        self._set = set
        self.setIndex = setIndex
        self._distanceInput = State(initialValue: set.wrappedValue.distance > 0 ? "\(set.wrappedValue.distance)" : "")
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

/// A single interactive row for a flexibility set.
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
