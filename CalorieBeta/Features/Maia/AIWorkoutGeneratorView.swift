import MyFitPlateCore

import SwiftUI
struct AIWorkoutGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject var goalSettings: GoalSettings // Access user's goal settings

    // State for the generator form
    @State private var goal: String = ""
    @State private var daysPerWeek: Int = 3
    @State private var fitnessLevel: FitnessLevel = .beginner
    @State private var equipment: Equipment = .fullGym
    @State private var details: String = "" // Optional notes
    
    // State for scheduling
    @State private var startDate: Date = Date()
    @State private var selectedDaysOfWeek: [Int] = []
    
    // View state
    @State private var isLoading = false
    @State private var generatedProgram: WorkoutProgram?
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?

    // Enums to provide structured options in the Pickers
    enum FitnessLevel: String, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        var id: Self { self }
    }

    enum Equipment: String, CaseIterable, Identifiable {
        case fullGym = "Full Gym"
        case dumbbellsOnly = "Dumbbells Only"
        case bodyweight = "Bodyweight Only"
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            if var program = generatedProgram {
                GeneratedProgramPreviewView(
                    program: program,
                    onBack: { generatedProgram = nil },
                    onSave: {
                        program.startDate = startDate
                        program.daysOfWeek = selectedDaysOfWeek
                        Task {
                            await workoutService.saveProgram(program)
                            dismiss()
                        }
                    }
                )
            } else {
                AppEditorScaffold(
                    title: "Build a Training Program",
                    subtitle: "Give Maia the goal, equipment, time, and constraints that matter.",
                    dismiss: { dismiss() }
                ) {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        goalSection
                        profileSection
                        scheduleSection
                        preferenceSection

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .appTextRole(.secondary)
                                .foregroundStyle(AppPalette.critical)
                                .fixedSize(horizontal: false, vertical: true)
                                .appSurface(.quiet)
                                .accessibilityIdentifier("ai_program_error")
                        }
                    }
                } actions: {
                    Button(action: generatePlan) {
                        Label("Generate Program", systemImage: "sparkles")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isLoading || goal.trimmed.isEmpty)
                    .accessibilityIdentifier("ai_program_generate")
                }
            }

            if isLoading {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    ProgressView()
                        .tint(AppPalette.brand)

                    AppSectionHeader(
                        title: "Building your program",
                        subtitle: "Balancing your goal, schedule, equipment, and recovery needs."
                    )

                    Button("Cancel Generation", action: cancelGeneration)
                        .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .appSurface(.emphasized)
                .padding(AppSpacing.screenHorizontal)
                .accessibilityIdentifier("ai_program_loading")
            }
        }
        .tint(AppPalette.brand)
        .onDisappear {
            generationTask?.cancel()
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Primary Goal",
                subtitle: "Use one clear outcome. You can refine the plan after generation."
            )

            TextField("Build muscle, improve endurance, return to training...", text: $goal)
                .textInputAutocapitalization(.sentences)
                .appTextRole(.control)
                .padding(AppSpacing.group)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityIdentifier("ai_program_goal")
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Training Profile",
                subtitle: "These choices determine exercise complexity and available movements."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Experience")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Experience", selection: $fitnessLevel) {
                        ForEach(FitnessLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Equipment")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .appTextRole(.control)
                }
            }
            .appSurface(.emphasized)
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Schedule",
                subtitle: "Choose the weekly frequency and days you can consistently protect."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Stepper(
                    "Training days: \(daysPerWeek)",
                    value: $daysPerWeek,
                    in: 2...6
                )
                .appTextRole(.control)

                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .appTextRole(.control)

                WeekDaySelector(selectedDays: $selectedDaysOfWeek)
            }
            .appSurface(.emphasized)
        }
    }

    private var preferenceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Constraints & Preferences",
                subtitle: "Optional details help Maia avoid exercises or schedules that do not fit."
            )

            TextEditor(text: $details)
                .appTextRole(.body)
                .frame(minHeight: 120)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Example: Keep sessions near 30 minutes and avoid high-impact knee work.")
                            .appTextRole(.secondary)
                            .foregroundStyle(.tertiary)
                            .padding(AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
    
    /// Calls the WorkoutService to generate a plan using the form data.
    private func generatePlan() {
        isLoading = true
        errorMessage = nil
        generationTask?.cancel()
        generationTask = Task {
            let result = await workoutService.generateAIWorkoutPlan(
                goal: goal,
                daysPerWeek: daysPerWeek,
                fitnessLevel: fitnessLevel.rawValue,
                equipment: equipment.rawValue,
                details: details,
                goalSettings: goalSettings
            )

            guard !Task.isCancelled else { return }
            isLoading = false
            switch result {
            case .success(let program):
                self.generatedProgram = program
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isLoading = false
    }
}

/// A view to show the AI-generated program before the user saves it.
struct GeneratedProgramPreviewView: View {
    let program: WorkoutProgram
    var onBack: () -> Void
    var onSave: () -> Void

    var body: some View {
        AppEditorScaffold(
            title: program.name,
            subtitle: "Review every session before adding this program to your training library.",
            dismiss: onBack
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Sessions",
                        value: program.routines.count.formatted(),
                        accent: AppPalette.effort
                    ),
                    AppMetricItem(
                        label: "Source",
                        value: "Maia",
                        accent: AppPalette.caution
                    )
                ])
                .appSurface(.interpreted)

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "Program Sessions",
                        subtitle: "Exercises and set counts remain editable after saving."
                    )

                    LazyVStack(spacing: AppSpacing.row) {
                        ForEach(program.routines) { routine in
                            VStack(alignment: .leading, spacing: AppSpacing.row) {
                                Text(routine.name)
                                    .appTextRole(.sectionTitle)
                                    .foregroundStyle(AppPalette.text)

                                ForEach(routine.exercises) { exercise in
                                    HStack(spacing: AppSpacing.compact) {
                                        Circle()
                                            .fill(exercise.type.color)
                                            .frame(width: 6, height: 6)
                                            .accessibilityHidden(true)
                                        Text(exercise.name)
                                            .appTextRole(.body)
                                        Spacer(minLength: AppSpacing.compact)
                                        Text("\(exercise.sets.count) sets")
                                            .appTextRole(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .appSurface(.emphasized)
                        }
                    }
                }
            }
        } actions: {
            Button("Save Program", action: onSave)
                .buttonStyle(AppActionButtonStyle(.primary))

            Button("Back to Details", action: onBack)
                .buttonStyle(AppActionButtonStyle(.ghost))
        }
    }
}

