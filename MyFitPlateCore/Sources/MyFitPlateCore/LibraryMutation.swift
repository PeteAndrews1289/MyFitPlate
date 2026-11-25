import Foundation

public struct RecipeLibraryMetadata: Codable, Equatable, Sendable {
    public var favorite: Bool
    public var tags: [String]
    public var archivedAt: Date?
    public var mergedIntoRecipeID: String?
    public init(favorite: Bool = false, tags: [String] = [], archivedAt: Date? = nil, mergedIntoRecipeID: String? = nil) {
        self.favorite = favorite; self.tags = tags; self.archivedAt = archivedAt; self.mergedIntoRecipeID = mergedIntoRecipeID
    }
    private enum CodingKeys: String, CodingKey { case favorite, tags, archivedAt, mergedIntoRecipeID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
        mergedIntoRecipeID = try values.decodeIfPresent(String.self, forKey: .mergedIntoRecipeID)
    }
    public var isNeutral: Bool { !favorite && tags.isEmpty && archivedAt == nil && mergedIntoRecipeID == nil }
    public var isValid: Bool {
        tags.count <= 20 && tags.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 40 }
            && (archivedAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
            && (mergedIntoRecipeID.map { !$0.isEmpty && $0.count <= 200 && !$0.contains("/") } ?? true)
    }
}

public enum LibraryMutationError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400, accountChanged = 401, changed = 409, cancelled = 410, unavailable = 503
    public static var errorDomain: String { "MyFitPlate.LibraryMutation" }
    public var errorCode: Int { rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "The library change could not be confirmed."] }
    public var errorDescription: String? {
        switch self {
        case .invalid: "Review the selected records and keeper before changing your library. Different product barcodes stay separate."
        case .accountChanged: "Return to the account that opened this library review."
        case .changed: "One of these records changed. Your review is kept; refresh the records before trying again."
        case .cancelled: "This library operation was cancelled and cannot be submitted again."
        case .unavailable: "The library change could not be confirmed. Your exact review is kept for retry or status checking."
        }
    }
}

public enum RecipeLibraryMutationResolution: String, Codable, Equatable, Sendable { case pending, accepted, cancelled }
public enum SavedFoodLibraryMutationResolution: String, Codable, Equatable, Sendable { case pending, accepted, cancelled }

public struct RecipeLibraryMutation: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let before: [Recipe]
    public let after: [Recipe]
    public let undoingID: UUID?
    public init(id: UUID = UUID(), title: String, before: [Recipe], after: [Recipe], undoingID: UUID? = nil) {
        self.id = id; self.title = title; self.before = before; self.after = after; self.undoingID = undoingID
    }
    public var recipeIDs: Set<String> { Set(after.compactMap(\.id)) }
    public func validate() throws {
        guard !title.isEmpty, title.count <= 200, (1...100).contains(before.count), before.count == after.count,
              undoingID != id, (try JSONEncoder().encode(self)).count <= 350_000,
              Set(before.compactMap(\.id)).count == before.count,
              Set(before.compactMap(\.id)) == recipeIDs, recipeIDs.count == after.count,
              recipeIDs.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0.count <= 200 }) else { throw LibraryMutationError.invalid }
        for updated in after {
            guard updated.libraryMetadata?.isValid != false,
                  let original = before.first(where: { $0.id == updated.id }),
                  try RecipePortionRules.revisionID(for: original) == RecipePortionRules.revisionID(for: updated) else {
                throw LibraryMutationError.invalid
            }
            if let keeper = updated.libraryMetadata?.mergedIntoRecipeID {
                guard keeper != updated.id else { throw LibraryMutationError.invalid }
            }
        }
    }
    public func applying(to recipes: [Recipe]) throws -> [Recipe] {
        try validate()
        guard Set(recipes.compactMap(\.id)).count == recipes.count else { throw LibraryMutationError.invalid }
        var result = recipes
        for original in before {
            guard let index = result.firstIndex(where: { $0.id == original.id }),
                  try Self.snapshotFingerprint(result[index]) == Self.snapshotFingerprint(original),
                  let updated = after.first(where: { $0.id == original.id }) else { throw LibraryMutationError.changed }
            result[index] = updated
        }
        return result
    }
    public func inverse() -> Self { Self(title: "Undo \(title)", before: after, after: before, undoingID: id) }
    public static func snapshotFingerprint(_ recipe: Recipe) throws -> String {
        struct Basis: Encodable { let id: String?; let content: String; let metadata: RecipeLibraryMetadata? }
        var metadata = recipe.libraryMetadata
        if metadata?.isNeutral == true { metadata = nil }
        if let date = metadata?.archivedAt { metadata?.archivedAt = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded() / 1_000) }
        return try PlanFingerprint.make(Basis(id: recipe.id, content: RecipePortionRules.revisionID(for: recipe), metadata: metadata))
    }
    public var fingerprint: String {
        get throws {
            struct Basis: Encodable { let id: UUID; let title: String; let before: [String]; let after: [String]; let undoingID: UUID? }
            return try PlanFingerprint.make(Basis(id: id, title: title, before: before.map(Self.snapshotFingerprint),
                after: after.map(Self.snapshotFingerprint), undoingID: undoingID))
        }
    }
}

