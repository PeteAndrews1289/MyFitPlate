import MyFitPlateCore
import SwiftUI

struct PlanningDocumentReviewView<Value: PlanningWorkspaceDocument>: View {
    @ObservedObject var session: PlanningDocumentSaveSession<Value>
    let save: (PlanningDocumentProposal<Value>) async throws -> Value
    let resolve: (PlanningDocumentProposal<Value>, Bool) async throws -> PlanningDocumentSaveResolution
    let onFinished: (PlanningDocumentSaveResolution) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Your review stays available until saving or cancellation is confirmed.")
                if let value = session.checkpoint {
                    Text(value.proposal.updated.name).appTextRole(.sectionTitle)
                    if let meal = value.proposal.updated as? SavedMealComposition {
                        ForEach(meal.components) { Text("\($0.name) · \($0.servingSize) · \(Int($0.calories.rounded())) cal") }
                        Text(meal.isArchived ? "This meal will be archived." : "This snapshot can be reused without changing past plans or food logs.")
                    }
                    if let week = value.proposal.updated as? SavedMealWeekTemplate {
                        Text("\(week.days.count) days · \(week.days.flatMap(\.meals).count) planned meals")
                        ForEach(week.days) { day in
                            Text("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.meals.map { $0.foodItem?.name ?? $0.mealType }.joined(separator: ", "))")
                        }
                        Text(week.isArchived ? "This template will be archived." : "Saved templates do not change your dated plans until separately reviewed.")
                    }
                    Text(session.finished ? value.resolution == .accepted ? "Saved" : "Cancelled before saving" : value.submitted ? "Submitted review kept for recovery" : "Ready to save")
                    if value.submitted, !session.finished {
                        Button("Check saved status") { Task { await session.resolve(cancelPending: false, resolve) } }.frame(minHeight: 44)
                        Button("Cancel pending save", role: .destructive) { Task { await session.resolve(cancelPending: true, resolve) } }.frame(minHeight: 44)
                    }
                    if !value.submitted { Button("Discard review", role: .destructive) { finish() }.frame(minHeight: 44) }
                }
            }.appFormStyle()
            .navigationTitle("Review library save").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(session.isWorking) } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let error = session.errorMessage { Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution).fixedSize(horizontal: false, vertical: true) }
                    Button(session.finished ? "Done" : session.isWorking ? "Saving…" : "Save exact review") {
                        if session.finished { finish() } else { Task { await session.save(save) } }
                    }.buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isWorking || session.checkpoint == nil)
                }.padding().background(AppPalette.canvas).accessibilityElement(children: .contain)
            }
        }.interactiveDismissDisabled(session.isWorking)
    }
    private func finish() {
        let resolution = session.checkpoint?.resolution ?? .pending
        if session.finish() { onFinished(resolution); dismiss() }
    }
}

