import Foundation

public struct RecipeImportProvenance: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case ai, text, url, photo, structuredURL }
    public var kind: Kind
    public var sourceURL: String?
    public var originalText: String?
    public var pageHashes: [String]
    public var uncertainLines: [String]
    public var importedAt: Date
    public var missingNutritionFields: [String]?
    public var componentRevisions: [RecipeComponentRevision]?
    public var requestedServings: Double?
    public var requestedExclusions: [String]?
    public init(kind: Kind, sourceURL: String? = nil, originalText: String? = nil,
                pageHashes: [String] = [], uncertainLines: [String] = [], importedAt: Date = Date(),
                componentRevisions: [RecipeComponentRevision]? = nil, requestedServings: Double? = nil,
                requestedExclusions: [String]? = nil) {
        self.kind = kind; self.sourceURL = sourceURL; self.originalText = originalText
        self.pageHashes = pageHashes; self.uncertainLines = uncertainLines; self.importedAt = importedAt
        self.componentRevisions = componentRevisions; self.requestedServings = requestedServings
        self.requestedExclusions = requestedExclusions
    }
}

/// Source identity only: ingredient quantities and punctuation remain significant.
/// Existing imports participate without rewriting their saved recipe or provenance.
public enum RecipeImportDuplicateRules {
    public static func sourceTextFingerprint(_ provenance: RecipeImportProvenance?) -> String? {
        guard let provenance, provenance.kind != .ai, let text = provenance.originalText else { return nil }
        let normalized = text.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return try? PlanFingerprint.make(["schema": "recipe-source-text-v1", "text": normalized])
    }

    public static func sourceIdentity(_ provenance: RecipeImportProvenance?) -> String? {
        guard let provenance, provenance.kind != .ai else { return nil }
        if let text = sourceTextFingerprint(provenance) { return text }
        if let url = provenance.sourceURL, !url.isEmpty { return try? PlanFingerprint.make(["url": url]) }
        guard provenance.kind == .photo, !provenance.pageHashes.isEmpty else { return nil }
        return try? PlanFingerprint.make(provenance.pageHashes)
    }

    public static func matchingRecipe(for draft: Recipe, in recipes: [Recipe]) -> Recipe? {
        guard let source = draft.importProvenance, source.kind != .ai else { return nil }
        return recipes.first { saved in
            guard saved.id != nil, let previous = saved.importProvenance, previous.kind != .ai else { return false }
            if let url = source.sourceURL, !url.isEmpty, previous.sourceURL == url { return true }
            if let text = sourceTextFingerprint(source), text == sourceTextFingerprint(previous) { return true }
            return source.kind == .photo && previous.kind == .photo && !source.pageHashes.isEmpty
                && source.pageHashes == previous.pageHashes
        }
    }
}

public struct RecipeDocumentLine: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Double
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var needsReview: Bool { confidence < 0.8 || !confidence.isFinite }
    public init(text: String, confidence: Double, x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.text = text; self.confidence = confidence; self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct RecipeDocumentPage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var digest: String
    public var lines: [RecipeDocumentLine]
    /// Local review only. This image is never part of the saved cloud recipe.
    public var preview: Data?
    public var reviewedText: String
    public init(digest: String, lines: [RecipeDocumentLine], preview: Data? = nil) {
        id = UUID(); self.digest = digest; self.lines = lines; self.preview = preview
        reviewedText = lines.map(\.text).joined(separator: "\n")
    }
}

public struct RecipeDocumentDraft: Codable {
    public var pages: [RecipeDocumentPage] = []
    public var retainSourceText = true
    public init() {}
    public var combinedText: String { pages.map(\.reviewedText).joined(separator: "\n\n") }
    public var uncertainLines: [String] { pages.flatMap(\.lines).filter(\.needsReview).map(\.text) }
    public mutating func append(_ page: RecipeDocumentPage) throws {
        guard pages.count < 8, (page.preview?.count ?? 0) <= 2_000_000,
              !pages.contains(where: { $0.digest == page.digest }) else { throw RecipeDocumentError.duplicateOrLimit }
        guard !page.reviewedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeDocumentError.noText }
        pages.append(page)
    }
    public var looksLikeRecipe: Bool {
        let text = combinedText.lowercased()
        let quantity = text.range(of: #"(?:\d|[½¼¾⅓⅔])\s*(?:g\b|kg\b|ml\b|cups?\b|tbsp\b|tsp\b|oz\b|pounds?\b|tablespoons?\b|teaspoons?\b)"#, options: .regularExpression) != nil
        let instructions = ["ingredients", "method", "directions", "instructions", "bake", "cook", "stir", "mix", "preheat", "simmer"].filter { text.contains($0) }.count
        return combinedText.count >= 50 && quantity && instructions >= 2
    }
    public var provenance: RecipeImportProvenance {
        RecipeImportProvenance(kind: .photo, originalText: retainSourceText ? combinedText : nil,
            pageHashes: pages.map(\.digest), uncertainLines: retainSourceText ? uncertainLines : [])
    }
}

public enum RecipeDocumentError: Error, LocalizedError {
    case duplicateOrLimit, noText, notRecipe
    public var errorDescription: String? {
        switch self {
        case .duplicateOrLimit: "This page is already included, or the eight-page limit has been reached."
        case .noText: "No readable text was found. Try a clearer, well-lit page or paste its text."
        case .notRecipe: "Review the text for ingredient amounts and preparation steps. A photo of food cannot establish a written recipe."
        }
    }
}
