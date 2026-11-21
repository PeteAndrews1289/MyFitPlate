import MyFitPlateCore

import SwiftUI

struct WorkoutSyncNotice: View {
    @ObservedObject var service: WorkoutService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if service.syncState != .synced || service.loadErrorMessage != nil {
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
             : AnyLayout(HStackLayout(spacing: AppSpacing.row))) {
                Label(service.loadErrorMessage ?? (service.syncState == .failed
                      ? "Saved on this device. Sync needs a retry." : "Saved on this device. Waiting to sync…"),
                      systemImage: "icloud.and.arrow.up")
                    .appTextRole(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry", action: service.retryPendingSaves).frame(minWidth: 44, minHeight: 44)
            }
            .appSurface(.quiet)
            .accessibilityIdentifier("workout_sync_notice")
        }
    }
}

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
            AppSectionHeader(
                title: "Fuel & activity",
                subtitle: brief.message
            )

            AppStatusBadge(brief.status, icon: brief.icon, role: brief.role)

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
        .accessibilityHint(brief.message)
    }
}

struct TrainingSignalPill: View {
    let signal: TrainingSignal
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: AppSpacing.row) {
            Image(systemName: signal.icon)
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(signal.role.color)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
             : AnyLayout(HStackLayout(spacing: AppSpacing.row))) {
                Text(signal.title)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(signal.value)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.title): \(signal.value)")
    }
}

struct TrainingWeekPreviewCard: View {
    let program: WorkoutProgram
    var history: [WorkoutSessionLog] = []
    @State private var selectedSession: UpcomingTrainingSession?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sessions: [UpcomingTrainingSession] { TrainingScheduleOverview.upcoming(program) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Coming up", subtitle: "Tap a session to see the exercises and equipment.")
                .accessibilityIdentifier("train_program_week")
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(spacing: AppSpacing.row))
             : AnyLayout(HStackLayout(spacing: AppSpacing.row))) {
                NavigationLink(destination: ProgramDetailView(program: program)) {
                    Label("Full program", systemImage: "calendar")
                }.buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("training_full_program")
                NavigationLink(destination: WeekRescueView()) {
                    Label("Adjust week", systemImage: "calendar.badge.clock")
                }.buttonStyle(AppActionButtonStyle(.secondary)).accessibilityIdentifier("training_adjust_week")
            }
            if sessions.isEmpty {
                Text("No sessions left in this block. Review your program to plan what comes next.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                Button { selectedSession = session } label: {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "Not scheduled")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            Text(session.routine.name).appTextRole(.control).foregroundStyle(AppPalette.text)
                            Text("Week \(session.week) · Day \(session.day) · \(session.routine.exercises.count) exercises · \(session.workingSets) working sets")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            if session.isOverdue {
                                Text("Still in your plan — adjust the date when you need to.")
                                    .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).appSurface(.quiet)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("training_preview_\(session.slot)")
            }

        }
        .sheet(item: $selectedSession) { session in
            TrainingSessionPreview(session: session, history: history, program: program)
        }
    }
}

private struct TrainingSessionPreview: View {
    let session: UpcomingTrainingSession
    let history: [WorkoutSessionLog]
    let program: WorkoutProgram
    @Environment(\.dismiss) private var dismiss
    private var hasActiveDraft: Bool {
        guard let owner = DIContainer.shared.authService.currentUserID else { return true }
        do { return try WorkoutDraftStore().load(userID: owner) != nil } catch { return true }
    }
    @State private var showingAdaptation = false
    @State private var reviewedWorkout: WorkoutPlayerLaunch?
    @State private var adaptation: WorkoutSessionEditReceipt?
    @State private var preparedRoutine: WorkoutRoutine?
    private var previewExercises: [RoutineExercise] { preparedRoutine?.exercises ?? session.routine.exercises.map(configuredExercise) }
    private var previewRoutine: WorkoutRoutine { preparedRoutine ?? session.routine }

    private var equipment: [String] {
        Array(Set(previewExercises.map { exercise in
            if let setup = exercise.loadEquipment {
                guard setup.isValid else { return "Review equipment setup" }
                return "\(setup.name ?? setup.kind.title) (\(setup.unit.rawValue))"
            }
            let named = ["Dumbbell", "Kettlebell", "Barbell", "Cable"].filter {
                exercise.name.localizedCaseInsensitiveContains($0)
            }
            if !named.isEmpty { return named.joined(separator: exercise.name.contains("/") ? " or " : ", ") }
            let family = ExerciseList.equipment(for: exercise.name)
            return family == .flexible ? "Other equipment choices: see exercises" : family.rawValue
        })).sorted()
    }

