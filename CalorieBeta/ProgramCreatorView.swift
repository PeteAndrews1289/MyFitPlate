import SwiftUI
import FirebaseFirestore

struct ProgramCreatorView: View {
    @ObservedObject var workoutService: WorkoutService
    var programToEdit: WorkoutProgram?
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var selectedRoutineIDs: Set<String> = []
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = []

    private var isEditMode: Bool { programToEdit != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Program Details")) {
                    TextField("Program Name (e.g., 12 Week Strength)", text: $name)
                }

                Section(header: Text("Select Routines for this Program")) {
                    if workoutService.userRoutines.isEmpty {
                        Text("You haven't created any routines yet. Go back to the Train tab to create some first.")
                            .foregroundColor(.secondary)
                    } else {
                        List(workoutService.userRoutines) { routine in
                            Button(action: {
                                toggleRoutineSelection(routine.id)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(routine.name)
                                            .foregroundColor(.primary)
                                        Text("\(routine.exercises.count) exercises")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedRoutineIDs.contains(routine.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.brandPrimary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Schedule")) {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    WeekDaySelector(selectedDays: $selectedDaysOfWeek)
                }
            }
            .onAppear(perform: setupView)
            .navigationTitle(isEditMode ? "Edit Program" : "New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveProgram)
                        .disabled(name.isEmpty || selectedRoutineIDs.isEmpty || selectedDaysOfWeek.isEmpty)
                }
            }
        }
    }
    
    private func setupView() {
        if let program = programToEdit {
            name = program.name
            selectedRoutineIDs = Set(program.routines.map { $0.id })
            startDate = program.startDate?.dateValue() ?? Date()
            selectedDaysOfWeek = program.daysOfWeek ?? []
        }
    }

    private func toggleRoutineSelection(_ routineID: String) {
        if selectedRoutineIDs.contains(routineID) {
            selectedRoutineIDs.remove(routineID)
        } else {
            selectedRoutineIDs.insert(routineID)
        }
    }

    private func saveProgram() {
        let selectedRoutines = workoutService.userRoutines.filter { selectedRoutineIDs.contains($0.id) }
        
        let program = WorkoutProgram(
            id: programToEdit?.id ?? UUID().uuidString,
            userID: programToEdit?.userID ?? "", // This will be set in the service
            name: name,
            dateCreated: programToEdit?.dateCreated ?? Timestamp(date: Date()),
            routines: selectedRoutines,
            startDate: Timestamp(date: startDate),
            daysOfWeek: selectedDaysOfWeek,
            currentProgressIndex: programToEdit?.currentProgressIndex ?? 0
        )
        
        Task {
            await workoutService.saveProgram(program)
            dismiss()
        }
    }
}