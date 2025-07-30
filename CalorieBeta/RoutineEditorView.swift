import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var workoutService: WorkoutService
    var routine: WorkoutRoutine?
    
    @State private var name: String = ""
    @State private var exercises: [RoutineExercise] = []
    
    @State private var showingSetInput = false
    @State private var exerciseIndex: Int? = nil
    @State private var newSetReps: Int = 0
    @State private var newSetWeight: Double = 0.0
    
    @State private var setIndex: Int? = nil
    
    @State private var showingExercisePicker = false
    @State private var exerciseList: [String] = [
        "Bodyweight Push-ups", "Bodyweight Squats", "Bodyweight Lunges", "Bodyweight Planks", "Bodyweight Pull-ups", "Bodyweight Chin-ups", "Bodyweight Dips", "Bodyweight Burpees", "Bodyweight Sit-ups", "Bodyweight Crunches", "Bodyweight Leg Raises", "Bodyweight Glute Bridges", "Bodyweight Hip Thrusts", "Bodyweight Calf Raises", "Dumbbell Bench Press", "Dumbbell Incline Press", "Dumbbell Overhead Press", "Dumbbell Arndold Press", "Dumbbell Chest Fly", "Dumbbell Reverse Fly", "Dumbbell Bent-over Row", "Dumbbell Renegade Row", "Dumbbell Bicep Curl", "Dumbbell Hammer Curl", "Dumbbell Concentration Curl", "Dumbbell Triceps Extension", "Dumbbell Triceps Kickbacks", "Dumbbell Goblet Squat", "Dumbbell Front Squat", "Dumbbell Lunges", "Dumbbell Romanian Deadlift", "Dumbbell Lateral Raises", "Dumbbell Shrugs", "Barbell Back Squat", "Barbell Front Squat", "Barbell Zercher Squat", "Barbell Conventional Deadlift", "Barbell Sumo Deadlift", "Barbell Romanian Deadlift", "Barbell Bench Press", "Barbell Overhead Press", "Barbell Push Press", "Barbell Bent-over Row", "Barbell Pendlay Row", "Barbell Bicep Curl", "Barbell Hip Thrust", "Barbell Good Mornings", "Cable Lat Pulldowns", "Cable Rows", "Cable Chest Fly", "Cable Crossover", "Cable Triceps Pushdowns", "Cable Bicep Curls", "Cable Face Pulls", "Cable Crunches", "Cable Wood Chops", "Cable Leg Kickbacks", "Cable Lateral Raises", "Kettlebell Swings", "Kettlebell Goblet Squats", "Kettlebell Turkish Get-ups", "Kettlebell Snatches", "Leg Press Machine", "Leg Extension Machine", "Leg Curl Machine", "Hack Squat Machine", "Calf Raise Machine", "Assisted Pull-up Machine", "Assisted Dip Machine", "Back Extension Bench", "Hyperextension Bench", "Abdominal Crunch Machine", "Medicine Ball Slams", "Medicine Ball Russian Twists", "Medicine Wall Balls"]
    
    var body: some View {
        Form {
            Section(header: Text("Routine Info")){
                TextField("Routine Name", text: $name)
            }
            Section(header: Text("Exercises")){
                ForEach(exercises.indices, id: \.self) { index in
                    DisclosureGroup(exercises[index].name){
                        Stepper("Rest Time: \(exercises[index].restTimeInSeconds)s", value: $exercises[index].restTimeInSeconds, in: 0...300, step: 15)
                        ForEach(exercises[index].sets.indices, id: \.self){ sIndex in
                            let set = exercises[index].sets[sIndex]
                            HStack{
                                Text("Reps: \(set.reps)")
                                Spacer()
                                Text("Weight: \(set.weight, specifier: "%.1f") lbs")
                                Spacer()
                                Button(role: .destructive){
                                    deleteSet(at: index, setIndex: sIndex)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                exerciseIndex = index
                                setIndex = sIndex
                                let set = exercises[index].sets[sIndex]
                                newSetReps = set.reps
                                newSetWeight = set.weight
                                showingSetInput = true
                            }
                        }
                        
                        Button("Add Set"){
                            exerciseIndex = index
                            newSetReps = 0
                            newSetWeight = 0.0
                            showingSetInput = true
                        }
                    }
                }
                .onDelete{ indexSet in
                    if let i = indexSet.first {
                        exercises.remove(at: i)
                    }
                }
                Button("Add Exercise"){
                    showingExercisePicker = true
                }
            }
            
            Section{
                Button("Save Routine", action: saveRoutine)
                    .disabled(name.isEmpty || exercises.isEmpty)
            }
        }
        .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
        .onAppear {
            if let routine = routine {
                self.name = routine.name
                self.exercises = routine.exercises
            }
        }
        .sheet(isPresented: $showingExercisePicker){
            ExercisePickerView(exerciseList: exerciseList){ selected in
                addExercise(named: selected)
                showingExercisePicker = false
            }
        }
        .sheet(isPresented: $showingSetInput){
            SetInputView(reps: $newSetReps,
                         weight: $newSetWeight,
                         onConfirm: {
                if let eIndex = exerciseIndex{
                    let set = ExerciseSet(reps: newSetReps, weight: newSetWeight)
                    if let sIndex = setIndex {
                        editSet(at: eIndex, setIndex: sIndex, newSet: set)
                    }else{
                        addSet(at: eIndex, newSet: set)
                    }
                    showingSetInput = false
                    exerciseIndex = nil
                    setIndex = nil
                }
            },
                         onCancel: {
                            showingSetInput = false
                        })
        }
    }
    
    private func addExercise(named name: String){
        let newExercise = RoutineExercise(name: name)
        exercises.append(newExercise)
    }
    
    private func addSet(at index: Int, newSet: ExerciseSet){
        guard exercises.indices.contains(index) else{ return }
        var exercise = exercises[index]
        exercise.sets.append(newSet)
        exercises[index] = exercise
    }
    
    private func saveRoutine(){
        guard let userID = Auth.auth().currentUser?.uid else{
            print("User not logged in.")
            return
        }
        
        let newRoutine = WorkoutRoutine(
            id: routine?.id ?? UUID().uuidString,
            userID: userID,
            name: name,
            dateCreated: routine?.dateCreated ?? Timestamp(date: Date()),
            exercises: exercises)
        
        Task {
            do {
                try await workoutService.saveRoutine(newRoutine)
                dismiss()
            } catch {
                print("Error saving routine: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteSet(at exerciseIndex: Int, setIndex: Int){
        guard exercises.indices.contains(exerciseIndex),
              exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        
        exercises[exerciseIndex].sets.remove(at: setIndex)
    }
    
    private func editSet(at exerciseIndex: Int, setIndex: Int, newSet: ExerciseSet){
        guard exercises.indices.contains(exerciseIndex),
              exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        
        exercises[exerciseIndex].sets[setIndex] = newSet
    }
}

struct ExercisePickerView: View{
    var exerciseList: [String]
    var onSelect: (String) -> Void
    
    var body: some View {
        NavigationView{
            List(exerciseList, id: \.self){ exercise in
                Button(exercise){
                    onSelect(exercise)
                }
            }
            .navigationTitle("Select Exercise")
        }
    }
}

struct SetInputView: View{
    @Binding var reps: Int
    @Binding var weight: Double
    var onConfirm: () -> Void
    var onCancel: () -> Void
    
    var body: some View{
        NavigationView{
            Form{
                Stepper("Reps: \(reps)", value: $reps, in: 0...50)
                Stepper("Weight: \(weight, specifier: "%.1f") lbs", value: $weight, in: 0...500)
            }
            .navigationTitle("New Set")
            .toolbar{
                ToolbarItem(placement: .confirmationAction){
                    Button("Add", action: onConfirm)
                }
                ToolbarItem(placement: .cancellationAction){
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
