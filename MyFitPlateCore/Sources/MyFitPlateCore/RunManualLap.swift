import Foundation

/// A deliberate boundary in the accepted cumulative clock/distance. Manual laps
/// never advance a prescribed step or replace automatic kilometer/mile splits.
public struct RunManualLap: Codable, Equatable, Identifiable {
    public let id: String
    public let recordingID: String
    public let index: Int
    public let timestamp: Date
    public let activeElapsedSeconds: Double
    public let distanceMeters: Double

    public init(id: String, recordingID: String, index: Int, timestamp: Date, activeElapsedSeconds: Double, distanceMeters: Double) {
        self.id = id; self.recordingID = recordingID; self.index = index; self.timestamp = timestamp
        self.activeElapsedSeconds = activeElapsedSeconds; self.distanceMeters = distanceMeters
    }

    public static func valid(_ laps: [Self], recordingID: String, start: Date, end: Date,
                             activeSeconds: Double, distanceMeters: Double) -> Bool {
        guard laps.count <= 1_000, Set(laps.map(\.id)).count == laps.count else { return false }
        var previousTime = 0.0, previousMeters = 0.0
        var previousDate = start
        for (index, lap) in laps.enumerated() {
            guard !lap.id.isEmpty, lap.recordingID == recordingID, lap.index == index + 1,
                  lap.timestamp.timeIntervalSinceReferenceDate.isFinite,
                  lap.timestamp >= previousDate, lap.timestamp <= end,
                  lap.activeElapsedSeconds.isFinite, lap.activeElapsedSeconds > previousTime,
                  lap.activeElapsedSeconds <= activeSeconds + 0.001,
                  lap.activeElapsedSeconds <= lap.timestamp.timeIntervalSince(start) + 0.001,
                  lap.distanceMeters.isFinite, lap.distanceMeters >= previousMeters,
                  lap.distanceMeters <= distanceMeters + 0.01 else { return false }
            previousTime = lap.activeElapsedSeconds; previousMeters = lap.distanceMeters; previousDate = lap.timestamp
        }
        return true
    }
}
