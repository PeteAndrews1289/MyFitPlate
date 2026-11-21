import MyFitPlateCore
import SwiftUI

struct LibraryMutationStatusView: View {
    @ObservedObject var session: LibraryMutationSession
    var onChanged: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if let pending = session.pending {
                Text(pending.title).appTextRole(.control)
                Text("Your review is kept here. Check status to confirm it saved.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                switch pending {
                case .recipes(let value): Text(value.before.map(\.name).joined(separator: ", ")).appTextRole(.secondary)
                case .foods(let value): Text(value.before.map(\.name).joined(separator: ", ")).appTextRole(.secondary)
                }
                Button(session.isWorking ? "Saving…" : "Retry library change") { perform { await session.submit(using: $0) } }
                    .buttonStyle(AppActionButtonStyle(.primary)).frame(minHeight: 44)
                    .accessibilityIdentifier("library_pending_retry")
                Button("Check status") { perform { await session.resolve(using: $0, cancelPending: false) } }
                    .frame(minHeight: 44).accessibilityIdentifier("library_pending_status")
                Button("Cancel unaccepted change", role: .destructive) { perform { await session.resolve(using: $0, cancelPending: true) } }
                    .frame(minHeight: 44).accessibilityIdentifier("library_pending_cancel")
            }
            if let error = session.errorMessage {
                Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("library_maintenance_error")
            }
            if session.pending == nil, let outcome = session.lastOutcome {
                Text(outcome).appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .disabled(session.isWorking)
        .accessibilityElement(children: .contain).accessibilityIdentifier("library_pending_review")
    }
    private func perform(_ work: @escaping (NutritionRepositoryProtocol) async -> Void) {
        Task { @MainActor in
            guard let repository = DIContainer.shared.nutritionRepository else { return }
            await work(repository); onChanged()
        }
    }
}

struct LibraryMaintenanceHistoryView: View {
    @ObservedObject var session: LibraryMutationSession
    var onChanged: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Up to \(session.historyLimit) recent changes per library. Undo checks for later edits before restoring anything. History syncs with your account.").foregroundStyle(.secondary) }
                if session.pending != nil || session.errorMessage != nil { Section { LibraryMutationStatusView(session: session, onChanged: onChanged) } }
                if session.checkpoint.history.isEmpty { Text("No accepted library changes on this device yet.").foregroundStyle(.secondary) }
                ForEach(session.checkpoint.history.reversed()) { entry in
                    Section {
                        Text(entry.operation.title).appTextRole(.control)
                        Text(entry.acceptedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Accepted account record · time not included in this page").foregroundStyle(.secondary)
                        if entry.undoneBy != nil { Text("Undone").foregroundStyle(.secondary) } else {
                            Button("Review Undo") {
                                guard session.undo(entry) else { return }
                            }.frame(minHeight: 44).disabled(session.isWorking)
                                .accessibilityIdentifier("library_history_undo_\(entry.id)")
                        }
                    }
                }
                if session.isLoadingHistory { ProgressView("Loading account changes") }
                if session.hasMoreHistory {
                    Button("Load more recent changes") { loadHistory(limit: session.historyLimit + 20) }.frame(minHeight: 44)
                }
                if session.historyLimit >= 200 { Text("Showing the supported 200 recent changes per library.").foregroundStyle(.secondary) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Library changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { loadHistory(limit: session.historyLimit) }
            .refreshable { await session.loadHistory(using: DIContainer.shared.nutritionRepository, limit: session.historyLimit) }
        }
    }
    private func loadHistory(limit: Int) { Task { await session.loadHistory(using: DIContainer.shared.nutritionRepository, limit: limit) } }
}

