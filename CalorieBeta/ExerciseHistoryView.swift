import SwiftUI

struct ExerciseHistoryView: View {
    let exerciseName: String
    @StateObject private var viewModel: ExerciseHistoryViewModel
    
    init(exerciseName: String) {
        self.exerciseName = exerciseName
        _viewModel = StateObject(wrappedValue: ExerciseHistoryViewModel(exerciseName: exerciseName))
    }
    
    var body: some View {
        NavigationView {
            content
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading History...")
        } else if viewModel.history.isEmpty {
            Text("No history found for \(exerciseName).")
                .foregroundColor(.secondary)
                .padding()
        } else {
            List(viewModel.history) { session in
                SessionRowView(session: session)
            }
        }
    }
}

private struct SessionRowView: View {
    let session: ExerciseHistoryViewModel.ExerciseHistorySession
    
    var body: some View {
        Section(header: Text(session.date, style: .date)) {
            ForEach(Array(session.sets.enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("Set \(index + 1)")
                    Spacer()
                    Text("\(String(format: "%.1f", set.weight)) lbs x \(set.reps) reps")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}


@MainActor
class ExerciseHistoryViewModel: ObservableObject {
    @Published var history: [ExerciseHistorySession] = []
    @Published var isLoading = false
    
    private let workoutService = WorkoutService()
    
    struct ExerciseHistorySession: Identifiable {
        let id = UUID()
        let date: Date
        let sets: [CompletedSet]
    }
    
    init(exerciseName: String) {
        fetchHistory(for: exerciseName)
    }
    
    func fetchHistory(for exerciseName: String) {
        isLoading = true
        Task {
            let logs = await workoutService.fetchHistory(for: exerciseName)
            
            self.history = logs.compactMap { log -> ExerciseHistorySession? in
                if let exercise = log.completedExercises.first(where: { $0.exerciseName == exerciseName }) {
                    return ExerciseHistorySession(date: log.date.dateValue(), sets: exercise.sets)
                }
                return nil
            }
            self.isLoading = false
        }
    }
}
