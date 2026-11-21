import Foundation

/// Every quantity is measured against the item's displayed catalog unit. Conversions
/// scale nutrition and all price estimates together, including partial shared rolls.
public enum AYCEPortionRules {
    public static let maximumQuantity = 100.0

    public static func isValid(_ quantity: Double, allowsZero: Bool = false) -> Bool {
        quantity.isFinite && quantity <= maximumQuantity && (allowsZero ? quantity >= 0 : quantity > 0)
    }

    public static func quantity(pieces: Double, item: AYCECatalogItem) -> Double? {
        guard let perUnit = item.piecesPerUnit, perUnit > 0, pieces.isFinite, pieces > 0 else { return nil }
        let quantity = pieces / Double(perUnit)
        return isValid(quantity) ? quantity : nil
    }

    public static func quantity(cookedGrams: Double, item: AYCECatalogItem) -> Double? {
        guard let perUnit = item.cookedGramsPerUnit, perUnit.isFinite, perUnit > 0,
              cookedGrams.isFinite, cookedGrams > 0 else { return nil }
        let quantity = cookedGrams / perUnit
        return isValid(quantity) ? quantity : nil
    }

    public static func formatted(_ quantity: Double) -> String {
        quantity.formatted(.number.precision(.fractionLength(0...2)))
    }

    public static func servingDescription(item: AYCECatalogItem, quantity: Double) -> String {
        if let pieces = item.piecesPerUnit {
            let pieceCount = quantity * Double(pieces)
            return "\(formatted(pieceCount)) \(pieceCount == 1 ? "piece" : "pieces") · \(formatted(quantity)) × \(item.unit)"
        }
        if let grams = item.cookedGramsPerUnit {
            return "\(formatted(quantity * grams)) g cooked · \(formatted(quantity)) \(quantity == 1 ? "serving" : "servings")"
        }
        // Parenthetical weights describe one catalog unit, not the amount eaten.
        // Keep that reference explicit: half a 20 g tablespoon is not 20 g.
        if quantity != 1, item.unit.contains("(") {
            return "\(formatted(quantity)) × 1 \(item.unit)"
        }
        let unit = quantity != 1 && ["piece", "slice", "bowl", "serving", "hand roll"].contains(item.unit)
            ? item.unit + "s" : item.unit
        return "\(formatted(quantity)) \(unit)"
    }
}

public extension AYCECatalog {
    /// Search English names and common menu spellings without changing saved item IDs.
    static func matchingSections(for cuisine: AYCECuisine, query: String = "", sectionID: String? = nil) -> [MenuSection] {
        let tokens = normalized(query).split(separator: " ")
        return sections(for: cuisine).compactMap { section in
            guard sectionID == nil || section.id == sectionID else { return nil }
            let items = section.items.filter { item in
                let text = normalized(([item.name, item.unit] + (searchAliases[item.id] ?? [])).joined(separator: " "))
                return tokens.allSatisfy { text.contains($0) }
            }
            return items.isEmpty ? nil : MenuSection(title: section.title, items: items)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
