import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RoutineEditorView: View {
    @ObservedObject var workoutService: WorkoutService
    var onSave: (WorkoutRoutine) -> Void

    @Environment(\.dismiss) private var dismiss

    private let sourceRoutine: WorkoutRoutine

    @State private var routineName: String
    @State private var routineNotes: String
    @State private var exercises: [RoutineExercise]
    @State private var showingExercisePicker = false
    @State private var exerciseToEdit: RoutineExercise?

    private var canSave: Bool {
        !routineName.trimmed.isEmpty
    }

    private var totalSetCount: Int {
        exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
    }

    private var estimatedMinutes: Int {
        let activeSeconds = totalSetCount * 55
        let restSeconds = exercises.reduce(0) { partial, exercise in
            let sets = max(exercise.sets.count, exercise.targetSets)
            return partial + max(sets - 1, 0) * max(exercise.restTimeInSeconds, 0)
        }
        guard totalSetCount > 0 else { return 0 }
        return max(5, Int(ceil(Double(activeSeconds + restSeconds) / 60.0)))
    }

    init(workoutService: WorkoutService, routine: WorkoutRoutine, onSave: @escaping (WorkoutRoutine) -> Void) {
        self.workoutService = workoutService
        self.sourceRoutine = routine
        self._routineName = State(initialValue: routine.name)
        self._routineNotes = State(initialValue: routine.notes ?? "")
        self._exercises = State(initialValue: routine.exercises)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    RoutineEditorHeaderCard(
                        routineName: routineName,
                        exerciseCount: exercises.count,
                        setCount: totalSetCount,
                        estimatedMinutes: estimatedMinutes,
                        exercises: exercises
                    )

                    RoutineBasicsCard(
                        routineName: $routineName,
                        routineNotes: $routineNotes
                    )

                    RoutineTemplateStrip(
                        templates: RoutineEditorTemplate.templates,
                        onApply: applyTemplate
                    )

                    RoutineExerciseBuilderCard(
                        exercises: exercises,
                        onAddExercise: { showingExercisePicker = true },
                        onEdit: { exerciseToEdit = $0 },
                        onDuplicate: duplicateExercise,
                        onDelete: deleteExercise,
                        onMove: moveExercise
                    )
                }
                .padding()
                .padding(.bottom, 14)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(routineName.trimmed.isEmpty ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveRoutine)
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    saveRoutine()
                } label: {
                    Label("Save Routine", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { draft in
                    addExercise(from: draft)
                    showingExercisePicker = false
                }
            }
            .sheet(item: $exerciseToEdit) { exercise in
                ExerciseSetEditorView(
                    exercise: exercise,
                    onSave: { updatedExercise in
                        if let index = exercises.firstIndex(where: { $0.id == updatedExercise.id }) {
                            exercises[index] = updatedExercise
                        }
                    }
                )
            }
        }
    }

    private func saveRoutine() {
        let updatedRoutine = WorkoutRoutine(
            id: sourceRoutine.id,
            userID: sourceRoutine.userID,
            name: routineName.trimmed,
            dateCreated: sourceRoutine.dateCreated,
            exercises: exercises,
            notes: routineNotes.trimmed.isEmpty ? nil : routineNotes.trimmed
        )
        onSave(updatedRoutine)
        dismiss()
    }

    private func applyTemplate(_ template: RoutineEditorTemplate) {
        if routineName.trimmed.isEmpty || routineName == "New Routine" {
            routineName = template.name
        }
        exercises.append(contentsOf: template.exercises.map(makeExercise))
        HapticManager.instance.feedback(.medium)
    }

    private func addExercise(from draft: ExercisePickerDraft) {
        exercises.append(makeExercise(name: draft.name, category: draft.category, type: draft.type))
        HapticManager.instance.feedback(.light)
    }

    private func duplicateExercise(_ exercise: RoutineExercise) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        var copy = exercise
        copy.id = UUID().uuidString
        copy.sets = copy.sets.map { set in
            var newSet = set
            newSet.id = UUID().uuidString
            newSet.isCompleted = false
            newSet.reps = 0
            newSet.weight = 0
            newSet.distance = 0
            newSet.durationInSeconds = 0
            return newSet
        }
        exercises.insert(copy, at: index + 1)
    }

    private func deleteExercise(_ exercise: RoutineExercise) {
        exercises.removeAll { $0.id == exercise.id }
    }

    private func moveExercise(_ exercise: RoutineExercise, direction: RoutineMoveDirection) {
        guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = max(index - 1, 0)
        case .down:
            targetIndex = min(index + 1, exercises.count - 1)
        }
        guard targetIndex != index else { return }
        exercises.move(fromOffsets: IndexSet(integer: index), toOffset: targetIndex > index ? targetIndex + 1 : targetIndex)
    }

    private func makeExercise(_ spec: RoutineEditorExerciseSpec) -> RoutineExercise {
        makeExercise(name: spec.name, category: spec.category, type: spec.type)
    }

    private func makeExercise(name: String, category: String?, type: ExerciseType) -> RoutineExercise {
        let defaults = RoutineEditorDefaults.defaults(for: type)
        let setTarget = RoutineEditorDefaults.setTarget(for: type, target: defaults.target)
        return RoutineExercise(
            name: name,
            type: type,
            sets: Array(repeating: ExerciseSet(target: setTarget), count: defaults.sets),
            restTimeInSeconds: defaults.rest,
            targetSets: defaults.sets,
            targetReps: defaults.target
        )
    }
}

