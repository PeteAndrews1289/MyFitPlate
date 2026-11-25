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

    private var primaryType: ExerciseType {
        exercises.first?.type ?? RoutineEditorDefaults.inferredType(name: routineName, category: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppScreenHeader(
                eyebrow: "Routine Builder",
                title: routineName.trimmed.isEmpty ? "Untitled Routine" : routineName,
                subtitle: balanceText
            ) {
                Image(systemName: primaryType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(primaryType.color)
                    .frame(width: 52, height: 52)
                    .background(primaryType.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Exercises", value: "\(exerciseCount)", accent: AppPalette.brand),
                AppMetricItem(label: "Sets", value: "\(setCount)", accent: .accentPositive),
                AppMetricItem(label: "Estimated", value: estimatedMinutes > 0 ? "\(estimatedMinutes) min" : "-", accent: AppPalette.caution)
            ])
            .appSurface(.quiet)
        }
    }
}

struct RoutineBasicsCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var routineName: String
    @Binding var routineNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                RoutineEditorFieldLabel(title: "Routine Name") {
                    TextField("Routine name", text: $routineName, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal)
                        .accessibilityIdentifier("routine_builder_name")
                        .appTextRole(.control)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .routineInputStyle()
                }

                DisclosureGroup {
                    TextEditor(text: $routineNotes)
                        .appTextRole(.body)
                        .frame(minHeight: 88)
                        .padding(AppSpacing.compact)
                        .scrollContentBackground(.hidden)
                        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notes").appTextRole(.secondary)
                        if !routineNotes.trimmed.isEmpty {
                            Text(routineNotes).appTextRole(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .accessibilityIdentifier("routine_builder_notes")
                }
                .tint(AppPalette.text)
            }
            .appSurface(.quiet)
        }
    }
}

struct RoutineTemplateStrip: View {
    let templates: [RoutineEditorTemplate]
    let onApply: (RoutineEditorTemplate) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Fast Starts",
                subtitle: "Choose a starter, review append or replace, then customize."
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
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                    Text(template.subtitle)
                                        .appTextRole(.secondary)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                }
                            }
                            .padding(AppSpacing.row)
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 244 : 184, alignment: .leading)
                            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(AppPalette.separator, lineWidth: 0.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Reviews \(template.exercises.count) movements before changing a nonempty routine")
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
    let onReorder: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Exercises",
                subtitle: exercises.isEmpty ? "Add the first movement to begin." : "Tap to edit. Drag to reorder."
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
                        .draggable(exercise.id)
                        .dropDestination(for: String.self) { identifiers, _ in
                            guard identifiers.count == 1, let source = identifiers.first, source != exercise.id,
                                  exercises.contains(where: { $0.id == source }) else { return false }
                            onReorder(source, exercise.id)
                            return true
                        }
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
                        Image(systemName: exercise.type.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(exercise.type.color)
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
                .foregroundStyle(AppPalette.brandText)
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
                Image(systemName: exercise.type.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(exercise.type.color)
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
                    accent: AppPalette.caution
                )
            ])
            .appSurface(.quiet)
        }
    }
}

struct ExercisePickerRow: View {
    let entry: ExercisePickerEntry
    var isSelected = false
    let onSelect: () -> Void

    private var type: ExerciseType {
        RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category)
    }

    private var equipment: ExerciseList.EquipmentFamily {
        ExerciseList.equipment(for: entry.name)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppSpacing.row) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(type.color)
                    .frame(width: 42, height: 42)
                    .background(type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if isSelected { Label("Selected", systemImage: "checkmark.circle.fill").appTextRole(.caption).foregroundStyle(AppPalette.brandText) }
                    Text("\(entry.category) • \(equipment.rawValue) • \(type.shortTitle)")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "plus")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundStyle(AppPalette.brandText)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.row)
            .appSurface(.quiet, padding: 0)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds this exercise to the routine")
    }
}

