import MyFitPlateCore

import SwiftUI

struct PastWorkoutDetailView: View {
    let exercise: LoggedExercise

    @StateObject private var workoutService = WorkoutService()
    @State private var sessionLog: WorkoutSessionLog?
    @State private var isLoading = true
    @State private var showingEditSheet = false
    @State private var editedExercise: LoggedExercise?
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) var dismiss

    private var displayedExercise: LoggedExercise { editedExercise ?? exercise }

    var body: some View {
        Group {
            if isLoading {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        AppScreenHeader(
                            eyebrow: "Training Evidence",
                            title: "Workout details",
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
                            eyebrow: displayedExercise.source == "HealthKit" ? "Apple Health" : "Manual Entry",
                            title: displayedExercise.source == "HealthKit" ? "Imported activity" : "Activity details",
                            subtitle: displayedExercise.source == "HealthKit"
                                ? "Corrections apply only to MyFitPlate. To remove this import, delete the original workout in Apple Health."
                                : "This entry has exercise totals but no recorded set-by-set session."
                        )

                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            AppSectionHeader(
                                title: displayedExercise.name,
                                subtitle: "Detailed trends become available when a workout is completed through the session player."
                            )

                            Button("Edit activity") {
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
            let original = displayedExercise
            AddExerciseView(exerciseToEdit: original) { userID, updated, completion in
                dailyLogService.exerciseLogStore.updateExerciseInLog(
                    for: userID, original: original, updated: updated
                ) { accepted in
                    if accepted, DIContainer.shared.authService.currentUserID == userID {
                        editedExercise = updated
                    }
                    completion(accepted)
                }
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