struct RecipeMetadataEditor: View {
    let recipe: Recipe
    @ObservedObject var session: LibraryMutationSession
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var favorite: Bool
    @State private var tags: String
    @State private var error: String?
    @State private var submittedID: UUID?
    init(recipe: Recipe, session: LibraryMutationSession, onSaved: @escaping () -> Void) {
        self.recipe = recipe; self.session = session; self.onSaved = onSaved
        _favorite = State(initialValue: recipe.libraryMetadata?.favorite ?? false)
        _tags = State(initialValue: (recipe.libraryMetadata?.tags ?? []).joined(separator: ", "))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(recipe.name) {
                    Toggle("Favorite", isOn: $favorite)
                    TextField("Tags, separated by commas", text: $tags)
                        .accessibilityIdentifier("recipe_library_tags")
                    Text("Try Breakfast, Quick or Vegetarian. Tags organize your library; they do not verify ingredients or change nutrition.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }.disabled(submittedID != nil)
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                if submittedID != nil { LibraryMutationStatusView(session: session, onChanged: finishIfAccepted) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("recipe_library_metadata")
            .navigationTitle("Organize recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Save organization", action: save).buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(submittedID != nil || session.isWorking).padding(AppSpacing.screenHorizontal)
                    .background(AppPalette.canvas).accessibilityIdentifier("recipe_library_metadata_save")
            }
        }
    }
    private func save() {
        do {
            var metadata = recipe.libraryMetadata ?? RecipeLibraryMetadata()
            metadata.favorite = favorite
            metadata.tags = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            let mutation = try RecipeLibraryRules.updating(recipe, metadata: metadata, title: "Organize recipe")
            guard session.prepare(.recipes(mutation)) else { return }
            submittedID = mutation.id
            Task { await session.submit(using: DIContainer.shared.nutritionRepository); finishIfAccepted() }
        } catch { self.error = error.localizedDescription }
    }
    private func finishIfAccepted() {
        guard let submittedID, session.checkpoint.history.contains(where: { $0.id == submittedID }) else { return }
        onSaved(); dismiss()
    }
}

struct RecipeDuplicateReview: View {
    let group: RecipeDuplicateGroup
    @ObservedObject var session: LibraryMutationSession
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keeperID: String
    @State private var acknowledged = false
    @State private var submittedID: UUID?
    @State private var error: String?
    init(group: RecipeDuplicateGroup, session: LibraryMutationSession, onSaved: @escaping () -> Void) {
        self.group = group; self.session = session; self.onSaved = onSaved
        _keeperID = State(initialValue: group.recipes.first?.id ?? "")
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(group.exact ? "These copies have the same recipe content." : "These names match, but recipe content differs. Compare portions, ingredients and source before choosing a keeper.")
                    Text("Other copies are archived with their complete content. Existing plans and food logs retain their snapshots. Undo is kept in Library changes.").foregroundStyle(.secondary)
                }
                ForEach(group.recipes) { recipe in
                    Section {
                        Button { keeperID = recipe.id ?? "" } label: {
                            Label(recipe.name, systemImage: keeperID == recipe.id ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight: 44).disabled(submittedID != nil)
                        Text(recipe.nutritionBasisLabel).foregroundStyle(.secondary)
                        Text("\(recipe.nutritionPerPortion.calories.formatted()) calories · \(recipe.servings?.formatted() ?? "Unconfirmed") servings")
                        Text(RecipePortionRules.originalIngredientLines(for: recipe).joined(separator: "\n")).appTextRole(.secondary)
                        if let source = recipe.importProvenance?.sourceURL { Text(source).appTextRole(.caption) }
                    }
                }
                Section { Toggle("I reviewed the differences and want this keeper", isOn: $acknowledged).disabled(submittedID != nil) }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                if submittedID != nil { LibraryMutationStatusView(session: session, onChanged: finishIfAccepted) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("recipe_duplicate_review")
            .navigationTitle("Review recipe copies").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep separate") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Keep selected recipe and archive copies", action: merge)
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(!acknowledged || submittedID != nil || session.isWorking)
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("recipe_duplicate_merge")
            }
        }
    }
    private func merge() {
        do {
            let mutation = try RecipeLibraryRules.merging(group.recipes, keeping: keeperID)
            guard session.prepare(.recipes(mutation)) else { return }
            submittedID = mutation.id
            Task { await session.submit(using: DIContainer.shared.nutritionRepository); finishIfAccepted() }
        } catch { self.error = error.localizedDescription }
    }
    private func finishIfAccepted() {
        guard let submittedID, session.checkpoint.history.contains(where: { $0.id == submittedID }) else { return }
        onSaved(); dismiss()
    }
}

