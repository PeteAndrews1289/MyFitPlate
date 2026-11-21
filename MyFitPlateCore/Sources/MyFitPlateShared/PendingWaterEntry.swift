import Foundation

public struct PendingWaterEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let accountScope: String
    public let ounces: Double
    public let capturedAt: Date

    public init(id: UUID = UUID(), accountScope: String, ounces: Double, capturedAt: Date = Date()) {
        self.id = id
        self.accountScope = accountScope
        self.ounces = ounces
        self.capturedAt = capturedAt
    }
}

/// One atomic file per receipt avoids lost read-modify-write updates between the widget and app.
public struct WaterEntryInbox: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func enqueue(_ entry: PendingWaterEntry) throws {
        guard !entry.accountScope.isEmpty, entry.ounces.isFinite, entry.ounces > 0,
              entry.capturedAt.timeIntervalSince1970.isFinite else { throw CocoaError(.coderInvalidValue) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: path(entry), options: .atomic)
    }

    public func pending(accountScope: String) throws -> [PendingWaterEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(PendingWaterEntry.self, from: Data(contentsOf: $0)) }
            .filter { $0.accountScope == accountScope }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    public func acknowledge(_ entry: PendingWaterEntry) throws {
        let file = path(entry)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    public func removeAll(accountScope: String) throws {
        for entry in try pending(accountScope: accountScope) { try acknowledge(entry) }
    }

    private func path(_ entry: PendingWaterEntry) -> URL {
        directory.appendingPathComponent(entry.id.uuidString).appendingPathExtension("json")
    }
}
