import MyFitPlateCore
import SwiftUI

/// A value-only editor. Dismissal never writes, and a failed save keeps every choice here.
struct SuggestionPreferencesView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: FoodPreferencesDraft
    @State private var revision: FoodPreferencesRevision
    @State private var exclusionsText: String
    @State private var ingredientPattern: PlanningDiet
    @State private var customChoices: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var restored = false
    @State private var didLoadCheckpoint = false
    @State private var finished = false
    @State private var conflictBaseline: FoodPreferencesDraft?
    @State private var reviewingConflict = false
    private let draftStore = EditorDraftStore()

    init(goalSettings: GoalSettings) {
        let initial = goalSettings.makeFoodPreferencesDraft()
        _exclusionsText = State(initialValue: initial.mealConstraintProfile?.hardExclusions.joined(separator: ", ") ?? "")
        _ingredientPattern = State(initialValue: initial.mealConstraintProfile?.diet ?? .unrestricted)
        _draft = State(initialValue: initial)
        _revision = State(initialValue: FoodPreferencesRevision(userID: DIContainer.shared.authService.currentUserID ?? "", baseline: initial))
    }

    var body: some View {
        AppEditorScaffold(
            title: "Food preferences",
            subtitle: "Make meal ideas feel more like you.",
            dismiss: { if !isSaving { dismiss() } }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if restored || checkpoint.requiresConflictReview(current: goalSettings.makeFoodPreferencesDraft()) {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(restored ? "Your unfinished choices are restored." : "Saved preferences changed.").appTextRole(.control)
                        if checkpoint.requiresConflictReview(current: goalSettings.makeFoodPreferencesDraft()) {
                            Text("Saved preferences changed since this draft began. Compare the two versions before keeping your draft choices.")
                                .appTextRole(.secondary)
                            Button("Review both versions") {
                                conflictBaseline = goalSettings.makeFoodPreferencesDraft(); reviewingConflict = true
                            }.accessibilityIdentifier("food_preferences_review_conflict")
                        }
                        Button("Use saved choices") { useSavedChoices() }.buttonStyle(.borderless)
                    }.appSurface(.quiet).accessibilityIdentifier("food_preferences_restored")
                }
                hardConstraintsSection
                AppSectionHeader(title: "Your favorites", subtitle: "Pick what you enjoy. Any keeps your options open.")
                if draft.selectionOrigin != "reviewed" {
                    Text(draft.selectionOrigin == "starter" ? "Starter choices · review before saving" : "Existing choices · review before saving")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                preferenceSection(title: "Proteins", options: ["Chicken", "Beef", "Fish", "Tofu", "Eggs", "Pork", "Lamb"], keyPath: \.proteins)
                preferenceSection(title: "Carbohydrates", options: ["Rice", "Quinoa", "Potatoes", "Pasta", "Bread", "Oats"], keyPath: \.carbs)
                preferenceSection(title: "Vegetables", options: ["Broccoli", "Spinach", "Bell Peppers", "Onions", "Carrots", "Zucchini", "Asparagus"], keyPath: \.vegetables)
                preferenceSection(title: "Cuisines", options: ["Italian", "Mexican", "Asian", "Mediterranean", "American"], keyPath: \.cuisines)
                DisclosureGroup("Preview a meal idea") {
                    Text("\(draft.proteins.first ?? "Any protein") with \(draft.carbs.first ?? "any base"), \(draft.vegetables.first ?? "any vegetable"). Your ingredient constraints take priority; this is an example, not a validated meal.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("food_preferences_brief_preview")
                        .padding(.top, AppSpacing.compact)
                }.appTextRole(.control).tint(AppPalette.text)
                Button("Use starter choices") {
                    let constraints = draft.mealConstraintProfile
                    draft = .defaults; draft.mealConstraintProfile = constraints; draft.selectionOrigin = "starter"; errorMessage = nil
                }
                    .buttonStyle(AppActionButtonStyle(.ghost))
                    .accessibilityIdentifier("food_preferences_defaults")
            }
            .disabled(isSaving)
        } actions: {
            VStack(spacing: AppSpacing.compact) {
                if let errorMessage {
                    Text(errorMessage)
                        .appTextRole(.caption).foregroundStyle(AppPalette.critical)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("food_preferences_error")
                }
                HStack(spacing: AppSpacing.row) {
                    Button("Cancel") { cancel() }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .disabled(isSaving)
                        .accessibilityIdentifier("food_preferences_cancel")
                    Button(action: save) {
                        if isSaving { ProgressView("Saving") } else { Text("Save") }
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isSaving)
                    .accessibilityIdentifier("food_preferences_save")
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { restoreCheckpoint() }
        .onChange(of: checkpoint) { _, _ in keepCheckpoint() }
        .onDisappear { if !finished { keepCheckpoint() } }
        .sheet(isPresented: $reviewingConflict) {
            if let conflictBaseline {
                FoodPreferenceConflictReview(saved: conflictBaseline, proposed: checkpoint) {
                    revision = .init(userID: revision.userID, baseline: conflictBaseline)
                    restored = false; errorMessage = nil; reviewingConflict = false; keepCheckpoint()
                }
            }
        }
    }

    private var checkpoint: FoodPreferencesEditorCheckpoint {
        .init(revision: revision, draft: draft, exclusionsText: exclusionsText,
              ingredientPattern: ingredientPattern, customChoices: customChoices)
    }
    private func restoreCheckpoint() {
        guard !didLoadCheckpoint, revision.userID == DIContainer.shared.authService.currentUserID else { return }
        defer { didLoadCheckpoint = true }
        do {
            guard let saved = try draftStore.load(FoodPreferencesEditorCheckpoint.self, userID: revision.userID,
                                                  scope: FoodPreferencesEditorCheckpoint.scope)?.value,
                  saved.canRestore(for: revision.userID) else { return }
            revision = saved.revision; draft = saved.draft; exclusionsText = saved.exclusionsText
            ingredientPattern = saved.ingredientPattern; customChoices = saved.customChoices; restored = true
        } catch { errorMessage = "Your unfinished choices could not be read. They have been kept. \(error.localizedDescription)" }
    }
    private func keepCheckpoint() {
        guard didLoadCheckpoint, !finished, revision.userID == DIContainer.shared.authService.currentUserID else { return }
        do { try draftStore.save(checkpoint, userID: revision.userID, scope: FoodPreferencesEditorCheckpoint.scope) } catch { errorMessage = "These choices are not yet protected if the app closes. \(error.localizedDescription)" }
    }
    private func useSavedChoices() {
        let initial = goalSettings.makeFoodPreferencesDraft()
        draft = initial; revision = .init(userID: revision.userID, baseline: initial)
        exclusionsText = initial.mealConstraintProfile?.hardExclusions.joined(separator: ", ") ?? ""
        ingredientPattern = initial.mealConstraintProfile?.diet ?? .unrestricted
        customChoices = [:]; restored = false; errorMessage = nil
        keepCheckpoint()
    }
    private func cancel() {
        guard revision.userID == DIContainer.shared.authService.currentUserID else { dismiss(); return }
        do {
            _ = try draftStore.removeIfUnchanged(FoodPreferencesEditorCheckpoint.self, userID: revision.userID,
                scope: FoodPreferencesEditorCheckpoint.scope, fingerprint: PlanFingerprint.make(checkpoint))
            finished = true; dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private var hardConstraintsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Diet & ingredients", subtitle: "Used across meal ideas and planning.")
            Picker("Ingredient pattern", selection: $ingredientPattern) {
                ForEach(PlanningDiet.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("meal_constraint_diet")
            TextField("Ingredients to avoid", text: $exclusionsText, axis: .vertical)
                .textInputAutocapitalization(.never).accessibilityIdentifier("meal_constraint_exclusions")
            Text("Separate names with commas. Review ingredients before logging; preferences do not verify allergen or cross-contact safety.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }.appSurface(.quiet)
    }

    private func preferenceSection(title: String, options: [String], keyPath: WritableKeyPath<FoodPreferencesDraft, [String]>) -> some View {
        let selected = draft[keyPath: keyPath]
        let savedExtras = selected.filter { $0 != "Any" && !options.contains($0) }
        let displayed = ["Any"] + options + Array(Set(savedExtras)).sorted()
        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 130), spacing: AppSpacing.compact)], spacing: AppSpacing.compact) {
                ForEach(displayed, id: \.self) { item in
                    let isSelected = item == "Any" ? selected.isEmpty || selected.contains("Any") : selected.contains(item)
                    Button { toggle(item, keyPath: keyPath) } label: {
                        HStack(spacing: AppSpacing.compact) {
                            Text(item).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").appFont(size: 20).accessibilityHidden(true)
                        }
                        .foregroundStyle(isSelected ? AppPalette.text : Color.secondary)
                        .padding(.horizontal, AppSpacing.row)
                        .padding(.vertical, AppSpacing.compact)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .overlay { RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppPalette.separator, lineWidth: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(item)")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("food_preference_\(title.lowercased())_\(item.lowercased().replacingOccurrences(of: " ", with: "_"))")
                }
            }
            HStack {
                TextField("Add a favorite", text: Binding(get: { customChoices[title] ?? "" }, set: { customChoices[title] = $0 }))
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("food_preference_custom_" + title.lowercased())
                Button("Add") {
                    let value = (customChoices[title] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.count <= 120 else { return }
                    var choices = draft[keyPath: keyPath].filter { $0 != "Any" }
                    if !choices.contains(value) { choices.append(value) }
                    draft[keyPath: keyPath] = choices; customChoices[title] = ""
                }.disabled((customChoices[title] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func toggle(_ item: String, keyPath: WritableKeyPath<FoodPreferencesDraft, [String]>) {
        errorMessage = nil
        if item == "Any" {
            draft[keyPath: keyPath] = keyPath == \.cuisines ? ["Any"] : []
        } else {
            var values = draft[keyPath: keyPath].filter { $0 != "Any" }
            if values.contains(item) { values.removeAll { $0 == item } } else { values.append(item) }
            draft[keyPath: keyPath] = values
        }
    }

    private func save() {
        guard !isSaving else { return }
        let exclusions = exclusionsText.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if ingredientPattern != (draft.mealConstraintProfile?.diet ?? .unrestricted) || exclusions != (draft.mealConstraintProfile?.hardExclusions ?? []) {
            draft.mealConstraintProfile = MealConstraintProfile(diet: ingredientPattern, hardExclusions: exclusions)
        }
        draft.selectionOrigin = "reviewed"
        isSaving = true; errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let submitted = checkpoint
                try draftStore.save(submitted, userID: revision.userID, scope: FoodPreferencesEditorCheckpoint.scope)
                try await goalSettings.saveFoodPreferencesDraft(draft, revision: revision)
                _ = try draftStore.removeIfUnchanged(FoodPreferencesEditorCheckpoint.self, userID: revision.userID,
                    scope: FoodPreferencesEditorCheckpoint.scope, fingerprint: PlanFingerprint.make(submitted))
                finished = true
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct FoodPreferenceConflictReview: View {
    let saved: FoodPreferencesDraft
    let proposed: FoodPreferencesEditorCheckpoint
    let onKeepDraft: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review the account's latest choices alongside this unfinished draft. Keeping the draft sets a new comparison baseline; nothing changes on your account until you tap Save preferences.")
                }
                compare("Proteins", saved.proteins, proposed.draft.proteins)
                compare("Carbohydrates", saved.carbs, proposed.draft.carbs)
                compare("Vegetables", saved.vegetables, proposed.draft.vegetables)
                compare("Cuisines", saved.cuisines, proposed.draft.cuisines)
                compare("Ingredient pattern", [(saved.mealConstraintProfile?.diet ?? .unrestricted).title], [proposed.ingredientPattern.title])
                compare("Ingredient exclusions", saved.mealConstraintProfile?.hardExclusions ?? [], [proposed.exclusionsText])
                Section { Button("Keep draft choices", action: onKeepDraft).accessibilityIdentifier("food_preferences_keep_reviewed_draft") }
            }.appFormStyle().navigationTitle("Compare preferences").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
        }
    }
    private func compare(_ title: String, _ saved: [String], _ proposed: [String]) -> some View {
        Section(title) {
            LabeledContent("Saved", value: saved.isEmpty ? "Any / none" : saved.joined(separator: ", "))
            LabeledContent("This draft", value: proposed.filter { !$0.isEmpty }.isEmpty ? "Any / none" : proposed.joined(separator: ", "))
        }
    }
}