public struct SavedFoodLibraryMutation: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let before: [FoodItem]
    public let upserts: [FoodItem]
    public let removedIDs: Set<String>
    public let undoingID: UUID?
    public init(id: UUID = UUID(), title: String, before: [FoodItem], upserts: [FoodItem], removedIDs: Set<String>, undoingID: UUID? = nil) {
        self.id = id; self.title = title; self.before = before; self.upserts = upserts; self.removedIDs = removedIDs; self.undoingID = undoingID
    }
    private enum CodingKeys: String, CodingKey { case id, title, before, upserts, removedIDs, undoingID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); title = try values.decode(String.self, forKey: .title)
        before = try values.decode([FoodItem].self, forKey: .before); upserts = try values.decode([FoodItem].self, forKey: .upserts)
        removedIDs = try values.decode(Set<String>.self, forKey: .removedIDs)
        undoingID = try values.decodeIfPresent(UUID.self, forKey: .undoingID)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(title, forKey: .title)
        try values.encode(before, forKey: .before); try values.encode(upserts, forKey: .upserts)
        try values.encode(removedIDs.sorted(), forKey: .removedIDs); try values.encodeIfPresent(undoingID, forKey: .undoingID)
    }
    public var foodIDs: Set<String> { Set(upserts.map(\.id)).union(removedIDs) }
    public func validate() throws {
        guard !title.isEmpty, title.count <= 200, (1...100).contains(foodIDs.count), before.count <= 100,
              undoingID != id, (try JSONEncoder().encode(self)).count <= 350_000,
              Set(before.map(\.id)).count == before.count, Set(upserts.map(\.id)).count == upserts.count,
              Set(before.map(\.id)).isSubset(of: foodIDs), Set(upserts.map(\.id)).isDisjoint(with: removedIDs),
              foodIDs.allSatisfy({ !$0.isEmpty && !$0.contains("/") && $0.count <= 200 }),
              (before + upserts).allSatisfy(MyFoodsLibraryRules.isValidSavedSnapshot) else { throw LibraryMutationError.invalid }
    }
    public func applying(to foods: [FoodItem]) throws -> [FoodItem] {
        try validate()
        guard Set(foods.map(\.id)).count == foods.count else { throw LibraryMutationError.invalid }
        for id in foodIDs {
            guard try Self.snapshotFingerprint(foods.first(where: { $0.id == id })) == Self.snapshotFingerprint(before.first(where: { $0.id == id })) else {
                throw LibraryMutationError.changed
            }
        }
        var result = foods.filter { !removedIDs.contains($0.id) }
        for updated in upserts {
            if let index = result.firstIndex(where: { $0.id == updated.id }) { result[index] = updated } else { result.append(updated) }
        }
        return result
    }
    public func inverse() -> Self {
        Self(title: "Undo \(title)", before: upserts, upserts: before,
            removedIDs: Set(upserts.map(\.id)).subtracting(before.map(\.id)), undoingID: id)
    }
    public static func merge(_ foods: [FoodItem], keeping id: String) throws -> Self {
        guard foods.count >= 2, var keeper = foods.first(where: { $0.id == id }) else { throw LibraryMutationError.invalid }
        let barcodes = Set(foods.map { BarcodeCorrectionRules.normalizedBarcode($0.sourceMetadata?.barcode ?? "") }.filter { !$0.isEmpty })
        guard barcodes.count <= 1 else { throw LibraryMutationError.invalid }
        if let barcode = barcodes.first, BarcodeCorrectionRules.normalizedBarcode(keeper.sourceMetadata?.barcode ?? "").isEmpty {
            var metadata = keeper.sourceMetadata ?? .userEntered(sourceName: "My Foods")
            metadata.barcode = barcode
            keeper.sourceMetadata = metadata
        }
        let result = Self(title: "Merge saved food copies", before: foods, upserts: [keeper], removedIDs: Set(foods.map(\.id)).subtracting([id]))
        try result.validate(); return result
    }
    public static func snapshotFingerprint(_ food: FoodItem?) throws -> String {
        try PlanFingerprint.make(food.map(RecipePortionRules.revisionIngredient))
    }
    public var fingerprint: String {
        get throws {
            struct Basis: Encodable { let id: UUID; let title: String; let before: [String]; let upserts: [String]; let removedIDs: [String]; let undoingID: UUID? }
            return try PlanFingerprint.make(Basis(id: id, title: title, before: before.map { try Self.snapshotFingerprint($0) },
                upserts: upserts.map { try Self.snapshotFingerprint($0) }, removedIDs: removedIDs.sorted(), undoingID: undoingID))
        }
    }
}
