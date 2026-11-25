import MyFitPlateCore

import SwiftUI

struct PreBuiltProgramsView: View {
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService

    @State private var showingPreBuiltDetail: WorkoutProgram?
    @State private var searchText = ""
    @State private var selectedFilter: ProgramCatalogFilter = .all
    @State private var selectingProgramID: String?
    @State private var selectionError: String?
    @State private var programPendingSchedule: WorkoutProgram?
    @State private var selectedStartDate = Date()
    @State private var comparisonPrograms: [WorkoutProgram] = []
    @State private var showingComparison = false

    private var filteredPrograms: [WorkoutProgram] {
        workoutService.preBuiltPrograms.filter { program in
            selectedFilter.matches(profile(for: program)) && matchesSearch(program)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PreBuiltProgramsHeader(
                    programCount: workoutService.preBuiltPrograms.count,
                    filteredCount: filteredPrograms.count
                )

                if workoutService.preBuiltPrograms.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.brandPrimary)
                        Text("Loading programs")
                            .appFont(size: 17, weight: .semibold)
                            .foregroundColor(.textPrimary)
                        Text("Getting the ready-made plans together.")
                            .appFont(size: 13)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                    .appSurface(.emphasized)
                } else {
                    if let selectionError {
                        ProgramSelectionErrorCard(message: selectionError)
                    }

                    ProgramCatalogSearchCard(searchText: $searchText)
                    ProgramCatalogFilterBar(selectedFilter: $selectedFilter)
                    if !comparisonPrograms.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text("Compare: " + comparisonPrograms.map(\.name).joined(separator: " + ")).appTextRole(.control)
                            Button("Compare these two plans") { showingComparison = true }
                                .buttonStyle(AppActionButtonStyle(.secondary)).disabled(comparisonPrograms.count != 2)
                                .accessibilityIdentifier("program_catalog_compare")
                            Button("Clear comparison") { comparisonPrograms = [] }.frame(minHeight: 44)
                        }.appSurface(.quiet)
                    }

                    if filteredPrograms.isEmpty {
                        ProgramCatalogEmptyState()
                    } else {
                        ForEach(filteredPrograms, id: \.name) { program in
                            preBuiltProgramRow(program)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Pre-built Programs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingComparison) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        Text("Choose the work that fits your week").appTextRole(.screenTitle)
                        Text("Estimates include prescribed work, between-set rest and setup. Review actual exercises and equipment before choosing. Comparing plans does not change your active program.").appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(comparisonPrograms, id: \.catalogID) { program in
                            comparisonCard(program)
                        }
                    }.padding(AppSpacing.screenHorizontal)
                }.background(AppPalette.canvas)
                    .navigationTitle("Compare plans").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingComparison = false } } }
            }.accessibilityIdentifier("program_catalog_comparison")
        }
        .sheet(item: $showingPreBuiltDetail) { program in
            NavigationStack {
                ProgramDetailView(
                    program: program,
                    isPreview: true,
                    isSelectingProgram: selectingProgramID == program.catalogID,
                    onSelectProgram: {
                        selectedStartDate = Calendar.current.startOfDay(for: Date())
                        programPendingSchedule = program
                    }
                )
                .environmentObject(workoutService)
                .environmentObject(goalSettings)
                .environmentObject(dailyLogService)
                .environmentObject(achievementService)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { showingPreBuiltDetail = nil }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Program Details")
                .sheet(item: $programPendingSchedule) { scheduledProgram in
                    PreBuiltProgramStartDateSheet(
                        program: scheduledProgram,
                        startDate: $selectedStartDate,
                        isSelecting: selectingProgramID == scheduledProgram.catalogID,
                        onCancel: {
                            programPendingSchedule = nil
                        },
                        onConfirm: {
                            selectPreBuiltProgram(
                                scheduledProgram,
                                startDate: selectedStartDate
                            )
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
        }
    }

    @ViewBuilder
    private func preBuiltProgramRow(_ program: WorkoutProgram) -> some View {
        let profile = profile(for: program)
        let isSelecting = selectingProgramID == program.catalogID

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: profile.icon)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(profile.color)
                    .frame(width: 42, height: 42)
                    .background(profile.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(profile.level) • \(profile.goal)")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(program.name)
                        .appFont(size: 19, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(profile.summary)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profile.tags, id: \.self) { tag in
                        ProgramTagPill(title: tag, color: profile.color)
                    }
                }
            }

            HStack(spacing: 10) {
                PreBuiltMetric(title: "Routines", value: "\(program.routines.count)", color: .brandPrimary)
                PreBuiltMetric(title: "Days/wk", value: "\(program.daysOfWeek?.count ?? 0)", color: AppPalette.effort)
                PreBuiltMetric(title: "Sets", value: "\(profile.setCount)", color: .accentPositive)
            }

            Button {
                showingPreBuiltDetail = program
            } label: {
                HStack {
                    if isSelecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    Text(isSelecting ? "Selecting..." : "Preview Plan")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .appFont(size: 12, weight: .bold)
                }
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(isSelecting)
            Button(comparisonPrograms.contains(where: { $0.catalogID == program.catalogID }) ? "Remove from comparison" : "Add to comparison") {
                if let index = comparisonPrograms.firstIndex(where: { $0.catalogID == program.catalogID }) { comparisonPrograms.remove(at: index) } else if comparisonPrograms.count < 2 { comparisonPrograms.append(program) }
            }.frame(minHeight: 44)
                .disabled(comparisonPrograms.count == 2 && !comparisonPrograms.contains(where: { $0.catalogID == program.catalogID }))
                .accessibilityIdentifier("program_compare_\(program.catalogID)")
        }
        .appSurface(.emphasized)
    }

    private func comparisonCard(_ program: WorkoutProgram) -> some View {
        let profile = profile(for: program)
        let estimates = program.routines.compactMap { WorkoutPlanningEligibility.estimatedMinutes($0) }
        let time = estimates.count == program.routines.count && !estimates.isEmpty
            ? "\(estimates.min() ?? 0)–\(estimates.max() ?? 0) min per session (estimate)" : "Session time needs manual target review"
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(program.name).appTextRole(.sectionTitle)
            LabeledContent("Goal", value: profile.goal)
            LabeledContent("Experience", value: profile.level)
            LabeledContent("Frequency", value: "\(program.daysOfWeek?.count ?? program.routines.count) days/week")
            LabeledContent("Block", value: "\(program.trainingBlock?.weeks.count ?? program.catalogRelease?.weekCount ?? 12) weeks")
            Text(time).appTextRole(.control)
            Text("Equipment: " + profile.equipment).appTextRole(.secondary)
            Text("\(profile.setCount) prescribed sets across \(program.routines.count) distinct days").appTextRole(.secondary)
            Text("Progression: " + (program.catalogRelease?.supportedPolicy.title ?? "Review authored targets")).appTextRole(.secondary)
            ForEach(program.routines, id: \.id) { routine in
                Text(routine.name + ": " + routine.exercises.map(\.name).joined(separator: ", ")).appTextRole(.caption)
            }
            Text(profile.summary).appTextRole(.caption).foregroundStyle(.secondary)
            Button("Preview \(program.name)") { showingComparison = false; showingPreBuiltDetail = program }
                .buttonStyle(AppActionButtonStyle(.secondary))
        }.appSurface(.quiet)
    }

    private func selectPreBuiltProgram(_ program: WorkoutProgram, startDate: Date) {
        guard selectingProgramID == nil else { return }
        selectingProgramID = program.catalogID
        selectionError = nil

        Task {
            let savedProgram = await workoutService.selectPreBuiltProgram(program, startDate: startDate)
            await MainActor.run {
                selectingProgramID = nil
                programPendingSchedule = nil
                if savedProgram != nil {
                    showingPreBuiltDetail = nil
                } else {
                    selectionError = "Could not select \(program.name). Check that you are signed in, then try again."
                }
            }
        }
    }

    private func matchesSearch(_ program: WorkoutProgram) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let profile = profile(for: program)
        let exercises = program.routines
            .flatMap(\.exercises)
            .map(\.name)
            .joined(separator: " ")

        let searchableText = ([program.name, profile.goal, profile.level, profile.equipment, profile.summary] + profile.tags + [exercises])
            .joined(separator: " ")
            .lowercased()

        return searchableText.contains(query)
    }

    private func profile(for program: WorkoutProgram) -> ProgramCatalogProfile {
        let release = program.catalogRelease ?? WorkoutCatalogRelease.profile(templateID: program.id ?? "")
        return ProgramCatalogProfile(goal: release?.goal ?? "Review plan", level: release?.experience ?? "Unspecified",
            equipment: release?.equipment ?? "Review requirements", summary: release?.fidelity ?? "Review this saved split before adopting it.",
            icon: "figure.strengthtraining.traditional", color: AppPalette.brand,
            tags: (release?.tags ?? []) + ["Catalog v\(release?.version ?? 1)"],
            setCount: program.routines.flatMap(\.exercises).reduce(0) { $0 + $1.sets.count })
    }
}