private enum RoutineMoveDirection {
    case up
    case down
}

private struct RoutineEditorHeaderCard: View {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Routine Builder")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(routineName.trimmed.isEmpty ? "Untitled Routine" : routineName)
                        .appFont(size: 28, weight: .black)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Text(balanceText)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.brandPrimary)
                        .lineLimit(2)
                }

                Spacer()

                Text(ExerciseEmojiMapper.getEmoji(for: exercises.first?.name ?? routineName))
                    .font(.system(size: 30))
                    .frame(width: 58, height: 58)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                RoutineEditorMetric(title: "Exercises", value: "\(exerciseCount)", icon: "dumbbell.fill", color: .brandPrimary)
                RoutineEditorMetric(title: "Sets", value: "\(setCount)", icon: "checkmark.seal.fill", color: .accentPositive)
                RoutineEditorMetric(title: "Time", value: estimatedMinutes > 0 ? "\(estimatedMinutes)m" : "-", icon: "clock.fill", color: .orange)
            }
        }
        .asCard()
    }
}

private struct RoutineEditorMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)

            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RoutineBasicsCard: View {
    @Binding var routineName: String
    @Binding var routineNotes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Basics", icon: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 8) {
                Text("Routine Name")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                TextField("Push Day, Lower A, Conditioning...", text: $routineName)
                    .appFont(size: 18, weight: .bold)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Coach Notes")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                TextEditor(text: $routineNotes)
                    .appFont(size: 14)
                    .frame(minHeight: 74)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .asCard()
    }
}

