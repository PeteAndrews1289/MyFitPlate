import SwiftUI
import ActivityKit
import MyFitPlateCore

// DESIGN.md rule 1: in the player, the hero is the set you're doing — header and control
// bar are chrome and stay compact. Progress is stated once (bar + one caption), not five
// ways; the rainbow metric tiles are gone. Finish becomes the primary action only once
// the planned sets are complete.
struct WorkoutSessionControlBar: View {
    let completedSets: Int
    let totalSets: Int
    let remainingSets: Int
    @Binding var isAutoRestEnabled: Bool
    let canReturnToSet: Bool
    let onCurrentSet: () -> Void
    let onPlateCalculator: () -> Void
    let onFinish: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    autoRestControls
                    HStack(spacing: AppSpacing.compact) {
                        currentSetButton
                        plateCalculatorButton
                        finishButton
                    }
                }
            } else {
                HStack(spacing: AppSpacing.compact) {
                    currentSetButton
                    autoRestControls
                    plateCalculatorButton
                    finishButton
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.canvas)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workout controls. \(completedSets) of \(totalSets) sets complete.")
    }

    private var currentSetButton: some View {
        Button(action: onCurrentSet) {
            Image(systemName: "scope")
        }
        .buttonStyle(AppIconButtonStyle(.plain))
        .disabled(!canReturnToSet)
        .accessibilityLabel("Current set")
        .accessibilityHint("Returns to your current set without logging or changing any work.")
        .accessibilityIdentifier("workout_current_set")
        .accessibilityShowsLargeContentViewer { Label("Current set", systemImage: "scope") }
    }

    private var autoRestControls: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(HStackLayout(spacing: AppSpacing.compact))
         : AnyLayout(VStackLayout(spacing: 0))) {
            Text("Auto rest")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Toggle("Auto rest timer", isOn: $isAutoRestEnabled)
                .labelsHidden()
                .tint(AppPalette.recovery)
                .frame(minHeight: 44)
                .accessibilityIdentifier("workout_auto_rest")
        }
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    private var plateCalculatorButton: some View {
        Button(action: onPlateCalculator) {
            Image(systemName: "square.stack.3d.up.fill")
        }
        .buttonStyle(AppIconButtonStyle(.plain))
        .accessibilityLabel("Plate calculator")
        .accessibilityIdentifier("workout_plate_calculator")
    }

    private var finishButton: some View {
        Button(action: {
            HapticManager.instance.feedback(.light)
            onFinish()
        }) {
            Text("Finish")
        }
        .buttonStyle(AppActionButtonStyle(totalSets > 0 && remainingSets == 0 ? .primary : .secondary))
        .accessibilityLabel("Finish Workout")
        .accessibilityIdentifier("workout_finish")
    }
}

