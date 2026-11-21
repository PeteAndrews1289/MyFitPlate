import Foundation

public enum RecipeRevisionError: Int, Error, LocalizedError, CustomNSError {
    case invalid = 400
    case accountChanged = 401
    case changed = 409
    case cancelled = 410
    case unavailable = 503

    public static var errorDomain: String { "MyFitPlate.RecipeRevision" }
    public var errorCode: Int { rawValue }
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Review the recipe amounts and yield before saving."
        case .accountChanged: return "Sign back into the account that opened this recipe."
        case .changed: return "This recipe changed elsewhere. Your proposal is kept; reopen the saved recipe to review the latest version."
        case .cancelled: return "This pending save was cancelled. It cannot change the recipe."
        case .unavailable: return "The recipe could not be confirmed. Keep this editor open and retry."
        }
    }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription ?? "Could not save the recipe."] }
}

public enum RecipeRevisionResolution: Equatable {
    /// The server has not confirmed acceptance. Absence alone cannot authorize local discard.
    case pending
    case cancelled
    /// Current library state may be newer, or absent after a later deliberate deletion.
    case accepted(Recipe?)
}

/// New authoring uses a stable recipe ID, a content revision and an exact opening snapshot.
/// The snapshot check is deliberately stricter than the content revision: incidental source
/// timestamps may be excluded from content identity, but never excuse a stale edit.
public enum RecipeRevisionRules {
    public static func commandFingerprint(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID) throws -> String {
        struct Intent: Encodable {
            let schemaVersion = 1
            let userID: String
            let expected: Recipe?
            let updated: Recipe
            let operationID: UUID
        }
        return try PlanFingerprint.make(Intent(userID: userID, expected: expected, updated: updated, operationID: operationID))
    }

    public static func validate(expected: Recipe?, updated: Recipe) throws {
        guard let id = updated.id, !id.isEmpty, id.utf8.count <= 128, !id.contains("/"),
              expected == nil || expected?.id == id,
              updated.revisionID == (try RecipePortionRules.revisionID(for: updated)),
              !updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [updated.nutrition.calories, updated.nutrition.protein, updated.nutrition.carbs, updated.nutrition.fats]
                .allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw RecipeRevisionError.invalid }
        if updated.nutritionBasis != nil {
            guard let yield = updated.servings, yield.isFinite, yield > 0, yield <= 100 else {
                throw RecipeRevisionError.invalid
            }
        }
        if let weight = updated.cookedWeightGrams {
            guard updated.nutritionBasis != nil, weight.isFinite, weight > 0, weight <= 1_000_000 else {
                throw RecipeRevisionError.invalid
            }
        }
        guard try JSONEncoder().encode(updated).count <= 500_000 else { throw RecipeRevisionError.invalid }
    }

    public static func sameOpeningSnapshot(_ first: Recipe, _ second: Recipe) throws -> Bool {
        try PlanFingerprint.make(first) == PlanFingerprint.make(second)
    }

    public static func isAcceptedRevision(_ latest: Recipe, updated: Recipe) throws -> Bool {
        guard latest.id == updated.id, let revision = updated.revisionID,
              latest.revisionID == revision else { return false }
        return try RecipePortionRules.revisionID(for: latest) == revision
    }
}
