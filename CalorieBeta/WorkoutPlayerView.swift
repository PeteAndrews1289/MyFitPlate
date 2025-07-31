import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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


struct WorkoutPlayerView: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var viewModel: WorkoutPlayerViewModel
    
    @State private var showingNoteEditor = false
    @State private var noteText = ""
    @State private var isNotePinned = false
    @State private var exerciseForNote: Binding<RoutineExercise>?
    
    @State private var showingHistoryFor: RoutineExercise?
    @State private var showingPlateCalculator = false
    
    
    @AppStorage("isAutoRestTimerEnabled") private var isAutoRestTimerEnabled = false
    
    struct SwappableExercise: Identifiable {
        let id: String
        let binding: Binding<RoutineExercise>
    }
    @State private var swappableExercise: SwappableExercise?
    
    var onWorkoutComplete: () -> Void

    init(routine: WorkoutRoutine, workoutService: WorkoutService, goalSettings: GoalSettings, dailyLogService: DailyLogService, onWorkoutComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: WorkoutPlayerViewModel(routine: routine, workoutService: workoutService, goalSettings: goalSettings, dailyLogService: dailyLogService))
        self.onWorkoutComplete = onWorkoutComplete
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text(viewModel.totalWorkoutTimer.formattedTime())
                        .padding(8)
                        .background(.thinMaterial)
                        .cornerRadius(8)
                    
                    Spacer()
                    
                    Text(viewModel.routine.name)
                        .appFont(size: 18, weight: .bold)
                    
                    Spacer()
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach($viewModel.routine.exercises) { $exercise in
                            ExerciseCardView(
                                exercise: $exercise,
                                restTimer: viewModel.restTimer,
                                isAutoRestEnabled: $isAutoRestTimerEnabled,
                                previousPerformance: viewModel.previousPerformance[exercise.name],
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
                        .onMove(perform: viewModel.moveExercise)

                        Button("Mark Workout as Complete") {
                            viewModel.logAllCompletedExercises()
                            viewModel.stopTimers()
                            onWorkoutComplete()
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("completeWorkoutButton")
                        .padding(.top)
                    }
                    .padding()
                }

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
            viewModel.startTimers()
            viewModel.loadPreviousPerformance()
        }
        .onDisappear {
            Task { await viewModel.saveRoutine() }
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
    
}

struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    @Binding var isAutoRestEnabled: Bool
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
                            restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds))
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
                        Button("Reorder Exercises", action: {})
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
                StrengthExerciseView(exercise: $exercise, previousPerformance: previousPerformance, onSetComplete: {
                    if isAutoRestEnabled {
                        restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds))
                    }
                })
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
    var onSetComplete: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(maxWidth: .infinity, alignment: .leading)
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
                    onComplete: onSetComplete
                )
            }
        }
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
        }
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
        }
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

struct StrengthSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var previousSet: CompletedSet?
    var onComplete: () -> Void
    
    @State private var weightInput: String
    @State private var repsInput: String
    @State private var isPersonalBest = false

    init(set: Binding<ExerciseSet>, setIndex: Int, previousSet: CompletedSet?, onComplete: @escaping () -> Void) {
        self._set = set
        self.setIndex = setIndex
        self.previousSet = previousSet
        self.onComplete = onComplete
        self._weightInput = State(initialValue: set.wrappedValue.weight > 0 ? String(format: "%.1f", set.wrappedValue.weight) : "")
        self._repsInput = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        HStack {
            Text(set.isWarmup ? "W" : "\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.target ?? (previousSet != nil ? "\(Int(previousSet!.weight))lb x \(previousSet!.reps)" : "-"))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("0", text: $weightInput)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: weightInput) { newValue in
                    let newWeight = Double(newValue) ?? 0
                    set.weight = newWeight
                    checkIfPersonalBest(newWeight: newWeight, newRps: set.reps)
                }

            TextField("0", text: $repsInput)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: repsInput) { newValue in
                    let newReps = Int(newValue) ?? 0
                    set.reps = newReps
                    checkIfPersonalBest(newWeight: set.weight, newRps: newReps)
                }

            HStack(spacing: 2) {
                if isPersonalBest {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
                
                Button(action: {
                    set.isCompleted.toggle()
                    if set.isCompleted {
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

struct CardioSetRow: View {
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
                .onChange(of: distanceInput) { newValue in
                    set.distance = Double(newValue) ?? 0
                }

            TextField("min", text: $timeInput)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: timeInput) { newValue in
                    set.durationInSeconds = (Int(newValue) ?? 0) * 60
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

struct FlexibilitySetRow: View {
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
                .onChange(of: timeInput) { newValue in
                    set.durationInSeconds = Int(newValue) ?? 0
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
