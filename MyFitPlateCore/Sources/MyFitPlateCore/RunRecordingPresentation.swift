import Foundation

/// A GPS fix is useful only while it is both accurate and recent. Signal loss never
/// pauses the recording clock or turns an old pace into a current measurement.
public enum RunGPSSignal: Equatable {
    case acquiring
    case ready
    case weak
    case lost

    public static func evaluate(fix: RunLocationFix?, at date: Date, hasError: Bool = false) -> Self {
        guard let fix else { return hasError ? .lost : .acquiring }
        let age = date.timeIntervalSince(fix.timestamp)
        guard age.isFinite, age >= -2, age <= 20 else { return .lost }
        guard fix.latitude.isFinite, (-90...90).contains(fix.latitude),
              fix.longitude.isFinite, (-180...180).contains(fix.longitude),
              fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0 else { return .weak }
        return fix.horizontalAccuracy <= RunSession.accuracyCutoffMeters ? .ready : .weak
    }

    public var title: String {
        switch self {
        case .acquiring: return "Finding GPS"
        case .ready: return "GPS ready"
        case .weak: return "Weak GPS"
        case .lost: return "GPS signal lost"
        }
    }

    public var detail: String {
        switch self {
        case .acquiring: return "Head outside with a clear view of the sky for a reliable route."
        case .ready: return "Ready to record your route, distance, and pace."
        case .weak: return "Distance and pace may be less accurate. Move away from buildings or cover."
        case .lost: return "Your timer continues. Distance and live pace need a fresh GPS signal."
        }
    }
}

/// Visual target feedback uses the current step and a fresh rolling pace. A warm-up
/// period prevents a tiny amount of GPS movement from issuing premature advice.
public enum RunPaceGuidance: Equatable {
    case settling
    case onTarget
    case fasterThanTarget
    case slowerThanTarget

    public static func evaluate(
        target: RunWorkoutTarget?, paceSecondsPerKm: Double?,
        stepElapsedSeconds: Double, stepDistanceMeters: Double
    ) -> Self? {
        guard let fastest = target?.fastestSecondsPerKm,
              let slowest = target?.slowestSecondsPerKm,
              fastest.isFinite, slowest.isFinite, fastest > 0, slowest >= fastest else { return nil }
        guard stepElapsedSeconds.isFinite, stepDistanceMeters.isFinite,
              stepElapsedSeconds >= 20, stepDistanceMeters >= 25,
              let pace = paceSecondsPerKm, pace.isFinite, pace > 0 else { return .settling }
        if pace < fastest { return .fasterThanTarget }
        if pace > slowest { return .slowerThanTarget }
        return .onTarget
    }

    public var title: String {
        switch self {
        case .settling: return "Settling into pace"
        case .onTarget: return "Within target pace"
        case .fasterThanTarget: return "Faster than target"
        case .slowerThanTarget: return "Slower than target"
        }
    }
}
