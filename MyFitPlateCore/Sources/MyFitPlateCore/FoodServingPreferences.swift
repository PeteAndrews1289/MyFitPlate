import Foundation

/// Remembers the last accepted portion, without changing a provider's base record.
@MainActor
public final class FoodServingPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func remember(_ food: FoodItem, userID: String) {
        guard let key = key(userID), let identity = identity(food),
              [food.calories, food.protein, food.carbs, food.fats, food.servingWeight].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return }
        var values = read(userID)
        var remembered = food
        remembered.timestamp = Date()
        values[identity] = remembered
        let ordered = values.sorted { ($0.value.timestamp ?? .distantPast) > ($1.value.timestamp ?? .distantPast) }
        if let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: ordered.prefix(100).map { ($0.key, $0.value) })) {
            defaults.set(data, forKey: key)
        }
    }

    public func preferred(_ food: FoodItem, userID: String) -> FoodItem {
        guard let identity = identity(food), var saved = read(userID)[identity], isCompatible(saved: saved, current: food) else { return food }
        // A cached, hydrated portion must not be interpreted as a raw provider ID and hydrated again.
        saved.id = "preferred_" + identity
        return saved
    }

    /// Old preferences remain inspectable in storage, but cannot silently replace a changed
    /// product, scoop conversion, or formulation. Management/review UI is a separate W1 task.
    private func isCompatible(saved: FoodItem, current: FoodItem) -> Bool {
        guard let old = saved.sourceMetadata, let new = current.sourceMetadata,
              old.sourceType == new.sourceType, old.sourceID == new.sourceID,
              old.sourceUpdatedAt == new.sourceUpdatedAt else { return false }
        let oldServing = portionMeasure(saved)
        let newServing = portionMeasure(current)
        let oldUnit = oldServing.unit
        let newUnit = newServing.unit
        guard oldUnit == newUnit else { return false }
        let oldQuantity = oldServing.quantity
        let newQuantity = newServing.quantity
        guard oldQuantity.isFinite, oldQuantity > 0, newQuantity.isFinite, newQuantity > 0 else { return false }
        let oldMass = saved.servingWeight / oldQuantity, newMass = current.servingWeight / newQuantity
        func close(_ first: Double, _ second: Double, absolute: Double) -> Bool {
            first.isFinite && second.isFinite && abs(first - second) <= max(absolute, max(abs(first), abs(second)) * 0.01)
        }
        guard close(oldMass, newMass, absolute: 0.01) else { return false }
        let oldDivisor = saved.servingWeight > 0 ? saved.servingWeight / 100 : oldQuantity
        let newDivisor = current.servingWeight > 0 ? current.servingWeight / 100 : newQuantity
        guard oldDivisor > 0, newDivisor > 0 else { return false }
        return close(saved.calories / oldDivisor, current.calories / newDivisor, absolute: 1)
            && close(saved.protein / oldDivisor, current.protein / newDivisor, absolute: 0.1)
            && close(saved.carbs / oldDivisor, current.carbs / newDivisor, absolute: 0.1)
            && close(saved.fats / oldDivisor, current.fats / newDivisor, absolute: 0.1)
    }

    /// Preferences include older natural labels ("1.5 cups") as well as typed
    /// quantity/unit and "2 x scoop" records. This parses the amount only; it
    /// never invents a mass/volume conversion for an unknown measure.
    private func portionMeasure(_ food: FoodItem) -> (quantity: Double, unit: String) {
        let text = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        var quantity = 1.0
        var unit = text
        let pattern = #"^((?:[0-9]+\s+)?[0-9]+/[0-9]+|[0-9]+(?:\.[0-9]+)?)\s*(?:[x×]\s*)?([A-Za-zµμ].*)$"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let amountRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text) {
            let amount = String(text[amountRange])
            let parts = amount.split(separator: " ")
            if let fraction = parts.last, fraction.contains("/") {
                quantity = 0
                let values = fraction.split(separator: "/").compactMap { Double($0) }
                if values.count == 2, values[1] > 0 {
                    quantity = (parts.count == 2 ? Double(parts[0]) ?? 0 : 0) + values[0] / values[1]
                }
            } else { quantity = Double(amount) ?? 0 }
            unit = String(text[unitRange])
        }
        let normalized = IngredientUnitNormalizer.normalized(food.servingUnit ?? unit)
        let canonical: String
        switch normalized {
        case "scoops": canonical = "scoop"
        case "servings": canonical = "serving"
        case "portions": canonical = "portion"
        default: canonical = normalized
        }
        return (food.quantityValue ?? quantity, canonical)
    }

    public func clear(userID: String) {
        if let key = key(userID) { defaults.removeObject(forKey: key) }
    }

    private func read(_ userID: String) -> [String: FoodItem] {
        guard let key = key(userID), let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: FoodItem].self, from: data) else { return [:] }
        return values
    }

    private func key(_ userID: String) -> String? { AccountScopedStorageKey.make(prefix: "foodServingPreferences", userID: userID) }

    private func identity(_ food: FoodItem) -> String? {
        let name = food.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !food.id.hasPrefix("ayce_"), let metadata = food.sourceMetadata else { return nil }
        if let barcode = metadata.barcode, !barcode.isEmpty { return "barcode|\(barcode)|\(name)" }
        guard let sourceID = metadata.sourceID, !sourceID.isEmpty else { return nil }
        return "\(metadata.sourceType.rawValue)|\(sourceID)|\(name)"
    }
}