struct WorkoutSessionHeaderCard: View {
    let routineName: String
    let elapsedTime: String
    let restTime: String?
    let completedSets: Int
    let totalSets: Int
    let completedExercises: Int
    let totalExercises: Int
    let progress: Double
    let currentExerciseName: String
    let onClose: () -> Void
    let onStopRest: () -> Void
    let onAdjustRest: (TimeInterval) -> Void
    var isCompact: Bool = false
    var showsClose = true
    var showsRestAdjustments = true
    var showsRestStatus = true
    let exercises: [RoutineExercise]
    var parkedExerciseIDs: [String] = []
    let onBrowseExercise: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? AppSpacing.compact : AppSpacing.row) {
            sessionIdentity

            AppProgressTrack(progress: progress, role: .effort, height: isCompact ? 4 : 7)
                .accessibilityElement()
                .accessibilityLabel("Workout progress")
                .accessibilityValue("\(completedSets) of \(totalSets) sets complete")

            if !isCompact || (restTime != nil && showsRestStatus) {
                currentSetContext
            }

            if restTime != nil && showsRestStatus && showsRestAdjustments { restControls }
        }
        .appSurface(.quiet, padding: isCompact ? AppSpacing.row : AppSpacing.group)
    }

    @ViewBuilder
    private var sessionIdentity: some View {
        if dynamicTypeSize.isAccessibilitySize && isCompact {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                Text(currentExerciseName)
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workout_current_exercise")
                    .accessibilityHint(routineName)
                Spacer(minLength: 0)
                exerciseMenu
                if showsClose { closeButton }
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(alignment: .center) {
                    Text("IN SESSION")
                        .appFont(size: 11, weight: .bold)
                        .foregroundStyle(AppPalette.effort)

                    Spacer(minLength: AppSpacing.compact)

                    if showsClose { closeButton }
                }

                Text(routineName)
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workout_routine_title")

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    Text(elapsedTime)
                        .appFont(size: 17, weight: .semibold)
                        .foregroundStyle(AppPalette.text)
                        .monospacedDigit()

                    Text("elapsed")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: AppSpacing.compact) {
                    Text(routineName)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("workout_routine_title")

                    exerciseMenu
                    if showsClose { closeButton }
                }

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    Text(isCompact ? currentExerciseName : "In session")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier(isCompact ? "workout_current_exercise" : "workout_session_status")

                    Spacer(minLength: AppSpacing.compact)

                    Text("\(elapsedTime) elapsed")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityIdentifier("workout_elapsed_time")
                }
            }
        }
    }

    @ViewBuilder private var exerciseMenu: some View {
        if exercises.count > 1 {
            Menu {
                Section("Jump to exercise") {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        let completed = exercise.sets.filter(\.isCompleted).count
                        Button {
                            onBrowseExercise(exercise.id)
                        } label: {
                            Text("\(index + 1). \(exercise.name)")
                            Text((parkedExerciseIDs.contains(exercise.id) && completed < exercise.sets.count ? "Parked · " : "") + "\(completed) of \(exercise.sets.count) sets complete")
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(AppPalette.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Jump to exercise")
            .accessibilityIdentifier("workout_exercise_menu")
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(AppIconButtonStyle(.plain))
        .accessibilityLabel("Close workout")
    }

    @ViewBuilder
    private var currentSetContext: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                HStack(spacing: AppSpacing.compact) {
                    setBadge
                    Spacer(minLength: 0)
                    restBadge
                }

                if !isCompact {
                    Text(currentExerciseName)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(spacing: 8) {
                setBadge

                if !isCompact {
                    Text(currentExerciseName)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 6)
                restBadge
            }
        }
    }

    private var setBadge: some View {
        AppStatusBadge(
            "Set \(min(completedSets + 1, max(totalSets, 1))) of \(max(totalSets, 1))",
            role: .effort
        )
    }

    @ViewBuilder
    private var restBadge: some View {
        if showsRestStatus, let restTime {
            if showsRestAdjustments {
                countdown(restTime)
            } else {
                Menu {
                    Button("Add 30 seconds") { onAdjustRest(30) }
                    Button("Subtract 15 seconds") { onAdjustRest(-15) }
                    Button("Skip rest", action: onStopRest)
                } label: {
                    AppStatusBadge("Rest \(restTime)", icon: "timer", role: .recovery)
                        .monospacedDigit().frame(minHeight: 44)
                }
                .accessibilityLabel("Rest timer \(restTime)")
                .accessibilityHint("Adjust or skip this rest.")
                .accessibilityIdentifier("workout_rest_inline_menu")
            }
        }
    }

    private func countdown(_ restTime: String) -> some View {
        AppStatusBadge("Rest \(restTime)", icon: "timer", role: .recovery)
            .monospacedDigit()
            .accessibilityLabel("Rest timer")
            .accessibilityValue(restTime)
            .accessibilityIdentifier("workout_rest_timer")
            .accessibilityAction(named: Text("Add 30 seconds")) { onAdjustRest(30) }
            .accessibilityAction(named: Text("Subtract 15 seconds")) { onAdjustRest(-15) }
            .accessibilityAction(named: Text("Skip rest"), onStopRest)
    }

    @ViewBuilder
    private var restControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.compact) { restAdjustmentButtons }
        } else {
            HStack(spacing: AppSpacing.compact) { restAdjustmentButtons }
        }
    }

    @ViewBuilder
    private var restAdjustmentButtons: some View {
        Button("−15s") { onAdjustRest(-15) }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Subtract 15 seconds from rest")
            .accessibilityIdentifier("workout_rest_subtract")
        Button("+30s") { onAdjustRest(30) }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Add 30 seconds to rest")
            .accessibilityIdentifier("workout_rest_add")
        Button("Skip", action: onStopRest)
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Skip rest")
            .accessibilityIdentifier("workout_rest_skip")
    }
}

