import MyFitPlateCore

import SwiftUI

struct RoutineEditorHeaderCard: View {
    let routineName: String
    let exerciseCount: Int
    let setCount: Int
    let estimatedMinutes: Int
    let exercises: [RoutineExercise]

    private var balanceText: String {
        let grouped = Dictionary(grouping: exercises, by: \.type)
        let parts = ExerciseType.allCases.compactMap { type -> String? in
            guard let count = grouped[type]?.count, count > 0 else { return nil }
            return "\(count) \(type.shortTitle.lowercased())"
        }
        return parts.isEmpty ? "Start with an exercise or template" : parts.joined(separator: " / ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Routine Builder",
                title: routineName.trimmed.isEmpty ? "Untitled Routine" : routineName,
                subtitle: balanceText
            ) {
                Text(ExerciseEmojiMapper.getEmoji(for: exercises.first?.name ?? routineName))
                    .appFont(size: 28)
                    .frame(width: 52, height: 52)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Exercises", value: "\(exerciseCount)", accent: AppPalette.brand),
                AppMetricItem(label: "Sets", value: "\(setCount)", accent: .accentPositive),
                AppMetricItem(label: "Estimated", value: estimatedMinutes > 0 ? "\(estimatedMinutes) min" : "-", accent: .orange)
            ])
            .appSurface(.quiet)
        }
    }
}

struct RoutineBasicsCard: View {
    @Binding var routineName: String
    @Binding var routineNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Routine Details",
                subtitle: "Name the workout and leave cues you will want during training."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                RoutineEditorFieldLabel(title: "Routine Name") {
                    TextField("Push Day, Lower A, Conditioning...", text: $routineName)
                        .appTextRole(.control)
                        .textInputAutocapitalization(.words)
                        .routineInputStyle()
                }

                RoutineEditorFieldLabel(title: "Coach Notes") {
                    TextEditor(text: $routineNotes)
                        .appTextRole(.body)
                        .frame(minHeight: 88)
                        .padding(AppSpacing.compact)
                        .scrollContentBackground(.hidden)
                        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                }
            }
            .appSurface(.quiet)
        }
    }
}

