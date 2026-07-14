import MyFitPlateCore

import SwiftUI

struct ProgramListView: View {
    @ObservedObject var workoutService: WorkoutService
    
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    
    @State private var showingProgramCreator = false
    @State private var programToEdit: WorkoutProgram?

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
        .accessibilityIdentifier("saved_programs")
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
            NavigationStack {
                ProgramCreatorView(
                    workoutService: workoutService,
                    programToEdit: programToEdit,
                    isPresentedModally: true
                )
            }
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
                Task {
                    let result = await workoutService.deleteProgram(program)
                    ToastManager.shared.showToast(message: result.userMessage)
                }
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

struct SavedProgramsHeader: View {
    let programCount: Int
    let activeProgramName: String?

    var body: some View {
        AppScreenHeader(
            eyebrow: "Training Library",
            title: "Your Training Plans",
            subtitle: activeProgramName.map { "Active now: \($0)" }
                ?? "Choose a plan, review its rotation, or adjust its schedule."
        ) {
            VStack(spacing: 0) {
                Text("\(programCount)")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.brand)

                Text(programCount == 1 ? "plan" : "plans")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 52, minHeight: 52)
            .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(programCount) saved \(programCount == 1 ? "plan" : "plans")")
        }
    }
}

struct SavedProgramsEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Image(systemName: "folder.badge.plus")
                .appFont(size: 26, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .accessibilityHidden(true)

            Text("No saved plans yet")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text("Choose a pre-built program, generate one with AI, or build a plan manually.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onCreate) {
                Label("Build a Plan", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }
}

struct SavedProgramCard<Destination: View>: View {
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
        guard let startDate = program.startDate else {
            return "No start date"
        }
        return "Starts \(startDate.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActive ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(statusColor)
                    .frame(width: 40, height: 40)
                    .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SavedProgramStatusPill(title: statusTitle, color: statusColor)

                        Text(scheduleText)
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(program.name)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(program.routines.count) routine rotation")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Edit") { onEdit() }
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Options for \(program.name)")
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Progress", value: progressText, accent: AppPalette.brand),
                AppMetricItem(label: "Days / week", value: trainingDays == 0 ? "Unset" : "\(trainingDays)", accent: .blue),
                AppMetricItem(label: "Sets", value: "\(totalSetCount)", accent: .accentPositive)
            ])

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.compact) {
                    actionLinks
                }

                VStack(spacing: AppSpacing.compact) {
                    actionLinks
                }
            }
        }
        .appSurface(.emphasized)
    }

    @ViewBuilder
    private var actionLinks: some View {
                NavigationLink(destination: destination()) {
                    Label("Details", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))

                Button(action: onSetActive) {
                    Label(isActive ? "Active" : "Set Active", systemImage: isActive ? "checkmark.circle.fill" : "target")
                }
                .buttonStyle(AppActionButtonStyle(isActive ? .secondary : .primary))
                .disabled(isActive)
    }
}

struct SavedProgramStatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .appTextRole(.caption)
            .foregroundStyle(color)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}
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
