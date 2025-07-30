import SwiftUI
import FirebaseFirestore

struct AIWorkoutGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutService: WorkoutService
    
    @State private var goal: String = ""
    @State private var daysPerWeek: Int = 3
    @State private var details: String = ""
    
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    
    @State private var isLoading = false
    @State private var generatedProgram: WorkoutProgram?

    var body: some View {
        NavigationView {
            VStack {
                if var program = generatedProgram {
                    GeneratedProgramPreviewView(program: program, onSave: {
                        program.startDate = Timestamp(date: startDate)
                        program.daysOfWeek = selectedDaysOfWeek
                        Task {
                            await workoutService.saveProgram(program)
                            dismiss()
                        }
                    })
                } else {
                    Form {
                        Section(header: Text("Primary Goal")) {
                            TextField("e.g., Build muscle, lose weight...", text: $goal)
                            Text("Tell Maia what your overall goal is, like building muscle, losing weight, increasing flexibility, or improving running for example.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Section(header: Text("Schedule")) {
                            Stepper("Workouts Per Week: \(daysPerWeek) days", value: $daysPerWeek, in: 2...6)
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            WeekDaySelector(selectedDays: $selectedDaysOfWeek)
                        }

                        Section(header: Text("Additional Details")) {
                            TextEditor(text: $details)
                                .frame(height: 120)
                            Text("Tell Maia about any other info, like what type of exercises you like, what you don't like, what equipment is available to you, etc.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            generatePlan()
                        } label: {
                            Label("Generate Program with AI", systemImage: "sparkles")
                        }
                        .disabled(isLoading || goal.isEmpty)
                    }
                }
            }
            .navigationTitle("AI Program Generator")
            .overlay(
                Group {
                    if isLoading {
                        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                        ProgressView("Generating your program...")
                    }
                }
            )
        }
    }
    
    private func generatePlan() {
        isLoading = true
        Task {
            let program = await workoutService.generateAIWorkoutPlan(goal: goal, daysPerWeek: daysPerWeek, details: details)
            self.generatedProgram = program
            isLoading = false
        }
    }
}

struct GeneratedProgramPreviewView: View {
    let program: WorkoutProgram
    var onSave: () -> Void

    var body: some View {
        VStack {
            List {
                Section(header: Text("Your New Program: \(program.name)")) {
                    ForEach(program.routines) { routine in
                        VStack(alignment: .leading) {
                            Text(routine.name).appFont(size: 17, weight: .bold)
                            ForEach(routine.exercises) { exercise in
                                Text("- \(exercise.name) (\(exercise.sets.count) sets)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            Button("Save Program", action: onSave)
                .buttonStyle(PrimaryButtonStyle())
                .padding()
        }
    }
}
