
import SwiftUI
import FirebaseAuth

struct WorkoutHistoryView: View {
    @StateObject var analyticsService = WorkoutAnalyticsService()
    @State private var logs: [WorkoutSessionLog] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoading {
                    ProgressView().padding(.top, 50)
                } else if logs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No Workout History").font(.title2).fontWeight(.bold)
                    }.padding(.top, 50)
                } else {
                    ForEach(logs) { log in
                        // Link to the same detailed view used by "Workout Complete"
                        NavigationLink(destination: WorkoutCompleteAnalyticsView(log: log)) {
                            WorkoutHistoryRow(log: log)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Workout History")
        .background(Color.backgroundPrimary)
        .onAppear {
            if logs.isEmpty {
                guard let uid = Auth.auth().currentUser?.uid else { return }
                Task {
                    self.logs = await analyticsService.fetchWorkoutHistory(userID: uid, limit: 50)
                    self.isLoading = false
                }
            }
        }
    }
}

struct WorkoutHistoryRow: View {
    let log: WorkoutSessionLog
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(log.date.dateValue().formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundColor(.secondary).textCase(.uppercase)
                let preview = log.completedExercises.prefix(2).map { $0.exerciseName }.joined(separator: ", ")
                Text(preview.isEmpty ? "Workout" : preview + (log.completedExercises.count > 2 ? "..." : "")).font(.headline).foregroundColor(.primary)
                HStack {
                    Label("\(log.completedExercises.count) Exercises", systemImage: "dumbbell.fill")
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary)
        }
        .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(12)
    }
}