struct RoutineTemplateStrip: View {
    let templates: [RoutineEditorTemplate]
    let onApply: (RoutineEditorTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Fast Starts",
                subtitle: "Append a proven block, then customize any movement."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.row) {
                    ForEach(templates) { template in
                        Button {
                            onApply(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: template.icon)
                                        .appFont(size: 14, weight: .semibold)
                                        .foregroundStyle(template.color)
                                        .frame(width: 30, height: 30)
                                        .background(template.color.opacity(0.12), in: Circle())
                                    Spacer()
                                    Text("+\(template.exercises.count)")
                                        .appTextRole(.caption)
                                        .foregroundStyle(template.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(template.color.opacity(0.10), in: Capsule())
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .appTextRole(.control)
                                        .foregroundStyle(AppPalette.text)
                                        .lineLimit(1)
                                    Text(template.subtitle)
                                        .appTextRole(.secondary)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(AppSpacing.row)
                            .frame(width: 184, alignment: .leading)
                            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(AppPalette.separator, lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Adds \(template.exercises.count) exercises to this routine")
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

struct RoutineExerciseBuilderCard: View {
    let exercises: [RoutineExercise]
    let onAddExercise: () -> Void
    let onEdit: (RoutineExercise) -> Void
    let onDuplicate: (RoutineExercise) -> Void
    let onDelete: (RoutineExercise) -> Void
    let onMove: (RoutineExercise, RoutineMoveDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Exercise Plan",
                subtitle: exercises.isEmpty ? "Add the first movement to begin." : "Tap a movement to edit its sets, target, rest, and substitutions."
            ) {
                Button(action: onAddExercise) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add exercise")
            }

            if exercises.isEmpty {
                RoutineEmptyBuilderCard(onAddExercise: onAddExercise)
            } else {
                VStack(spacing: AppSpacing.compact) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        RoutineExerciseEditorRow(
                            index: index,
                            exercise: exercise,
                            isFirst: index == 0,
                            isLast: index == exercises.count - 1,
                            onEdit: { onEdit(exercise) },
                            onDuplicate: { onDuplicate(exercise) },
                            onDelete: { onDelete(exercise) },
                            onMoveUp: { onMove(exercise, .up) },
                            onMoveDown: { onMove(exercise, .down) }
                        )
                    }
                }
            }
        }
    }
}

struct RoutineExerciseEditorRow: View {
    let index: Int
    let exercise: RoutineExercise
    let isFirst: Bool
    let isLast: Bool
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    private var setCount: Int {
        max(exercise.sets.count, exercise.targetSets)
    }

    private var targetText: String {
        exercise.sets.first?.target ?? RoutineEditorDefaults.setTarget(for: exercise.type, target: exercise.targetReps)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    VStack(spacing: 4) {
                        Text("\(index + 1)")
                            .appTextRole(.caption)
                            .foregroundStyle(exercise.type.color)
                        Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                            .font(.title3)
                    }
                    .frame(width: 42)
                    .frame(minHeight: 50)
                    .background(exercise.type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(setCount) sets - \(targetText) - \(RoutineEditorDefaults.restLabel(exercise.restTimeInSeconds))")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Label(exercise.type.shortTitle, systemImage: exercise.type.icon)
                            .appTextRole(.caption)
                            .foregroundStyle(exercise.type.color)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit Exercise", systemImage: "pencil", action: onEdit)
                Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                    .disabled(isFirst)
                Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                    .disabled(isLast)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Divider()
                Button("Delete Exercise", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Options for \(exercise.name)")
        }
        .padding(AppSpacing.row)
        .appSurface(.quiet, padding: 0)
    }
}

struct RoutineEmptyBuilderCard: View {
    let onAddExercise: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Image(systemName: "figure.strengthtraining.traditional")
                .appFont(size: 28, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .accessibilityHidden(true)

            Text("Build the first block")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text("Add movements manually or tap a fast-start template above.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)

            Button(action: onAddExercise) {
                Label("Add Exercise", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }
}

struct ExerciseEditorHero: View {
    let exercise: RoutineExercise

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Exercise Prescription",
                title: exercise.name.trimmed.isEmpty ? "New Exercise" : exercise.name,
                subtitle: "Set the target, recovery time, cues, and swap options."
            ) {
                Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                    .appFont(size: 28)
                    .frame(width: 52, height: 52)
                    .background(exercise.type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Sets", value: "\(exercise.targetSets)", accent: exercise.type.color),
                AppMetricItem(
                    label: exercise.type.targetLabel,
                    value: RoutineEditorDefaults.setTarget(for: exercise.type, target: exercise.targetReps),
                    accent: AppPalette.brand
                ),
                AppMetricItem(
                    label: "Rest",
                    value: RoutineEditorDefaults.restLabel(exercise.restTimeInSeconds),
                    accent: .orange
                )
            ])
            .appSurface(.quiet)
        }
    }
}

struct ExercisePickerRow: View {
    let entry: ExercisePickerEntry
    let onSelect: () -> Void

    private var type: ExerciseType {
        RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.row) {
                Text(ExerciseEmojiMapper.getEmoji(for: entry.name))
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(entry.category) • \(type.shortTitle)")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "plus")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundStyle(AppPalette.brand)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.row)
            .appSurface(.quiet, padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds this exercise to the routine")
    }
}

struct SectionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .accessibilityHidden(true)
            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
        }
    }
}

private struct RoutineEditorFieldLabel<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct RoutineInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.row)
            .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 0.5)
            }
    }
}

private extension View {
    func routineInputStyle() -> some View {
        modifier(RoutineInputStyle())
    }
}