struct MealCompositionLibraryView: View {
    let didChoose: (PlannedMeal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [SavedMealComposition] = []
    @State private var editor: CompositionEditRequest?
    @State private var review: PlanningDocumentSaveSession<SavedMealComposition>?
    @State private var error: String?
    private let owner = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Save familiar food combinations with their amounts. Pantry stock stays unchanged.") }
                Button("Build a meal", systemImage: "plus") { editor = .init(value: nil) }.frame(minHeight: 44)
                    .accessibilityIdentifier("planner_build_composition")
                Button("Resume saved-meal review") {
                    review = PlanningDocumentSaveSession(userID: owner, scope: "meal-composition-library-save")
                }.frame(minHeight: 44)
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                ForEach(values.filter { !$0.isArchived }) { value in
                    VStack(alignment: .leading) {
                        Button { choose(value) } label: { Label(value.name, systemImage: "fork.knife").frame(minHeight: 44) }
                        Text("\(value.components.count) foods · \(Int(Nutrition.total(for: value.components).calories.rounded())) cal")
                        HStack {
                            Button("Edit") { editor = .init(value: value) }.frame(minHeight: 44)
                            Button("Archive", role: .destructive) { archive(value) }.frame(minHeight: 44)
                        }
                    }.buttonStyle(AppListButtonStyle()).accessibilityElement(children: .contain)
                }
                ForEach(values.filter(\.isArchived)) { value in
                    Button("Restore \(value.name)") { archive(value) }.frame(minHeight: 44)
                }
            }.appFormStyle().navigationTitle("Reusable meals").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { request in
            MealCompositionEditorView(original: request.value)
        }
        .sheet(item: $review, onDismiss: { Task { await load() } }) { session in
            compositionReview(session)
        }
    }
    private func choose(_ value: SavedMealComposition) {
        do {
            let food = try MealCompositionRules.food(value.snapshot)
            didChoose(PlannedMeal(mealType: "Dinner", foodItem: food, ingredients: value.components.map(MealCompositionRules.ingredientText)))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func archive(_ value: SavedMealComposition) {
        guard let owner else { return }; var updated = value
        updated.isArchived.toggle(); updated.revisionID = UUID().uuidString; updated.updatedAt = Date()
        review = PlanningDocumentSaveSession(userID: owner, scope: "meal-composition-library-save", proposal: .init(userID: owner, expected: value, updated: updated))
    }
    private func load() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        do { let items = try await DIContainer.shared.nutritionRepository.fetchSavedMealCompositions(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }; values = items
        } catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func compositionReview(_ session: PlanningDocumentSaveSession<SavedMealComposition>) -> some View {
        if let owner {
            PlanningDocumentReviewView(session: session,
                save: { try await DIContainer.shared.nutritionRepository.saveSavedMealComposition(userID: owner, proposal: $0) },
                resolve: { try await DIContainer.shared.nutritionRepository.resolveSavedMealComposition(userID: owner, proposal: $0, cancelPending: $1) },
                onFinished: { _ in Task { await load() } })
        }
    }
}
private struct CompositionEditRequest: Identifiable { let id = UUID(); let value: SavedMealComposition? }

struct MealCompositionEditorView: View {
    let original: SavedMealComposition?
    @State private var name: String
    @State private var foods: [FoodItem]
    @State private var searching = false
    @State private var review: PlanningDocumentSaveSession<SavedMealComposition>?
    @State private var error: String?
    @State private var editorFingerprint: String?
    @State private var requestedOperationID: UUID?
    @State private var requestedEditorFingerprint: String?
    @State private var creationID = UUID().uuidString
    @Environment(\.dismiss) private var dismiss
    private let owner = DIContainer.shared.authService.currentUserID
    init(original: SavedMealComposition?) {
        self.original = original; _name = State(initialValue: original?.name ?? ""); _foods = State(initialValue: original?.components ?? [])
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal name", text: $name).accessibilityIdentifier("composition_name")
                Section("Foods and actual amounts") {
                    ForEach(foods) { food in
                        HStack(spacing: AppSpacing.row) {
                            FoodGlyph(food.name, pointSize: 26).frame(width: 44, height: 44)
                                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(food.name).appTextRole(.control)
                                Text("\(food.servingSize) · \(Int(food.calories.rounded()).formatted()) cal")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button(role: .destructive) { foods.removeAll { $0.id == food.id }; keepDraft() } label: {
                                Image(systemName: "trash").foregroundStyle(AppPalette.critical)
                            }
                            .buttonStyle(AppIconButtonStyle(.plain))
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Remove \(food.name)")
                        }
                    }
                    Button("Add reviewed food", systemImage: "plus") { searching = true }.frame(minHeight: 44)
                }
            }.appFormStyle().navigationTitle("Build a reusable meal").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { keepDraft(); dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        if let error { Text(error).foregroundStyle(AppPalette.caution) }
                        Button("Review reusable meal") { prepare() }.buttonStyle(AppActionButtonStyle(.primary)).disabled(foods.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("composition_review")
                    }.padding().background(AppPalette.canvas)
                }
        }
        .task { restoreDraft() }
        .onChange(of: name) { _, _ in keepDraft() }
        .sheet(isPresented: $searching) {
            FoodSearchView(dailyLog: .constant(nil), onFoodItemSelected: { food in
                let parts = food.mealComposition?.components ?? [food]
                for part in parts { var copy = part; copy.id = UUID().uuidString; foods.append(copy) }
                keepDraft(); searching = false
            }, searchContext: "meal_composition", selectedMeal: "Dinner")
        }
        .sheet(item: $review) { session in
            if let owner {
                let resolvedOperationID = session.checkpoint?.proposal.operationID
                let resolvedEditorFingerprint = requestedEditorFingerprint
                PlanningDocumentReviewView(session: session,
                    save: { try await DIContainer.shared.nutritionRepository.saveSavedMealComposition(userID: owner, proposal: $0) },
                    resolve: { try await DIContainer.shared.nutritionRepository.resolveSavedMealComposition(userID: owner, proposal: $0, cancelPending: $1) },
                    onFinished: { resolution in
                        guard resolution == .accepted else {
                            error = "The library save was cancelled. Your meal draft is kept here."; review = nil; return
                        }
                        guard resolvedOperationID == requestedOperationID else {
                            error = "The earlier review is finished. Your different meal draft is still here."; review = nil; return
                        }
                        do {
                            let current = try EditorDraftStore().load(SavedMealComposition.self, userID: owner, scope: draftScope)?.value
                            guard try current.map(PlanFingerprint.make) == resolvedEditorFingerprint else {
                                error = "The reviewed meal is saved. A newer editor draft is kept here."; review = nil; return
                            }
                            try EditorDraftStore().remove(userID: owner, scope: draftScope)
                            dismiss()
                        } catch {
                            self.error = "The reviewed meal is saved. Its unreadable editor draft was preserved."; review = nil
                        }
                    })
            }
        }
    }
    private var draftScope: String { "meal-composition-editor-\(original?.id ?? "new")" }
    @discardableResult private func keepDraft() -> Bool {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return false }
        let value = SavedMealComposition(id: original?.id ?? creationID, name: name, components: foods)
        do {
            let current = try EditorDraftStore().load(SavedMealComposition.self, userID: owner, scope: draftScope)?.value
            guard try current.map(PlanFingerprint.make) == editorFingerprint else { throw MealPlanEditError.changed }
            try EditorDraftStore().save(value, userID: owner, scope: draftScope); editorFingerprint = try PlanFingerprint.make(value)
            return true
        } catch { self.error = "Your meal draft could not be kept; leave this editor open and retry."; return false }
    }
    private func restoreDraft() {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        if let draft = try? EditorDraftStore().load(SavedMealComposition.self, userID: owner, scope: draftScope)?.value {
            editorFingerprint = try? PlanFingerprint.make(draft); name = draft.name; foods = draft.components
            if original == nil, draft.id != "draft" { creationID = draft.id }
        }
    }
    private func prepare() {
        guard let owner else { return }
        var value = SavedMealComposition(id: original?.id ?? creationID, name: name, components: foods)
        value.revisionID = UUID().uuidString
        do {
            try value.validate(); guard keepDraft() else { return }
            let proposal = MealCompositionSaveProposal(userID: owner, expected: original, updated: value)
            requestedOperationID = proposal.operationID; requestedEditorFingerprint = editorFingerprint
            review = PlanningDocumentSaveSession(userID: owner, scope: "meal-composition-library-save", proposal: proposal)
        } catch { self.error = error.localizedDescription }
    }
}

