import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RoutineEditorView: View {
    @ObservedObject var workoutService: WorkoutService
    var onSave: (WorkoutRoutine) -> Void
    
    @Environment(\.dismiss) private var dismiss

    @State private var editableRoutine: WorkoutRoutine
    @State private var showingExercisePicker = false
    @State private var exerciseToEdit: RoutineExercise?

    init(workoutService: WorkoutService, routine: WorkoutRoutine, onSave: @escaping (WorkoutRoutine) -> Void) {
        self.workoutService = workoutService
        self._editableRoutine = State(initialValue: routine)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Routine Name")){
                    TextField("e.g., Push Day, Leg Day", text: $editableRoutine.name)
                }
                
                Section(header: Text("Exercises")){
                    ForEach(editableRoutine.exercises) { exercise in
                        Button(action: {
                            self.exerciseToEdit = exercise
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                        .appFont(size: 16, weight: .medium)
                                    Text("\(exercise.targetSets) sets x \(exercise.targetReps) reps")
                                        .appFont(size: 12)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                     .font(.caption.weight(.bold))
                                     .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .onMove(perform: moveExercise)
                    .onDelete(perform: deleteExercise)
                    
                    Button("Add Exercise"){
                        showingExercisePicker = true
                    }
                }
            }
            .navigationTitle(editableRoutine.name.isEmpty ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editableRoutine)
                        dismiss()
                    }
                    .disabled(editableRoutine.name.isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker){
                ExercisePickerView { selectedExerciseName in
                    addExercise(named: selectedExerciseName)
                    showingExercisePicker = false
                }
            }
            .sheet(item: $exerciseToEdit) { exercise in
                 ExerciseSetEditorView(
                     exercise: exercise,
                     onSave: { updatedExercise in
                         if let index = editableRoutine.exercises.firstIndex(where: { $0.id == updatedExercise.id }) {
                             editableRoutine.exercises[index] = updatedExercise
                         }
                     }
                 )
            }
        }
    }
    
    private func addExercise(named name: String){
        var newExercise = RoutineExercise(name: name, targetSets: 3)
        newExercise.sets = Array(repeating: ExerciseSet(), count: newExercise.targetSets)
        editableRoutine.exercises.append(newExercise)
    }
    
    private func deleteExercise(at offsets: IndexSet) {
        editableRoutine.exercises.remove(atOffsets: offsets)
    }
    
    private func moveExercise(from source: IndexSet, to destination: Int) {
        editableRoutine.exercises.move(fromOffsets: source, toOffset: destination)
    }
}

struct ExerciseSetEditorView: View {
    @State private var editableExercise: RoutineExercise
    var onSave: (RoutineExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    init(exercise: RoutineExercise, onSave: @escaping (RoutineExercise) -> Void) {
        self._editableExercise = State(initialValue: exercise)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Configuration")) {
                    Stepper("Number of Sets: \(editableExercise.targetSets)", value: $editableExercise.targetSets, in: 1...15) { _ in
                        updateSetCount()
                    }
                    HStack {
                        Text("Target Reps")
                        Spacer()
                        TextField("e.g., 8-12", text: $editableExercise.targetReps)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper("Rest Time: \(editableExercise.restTimeInSeconds)s", value: $editableExercise.restTimeInSeconds, in: 0...300, step: 15)
                }
            }
            .navigationTitle(editableExercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editableExercise)
                        dismiss()
                    }
                }
            }
        }
    }

    private func updateSetCount() {
        let currentSetCount = editableExercise.sets.count
        let targetSetCount = editableExercise.targetSets
        
        if targetSetCount > currentSetCount {
            let setsToAdd = targetSetCount - currentSetCount
            for _ in 0..<setsToAdd {
                editableExercise.sets.append(ExerciseSet())
            }
        } else if targetSetCount < currentSetCount {
            editableExercise.sets.removeLast(currentSetCount - targetSetCount)
        }
    }
}

struct ExercisePickerView: View {
    @State private var searchText = ""
    var onSelect: (String) -> Void
    
    private let categorizedExercises = ExerciseList.categorizedExercises
    
    private var filteredCategories: [String: [String]] {
        if searchText.isEmpty {
            return categorizedExercises
        }
        var filtered: [String: [String]] = [:]
        for (category, exercises) in categorizedExercises {
            let matchingExercises = exercises.filter { $0.localizedCaseInsensitiveContains(searchText) }
            if !matchingExercises.isEmpty {
                filtered[category] = matchingExercises
            }
        }
        return filtered
    }
    
    private var sortedCategoryKeys: [String] {
        filteredCategories.keys.sorted()
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(sortedCategoryKeys, id: \.self) { category in
                    Section(header: Text(category)) {
                        ForEach(filteredCategories[category]!, id: \.self) { exercise in
                            Button(exercise) {
                                onSelect(exercise)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarItems(trailing: Button("Done") {
            })
        }
    }
}
