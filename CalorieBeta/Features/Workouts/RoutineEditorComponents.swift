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

struct RoutineEditorMetric: View {
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

struct RoutineBasicsCard: View {
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

struct RoutineTemplateStrip: View {
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

struct RoutineExerciseBuilderCard: View {
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

struct RoutineEmptyBuilderCard: View {
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

struct ExerciseEditorHero: View {
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

struct ExercisePickerRow: View {
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

struct SectionLabel: View {
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
