import MyFitPlateCore

import SwiftUI

struct TrainingHeroCard: View {
    let activeProgramName: String?
    let routineCount: Int
    let programCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Hub")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text(activeProgramName.map { "Active: \($0)" } ?? "Pick a plan, build a routine, or start a one-off session.")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "figure.strengthtraining.traditional")
                    .appFont(size: 18, weight: .bold)
                    .foregroundStyle(AppPalette.brandText)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Programs", value: "\(programCount)", accent: AppPalette.brand),
                AppMetricItem(label: "Routines", value: "\(routineCount)", accent: AppPalette.effort),
                AppMetricItem(
                    label: "Status",
                    value: activeProgramName == nil ? "Open" : "Active",
                    accent: AppPalette.positive
                )
            ])
        }
        .appSurface(.emphasized, radius: AppRadius.hero)
    }
}

struct TrainingReadinessCard: View {
    let brief: TrainingReadinessBrief

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Training Readiness", subtitle: brief.message) {
                Text("\(brief.score)%")
                    .appTextRole(.control)
                    .foregroundStyle(brief.role.color)
                    .monospacedDigit()
                    .accessibilityLabel("Readiness score \(brief.score) out of 100")
            }

            HStack(spacing: AppSpacing.row) {
                AppStatusBadge(brief.status, icon: brief.icon, role: brief.role)
                AppProgressTrack(progress: Double(brief.score) / 100, role: brief.role, height: 7)
            }

            VStack(spacing: 0) {
                ForEach(Array(brief.signals.enumerated()), id: \.element.id) { index, signal in
                    TrainingSignalPill(signal: signal)

                    if index < brief.signals.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityIdentifier("train_readiness")
    }
}

struct TrainingSignalPill: View {
    let signal: TrainingSignal

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: signal.icon)
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(signal.role.color)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            Text(signal.title)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(signal.value)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.title): \(signal.value)")
    }
}

struct TrainingWeekPreviewCard: View {
    let program: WorkoutProgram
    let nextWorkout: (program: WorkoutProgram, routine: WorkoutRoutine, title: String)?

    private let weekdays: [(value: Int, label: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Program Week",
                subtitle: program.daysOfWeek?.isEmpty == false
                    ? "Your training rhythm at a glance."
                    : "Choose training days to unlock scheduling."
            ) {
                // DESIGN.md rule 3: progress in words, not bare fractions ("5/7" read as
                // program progress when it meant training days per week).
                Text("\(program.daysOfWeek?.count ?? 0) training days")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppPalette.control, in: Capsule())
            }

            HStack(spacing: 7) {
                ForEach(weekdays, id: \.value) { weekday in
                    let routine = routine(for: weekday.value)
                    TrainingWeekDayChip(
                        label: weekday.label,
                        detail: routine.map { initials(for: $0.name) },
                        isActive: routine != nil,
                        isNext: routine?.id == nextWorkout?.routine.id
                    )
                }
            }

            // DESIGN.md rule 1: no "Next: ..." row here — the hero card above already
            // names the next workout. The schedule hint only appears when it adds info.
            if nextWorkout == nil {
                Text("Set a schedule in program details.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("train_program_week")
    }

    private var routineByWeekday: [Int: WorkoutRoutine] {
        guard let scheduledDays = program.daysOfWeek,
              !scheduledDays.isEmpty,
              !program.routines.isEmpty else {
            return [:]
        }

        let normalizedDays = Set(scheduledDays)
        let calendar = Calendar.current

        if let startDate = program.startDate {
            var routineMap: [Int: WorkoutRoutine] = [:]
            var routineIndex = 0

            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
                let weekday = calendar.component(.weekday, from: date)
                guard normalizedDays.contains(weekday), routineMap[weekday] == nil else { continue }

                routineMap[weekday] = program.routines[routineIndex % program.routines.count]
                routineIndex += 1

                if routineMap.count == normalizedDays.count { break }
            }

            return routineMap
        }

        let sortedDays = normalizedDays.sorted()
        return Dictionary(uniqueKeysWithValues: sortedDays.compactMap { weekday in
            guard let dayIndex = sortedDays.firstIndex(of: weekday) else { return nil }
            return (weekday, program.routines[dayIndex % program.routines.count])
        })
    }

    private func routine(for weekday: Int) -> WorkoutRoutine? {
        routineByWeekday[weekday]
    }