/// A reusable component for selecting days of the week.
struct WeekDaySelector: View {
    @Binding var selectedDays: [Int]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let days = [
        WeekDayChoice(day: 1, shortName: "S", fullName: "Sunday"),
        WeekDayChoice(day: 2, shortName: "M", fullName: "Monday"),
        WeekDayChoice(day: 3, shortName: "T", fullName: "Tuesday"),
        WeekDayChoice(day: 4, shortName: "W", fullName: "Wednesday"),
        WeekDayChoice(day: 5, shortName: "T", fullName: "Thursday"),
        WeekDayChoice(day: 6, shortName: "F", fullName: "Friday"),
        WeekDayChoice(day: 7, shortName: "S", fullName: "Saturday")
    ]

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.compact) {
                    ForEach(days) { day in
                        dayButton(day, usesFullName: true)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(days) { day in
                            dayButton(day, usesFullName: false)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: AppSpacing.compact) {
                        ForEach(days) { day in
                            dayButton(day, usesFullName: true)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("weekday_selector")
    }

    private func dayButton(_ day: WeekDayChoice, usesFullName: Bool) -> some View {
        let isSelected = selectedDays.contains(day.day)
        return Button {
            if let index = selectedDays.firstIndex(of: day.day) {
                selectedDays.remove(at: index)
            } else {
                selectedDays.append(day.day)
            }
        } label: {
            Text(usesFullName ? day.fullName : day.shortName)
                .appTextRole(usesFullName ? .secondary : .control)
                .frame(width: usesFullName ? nil : 42)
                .frame(maxWidth: usesFullName ? .infinity : nil, minHeight: 42)
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.text)
                .background(
                    isSelected ? AppPalette.brand : AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppPalette.separator, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.fullName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct WeekDayChoice: Identifiable {
    let day: Int
    let shortName: String
    let fullName: String

    var id: Int { day }
}
