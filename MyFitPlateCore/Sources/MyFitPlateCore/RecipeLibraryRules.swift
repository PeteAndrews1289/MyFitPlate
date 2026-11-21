import Foundation

public enum RecipeLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, favorites, needsReview, archived
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "All recipes"
        case .favorites: "Favorites"
        case .needsReview: "Needs review"
        case .archived: "Archived"
        }
    }
}

public struct RecipeDuplicateGroup: Identifiable, Sendable {
    public var recipes: [Recipe]
    public var exact: Bool
    public var id: String { recipes.compactMap(\.id).sorted().joined(separator: "|") }
}

public enum RecipeLibraryRules {
    public static func isVisible(_ recipe: Recipe) -> Bool {
        recipe.libraryMetadata?.archivedAt == nil && recipe.libraryMetadata?.mergedIntoRecipeID == nil
    }
    public static func needsReview(_ recipe: Recipe) -> Bool {
        recipe.nutritionBasis == nil || recipe.nutritionNeedsReview == true || !recipe.unresolvedIngredientTexts.isEmpty
            || recipe.importProvenance?.missingNutritionFields?.isEmpty == false
    }
    public static func filtered(_ recipes: [Recipe], query: String = "", filter: RecipeLibraryFilter = .all) -> [Recipe] {
        let query = normalized(query)
        return recipes.filter { recipe in
            let included: Bool
            switch filter {
            case .all: included = isVisible(recipe)
            case .favorites: included = isVisible(recipe) && recipe.libraryMetadata?.favorite == true
            case .needsReview: included = isVisible(recipe) && needsReview(recipe)
            case .archived: included = !isVisible(recipe)
            }
            guard included else { return false }
            let index = [recipe.name, recipe.importProvenance?.sourceURL ?? "", recipe.importProvenance?.originalText ?? ""]
                + recipe.ingredients + (recipe.libraryMetadata?.tags ?? [])
            return query.isEmpty || index.contains { normalized($0).contains(query) }
        }.sorted {
            if ($0.libraryMetadata?.favorite ?? false) != ($1.libraryMetadata?.favorite ?? false) {
                return $0.libraryMetadata?.favorite == true
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    public static func duplicateGroups(_ recipes: [Recipe]) -> [RecipeDuplicateGroup] {
        let candidates = recipes.filter { $0.id != nil && isVisible($0) }
        let groups = Dictionary(grouping: candidates, by: { normalized($0.name) })
        return groups.values.filter { $0.count > 1 }.map { recipes in
            let revisions = Set(recipes.compactMap { try? RecipePortionRules.revisionID(for: $0) })
            return RecipeDuplicateGroup(recipes: recipes.sorted { $0.libraryMetadata?.favorite == true && $1.libraryMetadata?.favorite != true },
                exact: revisions.count == 1 && revisions.first != nil)
        }.sorted { $0.id < $1.id }
    }
    public static func merging(_ recipes: [Recipe], keeping id: String, now: Date = Date()) throws -> RecipeLibraryMutation {
        guard recipes.count >= 2, let keeper = recipes.first(where: { $0.id == id }),
              recipes.allSatisfy(isVisible) else { throw LibraryMutationError.invalid }
        let tags = Array(Set(recipes.flatMap { $0.libraryMetadata?.tags ?? [] })).sorted()
        let after = recipes.map { recipe -> Recipe in
            var updated = recipe
            var metadata = recipe.libraryMetadata ?? RecipeLibraryMetadata()
            if recipe.id == id {
                metadata.tags = Array(tags.prefix(20))
                metadata.favorite = recipes.contains { $0.libraryMetadata?.favorite == true }
            } else { metadata.archivedAt = now; metadata.mergedIntoRecipeID = keeper.id }
            updated.libraryMetadata = metadata
            return updated
        }
        let mutation = RecipeLibraryMutation(title: "Merge recipe copies", before: recipes, after: after)
        try mutation.validate(); return mutation
    }
    public static func updating(_ recipe: Recipe, metadata: RecipeLibraryMetadata, title: String) throws -> RecipeLibraryMutation {
        var updated = recipe; updated.libraryMetadata = metadata
        let mutation = RecipeLibraryMutation(title: title, before: [recipe], after: [updated])
        try mutation.validate(); return mutation
    }
    public static func resolvedRecipe(id: String, in recipes: [Recipe]) -> Recipe? {
        var next = id; var seen = Set<String>()
        while seen.insert(next).inserted, seen.count <= 100,
              let recipe = recipes.first(where: { $0.id == next }) {
            guard let keeper = recipe.libraryMetadata?.mergedIntoRecipeID else { return recipe }
            next = keeper
        }
        return nil
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
