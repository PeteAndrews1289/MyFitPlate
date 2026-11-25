import Foundation

/// A performed hold/interval clock, independent from rest and the whole-workout clock.
public struct WorkoutIntervalTimerState: Codable, Equatable, Sendable {
    public var version: Int
    public var id: String
    public var setID: String
    public var targetSeconds: Int?
    public var accumulatedSeconds: Double
    public var runningSince: Date?
    public var completedAt: Date?
    public init(setID: String, targetSeconds: Int? = nil) {
        version = 1; id = UUID().uuidString; self.setID = setID; self.targetSeconds = targetSeconds; accumulatedSeconds = 0
    }
    public var isValid: Bool {
        version == 1 && !id.isEmpty && !setID.isEmpty && accumulatedSeconds.isFinite && (0...86_400).contains(accumulatedSeconds)
            && (targetSeconds.map { (1...86_400).contains($0) } ?? true)
            && (runningSince?.timeIntervalSinceReferenceDate.isFinite ?? true)
            && (completedAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
            && !(runningSince != nil && completedAt != nil)
    }
    public func elapsed(at now: Date = Date()) -> Double {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite else { return 0 }
        return min(86_400, accumulatedSeconds + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0))
    }
    public mutating func start(at now: Date = Date()) throws {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite, completedAt == nil else { throw WorkoutBlockError.invalid }
        if runningSince == nil { runningSince = now }
    }
    public mutating func pause(at now: Date = Date()) throws {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite, completedAt == nil else { throw WorkoutBlockError.invalid }
        accumulatedSeconds = elapsed(at: now); runningSince = nil
    }
    @discardableResult public mutating func complete(at now: Date = Date()) throws -> Int {
        guard isValid, now.timeIntervalSinceReferenceDate.isFinite else { throw WorkoutBlockError.invalid }
        let value = elapsed(at: now)
        guard value >= 0.5 else { throw WorkoutBlockError.invalid }
        if completedAt == nil {
            accumulatedSeconds = value; runningSince = nil; completedAt = now
        }
        return Int(accumulatedSeconds.rounded())
    }
}
