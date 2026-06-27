import SwiftUI

struct PastWorkoutDetailView: View {
    let exercise: LoggedExercise // The entry point from history/log
    
    @StateObject private var workoutService = WorkoutService()
    @State private var sessionLog: WorkoutSessionLog?
    @State private var isLoading = true
    @State private var showingEditSheet = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Retrieving full workout details...")
                        .foregroundColor(.secondary)
                        .appFont(size: 16)
                }
            } else if let log = sessionLog {
                // SUCCESS: Pass the fetched log to the analytics view
                WorkoutCompleteAnalyticsView(log: log)
            } else {
                // FAILURE: Could not find the detailed session log (maybe it was a manual entry)
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .appFont(size: 60)
                        .foregroundColor(.orange)
                    Text("Simple Log Entry")
                        .appFont(size: 24, weight: .bold)
                    Text("This exercise was logged manually, so detailed set analytics and trends aren't available.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .appFont(size: 16)
                        .padding(.horizontal)
                    
                    Button("Edit Entry") {
                        showingEditSheet = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddExerciseView(exerciseToEdit: exercise) { _ in
                // Callback handling if needed
            }
        }
        .onAppear {
            loadSessionLog()
        }
    }
    
    private func loadSessionLog() {
        guard let sessionID = exercise.sessionID, let workoutID = exercise.workoutID else {
            // No IDs means it was a manual "quick add"
            isLoading = false
            return
        }
        
        Task {
            let result = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)
            if case .success(let log) = result {
                self.sessionLog = log
            }
            self.isLoading = false
        }
    }
}
