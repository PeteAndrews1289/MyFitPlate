import Foundation

public protocol RunningShoeStoreProtocol: AnyObject {
    var shoes: [RunningShoe] { get }
    func addShoe(_ shoe: RunningShoe)
    func updateShoe(_ shoe: RunningShoe)
    func retireShoe(id: String)
    func setDefaultShoe(id: String)
    func defaultShoe() -> RunningShoe?
    func shoe(for id: String) -> RunningShoe?
    func totalMeters(for shoeID: String, across runs: [Run]) -> Double
    func wearPercentage(for shoeID: String, across runs: [Run]) -> Double
    func isWornOut(shoeID: String, across runs: [Run]) -> Bool
    func shoeID(forRunID runID: String) -> String?
    func tagRun(runID: String, withShoeID shoeID: String?)
    func applyTags(to runs: [Run]) -> [Run]
    func averagePaceSecondsPerKm(for shoeID: String, across runs: [Run]) -> Double?
    func runCount(for shoeID: String, across runs: [Run]) -> Int
    func longestRunDistance(for shoeID: String, across runs: [Run]) -> Double?
    func fastestShoeID(across runs: [Run]) -> String?
}

public final class RunningShoeStore: ObservableObject, RunningShoeStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey = "myfitplate.running_shoes"
    private let tagStorageKey = "myfitplate.running_shoe_tags"

    @Published public private(set) var shoes: [RunningShoe] = [] {
        didSet {
            saveToDefaults()
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadFromDefaults()
        if shoes.isEmpty {
            // Seed a default standard shoe if none exist
            let initialShoe = RunningShoe(name: "Road Trainer", brand: "Default", isDefault: true)
            shoes = [initialShoe]
        }
    }

    private func loadFromDefaults() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RunningShoe].self, from: data) else {
            return
        }
        self.shoes = decoded
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(shoes) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    public func addShoe(_ shoe: RunningShoe) {
        var newShoe = shoe
        if shoes.isEmpty {
            newShoe.isDefault = true
        } else if newShoe.isDefault {
            // Unset previous default
            for i in 0..<shoes.count {
                shoes[i].isDefault = false
            }
        }
        shoes.append(newShoe)
    }

    public func updateShoe(_ shoe: RunningShoe) {
        guard let index = shoes.firstIndex(where: { $0.id == shoe.id }) else { return }
        let updated = shoe
        if updated.isDefault {
            for i in 0..<shoes.count where i != index {
                shoes[i].isDefault = false
            }
        }
        shoes[index] = updated
    }

    public func retireShoe(id: String) {
        guard let index = shoes.firstIndex(where: { $0.id == id }) else { return }
        shoes[index].isRetired = true
        if shoes[index].isDefault {
            shoes[index].isDefault = false
            // Find another non-retired shoe to make default
            if let nextIndex = shoes.firstIndex(where: { !$0.isRetired && $0.id != id }) {
                shoes[nextIndex].isDefault = true
            }
        }
    }

    public func setDefaultShoe(id: String) {
        for i in 0..<shoes.count {
            shoes[i].isDefault = (shoes[i].id == id)
        }
    }

    public func defaultShoe() -> RunningShoe? {
        shoes.first(where: { $0.isDefault && !$0.isRetired }) ?? shoes.first(where: { !$0.isRetired }) ?? shoes.first
    }

    public func shoe(for id: String) -> RunningShoe? {
        shoes.first(where: { $0.id == id })
    }

    public func totalMeters(for shoeID: String, across runs: [Run]) -> Double {
        guard let shoe = shoe(for: shoeID) else { return 0 }
        let runMeters = runs
            .filter { $0.shoeID == shoeID }
            .reduce(0.0) { $0 + $1.distanceMeters }
        return shoe.initialMeters + runMeters
    }

    public func wearPercentage(for shoeID: String, across runs: [Run]) -> Double {
        guard let shoe = shoe(for: shoeID) else { return 0 }
        let meters = totalMeters(for: shoeID, across: runs)
        return shoe.wearPercentage(totalMeters: meters)
    }

    public func isWornOut(shoeID: String, across runs: [Run]) -> Bool {
        guard let shoe = shoe(for: shoeID) else { return false }
        let meters = totalMeters(for: shoeID, across: runs)
        return shoe.isWornOut(totalMeters: meters)
    }

    public func shoeID(forRunID runID: String) -> String? {
        guard let data = userDefaults.data(forKey: tagStorageKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return map[runID]
    }

    public func tagRun(runID: String, withShoeID shoeID: String?) {
        var map: [String: String] = [:]
        if let data = userDefaults.data(forKey: tagStorageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
        if let shoeID = shoeID {
            map[runID] = shoeID
        } else {
            map.removeValue(forKey: runID)
        }
        if let encoded = try? JSONEncoder().encode(map) {
            userDefaults.set(encoded, forKey: tagStorageKey)
        }
    }

    public func applyTags(to runs: [Run]) -> [Run] {
        var map: [String: String] = [:]
        if let data = userDefaults.data(forKey: tagStorageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
        // EXPLICIT tags only. Falling back to the current default shoe here meant
        // switching your default silently migrated the whole run history's mileage onto
        // the new shoe. The default is a picker convenience, stamped onto NEW recordings
        // at save time — never onto history.
        return runs.map { run in
            var r = run
            if let tagged = map[run.id] {
                r.shoeID = tagged
            }
            return r
        }
    }

    public func averagePaceSecondsPerKm(for shoeID: String, across runs: [Run]) -> Double? {
        let shoeRuns = runs.filter { $0.shoeID == shoeID && $0.distanceMeters >= 500 && $0.movingSeconds > 0 }
        guard !shoeRuns.isEmpty else { return nil }
        let totalDist = shoeRuns.reduce(0.0) { $0 + $1.distanceMeters }
        let totalSec = shoeRuns.reduce(0.0) { $0 + $1.movingSeconds }
        guard totalDist > 0 else { return nil }
        return totalSec / (totalDist / 1000.0)
    }

    public func runCount(for shoeID: String, across runs: [Run]) -> Int {
        runs.filter { $0.shoeID == shoeID }.count
    }

    public func longestRunDistance(for shoeID: String, across runs: [Run]) -> Double? {
        let shoeRuns = runs.filter { $0.shoeID == shoeID }
        return shoeRuns.map { $0.distanceMeters }.max()
    }

    public func fastestShoeID(across runs: [Run]) -> String? {
        let validShoes = shoes.filter { !$0.isRetired }
        let withPaces = validShoes.compactMap { shoe -> (String, Double)? in
            guard let pace = averagePaceSecondsPerKm(for: shoe.id, across: runs) else { return nil }
            return (shoe.id, pace)
        }
        return withPaces.min(by: { $0.1 < $1.1 })?.0
    }
}