private struct ProgramCatalogProfile {
    let goal: String
    let level: String
    let equipment: String
    let summary: String
    let icon: String
    let color: Color
    let tags: [String]
    let setCount: Int
}

private enum ProgramCatalogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case strength = "Strength"
    case hypertrophy = "Muscle"
    case dumbbell = "Dumbbell"
    case machine = "Machines"
    case conditioning = "Conditioning"
    case bodyweight = "Bodyweight"
    case recovery = "Recovery"
    case minimal = "Minimal Gear"
    case barbell = "Barbell"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .strength: return "bolt.fill"
        case .hypertrophy: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "rectangle.grid.2x2.fill"
        case .conditioning: return "flame.fill"
        case .bodyweight: return "figure.run"
        case .recovery: return "heart.fill"
        case .minimal: return "house.fill"
        case .barbell: return "scalemass.fill"
        }
    }

    func matches(_ profile: ProgramCatalogProfile) -> Bool {
        switch self {
        case .all:
            return true
        case .strength:
            return profile.goal.localizedCaseInsensitiveContains("Strength") || profile.tags.contains("Strength")
        case .hypertrophy:
            return profile.goal.localizedCaseInsensitiveContains("Muscle") || profile.tags.contains("Hypertrophy")
        case .dumbbell:
            return profile.equipment.localizedCaseInsensitiveContains("Dumbbell") || profile.tags.contains("Dumbbell")
        case .machine:
            return profile.equipment.localizedCaseInsensitiveContains("Machine") || profile.tags.contains("Machines")
        case .conditioning:
            return profile.goal.localizedCaseInsensitiveContains("Conditioning") || profile.tags.contains("Conditioning")
        case .bodyweight:
            return profile.tags.contains("Full Body") || profile.equipment.localizedCaseInsensitiveContains("Minimal")
        case .recovery:
            return profile.goal.localizedCaseInsensitiveContains("Recovery") || profile.tags.contains("Mobility") || profile.tags.contains("Recovery")
        case .minimal:
            return profile.equipment.localizedCaseInsensitiveContains("Minimal") || profile.tags.contains("Low Barrier") || profile.tags.contains("Low Impact")
        case .barbell:
            return profile.equipment.localizedCaseInsensitiveContains("Barbell") || profile.tags.contains("Barbell")
        }
    }
}