/// Shared in-session controls remain visible beside set entry, including at large text
/// sizes. Every action targets the rest whose values the user actually reviewed.
struct WorkoutRestControlsView: View {
    @ObservedObject private var timer: RestTimer
    private let context: String?
    private let showsContextCaption: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(timer: RestTimer, context: String? = nil, showsContextCaption: Bool = true) {
        _timer = ObservedObject(wrappedValue: timer)
        self.context = context
        self.showsContextCaption = showsContextCaption
    }

    var body: some View {
        if let rest = timer.state {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .center, spacing: AppSpacing.compact) {
                        countdown
                        Spacer(minLength: AppSpacing.compact)
                        skipButton(for: rest)
                    }
                    HStack(spacing: AppSpacing.compact) { adjustmentButtons(for: rest) }
                } else {
                    HStack(alignment: .center, spacing: AppSpacing.compact) {
                        countdown
                        adjustmentButtons(for: rest)
                        skipButton(for: rest)
                    }
                }
                if showsContextCaption, let context, !context.isEmpty {
                    Text(context).appFont(size: 11, weight: .semibold).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(context)
                }
                if let error = timer.errorMessage {
                    Text(error).appFont(size: 13).foregroundStyle(AppPalette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workout_rest_error")
                }
            }
            .appSurface(.quiet, padding: AppSpacing.compact, radius: AppRadius.control)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout_rest_controls")
        } else if let completion = timer.completion {
            completionStatus(completion)
        }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timer.isRecovered ? "Rest restored" : "Rest")
                .appFont(size: 11, weight: .semibold).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("workout_rest_status")
            Text(timer.formattedTime()).appFont(size: 17, weight: .semibold)
                .foregroundStyle(AppPalette.recovery).monospacedDigit()
                .accessibilityLabel("Rest timer")
                .accessibilityValue(timer.formattedTime())
                .accessibilityHint(context.map { "Minutes and seconds remaining. Rest for \($0)." } ?? "Minutes and seconds remaining.")
                .accessibilityIdentifier("workout_rest_timer")
        }
        .frame(minWidth: 56, alignment: .leading)
    }

    @ViewBuilder
    private func adjustmentButtons(for rest: WorkoutRestState) -> some View {
        Button("−15s") { timer.adjust(by: -15, for: rest.id) }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Subtract 15 seconds from rest")
            .accessibilityIdentifier("workout_rest_subtract")
        Button("+30s") { timer.adjust(by: 30, for: rest.id) }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Add 30 seconds to rest")
            .accessibilityIdentifier("workout_rest_add")
    }

    private func skipButton(for rest: WorkoutRestState) -> some View {
        Button("Skip") { timer.skip(restID: rest.id) }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .accessibilityLabel("Skip rest")
            .accessibilityIdentifier("workout_rest_skip")
    }

    private func completionStatus(_ completion: WorkoutRestCompletion) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Label(completionTitle(completion), systemImage: completion.outcome == .unavailable ? "exclamationmark.triangle" : "timer")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundStyle(completion.outcome == .unavailable ? AppPalette.caution : AppPalette.recovery)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(completionTitle(completion))
                if showsContextCaption || completion.outcome == .unavailable {
                    Text(completionDetail(completion)).appFont(size: 11).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Button(action: timer.dismissCompletion) { Image(systemName: "xmark") }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Dismiss rest status")
                .accessibilityIdentifier("workout_rest_dismiss")
        }
        .appSurface(.quiet, padding: AppSpacing.compact, radius: AppRadius.control)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout_rest_completion")
    }

    private func completionTitle(_ completion: WorkoutRestCompletion) -> String {
        switch completion.outcome {
        case .elapsed: "Rest complete"
        case .skipped: "Rest skipped"
        case .shortened: "Rest ended"
        case .unavailable: "Rest needs review"
        }
    }

    private func completionDetail(_ completion: WorkoutRestCompletion) -> String {
        switch completion.outcome {
        case .elapsed: completion.wasRecovered ? "Saved rest deadline passed." : "Continue when you're ready."
        case .skipped: "Ready for your next set."
        case .shortened: "The remaining rest was shortened to zero."
        case .unavailable: "Saved timing couldn't be resumed. Your sets are unchanged."
        }
    }
}
