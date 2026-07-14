import MyFitPlateCore

import SwiftUI

struct RoutineEditorView: View {
    @ObservedObject var workoutService: WorkoutService
    @StateObject private var viewModel: RoutineEditorViewModel

    @Environment(\.dismiss) private var dismiss

    init(workoutService: WorkoutService, routine: WorkoutRoutine, onSave: @escaping (WorkoutRoutine) -> Void) {
        self.workoutService = workoutService
        self._viewModel = StateObject(wrappedValue: RoutineEditorViewModel(routine: routine, onSave: onSave))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    RoutineEditorHeaderCard(
                        routineName: viewModel.routineName,
                        exerciseCount: viewModel.exercises.count,
                        setCount: viewModel.totalSetCount,
                        estimatedMinutes: viewModel.estimatedMinutes,
                        exercises: viewModel.exercises
                    )

                    RoutineBasicsCard(
                        routineName: $viewModel.routineName,
                        routineNotes: $viewModel.routineNotes
                    )
                    .accessibilityIdentifier("routine_builder_details")

                    RoutineTemplateStrip(
                        templates: RoutineEditorTemplate.templates,
                        onApply: { viewModel.applyTemplate($0) }
                    )
                    .accessibilityIdentifier("routine_builder_templates")

                    RoutineExerciseBuilderCard(
                        exercises: viewModel.exercises,
                        onAddExercise: { viewModel.showingExercisePicker = true },
                        onEdit: { viewModel.exerciseToEdit = $0 },
                        onDuplicate: { viewModel.duplicateExercise($0) },
                        onDelete: { viewModel.deleteExercise($0) },
                        onMove: { viewModel.moveExercise($0, direction: $1) }
                    )
                    .accessibilityIdentifier("routine_builder_exercises")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .accessibilityIdentifier("routine_builder")
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(viewModel.routineName.trimmed.isEmpty ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(AppPalette.text)
                    .accessibilityLabel("Close routine editor")
                    .accessibilityIdentifier("routine_builder_close")
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button(action: saveAndDismiss) {
                    Label("Save Routine", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("routine_builder_save")
                .disabled(!viewModel.canSave)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(.bar)
            }
            .sheet(isPresented: $viewModel.showingExercisePicker) {
                ExercisePickerView { draft in
                    viewModel.addExercise(from: draft)
                    viewModel.showingExercisePicker = false
                }
            }
            .sheet(item: $viewModel.exerciseToEdit) { exercise in
                ExerciseSetEditorView(
                    exercise: exercise,
                    onSave: { updatedExercise in
                        viewModel.updateExercise(updatedExercise)
                    }
                )
            }
        }
    }

    private func saveAndDismiss() {
        viewModel.saveRoutine()
        dismiss()
    }
}
