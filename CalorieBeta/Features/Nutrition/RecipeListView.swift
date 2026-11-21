import MyFitPlateCore
import SwiftUI

struct RecipeListView: View {
    @EnvironmentObject private var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreateRecipeSheet = false
    @State private var pendingDeletion: Recipe?
    @State private var searchText = ""
    @State private var filter: RecipeLibraryFilter = .all
    @State private var editingMetadata: Recipe?
    @State private var reviewingDuplicates: RecipeDuplicateGroup?
    @State private var showingHistory = false
    @State private var restoringVersion: RecipeVersionRestoreSession?
    @State private var libraryRecipes: [Recipe] = []
    @State private var loadedLibrary = false
    @State private var libraryLoading = false
    @State private var libraryError: String?
    @State private var libraryLoadID = UUID()
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    @StateObject private var maintenance = LibraryMutationSession(userID: DIContainer.shared.authService.currentUserID)

    private var allRecipes: [Recipe] { loadedLibrary ? libraryRecipes : recipeService.userRecipes }

    private var filteredRecipes: [Recipe] {
        RecipeLibraryRules.filtered(allRecipes, query: searchText, filter: filter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if (recipeService.isLoading || libraryLoading) && allRecipes.isEmpty {
                    loadingState
                } else if allRecipes.isEmpty && libraryError == nil {
                    emptyState
                } else {
                    recipeLibrary
                }
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("My Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Recipes, ingredients, tags or source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Menu {
                            Button("Library changes") { showingHistory = true }
                            Button("Resume version restore") {
                                restoringVersion = RecipeVersionRestoreSession(userID: DIContainer.shared.authService.currentUserID)
                            }.accessibilityIdentifier("recipe_library_resume_version")
                            ForEach(RecipeLibraryRules.duplicateGroups(allRecipes)) { group in
                                Button("Review \(group.recipes.first?.name ?? "recipe") copies") { reviewingDuplicates = group }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Recipe library tools")
                        Button { showingCreateRecipeSheet = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Create recipe")
                    }
                }
            }
            .refreshable {
                await loadLibrary()
            }
            .task {
                restoreCache()
                await loadLibrary()
            }
            .onChange(of: maintenance.checkpoint.history.map(\.id)) { _, _ in refreshRecipes() }
        }
        .sheet(isPresented: $showingCreateRecipeSheet, onDismiss: refreshRecipes) {
            CreateRecipeView()
        }
        .sheet(item: $editingMetadata, onDismiss: refreshRecipes) { recipe in
            RecipeMetadataEditor(recipe: recipe, session: maintenance, onSaved: refreshRecipes)
        }
        .sheet(item: $reviewingDuplicates, onDismiss: refreshRecipes) { group in
            RecipeDuplicateReview(group: group, session: maintenance, onSaved: refreshRecipes)
        }
        .sheet(item: $restoringVersion, onDismiss: refreshRecipes) { session in
            RecipeVersionRestoreReviewView(session: session, onFinished: refreshRecipes)
        }
        .sheet(isPresented: $showingHistory, onDismiss: refreshRecipes) {
            LibraryMaintenanceHistoryView(session: maintenance, onChanged: refreshRecipes)
        }
        .alert("Archive recipe?", isPresented: deletionAlertIsPresented) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Archive") {
                guard let recipe = pendingDeletion else { return }
                pendingDeletion = nil
                archiveRecipe(recipe)
            }
        } message: {
            Text("\(pendingDeletion?.name ?? "The recipe") moves to Archived. Its content, existing plans and logged foods stay available. Restore it from the Archived filter or Library changes.")
        }
    }

    private var recipeLibrary: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                collectionHeader
                if let libraryError {
                    Text(libraryError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("recipe_library_load_error")
                    Button("Retry loading recipes") { refreshRecipes() }.frame(minHeight: 44)
                }
                if maintenance.pending != nil || maintenance.errorMessage != nil || maintenance.lastOutcome != nil {
                    LibraryMutationStatusView(session: maintenance, onChanged: refreshRecipes).appSurface(.quiet)
                }
                if let latest = maintenance.checkpoint.history.last, latest.undoneBy == nil, maintenance.pending == nil {
                    Button("Review Undo: \(latest.operation.title)") {
                        _ = maintenance.undo(latest)
                    }.frame(minHeight: 44).accessibilityIdentifier("recipe_library_undo")
                }

                if filteredRecipes.isEmpty {
                    noMatchesState
                } else {
                    savedRecipesSection
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("recipe_library")
    }

    private var savedRecipesSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredRecipes.enumerated()), id: \.element.id) { index, recipe in
                RecipeLibraryRow(
                    recipe: recipe,
                    onDelete: { pendingDeletion = recipe },
                    onOrganize: { editingMetadata = recipe },
                    onFavorite: { toggleFavorite(recipe) },
                    onRestore: { restoreRecipe(recipe) }
                )

                if index < filteredRecipes.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .appSurface(.quiet, padding: 0)
        .accessibilityIdentifier("recipe_library_list")
    }

    private var collectionHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.group) {
                recipeCount.fixedSize()
                Spacer(minLength: AppSpacing.compact)
                collectionPicker.fixedSize()
            }
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                recipeCount
                collectionPicker
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe_library_summary")
    }

    private var recipeCount: some View {
        Text("\(filteredRecipes.count.formatted()) \(filteredRecipes.count == 1 ? "recipe" : "recipes")")
            .appTextRole(.control)
            .foregroundStyle(AppPalette.text)
            .accessibilityIdentifier("recipe_summary_saved")
    }

    private var collectionPicker: some View {
        Picker("Recipe collection", selection: $filter) {
            ForEach(RecipeLibraryFilter.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .tint(AppPalette.text)
        .frame(minHeight: 44)
        .accessibilityIdentifier("recipe_library_filter")
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)
            Text("Loading recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "book.closed")
                .appTextRole(.screenTitle)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))

            VStack(spacing: 4) {
                Text("Save your go-to recipes")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                Text("Generate one with Maia, import a recipe, or build one from foods you already log.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingCreateRecipeSheet = true
            } label: {
                Label("Create recipe", systemImage: "plus")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    private var noMatchesState: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: "magnifyingglass")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
            Text("No matching recipes")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
            Text("Try another recipe name or ingredient.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func refreshRecipes() {
        Task { await loadLibrary() }
    }

    private func archiveRecipe(_ recipe: Recipe) {
        var metadata = recipe.libraryMetadata ?? RecipeLibraryMetadata(); metadata.archivedAt = Date()
        maintain(recipe, metadata: metadata, title: "Archive recipe")
    }
    private func restoreRecipe(_ recipe: Recipe) {
        var metadata = recipe.libraryMetadata ?? RecipeLibraryMetadata()
        metadata.archivedAt = nil; metadata.mergedIntoRecipeID = nil
        maintain(recipe, metadata: metadata, title: "Restore recipe")
    }
    private func toggleFavorite(_ recipe: Recipe) {
        var metadata = recipe.libraryMetadata ?? RecipeLibraryMetadata(); metadata.favorite.toggle()
        maintain(recipe, metadata: metadata, title: "Update recipe favorite")
    }
    private func maintain(_ recipe: Recipe, metadata: RecipeLibraryMetadata, title: String) {
        do {
            guard maintenance.prepare(.recipes(try RecipeLibraryRules.updating(recipe, metadata: metadata, title: title))) else { return }
            Task { await maintenance.submit(using: DIContainer.shared.nutritionRepository); await loadLibrary() }
        } catch { libraryError = error.localizedDescription }
    }
    private func restoreCache() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            if let cache = try EditorDraftStore().load(RecipeLibraryCache.self, userID: ownerID, scope: "recipe-library-cache")?.value {
                libraryRecipes = cache.recipes; loadedLibrary = true
                libraryError = "Showing recipes saved on this device while the account is refreshed."
            }
        } catch { libraryError = "Your previous recipe cache could not be opened. The file has been kept." }
    }
    @MainActor private func loadLibrary() async {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { libraryError = LibraryMutationError.accountChanged.localizedDescription; return }
        let requestID = UUID(); libraryLoadID = requestID; libraryLoading = true
        defer { if libraryLoadID == requestID { libraryLoading = false } }
        do {
            let recipes = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: ownerID)
            guard libraryLoadID == requestID, ownerID == DIContainer.shared.authService.currentUserID else { return }
            libraryRecipes = recipes; loadedLibrary = true; libraryError = nil
            do { try EditorDraftStore().save(RecipeLibraryCache(recipes: recipes), userID: ownerID, scope: "recipe-library-cache") } catch {
                libraryError = "Recipes loaded from your account; this device couldn't refresh its offline copy."
            }
        } catch {
            guard libraryLoadID == requestID, ownerID == DIContainer.shared.authService.currentUserID else { return }
            libraryError = "Couldn't refresh recipes. The last available library is kept. " + error.localizedDescription
        }
    }
}