struct SavedMealWeeksView: View {
    let currentDays: [MealPlanDay]
    let starting: Date
    let didChoose: (MealPlanWeekDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goals: GoalSettings
    @State private var values: [SavedMealWeekTemplate] = []
    @State private var name = ""
    @State private var selected: SavedMealWeekTemplate?
    @State private var start: Date
    @State private var scale = 1.0
    @State private var excluded = Set<String>()
    @State private var review: PlanningDocumentSaveSession<SavedMealWeekTemplate>?
    @State private var error: String?
    @State private var saveIndependent = false
    private let owner = DIContainer.shared.authService.currentUserID
    init(currentDays: [MealPlanDay], starting: Date, didChoose: @escaping (MealPlanWeekDraft) -> Void) {
        self.currentDays = currentDays; self.starting = starting; self.didChoose = didChoose; _start = State(initialValue: starting)
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Save this week") {
                    TextField("Week name", text: $name)
                    Toggle("Save as independent meals", isOn: $saveIndependent)
                    Text("Keep shared batches only when all linked dates are included. Independent meals need cooking again; pantry stock is never copied.").font(.caption)
                    Button("Review saved week") { prepareNew() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Resume week-library save") { review = PlanningDocumentSaveSession(userID: owner, scope: "meal-week-template-save") }
                }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                Section("Saved weeks") {
                    ForEach(values.filter { !$0.isArchived }.sorted { $0.favorite && !$1.favorite }) { value in
                        VStack(alignment: .leading) {
                            Button(value.name) { selected = value; excluded = [] }.frame(minHeight: 44)
                            Text("\(value.days.flatMap(\.meals).count) planned meals · saved portions").font(.caption)
                            HStack {
                                Button(value.favorite ? "Unfavorite" : "Favorite") { change(value, archive: false) }.frame(minHeight: 44)
                                Button("Archive", role: .destructive) { change(value, archive: true) }.frame(minHeight: 44)
                            }
                        }.buttonStyle(AppListButtonStyle()).accessibilityElement(children: .contain)
                    }
                    ForEach(values.filter(\.isArchived)) { value in Button("Restore \(value.name)") { change(value, archive: true) }.frame(minHeight: 44) }
                }
                if let selected {
                    Section("Review reuse · \(selected.name)") {
                        DatePicker("New first date", selection: $start, displayedComponents: .date)
                        Stepper("Cooking quantity ×\(scale.formatted())", value: $scale, in: 0.25...4, step: 0.25)
                        Text("Personal portions stay unchanged. Shared cooking quantities scale only after allocation checks. Existing destination meals remain until reviewed.")
                        ForEach(selected.days) { day in
                            ForEach(day.meals) { meal in
                                Toggle(meal.foodItem?.name ?? meal.mealType, isOn: Binding(get: { !excluded.contains(meal.id) }, set: { include in
                                    let related = Set(meal.cookingBatch?.allocations.map(\.mealID) ?? [meal.id])
                                    if include { excluded.subtract(related) } else { excluded.formUnion(related) }
                                }))
                            }
                        }
                        Button("Preview on new dates") { reuse(selected) }.frame(minHeight: 44).accessibilityIdentifier("planner_template_preview")
                    }
                }
            }.appFormStyle().navigationTitle("Saved meal weeks").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task { await load() }
        .sheet(item: $review, onDismiss: { Task { await load() } }) { session in
            if let owner {
                PlanningDocumentReviewView(session: session,
                    save: { try await DIContainer.shared.nutritionRepository.saveSavedMealWeekTemplate(userID: owner, proposal: $0) },
                    resolve: { try await DIContainer.shared.nutritionRepository.resolveSavedMealWeekTemplate(userID: owner, proposal: $0, cancelPending: $1) },
                    onFinished: { _ in Task { await load() } })
            }
        }
    }
    private func load() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        do { let result = try await DIContainer.shared.nutritionRepository.fetchSavedMealWeekTemplates(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }; values = result
        } catch { self.error = error.localizedDescription }
    }
    private func prepareNew() {
        guard let owner else { return }
        let dates = MealPlanEditingRules.week(containing: starting)
        let days = dates.map { date -> MealPlanDay in
            var day = currentDays.first { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? MealPlanEditingRules.emptyDay(date)
            if saveIndependent { day.meals = day.meals.map(MealPlanEditingRules.duplicate) }
            return day
        }
        let value = SavedMealWeekTemplate(name: name, days: days)
        do { try value.validate(); review = PlanningDocumentSaveSession(userID: owner, scope: "meal-week-template-save", proposal: .init(userID: owner, expected: nil, updated: value)) } catch { self.error = error.localizedDescription }
    }
    private func change(_ value: SavedMealWeekTemplate, archive: Bool) {
        guard let owner else { return }; var updated = value
        if archive { updated.isArchived.toggle() } else { updated.favorite.toggle() }
        updated.revisionID = UUID().uuidString; updated.updatedAt = Date()
        review = PlanningDocumentSaveSession(userID: owner, scope: "meal-week-template-save", proposal: .init(userID: owner, expected: value, updated: updated))
    }
    private func reuse(_ value: SavedMealWeekTemplate) {
        do {
            var draft = try MealWeekTemplateRules.draft(value, starting: start, excluding: excluded, householdScale: scale)
            guard let owner, DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
            var constraints = try EditorDraftStore().load(MealPlanConstraints.self, userID: owner, scope: "meal-planning-constraints")?.value
                ?? MealPlanConstraints(calories: goals.calories ?? 2_000, protein: goals.protein, carbs: goals.carbs, fats: goals.fats)
            constraints.calories = goals.calories ?? 2_000; constraints.protein = goals.protein; constraints.carbs = goals.carbs; constraints.fats = goals.fats
            draft.constraints = constraints
            didChoose(draft); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MealPlanHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: MealPlannerService
    @State private var values: [MealPlanChange] = []
    @State private var review: MealPlanWeekSaveSession?
    @State private var error: String?
    private let owner = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            List {
                Text("Undo a recorded change after reviewing it. Other meals stay in place; later edits may need another review.")
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                ForEach(values) { value in
                    VStack(alignment: .leading) {
                        Text(value.title).fontWeight(.semibold)
                        Text(value.before.map { $0.date.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")).font(.caption)
                        Button("Review Undo") { Task { await prepare(value) } }.frame(minHeight: 44)
                    }
                }

            }.appFormStyle().navigationTitle("Meal plan changes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            let pending = MealPlanWeekSaveSession(userID: owner, scope: "meal-plan-history-undo")
            if pending.checkpoint != nil { review = pending }
            await load()
        }
        .sheet(isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), onDismiss: { Task { await load() } }) {
            if let review { MealPlanOperationReviewView(session: review) { self.review = nil; Task { await load() } } }
        }
    }
    private func load() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        do { let result = try await DIContainer.shared.nutritionRepository.fetchMealPlanChangeHistory(userID: owner, limit: 100)
            guard DIContainer.shared.authService.currentUserID == owner else { return }; values = result
        } catch { self.error = error.localizedDescription }
    }
    private func prepare(_ value: MealPlanChange) async {
        guard let owner else { return }
        do {
            var current: [MealPlanDay] = []
            for day in value.after {
                let fetched = try await service.fetchBasePlanResult(for: day.date, userID: owner).get()
                current.append(fetched ?? MealPlanEditingRules.emptyDay(day.date))
            }
            let inverse = try MealPlanHistoryRules.inverse(value, current: current)
            let existing = MealPlanWeekSaveSession(userID: owner, scope: "meal-plan-history-undo")
            if existing.checkpoint != nil { review = existing; return }
            let session = MealPlanWeekSaveSession(userID: owner, draft: .init(days: inverse.after, title: inverse.title), scope: "meal-plan-history-undo")
            guard session.prepare(inverse) else { error = session.errorMessage; return }; review = session
        } catch { self.error = error.localizedDescription }
    }
}

struct PantryPhotoObservationView: View {
    @State private var draft: PantryPhotoObservationDraft
    @State private var recipes: [Recipe] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var idea: PantryIdeaRequest?
    @State private var newIngredient = ""
    @State private var stock: [PantryItem] = []
    @State private var stockEditor: ObservedStockRequest?
    @State private var expectedFingerprint: String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeService: RecipeService
    init(draft: PantryPhotoObservationDraft) {
        _draft = State(initialValue: draft); _recipes = State(initialValue: draft.recipeIdeas ?? [])
        _expectedFingerprint = State(initialValue: try? PlanFingerprint.make(draft))
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Confirm what is visible") {
                    Text("Check the ingredients seen in your photo. Quantities need your confirmation before pantry stock changes.")
                    ForEach(Array(draft.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        HStack {
                            TextField("Ingredient", text: Binding(get: { draft.ingredients.indices.contains(index) ? draft.ingredients[index] : "" }, set: { guard draft.ingredients.indices.contains(index) else { return }; draft.ingredients[index] = $0; invalidateIdeas(); keep() }))
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { draft.ingredients.remove(at: index); invalidateIdeas(); keep() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                            Button("Review stock", systemImage: "refrigerator") {
                                var item = PantryItem(name: ingredient, quantity: 0, unit: "item"); item.quantityUnknown = true
                                stockEditor = .init(item: item)
                            }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    HStack { TextField("Missed ingredient", text: $newIngredient); Button("Add") {
                        let text = newIngredient.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty, draft.ingredients.count < 40 { draft.ingredients.append(text); newIngredient = ""; invalidateIdeas(); keep() }
                    }.frame(minHeight: 44) }
                }
                Section("Destination") {
                    DatePicker("Meal date", selection: $draft.date, displayedComponents: .date).onChange(of: draft.date) { _, _ in keep() }
                    Picker("Meal", selection: $draft.mealName) { ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) } }
                        .onChange(of: draft.mealName) { _, _ in keep() }
                    Button(isLoading ? "Preparing ideas…" : "Confirm ingredients and create ideas") { Task { await generate() } }.disabled(isLoading || draft.ingredients.isEmpty).frame(minHeight: 44)
                        .accessibilityIdentifier("pantry_observation_confirm")
                }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                ForEach(Array(recipes.enumerated()), id: \.offset) { _, recipe in
                    Button { idea = .init(recipe: recipe, date: draft.date, meal: draft.mealName) } label: {
                        VStack(alignment: .leading) { Text(recipe.name); Text("Estimated recipe · review quantities and stock fit").font(.caption) }.frame(minHeight: 44)
                    }.disabled(isLoading)
                }
                Button("Discard observation", role: .destructive) {
                    guard DIContainer.shared.authService.currentUserID == draft.userID else { return }
                    do {
                        let current = try EditorDraftStore().load(PantryPhotoObservationDraft.self, userID: draft.userID, scope: "pantry-photo-observation")?.value
                        guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw MealPlanEditError.changed }
                        try EditorDraftStore().remove(userID: draft.userID, scope: "pantry-photo-observation"); dismiss()
                    } catch { self.error = "A newer observation was kept. Close and reopen before discarding." }
                }.frame(minHeight: 44)
            }.appFormStyle().navigationTitle("Pantry observation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { keep(); dismiss() } } }
        }
        .task {
            keep()
            do { let result = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: draft.userID)
                guard DIContainer.shared.authService.currentUserID == draft.userID else { return }; stock = result
            } catch { self.error = "Stock could not be refreshed. Ideas remain estimates until you reconnect and review availability." }
        }
        .sheet(item: $idea) { request in PantryRecipeIdeaReviewView(recipe: request.recipe, stock: stock, date: request.date, meal: request.meal) }
        .sheet(item: $stockEditor) { request in StockItemEditorView(name: request.item.name, newQuantityUnknown: true) }
    }
    private func keep() {
        guard DIContainer.shared.authService.currentUserID == draft.userID else { return }
        do {
            let current = try EditorDraftStore().load(PantryPhotoObservationDraft.self, userID: draft.userID, scope: "pantry-photo-observation")?.value
            guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw MealPlanEditError.changed }
            try EditorDraftStore().save(draft, userID: draft.userID, scope: "pantry-photo-observation")
            expectedFingerprint = try PlanFingerprint.make(draft)
        } catch { self.error = "This observation could not be kept. Keep it open and retry." }
    }
    private func invalidateIdeas() { recipes = []; draft.recipeIdeas = nil; draft.confirmed = false }
    private func generate() async {
        guard DIContainer.shared.authService.currentUserID == draft.userID else { return }
        do { try draft.validate() } catch { self.error = error.localizedDescription; return }
        draft.confirmed = true; keep(); isLoading = true; defer { isLoading = false }
        let requestedIngredients = draft.ingredients
        let result = await recipeService.createRecipesFromPantry(itemsString: draft.ingredients.map { "\($0) (quantity unknown in photo)" }.joined(separator: ", "), userID: draft.userID)
        guard DIContainer.shared.authService.currentUserID == draft.userID else { return }
        guard draft.ingredients == requestedIngredients else {
            error = "Ingredients changed while ideas were prepared. Your edits are kept; generate ideas for this version."; return
        }
        recipes = Array(PantryRecipeFitRules.ranked(result, stock: stock).prefix(6)); draft.recipeIdeas = recipes; keep(); if result.isEmpty { error = "No usable recipe drafts returned. Your observations and destination remain here." }
    }
}
private struct ObservedStockRequest: Identifiable { let id = UUID(); let item: PantryItem }
struct PantryIdeaRequest: Identifiable { let id = UUID(); let recipe: Recipe; let date: Date; let meal: String }

