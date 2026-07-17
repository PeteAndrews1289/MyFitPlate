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
    private let authService: AuthServiceProtocol
    private let legacyStorageKey = "myfitplate.running_shoes"
    private let legacyTagStorageKey = "myfitplate.running_shoe_tags"
    private var activeUserID: String?
    private var isRestoring = false

    @Published private var storedShoes: [RunningShoe] = [] {
        didSet {
            if !isRestoring { saveToDefaults() }
        }
    }

    public var shoes: [RunningShoe] {
        synchronizeAccountIfNeeded()
        return storedShoes
    }

    public init(userDefaults: UserDefaults, authService: AuthServiceProtocol) {
        self.userDefaults = userDefaults
        self.authService = authService
        activeUserID = authService.currentUserID
        loadFromDefaults()
        seedDefaultShoeIfNeeded()
    }

    @MainActor
    public convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, authService: DIContainer.shared.authService)
    }

    private func loadFromDefaults() {
        isRestoring = true
        defer { isRestoring = false }
        storedShoes = []
        guard let storageKey else { return }
        migrateLegacyStorageIfNeeded()
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RunningShoe].self, from: data) else {
            return
        }
        storedShoes = decoded
    }

    private func saveToDefaults() {
        guard let storageKey,
              let data = try? JSONEncoder().encode(storedShoes) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    public func addShoe(_ shoe: RunningShoe) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil else { return }
        var newShoe = shoe
        if storedShoes.isEmpty {
            newShoe.isDefault = true
        } else if newShoe.isDefault {
            // Unset previous default
            for i in 0..<storedShoes.count {
                storedShoes[i].isDefault = false
            }
        }
        storedShoes.append(newShoe)
    }

    public func updateShoe(_ shoe: RunningShoe) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil,
              let index = storedShoes.firstIndex(where: { $0.id == shoe.id }) else { return }
        let updated = shoe
        if updated.isDefault {
            for i in 0..<storedShoes.count where i != index {
                storedShoes[i].isDefault = false
            }
        }
        storedShoes[index] = updated
    }

    public func retireShoe(id: String) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil,
              let index = storedShoes.firstIndex(where: { $0.id == id }) else { return }
        storedShoes[index].isRetired = true
        if storedShoes[index].isDefault {
            storedShoes[index].isDefault = false
            // Find another non-retired shoe to make default
            if let nextIndex = storedShoes.firstIndex(where: { !$0.isRetired && $0.id != id }) {
                storedShoes[nextIndex].isDefault = true
            }
        }
    }

    public func setDefaultShoe(id: String) {
        synchronizeAccountIfNeeded()
        guard activeUserID != nil else { return }
        for i in 0..<storedShoes.count {
            storedShoes[i].isDefault = (storedShoes[i].id == id)
        }
    }

    public func defaultShoe() -> RunningShoe? {
        synchronizeAccountIfNeeded()
        return storedShoes.first(where: { $0.isDefault && !$0.isRetired })
            ?? storedShoes.first(where: { !$0.isRetired })
            ?? storedShoes.first
    }

    public func shoe(for id: String) -> RunningShoe? {
        synchronizeAccountIfNeeded()
        return storedShoes.first(where: { $0.id == id })
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
        synchronizeAccountIfNeeded()
        guard let tagStorageKey else { return nil }
        guard let data = userDefaults.data(forKey: tagStorageKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return map[runID]
    }

    public func tagRun(runID: String, withShoeID shoeID: String?) {
        synchronizeAccountIfNeeded()
        guard let tagStorageKey else { return }
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
        if map.isEmpty {
            userDefaults.removeObject(forKey: tagStorageKey)
        } else if let encoded = try? JSONEncoder().encode(map) {
            userDefaults.set(encoded, forKey: tagStorageKey)
        }
    }

    public func applyTags(to runs: [Run]) -> [Run] {
        synchronizeAccountIfNeeded()
        guard let tagStorageKey else { return runs }
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
        synchronizeAccountIfNeeded()
        let validShoes = storedShoes.filter { !$0.isRetired }
        let withPaces = validShoes.compactMap { shoe -> (String, Double)? in
            guard let pace = averagePaceSecondsPerKm(for: shoe.id, across: runs) else { return nil }
            return (shoe.id, pace)
        }
        return withPaces.min(by: { $0.1 < $1.1 })?.0
    }

    private var storageKey: String? {
        AccountScopedStorageKey.make(prefix: legacyStorageKey, userID: activeUserID)
    }

    private var tagStorageKey: String? {
        AccountScopedStorageKey.make(prefix: legacyTagStorageKey, userID: activeUserID)
    }

    private func synchronizeAccountIfNeeded() {
        let currentUserID = authService.currentUserID
        guard currentUserID != activeUserID else { return }
        activeUserID = currentUserID
        loadFromDefaults()
        seedDefaultShoeIfNeeded()
    }

    private func seedDefaultShoeIfNeeded() {
        guard activeUserID != nil, storedShoes.isEmpty else { return }
        storedShoes = [RunningShoe(name: "Road Trainer", brand: "Default", isDefault: true)]
    }

    private func migrateLegacyStorageIfNeeded() {
        guard let storageKey, let tagStorageKey else { return }
        if userDefaults.data(forKey: storageKey) == nil,
           let legacyData = userDefaults.data(forKey: legacyStorageKey) {
            userDefaults.set(legacyData, forKey: storageKey)
        }
        if userDefaults.data(forKey: tagStorageKey) == nil,
           let legacyTagData = userDefaults.data(forKey: legacyTagStorageKey) {
            userDefaults.set(legacyTagData, forKey: tagStorageKey)
        }
        userDefaults.removeObject(forKey: legacyStorageKey)
        userDefaults.removeObject(forKey: legacyTagStorageKey)
    }
}