private struct RecipeLibraryCache: Codable { let recipes: [Recipe] }

private struct RecipeLibraryRow: View {
    let recipe: Recipe
    let onDelete: () -> Void
    let onOrganize: () -> Void
    let onFavorite: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    recipeGlyph
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(recipe.name)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if recipe.libraryMetadata?.favorite == true {
                                Image(systemName: "star.fill")
                                    .appTextRole(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Favorite")
                            }
                        }

                        Text(nutritionSummary)
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(recipe.nutritionBasis == nil ? "Confirm serving basis" : recipe.nutritionBasisLabel)
                            .appTextRole(.caption)
                            .foregroundStyle(RecipeLibraryRules.needsReview(recipe) ? AppPalette.caution : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        metadata
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recipe_open_\(recipe.id ?? recipe.name)")
            .accessibilityHint("Opens recipe details")

            Menu {
                Button(recipe.libraryMetadata?.favorite == true ? "Remove favorite" : "Favorite", action: onFavorite)
                Button("Edit tags and organization", action: onOrganize)
                if RecipeLibraryRules.isVisible(recipe) { Button("Archive recipe", action: onDelete) } else {
                    Button("Restore recipe", action: onRestore)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Actions for \(recipe.name)")
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }

    private var recipeGlyph: some View {
        Text(FoodEmojiMapper.getEmoji(for: recipe.name))
            .font(.system(size: 26))
            .frame(width: 44, height: 44)
            .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var metadata: some View {
        Text("\(recipe.ingredients.count.formatted()) ingredients · \(recipe.instructions.count.formatted()) steps")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let tags = recipe.libraryMetadata?.tags, !tags.isEmpty {
            Text(tags.joined(separator: " · ")).appTextRole(.caption).foregroundStyle(.secondary)
        }
    }

    private var nutritionSummary: String {
        let calories = Int(recipe.nutritionPerPortion.calories.rounded()).formatted()
        let protein = Int(recipe.nutritionPerPortion.protein.rounded()).formatted()
        return "\(calories) cal · \(protein) g protein"
    }
}