    private func initials(for routineName: String) -> String {
        let words = routineName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let initials = String(words).uppercased()
        return initials.isEmpty ? "W" : initials
    }
}

struct TrainingWeekDayChip: View {
    let label: String
    let detail: String?
    let isActive: Bool
    let isNext: Bool

    // DESIGN.md rule 2: green marks "now", not "scheduled" — only the next session's
    // chip carries brand color; other training days are neutral so the week reads at
    // a glance instead of as a wall of green.
    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .appTextRole(.caption)
                .foregroundStyle(isNext ? AppPalette.brandText : Color.secondary)

            Text(detail ?? "-")
                .appFont(size: 11, weight: .bold)
                .foregroundStyle(isNext ? AppPalette.brandText : (isActive ? AppPalette.text : Color.secondary))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isNext ? AppPalette.brand.opacity(0.10) : AppPalette.control.opacity(isActive ? 1 : 0.45))
                )
                .overlay(
                    Circle()
                        .stroke(isNext ? AppPalette.brand : Color.clear, lineWidth: 1.5)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }
}

struct TrainingDecisionCard: View {
    let nextWorkout: (program: WorkoutProgram, routine: WorkoutRoutine, title: String)?
    let activeProgramName: String?
    let routineCount: Int
    let onStartWorkout: () -> Void
    let onChoosePlan: () -> Void
    let onChooseOneOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextWorkout == nil ? "point.topleft.down.curvedto.point.bottomright.up" : "play.circle.fill")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandForeground)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(nextWorkout == nil ? "Choose Your Training Path" : "Today's Best Next Step")
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(decisionText)
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let nextWorkout {
                Button(action: onStartWorkout) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(nextWorkout.title)
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            Text(nextWorkout.routine.name)
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Label("Start", systemImage: "play.fill")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(AppPalette.onBrand)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.brandPrimary, in: Capsule())
                    }
                    .padding(14)
                    .background(Color.brandPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Button(action: onChoosePlan) {
                        TrainingPathPill(title: "Start a Plan", subtitle: "Use Plan Library", icon: "rectangle.stack.fill", color: AppPalette.achievement)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("start_plan_button")

                    Button(action: onChooseOneOff) {
                        TrainingPathPill(title: "One-off", subtitle: "\(routineCount) saved", icon: "bolt.fill", color: AppPalette.effort)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("one_off_workouts_button")
                }
            }
        }
        .appSurface(.emphasized)
    }

    private var decisionText: String {
        if let activeProgramName {
            return "Continue \(activeProgramName), or choose another route below if today's session needs to change."
        }
        return "Pick a full program for guided progression, or run a one-off routine when you just need a session."
    }
}

struct TrainingPathPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TrainingMetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProgramCompleteCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 44, height: 44)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Program Complete")
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("Great job. Choose a new program or build your next phase when you are ready.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface(.emphasized)
    }
}

struct ActiveProgramManagementCard<Destination: View>: View {
    let program: WorkoutProgram
    let onDelete: () -> Void
    let destination: () -> Destination

    private var progressText: String {
        guard let currentIndex = program.currentProgressIndex else { return "Open" }
        let daysPerWeek = max(program.daysOfWeek?.count ?? 0, 1)
        let totalWorkouts = max(daysPerWeek * 12, program.routines.count)
        return "\(min(currentIndex, totalWorkouts))/\(totalWorkouts)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Current Program", subtitle: program.name) {
                Text(progressText)
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brandText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppPalette.brand.opacity(0.10), in: Capsule())
            }

            HStack(spacing: AppSpacing.compact) {
                NavigationLink(destination: destination()) {
                    Label("Manage", systemImage: "folder.fill")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash.fill")
                }
                .buttonStyle(AppActionButtonStyle(.destructive))
            }
        }
        .appSurface(.quiet)
    }
}

struct TrainingSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppSectionHeader(title: title, subtitle: subtitle)
    }
}

struct TrainingActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .bold)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.compact)

            Image(systemName: "chevron.right")
                .appTextRole(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.row)
        .appSurface(.quiet, padding: 0)
        .contentShape(Rectangle())
    }
}

struct RoutineEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.dashed")
                .appFont(size: 30, weight: .semibold)
                .foregroundColor(.brandForeground)
                .frame(width: 60, height: 60)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No manual routines yet")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Generate an AI program or use manual build to create reusable sessions.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(Color.backgroundSecondary.opacity(0.70), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