struct SavedFoodMergeReviewView: View {
    let foods: [FoodItem]
    @ObservedObject var session: LibraryMutationSession
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keeperID: String
    @State private var reviewed = false
    @State private var submittedID: UUID?
    @State private var error: String?
    init(group: MyFoodsDuplicateGroup, session: LibraryMutationSession, onChanged: @escaping () -> Void) {
        foods = [group.keeper.item] + group.duplicates.map(\.item)
        self.session = session; self.onChanged = onChanged
        _keeperID = State(initialValue: group.keeper.id)
    }
    private var compatibleBarcodes: Bool {
        Set(foods.map { BarcodeCorrectionRules.normalizedBarcode($0.sourceMetadata?.barcode ?? "") }.filter { !$0.isEmpty }).count <= 1
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(MyFoodsLibraryRules.areExactDuplicates(foods) ? "The quantities, reported nutrients and source evidence match. Choose the copy to keep."
                        : "These names match; the quantities, reported nutrition or source versions differ. Compare every copy and choose deliberately.")
                    Text("Choose the personal copy to keep. Removed copies are retained for Undo; your diary stays unchanged.").foregroundStyle(.secondary)
                    Text("A shared barcode follows the copy you keep. Merging does not improve its nutrition evidence.").appTextRole(.secondary).foregroundStyle(.secondary)
                    if !compatibleBarcodes { Text("Different product barcodes identify different products and cannot be merged here.").foregroundStyle(AppPalette.caution) }
                }
                ForEach(foods) { food in
                    Section {
                        Button { keeperID = food.id } label: { Label(food.name, systemImage: keeperID == food.id ? "checkmark.circle.fill" : "circle") }
                            .frame(minHeight: 44).disabled(submittedID != nil)
                            .accessibilityIdentifier("saved_food_keeper_\(food.id)")
                        Text(food.sourceMetadata?.brandName ?? "Brand not reported").foregroundStyle(.secondary)
                        Text("\(food.servingSize) · \(food.calories.formatted()) cal · P \(food.protein.formatted()) g · C \(food.carbs.formatted()) g · F \(food.fats.formatted()) g")
                        Text("Barcode: \(food.sourceMetadata?.barcode ?? "None")").appTextRole(.caption)
                        Text(food.sourceMetadata?.sourceName ?? "Source not confirmed").appTextRole(.caption).foregroundStyle(.secondary)
                        if let version = food.sourceMetadata?.sourceUpdatedAt {
                            Text("Source version: \(version.formatted(date: .abbreviated, time: .shortened))").appTextRole(.caption)
                        }
                    }
                }
                Section { Toggle("I've checked the keeper, amounts and source differences", isOn: $reviewed).disabled(submittedID != nil) }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                if submittedID != nil { LibraryMutationStatusView(session: session, onChanged: finishIfAccepted) }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("saved_food_merge_review")
            .navigationTitle("Review saved copies").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Keep separate", action: keepSeparate).disabled(submittedID != nil) } }
            .safeAreaInset(edge: .bottom) {
                Button("Keep selected copy and merge others", action: merge).buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!compatibleBarcodes || !reviewed || submittedID != nil || session.isWorking)
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("saved_food_merge_apply")
            }
        }
    }
    private func keepSeparate() {
        do {
            try SavedFoodDuplicateDecisionStore(userID: session.userID).keepSeparate(foods)
            onChanged(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func merge() {
        do {
            let mutation = try SavedFoodLibraryMutation.merge(foods, keeping: keeperID)
            guard session.prepare(.foods(mutation)) else { return }
            submittedID = mutation.id
            Task { await session.submit(using: DIContainer.shared.nutritionRepository); finishIfAccepted() }
        } catch { self.error = error.localizedDescription }
    }
    private func finishIfAccepted() {
        guard let submittedID, session.checkpoint.history.contains(where: { $0.id == submittedID }) else { return }
        onChanged(); dismiss()
    }
}
