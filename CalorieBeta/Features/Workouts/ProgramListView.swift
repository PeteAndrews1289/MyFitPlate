import MyFitPlateCore

import SwiftUI

struct ProgramListView: View {
    @ObservedObject var workoutService: WorkoutService

    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService

    @State private var showingProgramCreator = false
    @State private var programToEdit: WorkoutProgram?
    @State private var programToDelete: WorkoutProgram?
    @State private var showingArchived = false
    @State private var isUpdatingArchive = false
    private var visiblePrograms: [WorkoutProgram] {
        workoutService.userPrograms.filter { showingArchived ? $0.archivedAt != nil : $0.archivedAt == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkoutSyncNotice(service: workoutService)
                SavedProgramsHeader(
                    programCount: visiblePrograms.count,
                    activeProgramName: workoutService.activeProgram?.name
                )

                Picker("Plan library", selection: $showingArchived) {
                    Text("Current").tag(false)
                    Text("Archived").tag(true)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("program_library_scope")
                if visiblePrograms.isEmpty && showingArchived {
                    Text("No archived plans. Archive an inactive plan to tidy your library while keeping its progress and logs.")
                        .appTextRole(.secondary).foregroundStyle(.secondary).appSurface(.quiet)
                } else if visiblePrograms.isEmpty {
                    SavedProgramsEmptyState {
                        programToEdit = nil
                        showingProgramCreator = true
                    }
                } else {
                    ForEach(visiblePrograms) { program in
                        savedProgramCard(program)
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("saved_programs")
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Training plans")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this program?", isPresented: Binding(
            get: { programToDelete != nil }, set: { if !$0 { programToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Program", role: .destructive) {
                guard let program = programToDelete else { return }
                programToDelete = nil
                Task {
                    let result = await workoutService.deleteProgram(program)
                    ToastManager.shared.showToast(message: result.userMessage)
                }
            }
        } message: { Text("Your completed workout history will be kept.") }
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
                programToDelete = program
            },
            onArchive: {
                guard !isUpdatingArchive else { return }
                isUpdatingArchive = true
                Task {
                    _ = await workoutService.setProgramArchived(program, archived: program.archivedAt == nil)
                    isUpdatingArchive = false
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
            title: "Your plans",
            subtitle: activeProgramName.map { "Active now: \($0)" }
                ?? "Your routines, organized into a plan."
        ) {
            VStack(spacing: 0) {
                Text("\(programCount)")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.brandText)

                Text(programCount == 1 ? "plan" : "plans")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 52, minHeight: 52)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
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
                .foregroundStyle(AppPalette.brandText)
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
    var onArchive: (() -> Void)?
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
        program.totalSlots
    }

    private var progressText: String {
        let completed = min(program.currentProgressIndex ?? 0, totalWorkouts)
        return "\(completed)/\(totalWorkouts)"
    }

    private var statusTitle: String {
        if isActive { return "Active" }
        if program.archivedAt != nil { return "Archived" }
        return program.startDate == nil ? "Needs Schedule" : "Saved"
    }

    private var statusColor: Color {
        if isActive { return .accentPositive }
        if program.archivedAt != nil { return .gray }
        return program.startDate == nil ? AppPalette.caution : AppPalette.brand
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
                Image(systemName: program.archivedAt != nil ? "archivebox" : isActive ? "checkmark.seal.fill" : "calendar.badge.clock")
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
                    Button("Edit") { onEdit() }.disabled(program.archivedAt != nil)
                    if let onArchive {
                        Button(program.archivedAt == nil ? "Archive plan" : "Restore plan", action: onArchive)
                            .disabled(isActive && program.archivedAt == nil)
                    }
                    Button("Delete permanently", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Options for \(program.name)")
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Progress", value: progressText, accent: AppPalette.brand),
                AppMetricItem(label: "Days / week", value: trainingDays == 0 ? "Unset" : "\(trainingDays)", accent: AppPalette.effort),
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

                if !isActive || program.archivedAt != nil {
                    Button(action: program.archivedAt == nil ? onSetActive : { onArchive?() }) {
                        Label(program.archivedAt != nil ? "Restore plan" : "Set active", systemImage: "target")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                }
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
