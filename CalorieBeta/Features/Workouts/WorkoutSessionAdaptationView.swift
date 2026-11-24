import MyFitPlateCore
import SwiftUI

struct WorkoutSwapMenu: View {
    let source: RoutineExercise
    let title: String
    let suggestions: [WorkoutSubstitutionSuggestion]
    let onChoose: (ExercisePickerDraft) -> Void
    let onBrowse: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: AppSpacing.compact) {
                    Text(title).appTextRole(.sectionTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Swap \(source.name)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("exercise_swap_\(source.id)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Swap remaining sets").appTextRole(.caption)
                        .foregroundStyle(.secondary).padding(.top, AppSpacing.row)
                    ForEach(suggestions) { suggestion in
                        Button {
                            let category = ExerciseList.entries.first { $0.name == suggestion.name }?.category
                            isExpanded = false
                            onChoose(ExercisePickerDraft(name: suggestion.name, category: category,
                                type: RoutineEditorDefaults.inferredType(name: suggestion.name, category: category)))
                        } label: {
                            Text(suggestion.name).appTextRole(.body)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("workout_swap_choice_\(suggestion.name)")
                        Divider()
                    }
                    Button {
                        isExpanded = false
                        onBrowse()
                    } label: {
                        Label("Browse all exercises", systemImage: "magnifyingglass")
                            .appTextRole(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("workout_swap_browse")
                }
                .padding(.horizontal, AppSpacing.row)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppPalette.text)
        .onChange(of: source.id) { _, _ in isExpanded = false }
    }
}

struct WorkoutSessionAdaptationView: View {
    enum Mode: String, CaseIterable, Identifiable { case shorten = "Adjust time", remove = "Remove unfinished", substitute = "Substitute"; var id: String { rawValue } }
    let exercises: [RoutineExercise]
    let history: [WorkoutSessionLog]
    var initialExerciseID: String?
    var initialMode: Mode = .shorten
    let onApply: (WorkoutSessionEditReceipt) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.shorten
    @State private var minutes = 30
    @State private var priority = Set<String>()
    @State private var sourceID = ""
    @State private var reason = WorkoutSubstitutionProvenance.Reason.preference
    @State private var choosingMovement = false
    @State private var selectedFromLibrary: ExercisePickerDraft?
    @State private var review: WorkoutSessionEditReceipt?
    @State private var errorMessage: String?
    @State private var rankingGym: StrengthGymProfile?
    @State private var choosingRankingGym = false
    @State private var favoriteMovements = Set<String>()
    @State private var rankingError: String?
    @State private var substitutionIntent = WorkoutSubstitutionRanking.Intent.preserveRole
    private var source: RoutineExercise? { exercises.first { $0.id == sourceID } }
    private var confirmedMovements: [String: StrengthEquipment] {
        var result: [String: StrengthEquipment] = [:]
        for exercise in exercises {
            if let setup = exercise.loadEquipment, setup.isValid,
               let profile = setup.gymProfile, profile.profileID == rankingGym?.id, profile.revisionID == rankingGym?.revisionID {
                result[exercise.name] = setup
            }
        }
        return result
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Change today", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    Text("About \(WorkoutSessionAdaptationRules.remainingMinutes(exercises)) minutes of prescribed work and rest remain.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if mode == .shorten {
                    Section("Time & priority movements") {
                        Stepper("About \(minutes) minutes remaining", value: $minutes, in: 5...180, step: 5)
                        ForEach(exercises.filter { $0.sets.contains { !$0.isCompleted } }) { exercise in
                            Toggle(exercise.name, isOn: Binding(get: { priority.contains(exercise.id) }, set: {
                                if $0 { priority.insert(exercise.id) } else { priority.remove(exercise.id) }
                            }))
                        }
                        Text("At least one unfinished working set stays for each selected priority movement. All warm-ups and recorded sets stay. The preview removes later unfinished sets first.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Source movement") {
                        Picker("Movement", selection: $sourceID) {
                            ForEach(exercises.filter { $0.sets.contains { !$0.isCompleted } }) { Text($0.name).tag($0.id) }
                        }
                        if let source { Text("\(source.sets.filter(\.isCompleted).count) recorded sets stay; \(source.sets.filter { !$0.isCompleted }.count) unfinished sets are reviewed.").appTextRole(.secondary) }
                    }
                }
                if mode == .substitute, let source {
                    Section("Replacement") {
                        WorkoutSwapMenu(source: source, title: "Choose exercise",
                            suggestions: WorkoutSubstitutionRanking.suggestions(for: source, gym: rankingGym,
                            confirmedMovements: confirmedMovements, favorites: favoriteMovements, reason: reason,
                            intent: substitutionIntent, limit: 5), onChoose: applySwap, onBrowse: { choosingMovement = true })
                        DisclosureGroup("Swap preferences") {
                            Picker("Reason", selection: $reason) {
                                ForEach(WorkoutSubstitutionProvenance.Reason.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Training priority", selection: $substitutionIntent) {
                                ForEach(WorkoutSubstitutionRanking.Intent.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Button(rankingGym?.name ?? "Choose gym") { choosingRankingGym = true }
                            if let rankingError { Text(rankingError).appTextRole(.caption) }
                        }
                    }
                }
                if mode != .substitute {
                    previewSection
                }
                if let errorMessage { Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Adapt today's workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                mode = initialMode; sourceID = initialExerciseID ?? exercises.first(where: { $0.sets.contains { !$0.isCompleted } })?.id ?? ""
                priority = Set(exercises.prefix(2).map(\.id))
                loadRankingContext()
            }
            .onChange(of: mode) { _, _ in review = nil }
            .onChange(of: minutes) { _, _ in review = nil }
            .onChange(of: sourceID) { _, _ in review = nil; errorMessage = nil }
            .onChange(of: reason) { _, _ in review = nil }
            .onChange(of: priority) { _, _ in review = nil }
            .sheet(isPresented: $choosingMovement, onDismiss: {
                if let selectedFromLibrary {
                    self.selectedFromLibrary = nil
                    applySwap(selectedFromLibrary)
                }
            }) {
                ExercisePickerView(isReplacing: true) { selectedFromLibrary = $0 }
            }
            .sheet(isPresented: $choosingRankingGym) { StrengthGymLibraryView { rankingGym = $0 } }
        }
    }
    private func loadRankingContext() {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        do {
            favoriteMovements = Set(try WorkoutMovementSelectionStore().load(userID: owner).favorites)
            if let reference = source?.loadEquipment?.gymProfile {
                rankingGym = try StrengthGymProfileStore().profiles(userID: owner).first { $0.id == reference.profileID }
            }
        } catch { rankingError = "Saved ranking preferences could not load. Suggestions show their available evidence; confirm the setup manually." }
    }
    private func applySwap(_ selection: ExercisePickerDraft) {
        do {
            let edit = try WorkoutSessionAdaptationRules.swapping(exerciseID: sourceID, to: selection,
                in: exercises, history: history, reason: reason)
            try onApply(edit)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var previewSection: some View {
        Section {
            Button("Preview exact change", action: preview).frame(minHeight: 44).accessibilityIdentifier("session_adaptation_preview")
            if let review {
                Text(review.explanation).appTextRole(.secondary)
                Text("Estimated remaining time: \(review.beforeMinutes) → \(review.afterMinutes) min").appTextRole(.control)
                if let after = try? JSONDecoder().decode([RoutineExercise].self, from: review.after) {
                    ForEach(after) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).appTextRole(.control)
                            Text("\(exercise.sets.filter(\.isCompleted).count) recorded · \(exercise.sets.filter { !$0.isCompleted }.count) unfinished · \(WorkoutSetMath.contextLabel(exercise))").appTextRole(.caption).foregroundStyle(.secondary)
                            ForEach(exercise.sets.filter { !$0.isCompleted }) { set in
                                Text("\(set.prescription?.summary ?? set.target ?? "Manual") · \(set.weight > 0 ? set.weight.formatted() + " stored lb" : "manual/zero external load")")
                                    .appTextRole(.caption)
                            }
                        }
                    }
                }
                Button("Apply reviewed change") {
                    do { try onApply(review); dismiss() } catch { errorMessage = error.localizedDescription }
                }.frame(minHeight: 44).accessibilityIdentifier("session_adaptation_apply")
            }
        }
    }

    private func preview() {
        do {
            switch mode {
            case .shorten: review = try WorkoutSessionAdaptationRules.shortening(exercises, toMinutes: minutes, protectedMovementIDs: priority)
            case .remove: review = try WorkoutSessionAdaptationRules.removingUnfinished(exerciseID: sourceID, from: exercises)
            case .substitute: return
            }
            errorMessage = nil
        } catch { review = nil; errorMessage = "No safe change fits this request. Review the priorities, available equipment or time, then try again. \(error.localizedDescription)" }
    }
}
