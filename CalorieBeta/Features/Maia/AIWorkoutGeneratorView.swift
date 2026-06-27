import SwiftUI
import FirebaseFirestore

struct AIWorkoutGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings // Access user's goal settings

    // State for the generator form
    @State private var goal: String = ""
    @State private var daysPerWeek: Int = 3
    @State private var fitnessLevel: FitnessLevel = .beginner
    @State private var equipment: Equipment = .fullGym
    @State private var details: String = "" // Optional notes
    
    // State for scheduling
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    
    // View state
    @State private var isLoading = false
    @State private var generatedProgram: WorkoutProgram?
    @State private var errorMessage: String?

    // Enums to provide structured options in the Pickers
    enum FitnessLevel: String, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        var id: Self { self }
    }

    enum Equipment: String, CaseIterable, Identifiable {
        case fullGym = "Full Gym"
        case dumbbellsOnly = "Dumbbells Only"
        case bodyweight = "Bodyweight Only"
        var id: Self { self }
    }

    var body: some View {
        NavigationView {
            VStack {
                // If a program has been generated, show the preview
                if var program = generatedProgram {
                    GeneratedProgramPreviewView(program: program, onSave: {
                        // Assign the schedule to the program before saving
                        program.startDate = Timestamp(date: startDate)
                        program.daysOfWeek = selectedDaysOfWeek
                        Task {
                            await workoutService.saveProgram(program)
                            dismiss()
                        }
                    })
                } else {
                    // Otherwise, show the form to generate a program
                    Form {
                        if let errorMessage = errorMessage {
                            Section {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                            }
                        }

                        Section(header: Text("Primary Goal")) {
                            TextField("e.g., Build muscle, lose fat...", text: $goal)
                            Text("This is your main objective. Be specific!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Section for user's fitness level and equipment
                        Section(header: Text("Your Profile")) {
                            Picker("Fitness Level", selection: $fitnessLevel) {
                                ForEach(FitnessLevel.allCases) { level in
                                    Text(level.rawValue).tag(level)
                                }
                            }
                            
                            Picker("Available Equipment", selection: $equipment) {
                                ForEach(Equipment.allCases) { eq in
                                    Text(eq.rawValue).tag(eq)
                                }
                            }
                        }
                        
                        Section(header: Text("Schedule")) {
                            Stepper("Workouts Per Week: \(daysPerWeek) days", value: $daysPerWeek, in: 2...6)
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            WeekDaySelector(selectedDays: $selectedDaysOfWeek)
                        }

                        Section(header: Text("Additional Preferences (Optional)")) {
                            TextEditor(text: $details)
                                .frame(height: 100)
                            Text("Add any specific notes for Maia. e.g., 'I have a bad knee', 'I hate running', 'Focus on 30-minute workouts'.")
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
                // Loading overlay
                Group {
                    if isLoading {
                        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                        VStack {
                            ProgressView()
                            Text("Generating your program...")
                                .foregroundColor(.white)
                                .padding()
                        }
                        .padding(20)
                        .background(.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                }
            )
        }
    }
    
    /// Calls the WorkoutService to generate a plan using the form data.
    private func generatePlan() {
        isLoading = true
        errorMessage = nil
        Task {
            // Pass all the structured data to the service
            let result = await workoutService.generateAIWorkoutPlan(
                goal: goal,
                daysPerWeek: daysPerWeek,
                fitnessLevel: fitnessLevel.rawValue,
                equipment: equipment.rawValue,
                details: details,
                goalSettings: goalSettings
            )
            
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

/// A view to show the AI-generated program before the user saves it.
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

/// A reusable component for selecting days of the week.
struct WeekDaySelector: View {
    @Binding var selectedDays: [Int]
    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack {
            ForEach(0..<7) { index in
                let day = index + 1 // Use 1 (Sun) to 7 (Sat) for Calendar component
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
