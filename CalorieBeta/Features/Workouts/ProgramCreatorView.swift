import MyFitPlateCore

import SwiftUI

struct ProgramCreatorView: View {
    @ObservedObject var workoutService: WorkoutService
    var programToEdit: WorkoutProgram?
    var isPresentedModally = false

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var routines: [WorkoutRoutine] = []
    @State private var startDate = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    @State private var routineToEdit: WorkoutRoutine?
    @State private var didSetUp = false
    @State private var isSaving = false

    private var isEditMode: Bool { programToEdit != nil }

    private var canSave: Bool {
        !name.trimmed.isEmpty && !routines.isEmpty && !selectedDaysOfWeek.isEmpty && !isSaving
    }

    private var exerciseCount: Int {
        routines.reduce(0) { $0 + $1.exercises.count }
    }

    private var totalSetCount: Int {
        routines.reduce(0) { partial, routine in
            partial + routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppScreenHeader(
                    eyebrow: "Program Builder",
                    title: name.trimmed.isEmpty ? "Build Your Plan" : name,
                    subtitle: "Arrange the workout rotation once, then choose when it repeats."
                )

                AppMetricStrip(items: [
                    AppMetricItem(label: "Routines", value: "\(routines.count)", accent: AppPalette.brand),
                    AppMetricItem(label: "Exercises", value: "\(exerciseCount)", accent: AppPalette.effort),
                    AppMetricItem(label: "Sets", value: "\(totalSetCount)", accent: .accentPositive)
                ])
                .appSurface(.quiet)

                ProgramDetailsSection(name: $name)
                    .accessibilityIdentifier("program_builder_details")

                RoutineSelectionList(
                    routines: routines,
                    onEdit: { routineToEdit = $0 },
                    onDelete: deleteRoutine,
                    onAdd: addRoutine
                )
                .accessibilityIdentifier("program_builder_routines")

                ProgramScheduleSection(
                    startDate: $startDate,
                    selectedDaysOfWeek: $selectedDaysOfWeek
                )
                .accessibilityIdentifier("program_builder_schedule")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("program_builder")
        .background(AppPalette.canvas.ignoresSafeArea())
        .navigationTitle(isEditMode ? "Edit Program" : "New Program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(AppPalette.text)
                    .accessibilityLabel("Close program builder")
                    .accessibilityIdentifier("program_builder_close")
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            ProgramSaveBar(
                isEditMode: isEditMode,
                isSaving: isSaving,
                isEnabled: canSave,
                action: saveProgram
            )
        }
        .onAppear(perform: setupView)
        .sheet(item: $routineToEdit) { routine in
            RoutineEditorView(
                workoutService: workoutService,
                routine: routine,
                onSave: updateRoutine
            )
        }
    }

    private func setupView() {
        guard !didSetUp else { return }
        didSetUp = true
        guard let program = programToEdit else { return }
        name = program.name
        routines = program.routines
        startDate = program.startDate ?? Date()
        selectedDaysOfWeek = program.daysOfWeek ?? []
    }

    private func addRoutine() {
        let routine = WorkoutRoutine(
            userID: DIContainer.shared.authService.currentUserID ?? "",
            name: "",
            dateCreated: Date()
        )
        routines.append(routine)
        routineToEdit = routine
    }

    private func updateRoutine(_ updatedRoutine: WorkoutRoutine) {
        guard let index = routines.firstIndex(where: { $0.id == updatedRoutine.id }) else { return }
        routines[index] = updatedRoutine
    }

    private func deleteRoutine(_ routine: WorkoutRoutine) {
        routines.removeAll { $0.id == routine.id }
    }

    private func saveProgram() {
        guard canSave else { return }
        isSaving = true
        let program = WorkoutProgram(
            id: programToEdit?.id ?? UUID().uuidString,
            userID: programToEdit?.userID ?? DIContainer.shared.authService.currentUserID ?? "",
            name: name.trimmed,
            dateCreated: programToEdit?.dateCreated ?? Date(),
            routines: routines,
            startDate: startDate,
            daysOfWeek: selectedDaysOfWeek.sorted(),
            currentProgressIndex: programToEdit?.currentProgressIndex ?? 0,
            skippedIndices: programToEdit?.skippedIndices
        )

        Task {
            await workoutService.saveProgram(program)
            dismiss()
        }
    }
}

private struct ProgramDetailsSection: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Plan Details",
                subtitle: "Use a name that will still make sense months from now."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("PROGRAM NAME")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)

                TextField("12 Week Strength", text: $name)
                    .appTextRole(.control)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            .appSurface(.quiet)
        }
    }
}

private struct RoutineSelectionList: View {
    let routines: [WorkoutRoutine]
    let onEdit: (WorkoutRoutine) -> Void
    let onDelete: (WorkoutRoutine) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Routine Rotation",
                subtitle: "Workouts repeat in this order on your selected training days."
            ) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add routine")
            }

            if routines.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Image(systemName: "list.number")
                        .appFont(size: 24, weight: .semibold)
                        .foregroundStyle(AppPalette.brand)
                        .accessibilityHidden(true)

                    Text("Start the rotation")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text("Add your first workout day, then choose exercises and set targets.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)

                    Button(action: onAdd) {
                        Label("Add First Routine", systemImage: "plus")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .appSurface(.quiet)
            } else {
                VStack(spacing: AppSpacing.compact) {
                    ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                        ProgramRoutineRow(
                            position: index + 1,
                            routine: routine,
                            onEdit: { onEdit(routine) },
                            onDelete: { onDelete(routine) }
                        )
                    }
                }
            }
        }
    }
}

private struct ProgramRoutineRow: View {
    let position: Int
    let routine: WorkoutRoutine
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var setCount: Int {
        routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
    }

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Text("\(position)")
                .appTextRole(.control)
                .monospacedDigit()
                .foregroundStyle(AppPalette.brand)
                .frame(width: 40, height: 40)
                .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name.trimmed.isEmpty ? "Untitled Routine" : routine.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(routine.exercises.count) exercises • \(setCount) sets")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit Routine", systemImage: "pencil", action: onEdit)
                Button("Delete Routine", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Options for \(routine.name.trimmed.isEmpty ? "untitled routine" : routine.name)")
        }
        .padding(AppSpacing.row)
        .appSurface(.quiet, padding: 0)
    }
}

private struct ProgramScheduleSection: View {
    @Binding var startDate: Date
    @Binding var selectedDaysOfWeek: [Int]

    private var frequencyDescription: String {
        switch selectedDaysOfWeek.count {
        case 0: "Choose at least one training day"
        case 1: "1 workout each week"
        default: "\(selectedDaysOfWeek.count) workouts each week"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Weekly Schedule",
                subtitle: frequencyDescription
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    .appTextRole(.control)

                Divider()

                WeekDaySelector(selectedDays: $selectedDaysOfWeek)
            }
            .appSurface(.quiet)
        }
    }
}

private struct ProgramSaveBar: View {
    let isEditMode: Bool
    let isSaving: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSaving {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Saving program")
            } else {
                Label(isEditMode ? "Save Changes" : "Create Program", systemImage: "checkmark")
            }
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .accessibilityIdentifier("program_builder_save")
        .disabled(!isEnabled)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.compact)
        .padding(.bottom, AppSpacing.compact)
        .background(.bar)
    }
}
