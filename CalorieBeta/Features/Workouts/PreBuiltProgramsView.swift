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
                    .asCard()
                } else {
                    if let selectionError {
                        ProgramSelectionErrorCard(message: selectionError)
                    }

                    ProgramCatalogSearchCard(searchText: $searchText)
                    ProgramCatalogFilterBar(selectedFilter: $selectedFilter)

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
        .sheet(item: $showingPreBuiltDetail) { program in
            NavigationStack {
                ProgramDetailView(
                    program: program,
                    isPreview: true,
                    isSelectingProgram: selectingProgramID == program.catalogID,
                    onSelectProgram: {
                        selectPreBuiltProgram(program)
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
                PreBuiltMetric(title: "Days/wk", value: "\(program.daysOfWeek?.count ?? 0)", color: .blue)
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
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSelecting)
        }
        .asCard()
    }

    private func selectPreBuiltProgram(_ program: WorkoutProgram) {
        guard selectingProgramID == nil else { return }
        selectingProgramID = program.catalogID
        selectionError = nil

        Task {
            let savedProgram = await workoutService.selectPreBuiltProgram(program)
            await MainActor.run {
                selectingProgramID = nil
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
        let name = program.name.lowercased()
        let exercises = program.routines.flatMap(\.exercises)
        let exerciseNames = exercises.map { $0.name.lowercased() }.joined(separator: " ")
        let usesBodyweight = name.contains("bodyweight") || exerciseNames.contains("push-up") || exerciseNames.contains("burpees")
        let usesBarbell = exerciseNames.contains("barbell") || exerciseNames.contains("deadlift") || exerciseNames.contains("bench press")
        let usesDumbbell = name.contains("dumbbell") || exerciseNames.contains("dumbbell")
        let mobilityExerciseCount = exercises.filter { $0.type == .flexibility }.count
        let isRecoveryFocused = name.contains("mobility") || name.contains("reset") || mobilityExerciseCount >= max(1, exercises.count / 2)
        let setCount = exercises.reduce(0) { $0 + max($1.sets.count, $1.targetSets) }

        if isRecoveryFocused {
            return ProgramCatalogProfile(
                goal: "Recovery",
                level: "All Levels",
                equipment: "Minimal Equipment",
                summary: "A low-impact reset for mobility, core control, easy conditioning, and better recovery between harder sessions.",
                icon: "heart.fill",
                color: .blue,
                tags: ["Mobility", "Core", "Recovery", "Low Impact"],
                setCount: setCount
            )
        }

        if usesDumbbell {
            return ProgramCatalogProfile(
                goal: "Muscle Growth",
                level: "Intermediate",
                equipment: "Dumbbells",
                summary: "An upper/lower hypertrophy block for building muscle with clear volume, repeatable sessions, and flexible equipment.",
                icon: "dumbbell.fill",
                color: .orange,
                tags: ["Hypertrophy", "Dumbbell", "Upper/Lower", "4 Days"],
                setCount: setCount
            )
        }

        if usesBodyweight {
            return ProgramCatalogProfile(
                goal: "General Fitness",
                level: "Beginner",
                equipment: "Minimal Equipment",
                summary: "A forgiving full-body path for building consistency, movement quality, and conditioning.",
                icon: "figure.run",
                color: .accentPositive,
                tags: ["Beginner", "Full Body", "Conditioning", "Low Barrier"],
                setCount: setCount
            )
        }

        if usesBarbell {
            return ProgramCatalogProfile(
                goal: "Strength",
                level: "Beginner",
                equipment: "Barbell",
                summary: "A simple progressive strength block built around heavy compound lifts and repeatable practice.",
                icon: "scalemass.fill",
                color: .brandPrimary,
                tags: ["Strength", "Barbell", "Progressive", "Compound Lifts"],
                setCount: setCount
            )
        }

        return ProgramCatalogProfile(
            goal: "Balanced",
            level: "All Levels",
            equipment: "Flexible",
            summary: "A structured plan with enough variety to support steady weekly training.",
            icon: "figure.strengthtraining.traditional",
            color: .blue,
            tags: ["Balanced", "Flexible", "12 Weeks"],
            setCount: setCount
        )
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
    case dumbbell = "Dumbbell"
    case bodyweight = "Bodyweight"
    case recovery = "Recovery"
    case minimal = "Minimal Gear"
    case barbell = "Barbell"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .strength: return "bolt.fill"
        case .dumbbell: return "dumbbell.fill"
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
        case .dumbbell:
            return profile.equipment.localizedCaseInsensitiveContains("Dumbbell") || profile.tags.contains("Dumbbell")
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgramCatalogFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .appFont(size: 11, weight: .bold)
                            Text(filter.rawValue)
                                .appFont(size: 12, weight: .bold)
                        }
                        .foregroundColor(selectedFilter == filter ? .white : .brandPrimary)
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
                .foregroundColor(.brandPrimary)
                .frame(width: 58, height: 58)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

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
        .asCard()
    }
}

private struct ProgramSelectionErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.12), in: Circle())

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
                    Text("Ready-Made Training")
                        .appFont(size: 25, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Choose a complete plan, inspect the routine structure, then make it your active program.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text("\(filteredCount)")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.brandPrimary)

                    Text("of \(programCount)")
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