struct PantryRecipeIdeaReviewView: View {
    @State private var recipe: Recipe
    @State private var stock: [PantryItem]
    @State private var date: Date
    @State private var meal: String
    @State private var portions = 1.0
    @State private var exclusions = ""
    @State private var equipment = ""
    @State private var allowsShopping = true
    @State private var editor = false
    @State private var logRequest: PantryIdeaLogRequest?
    @State private var selectedLots: Set<UUID>
    @State private var stockError: String?
    @State private var didLoadStock = false
    @State private var stockSelectionTouched = false
    @State private var planned: PlannedMeal?
    @State private var error: String?
    @EnvironmentObject private var planner: MealPlannerService
    @EnvironmentObject private var pantry: PantryService
    @Environment(\.dismiss) private var dismiss
    private let owner = DIContainer.shared.authService.currentUserID
    init(recipe: Recipe, stock: [PantryItem], date: Date, meal: String) {
        _recipe = State(initialValue: recipe); _stock = State(initialValue: stock); _selectedLots = State(initialValue: Set(stock.map(\.id))); _date = State(initialValue: date); _meal = State(initialValue: meal)
    }
    private var fit: PantryRecipeFit? { try? PantryRecipeFitRules.review(recipe: recipe, servings: portions, stock: stockError == nil ? stock.filter { selectedLots.contains($0.id) } : [],
        exclusions: exclusions.components(separatedBy: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
        equipment: equipment.components(separatedBy: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) }
    private var canUse: Bool { fit.map { $0.blockers.isEmpty && (allowsShopping || $0.canUseWithoutShopping) } ?? false }
    var body: some View {
        NavigationStack {
            List {
                Section(recipe.name) {
                    Text("Estimated recipe · review your portion and available ingredients. Stock is not reserved or deducted here.")
                    DatePicker("Destination date", selection: $date, displayedComponents: .date)
                    Picker("Meal", selection: $meal) { ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) } }
                    Stepper("\(portions.formatted()) servings", value: $portions, in: 0.25...8, step: 0.25)
                    TextField("Excluded ingredients, comma separated", text: $exclusions)
                    TextField("Available equipment, comma separated", text: $equipment)
                    Toggle("Allow explicitly listed shopping additions", isOn: $allowsShopping)
                }
                if let stockError { Text(stockError).foregroundStyle(AppPalette.caution) }
                Button("Refresh stock review") { Task { await refreshStock() } }.frame(minHeight: 44)
                Section("Stock lots considered") {
                    ForEach(stock) { lot in
                        Toggle("\(lot.name) · \(lot.quantityVerified == true && lot.quantityUnknown != true ? "\(lot.quantity.formatted()) \(lot.unit)" : "amount unconfirmed")", isOn: Binding(get: { selectedLots.contains(lot.id) }, set: { stockSelectionTouched = true; if $0 { selectedLots.insert(lot.id) } else { selectedLots.remove(lot.id) } }))
                    }
                }
                if let fit {
                    ForEach(fit.rows) { row in
                        VStack(alignment: .leading) {
                            Text(row.ingredient).fontWeight(.semibold)
                            Text(row.required.map { "Need \($0.formatted()) \(row.unit) · covered \(row.available.formatted())" } ?? "Amount unconfirmed")
                            Text(row.message).foregroundStyle(.secondary)
                            ForEach(stock.filter { row.lotIDs.contains($0.id) }) { Text("Lot: \($0.name) · \($0.location ?? "storage unspecified")").font(.caption) }
                        }
                    }
                    ForEach(fit.blockers, id: \.self) { Text($0).foregroundStyle(AppPalette.caution) }
                    ForEach(fit.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                } else { Text("Confirm recipe yield and nutrition before planning or logging this draft.").foregroundStyle(AppPalette.caution) }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                Button("Review / save recipe") { editor = true }.frame(minHeight: 44)
                Button("Plan reviewed amount") { preparePlan() }.disabled(!canUse).frame(minHeight: 44)
                Button("Review food log") { Task {
                    guard await refreshStock(), canUse else { return }
                    logRequest = .init(recipe: recipe, date: date, meal: meal, portions: portions)
                } }.disabled(!canUse || date > Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_399)).frame(minHeight: 44)
            }.appFormStyle().navigationTitle("Review pantry idea").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            if let owner { pantry.startListening(userID: owner) }
            _ = await refreshStock()
        }
        .onReceive(pantry.$pantryItems) { items in
            guard let owner, pantry.activeUserID == owner, DIContainer.shared.authService.currentUserID == owner else { return }
            stock = items; stockError = pantry.errorMessage
        }
        .onReceive(pantry.$errorMessage) { message in
            guard let owner, pantry.activeUserID == owner, DIContainer.shared.authService.currentUserID == owner else { return }; stockError = message
        }
        .sheet(isPresented: $editor) { CreateRecipeView(initialDraft: recipe) { recipe = $0 } }
        .sheet(item: $logRequest) { request in RecipeLoggingView(recipe: request.recipe, dailyLog: .constant(nil), date: request.date, mealName: request.meal == "Snack" ? "Snacks" : request.meal, initialSelection: .init(unit: .servings, amount: request.portions)) {} }
        .sheet(item: $planned) { value in
            PlannedMealEditSheet(meal: value, date: date, title: "Review recipe plan") { updated in
                guard let owner, DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
                let freshStock = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
                let freshFit = try PantryRecipeFitRules.review(recipe: recipe, servings: portions, stock: freshStock.filter { selectedLots.contains($0.id) },
                    exclusions: exclusions.components(separatedBy: ",").filter { !$0.isEmpty }, equipment: equipment.components(separatedBy: ",").filter { !$0.isEmpty })
                guard freshFit.blockers.isEmpty, allowsShopping || freshFit.canUseWithoutShopping else { throw InventoryError.changed }
                let current = try await planner.fetchBasePlanResult(for: date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(date)
                var after = current; after.meals.append(MealPlanEditingRules.duplicate(updated))
                try await planner.applyPlanChange(.init(title: "Pantry recipe planned", before: [current], after: [after]), for: owner)
            }
        }
    }
    @discardableResult private func refreshStock() async -> Bool {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return false }
        do {
            let fresh = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return false }
            if !didLoadStock, !stockSelectionTouched, selectedLots.isEmpty { selectedLots = Set(fresh.map(\.id)) }
            didLoadStock = true
            stock = fresh; stockError = nil; return true
        } catch {
            stockError = "Stock could not be refreshed. Availability is not assumed; reconnect before accepting this stock review."; return false
        }
    }
    private func preparePlan() {
        do {
            let selection = RecipePortionSelection(unit: .servings, amount: portions)
            planned = PlannedMeal(mealType: meal, recipeID: recipe.id, foodItem: try RecipePortionRules.foodItem(for: recipe, selection: selection),
                ingredients: try RecipePortionRules.ingredients(for: recipe, selection: selection), instructions: recipe.instructions.joined(separator: "\n"))
        } catch { self.error = error.localizedDescription }
    }
}

