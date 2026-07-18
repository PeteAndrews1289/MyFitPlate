import SwiftUI

struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @State private var exerciseName: String = ""
    @State private var duration: String = ""
    @State private var caloriesBurned: String = ""
    @State private var selectedDate: Date = Date()

    var exerciseToEdit: LoggedExercise?
    var onSave: (LoggedExercise) -> Void
    
    @State private var isEditing: Bool = false
    @State private var attemptedSave = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case duration
        case calories
    }

    init(exerciseToEdit: LoggedExercise? = nil, onSave: @escaping (LoggedExercise) -> Void) {
        self.exerciseToEdit = exerciseToEdit
        self.onSave = onSave
        
        if let exercise = exerciseToEdit {
            _exerciseName = State(initialValue: exercise.name)
            _duration = State(initialValue: exercise.durationMinutes.map(String.init) ?? "")
            _caloriesBurned = State(initialValue: "\(Int(exercise.caloriesBurned))")
            _selectedDate = State(initialValue: exercise.date)
            _isEditing = State(initialValue: true)
        } else {
             _exerciseName = State(initialValue: "")
             _duration = State(initialValue: "")
             _caloriesBurned = State(initialValue: "")
             _selectedDate = State(initialValue: Date())
             _isEditing = State(initialValue: false)
        }
    }

    var body: some View {
        AppEditorScaffold(
            title: isEditing ? "Edit Exercise" : "Add Exercise",
            subtitle: isEditing
                ? "Correct the activity stored in MyFitPlate."
                : "Log an activity that was not imported automatically.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Activity",
                        subtitle: "Use a name you will recognize in your daily log."
                    )

                    TextField("Exercise name", text: $exerciseName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .accessibilityIdentifier("manual_exercise_name")

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            durationField
                            calorieField
                        }
                        VStack(spacing: AppSpacing.row) {
                            durationField
                            calorieField
                        }
                    }

                    DatePicker("Activity date", selection: $selectedDate, displayedComponents: .date)
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                }
                .appSurface(.emphasized)

                if isEditing, exerciseToEdit?.source != "manual" {
                    AppListRow(
                        icon: "heart.text.square",
                        iconColor: AppPalette.caution,
                        title: "MyFitPlate copy only",
                        subtitle: "This edit changes your MyFitPlate log. It does not alter the original Apple Health workout."
                    )
                    .appSurface(.quiet, padding: 0)
                }

                if attemptedSave, let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                        .appSurface(.quiet)
                        .accessibilityIdentifier("manual_exercise_validation")
                }
            }
        } actions: {
            Button(isEditing ? "Update Exercise" : "Log Exercise", action: saveExercise)
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!canSave)
                .accessibilityIdentifier("manual_exercise_save")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .tint(AppPalette.brand)
    }

    private func saveExercise() {
        attemptedSave = true
        guard canSave, let calories = Double(caloriesBurned) else { return }
        let durationMinutes = Int(duration)

        let exercise = LoggedExercise(
            id: exerciseToEdit?.id ?? UUID().uuidString,
            name: exerciseName,
            durationMinutes: durationMinutes,
            caloriesBurned: calories,
            date: selectedDate,
            source: exerciseToEdit?.source ?? "manual"
        )
        onSave(exercise)
        dismiss()
    }

    private var durationField: some View {
        editorField(title: "Duration", unit: "min") {
            TextField("Optional", text: $duration)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .duration)
                .accessibilityIdentifier("manual_exercise_duration")
        }
    }

    private var calorieField: some View {
        editorField(title: "Active calories", unit: "cal") {
            TextField("Required", text: $caloriesBurned)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .calories)
                .accessibilityIdentifier("manual_exercise_calories")
        }
    }

    private func editorField<Content: View>(
        title: String,
        unit: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: AppSpacing.compact) {
                content()
                    .appTextRole(.control)
                Text(unit)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
    }

    private var validationMessage: String? {
        if exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter an exercise name."
        }
        guard let calories = Double(caloriesBurned), calories > 0 else {
            return "Active calories must be a number greater than zero."
        }
        if !duration.isEmpty, (Int(duration) ?? 0) <= 0 {
            return "Duration must be a positive whole number when provided."
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }
}
