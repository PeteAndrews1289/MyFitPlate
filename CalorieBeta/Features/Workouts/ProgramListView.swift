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

struct SavedProgramsHeader: View {
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

struct SavedProgramsEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .appFont(size: 30, weight: .semibold)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActive ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .appFont(size: 18, weight: .bold)
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
                        .appFont(size: 14, weight: .bold)
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

struct SavedProgramStatusPill: View {
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

struct SavedProgramMetric: View {
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