private struct PantryIdeaLogRequest: Identifiable { let id = UUID(); let recipe: Recipe; let date: Date; let meal: String; let portions: Double }

struct ActualPlannedFoodReviewView: View {
    let original: FoodItem
    let date: Date
    let onSave: (FoodItem) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var foods: [FoodItem]
    @State private var amounts: [String: Double] = [:]
    @State private var included: Set<String>
    @State private var replacingID: String?
    @State private var error: String?
    init(food: FoodItem, date: Date, onSave: @escaping (FoodItem) -> Bool) {
        original = food; self.date = date; self.onSave = onSave
        let parts = food.mealComposition?.components ?? [food]
        _foods = State(initialValue: parts); _included = State(initialValue: Set(parts.map(\.id)))
    }
    private var actual: [FoodItem] { foods.filter { included.contains($0.id) }.compactMap { FoodRepeatRules.adjusting($0, by: amounts[$0.id] ?? 1) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(original.name).fontWeight(.semibold)
                    Text(date.formatted(date: .complete, time: .omitted))
                    Text("Review what you actually ate. Skipped foods and substitutions change this diary entry only; the original plan and physical stock stay unchanged.")
                }
                ForEach(foods) { food in
                    Section(food.name) {
                        Toggle("I ate this component", isOn: Binding(get: { included.contains(food.id) }, set: { if $0 { included.insert(food.id) } else { included.remove(food.id) } }))
                        Stepper("Amount ×\((amounts[food.id] ?? 1).formatted())", value: Binding(get: { amounts[food.id] ?? 1 }, set: { amounts[food.id] = $0 }), in: 0.25...8, step: 0.25)
                            .disabled(!included.contains(food.id))
                        Text("Original amount: \(food.servingSize)").foregroundStyle(.secondary)
                        Button("Substitute this food") { replacingID = food.id }.frame(minHeight: 44)
                    }
                }
                Text("Actual total · \(Int(Nutrition.total(for: actual).calories.rounded())) cal")
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
            }.appFormStyle().navigationTitle("Ate as planned?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Button("Keep actual portions") { save() }.buttonStyle(AppActionButtonStyle(.primary)).padding().background(AppPalette.canvas).disabled(actual.isEmpty)
                        .accessibilityIdentifier("planned_actual_keep")
                }
        }
        .sheet(isPresented: Binding(get: { replacingID != nil }, set: { if !$0 { replacingID = nil } })) {
            FoodSearchView(dailyLog: .constant(nil), onFoodItemSelected: { replacement in
                guard let id = replacingID, let index = foods.firstIndex(where: { $0.id == id }) else { return }
                var value = replacement; value.id = id; foods[index] = value; amounts[id] = 1; included.insert(id); replacingID = nil
            }, searchContext: "planned_actual_substitution", selectedMeal: "Dinner")
        }
    }
    private func save() {
        do {
            let snapshot = MealCompositionSnapshot(title: original.name, components: actual, sourceID: original.mealComposition?.sourceID ?? original.id)
            var value = try MealCompositionRules.food(snapshot, entryID: original.id); value.timestamp = original.timestamp
            value.sourceMetadata?.notes = "Actual components reviewed independently from the original plan."
            if onSave(value) { dismiss() } else { error = "This review could not be updated. Its last accepted draft is still kept." }
        } catch { self.error = error.localizedDescription }
    }
}

