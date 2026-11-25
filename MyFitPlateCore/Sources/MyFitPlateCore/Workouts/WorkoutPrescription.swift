import Foundation

/// A target is separate from the values actually performed. Historical target text is
/// retained when it cannot be interpreted without guessing.
public struct WorkoutPrescription: Codable, Equatable, Sendable {
    public struct LoadReference: Codable, Equatable, Sendable {
        public var label: String
        public var weightPounds: Double
        public var date: Date

        public init(label: String, weightPounds: Double, date: Date) {
            self.label = label; self.weightPounds = weightPounds; self.date = date
        }
    }
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case repetitions, duration, distance, amrap, manual
    }

    public var schemaVersion: Int
    public var kind: Kind
    /// Repetitions, seconds, or metres according to `kind`.
    public var lowerBound: Double?
    public var upperBound: Double?
    public var effort: SetEffort?
    public var notes: String?
    public var originalText: String?
    public var loadPercentage: Double?
    public var loadReference: LoadReference?

    public init(kind: Kind, lowerBound: Double? = nil, upperBound: Double? = nil,
                effort: SetEffort? = nil, notes: String? = nil, originalText: String? = nil,
                loadPercentage: Double? = nil, loadReference: LoadReference? = nil) {
        schemaVersion = 1
        self.kind = kind
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.effort = effort
        self.notes = notes
        self.originalText = originalText
        self.loadPercentage = loadPercentage
        self.loadReference = loadReference
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, lowerBound, upperBound, effort, notes, originalText, loadPercentage, loadReference
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else { throw WorkoutBlockError.unsupported }
        kind = try values.decode(Kind.self, forKey: .kind)
        lowerBound = try values.decodeIfPresent(Double.self, forKey: .lowerBound)
        upperBound = try values.decodeIfPresent(Double.self, forKey: .upperBound)
        effort = try values.decodeIfPresent(SetEffort.self, forKey: .effort)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        originalText = try values.decodeIfPresent(String.self, forKey: .originalText)
        loadPercentage = try values.decodeIfPresent(Double.self, forKey: .loadPercentage)
        loadReference = try values.decodeIfPresent(LoadReference.self, forKey: .loadReference)
    }

    public var validationMessage: String? {
        guard schemaVersion == 1 else { return "This target needs a newer app version." }
        if (notes?.count ?? 0) > 2_000 || (originalText?.count ?? 0) > 2_000 {
            return "Keep target notes within 2,000 characters."
        }
        if loadPercentage != nil || loadReference != nil {
            guard kind == .repetitions || kind == .amrap,
                  let percentage = loadPercentage, percentage.isFinite, (1...200).contains(percentage),
                  let reference = loadReference, reference.weightPounds.isFinite, reference.weightPounds > 0,
                  reference.weightPounds <= 5_000, !reference.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reference.label.count <= 200,
                  reference.date.timeIntervalSinceReferenceDate.isFinite else {
                return "A percentage needs a named reference, its weight and date. Use 1–200%."
            }
        }
        if let effort, !effort.value.isFinite || !(effort.scale == .rpe ? 1...10 : 0...10).contains(effort.value) {
            return "Choose RPE from 1 to 10 or RIR from 0 to 10."
        }
        if kind == .manual {
            return originalText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? nil : "Keep a written target for this prescription."
        }
        if kind == .amrap { return nil }
        guard let low = lowerBound, low.isFinite, low > 0 else { return "Enter a positive target." }
        let high = upperBound ?? low
        guard high.isFinite, high >= low else { return "The upper target must be at least the lower target." }
        if kind == .repetitions, low.rounded() != low || high.rounded() != high || high > 1_000 {
            return "Use whole repetitions from 1 to 1,000."
        }
        if kind == .duration, low.rounded() != low || high.rounded() != high || high > 86_400 {
            return "Use whole seconds, up to 24 hours."
        }
        if kind == .distance, high > 1_000_000 { return "Distance must be at most 1,000 km." }
        return nil
    }

    public var targetText: String {
        switch kind {
        case .manual: return originalText ?? "Written target"
        case .amrap: return "AMRAP"
        case .repetitions: return rangeText + " reps"
        case .duration: return rangeText + " sec"
        case .distance: return rangeText + " m"
        }
    }

    public var summary: String {
        var core = targetText
        if let percentage = loadPercentage, let reference = loadReference {
            core += " · " + Self.number(percentage) + "% of " + reference.label
        }
        guard let effort else { return core }
        return core + " · " + (effort.scale == .rpe ? "RPE " : "RIR ") + Self.number(effort.value)
    }

    public var resolvedWeightPounds: Double? {
        guard validationMessage == nil, let loadPercentage, let loadReference else { return nil }
        return loadReference.weightPounds * loadPercentage / 100
    }

    public func isSupported(for type: ExerciseType) -> Bool {
        switch kind {
        case .manual: true
        case .repetitions, .amrap: type == .strength
        case .duration: type == .cardio || type == .flexibility
        case .distance: type == .cardio
        }
    }

    /// Applies only to a fresh logger copy, never to a recovered or completed set.
    public func seedingEmptyValues(in set: ExerciseSet, type: ExerciseType) -> ExerciseSet {
        guard !set.isCompleted, validationMessage == nil, isSupported(for: type) else { return set }
        var result = set
        if type == .strength {
            if kind == .repetitions, result.reps == 0, let lowerBound { result.reps = Int(lowerBound) }
            if result.weight == 0, let weight = resolvedWeightPounds { result.weight = weight }
        } else {
            if kind == .duration, result.durationInSeconds == 0, let lowerBound { result.durationInSeconds = Int(lowerBound.rounded()) }
            if type == .cardio, kind == .distance, result.distance == 0, let lowerBound { result.distance = lowerBound / 1_609.344 }
        }
        return result
    }

    private var rangeText: String {
        guard let low = lowerBound else { return "—" }
        guard let high = upperBound, high != low else { return Self.number(low) }
        return Self.number(low) + "–" + Self.number(high)
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Strictly recognizes only supported unqualified legacy targets. Percentage,
    /// tempo and RPE-bearing text remain visible manual prescriptions.
    public static func legacy(_ text: String?, type: ExerciseType) -> WorkoutPrescription? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased() == "AMRAP" { return WorkoutPrescription(kind: .amrap, originalText: text) }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "–", with: "-")
        let pattern = #"^(\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?))?\s*(reps?|sec(?:onds?)?|s|min(?:utes?)?|km|m)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let lowRange = Range(match.range(at: 1), in: normalized), let low = Double(normalized[lowRange]) else {
            return WorkoutPrescription(kind: .manual, originalText: text)
        }
        let high = Range(match.range(at: 2), in: normalized).flatMap { Double(normalized[$0]) }
        let unit = Range(match.range(at: 3), in: normalized).map { String(normalized[$0]) } ?? ""
        let kind: Kind
        let multiplier: Double
        switch unit {
        case "m": kind = .distance; multiplier = 1
        case "km": kind = .distance; multiplier = 1_000
        case "s", "sec", "secs", "second", "seconds": kind = .duration; multiplier = 1
        case "min", "mins", "minute", "minutes": kind = .duration; multiplier = 60
        case "rep", "reps": kind = .repetitions; multiplier = 1
        default:
            guard type == .strength else { return WorkoutPrescription(kind: .manual, originalText: text) }
            kind = .repetitions; multiplier = 1
        }
        let target = WorkoutPrescription(kind: kind, lowerBound: low * multiplier,
                                         upperBound: high.map { $0 * multiplier }, originalText: text)
        return target.validationMessage == nil && target.isSupported(for: type)
            ? target : WorkoutPrescription(kind: .manual, originalText: text)
    }
}
