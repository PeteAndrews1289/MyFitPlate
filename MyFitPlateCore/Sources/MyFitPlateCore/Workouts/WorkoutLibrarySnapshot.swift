import Foundation

/// A library can be useful without being complete. Unreadable records remain explicit so
/// neither an offline cache nor a single incompatible plan can silently change selection.
public struct WorkoutLibrarySnapshot<Value: Codable>: Codable {
    public var values: [Value]
    public var unreadableIDs: Set<String>
    public var isFromCache: Bool
    public var cacheWriteFailed: Bool

    public init(values: [Value], unreadableIDs: Set<String> = [], isFromCache: Bool = false, cacheWriteFailed: Bool = false) {
        self.values = values
        self.unreadableIDs = unreadableIDs
        self.isFromCache = isFromCache
        self.cacheWriteFailed = cacheWriteFailed
    }

    private enum CodingKeys: String, CodingKey { case values, unreadableIDs, isFromCache, cacheWriteFailed }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
        try container.encode(unreadableIDs.sorted(), forKey: .unreadableIDs)
        try container.encode(isFromCache, forKey: .isFromCache)
        try container.encode(cacheWriteFailed, forKey: .cacheWriteFailed)
    }

    public func retainingLastGood(_ previous: [Value], id: (Value) -> String?) -> Self {
        var result = self
        let incomingIDs = Set(values.compactMap(id))
        result.values += previous.filter {
            guard let key = id($0), !incomingIDs.contains(key) else { return false }
            return isFromCache || unreadableIDs.contains(key)
        }
        return result
    }

    public func notice(noun: String) -> String? {
        if !unreadableIDs.isEmpty {
            return "Some \(noun) couldn't be read. Available plans and last saved copies are shown. Your selection has been kept."
        }
        if cacheWriteFailed { return "Your \(noun) loaded, but couldn't be backed up on this device. Try refreshing." }
        if isFromCache { return "Showing saved \(noun) while checking for updates." }
        return nil
    }
}