private struct ProgramCatalogSearchCard: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            TextField("Search goal, equipment, or exercise", text: $searchText)
                .appFont(size: 15)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProgramCatalogFilterBar: View {
    @Binding var selectedFilter: ProgramCatalogFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgramCatalogFilter.allCases) { filter in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .appFont(size: 11, weight: .bold)
                            Text(filter.rawValue)
                                .appFont(size: 12, weight: .bold)
                        }
                        .foregroundColor(selectedFilter == filter ? AppPalette.onBrand : .brandForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selectedFilter == filter ? Color.brandPrimary : Color.brandPrimary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ProgramCatalogEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .appFont(size: 28, weight: .semibold)
                .foregroundColor(.brandForeground)
                .frame(width: 58, height: 58)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))

            Text("No matching programs")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Try a different search or filter. The catalog is built to grow as more training paths are added.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .appSurface(.emphasized)
    }
}

private struct ProgramSelectionErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(AppPalette.caution)
                .frame(width: 38, height: 38)
                .background(AppPalette.caution.opacity(0.12), in: Circle())

            Text(message)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PreBuiltProgramStartDateSheet: View {
    let program: WorkoutProgram
    @Binding var startDate: Date
    let isSelecting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var trainingDayCount: Int {
        program.daysOfWeek?.count ?? 0
    }

    private var startDateText: String {
        startDate.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.brandForeground)
                            .frame(width: 44, height: 44)
                            .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose Start Date")
                                .appFont(size: 22, weight: .bold)
                                .foregroundColor(.textPrimary)

                            Text("Your copied program will begin on \(startDateText).")
                                .appFont(size: 13)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    AppDateField("Start Date", selection: $startDate)
                        .appFont(size: 15, weight: .semibold)
                        .tint(.brandPrimary)
                        .padding(14)
                        .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .appSurface(.emphasized)

                VStack(alignment: .leading, spacing: 10) {
                    Text(program.name)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        PreBuiltMetric(title: "Routines", value: "\(program.routines.count)", color: .brandPrimary)
                        PreBuiltMetric(title: "Days/wk", value: "\(trainingDayCount)", color: AppPalette.effort)
                    }

                    Text("The weekly rhythm is preserved, and the first workout is aligned to your chosen start date.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appSurface(.emphasized)

                Spacer(minLength: 0)
            }
            .padding()
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Schedule Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSelecting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onConfirm()
                    } label: {
                        if isSelecting {
                            ProgressView()
                        } else {
                            Text("Start")
                        }
                    }
                    .disabled(isSelecting)
                }
            }
        }
    }
}

private struct ProgramTagPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .appFont(size: 11, weight: .bold)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private extension WorkoutProgram {
    var catalogID: String {
        id ?? name
    }
}

private struct PreBuiltProgramsHeader: View {
    let programCount: Int
    let filteredCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your next plan")
                        .appFont(size: 25, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Browse the sessions before you choose.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text("\(filteredCount)")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.brandForeground)

                    Text("of \(programCount)")
                        .appFont(size: 10, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(width: 52, height: 52)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
        }
        .appSurface(.emphasized)
    }
}

private struct PreBuiltMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(color)
            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
