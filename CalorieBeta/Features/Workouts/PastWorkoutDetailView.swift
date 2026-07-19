import MyFitPlateCore

import SwiftUI

struct PastWorkoutDetailView: View {
    let exercise: LoggedExercise

    @StateObject private var workoutService = WorkoutService()
    @State private var sessionLog: WorkoutSessionLog?
    @State private var isLoading = true
    @State private var showingEditSheet = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            if isLoading {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        AppScreenHeader(
                            eyebrow: "Training Evidence",
                            title: "Workout Details",
                            subtitle: "Retrieving the completed session."
                        )

                        HStack(spacing: AppSpacing.row) {
                            ProgressView()
                                .tint(AppPalette.brand)

                            Text("Loading set history and performance details")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .appSurface(.quiet)
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                }
            } else if let log = sessionLog {
                WorkoutCompleteAnalyticsView(log: log)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        AppScreenHeader(
                            eyebrow: "Manual Entry",
                            title: "Simple Workout Log",
                            subtitle: "This entry has exercise totals but no recorded set-by-set session."
                        )

                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            AppSectionHeader(
                                title: exercise.name,
                                subtitle: "Detailed trends become available when a workout is completed through the session player."
                            )

                            Button("Edit Entry") {
                                showingEditSheet = true
                            }
                            .buttonStyle(AppActionButtonStyle(.primary))
                            .accessibilityIdentifier("past_workout_edit_entry")
                        }
                        .appSurface(.quiet)
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.section)
                }
            }
        }
        .accessibilityIdentifier("past_workout_detail")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle("Workout")
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
        .task {
            await loadSessionLog()
        }
    }

    @MainActor
    private func loadSessionLog() async {
        guard let sessionID = exercise.sessionID, let workoutID = exercise.workoutID else {
            isLoading = false
            return
        }

        let result = await workoutService.fetchWorkoutSessionLog(workoutID: workoutID, sessionID: sessionID)
        if case .success(let log) = result {
            sessionLog = log
        }
        isLoading = false
    }
}