struct MealAlternativesView: View {
    let day: MealPlanDay
    let original: PlannedMeal
    let didFinish: () -> Void
    @EnvironmentObject private var goals: GoalSettings
    @EnvironmentObject private var recipes: RecipeService
    @EnvironmentObject private var planner: MealPlannerService
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [MealAlternativeCandidate] = []
    @State private var error: String?
    private struct EditRequest: Identifiable { let id = UUID(); let meal: PlannedMeal }
    @State private var review: EditRequest?
    @State private var constraints: MealPlanConstraints?
    @State private var week: [MealPlanDay] = []
    @State private var pending: MealPlanWeekSaveSession?
    @State private var showingOperation = false
    @State private var isRequestingIdea = false
    @State private var snackPreferences = ""
    private let owner = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            List {
                Text("Ideas that fit your remaining day and saved restrictions. Review a swap before your plan changes.")
                if MealPlanEditingRules.canonicalSlot(original.mealType) == "Snack" { TextField("Preferred snacks", text: $snackPreferences) }
                Button(isRequestingIdea ? "Requesting idea…" : "Ask Maia for another idea", systemImage: "sparkles") { Task { await requestIdea() } }
                    .frame(minHeight: 44).disabled(isRequestingIdea || constraints == nil || (original.cookingBatch?.allocations.count ?? 0) > 1)
                if choices.isEmpty { Text("No supported alternatives yet. Add recipes with confirmed yield and current ingredient/equipment reviews, or use direct Swap.") }
                ForEach(choices) { candidate in
                    Section(candidate.meal.foodItem?.name ?? "Alternative") {
                        Text("\(Int(candidate.meal.plannedFood?.calories ?? 0)) cal · \(candidate.meal.portions.formatted()) recipe servings")
                        Text("Day difference · \(Int(candidate.calorieDifference.rounded())) cal")
                        ForEach(candidate.issues) { Text($0.message).foregroundStyle($0.blocking ? AppPalette.caution : .secondary) }
                        Button("Review this alternative") { review = .init(meal: candidate.meal) }.frame(minHeight: 44)
                    }
                }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
            }.appFormStyle().navigationTitle("Meal alternatives").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            guard let owner else { return }; await recipes.fetchUserRecipes()
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            var c = (try? EditorDraftStore().load(MealPlanConstraints.self, userID: owner, scope: "meal-planning-constraints")?.value)
                ?? MealPlanConstraints(calories: goals.calories ?? 2_000, protein: goals.protein, carbs: goals.carbs, fats: goals.fats)
            c.calories = goals.calories ?? 2_000; c.protein = goals.protein; c.carbs = goals.carbs; c.fats = goals.fats
            constraints = c
            do {
                for date in MealPlanEditingRules.week(containing: day.date) {
                    week.append(try await planner.fetchBasePlanResult(for: date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(date))
                }
            } catch { self.error = "The whole week could not be loaded. Weekly budget checks remain unavailable." }
            choices = MealAlternativeRules.candidates(recipes: recipes.userRecipes, day: day, replacing: original, constraints: c, week: week)
        }
        .sheet(item: $review, onDismiss: { if pending != nil { showingOperation = true } }) { request in
            PlannedMealEditSheet(meal: request.meal, date: day.date, title: "Review alternative") { updated in
                guard let constraints, DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
                let checked = MealAlternativeRules.review(meal: updated, day: day, replacing: original, constraints: constraints, week: week)
                guard checked.canUse else { throw MealPlanConstraintError.infeasible(checked.issues.filter(\.blocking).map(\.message)) }
                guard let owner else { throw MealPlanEditError.accountChanged }
                let existing = MealPlanWeekSaveSession(userID: owner, scope: "meal-alternative-review")
                if existing.checkpoint != nil { pending = existing; return }
                var afterDay = day; afterDay.meals = day.meals.map { $0.id == original.id ? updated : $0 }
                let before = constraints.weeklyBudget != nil ? week : [day]
                let after = before.map { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) ? afterDay : $0 }
                let change = MealPlanChange(title: "Replace \(original.foodItem?.name ?? original.mealType)", before: before, after: after)
                let session = MealPlanWeekSaveSession(userID: owner, draft: .init(days: after, title: change.title), scope: "meal-alternative-review")
                guard session.prepare(change) else { throw MealPlanEditError.changed }; pending = session
            }
        }
        .sheet(isPresented: $showingOperation) {
            if let pending { MealPlanOperationReviewView(session: pending) { self.pending = nil; didFinish(); dismiss() } }
        }
    }
    private func requestIdea() async {
        guard let owner, let constraints, DIContainer.shared.authService.currentUserID == owner else { return }
        isRequestingIdea = true; defer { isRequestingIdea = false }
        let snacks = snackPreferences.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard var meal = await planner.regenerateSingleMeal(for: day, mealToReplace: original, goals: goals,
            preferredFoods: goals.suggestionProteins + goals.suggestionCarbs + goals.suggestionVeggies,
            preferredCuisines: goals.suggestionCuisines, preferredSnacks: snacks, userID: owner) else {
            error = "Maia did not return a usable alternative. Your saved choices remain available."; return
        }
        guard DIContainer.shared.authService.currentUserID == owner else { return }
        meal.id = original.id; meal.mealType = original.mealType
        if let quantity = original.cookingBatch?.totalPortions {
            do { meal = try MealPlanCookingRules.configuring(meal, date: day.date, cookingPortions: max(quantity, meal.portions)) } catch { self.error = error.localizedDescription; return }
        }
        choices.insert(MealAlternativeRules.review(meal: meal, day: day, replacing: original, constraints: constraints, week: week), at: 0)
    }
}

