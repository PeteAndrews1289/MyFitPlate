import Foundation

/// An affirmative save decision, not an inference from distance or a Health source.
/// Optional on Run so older accepted records remain readable without invented consent.
public enum RunSaveReview: String, Codable, Equatable, Sendable {
    case standard
    case shortRecording
}

public enum RunSaveReviewRules {
    public enum Requirement: Equatable { case empty, shortRecording, standard }
    public static let minimumActiveSeconds: Double = 1
    public static let shortActiveSeconds: Double = 60
    public static let shortDistanceMeters: Double = 50
    public static let automaticImportActiveSeconds: Double = 120
    public static let automaticImportDistanceMeters: Double = 100
    public static let healthReviewMetadataKey = "MyFitPlateRunSaveReviewV1"

    public static func requirement(activeSeconds: Double, distanceMeters: Double) -> Requirement {
        guard activeSeconds.isFinite, activeSeconds >= minimumActiveSeconds,
              distanceMeters.isFinite, distanceMeters >= 0 else { return .empty }
        return activeSeconds < shortActiveSeconds || distanceMeters < shortDistanceMeters ? .shortRecording : .standard
    }

    /// Shared by new local writes and Health export. Legacy positive recordings remain
    /// exportable; reading old records is intentionally a separate compatibility policy.
    public static func canSave(_ run: Run) -> Bool {
        let elapsed = run.endDate.timeIntervalSince(run.startDate)
        guard run.startDate.timeIntervalSinceReferenceDate.isFinite,
              run.endDate.timeIntervalSinceReferenceDate.isFinite, elapsed > 0,
              run.movingSeconds <= elapsed + 0.001,
              requirement(activeSeconds: run.movingSeconds, distanceMeters: run.distanceMeters) != .empty else { return false }
        return true
    }

    /// Automatic third-party import lacks our explicit review, so its conservative
    /// false-start filter remains distinct from a person's deliberate recorder save.
    public static func canAutomaticallyImport(activeSeconds: Double, distanceMeters: Double) -> Bool {
        requirement(activeSeconds: activeSeconds, distanceMeters: distanceMeters) != .empty
            && (activeSeconds >= automaticImportActiveSeconds || distanceMeters >= automaticImportDistanceMeters)
    }
}

/// Frozen before a reviewed finish enters local/Health saving. Recovery retries this
/// same value, including the original end date, rather than finishing the timer again.
public struct RunRecordingCompletion: Codable, Equatable {
    public let run: Run
    public let weightLbs: Double
    public init(run: Run, weightLbs: Double) { self.run = run; self.weightLbs = weightLbs }
}