private struct ExerciseFilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .appTextRole(.secondary)
            .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.text)
            .padding(.horizontal, AppSpacing.row)
            .frame(minHeight: 40)
            .background(
                isSelected ? AppPalette.brand : AppPalette.control,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.clear : AppPalette.separator, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SectionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
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
    @State private var prescriptionSet: ExerciseSet?
    @State private var showingTemplateEquipment = false
    var onSave: (RoutineExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    private var setTarget: String {
        RoutineEditorDefaults.setTarget(for: editableExercise.type, target: editableExercise.targetReps)
    }

    private var targetPresets: [String] {
        switch editableExercise.type {
        case .strength:
            ["5", "6-8", "8-12", "12-15"]
        case .cardio:
            ["10 min", "20 min", "30 min", "5 km"]
        case .flexibility:
            ["20 sec", "30 sec", "45 sec", "60 sec"]
        }
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

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.compact) {
                                    ForEach(targetPresets, id: \.self) { preset in
                                        ExerciseFilterChip(
                                            title: preset,
                                            icon: nil,
                                            isSelected: editableExercise.targetReps == preset
                                        ) {
                                            editableExercise.targetReps = preset
                                            applyTargetToAllSets()
                                        }
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                            .accessibilityLabel("\(editableExercise.type.targetLabel) presets")

                            if editableExercise.type == .strength {
                                Button("Equipment & loading convention") { showingTemplateEquipment = true }.frame(minHeight: 44)
                                Picker("Progression policy", selection: Binding(get: { editableExercise.progressionPolicy?.kind ?? .conservativeDouble }, set: {
                                    editableExercise.progressionPolicy = WorkoutProgressionPolicy(kind: $0, incrementPounds: editableExercise.progressionIncrement ?? 5)
                                })) {
                                    ForEach(WorkoutProgressionPolicy.Kind.allCases) { Text($0.title).tag($0) }
                                }.accessibilityIdentifier("exercise_progression_policy")
                                if editableExercise.progressionPolicy != nil {
                                    Stepper("Load step: \((editableExercise.progressionPolicy?.incrementPounds ?? 5).formatted()) lb", value: Binding(get: {
                                        editableExercise.progressionPolicy?.incrementPounds ?? 5
                                    }, set: { editableExercise.progressionPolicy?.incrementPounds = $0 }), in: 0.25...100, step: 0.25)
                                }
                                if let policy = editableExercise.progressionPolicy {
                                    Text("Policy v\(policy.version) · \(policy.validationMessage(for: editableExercise) ?? "Applies to reviewed future-session suggestions; performed sets stay intact.")")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
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
                            .foregroundStyle(AppPalette.brandText)
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
                                        set: {
                                            editableExercise.sets[index].target = $0.trimmed.isEmpty ? nil : $0
                                            editableExercise.sets[index].prescription = nil
                                        }
                                    ))
                                    .appTextRole(.body)
                                    .routineInputStyle()
                                    .accessibilityLabel("Set \(index + 1) target")
                                    Button { prescriptionSet = editableExercise.sets[index] } label: {
                                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Structure target for set \(index + 1)")
                                    .accessibilityIdentifier("edit_prescription_\(index)")
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
            .accessibilityIdentifier("exercise_editor_scroll")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTemplateEquipment) {
                StrengthEquipmentSetupView(exerciseName: editableExercise.name, equipment: editableExercise.loadEquipment) { setup in
                    editableExercise.loadEquipment = setup
                }
            }
            .sheet(item: $prescriptionSet) { set in
                WorkoutPrescriptionEditorView(exerciseType: editableExercise.type, set: set) { updated in
                    guard let index = editableExercise.sets.firstIndex(where: { $0.id == updated.id }) else { return }
                    editableExercise.sets[index] = updated
                }
            }
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
                .disabled(editableExercise.progressionPolicy?.validationMessage(for: editableExercise) != nil)
                .accessibilityIdentifier("exercise_editor_save")
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
            editableExercise.sets[index].prescription = nil
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
    @State private var selectedEquipment: ExerciseList.EquipmentFamily?
    @State private var customExerciseName = ""
    @State private var customExerciseType: ExerciseType = .strength
    @State private var customMovements: [WorkoutCustomMovement] = []
    @State private var editingCustomID: String?
    @State private var customCue = ""
    @State private var customError: String?
    private let customOwnerID = DIContainer.shared.authService.currentUserID

    var onSelect: (ExercisePickerDraft) -> Void
    var onSelectMultiple: (([ExercisePickerDraft]) -> Void)?
    private let isReplacing: Bool
    @State private var selectsMultiple = false
    @State private var selectedMovements: [ExercisePickerDraft] = []
    @State private var favoriteKeys: [String] = []
    @State private var recentKeys: [String] = []
    @State private var expandingCustom = false

    init(isReplacing: Bool = false, onSelectMultiple: (([ExercisePickerDraft]) -> Void)? = nil, onSelect: @escaping (ExercisePickerDraft) -> Void) {
        self.isReplacing = isReplacing
        self.onSelectMultiple = onSelectMultiple; self.onSelect = onSelect
    }

    private let categorizedExercises = ExerciseList.categorizedExercises

    private var categories: [String] {
        ["All"] + categorizedExercises.keys.sorted()
    }

    private var visibleEntries: [ExercisePickerEntry] {
        let entries = categorizedExercises.flatMap { category, exercises in
            exercises.map { ExercisePickerEntry(name: $0, category: category) }
        }
        let categoryFiltered = selectedCategory == "All" ? entries : entries.filter { $0.category == selectedCategory }
        let equipmentFiltered = selectedEquipment.map { selected in
            categoryFiltered.filter { ExerciseList.equipment(for: $0.name) == selected }
        } ?? categoryFiltered
        guard !searchText.trimmed.isEmpty else {
            return sortedForDiscovery(equipmentFiltered)
        }
        return sortedForDiscovery(equipmentFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText)
                || WorkoutMovementCatalog.canonicalName(searchText) == $0.name
                || ExerciseList.equipment(for: $0.name).rawValue.localizedCaseInsensitiveContains(searchText)
        })
    }

    private var hasActiveFilters: Bool {
        selectedCategory != "All" || selectedEquipment != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if !isReplacing {
                        AppScreenHeader(
                            eyebrow: "Routine Builder",
                            title: "Add a Movement",
                            subtitle: "Search the exercise library or create one that is specific to your training."
                        )
                    }

                    if onSelectMultiple != nil {
                        Toggle("Select several movements", isOn: $selectsMultiple)
                            .accessibilityIdentifier("exercise_picker_multiple")
                        if selectsMultiple { Text("\(selectedMovements.count) selected in tap order. Nothing is added until Add selected.").appTextRole(.caption).foregroundStyle(.secondary) }
                    }
                    if !customMovements.filter({ !$0.archived }).isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("Saved custom movements").appTextRole(.sectionTitle)
                            ForEach(customMovements.filter { !$0.archived && (searchText.trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)) }) { movement in
                                HStack {
                                    Button(movement.name) {
                                        guard let customOwnerID else { return }
                                        choose(ExercisePickerDraft(name: movement.name, category: "Custom", type: movement.type, movementIdentity: movement.identity(ownerID: customOwnerID)))
                                    }.frame(minHeight: 44)
                                    Spacer()
                                    Menu {
                                        Button(favoriteKeys.contains(selectionKey(name: movement.name, identity: movement.identity(ownerID: customOwnerID ?? ""))) ? "Remove favorite" : "Favorite movement") {
                                            toggleFavorite(selectionKey(name: movement.name, identity: movement.identity(ownerID: customOwnerID ?? "")))
                                        }
                                        Button("Rename or edit cue") { expandingCustom = true; editingCustomID = movement.id; customExerciseName = movement.name; customExerciseType = movement.type; customCue = movement.cue }
                                        Button("Archive from selection") {
                                            do {
                                                guard let customOwnerID else { throw WorkoutBlockError.accountChanged }
                                                var archived = movement; archived.archived = true
                                                try WorkoutCustomMovementStore().save(archived, userID: customOwnerID)
                                                customMovements = try WorkoutCustomMovementStore().entries(userID: customOwnerID)
                                            } catch { customError = error.localizedDescription }
                                        }
                                    } label: { Image(systemName: "ellipsis") }.buttonStyle(AppIconButtonStyle(.plain))
                                }
                            }
                        }.appSurface(.quiet)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Exercise Library",
                            subtitle: "\(visibleEntries.count) matches · favorites and recent first"
                        ) {
                            if hasActiveFilters {
                                Button("Clear") {
                                    selectedCategory = "All"
                                    selectedEquipment = nil
                                }
                                .appTextRole(.secondary)
                                .foregroundStyle(AppPalette.brandText)
                                .accessibilityLabel("Clear exercise filters")
                            }
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("MUSCLE")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.compact) {
                                    ForEach(categories, id: \.self) { category in
                                        ExerciseFilterChip(
                                            title: category,
                                            icon: category == "All" ? "square.grid.2x2" : nil,
                                            isSelected: selectedCategory == category
                                        ) {
                                            selectedCategory = category
                                        }
                                    }
                                }
                                .padding(.horizontal, 1)
                            }

                            Text("EQUIPMENT")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppSpacing.compact) {
                                    ExerciseFilterChip(
                                        title: "All",
                                        icon: "square.grid.2x2",
                                        isSelected: selectedEquipment == nil
                                    ) {
                                        selectedEquipment = nil
                                    }

                                    ForEach(ExerciseList.EquipmentFamily.allCases) { equipment in
                                        ExerciseFilterChip(
                                            title: equipment.rawValue,
                                            icon: equipment.icon,
                                            isSelected: selectedEquipment == equipment
                                        ) {
                                            selectedEquipment = equipment
                                        }
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        }
                        .appSurface(.quiet)

                        if visibleEntries.isEmpty {
                            GuidanceEmptyState(
                                icon: "magnifyingglass",
                                title: "No exercises found",
                                message: "Try a different search term, or add a custom exercise."
                            )
                        } else {
                            LazyVStack(spacing: AppSpacing.compact) {
                                ForEach(visibleEntries) { entry in
                                    ExercisePickerRow(entry: entry, isSelected: selectedMovements.contains(where: { $0.name == entry.name })) {
                                        choose(ExercisePickerDraft(name: entry.name, category: entry.category,
                                            type: RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category),
                                            movementIdentity: WorkoutMovementCatalog.identity(for: entry.name)))
                                    }
                                    .contextMenu {
                                        let key = selectionKey(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name))
                                        Button(favoriteKeys.contains(key) ? "Remove favorite" : "Favorite movement") { toggleFavorite(key) }
                                    }
                                    .accessibilityHint(favoriteKeys.contains(selectionKey(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name))) ? "Favorite movement. Actions include Remove favorite." : "Actions include Favorite movement.")
                                    .accessibilityAction(named: Text(favoriteKeys.contains(selectionKey(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name))) ? "Remove favorite" : "Favorite movement")) {
                                        toggleFavorite(selectionKey(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name)))
                                    }
                                }
                            }
                        }
                    }
                    DisclosureGroup("Create or edit a custom movement", isExpanded: $expandingCustom) {
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

                            TextField("Optional setup cue", text: $customCue, axis: .vertical).routineInputStyle()
                            if let duplicate = customMovements.first(where: { !$0.archived && $0.name.caseInsensitiveCompare(customExerciseName.trimmed) == .orderedSame && $0.id != editingCustomID }) {
                                Text("A saved movement already uses this name: \(duplicate.name). Add it from Saved custom movements below.").appTextRole(.caption).foregroundStyle(AppPalette.caution)
                            }
                            if let customError { Text(customError).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
                            Button(action: selectCustomExercise) {
                                Label("Add Custom Movement", systemImage: "plus")
                            }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .disabled(customExerciseName.trimmed.isEmpty)
                        }
                        .appSurface(.quiet)
                    }

                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if selectsMultiple {
                    Button("Add selected \(selectedMovements.count) movements") { recordSelections(selectedMovements); onSelectMultiple?(selectedMovements); dismiss() }
                        .buttonStyle(AppActionButtonStyle(.primary)).disabled(selectedMovements.isEmpty)
                        .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                        .accessibilityIdentifier("exercise_picker_add_selected")
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .onAppear {
                do {
                    if let customOwnerID {
                        customMovements = try WorkoutCustomMovementStore().entries(userID: customOwnerID)
                        let preferences = try WorkoutMovementSelectionStore().load(userID: customOwnerID)
                        favoriteKeys = preferences.favorites; recentKeys = preferences.recent
                    }
                } catch { customError = error.localizedDescription }
            }
            .navigationTitle(isReplacing ? "Choose replacement" : "Add Exercise")
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

    private func choose(_ movement: ExercisePickerDraft) {
        if selectsMultiple {
            if let index = selectedMovements.firstIndex(where: { $0.movementIdentity == movement.movementIdentity && $0.name == movement.name }) { selectedMovements.remove(at: index) } else { selectedMovements.append(movement) }
        } else { recordSelections([movement]); onSelect(movement); dismiss() }
    }
    private func selectionKey(name: String, identity: WorkoutMovementIdentity?) -> String { WorkoutMovementSelectionStore.key(name: name, identity: identity) }
    private func sortedForDiscovery(_ entries: [ExercisePickerEntry]) -> [ExercisePickerEntry] {
        func rank(_ entry: ExercisePickerEntry) -> Int {
            let key = selectionKey(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name))
            if favoriteKeys.contains(key) { return -1 }
            return recentKeys.firstIndex(of: key) ?? 1_000
        }
        return entries.sorted { rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1) }
    }
    private func recordSelections(_ movements: [ExercisePickerDraft]) {
        guard let customOwnerID else { return }
        do { try WorkoutMovementSelectionStore().record(movements.map { selectionKey(name: $0.name, identity: $0.movementIdentity) }, userID: customOwnerID) } catch { customError = "The movements were selected, but recent choices could not be saved on this device." }
    }
    private func toggleFavorite(_ key: String) {
        guard let customOwnerID else { return }
        do {
            let store = WorkoutMovementSelectionStore()
            try store.setFavorite(key, enabled: !favoriteKeys.contains(key), userID: customOwnerID)
            favoriteKeys = try store.load(userID: customOwnerID).favorites
        } catch { customError = error.localizedDescription }
    }
    private func selectCustomExercise() {
        do {
            guard let customOwnerID else { throw WorkoutBlockError.accountChanged }
            let movement = WorkoutCustomMovement(id: editingCustomID ?? UUID().uuidString, name: customExerciseName.trimmed,
                type: customExerciseType, cue: customCue)
            try WorkoutCustomMovementStore().save(movement, userID: customOwnerID)
            let selected = ExercisePickerDraft(name: movement.name, category: "Custom", type: movement.type,
                movementIdentity: movement.identity(ownerID: customOwnerID))
            if selectsMultiple, let index = selectedMovements.firstIndex(where: { $0.movementIdentity == selected.movementIdentity }) { selectedMovements[index] = selected } else { choose(selected) }
            if selectsMultiple { customExerciseName = ""; customCue = ""; editingCustomID = nil; customMovements = try WorkoutCustomMovementStore().entries(userID: customOwnerID) }
        } catch { customError = error.localizedDescription }
    }
}