struct ExerciseSetEditorView: View {
    @State private var editableExercise: RoutineExercise
    @State private var alternativesText: String
    var onSave: (RoutineExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    private var setTarget: String {
        RoutineEditorDefaults.setTarget(for: editableExercise.type, target: editableExercise.targetReps)
    }

    init(exercise: RoutineExercise, onSave: @escaping (RoutineExercise) -> Void) {
        self._editableExercise = State(initialValue: exercise)
        self._alternativesText = State(initialValue: exercise.alternatives?.joined(separator: ", ") ?? "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    ExerciseEditorHero(exercise: editableExercise)

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        SectionLabel(title: "Movement", icon: "slider.horizontal.3")

                        VStack(alignment: .leading, spacing: AppSpacing.group) {
                            TextField("Exercise name", text: $editableExercise.name)
                                .appTextRole(.control)
                                .textInputAutocapitalization(.words)
                                .routineInputStyle()

                            Picker("Type", selection: $editableExercise.type) {
                                ForEach(ExerciseType.allCases, id: \.self) { type in
                                    Label(type.rawValue, systemImage: type.icon).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: editableExercise.type) { _, newType in
                                applyTypeDefaults(newType)
                            }
                        }
                        .appSurface(.quiet)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        SectionLabel(title: "Prescription", icon: "target")

                        VStack(alignment: .leading, spacing: AppSpacing.group) {
                            Stepper("Sets: \(editableExercise.targetSets)", value: $editableExercise.targetSets, in: 1...15) { _ in
                                updateSetCount()
                            }
                            .appTextRole(.control)

                            RoutineEditorFieldLabel(title: editableExercise.type.targetLabel) {
                                TextField(editableExercise.type.targetPlaceholder, text: $editableExercise.targetReps)
                                    .appTextRole(.control)
                                    .routineInputStyle()
                                    .onChange(of: editableExercise.targetReps) { _, _ in
                                        applyTargetToAllSets()
                                    }
                            }

                            Picker("Rest Between Sets", selection: $editableExercise.restTimeInSeconds) {
                                ForEach(editableExercise.type.restPresets, id: \.self) { seconds in
                                    Text(RoutineEditorDefaults.restLabel(seconds)).tag(seconds)
                                }
                            }
                            .appTextRole(.control)
                            .tint(AppPalette.brand)
                        }
                        .appSurface(.quiet)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        HStack {
                            SectionLabel(title: "Set Targets", icon: "list.number")
                            Spacer()
                            Button("Apply All") {
                                applyTargetToAllSets()
                            }
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.brand)
                        }

                        VStack(spacing: AppSpacing.compact) {
                            ForEach(editableExercise.sets.indices, id: \.self) { index in
                                HStack(spacing: AppSpacing.row) {
                                    Text("\(index + 1)")
                                        .appTextRole(.caption)
                                        .foregroundStyle(editableExercise.type.color)
                                        .frame(width: 32, height: 32)
                                        .background(editableExercise.type.color.opacity(0.10), in: Circle())
                                        .accessibilityHidden(true)

                                    TextField("Target", text: Binding(
                                        get: { editableExercise.sets[index].target ?? "" },
                                        set: { editableExercise.sets[index].target = $0.trimmed.isEmpty ? nil : $0 }
                                    ))
                                    .appTextRole(.body)
                                    .routineInputStyle()
                                    .accessibilityLabel("Set \(index + 1) target")
                                }
                            }
                        }
                        .appSurface(.quiet)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        SectionLabel(title: "Notes", icon: "note.text")

                        TextEditor(text: Binding(
                            get: { editableExercise.notes ?? "" },
                            set: { editableExercise.notes = $0.trimmed.isEmpty ? nil : $0 }
                        ))
                        .appTextRole(.body)
                        .frame(minHeight: 90)
                        .padding(AppSpacing.row)
                        .scrollContentBackground(.hidden)
                        .appSurface(.quiet, padding: 0)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        SectionLabel(title: "Swap Options", icon: "arrow.triangle.2.circlepath")

                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("Add alternatives separated by commas. These appear in the workout player when you need a substitute.")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)

                            TextField("Dumbbell Bench Press, Push-up", text: $alternativesText)
                                .appTextRole(.body)
                                .textInputAutocapitalization(.words)
                                .routineInputStyle()
                        }
                        .appSurface(.quiet)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close exercise editor")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveAndDismiss) {
                    Label("Save Exercise", systemImage: "checkmark")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(editableExercise.name.trimmed.isEmpty)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.compact)
                .background(.bar)
            }
        }
    }

    private func updateSetCount() {
        let currentSetCount = editableExercise.sets.count
        let targetSetCount = editableExercise.targetSets

        if targetSetCount > currentSetCount {
            let setsToAdd = targetSetCount - currentSetCount
            for _ in 0..<setsToAdd {
                editableExercise.sets.append(ExerciseSet(target: setTarget))
            }
        } else if targetSetCount < currentSetCount {
            editableExercise.sets.removeLast(currentSetCount - targetSetCount)
        }
    }

    private func applyTargetToAllSets() {
        let target = setTarget
        for index in editableExercise.sets.indices {
            editableExercise.sets[index].target = target
        }
    }

    private func applyTypeDefaults(_ type: ExerciseType) {
        let defaults = RoutineEditorDefaults.defaults(for: type)
        editableExercise.targetSets = defaults.sets
        editableExercise.targetReps = defaults.target
        editableExercise.restTimeInSeconds = defaults.rest
        updateSetCount()
        applyTargetToAllSets()
    }

    private func normalizeExerciseBeforeSave() {
        editableExercise.name = editableExercise.name.trimmed
        editableExercise.alternatives = alternativesText
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
            .nilIfEmpty
        updateSetCount()
        applyTargetToAllSets()
    }

    private func saveAndDismiss() {
        normalizeExerciseBeforeSave()
        onSave(editableExercise)
        dismiss()
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var customExerciseName = ""
    @State private var customExerciseType: ExerciseType = .strength

    var onSelect: (ExercisePickerDraft) -> Void

    private let categorizedExercises = ExerciseList.categorizedExercises

    private var categories: [String] {
        ["All"] + categorizedExercises.keys.sorted()
    }

    private var visibleEntries: [ExercisePickerEntry] {
        let entries = categorizedExercises.flatMap { category, exercises in
            exercises.map { ExercisePickerEntry(name: $0, category: category) }
        }
        let categoryFiltered = selectedCategory == "All" ? entries : entries.filter { $0.category == selectedCategory }
        guard !searchText.trimmed.isEmpty else {
            return categoryFiltered.sorted()
        }
        return categoryFiltered
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
            .sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Routine Builder",
                        title: "Add a Movement",
                        subtitle: "Search the exercise library or create one that is specific to your training."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Custom Movement",
                            subtitle: "Name it, choose how it is measured, and add it directly."
                        )

                        VStack(alignment: .leading, spacing: AppSpacing.group) {
                            TextField("Add your own exercise", text: $customExerciseName)
                                .appTextRole(.control)
                                .textInputAutocapitalization(.words)
                                .routineInputStyle()

                            Picker("Measurement Type", selection: $customExerciseType) {
                                ForEach(ExerciseType.allCases, id: \.self) { type in
                                    Text(type.shortTitle).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button(action: selectCustomExercise) {
                                Label("Add Custom Movement", systemImage: "plus")
                            }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .disabled(customExerciseName.trimmed.isEmpty)
                        }
                        .appSurface(.quiet)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Exercise Library",
                            subtitle: selectedCategory == "All" ? "Showing every category" : "Filtered to \(selectedCategory)"
                        ) {
                            Menu {
                                ForEach(categories, id: \.self) { category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        if selectedCategory == category {
                                            Label(category, systemImage: "checkmark")
                                        } else {
                                            Text(category)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease")
                            }
                            .buttonStyle(AppIconButtonStyle(.neutral))
                            .accessibilityLabel("Filter exercise category")
                            .accessibilityValue(selectedCategory)
                        }

                        if visibleEntries.isEmpty {
                            GuidanceEmptyState(
                                icon: "magnifyingglass",
                                title: "No exercises found",
                                message: "Try a different search term, or add a custom exercise."
                            )
                        } else {
                            LazyVStack(spacing: AppSpacing.compact) {
                                ForEach(visibleEntries) { entry in
                                    ExercisePickerRow(entry: entry) {
                                        onSelect(ExercisePickerDraft(
                                            name: entry.name,
                                            category: entry.category,
                                            type: RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category)
                                        ))
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close exercise library")
                }
            }
        }
    }

    private func selectCustomExercise() {
        onSelect(ExercisePickerDraft(
            name: customExerciseName.trimmed,
            category: "Custom",
            type: customExerciseType
        ))
        dismiss()
    }
}
