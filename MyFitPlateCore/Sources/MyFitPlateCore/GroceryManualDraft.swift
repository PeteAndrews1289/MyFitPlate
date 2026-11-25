import Foundation

public struct GroceryManualDraft: Codable {
    public var operationID: UUID
    public var itemID: UUID
    public var original: GroceryListItem?
    public var shoppingStartDate: Date?
    public var name: String
    public var quantity: String
    public var unit: String
    public var category: String
    public var barcode: String?
    public var product: GroceryProductSnapshot?
    public var packageQuantity: String
    public var packageUnit: String
    public var overrideReason: String
    public init(operationID: UUID, itemID: UUID, original: GroceryListItem?, shoppingStartDate: Date?, name: String,
                quantity: String, unit: String, category: String, barcode: String?, product: GroceryProductSnapshot?,
                packageQuantity: String, packageUnit: String, overrideReason: String) {
        self.operationID = operationID; self.itemID = itemID; self.original = original; self.shoppingStartDate = shoppingStartDate
        self.name = name; self.quantity = quantity; self.unit = unit; self.category = category; self.barcode = barcode; self.product = product
        self.packageQuantity = packageQuantity; self.packageUnit = packageUnit; self.overrideReason = overrideReason
    }
}

@MainActor
public struct GroceryManualDraftStore {
    private let userID: String?
    private let store: EditorDraftStore
    private let scope = "grocery-manual-editor"
    public init(userID: String?, store: EditorDraftStore = EditorDraftStore()) { self.userID = userID; self.store = store }
    public func load() throws -> GroceryManualDraft? {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw GroceryChecklistError.accountChanged }
        return try store.load(GroceryManualDraft.self, userID: userID, scope: scope)?.value
    }
    public func save(_ draft: GroceryManualDraft, expectedFingerprint: String?) throws -> String {
        guard let userID, try load().map(PlanFingerprint.make) == expectedFingerprint else { throw GroceryChecklistError.changed }
        try store.save(draft, userID: userID, scope: scope)
        return try PlanFingerprint.make(draft)
    }
    public func clear(expectedFingerprint: String) throws {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw GroceryChecklistError.accountChanged }
        guard try store.removeIfUnchanged(GroceryManualDraft.self, userID: userID, scope: scope, fingerprint: expectedFingerprint) else {
            throw GroceryChecklistError.changed
        }
    }
    public func discardCorrupt() throws {
        guard let userID, userID == DIContainer.shared.authService.currentUserID else { throw GroceryChecklistError.accountChanged }
        do {
            _ = try store.load(GroceryManualDraft.self, userID: userID, scope: scope)
        } catch {
            try store.remove(userID: userID, scope: scope); return
        }
        throw GroceryChecklistError.changed
    }
}