private struct RoutineTemplateStrip: View {
    let templates: [RoutineEditorTemplate]
    let onApply: (RoutineEditorTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Fast Starts", icon: "bolt.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(templates) { template in
                        Button {
                            onApply(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: template.icon)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(template.color)
                                        .frame(width: 30, height: 30)
                                        .background(template.color.opacity(0.12), in: Circle())
                                    Spacer()
                                    Text("+\(template.exercises.count)")
                                        .appFont(size: 11, weight: .bold)
                                        .foregroundColor(template.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(template.color.opacity(0.10), in: Capsule())
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .appFont(size: 15, weight: .bold)
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                    Text(template.subtitle)
                                        .appFont(size: 12, weight: .semibold)
                                        .foregroundColor(Color(UIColor.secondaryLabel))
                                        .lineLimit(2)
                                }
                            }
                            .padding()
                            .frame(width: 184, alignment: .leading)
                            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .asCard()
    }
}

private struct RoutineExerciseBuilderCard: View {
    let exercises: [RoutineExercise]
    let onAddExercise: () -> Void
    let onEdit: (RoutineExercise) -> Void
    let onDuplicate: (RoutineExercise) -> Void
    let onDelete: (RoutineExercise) -> Void
    let onMove: (RoutineExercise, RoutineMoveDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Exercise Plan", icon: "list.bullet.clipboard.fill")

                Spacer()

                Button(action: onAddExercise) {
                    Label("Add", systemImage: "plus")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.brandPrimary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if exercises.isEmpty {
                RoutineEmptyBuilderCard(onAddExercise: onAddExercise)
            } else {
                VStack(spacing: 12) {
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
        .asCard()
    }
}

private struct RoutineExerciseEditorRow: View {
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
        HStack(alignment: .top, spacing: 12) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Text("\(index + 1)")
                            .appFont(size: 12, weight: .black)
                            .foregroundColor(exercise.type.color)
                        Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                            .font(.title3)
                    }
                    .frame(width: 44, height: 50)
                    .background(exercise.type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        Text("\(setCount) sets - \(targetText) - \(RoutineEditorDefaults.restLabel(exercise.restTimeInSeconds))")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 10) {
                Label(exercise.type.shortTitle, systemImage: exercise.type.icon)
                    .appFont(size: 10, weight: .bold)
                    .foregroundColor(exercise.type.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(exercise.type.color.opacity(0.10), in: Capsule())

                HStack(spacing: 8) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(isFirst)

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(isLast)

                    Button(action: onDuplicate) {
                        Image(systemName: "plus.square.on.square")
                    }

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                }
                .font(.system(size: 13, weight: .bold))
                .buttonStyle(.borderless)
                .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RoutineEmptyBuilderCard: View {
    let onAddExercise: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.brandPrimary)
                .frame(width: 68, height: 68)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("Build the first block")
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Add movements manually or tap a fast-start template above.")
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)

            Button(action: onAddExercise) {
                Label("Add Exercise", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
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
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    ExerciseEditorHero(exercise: editableExercise)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Movement", icon: "slider.horizontal.3")

                        TextField("Exercise name", text: $editableExercise.name)
                            .appFont(size: 18, weight: .bold)
                            .padding(12)
                            .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                    .asCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Prescription", icon: "target")

                        Stepper("Sets: \(editableExercise.targetSets)", value: $editableExercise.targetSets, in: 1...15) { _ in
                            updateSetCount()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(editableExercise.type.targetLabel)
                                .appFont(size: 12, weight: .bold)
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            TextField(editableExercise.type.targetPlaceholder, text: $editableExercise.targetReps)
                                .appFont(size: 16, weight: .semibold)
                                .padding(12)
                                .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onChange(of: editableExercise.targetReps) { _, _ in
                                    applyTargetToAllSets()
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rest")
                                .appFont(size: 12, weight: .bold)
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            HStack(spacing: 8) {
                                ForEach(editableExercise.type.restPresets, id: \.self) { seconds in
                                    Button {
                                        editableExercise.restTimeInSeconds = seconds
                                    } label: {
                                        Text(RoutineEditorDefaults.restLabel(seconds))
                                            .appFont(size: 12, weight: .bold)
                                            .foregroundColor(editableExercise.restTimeInSeconds == seconds ? .white : editableExercise.type.color)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 8)
                                            .background(
                                                editableExercise.restTimeInSeconds == seconds ? editableExercise.type.color : editableExercise.type.color.opacity(0.10),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .asCard()

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel(title: "Set Targets", icon: "list.number")
                            Spacer()
                            Button("Apply All") {
                                applyTargetToAllSets()
                            }
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.brandPrimary)
                        }

                        ForEach(editableExercise.sets.indices, id: \.self) { index in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .appFont(size: 12, weight: .black)
                                    .foregroundColor(editableExercise.type.color)
                                    .frame(width: 30, height: 30)
                                    .background(editableExercise.type.color.opacity(0.10), in: Circle())

                                TextField("Target", text: Binding(
                                    get: { editableExercise.sets[index].target ?? "" },
                                    set: { editableExercise.sets[index].target = $0.trimmed.isEmpty ? nil : $0 }
                                ))
                                .appFont(size: 14, weight: .semibold)
                                .padding(10)
                                .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    .asCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Notes", icon: "note.text")

                        TextEditor(text: Binding(
                            get: { editableExercise.notes ?? "" },
                            set: { editableExercise.notes = $0.trimmed.isEmpty ? nil : $0 }
                        ))
                        .appFont(size: 14)
                        .frame(minHeight: 90)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .asCard()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Swap Options", icon: "arrow.triangle.2.circlepath")

                        Text("Add alternatives separated by commas. These appear in the workout player when you need a substitute.")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))

                        TextField("Dumbbell Bench Press, Push-up", text: $alternativesText)
                            .appFont(size: 14, weight: .semibold)
                            .textInputAutocapitalization(.words)
                            .padding(12)
                            .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .asCard()
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        normalizeExerciseBeforeSave()
                        onSave(editableExercise)
                        dismiss()
                    }
                    .disabled(editableExercise.name.trimmed.isEmpty)
                }
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
}

private struct ExerciseEditorHero: View {
    let exercise: RoutineExercise

    var body: some View {
        HStack(spacing: 14) {
            Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                .font(.system(size: 32))
                .frame(width: 64, height: 64)
                .background(exercise.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name.trimmed.isEmpty ? "New Exercise" : exercise.name)
                    .appFont(size: 23, weight: .black)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text("\(exercise.targetSets) sets - \(RoutineEditorDefaults.setTarget(for: exercise.type, target: exercise.targetReps))")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()
        }
        .asCard()
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
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Custom Movement", icon: "plus.circle.fill")

                        HStack(spacing: 10) {
                            TextField("Add your own exercise", text: $customExerciseName)
                                .appFont(size: 15, weight: .semibold)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(Color.backgroundPrimary.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                selectCustomExercise()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 42, height: 42)
                                    .background(Color.brandPrimary, in: Circle())
                            }
                            .disabled(customExerciseName.trimmed.isEmpty)
                        }

                        Picker("Type", selection: $customExerciseType) {
                            ForEach(ExerciseType.allCases, id: \.self) { type in
                                Text(type.shortTitle).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .asCard()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Exercise Library", icon: "magnifyingglass")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        Text(category)
                                            .appFont(size: 12, weight: .bold)
                                            .foregroundColor(selectedCategory == category ? .white : .brandPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(selectedCategory == category ? Color.brandPrimary : Color.brandPrimary.opacity(0.10), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if visibleEntries.isEmpty {
                            Text("No exercises found.")
                                .appFont(size: 14, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 10) {
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
                    .asCard()
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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

private struct ExercisePickerRow: View {
    let entry: ExercisePickerEntry
    let onSelect: () -> Void

    private var type: ExerciseType {
        RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(ExerciseEmojiMapper.getEmoji(for: entry.name))
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text(entry.category)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Label(type.shortTitle, systemImage: type.icon)
                    .appFont(size: 10, weight: .bold)
                    .foregroundColor(type.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(type.color.opacity(0.10), in: Capsule())
            }
            .padding(10)
            .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SectionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.brandPrimary)
            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
        }
    }
}

struct ExercisePickerDraft {
    let name: String
    let category: String?
    let type: ExerciseType
}

private struct ExercisePickerEntry: Identifiable, Comparable {
    var id: String { "\(category)-\(name)" }
    let name: String
    let category: String

    static func < (lhs: ExercisePickerEntry, rhs: ExercisePickerEntry) -> Bool {
        if lhs.category == rhs.category {
            return lhs.name < rhs.name
        }
        return lhs.category < rhs.category
    }
}

private struct RoutineEditorExerciseSpec: Identifiable {
    var id: String { name }
    let name: String
    let category: String?
    let type: ExerciseType
}

private struct RoutineEditorTemplate: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
    let color: Color
    let exercises: [RoutineEditorExerciseSpec]

    static let templates: [RoutineEditorTemplate] = [
        RoutineEditorTemplate(
            name: "Push Day",
            subtitle: "Chest, shoulders, triceps",
            icon: "arrow.up.forward.circle.fill",
            color: .brandPrimary,
            exercises: [
                RoutineEditorExerciseSpec(name: "Barbell Bench Press", category: "Chest", type: .strength),
                RoutineEditorExerciseSpec(name: "Dumbbell Shoulder Press", category: "Shoulders", type: .strength),
                RoutineEditorExerciseSpec(name: "Incline Dumbbell Bench Press", category: "Chest", type: .strength),
                RoutineEditorExerciseSpec(name: "Triceps Pushdown (Cable)", category: "Triceps", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Pull Day",
            subtitle: "Back, biceps, rear delts",
            icon: "arrow.down.backward.circle.fill",
            color: .accentPositive,
            exercises: [
                RoutineEditorExerciseSpec(name: "Pull-up", category: "Back", type: .strength),
                RoutineEditorExerciseSpec(name: "Barbell Bent-over Row", category: "Back", type: .strength),
                RoutineEditorExerciseSpec(name: "Face Pull", category: "Shoulders", type: .strength),
                RoutineEditorExerciseSpec(name: "Dumbbell Curl", category: "Biceps", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Lower Body",
            subtitle: "Squat, hinge, single leg",
            icon: "figure.strengthtraining.traditional",
            color: .orange,
            exercises: [
                RoutineEditorExerciseSpec(name: "Barbell Back Squat", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Romanian Deadlift (RDL)", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Bulgarian Split Squat", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Standing Calf Raise", category: "Legs", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Conditioning",
            subtitle: "Short cardio and core finisher",
            icon: "heart.fill",
            color: .red,
            exercises: [
                RoutineEditorExerciseSpec(name: "Rowing Machine", category: "Cardio", type: .cardio),
                RoutineEditorExerciseSpec(name: "Jump Rope", category: "Cardio", type: .cardio),
                RoutineEditorExerciseSpec(name: "Plank", category: "Abs & Core", type: .flexibility),
                RoutineEditorExerciseSpec(name: "Burpees", category: "Cardio", type: .cardio)
            ]
        )
    ]
}

private enum RoutineEditorDefaults {
    static func defaults(for type: ExerciseType) -> (sets: Int, target: String, rest: Int) {
        switch type {
        case .strength:
            return (3, "8-12", 90)
        case .cardio:
            return (1, "20 min", 0)
        case .flexibility:
            return (3, "45 sec", 30)
        }
    }

    static func setTarget(for type: ExerciseType, target: String) -> String {
        let trimmedTarget = target.trimmed
        guard !trimmedTarget.isEmpty else {
            return defaults(for: type).target
        }

        switch type {
        case .strength:
            let lower = trimmedTarget.lowercased()
            if lower.contains("rep") || lower.contains("amrap") || lower.contains("sec") || lower.contains("min") {
                return trimmedTarget
            }
            return "\(trimmedTarget) reps"
        case .cardio, .flexibility:
            return trimmedTarget
        }
    }

    static func inferredType(name: String, category: String?) -> ExerciseType {
        if category == "Cardio" {
            return .cardio
        }

        let lower = name.lowercased()
        if lower.contains("run") || lower.contains("cycling") || lower.contains("bike") || lower.contains("elliptical") || lower.contains("row") || lower.contains("swim") || lower.contains("jump rope") || lower.contains("burpee") || lower.contains("stair") {
            return .cardio
        }

        if lower.contains("plank") || lower.contains("yoga") || lower.contains("stretch") || lower.contains("mobility") {
            return .flexibility
        }

        return .strength
    }

    static func restLabel(_ seconds: Int) -> String {
        if seconds <= 0 { return "No rest" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
    }
}

private extension ExerciseType {
    var shortTitle: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .flexibility: return "Mobility"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .flexibility: return "figure.flexibility"
        }
    }

    var color: Color {
        switch self {
        case .strength: return .brandPrimary
        case .cardio: return .red
        case .flexibility: return .blue
        }
    }

    var targetLabel: String {
        switch self {
        case .strength: return "Target Reps"
        case .cardio: return "Target Duration or Distance"
        case .flexibility: return "Target Hold"
        }
    }

    var targetPlaceholder: String {
        switch self {
        case .strength: return "8-12"
        case .cardio: return "20 min or 2 miles"
        case .flexibility: return "45 sec"
        }
    }

    var restPresets: [Int] {
        switch self {
        case .strength: return [60, 90, 120, 180]
        case .cardio: return [0, 30, 60, 90]
        case .flexibility: return [0, 15, 30, 45]
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == String {
    var nilIfEmpty: [String]? {
        isEmpty ? nil : self
    }
}
