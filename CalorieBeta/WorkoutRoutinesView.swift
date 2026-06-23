import SwiftUI
import FirebaseAuth

struct WorkoutRoutinesView: View {
    @StateObject private var workoutService = WorkoutService()
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService

    @State private var routineToPlay: WorkoutRoutine?
    @State private var showingAIGenerator = false
    @State private var routineToEdit: WorkoutRoutine?

    private let planLibraryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var nextWorkoutInfo: (program: WorkoutProgram, routine: WorkoutRoutine, title: String)? {
        guard let program = workoutService.activeProgram,
              let progressIndex = program.currentProgressIndex,
              !program.routines.isEmpty,
              let daysPerWeek = program.daysOfWeek?.count, daysPerWeek > 0 else {
            return nil
        }

        let totalWorkoutsInProgram = daysPerWeek * 12
        guard progressIndex < totalWorkoutsInProgram else { return nil }

        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }

        let routine = program.routines[routineIndex]
        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Start Week \(weekNumber) · Day \(dayNumber)"

        return (program, routine, title)
    }

    private var trainingBrief: TrainingReadinessBrief {
        let todayLog = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDateInToday(log.date) ? log : nil
        }

        let calories = todayLog?.totalCalories() ?? 0
        let calorieGoal = max(goalSettings.calories ?? 2000, 1)
        let protein = todayLog?.totalMacros().protein ?? 0
        let proteinGoal = max(goalSettings.protein, 1)
        let water = todayLog?.waterTracker?.totalOunces ?? 0
        let waterGoal = max(goalSettings.waterGoal, 1)
        let loggedWorkouts = todayLog?.exercises?.count ?? 0

        let calorieRatio = calories / calorieGoal
        let proteinRatio = protein / proteinGoal
        let waterRatio = water / waterGoal

        var score = 48
        score += calorieRatio >= 0.20 ? 14 : -4
        score += proteinRatio >= 0.35 ? 14 : 0
        score += waterRatio >= 0.35 ? 14 : -3
        score += loggedWorkouts == 0 ? 6 : -6
        score = min(max(score, 25), 95)

        let status: String
        let message: String
        let icon: String
        let color: Color

        if loggedWorkouts > 0 {
            status = "Recovery Mode"
            message = "You already logged activity today. Start another session if it is intentional, or keep the next block easy."
            icon = "moon.zzz.fill"
            color = .blue
        } else if score >= 78 {
            status = "Primed to Train"
            message = "Fuel, hydration, and protein are lining up. This is a good window for a focused session."
            icon = "bolt.fill"
            color = .accentPositive
        } else if waterRatio < 0.25 {
            status = "Hydrate First"
            message = "Log some water before you train. It is the fastest readiness win in the app."
            icon = "drop.fill"
            color = .cyan
        } else if calorieRatio < 0.15 {
            status = "Fuel First"
            message = "You have not logged much food yet. Consider a small meal or snack before a hard session."
            icon = "fork.knife"
            color = .orange
        } else {
            status = "Ready, Build Gradually"
            message = "You are clear to train. Warm up patiently and let the first working set tell you the day."
            icon = "figure.strengthtraining.traditional"
            color = .brandPrimary
        }

        return TrainingReadinessBrief(
            score: score,
            status: status,
            message: message,
            icon: icon,
            color: color,
            signals: [
                TrainingSignal(title: "Fuel", value: calories > 0 ? "\(Int(calories.rounded())) cal" : "Not logged", icon: "flame.fill", color: .orange),
                TrainingSignal(title: "Protein", value: "\(Int(protein.rounded()))/\(Int(proteinGoal.rounded()))g", icon: "bolt.fill", color: .accentProtein),
                TrainingSignal(title: "Water", value: "\(Int(water.rounded()))/\(Int(waterGoal.rounded())) oz", icon: "drop.fill", color: .cyan),
                TrainingSignal(title: "Activity", value: loggedWorkouts == 0 ? "Open" : "\(loggedWorkouts) logged", icon: "figure.run", color: .blue)
            ]
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let nextWorkout = nextWorkoutInfo

                    TrainingHeroCard(
                        activeProgramName: workoutService.activeProgram?.name,
                        routineCount: workoutService.userRoutines.count,
                        programCount: workoutService.userPrograms.count
                    )

                    TrainingReadinessCard(brief: trainingBrief)

                    if workoutService.activeProgram != nil {
                        MuscleRecoveryMapView()
                    }

                    TrainingDecisionCard(
                        nextWorkout: nextWorkout,
                        activeProgramName: workoutService.activeProgram?.name,
                        routineCount: workoutService.userRoutines.count,
                        onStartWorkout: {
                            if let nextWorkout {
                                self.routineToPlay = nextWorkout.routine
                            }
                        }
                    )

                    if let program = workoutService.activeProgram {
                        TrainingWeekPreviewCard(program: program, nextWorkout: nextWorkout)
                    }

                    if let (program, routine, title) = nextWorkout {
                        ContinueProgramCard(
                            program: program,
                            nextWorkout: (routine: routine, title: title),
                            onStartWorkout: {
                                self.routineToPlay = routine
                            }
                        )
                        .environmentObject(workoutService)
                        .environmentObject(goalSettings)
                        .environmentObject(dailyLogService)
                        .environmentObject(achievementService)
                        
                    } else if workoutService.activeProgram != nil {
                        ProgramCompleteCard()
                    }

                    if workoutService.activeProgram == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            TrainingSectionHeader(
                                title: "Plan Library",
                                subtitle: "Choose a ready-made plan, generate one, or build your own."
                            )

                        LazyVGrid(columns: planLibraryColumns, spacing: 12) {
                            NavigationLink(destination: PreBuiltProgramsView()
                                .environmentObject(workoutService)
                                .environmentObject(goalSettings)
                                .environmentObject(dailyLogService)
                                .environmentObject(achievementService)
                            ) {
                                TrainingActionTile(
                                    icon: "rectangle.stack.fill",
                                    title: "Pre-built",
                                    subtitle: "Preview proven plans",
                                    color: .orange
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                showingAIGenerator = true
                            } label: {
                                TrainingActionTile(
                                    icon: "sparkles",
                                    title: "AI Program",
                                    subtitle: "Create from goals",
                                    color: .brandPrimary
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ProgramCreatorView(workoutService: workoutService)) {
                                TrainingActionTile(
                                    icon: "square.and.pencil",
                                    title: "Manual Build",
                                    subtitle: "Design your split",
                                    color: .blue
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: ProgramListView(workoutService: workoutService)
                                .environmentObject(goalSettings)
                                .environmentObject(dailyLogService)
                                .environmentObject(achievementService)
                            ) {
                                TrainingActionTile(
                                    icon: "folder.fill",
                                    title: "Saved Plans",
                                    subtitle: "Manage programs",
                                    color: .accentPositive
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    }

                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: WorkoutHistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.brandPrimary)
                    }
                }
            }
            .onAppear {
                workoutService.fetchRoutinesAndPrograms()
            }
            .fullScreenCover(item: $routineToPlay) { routine in
                WorkoutPlayerView(routine: routine, onWorkoutComplete: {
                    if let program = workoutService.activeProgram, var currentIndex = program.currentProgressIndex {
                        currentIndex += 1
                        var mutableProgram = program
                        mutableProgram.currentProgressIndex = currentIndex

                        Task {
                            await workoutService.saveProgram(mutableProgram)
                        }
                    }
                })
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(workoutService)
                .environmentObject(achievementService)
            }
            .sheet(isPresented: $showingAIGenerator) {
                AIWorkoutGeneratorView()
                    .environmentObject(workoutService)
                    .environmentObject(goalSettings)
            }
            .sheet(item: $routineToEdit) { routine in
                RoutineEditorView(
                    workoutService: workoutService,
                    routine: routine,
                    onSave: { updatedRoutine in
                        Task {
                            try? await workoutService.saveRoutine(updatedRoutine)
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func routineRow(_ routine: WorkoutRoutine) -> some View {
        HStack(spacing: 12) {
            Text(ExerciseEmojiMapper.getEmoji(for: routine.exercises.first?.name ?? routine.name))
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("\(routine.exercises.count) exercises • \(routine.exercises.reduce(0) { $0 + $1.sets.count }) sets")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Spacer()

            Button {
                routineToPlay = routine
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary, in: Circle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit") {
                    routineToEdit = routine
                }
                Button("Delete", role: .destructive) {
                    workoutService.deleteRoutine(routine)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(Color.backgroundPrimary.opacity(0.68), in: Circle())
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TrainingHeroCard: View {
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
                    .font(.system(size: 18, weight: .bold))
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

private struct TrainingReadinessBrief {
    let score: Int
    let status: String
    let message: String
    let icon: String
    let color: Color
    let signals: [TrainingSignal]
}

private struct TrainingSignal: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let icon: String
    let color: Color
}

private struct TrainingReadinessCard: View {
    let brief: TrainingReadinessBrief

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: brief.icon)
                    .font(.system(size: 18, weight: .bold))
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
    }
}

private struct TrainingSignalPill: View {
    let signal: TrainingSignal

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: signal.icon)
                .font(.system(size: 11, weight: .bold))
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
    }
}

private struct TrainingWeekPreviewCard: View {
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

                Text("\(program.daysOfWeek?.count ?? 0)/7")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
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

            HStack(spacing: 9) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.brandPrimary)

                Text(nextWorkout.map { "Next: \($0.routine.name)" } ?? "Set a schedule in program details.")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.brandPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct TrainingWeekDayChip: View {
    let label: String
    let detail: String?
    let isActive: Bool
    let isNext: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .appFont(size: 11, weight: .bold)
                .foregroundColor(isActive ? .brandPrimary : Color(UIColor.secondaryLabel))

            Text(detail ?? "-")
                .appFont(size: 10, weight: .bold)
                .foregroundColor(isActive ? .textPrimary : Color(UIColor.tertiaryLabel))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isActive ? Color.brandPrimary.opacity(isNext ? 0.22 : 0.10) : Color.backgroundSecondary.opacity(0.58))
                )
                .overlay(
                    Circle()
                        .stroke(isNext ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(isNext ? Color.brandPrimary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct TrainingDecisionCard: View {
    let nextWorkout: (program: WorkoutProgram, routine: WorkoutRoutine, title: String)?
    let activeProgramName: String?
    let routineCount: Int
    let onStartWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: nextWorkout == nil ? "point.topleft.down.curvedto.point.bottomright.up" : "play.circle.fill")
                    .font(.system(size: 18, weight: .bold))
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

private struct TrainingPathPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
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

private struct TrainingMetricPill: View {
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

private struct ProgramCompleteCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .bold))
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

private struct TrainingSectionHeader: View {
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

private struct TrainingActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
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

private struct RoutineEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.square.dashed")
                .font(.system(size: 30, weight: .semibold))
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


struct ProgramListView: View {
    @ObservedObject var workoutService: WorkoutService
    
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var showingProgramCreator = false
    @State private var programToEdit: WorkoutProgram? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SavedProgramsHeader(
                    programCount: workoutService.userPrograms.count,
                    activeProgramName: workoutService.activeProgram?.name
                )

                if workoutService.userPrograms.isEmpty {
                    SavedProgramsEmptyState {
                        programToEdit = nil
                        showingProgramCreator = true
                    }
                } else {
                    ForEach(workoutService.userPrograms) { program in
                        savedProgramCard(program)
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Saved Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    programToEdit = nil
                    showingProgramCreator = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingProgramCreator) {
            ProgramCreatorView(workoutService: workoutService, programToEdit: programToEdit)
        }
    }

    @ViewBuilder
    private func savedProgramCard(_ program: WorkoutProgram) -> some View {
        SavedProgramCard(
            program: program,
            isActive: isActive(program),
            onSetActive: {
                workoutService.setActiveProgram(program)
            },
            onEdit: {
                programToEdit = program
                showingProgramCreator = true
            },
            onDelete: {
                workoutService.deleteProgram(program)
            }
        ) {
            ProgramDetailView(program: program)
                .environmentObject(workoutService)
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(achievementService)
        }
    }

    private func isActive(_ program: WorkoutProgram) -> Bool {
        guard let activeProgram = workoutService.activeProgram else { return false }
        if let activeProgramID = activeProgram.id, let programID = program.id {
            return activeProgramID == programID
        }
        return activeProgram.name == program.name
    }
}

private struct SavedProgramsHeader: View {
    let programCount: Int
    let activeProgramName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Plans")
                        .appFont(size: 25, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(activeProgramName.map { "Active now: \($0)" } ?? "Select a plan as active, open details, or adjust a schedule.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text("\(programCount)")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.brandPrimary)

                    Text("plans")
                        .appFont(size: 10, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(width: 52, height: 52)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }
        }
        .asCard()
    }
}

private struct SavedProgramsEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("No saved plans yet")
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Choose a pre-built program, generate one with AI, or build a plan manually.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onCreate) {
                Label("Build a Plan", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .asCard()
    }
}

private struct SavedProgramCard<Destination: View>: View {
    let program: WorkoutProgram
    let isActive: Bool
    let onSetActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let destination: () -> Destination

    private var trainingDays: Int {
        program.daysOfWeek?.count ?? 0
    }

    private var totalSetCount: Int {
        program.routines.reduce(0) { partial, routine in
            partial + routine.exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }
        }
    }

    private var totalWorkouts: Int {
        max(trainingDays * 12, program.routines.count)
    }

    private var progressText: String {
        let completed = min(program.currentProgressIndex ?? 0, totalWorkouts)
        return "\(completed)/\(totalWorkouts)"
    }

    private var statusTitle: String {
        if isActive { return "Active" }
        return program.startDate == nil ? "Needs Schedule" : "Saved"
    }

    private var statusColor: Color {
        if isActive { return .accentPositive }
        return program.startDate == nil ? .orange : .brandPrimary
    }

    private var scheduleText: String {
        guard let startDate = program.startDate?.dateValue() else {
            return "No start date"
        }
        return "Starts \(startDate.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActive ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(statusColor)
                    .frame(width: 42, height: 42)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SavedProgramStatusPill(title: statusTitle, color: statusColor)

                        Text(scheduleText)
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Text(program.name)
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(program.routines.count) routine rotation")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                        .background(Color.backgroundPrimary.opacity(0.68), in: Circle())
                }
            }

            HStack(spacing: 10) {
                SavedProgramMetric(title: "Progress", value: progressText, color: .brandPrimary)
                SavedProgramMetric(title: "Days/wk", value: trainingDays == 0 ? "Unset" : "\(trainingDays)", color: .blue)
                SavedProgramMetric(title: "Sets", value: "\(totalSetCount)", color: .accentPositive)
            }

            HStack(spacing: 10) {
                NavigationLink(destination: destination()) {
                    Label("Details", systemImage: "doc.text.magnifyingglass")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onSetActive) {
                    Label(isActive ? "Active" : "Set Active", systemImage: isActive ? "checkmark.circle.fill" : "target")
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(isActive ? .accentPositive : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isActive ? Color.accentPositive.opacity(0.12) : Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isActive)
            }
        }
        .asCard()
    }
}

private struct SavedProgramStatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .appFont(size: 10, weight: .bold)
            .foregroundColor(color)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct SavedProgramMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
import SwiftUI

enum MuscleGroup: String, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case legs = "Legs"
    case arms = "Arms"
    case core = "Core"
    case shoulders = "Shoulders"
    
    var icon: String {
        switch self {
        case .chest: return "shield.fill" // Or figure.strengthtraining.traditional
        case .back: return "figure.flexibility"
        case .legs: return "figure.walk"
        case .arms: return "figure.arms.open"
        case .core: return "circle.grid.2x2.fill"
        case .shoulders: return "figure.stand"
        }
    }
}

struct MuscleRecovery: Identifiable {
    var id: String { group.rawValue }
    let group: MuscleGroup
    let lastTrained: Date?
    
    var recoveryPercentage: Double {
        guard let lastTrained = lastTrained else { return 1.0 }
        let hoursSince = max(0, Date().timeIntervalSince(lastTrained) / 3600)
        let maxRecoveryTime: Double = 72.0
        let percent = min(1.0, hoursSince / maxRecoveryTime)
        return percent
    }
    
    var statusColor: Color {
        let percent = recoveryPercentage
        if percent < 0.33 {
            return .red
        } else if percent < 0.66 {
            return .orange
        } else if percent < 1.0 {
            return .yellow
        } else {
            return .accentPositive
        }
    }
    
    var statusText: String {
        let percent = recoveryPercentage
        if percent < 0.33 {
            return "Fatigued"
        } else if percent < 0.66 {
            return "Recovering"
        } else if percent < 1.0 {
            return "Almost Ready"
        } else {
            return "Fully Recovered"
        }
    }
}

struct MuscleRecoveryMapView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @StateObject private var workoutService = WorkoutService()
    @State private var recoveries: [MuscleRecovery] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muscle Recovery Map")
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("Based on your last 72 hours of logged exercises.")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(recoveries) { recovery in
                    muscleCard(for: recovery)
                }
            }
            .padding(.top, 4)
        }
        .asCard()
        .onAppear(perform: calculateRecovery)
        .onChange(of: dailyLogService.currentDailyLog) { _, _ in
            calculateRecovery()
        }
    }
    
    @ViewBuilder
    private func muscleCard(for recovery: MuscleRecovery) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.backgroundSecondary, lineWidth: 4)
                
                Circle()
                    .trim(from: 0, to: recovery.recoveryPercentage)
                    .stroke(recovery.statusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: recovery.recoveryPercentage)
                
                Image(systemName: recovery.group.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(recovery.statusColor)
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recovery.group.rawValue)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)
                
                Text(recovery.statusText)
                    .appFont(size: 10, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func calculateRecovery() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -4, to: now)!

        Task {
            var lastTrainedTimes: [MuscleGroup: Date] = [:]

            func record(_ groups: [MuscleGroup], at date: Date) {
                for group in groups where date > (lastTrainedTimes[group] ?? .distantPast) {
                    lastTrainedTimes[group] = date
                }
            }

            // Primary source: completed routine sessions carry the real exercise names.
            // (The daily log only stores one summary entry named after the routine, so matching
            // muscle keywords against it misses almost everything — that was the stale-map bug.)
            let sessions = await workoutService.fetchRecentSessionLogs(sinceDays: 4)
            for session in sessions {
                let date = session.date.dateValue()
                for completed in session.completedExercises {
                    record(extractMuscleGroups(from: completed.exerciseName.lowercased()), at: date)
                }
            }

            // Secondary source: manually-logged exercises in the daily log.
            let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: now)
            if case .success(let logs) = result {
                for log in logs {
                    guard let exercises = log.exercises else { continue }
                    for exercise in exercises {
                        record(extractMuscleGroups(from: exercise.name.lowercased()), at: log.date)
                    }
                }
            }

            await MainActor.run {
                self.recoveries = MuscleGroup.allCases.map { group in
                    MuscleRecovery(group: group, lastTrained: lastTrainedTimes[group])
                }
            }
        }
    }
    
    private func extractMuscleGroups(from name: String) -> [MuscleGroup] {
        var groups = [MuscleGroup]()
        
        if name.contains("bench") || name.contains("chest") || name.contains("pushup") || name.contains("fly") {
            groups.append(.chest)
        }
        if name.contains("row") || name.contains("pullup") || name.contains("lat") || name.contains("back") || name.contains("deadlift") {
            groups.append(.back)
        }
        if name.contains("squat") || name.contains("leg") || name.contains("lunge") || name.contains("calf") || name.contains("glute") || name.contains("deadlift") {
            groups.append(.legs)
        }
        if name.contains("curl") || name.contains("tricep") || name.contains("arm") || name.contains("pushdown") || name.contains("extension") {
            groups.append(.arms)
        }
        if name.contains("crunch") || name.contains("plank") || name.contains("ab") || name.contains("situp") || name.contains("core") {
            groups.append(.core)
        }
        if name.contains("shoulder") || name.contains("lateral") || name.contains("overhead") || name.contains("raise") || name.contains("press") {
            // Wait, "bench press" could trigger shoulders too if "press" is in it, which is somewhat accurate.
            groups.append(.shoulders)
        }
        
        return groups
    }
}
