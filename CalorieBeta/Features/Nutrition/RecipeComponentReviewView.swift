import MyFitPlateCore
import SwiftUI

private struct RecipeComponentCheckpoint: Codable {
    var component: String
    var request: String
    var candidate: Recipe?
    var editedText: String
}

struct RecipeComponentReviewView: View {
    let recipe: Recipe
    let onReviewedDraft: (Recipe) -> Void
    @EnvironmentObject private var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss
    @State private var component: RecipeComponentRules.Component = .instructions
    @State private var request = ""
    @State private var candidate: Recipe?
    @State private var editedText = ""
    @State private var acknowledged = false
    @State private var busy = false
    @State private var error: String?
    @State private var generation: UUID?
    @State private var ready = false
    @State private var unreadable = false
    @State private var expectedFingerprint: String?
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    private var scope: String { "recipe-component-" + ((try? RecipePortionRules.revisionID(for: recipe)) ?? recipe.id ?? recipe.name) }
    private var checkpoint: RecipeComponentCheckpoint { RecipeComponentCheckpoint(component: component.rawValue, request: request, candidate: candidate, editedText: editedText) }
    private var checkpointFingerprint: String? { try? PlanFingerprint.make(checkpoint) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Keep the accepted recipe") {
                    Text(recipe.name).appTextRole(.control)
                    Text("Review one part at a time. Title and method changes keep your ingredients, yield and nutrition. Apply to your draft, then save the recipe.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Picker("Component", selection: Binding(get: { component }, set: { value in
                        component = value; candidate = nil; editedText = ""; acknowledged = false; generation = nil
                    })) {
                        ForEach(RecipeComponentRules.Component.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("recipe_component_scope")
                    if component != .ingredientNutrition {
                        TextField("What should change?", text: $request, axis: .vertical).lineLimit(2...5)
                            .accessibilityIdentifier("recipe_component_request")
                    }
                    Button(component == .ingredientNutrition ? "Recalculate from matched ingredients" : "Regenerate this component", action: regenerate)
                        .frame(minHeight: 44).disabled(busy || unreadable)
                        .accessibilityIdentifier("recipe_component_generate")
                }
                if busy { ProgressView("Preparing a component review") }
                if let candidate {
                    Section("Review the proposed change") {
                        if component == .ingredientNutrition {
                            Text("Saved: \(recipe.nutrition.calories.formatted()) calories · \(recipe.nutritionBasisLabel)")
                            Text("Calculated: \(candidate.nutrition.calories.formatted()) calories · \(candidate.nutritionBasisLabel)")
                            Text("Only complete matched ingredients can establish this total. Unknown nutrients remain unknown.")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        } else {
                            Text(component == .title ? recipe.name : recipe.instructions.joined(separator: "\n")).foregroundStyle(.secondary)
                            TextEditor(text: $editedText).frame(minHeight: 180).accessibilityIdentifier("recipe_component_proposal")
                        }
                        Toggle("I've checked this change", isOn: $acknowledged).frame(minHeight: 44)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution).accessibilityIdentifier("recipe_component_error") } }
                Section { Text("Your unfinished review is kept here. Check preparation changes against your ingredients; Maia does not verify allergen absence.").appTextRole(.secondary).foregroundStyle(.secondary) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("recipe_component_review")
            .navigationTitle("Refine one component").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { if persist() { generation = nil; dismiss() } } } }
            .safeAreaInset(edge: .bottom) {
                Button("Use reviewed component", action: accept).buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(candidate == nil || !acknowledged || busy || unreadable)
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("recipe_component_apply")
            }
            .onAppear(perform: restore)
            .onChange(of: checkpointFingerprint) { _, _ in if ready { _ = persist() } }
            .onDisappear { generation = nil }
        }
    }
    private func regenerate() {
        guard !busy, !unreadable, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        error = nil; acknowledged = false
        let selected = component, requestID = UUID(); generation = requestID
        if selected == .ingredientNutrition {
            do { candidate = try RecipeComponentRules.applying(selected, from: nil, to: recipe); _ = persist() } catch { self.error = error.localizedDescription }
            return
        }
        let ingredients = RecipePortionRules.originalIngredientLines(for: recipe)
        let prompt = "Revise only this recipe's \(selected.rawValue). Request: \(request.prefix(2_000)). Keep these exact ingredient strings in the same order: \(ingredients). Preserve yield \(recipe.servings ?? 1). Original title: \(recipe.name). Original instructions: \(recipe.instructions.joined(separator: " ").prefix(20_000)). Do not add ingredients. Other components will be discarded."
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard let generated = await recipeService.createRecipeFromAI(description: prompt, userID: ownerID, saveResult: false) else {
                if generation == requestID { error = "A component draft could not be prepared. Your original recipe is kept; retry or edit it manually." }
                return
            }
            guard generation == requestID, component == selected, ownerID == DIContainer.shared.authService.currentUserID else { return }
            do {
                candidate = try RecipeComponentRules.applying(selected, from: generated, to: recipe)
                editedText = selected == .title ? generated.name : generated.instructions.joined(separator: "\n")
                _ = persist()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func accept() {
        guard acknowledged, let candidate, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            var reviewed = candidate
            if component != .ingredientNutrition {
                let replacement = Recipe(name: component == .title ? editedText : recipe.name,
                    ingredients: RecipePortionRules.originalIngredientLines(for: recipe),
                    instructions: component == .instructions ? editedText.split(separator: "\n").map(String.init) : recipe.instructions,
                    nutrition: .zero)
                reviewed = try RecipeComponentRules.applying(component, from: replacement, to: recipe)
            }
            guard persist() else { return }
            onReviewedDraft(reviewed); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func restore() {
        guard !ready, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            if let saved = try EditorDraftStore().load(RecipeComponentCheckpoint.self, userID: ownerID, scope: scope)?.value {
                component = .init(rawValue: saved.component) ?? .instructions; request = saved.request
                candidate = saved.candidate; editedText = saved.editedText; expectedFingerprint = try PlanFingerprint.make(saved)
            }
        } catch { unreadable = true; self.error = "Your previous component review could not be opened. It has been kept." }
        ready = true
    }
    @discardableResult private func persist() -> Bool {
        guard ready, !unreadable, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return false }
        do {
            let store = EditorDraftStore()
            let previous = try store.load(RecipeComponentCheckpoint.self, userID: ownerID, scope: scope)?.value
            guard try previous.map(PlanFingerprint.make) == expectedFingerprint else { throw LibraryMutationError.changed }
            try store.save(checkpoint, userID: ownerID, scope: scope)
            expectedFingerprint = checkpointFingerprint; return true
        } catch { self.error = "This review is still open; the previous device checkpoint is kept. " + error.localizedDescription; return false }
    }
}

struct RecipeVariationReviewView: View {
    @Environment(\.dismiss) private var dismiss
    private let variation: Recipe?
    private let error: String?
    init(food: FoodItem) {
        do { variation = try RecipeVariationRules.variation(from: food); error = nil } catch {
            variation = nil; self.error = "This log does not retain complete adjusted ingredient amounts. Its nutrition and source remain available; create a reviewed recipe rather than guessing missing quantities."
        }
    }
    var body: some View {
        if let variation { CreateRecipeView(initialDraft: variation) } else {
            NavigationStack {
                Text(error ?? "No variation is available.").padding()
                    .navigationTitle("Recipe variation")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
        }
    }
}
