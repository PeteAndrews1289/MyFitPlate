import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ProgramCreatorView: View {
    @ObservedObject var workoutService: WorkoutService
    var programToEdit: WorkoutProgram?
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var routines: [WorkoutRoutine] = []
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    
    @State private var routineToEdit: WorkoutRoutine?

    private var isEditMode: Bool { programToEdit != nil }

    var body: some View {
        Form {
            Section(header: Text("Program Details")) {
                TextField("Program Name (e.g., 12 Week Strength)", text: $name)
            }

            Section(header: Text("Routines / Days")) {
                RoutineSelectionList(
                    routines: $routines,
                    onEdit: { routine in
                        self.routineToEdit = routine
                    },
                    onDelete: { offsets in
                        self.routines.remove(atOffsets: offsets)
                    },
                    onAdd: {
                        let newRoutine = WorkoutRoutine(userID: Auth.auth().currentUser?.uid ?? "", name: "New Routine", dateCreated: Timestamp())
                        self.routines.append(newRoutine)
                    }
                )
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveProgram)
                    .disabled(name.isEmpty || routines.isEmpty || selectedDaysOfWeek.isEmpty)
            }
        }
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                onSave: { updatedRoutine in
                    if let index = self.routines.firstIndex(where: { $0.id == updatedRoutine.id }) {
                        self.routines[index] = updatedRoutine
                    }
                }
            )
        }
    }
    
    private func setupView() {
        if let program = programToEdit {
            name = program.name
            routines = program.routines.map { $0 }
            startDate = program.startDate?.dateValue() ?? Date()
            selectedDaysOfWeek = program.daysOfWeek ?? []
        }
    }

    private func saveProgram() {
        let program = WorkoutProgram(
            id: programToEdit?.id ?? UUID().uuidString,
            userID: programToEdit?.userID ?? "",
            name: name,
            dateCreated: programToEdit?.dateCreated ?? Timestamp(date: Date()),
            routines: self.routines,
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


private struct RoutineSelectionList: View {
    @Binding var routines: [WorkoutRoutine]
    var onEdit: (WorkoutRoutine) -> Void
    var onDelete: (IndexSet) -> Void
    var onAdd: () -> Void
    
    var body: some View {
        ForEach(routines) { routine in
            Button(action: { onEdit(routine) }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(routine.name.isEmpty ? "New Day / Routine" : routine.name)
                            .foregroundColor(routine.name.isEmpty ? .secondary : .primary)
                        Text("\(routine.exercises.count) exercises")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onDelete(perform: onDelete)
        
        Button("Add Day / Routine", action: onAdd)
    }
}
