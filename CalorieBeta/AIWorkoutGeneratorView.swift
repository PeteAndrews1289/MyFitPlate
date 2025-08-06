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
    @State private var errorMessage: String?

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
                        if let errorMessage = errorMessage {
                            Section {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                            }
                        }

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
        errorMessage = nil
        Task {
            let result = await workoutService.generateAIWorkoutPlan(goal: goal, daysPerWeek: daysPerWeek, details: details)
            isLoading = false
            switch result {
            case .success(let program):
                self.generatedProgram = program
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
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

struct WeekDaySelector: View {
    @Binding var selectedDays: [Int]
    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack {
            ForEach(0..<7) { index in
                let day = index + 1
                Text(days[index])
                    .fontWeight(.bold)
                    .foregroundColor(selectedDays.contains(day) ? .white : .primary)
                    .frame(width: 35, height: 35)
                    .background(
                        Circle().fill(selectedDays.contains(day) ? Color.brandPrimary : Color.gray.opacity(0.2))
                    )
                    .onTapGesture {
                        if let index = selectedDays.firstIndex(of: day) {
                            selectedDays.remove(at: index)
                        } else {
                            selectedDays.append(day)
                        }
                    }
            }
        }
    }
}