    /// Preview the same remembered setup used by a fresh session without editing
    /// the saved program's shared WorkoutRoutine reference.
    @MainActor
    private func configuredExercise(_ exercise: RoutineExercise) -> RoutineExercise {
        guard let owner = DIContainer.shared.authService.currentUserID else { return exercise }
        var copy = exercise
        if let remembered = StrengthEquipmentPreferenceStore().load(userID: owner, routineID: session.routine.id,
            exerciseID: exercise.id, exerciseName: exercise.name) {
            copy.loadEquipment = remembered
        }
        return copy
    }

    @ViewBuilder private func previousPerformance(_ exercise: RoutineExercise) -> some View {
        if let log = ProgressionRules.history(for: exercise, in: history, routineID: session.routine.id).first,
           let result = ProgressionRules.performance(for: exercise, in: log), !WorkoutSetMath.workingSets(in: result).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last comparable result · \(log.date.formatted(date: .abbreviated, time: .omitted))").appTextRole(.control)
                Text(WorkoutSetMath.contextLabel(result.exercise)).appTextRole(.caption).foregroundStyle(.secondary)
                ForEach(Array(WorkoutSetMath.workingSets(in: result).enumerated()), id: \.offset) { index, set in
                    Text("Set \(index + 1) · " + previousSetText(set, exercise: result.exercise)).appTextRole(.secondary)
                }
                Text("Recorded results from this plan day and a compatible movement/setup. Today's targets and proposed changes are shown separately.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("training_preview_previous_\(exercise.id)")
        } else {
            Text("No recorded comparable working sets for this plan day and setup yet.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
    }

    private func previousSetText(_ set: CompletedSet, exercise: RoutineExercise) -> String {
        var pieces: [String] = []
        if exercise.type == .strength {
            let unit = exercise.loadEquipment?.unit ?? .lb
            if exercise.loadEquipment?.loadingMeaning == .bodyweightOnly { pieces.append("Bodyweight") } else {
                pieces.append("\(unit.displayWeight(set.weight).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue)")
            }
            pieces.append("\(set.reps) reps")
        }
        if let seconds = set.durationInSeconds, seconds > 0 { pieces.append("\(seconds) sec") }
        if let miles = set.distance, miles > 0 { pieces.append("\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi") }
        if let effort = set.effort { pieces.append("\(effort.scale.rawValue.uppercased()) \(effort.value.formatted())") } else { pieces.append("Effort not recorded") }
        return pieces.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(session.routine.name).appTextRole(.sectionTitle).accessibilityIdentifier("training_session_preview")
                    Text(session.date?.formatted(date: .complete, time: .omitted) ?? "Choose dates in Full program")
                        .foregroundStyle(.secondary)
                    Text("Week \(session.week) · Day \(session.day) · \(session.workingSets) working sets")
                        .appTextRole(.secondary)
                    if let minutes = WorkoutPlanningEligibility.estimatedMinutes(previewRoutine) {
                        Text("About \(max(5, minutes - 5))–\(minutes + 5) min · prescription and rest estimate").appTextRole(.secondary)
                    }
                    if let first = previewExercises.first { Text("First: " + first.name).appTextRole(.control) }
                    if let notes = session.routine.notes, !notes.isEmpty { Text(notes).appTextRole(.secondary) }
                }
                Section("Equipment to have ready") {
                    Text(equipment.isEmpty ? "No equipment listed" : equipment.joined(separator: " · "))
                        .accessibilityIdentifier("training_preview_equipment")
                    Text("Uses your saved equipment setups when available. Check exercise notes for substitutions.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Fit today's time") {
                    Button("Review a shorter session or substitution") { showingAdaptation = true }
                        .frame(minHeight: 44).accessibilityIdentifier("training_preview_adapt")
                    Text("Preview remaining work without changing your saved program. An accepted adaptation starts as a separate recoverable session draft.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    if let adaptation {
                        Text(adaptation.explanation).appTextRole(.secondary)
                        Text("Estimated remaining work: \(adaptation.beforeMinutes) → \(adaptation.afterMinutes) min").appTextRole(.control)
                    }
                }
                Section {
                    Button(adaptation == nil ? "Start this session" : "Start reviewed session") {
                        guard let launch = WorkoutPlayerLaunch(routine: previewRoutine, program: program, slot: session.slot) else {
                            ToastManager.shared.showToast(message: "Reopen your program to choose its current session.")
                            return
                        }
                        reviewedWorkout = launch
                    }
                        .buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("training_preview_start")
                        .disabled(hasActiveDraft || program.id == nil || preparedRoutine == nil || session.slot < (program.currentProgressIndex ?? 0))
                    if hasActiveDraft { Text("Finish or discard the active session before starting another.").appTextRole(.caption).foregroundStyle(.secondary) }
                }
                Section("Session plan") {
                    ForEach(Array(previewExercises.enumerated()), id: \.element.id) { index, exercise in
                        DisclosureGroup {
                            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { setIndex, set in
                                Text("\(set.resolvedSetType == .warmup ? "Warm-up" : "Set \(setIndex + 1)") · \(set.target ?? exercise.targetReps)")
                                    .appTextRole(.secondary)
                            }
                            if exercise.restTimeInSeconds > 0 {
                                Text("Rest: \(exercise.restTimeInSeconds) sec").appTextRole(.secondary)
                            }
                            if let notes = exercise.notes, !notes.isEmpty { Text(notes).appTextRole(.secondary) }
                            if let alternatives = exercise.alternatives, !alternatives.isEmpty {
                                Text("Alternatives: " + alternatives.joined(separator: ", ")).appTextRole(.secondary)
                            }
                            previousPerformance(exercise)
                            if let plan = ProgressionRules.plan(for: exercise, history: history, routineID: session.routine.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.headline).appTextRole(.control)
                                    Text(plan.rationale).appTextRole(.secondary)
                                    Text("Based on your current history. Review and apply targets when you start the workout.")
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, AppSpacing.compact)
                            } else {
                                Text("Progression guidance appears when your history and this exercise's targets support a comparison.")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(index + 1). \(exercise.name)").appTextRole(.control)
                                Text(exercise.type == .strength
                                     ? "\(exercise.sets.isEmpty ? max(0, exercise.targetSets) : exercise.sets.filter { $0.resolvedSetType != .warmup }.count) working sets · Tap for targets"
                                     : exercise.type.rawValue.capitalized)
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .buttonStyle(AppListButtonStyle())
            .onAppear {
                if preparedRoutine == nil, let copy = session.routine.deepCopy() {
                    copy.exercises = copy.exercises.map(configuredExercise); preparedRoutine = copy
                }
            }
            .sheet(isPresented: $showingAdaptation) {
                WorkoutSessionAdaptationView(exercises: previewExercises, history: history) { reviewed in
                    _ = try WorkoutSessionAdaptationRules.applying(reviewed, to: previewExercises)
                    adaptation = reviewed
                }
            }
            .fullScreenCover(item: $reviewedWorkout) { launch in
                WorkoutPlayerView(routine: launch.routine, programContext: launch.programContext,
                    initialSessionEdit: adaptation, freezesReviewedSetup: true) { reviewedWorkout = nil; dismiss() }
            }
            .navigationTitle("Session preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text(nextWorkout == nil ? "Choose your next workout" : "Ready for your next session")
                .appTextRole(.sectionTitle).foregroundStyle(AppPalette.text)
            Text("Follow a plan for guided progression, or start a saved routine.")
                .appTextRole(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let nextWorkout {
                Text(nextWorkout.routine.name).appTextRole(.control)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStartWorkout) { Label("Start workout", systemImage: "play.fill") }
                    .buttonStyle(AppActionButtonStyle(.primary))
            } else {
                Button(action: onChoosePlan) { Label("Choose a plan", systemImage: "rectangle.stack") }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .accessibilityIdentifier("start_plan_button")
                Button(action: onChooseOneOff) { Label("Saved routines", systemImage: "dumbbell") }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("one_off_workouts_button")
            }
        }
        .appSurface(.emphasized, radius: AppRadius.hero)
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

struct ActiveProgramManagementCard<Destination: View>: View {
    let program: WorkoutProgram
    let onDelete: () -> Void
    let destination: () -> Destination

    private var progressText: String {
        guard let currentIndex = program.currentProgressIndex, program.totalSlots > 0 else { return "Progress not set" }
        guard currentIndex < program.totalSlots else { return "Block complete" }
        return "Session \(max(currentIndex, 0) + 1) of \(program.totalSlots.formatted())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Program options", subtitle: progressText) {
                Menu {
                    Button("Delete program", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Program options")
                .accessibilityIdentifier("train_program_options")
            }
            Text(program.name).appTextRole(.control)
                .foregroundStyle(AppPalette.text).fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: destination()) {
                Label("Saved plans", systemImage: "folder")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .appSurface(.quiet)
    }
}

/// A quiet, full-width destination inside the Train navigation group.
/// Keep detailed reports and management controls on their own pages.
struct TrainingNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.control).foregroundStyle(.secondary)
                .frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).appTextRole(.control).foregroundStyle(AppPalette.text)
                Text(subtitle).appTextRole(.secondary).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppSpacing.compact)
            Image(systemName: "chevron.right")
                .appTextRole(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(AppSpacing.group)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TrainingSectionHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AppSectionHeader(
            title: title,
            subtitle: dynamicTypeSize.isAccessibilitySize ? nil : subtitle
        )
        .accessibilityHint(subtitle)
    }
}

struct TrainingActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityHint(subtitle)
    }
}
