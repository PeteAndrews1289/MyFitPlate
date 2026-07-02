import MyFitPlateCore

import SwiftUI

struct TrainingHeroCard: View {
    let activeProgramName: String?
    let routineCount: Int
    let programCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Hub")
                        .appFont(size: 26, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(activeProgramName.map { "Active: \($0)" } ?? "Pick a plan, build a routine, or start a one-off session.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "figure.strengthtraining.traditional")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }

            HStack(spacing: 10) {
                TrainingMetricPill(title: "Programs", value: "\(programCount)", color: .brandPrimary)
                TrainingMetricPill(title: "Routines", value: "\(routineCount)", color: .blue)
                TrainingMetricPill(title: "Status", value: activeProgramName == nil ? "Open" : "Active", color: .accentPositive)
            }
        }
        .asCard()
    }
}

struct TrainingReadinessCard: View {
    let brief: TrainingReadinessBrief

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: brief.icon)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(brief.color)
                    .frame(width: 42, height: 42)
                    .background(brief.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(brief.status)
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(brief.message)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(spacing: 0) {
                    Text("\(brief.score)")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(brief.color)
                    Text("ready")
                        .appFont(size: 10, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(brief.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(brief.signals) { signal in
                    TrainingSignalPill(signal: signal)
                }
            }
        }
        .asCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(brief.status). \(brief.message). Readiness score is \(brief.score) out of 100.")
    }
}

struct TrainingSignalPill: View {
    let signal: TrainingSignal

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: signal.icon)
                .appFont(size: 11, weight: .bold)
                .foregroundColor(signal.color)
                .frame(width: 24, height: 24)
                .background(signal.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(signal.title)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)

                Text(signal.value)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.backgroundSecondary.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Program Week")
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(program.daysOfWeek?.isEmpty == false ? "Your training rhythm at a glance." : "Choose training days to unlock scheduling.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                // DESIGN.md rule 3: progress in words, not bare fractions ("5/7" read as
                // program progress when it meant training days per week).
                Text("\(program.daysOfWeek?.count ?? 0) training days")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.backgroundSecondary.opacity(0.7), in: Capsule())
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
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .asCard()
    }

    private func routine(for weekday: Int) -> WorkoutRoutine? {
        guard let scheduledDays = program.daysOfWeek?.sorted(),
              let dayIndex = scheduledDays.firstIndex(of: weekday),
              !program.routines.isEmpty else {
            return nil
        }

        return program.routines[dayIndex % program.routines.count]
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
                .appFont(size: 11, weight: .bold)
                .foregroundColor(isNext ? .brandPrimary : Color(UIColor.secondaryLabel))

            Text(detail ?? "-")
                .appFont(size: 10, weight: .bold)
                .foregroundColor(isNext ? .brandPrimary : (isActive ? .textPrimary : Color(UIColor.tertiaryLabel)))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isNext ? Color.brandPrimary.opacity(0.15) : Color.backgroundSecondary.opacity(isActive ? 0.9 : 0.45))
                )
                .overlay(
                    Circle()
                        .stroke(isNext ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextWorkout == nil ? "point.topleft.down.curvedto.point.bottomright.up" : "play.circle.fill")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandPrimary)
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
                            .foregroundColor(.white)
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
                    TrainingPathPill(title: "Start a Plan", subtitle: "Use Plan Library", icon: "rectangle.stack.fill", color: .orange)
                    TrainingPathPill(title: "One-off", subtitle: "\(routineCount) saved", icon: "bolt.fill", color: .blue)
                }
            }
        }
        .asCard()
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
        .asCard()
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Program")
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(program.name)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                Text(progressText)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            }

            HStack(spacing: 10) {
                NavigationLink(destination: destination()) {
                    Label("Manage", systemImage: "folder.fill")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash.fill")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .asCard()
    }
}

struct TrainingSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TrainingActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(title)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            Text(subtitle)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct RoutineEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.dashed")
                .appFont(size: 30, weight: .semibold)
                .foregroundColor(.brandPrimary)
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
