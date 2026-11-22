import Foundation

/// Loads retain the original canonical pounds. Display units and loading meaning are explicit
/// metadata, so choosing kilograms or a per-hand convention never rewrites old set values.
public struct StrengthEquipment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case fixedWeights, barbell
        public var id: String { rawValue }
        public var title: String { self == .fixedWeights ? "Fixed weights or machine" : "Bar and plates" }
    }

    public enum Unit: String, Codable, CaseIterable, Identifiable, Sendable {
        case lb, kg
        public var id: String { rawValue }
        public var title: String { rawValue }
        public func displayWeight(_ pounds: Double) -> Double { self == .kg ? pounds * 0.45359237 : pounds }
        public func storedWeight(_ displayed: Double) -> Double { self == .kg ? displayed / 0.45359237 : displayed }
    }

    public enum LoadingMeaning: String, Codable, CaseIterable, Identifiable, Sendable {
        case asLogged, total, perHand, added, assistance, bodyweightOnly
        public var id: String { rawValue }
        public func supports(_ kind: Kind) -> Bool {
            switch self {
            case .assistance, .bodyweightOnly: kind == .fixedWeights
            default: true
            }
        }
        public var title: String {
            switch self {
            case .asLogged: "As previously logged"
            case .total: "Total load"
            case .perHand: "Per hand"
            case .added: "Added weight"
            case .assistance: "Assistance (less is harder)"
            case .bodyweightOnly: "Bodyweight only"
            }
        }
    }

    public var kind: Kind
    public var unit: Unit
    public var loadingMeaning: LoadingMeaning
    /// Use a name to keep different machines or implements from sharing performance history.
    public var name: String?
    public var availableWeights: [Double]
    public var barWeight: Double
    /// One plate on each side of the bar. Repeating a size supplies an additional pair.
    public var plates: [Double]
    /// Immutable profile/implement identity and revision used for this session's setup.
    public var gymProfile: StrengthGymProfileReference?

    public init(kind: Kind = .fixedWeights, unit: Unit = .lb, loadingMeaning: LoadingMeaning = .asLogged,
                name: String? = nil, availableWeights: [Double] = [], barWeight: Double = 45,
                plates: [Double] = [], gymProfile: StrengthGymProfileReference? = nil) {
        self.kind = kind
        self.unit = unit
        self.loadingMeaning = loadingMeaning
        self.name = name
        self.availableWeights = availableWeights
        self.barWeight = barWeight
        self.plates = plates
        self.gymProfile = gymProfile
    }

    public var isValid: Bool {
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 { return false }
        guard loadingMeaning.supports(kind) else { return false }
        if loadingMeaning == .bodyweightOnly { return availableWeights == [0] }
        switch kind {
        case .fixedWeights:
            return (1...256).contains(availableWeights.count)
                && availableWeights.allSatisfy { $0.isFinite && (0...10_000).contains($0) }
        case .barbell:
            return barWeight.isFinite && (0...1_000).contains(barWeight) && plates.count <= 12
                && (barWeight > 0 || !plates.isEmpty)
                && plates.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1_000 }
        }
    }

    /// An inventory, rather than arbitrary rounding, defines which loads are achievable.
    /// Millionths of a pound make converted kilogram plates deterministic without losing
    /// practical precision. The inventory bounds keep subset enumeration finite.
    public var attainableLoads: [Double] {
        guard isValid else { return [] }
        let scale = 1_000_000.0
        switch kind {
        case .fixedWeights:
            return Set(availableWeights.map { Int64(($0 * scale).rounded()) }).sorted().map { Double($0) / scale }
        case .barbell:
            var sums: Set<Int64> = [Int64((barWeight * scale).rounded())]
            for plate in plates {
                let pair = Int64((2 * plate * scale).rounded())
                sums.formUnion(sums.map { $0 + pair }.filter { $0 <= 10_000 * Int64(scale) })
            }
            return sums.sorted().map { Double($0) / scale }
        }
    }

    /// Exact plate pairs for one side of the configured bar. Never borrows a plate
    /// from another inventory or substitutes a nearby load. The validated twelve-pair
    /// limit bounds the search; ties prefer larger plates and the fewest pairs.
    public func platePairs(for weight: Double) -> [Double]? {
        guard kind == .barbell, isValid, weight.isFinite, weight >= barWeight - 0.01 else { return nil }
        let inventory = plates.sorted(by: >)
        var best: [Double]?
        func search(_ index: Int, total: Double, selected: [Double]) {
            if abs(total - weight) < 0.01 {
                if selected.count < (best?.count ?? Int.max) { best = selected }
                return
            }
            guard index < inventory.count, total < weight + 0.01 else { return }
            if let best, selected.count >= best.count { return }
            search(index + 1, total: total + inventory[index] * 2, selected: selected + [inventory[index]])
            search(index + 1, total: total, selected: selected)
        }
        search(0, total: barWeight, selected: [])
        return best
    }

    public func contains(_ weight: Double) -> Bool {
        weight.isFinite && attainableLoads.contains { abs($0 - weight) < 0.01 }
    }

    public func next(after weight: Double) -> Double? {
        guard weight.isFinite else { return nil }
        return attainableLoads.first { $0 > weight + 0.01 }
    }

    public func previous(before weight: Double) -> Double? {
        guard weight.isFinite else { return nil }
        return attainableLoads.last { $0 < weight - 0.01 }
    }

    public func atOrBelow(_ weight: Double) -> Double? {
        guard weight.isFinite else { return nil }
        return attainableLoads.last { $0 <= weight + 0.01 }
    }

    public static func historyCompatible(current: StrengthEquipment?, previous: StrengthEquipment?) -> Bool {
        guard current?.isValid != false, previous?.isValid != false else { return false }
        let currentMeaning = current?.loadingMeaning ?? .asLogged
        let previousMeaning = previous?.loadingMeaning ?? .asLogged
        guard currentMeaning == previousMeaning else { return false }
        if current?.gymProfile != nil || previous?.gymProfile != nil {
            guard let currentProfile = current?.gymProfile, let previousProfile = previous?.gymProfile,
                  currentProfile.profileID == previousProfile.profileID,
                  currentProfile.implementID == previousProfile.implementID,
                  current?.kind == previous?.kind else { return false }
            return true
        }
        let currentName = current?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let previousName = previous?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard currentName == previousName else { return false }
        if let current, let previous, current.kind != previous.kind { return false }
        return true
    }
}
