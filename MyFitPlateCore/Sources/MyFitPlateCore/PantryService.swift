import Combine
import Foundation

public struct PantryItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var quantity: Double
    public var unit: String
    public var category: String = "Misc"
    public var dateAdded: Date? = Date()
    public var quantityUnknown: Bool?
    /// Nil legacy amounts remain visible but need explicit confirmation before automatic coverage.
    public var quantityVerified: Bool?
    public var bestBefore: Date?
    public var preparation: String?
    public var location: String?
    public var revisionID: String?
    public var cookedBatch: MealCookingBatch?
    public var portionFood: FoodItem?
    public var cookedAt: Date?
    public var isArchived: Bool?
    public var creationUndone: Bool?
    public var recordedPlannedPortions: [String]?
    public var productSnapshot: GroceryProductSnapshot?
    public var purchaseEvidence: PantryPurchaseEvidence?

    public var availableQuantity: Double { quantityUnknown == true || quantityVerified != true || isArchived == true ? 0 : max(0, quantity) }
    public var isCookedBatch: Bool { cookedBatch != nil }

    public init(id: UUID = UUID(), name: String, quantity: Double, unit: String, category: String = "Misc", dateAdded: Date? = Date(),
                productSnapshot: GroceryProductSnapshot? = nil, purchaseEvidence: PantryPurchaseEvidence? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.dateAdded = dateAdded
        self.productSnapshot = productSnapshot
        self.purchaseEvidence = purchaseEvidence
    }
}

public enum PantryReceiptReviewRules {
    public static func reviewedItems(from items: [PantryItem]) -> [PantryItem] {
        items.compactMap { item in
            var reviewed = item
            reviewed.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            reviewed.unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            reviewed.category = item.category.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !reviewed.name.isEmpty,
                  reviewed.purchaseEvidence?.isValid != false,
                  reviewed.quantity.isFinite,
                  reviewed.quantity > 0 else { return nil }

            if reviewed.unit.isEmpty { reviewed.unit = "item" }
            if reviewed.category.isEmpty { reviewed.category = "Misc" }
            return reviewed
        }
    }
}

@MainActor
public class PantryService: ObservableObject {
    @Published public var pantryItems: [PantryItem] = []
    @Published public var isLoading = false
    @Published public private(set) var errorMessage: String?

    private var listenerRegistration: Any?
    private var listeningUserID: String?
    public var activeUserID: String? { listeningUserID }
    // A diary food does not identify a stock item or its consumed mass. Preserve accepted
    // inventory until the user edits it or a future explicit stock-consumption ledger maps it.
    public init() {}

    deinit {
        let handle = listenerRegistration
        Task { @MainActor in
            if let handle {
                DIContainer.shared.nutritionRepository.removePantrySnapshotListener(handle)
            }
        }
    }

    public func startListening(userID: String) {
        guard !userID.isEmpty,
              DIContainer.shared.authService.currentUserID == userID else { return }
        if listeningUserID == userID, listenerRegistration != nil { return }

        if listeningUserID != nil, listeningUserID != userID {
            pantryItems = []
        }
        if let handle = listenerRegistration {
            DIContainer.shared.nutritionRepository.removePantrySnapshotListener(handle)
        }
        listeningUserID = userID
        isLoading = true

        listenerRegistration = DIContainer.shared.nutritionRepository.addPantrySnapshotListener(userID: userID) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.listeningUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                self.isLoading = false
                switch result {
                case .success(let items):
                    self.errorMessage = nil
                    self.pantryItems = items.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                case .failure(let error):
                    self.errorMessage = "Couldn’t refresh pantry stock. Previously loaded amounts remain visible; reconnect and retry before using them."
                    AppLog.data.error("Error fetching pantry items: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    public func stopListening(clearItems: Bool = true) {
        if let handle = listenerRegistration {
            DIContainer.shared.nutritionRepository.removePantrySnapshotListener(handle)
        }
        listenerRegistration = nil
        listeningUserID = nil
        isLoading = false
        errorMessage = nil
        if clearItems {
            pantryItems = []
        }
    }

    public func addOrUpdateItem(_ item: PantryItem, userID: String) {
        guard canMutatePantry(for: userID) else { return }
        var itemToSave = item
        if pantryItems.contains(where: { $0.id == item.id }) {
            itemToSave = item
        } else if let existing = pantryItems.first(where: {
            IngredientNameMatcher.matches($0.name, item.name) &&
            IngredientUnitNormalizer.normalized($0.unit) == IngredientUnitNormalizer.normalized(item.unit)
        }) {
            itemToSave = existing
            itemToSave.quantity = existing.quantity + item.quantity
            itemToSave.dateAdded = existing.dateAdded ?? item.dateAdded
        }

        Task {
            do {
                try await DIContainer.shared.nutritionRepository.savePantryItem(userID: userID, item: itemToSave)
            } catch {
                AppLog.data.error("Error saving pantry item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func deleteItem(_ item: PantryItem, userID: String) {
        guard canMutatePantry(for: userID) else { return }
        Task {
            do {
                try await DIContainer.shared.nutritionRepository.deletePantryItem(userID: userID, itemID: item.id.uuidString)
            } catch {
                AppLog.data.error("Error deleting pantry item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func clearPantry(userID: String) async {
        let itemsToDelete = pantryItems
        for item in itemsToDelete {
            deleteItem(item, userID: userID)
        }
    }

    public func removeIngredients(_ itemsToRemove: [FoodItem], userID: String) {
        for loggedItem in itemsToRemove {
            removeIngredient(named: loggedItem.name, userID: userID)
        }
    }

    public func removeIngredients(_ ingredientNames: [String], userID: String) {
        for ingredientName in ingredientNames {
            removeIngredient(named: ingredientName, userID: userID)
        }
    }

    private func removeIngredient(named rawName: String, userID: String) {
        guard canMutatePantry(for: userID) else { return }
        guard let index = pantryItems.firstIndex(where: { IngredientNameMatcher.matches($0.name, rawName) }) else {
            return
        }

        let parsed = IngredientParser.parse(rawName)
        var pantryItem = pantryItems[index]
        let amountToRemove = IngredientQuantityResolver.amountToRemove(parsed: parsed, pantryUnit: pantryItem.unit)

        if pantryItem.quantity > amountToRemove {
            pantryItem.quantity -= amountToRemove
            addOrUpdateItem(pantryItem, userID: userID)
        } else {
            deleteItem(pantryItem, userID: userID)
        }
    }

    private func canMutatePantry(for userID: String) -> Bool {
        DIContainer.shared.authService.currentUserID == userID &&
            (listeningUserID == nil || listeningUserID == userID)
    }
}
