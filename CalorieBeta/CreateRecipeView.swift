import SwiftUI
import MyFitPlateCore
import UIKit

struct CreateRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var bannerService: BannerService

    private let recipeToEdit: Recipe?
    private let onSaved: ((Recipe) -> Void)?
    @State private var expectedRecipe: Recipe?
    @State private var importedRecipe: Recipe?
    @State private var showingPhotoImport = false
    @State private var componentReview: RecipeComponentReviewRequest?
    @State private var importChoices: [Recipe] = []
    @State private var choosingImport = false
    @State private var duplicateDraft: Recipe?
    @State private var duplicateOriginal: Recipe?
    @State private var showingDuplicate = false
    @State private var reviewedDuplicateSource: String?
    @State private var prepMinutes = ""
    @State private var equipment = ""
    @State private var planningDiet: PlanningDiet = .unrestricted
    @State private var reviewedExclusions = ""
    @State private var estimatedCost = ""
    @State private var reviewedPlanning = false
    @State private var planningDetailsExpanded = false
    @State private var checkpointReady = false
    @State private var formFinished = false
    @State private var checkpointOwner: String?
    @State private var checkpointUnreadable = false
    @State private var formExpectedFingerprint: String?
    private var baseRecipe: Recipe? { importedRecipe ?? recipeToEdit }

    @State private var recipeName = ""
    @State private var newRecipeID = UUID().uuidString
    @State private var ingredientSnapshot = RecipeIngredientEditorSnapshot([])
    private var ingredients: [FoodItem] {
        get { ingredientSnapshot.ingredients }
        nonmutating set { ingredientSnapshot = RecipeIngredientEditorSnapshot(newValue) }
    }
    @State private var unresolvedIngredients: [String] = []
    @State private var nutritionChoice: RecipeEditingState.NutritionChoice = .recalculate
    @State private var servingsText = "1"
    @State private var yieldChoice: RecipeEditingState.YieldChoice = .keepSaved
    @State private var cookedWeightText = ""
    @State private var ingredientBasisSelection: RecipeNutritionBasis? = .wholeRecipe
    @State private var showingDiscardForm = false
    @State private var saveError: String?
    @State private var recipeSaveOperationID = UUID()
    @StateObject private var revisionSession: RecipeRevisionSaveSession
    @State private var replacingUnresolvedIndex: Int?
    @State private var pendingIngredientMatch: RecipeIngredientMatchRequest?
    @State private var ingredientMatch: RecipeIngredientMatchRequest?
    @State private var invalidIngredientIDs: Set<String> = []
    @State private var instructions = ""
    @State private var showingFoodSearch = false
    @State private var creationMode: CreationMode = .ai
    @State private var aiDescription = ""
    @State private var importText = ""
    @State private var importURL = ""
    @State private var isLoading = false

    init(recipeToEdit: Recipe? = nil, initialDraft: Recipe? = nil, planningDetailsInitiallyExpanded: Bool = false, onSaved: ((Recipe) -> Void)? = nil) {
        self.recipeToEdit = recipeToEdit
        self.onSaved = onSaved
        _planningDetailsExpanded = State(initialValue: planningDetailsInitiallyExpanded)
        _expectedRecipe = State(initialValue: recipeToEdit)
        _importedRecipe = State(initialValue: initialDraft)
        _revisionSession = StateObject(wrappedValue: RecipeRevisionSaveSession(userID: DIContainer.shared.authService.currentUserID))
        if let recipe = initialDraft ?? recipeToEdit {
            let profile = recipe.planningProfile
            _prepMinutes = State(initialValue: profile?.prepMinutes.map(String.init) ?? "")
            _equipment = State(initialValue: profile?.equipment.joined(separator: ", ") ?? "")
            _planningDiet = State(initialValue: profile?.diet ?? .unrestricted)
            _reviewedExclusions = State(initialValue: profile?.reviewedExclusions.joined(separator: ", ") ?? "")
            _estimatedCost = State(initialValue: profile?.costPerServing.map { String($0) } ?? "")
            _reviewedPlanning = State(initialValue: profile?.isCurrent(for: recipe) == true)
            _ingredientBasisSelection = State(initialValue: recipe.ingredientBasis)
            _recipeName = State(initialValue: recipe.name)
            let edit = RecipeEditingState(recipe: recipe)
            _ingredientSnapshot = State(initialValue: RecipeIngredientEditorSnapshot(edit.ingredients))
            _unresolvedIngredients = State(initialValue: edit.unresolvedIngredients)
            _nutritionChoice = State(initialValue: edit.nutritionChoice)
            _servingsText = State(initialValue: edit.servings.formatted(.number.precision(.fractionLength(0...2))))
            _cookedWeightText = State(initialValue: edit.cookedWeightGrams.map {
                $0.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3)))
            } ?? "")
            _instructions = State(initialValue: recipe.instructions.joined(separator: "\n"))
            _creationMode = State(initialValue: .manual)
        }
    }

    enum CreationMode: String, CaseIterable, Identifiable {
        case ai
        case text
        case url
        case manual

        var id: Self { self }

        var shortTitle: String {
            switch self {
            case .ai: "Maia"
            case .text: "Paste"
            case .url: "URL"
            case .manual: "Manual"
            }
        }

        var title: String {
            switch self {
            case .ai: "Generate with Maia"
            case .text: "Import Pasted Text"
            case .url: "Import from a URL"
            case .manual: "Build Manually"
            }
        }

        var subtitle: String {
            switch self {
            case .ai:
                "Describe the meal and let Maia draft its ingredients, steps, and nutrition."
            case .text:
                "Paste a recipe from any text source and let Maia structure it."
            case .url:
                "Use a public recipe page as the starting point."
            case .manual:
                "Add foods from search and write the preparation steps yourself."
            }
        }

        var systemImage: String {
            switch self {
            case .ai: "sparkles"
            case .text: "doc.on.clipboard"
            case .url: "link"
            case .manual: "hand.draw"
            }
        }
    }

    private var editingState: RecipeEditingState {
        var edit = RecipeEditingState(recipe: baseRecipe)
        edit.ingredientBasis = ingredientBasisSelection
        edit.ingredients = ingredients
        edit.unresolvedIngredients = unresolvedIngredients
        edit.nutritionChoice = nutritionChoice
        edit.servings = Double(servingsText.replacingOccurrences(of: ",", with: ".")) ?? .nan
        edit.yieldChoice = yieldChoice
        edit.cookedWeightGrams = cookedWeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : Double(cookedWeightText.replacingOccurrences(of: ",", with: ".")) ?? .nan
        return edit
    }

    private var totalNutrition: Nutrition { editingState.nutrition }
    private var pendingRecipeSave: RecipeRevisionSaveProposal? { revisionSession.proposal }

    private var nutritionPreviewSubtitle: String {
        guard nutritionChoice == .keepSaved, let recipeToEdit = baseRecipe else {
            return ingredientBasisSelection == .perServing ? "One-serving nutrition calculated from your ingredients" : "Whole-recipe total calculated from your ingredients"
        }
        switch recipeToEdit.nutritionBasis {
        case .wholeRecipe: return "Saved whole-recipe total; ingredient edits are excluded"
        case .perServing: return "Saved nutrition per serving; ingredient edits are excluded"
        case nil: return "Saved nutrition for the original amount; ingredient edits are excluded"
        }
    }

    private var savedNutritionBasisLabel: String {
        guard let recipeToEdit = baseRecipe else { return "Saved nutrition" }
        guard recipeToEdit.nutritionBasis == .wholeRecipe else { return recipeToEdit.nutritionBasisLabel }
        let yield = (recipeToEdit.servings ?? 1).formatted(.number.precision(.fractionLength(0...2)))
        return "Whole-recipe nutrition · \(yield) servings per recipe"
    }

    private var editorTitle: String {
        if pendingRecipeSave != nil { return "Finish recipe save" }
        if importedRecipe != nil { return "Review your recipe" }
        return recipeToEdit == nil ? creationMode.title : "Edit your recipe"
    }
    private var editorSubtitle: String {
        if pendingRecipeSave != nil { return "Your reviewed recipe is kept here until saving is confirmed. You can safely return later." }
        if importedRecipe != nil { return "Confirm ingredient amounts, yield and nutrition before adding this recipe to your library." }
        return recipeToEdit == nil ? creationMode.subtitle : "Update your recipe. Earlier food logs keep their saved amounts."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    if pendingRecipeSave != nil || importedRecipe != nil || creationMode != .manual {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            if pendingRecipeSave != nil || importedRecipe != nil {
                                Text(editorTitle).appTextRole(.sectionTitle)
                            }
                            Text(editorSubtitle).appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                    }

                    if recipeToEdit == nil && pendingRecipeSave == nil && !revisionSession.isUnreadable && importedRecipe == nil {
                        CreateRecipeModePicker(selection: $creationMode)
                            .disabled(pendingRecipeSave != nil)
                        Button { showingPhotoImport = true } label: { Label("Scan a written recipe", systemImage: "doc.viewfinder") }
                            .frame(minHeight: 44).accessibilityIdentifier("recipe_scan_document")
                    }
                    if importedRecipe != nil && pendingRecipeSave == nil {
                        Label("Draft · review before saving", systemImage: "doc.text").appTextRole(.control).foregroundStyle(AppPalette.text)
                            .accessibilityIdentifier("recipe_import_draft")
                        Text("Confirm the yield and nutrition basis. Imported nutrition may be an estimate; unmatched ingredients remain visible for review.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        if let source = importedRecipe?.importProvenance?.sourceURL { Text(source).appTextRole(.caption).foregroundStyle(.secondary) }
                        if let sourceText = importedRecipe?.importProvenance?.originalText {
                            DisclosureGroup("Source text and extraction notes") { Text(sourceText).appTextRole(.caption).textSelection(.enabled) }
                        }
                        if let missing = importedRecipe?.importProvenance?.missingNutritionFields, !missing.isEmpty, nutritionChoice == .keepSaved {
                            Text("Not supplied: \(missing.joined(separator: ", ")). Match the ingredients and recalculate before using this recipe for logging or planning.")
                                .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        }
                    }

                    if let pendingRecipeSave {
                        pendingRecipeSection(pendingRecipeSave)
                    } else if revisionSession.isUnreadable {
                        Text("The pending recipe save is preserved. A new proposal cannot replace it until it can be recovered.")
                            .appTextRole(.body).foregroundStyle(.secondary)
                    } else { modeContent }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .accessibilityIdentifier("recipe_editor_scroll")
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(recipeToEdit == nil ? "Create Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(pendingRecipeSave == nil ? "Cancel" : "Close") { dismiss() }
                        .tint(AppPalette.brand)
                }
                if pendingRecipeSave == nil, !revisionSession.isUnreadable, !checkpointUnreadable {
                    ToolbarItem(placement: .primaryAction) {
                        Menu { Button("Discard editor draft", role: .destructive) { showingDiscardForm = true } } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("Recipe draft options")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("recipe_editor_keyboard_done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                    if let error = saveError ?? revisionSession.errorMessage {
                        Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("create_recipe_error")
                    }
                    Button(action: saveRecipe) {
                        Label(actionTitle, systemImage: actionIcon)
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled((pendingRecipeSave == nil && isSaveDisabled) || isLoading || revisionSession.isWorking || revisionSession.isUnreadable || checkpointUnreadable)
                    .accessibilityIdentifier("create_recipe_action")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("recipe_editor_footer")
            }
            .sheet(isPresented: $showingFoodSearch, onDismiss: {
                replacingUnresolvedIndex = nil
                ingredientMatch = pendingIngredientMatch; pendingIngredientMatch = nil
            }) {
                FoodSearchView(
                    dailyLog: $dailyLogService.currentDailyLog,
                    onFoodItemLogged: nil,
                    onFoodItemSelected: addIngredient,
                    searchContext: "recipe_ingredient"
                )
            }
            .sheet(item: $ingredientMatch) { request in
                RecipeIngredientMatchReview(sourceText: request.source, selectedFood: request.food) { food in
                    guard request.owner == DIContainer.shared.authService.currentUserID,
                          unresolvedIngredients.indices.contains(request.index), unresolvedIngredients[request.index] == request.source else {
                        saveError = "This source ingredient changed. Reopen its food match."; return
                    }
                    var value = food; value.id = UUID().uuidString
                    ingredients.append(value); unresolvedIngredients.remove(at: request.index)
                    ingredientMatch = nil; HapticManager.instance.feedback(.light)
                }
            }
            .sheet(item: $componentReview) { request in
                RecipeComponentReviewView(recipe: request.recipe) { reviewed in
                    guard request.ownerID == DIContainer.shared.authService.currentUserID,
                          componentReview?.id == request.id,
                          (try? PlanFingerprint.make(formCheckpoint)) == request.editorFingerprint,
                          pendingRecipeSave == nil else {
                        saveError = "The recipe editor changed. Reopen component review from its latest draft."; return
                    }
                    loadImportedDraft(reviewed); componentReview = nil
                }
            }
            .sheet(isPresented: $showingPhotoImport) {
                RecipePhotoImportView { text, provenance in
                    showingPhotoImport = false
                    importText = text
                    isLoading = true
                    let owner = DIContainer.shared.authService.currentUserID
                    Task { @MainActor in
                        defer { isLoading = false }
                        guard let owner, let draft = await recipeService.createRecipeFromText(text: text, userID: owner, saveResult: false), DIContainer.shared.authService.currentUserID == owner else {
                            saveError = "The scanned pages are kept. Parsing didn't finish; reopen Scan or try again."; return
                        }
                        var value = draft; value.importProvenance = provenance
                        acceptImportedDraft(value)
                    }
                }
            }
            .sheet(isPresented: $choosingImport) {
                NavigationStack {
                    List(Array(importChoices.enumerated()), id: \.offset) { _, recipe in
                        Button(recipe.name) { choosingImport = false; acceptImportedDraft(recipe) }.frame(minHeight: 44)
                    }
                    .navigationTitle("Choose recipe")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingImport = false } } }
                }
            }
            .confirmationDialog("Discard this editor draft?", isPresented: $showingDiscardForm, titleVisibility: .visible) {
                Button("Discard editor draft", role: .destructive) { discardForm() }
                Button("Keep draft", role: .cancel) {}
            } message: { Text("The saved recipe and food logs stay intact. Captured source pages remain available in Scan.") }
            .confirmationDialog("This recipe source is already in your library", isPresented: $showingDuplicate, titleVisibility: .visible) {
                Button("Review an update to the saved recipe") {
                    guard var draft = duplicateDraft, let original = duplicateOriginal else { return }
                    draft.id = original.id; draft.libraryMetadata = original.libraryMetadata
                    expectedRecipe = original; loadImportedDraft(draft)
                }
                Button("Create a separate variation") {
                    guard var draft = duplicateDraft else { return }
                    reviewedDuplicateSource = RecipeImportDuplicateRules.sourceIdentity(draft.importProvenance)
                    draft.id = nil; expectedRecipe = nil; loadImportedDraft(draft)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Updating uses a checked save. A separate variation gets a new identity and leaves the saved recipe intact.") }
            .overlay {
                if isLoading {
                    CreateRecipeProgressOverlay(mode: creationMode)
                }
            }
            .interactiveDismissDisabled(isLoading)
        }
        .accessibilityIdentifier("create_recipe")
        .task { restoreForm() }
        .onChange(of: formData) { _, _ in persistForm() }
        .onChange(of: ingredientSnapshot) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: unresolvedIngredients) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: instructions) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: servingsText) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: yieldChoice) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: nutritionChoice) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: cookedWeightText) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: ingredientBasisSelection) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: prepMinutes) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: equipment) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: planningDiet) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: reviewedExclusions) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onChange(of: estimatedCost) { _, _ in if checkpointReady { reviewedPlanning = false } }
        .onDisappear { persistForm() }
    }

    private var planningSection: some View {
        DisclosureGroup("Planning details", isExpanded: $planningDetailsExpanded) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Optional personal estimates make constraints checkable. Unknown values stay unknown.").appTextRole(.secondary).foregroundStyle(.secondary)
                TextField("Preparation minutes · optional", text: $prepMinutes).keyboardType(.numberPad).accessibilityIdentifier("recipe_planning_minutes")
                TextField("Equipment · e.g. stove, oven, or no cooking", text: $equipment).accessibilityIdentifier("recipe_planning_equipment")
                Picker("Ingredient pattern", selection: $planningDiet) { ForEach(PlanningDiet.allCases) { Text($0.title).tag($0) } }
                TextField("Personally checked exclusions · comma separated", text: $reviewedExclusions)
                TextField("Estimated USD per serving · optional", text: $estimatedCost).keyboardType(.decimalPad).accessibilityIdentifier("recipe_planning_cost")
                Text("An ingredient review does not verify manufacturer allergens or kitchen cross-contact. Prices are your estimates; they are not live store prices.").appTextRole(.caption).foregroundStyle(.secondary)
                Toggle("I've checked these details against the ingredients", isOn: $reviewedPlanning).accessibilityIdentifier("recipe_planning_reviewed")
            }.textFieldStyle(.roundedBorder).padding(.top, AppSpacing.row)
        }.appSurface(.quiet)
    }
    private func splitList(_ text: String) -> [String] {
        Array(Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    private var formScope: String { "recipe-editor-" + (recipeToEdit?.id ?? "new") }
    private var formCheckpoint: RecipeEditorFormCheckpoint {
        RecipeEditorFormCheckpoint(identity: newRecipeID, expected: expectedRecipe, imported: importedRecipe,
            name: recipeName, ingredients: ingredients, unresolved: unresolvedIngredients,
            nutrition: nutritionChoice.rawValue, servings: servingsText, yield: yieldChoice.rawValue,
            weight: cookedWeightText, instructions: instructions, mode: creationMode.rawValue,
            description: aiDescription, text: importText, url: importURL, prep: prepMinutes,
            equipment: equipment, diet: planningDiet, exclusions: reviewedExclusions,
            cost: estimatedCost, reviewed: reviewedPlanning, ingredientBasis: ingredientBasisSelection,
            reviewedDuplicateSource: reviewedDuplicateSource)
    }
    private var formData: Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(formCheckpoint)
    }
    private func restoreForm() {
        guard !checkpointReady else { return }
        checkpointOwner = DIContainer.shared.authService.currentUserID
        defer { checkpointReady = true }
        guard let owner = checkpointOwner else { return }
        do {
            guard let saved = try EditorDraftStore().load(RecipeEditorFormCheckpoint.self, userID: owner, scope: formScope)?.value else { return }
            formExpectedFingerprint = try PlanFingerprint.make(saved)
            ingredientBasisSelection = saved.ingredientBasis
            newRecipeID = saved.identity; expectedRecipe = saved.expected; importedRecipe = saved.imported
            reviewedDuplicateSource = saved.reviewedDuplicateSource
            recipeName = saved.name; ingredients = saved.ingredients; unresolvedIngredients = saved.unresolved
            nutritionChoice = .init(rawValue: saved.nutrition) ?? .keepSaved
            yieldChoice = .init(rawValue: saved.yield) ?? .keepSaved; servingsText = saved.servings
            cookedWeightText = saved.weight; instructions = saved.instructions
            creationMode = .init(rawValue: saved.mode) ?? .manual
            aiDescription = saved.description; importText = saved.text; importURL = saved.url
            prepMinutes = saved.prep; equipment = saved.equipment; planningDiet = saved.diet
            reviewedExclusions = saved.exclusions; estimatedCost = saved.cost; reviewedPlanning = saved.reviewed
        } catch { checkpointUnreadable = true; saveError = "An older editor draft couldn't be opened and has been preserved. Finish its recovery before replacing it." }
    }
    private func persistForm() {
        guard checkpointReady, !formFinished, !checkpointUnreadable, let owner = checkpointOwner,
              DIContainer.shared.authService.currentUserID == owner else { return }
        do {
            let store = EditorDraftStore()
            let existing = try store.load(RecipeEditorFormCheckpoint.self, userID: owner, scope: formScope)?.value
            guard try existing.map({ try PlanFingerprint.make($0) }) == formExpectedFingerprint else {
                saveError = "A newer recipe draft is kept. Close and reopen it before making another change."; return
            }
            let value = formCheckpoint
            try store.save(value, userID: owner, scope: formScope)
            formExpectedFingerprint = try PlanFingerprint.make(value)
        } catch { saveError = "Couldn't keep this edit on the device. Keep this screen open and try saving again." }
    }

    private func pendingRecipeSection(_ proposal: RecipeRevisionSaveProposal) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Text(proposal.updated.name).appTextRole(.sectionTitle)
                .accessibilityIdentifier("recipe_pending_name")
            Text(submittedNutritionBasisLabel(proposal.updated)).appTextRole(.secondary).foregroundStyle(.secondary)
            CreateRecipeNutritionPreview(nutrition: proposal.updated.nutrition,
                subtitle: proposal.updated.nutritionBasis == .wholeRecipe ? "Submitted whole-batch nutrition" : "Submitted saved nutrition")
            if let weight = proposal.updated.cookedWeightGrams {
                Text("Cooked batch · \(weight.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            DisclosureGroup("Submitted ingredients") {
                ForEach(Array(proposal.updated.ingredients.enumerated()), id: \.offset) { _, text in
                    Text(text).appTextRole(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Button { resolvePendingRecipe(cancelIfUnaccepted: false) } label: {
                    Text("Check saved status").appFont(size: 17, weight: .medium)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.text)
                .accessibilityIdentifier("recipe_pending_check_status")
                Button(role: .destructive) { resolvePendingRecipe(cancelIfUnaccepted: true) } label: {
                    Text("Cancel pending save").appFont(size: 17, weight: .medium)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.critical)
                .accessibilityIdentifier("recipe_pending_cancel")
                Text("Cancellation checks the server first. A recipe that was already saved stays saved; later edits or deletion are preserved.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            .disabled(isLoading || revisionSession.isWorking)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_pending_save")
    }

    private func submittedNutritionBasisLabel(_ recipe: Recipe) -> String {
        let yield = recipe.servings.map { $0.formatted(.number.precision(.fractionLength(0...2))) }
        switch recipe.nutritionBasis {
        case .wholeRecipe:
            return yield.map { "Whole batch · yields \($0) servings" } ?? "Whole batch · yield unconfirmed"
        case .perServing:
            return yield.map { "Nutrition per serving · \($0) servings per batch" } ?? "Nutrition per serving"
        case nil:
            return "Saved amount · original serving basis unconfirmed"
        }
    }

    private func resolvePendingRecipe(cancelIfUnaccepted: Bool) {
        guard !isLoading, !revisionSession.isWorking else { return }
        saveError = nil
        Task {
            let proposal = revisionSession.proposal
            guard await revisionSession.resolve(using: recipeService, cancelIfUnaccepted: cancelIfUnaccepted) else { return }
            if let proposal {
                finishEditor(for: proposal, accepted: revisionSession.wasAccepted)
                if matchesOpeningEditor(proposal), let saved = revisionSession.acceptedRecipe { onSaved?(saved) }
            }
            dismiss()
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch creationMode {
        case .ai:
            recipeTextInputSection(
                title: "Recipe Brief",
                subtitle: "Include portions, ingredients, cuisine, and macro targets when they matter.",
                placeholder: "Example: High-protein chicken burrito bowls for two servings, around 600 calories each.",
                text: $aiDescription,
                identifier: "create_recipe_ai_input"
            )
        case .text:
            recipeTextInputSection(
                title: "Recipe Text",
                subtitle: "Paste the ingredients, instructions, and any available nutrition details.",
                placeholder: "Paste the recipe text here.",
                text: $importText,
                identifier: "create_recipe_text_input"
            )
        case .url:
            urlSection
        case .manual:
            manualSection
        }
    }

    private func recipeTextInputSection(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title, subtitle: subtitle)

            TextEditor(text: text)
                .appTextRole(.body)
                .frame(minHeight: 190)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .appTextRole(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .appSurface(.quiet)
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Recipe URL",
                subtitle: "Use a public recipe blog or website. Paywalled and sign-in-only pages may not import."
            )

            TextField("https://example.com/recipe", text: $importURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .appTextRole(.body)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 50)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Recipe URL")
                .accessibilityIdentifier("create_recipe_url_input")
        }
        .appSurface(.quiet)
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            recipeNameSection
            ingredientSection
            nutritionBasisSection

            if !ingredients.isEmpty || baseRecipe != nil {
                CreateRecipeNutritionPreview(nutrition: totalNutrition, subtitle: nutritionPreviewSubtitle)
            }

            instructionSection
            DisclosureGroup("Recipe assistance") {
                Button { openComponentReview() } label: {
                    Label("Review one component", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .disabled(ingredients.isEmpty && unresolvedIngredients.isEmpty || !checkpointReady || checkpointUnreadable)
                .accessibilityIdentifier("recipe_component_review")
            }
            .appTextRole(.control)
            .tint(AppPalette.text)
            planningSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create_recipe_manual")
    }

    private var nutritionBasisSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Batch and yield", subtitle: nutritionChoice == .keepSaved
                ? "Ingredient edits affect nutrition after you choose Recalculate ingredients."
                : ingredientBasisSelection == .perServing ? "Calculated nutrition describes one serving." : "Calculated nutrition describes the whole batch.")
            Picker("Ingredient amounts describe", selection: $ingredientBasisSelection) {
                if baseRecipe != nil { Text("Keep original interpretation").tag(Optional<RecipeNutritionBasis>.none) }
                Text("The whole batch").tag(Optional(RecipeNutritionBasis.wholeRecipe))
                Text("One serving").tag(Optional(RecipeNutritionBasis.perServing))
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("recipe_ingredient_basis")
            DisclosureGroup("How ingredient amounts work") {
                Text("For four servings with 400 g of rice in the full recipe, choose whole-batch ingredients. The nutrition label can still describe one serving.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if nutritionChoice == .keepSaved {
                Text("Nutrition values").appTextRole(.control)
                if baseRecipe?.ingredientBasis != nil, baseRecipe?.nutritionBasis == nil, yieldChoice == .keepSaved {
                    Text("Choose what the supplied nutrition describes before logging or planning this recipe. You can save the draft for later review.").appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                }
                Text(savedNutritionBasisLabel)
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                Picker("Saved nutrition describes", selection: $yieldChoice) {
                    Text("Keep original basis").tag(RecipeEditingState.YieldChoice.keepSaved)
                    Text("The whole batch").tag(RecipeEditingState.YieldChoice.wholeRecipe)
                    Text("One serving").tag(RecipeEditingState.YieldChoice.perServing)
                }
                .pickerStyle(.menu).frame(minHeight: 44)
                .accessibilityIdentifier("recipe_yield_basis")
                if yieldChoice != .keepSaved {
                    Text("Confirm the saved numbers describe \(yieldChoice == .wholeRecipe ? "the entire batch" : "one serving"). Portion calculations change after saving.")
                        .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                }
                Button("Recalculate ingredients") { nutritionChoice = .recalculate }
                    .disabled(!editingState.canRecalculate)
                    .accessibilityIdentifier("recipe_recalculate_ingredients")
                if !unresolvedIngredients.isEmpty {
                    Text("Match or remove every unlinked ingredient before recalculating. Missing nutrition is unknown, not zero.")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                }
            }
            if nutritionChoice == .recalculate || yieldChoice != .keepSaved {
                HStack {
                    Text("Servings per batch").appTextRole(.body)
                    TextField("1", text: $servingsText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(minWidth: 64, maxWidth: 110, minHeight: 44)
                        .accessibilityLabel("Servings per whole recipe")
                        .accessibilityIdentifier("recipe_yield")
                }
                Text("Total batch yield · greater than zero, up to 100 servings.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if baseRecipe != nil && nutritionChoice == .recalculate {
                    Button("Keep saved nutrition") { nutritionChoice = .keepSaved }
                }
            }
            if nutritionChoice == .recalculate || yieldChoice != .keepSaved || baseRecipe?.nutritionBasis != nil {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Cooked batch weight").appTextRole(.body)
                    Spacer(minLength: AppSpacing.compact)
                    TextField("Optional", text: $cookedWeightText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(minWidth: 64, maxWidth: 110, minHeight: 44)
                        .accessibilityLabel("Cooked batch weight in grams")
                        .accessibilityIdentifier("recipe_cooked_weight")
                    Text("g").appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Text("Weigh the finished edible batch to log by grams. Raw weights stay separate.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
    }

    private var recipeNameSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Recipe name")

            TextField("Recipe name", text: $recipeName)
                .textInputAutocapitalization(.words)
                .appTextRole(.control)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 50)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityIdentifier("create_recipe_name")
        }
        .appSurface(.quiet)
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Ingredients",
                subtitle: ingredients.isEmpty
                    ? "Add foods to calculate the recipe's nutrition."
                    : "\(ingredients.count.formatted()) ingredient\(ingredients.count == 1 ? "" : "s") included."
            ) {
                Button {
                    showingFoodSearch = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add ingredient")
                .accessibilityIdentifier("create_recipe_add_ingredient")
            }

            if !unresolvedIngredients.isEmpty {
                ForEach(Array(unresolvedIngredients.enumerated()), id: \.offset) { index, text in
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(text).appTextRole(.body)
                        Text("Unlinked ingredient · nutrition unknown").appTextRole(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Match food") { replacingUnresolvedIndex = index; showingFoodSearch = true }
                            Spacer()
                            Button("Remove", role: .destructive) { unresolvedIngredients.remove(at: index) }
                        }
                        .frame(minHeight: 44)
                    }.appSurface(.quiet)
                }
            }
            if ingredients.isEmpty && unresolvedIngredients.isEmpty {
                Button {
                    showingFoodSearch = true
                } label: {
                    VStack(spacing: AppSpacing.compact) {
                        Image(systemName: "plus.circle")
                            .appTextRole(.sectionTitle)
                            .foregroundStyle(AppPalette.brandText)
                        Text("Add Your First Ingredient")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Text("Search foods you already use or find a new ingredient.")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.section)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appSurface(.quiet, padding: 0)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        RecipeLoggingIngredientRow(
                            ingredient: ingredient,
                            onQuantityChange: { quantity in
                                guard let position = ingredients.firstIndex(where: { $0.id == ingredient.id }),
                                      let adjusted = RecipeIngredientQuantityRules.adjustedIngredient(ingredients[position], newQuantity: quantity) else { return }
                                ingredients[position] = adjusted
                            },
                            onValidityChanged: { valid in
                                if valid { invalidIngredientIDs.remove(ingredient.id) } else {
                                    invalidIngredientIDs.insert(ingredient.id)
                                }
                            },
                            onDelete: { removeIngredient(ingredient) }
                        )

                        if index < ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create_recipe_ingredients")
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Instructions",
                subtitle: "Put each step on a new line."
            )

            TextEditor(text: $instructions)
                .appTextRole(.body)
                .frame(minHeight: 180)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("1. Prepare the ingredients\n2. Cook and assemble\n3. Serve")
                            .appTextRole(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Recipe instructions")
                .accessibilityIdentifier("create_recipe_instructions")
        }
        .appSurface(.quiet)
    }

    private var actionTitle: String {
        if pendingRecipeSave != nil { return "Retry save" }
        switch creationMode {
        case .ai: return "Generate Recipe"
        case .text, .url: return "Import Recipe"
        case .manual:
            if baseRecipe?.ingredientBasis != nil, baseRecipe?.nutritionBasis == nil, nutritionChoice == .keepSaved, yieldChoice == .keepSaved { return "Save Recipe Draft" }
            return recipeToEdit == nil ? "Save Recipe" : "Save Changes"
        }
    }

    private var actionIcon: String {
        if pendingRecipeSave != nil { return "checkmark" }
        switch creationMode {
        case .ai: return "sparkles"
        case .text, .url: return "square.and.arrow.down"
        case .manual: return "checkmark"
        }
    }

    private var isSaveDisabled: Bool {
        switch creationMode {
        case .ai:
            aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .text:
            importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url:
            importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manual:
            recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !invalidIngredientIDs.isEmpty ||
                (ingredients.isEmpty && unresolvedIngredients.isEmpty) ||
                (nutritionChoice == .recalculate && (!editingState.canRecalculate || !editingState.servings.isFinite || editingState.servings <= 0 || editingState.servings > 100)) ||
                (yieldChoice != .keepSaved && (!editingState.servings.isFinite || editingState.servings <= 0 || editingState.servings > 100)) ||
                (editingState.cookedWeightGrams.map { !$0.isFinite || $0 <= 0 || $0 > 1_000_000 } ?? false) ||
                instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func addIngredient(foodItem: FoodItem) {
        if let index = replacingUnresolvedIndex, unresolvedIngredients.indices.contains(index) {
            pendingIngredientMatch = RecipeIngredientMatchRequest(index: index, source: unresolvedIngredients[index], food: foodItem,
                owner: DIContainer.shared.authService.currentUserID)
        } else {
            var ingredient = foodItem; ingredient.id = UUID().uuidString
            ingredients.append(ingredient); HapticManager.instance.feedback(.light)
        }
        showingFoodSearch = false
    }

    private func removeIngredient(_ ingredient: FoodItem) {
        ingredients.removeAll { $0.id == ingredient.id }
        invalidIngredientIDs.remove(ingredient.id)
        HapticManager.instance.feedback(.light)
    }

    private func saveRecipe() {
        guard let userID = DIContainer.shared.authService.currentUserID, checkpointOwner == userID else {
            bannerService.showBanner(
                title: "Sign In Required",
                message: "Sign in before saving a recipe.",
                iconName: "person.crop.circle.badge.exclamationmark",
                iconColor: AppPalette.caution
            )
            return
        }

        HapticManager.instance.feedback(.medium)
        saveError = nil
        isLoading = true

        Task { @MainActor in
            defer { isLoading = false }
            if pendingRecipeSave != nil || creationMode == .manual {
                guard await saveManualRecipe(for: userID) else {
                    saveError = saveError ?? revisionSession.errorMessage ?? "Your exact recipe is kept. Check its status or try again."; return
                }
                bannerService.showBanner(title: expectedRecipe == nil ? "Recipe Saved" : "Recipe Updated", message: "Your reviewed recipe is in the library.", iconName: "checkmark.circle.fill", iconColor: .accentPositive)
                dismiss(); return
            }
            var result: Recipe?
            switch creationMode {
            case .ai: result = await recipeService.createRecipeFromAI(description: aiDescription, userID: userID, saveResult: false)
            case .text: result = await recipeService.createRecipeFromText(text: importText, userID: userID, saveResult: false)
            case .url:
                do {
                    let choices = try await recipeService.draftRecipesFromURL(url: importURL, userID: userID)
                    await recipeService.fetchUserRecipes()
                    guard DIContainer.shared.authService.currentUserID == userID else { return }
                    if choices.count > 1 { importChoices = choices; choosingImport = true; return }
                    result = choices.first
                } catch { saveError = error.localizedDescription }
            case .manual: break
            }
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            if let result {
                await recipeService.fetchUserRecipes()
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                acceptImportedDraft(result)
            } else { saveError = saveError ?? "The source is kept. No recipe was saved. Review the text or try another source." }
        }
    }

    private func openComponentReview() {
        guard let owner = DIContainer.shared.authService.currentUserID, owner == checkpointOwner,
              pendingRecipeSave == nil, !revisionSession.isWorking else { return }
        do {
            let steps = instructions.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let draft = try editingState.makeRecipe(name: recipeName.isEmpty ? "Recipe draft" : recipeName, instructions: steps)
            componentReview = RecipeComponentReviewRequest(ownerID: owner, recipe: draft,
                editorFingerprint: try PlanFingerprint.make(formCheckpoint))
        } catch { saveError = error.localizedDescription }
    }

    private func acceptImportedDraft(_ recipe: Recipe) {
        if let existing = RecipeImportDuplicateRules.matchingRecipe(for: recipe, in: recipeService.userRecipes) {
            duplicateDraft = recipe; duplicateOriginal = existing; showingDuplicate = true
        } else { loadImportedDraft(recipe) }
    }

    private func loadImportedDraft(_ recipe: Recipe) {
        importedRecipe = recipe
        recipeName = recipe.name
        ingredientBasisSelection = recipe.ingredientBasis
        let edit = RecipeEditingState(recipe: recipe)
        ingredients = edit.ingredients; unresolvedIngredients = edit.unresolvedIngredients
        nutritionChoice = .keepSaved; yieldChoice = .keepSaved
        servingsText = (recipe.servings ?? 1).formatted(.number.precision(.fractionLength(0...2)))
        cookedWeightText = recipe.cookedWeightGrams.map { String($0) } ?? ""
        instructions = recipe.instructions.joined(separator: "\n"); creationMode = .manual
        reviewedPlanning = false; saveError = nil
        persistForm()
    }

    private func discardForm() {
        guard pendingRecipeSave == nil, !isLoading, !revisionSession.isWorking, let owner = checkpointOwner,
              DIContainer.shared.authService.currentUserID == owner else { return }
        do {
            let store = EditorDraftStore()
            if let saved = try store.load(RecipeEditorFormCheckpoint.self, userID: owner, scope: formScope) {
                guard try PlanFingerprint.make(saved.value) == formExpectedFingerprint else { throw MealPlanEditError.changed }
                guard try store.removeIfUnchanged(RecipeEditorFormCheckpoint.self, userID: owner, scope: formScope, fingerprint: PlanFingerprint.make(saved.value)) else { throw MealPlanEditError.changed }
            } else if formExpectedFingerprint != nil { throw MealPlanEditError.changed }
            formFinished = true; dismiss()
        } catch { saveError = "A newer editor draft is kept. Reopen it before discarding." }
    }

    private func matchesOpeningEditor(_ proposal: RecipeRevisionSaveProposal) -> Bool {
        if let scope = proposal.editorScope, let identity = proposal.editorIdentity { return scope == formScope && identity == newRecipeID }
        return recipeToEdit?.id != nil && recipeToEdit?.id == proposal.expected?.id
    }
    private func finishEditor(for proposal: RecipeRevisionSaveProposal, accepted: Bool) {
        guard DIContainer.shared.authService.currentUserID == proposal.userID else { return }
        if let scope = proposal.editorScope, let identity = proposal.editorIdentity, let fingerprint = proposal.editorFingerprint {
            do {
                let store = EditorDraftStore()
                if try store.load(RecipeEditorFormCheckpoint.self, userID: proposal.userID, scope: scope)?.value.identity == identity {
                    let removed = try store.removeIfUnchanged(RecipeEditorFormCheckpoint.self, userID: proposal.userID, scope: scope, fingerprint: fingerprint)
                    if removed && matchesOpeningEditor(proposal) { formFinished = true }
                }
            } catch { saveError = "The save is resolved; the separate editor draft is still kept on this device." }
        }
        if accepted, let provenance = proposal.updated.importProvenance, provenance.kind == .photo {
            RecipePhotoImportView.finish(userID: proposal.userID, provenance: provenance)
        }
    }

    private func saveManualRecipe(for userID: String) async -> Bool {
        let instructionSteps = instructions
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let proposal: RecipeRevisionSaveProposal
            if let pendingRecipeSave { proposal = pendingRecipeSave } else {
                var recipe = try editingState.makeRecipe(name: recipeName.trimmingCharacters(in: .whitespacesAndNewlines), instructions: instructionSteps)
                if recipe.id == nil { recipe.id = newRecipeID }
                if expectedRecipe == nil,
                   let identity = RecipeImportDuplicateRules.sourceIdentity(recipe.importProvenance), identity != reviewedDuplicateSource {
                    // Check the accepted library again at save time, including
                    // imports opened from a photo or restored editor draft.
                    let library = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: userID)
                    guard DIContainer.shared.authService.currentUserID == userID else { throw CancellationError() }
                    if let existing = RecipeImportDuplicateRules.matchingRecipe(for: recipe, in: library) {
                        duplicateDraft = recipe; duplicateOriginal = existing; showingDuplicate = true
                        saveError = "This source is already saved. Review an update or choose a separate variation."
                        return false
                    }
                }
                let prep = prepMinutes.trimmingCharacters(in: .whitespaces)
                let cost = estimatedCost.trimmingCharacters(in: .whitespaces)
                guard prep.isEmpty || Int(prep).map({ (1...480).contains($0) }) == true,
                      cost.isEmpty || Double(cost).map({ $0.isFinite && (0...100_000).contains($0) }) == true else {
                    saveError = "Enter a valid preparation time and price, or leave an unknown value empty."; return false
                }
                if reviewedPlanning || !prep.isEmpty || !equipment.isEmpty || planningDiet != .unrestricted || !reviewedExclusions.isEmpty || !cost.isEmpty {
                    recipe.planningProfile = RecipePlanningProfile(prepMinutes: Int(prep), equipment: splitList(equipment), diet: planningDiet,
                        reviewedExclusions: splitList(reviewedExclusions), costPerServing: Double(cost), reviewedAt: reviewedPlanning ? Date() : nil,
                        contentFingerprint: reviewedPlanning ? try RecipePlanningProfile.fingerprint(recipe) : nil)
                } else { recipe.planningProfile = nil }
                recipe.revisionID = try RecipePortionRules.revisionID(for: recipe)
                persistForm()
                let editorFingerprint = try PlanFingerprint.make(formCheckpoint)
                guard editorFingerprint == formExpectedFingerprint else { saveError = "The editor draft changed. Close and reopen its latest version before saving."; return false }
                proposal = RecipeRevisionSaveProposal(userID: userID, operationID: recipeSaveOperationID,
                    expected: expectedRecipe?.id == nil ? nil : expectedRecipe, updated: recipe,
                    editorScope: formScope, editorIdentity: newRecipeID, editorFingerprint: editorFingerprint)
                guard revisionSession.prepare(proposal) else { return false }
            }
            guard proposal.userID == userID else { throw CancellationError() }
            guard await revisionSession.submit(using: recipeService) else { return false }
            finishEditor(for: proposal, accepted: true)
            if matchesOpeningEditor(proposal), let saved = revisionSession.acceptedRecipe { onSaved?(saved) }
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}

private struct RecipeComponentReviewRequest: Identifiable {
    let id = UUID()
    let ownerID: String
    let recipe: Recipe
    let editorFingerprint: String
}

private struct RecipeIngredientMatchRequest: Identifiable {
    let id = UUID()
    let index: Int
    let source: String
    let food: FoodItem
    let owner: String?
}

private struct RecipeEditorFormCheckpoint: Codable {
    var identity: String
    var expected: Recipe?
    var imported: Recipe?
    var name: String
    var ingredients: [FoodItem]
    var unresolved: [String]
    var nutrition: String
    var servings: String
    var yield: String
    var weight: String
    var instructions: String
    var mode: String
    var description: String
    var text: String
    var url: String
    var prep: String
    var equipment: String
    var diet: PlanningDiet
    var exclusions: String
    var cost: String
    var reviewed: Bool
    var ingredientBasis: RecipeNutritionBasis?
    var reviewedDuplicateSource: String?
}

private struct CreateRecipeModePicker: View {
    @Binding var selection: CreateRecipeView.CreationMode

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(CreateRecipeView.CreationMode.allCases) { mode in
                        Button {
                            selection = mode
                        } label: {
                            Label(
                                mode.title,
                                systemImage: selection == mode ? "checkmark" : mode.systemImage
                            )
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        Image(systemName: selection.systemImage)
                            .foregroundStyle(AppPalette.brandText)
                        Text(selection.title)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Spacer(minLength: AppSpacing.compact)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(AppPalette.brandText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appSurface(.quiet)
                .accessibilityLabel("Creation method")
                .accessibilityValue(selection.title)
            } else {
                Picker("Creation method", selection: $selection) {
                    ForEach(CreateRecipeView.CreationMode.allCases) { mode in
                        Text(mode.shortTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .accessibilityIdentifier("create_recipe_mode")
    }
}

private struct CreateRecipeNutritionPreview: View {
    let nutrition: Nutrition
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition Preview",
                subtitle: subtitle
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calories",
                    value: "\(Int(nutrition.calories.rounded()).formatted()) cal",
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Protein",
                    value: "\(Int(nutrition.protein.rounded()).formatted()) g",
                    accent: .accentProtein
                ),
                AppMetricItem(
                    label: "Carbs",
                    value: "\(Int(nutrition.carbs.rounded()).formatted()) g",
                    accent: .accentCarbs
                ),
                AppMetricItem(
                    label: "Fat",
                    value: "\(Int(nutrition.fats.rounded()).formatted()) g",
                    accent: .accentFats
                )
            ])
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("create_recipe_nutrition")
    }
}

private struct CreateRecipeProgressOverlay: View {
    let mode: CreateRecipeView.CreationMode

    private var title: String {
        switch mode {
        case .ai: "Generating Recipe"
        case .text, .url: "Importing Recipe"
        case .manual: "Saving Recipe"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.row) {
                ProgressView()
                    .tint(AppPalette.brand)
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text("This may take a moment.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
            .appSurface(.emphasized)
            .padding(AppSpacing.screenHorizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
