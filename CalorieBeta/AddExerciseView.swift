import SwiftUI

struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @State private var exerciseName: String = ""
    @State private var duration: String = ""
    @State private var caloriesBurned: String = ""
    @State private var selectedDate: Date = Date()

    var exerciseToEdit: LoggedExercise?
    var onSave: (LoggedExercise) -> Void
    
    @State private var isEditing: Bool = false
    @State private var alertMessage: String? = nil
    @State private var showingAlert = false

    init(exerciseToEdit: LoggedExercise? = nil, onSave: @escaping (LoggedExercise) -> Void) {
        self.exerciseToEdit = exerciseToEdit
        self.onSave = onSave
        
        if let exercise = exerciseToEdit {
            _exerciseName = State(initialValue: exercise.name)
            _duration = State(initialValue: exercise.durationMinutes != nil ? "\(exercise.durationMinutes!)" : "")
            _caloriesBurned = State(initialValue: "\(Int(exercise.caloriesBurned))")
            _selectedDate = State(initialValue: exercise.date)
            _isEditing = State(initialValue: true)
        } else {
             _exerciseName = State(initialValue: "")
             _duration = State(initialValue: "")
             _caloriesBurned = State(initialValue: "")
             _selectedDate = State(initialValue: Date())
             _isEditing = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    TextField("Exercise Name (e.g., Running)", text: $exerciseName)
                    HStack {
                        TextField("Duration (minutes)", text: $duration)
                            .keyboardType(.numberPad)
                        Text("min")
                    }
                    HStack {
                        TextField("Calories Burned", text: $caloriesBurned)
                            .keyboardType(.numberPad)
                        Text("kcal")
                    }
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                }

                Button(action: saveExercise) {
                    Text(isEditing ? "Update Exercise" : "Log Exercise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(exerciseName.isEmpty || caloriesBurned.isEmpty)
            }
            .navigationTitle(isEditing ? "Edit Exercise" : "Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Input Error", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func saveExercise() {
        guard !exerciseName.isEmpty else {
            alertMessage = "Please enter an exercise name."
            showingAlert = true
            return
        }
        guard let calories = Double(caloriesBurned), calories > 0 else {
            alertMessage = "Please enter valid calories burned (must be a number greater than 0)."
            showingAlert = true
            return
        }
        let durationMinutes = Int(duration)

        if let durationVal = durationMinutes, durationVal <= 0 && !duration.isEmpty {
            alertMessage = "Duration must be a positive number if entered."
            showingAlert = true
            return
        }

        let exercise = LoggedExercise(
            id: exerciseToEdit?.id ?? UUID().uuidString,
            name: exerciseName,
            durationMinutes: durationMinutes,
            caloriesBurned: calories,
            date: selectedDate,
            source: exerciseToEdit?.source ?? "manual"
        )
        onSave(exercise)
        dismiss()
    }
}
