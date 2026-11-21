import SwiftUI

struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @State private var exerciseName: String = ""
    @State private var duration: String = ""
    @State private var caloriesBurned: String = ""
    @State private var selectedDate: Date = Date()
    @State private var draftID = UUID().uuidString
    @State private var accountID: String?
    @State private var isSaving = false
    @State private var saveError: String?

    var exerciseToEdit: LoggedExercise?
    var onSave: (String, LoggedExercise, @escaping (Bool) -> Void) -> Void

    @State private var isEditing: Bool = false
    @State private var attemptedSave = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case duration
        case calories
    }

    init(
        exerciseToEdit: LoggedExercise? = nil,
        initialDate: Date = Date(),
        onSave: @escaping (String, LoggedExercise, @escaping (Bool) -> Void) -> Void
    ) {
        self.exerciseToEdit = exerciseToEdit
        self.onSave = onSave
        _accountID = State(initialValue: DIContainer.shared.authService.currentUserID)

        if let exercise = exerciseToEdit {
            _exerciseName = State(initialValue: exercise.name)
            _duration = State(initialValue: exercise.durationMinutes.map(String.init) ?? "")
            _caloriesBurned = State(initialValue: String(exercise.caloriesBurned))
            _selectedDate = State(initialValue: exercise.date)
            _isEditing = State(initialValue: true)
        } else {
             _exerciseName = State(initialValue: "")
             _duration = State(initialValue: "")
             _caloriesBurned = State(initialValue: "")
             _selectedDate = State(initialValue: initialDate)
             _isEditing = State(initialValue: false)
        }
    }

    var body: some View {
        AppEditorScaffold(
            title: isEditing ? "Edit activity" : "Log activity",
            subtitle: isEditing
                ? "Correct the activity stored in MyFitPlate."
                : "Log an activity that was not imported automatically.",
            dismiss: { if !isSaving { dismiss() } }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Activity")

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

                    if isEditing {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            LabeledContent("Activity date", value: selectedDate.formatted(date: .abbreviated, time: .omitted))
                            Text("Corrections stay on this activity's original day.")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppSpacing.group)
                    } else {
                        AppDateField("Activity date", selection: $selectedDate)
                            .appTextRole(.control)
                            .padding(AppSpacing.group)
                            .background(
                                AppPalette.control,
                                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            )
                    }
                }
                .appSurface(.emphasized)
                .disabled(isSaving)

                if isEditing, exerciseToEdit?.source != "manual" {
                    AppListRow(
                        icon: "heart.text.square",
                        iconColor: AppPalette.caution,
                        title: exerciseToEdit?.source == "HealthKit" ? "MyFitPlate copy only" : "Diary activity totals",
                        subtitle: exerciseToEdit?.source == "HealthKit"
                            ? "Corrections stay in MyFitPlate when Health refreshes. They do not alter the original workout. To remove this import, delete the original in Apple Health."
                            : "Correct this diary entry's totals. Recorded sets can be edited from workout history."
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
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manual_exercise_save_error")
            }
            Button(isSaving ? "Saving…" : isEditing ? "Update activity" : "Log activity", action: saveExercise)
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
        .interactiveDismissDisabled(isSaving)
    }

    private func saveExercise() {
        attemptedSave = true
        guard canSave, let calories = Double(caloriesBurned) else { return }
        guard let accountID, DIContainer.shared.authService.currentUserID == accountID else {
            saveError = "Your account changed. Close this editor and reopen it from your diary."
            return
        }
        let durationMinutes = Int(duration)

        var exercise = exerciseToEdit ?? LoggedExercise(
            id: draftID, name: exerciseName, caloriesBurned: calories, date: selectedDate
        )
        exercise.name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.durationMinutes = durationMinutes
        exercise.caloriesBurned = calories
        exercise.date = selectedDate
        isSaving = true
        saveError = nil
        focusedField = nil
        onSave(accountID, exercise) { accepted in
            Task { @MainActor in
                isSaving = false
                guard DIContainer.shared.authService.currentUserID == accountID else {
                    saveError = "Your account changed. Reopen your diary to check this activity."
                    return
                }
                if accepted {
                    dismiss()
                } else {
                    saveError = "Your changes are still here. Try saving again."
                }
            }
        }
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
        guard let calories = Double(caloriesBurned), calories.isFinite, calories > 0 else {
            return "Active calories must be a number greater than zero."
        }
        if !duration.isEmpty, (Int(duration) ?? 0) <= 0 {
            return "Duration must be a positive whole number when provided."
        }
        return nil
    }

    private var canSave: Bool {
        !isSaving && validationMessage == nil
    }
}