struct MealPlanOperationReviewView: View {
    @ObservedObject var session: MealPlanWeekSaveSession
    let onFinished: () -> Void
    @EnvironmentObject private var planner: MealPlannerService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let value = session.checkpoint {
                    Text(value.draft.title).appTextRole(.sectionTitle)
                    Text("Review the meals that will change. Your food diary stays intact.")
                    ForEach(value.change?.after ?? []) { day in
                        Section(day.date.formatted(date: .complete, time: .omitted)) {
                            let before = value.change?.before.first { $0.id == day.id }
                            Text("\(before?.meals.count ?? 0) → \(day.meals.count) planned meals")
                            ForEach((before?.meals ?? []).filter { old in !day.meals.contains { $0.id == old.id } }) { old in
                                Text("Remove \(old.foodItem?.name ?? old.mealType)").foregroundStyle(AppPalette.caution)
                            }
                            ForEach(day.meals) { meal in
                                Text("\(meal.foodItem?.name ?? meal.mealType) · \(meal.portions.formatted()) original portions")
                                if let batch = MealPlanCookingRules.summary(for: meal) { Text(batch).font(.caption) }
                            }
                        }
                    }
                    if value.submitted, !value.accepted, !value.cancelled {
                        Button("Check saved status") { Task { await session.resolve(using: DIContainer.shared.nutritionRepository) } }.frame(minHeight: 44)
                        Button("Cancel pending Undo") { Task { await session.resolve(using: DIContainer.shared.nutritionRepository, cancelPending: true) } }.frame(minHeight: 44)
                    }
                }
            }.appFormStyle().navigationTitle("Review plan change").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(session.isWorking) } }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading) {
                        if let error = session.errorMessage { Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
                        Button(session.isWorking ? "Saving…" : session.checkpoint?.accepted == true || session.checkpoint?.cancelled == true ? "Done" : "Apply reviewed change") {
                            if session.checkpoint?.accepted == true || session.checkpoint?.cancelled == true {
                                if session.closeResolvedOrUnsubmitted() { onFinished(); dismiss() }
                            } else { Task { _ = await session.save(using: planner) } }
                        }.buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isWorking || session.checkpoint == nil)
                    }.padding().background(AppPalette.canvas).accessibilityElement(children: .contain)
                }
        }.interactiveDismissDisabled(session.isWorking)
    }
}

struct MealPlannerDateJumpView: View {
    @State private var date: Date
    let onChoose: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    init(date: Date, onChoose: @escaping (Date) -> Void) { _date = State(initialValue: date); self.onChoose = onChoose }
    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Plan date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).padding()
            }.navigationTitle("Choose plan date").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Choose") { onChoose(Calendar.current.startOfDay(for: date)); dismiss() } }
                }
        }
    }
}
