import Combine
import Foundation
import FirebaseFirestore

struct PantryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unit: String
    var category: String = "Misc"
    var dateAdded: Date? = Date()
}

@MainActor
class PantryService: ObservableObject {
    @Published var pantryItems: [PantryItem] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    private var listeningUserID: String?
    private var foodLoggedObserver: NSObjectProtocol?

    init() {
        foodLoggedObserver = NotificationCenter.default.addObserver(
            forName: .foodItemLogged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let userInfo = notification.userInfo,
                      let foodItem = userInfo[DailyLogNotificationUserInfoKey.foodItem] as? FoodItem,
                      let userID = userInfo[DailyLogNotificationUserInfoKey.userID] as? String else { return }

                self.removeIngredient(named: foodItem.name, userID: userID)
            }
        }
    }

    deinit {
        if let foodLoggedObserver {
            NotificationCenter.default.removeObserver(foodLoggedObserver)
        }
        listenerRegistration?.remove()
    }

    func startListening(userID: String) {
        guard !userID.isEmpty else { return }
        if listeningUserID == userID, listenerRegistration != nil { return }

        listenerRegistration?.remove()
        listeningUserID = userID
        isLoading = true

        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems)
        listenerRegistration = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            self.isLoading = false

            if let error {
                AppLog.data.error("Error fetching pantry items: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let documents = snapshot?.documents else { return }

            self.pantryItems = documents.compactMap { doc -> PantryItem? in
                try? doc.data(as: PantryItem.self)
            }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    func stopListening(clearItems: Bool = true) {
        listenerRegistration?.remove()
        listenerRegistration = nil
        listeningUserID = nil
        isLoading = false
        if clearItems {
            pantryItems = []
        }
    }

    func addOrUpdateItem(_ item: PantryItem, userID: String) {
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

        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(itemToSave.id.uuidString)
        do {
            try ref.setData(from: itemToSave)
        } catch {
            AppLog.data.error("Error saving pantry item: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteItem(_ item: PantryItem, userID: String) {
        let ref = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.pantryItems).document(item.id.uuidString)
        ref.delete { error in
            if let error {
                AppLog.data.error("Error deleting pantry item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearPantry(userID: String) async {
        let itemsToDelete = pantryItems
        for item in itemsToDelete {
            deleteItem(item, userID: userID)
        }
    }

    func removeIngredients(_ itemsToRemove: [FoodItem], userID: String) {
        for loggedItem in itemsToRemove {
            removeIngredient(named: loggedItem.name, userID: userID)
        }
    }

    func removeIngredients(_ ingredientNames: [String], userID: String) {
        for ingredientName in ingredientNames {
            removeIngredient(named: ingredientName, userID: userID)
        }
    }

    private func removeIngredient(named rawName: String, userID: String) {
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
}
