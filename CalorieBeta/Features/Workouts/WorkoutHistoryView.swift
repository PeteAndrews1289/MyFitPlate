
import SwiftUI
import FirebaseAuth

struct WorkoutHistoryView: View {
    @StateObject var analyticsService = WorkoutAnalyticsService()
    @State private var logs: [WorkoutSessionLog] = []
    @State private var isLoading = true

    private var totalLoggedVolume: Double {
        logs.reduce(0) { partial, log in
            partial + log.completedExercises.reduce(0) { exerciseSum, exercise in
                exerciseSum + exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }
    }

    private var totalLoggedSets: Int {
        logs.reduce(0) { partial, log in
            partial + log.completedExercises.reduce(0) { $0 + $1.sets.count }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.brandPrimary)
                        Text("Loading workout history")
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if logs.isEmpty {
                    WorkoutHistoryEmptyState()
                        .padding(.top, 50)
                } else {
                    WorkoutHistoryHeaderCard(
                        sessionCount: logs.count,
                        totalVolume: totalLoggedVolume,
                        totalSets: totalLoggedSets,
                        latestDate: logs.first?.date.dateValue()
                    )

                    ForEach(logs) { log in
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

    private var totalVolume: Double {
        log.completedExercises.reduce(0) { exerciseSum, exercise in
            exerciseSum + exercise.sets.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }

    private var completedSetCount: Int {
        log.completedExercises.reduce(0) { $0 + $1.sets.count }
    }

    private var exercisePreview: String {
        let preview = log.completedExercises.prefix(2).map { $0.exerciseName }.joined(separator: ", ")
        guard !preview.isEmpty else { return "Workout" }
        return preview + (log.completedExercises.count > 2 ? "..." : "")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 3) {
                Text(log.date.dateValue().formatted(.dateTime.day()))
                    .appFont(size: 21, weight: .black)
                    .foregroundColor(.brandPrimary)
                Text(log.date.dateValue().formatted(.dateTime.month(.abbreviated)))
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .textCase(.uppercase)
            }
            .frame(width: 48, height: 56)
            .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercisePreview)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(log.date.dateValue().formatted(date: .omitted, time: .shortened))
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                HStack(spacing: 8) {
                    WorkoutHistoryPill(title: "\(log.completedExercises.count)", subtitle: "exercises", icon: "dumbbell.fill", color: .brandPrimary)
                    WorkoutHistoryPill(title: "\(completedSetCount)", subtitle: "sets", icon: "checkmark.seal.fill", color: .accentPositive)

                    if totalVolume > 0 {
                        WorkoutHistoryPill(title: "\(Int(totalVolume))", subtitle: "lbs", icon: "chart.bar.fill", color: .orange)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding()
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WorkoutHistoryHeaderCard: View {
    let sessionCount: Int
    let totalVolume: Double
    let totalSets: Int
    let latestDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Log")
                        .appFont(size: 24, weight: .black)
                        .foregroundColor(.textPrimary)

                    Text(latestDate.map { "Last workout: \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No recent workouts")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }

            HStack(spacing: 10) {
                WorkoutHistoryMetric(title: "Sessions", value: "\(sessionCount)", color: .brandPrimary)
                WorkoutHistoryMetric(title: "Sets", value: "\(totalSets)", color: .accentPositive)
                WorkoutHistoryMetric(title: "Volume", value: totalVolume > 0 ? "\(Int(totalVolume))" : "0", color: .orange)
            }
        }
        .asCard()
    }
}

private struct WorkoutHistoryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct WorkoutHistoryPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .appFont(size: 11, weight: .bold)
            Text(subtitle)
                .appFont(size: 10, weight: .semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }
}

private struct WorkoutHistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.brandPrimary)
                .frame(width: 74, height: 74)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No Workout History")
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Finish a routine and your training log will start filling in here.")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }
}
