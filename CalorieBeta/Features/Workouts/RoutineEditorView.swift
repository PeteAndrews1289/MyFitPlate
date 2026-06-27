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
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
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

                    RoutineTemplateStrip(
                        templates: RoutineEditorTemplate.templates,
                        onApply: { viewModel.applyTemplate($0) }
                    )

                    RoutineExerciseBuilderCard(
                        exercises: viewModel.exercises,
                        onAddExercise: { viewModel.showingExercisePicker = true },
                        onEdit: { viewModel.exerciseToEdit = $0 },
                        onDuplicate: { viewModel.duplicateExercise($0) },
                        onDelete: { viewModel.deleteExercise($0) },
                        onMove: { viewModel.moveExercise($0, direction: $1) }
                    )
                }
                .padding()
                .padding(.bottom, 14)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(viewModel.routineName.trimmed.isEmpty ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: {
                        viewModel.saveRoutine()
                        dismiss()
                    })
                    .disabled(!viewModel.canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    viewModel.saveRoutine()
                    dismiss()
                } label: {
                    Label("Save Routine", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSave)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
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
}
