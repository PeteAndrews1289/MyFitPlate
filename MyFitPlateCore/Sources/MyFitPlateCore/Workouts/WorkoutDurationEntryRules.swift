import Foundation

public enum WorkoutDurationEntryRules {
    /// The measured clock supports at most 24 hours. Invalid typed prescriptions
    /// remain untargeted rather than being replaced by potentially stale legacy text.
    public static func intervalTargetSeconds(prescription: WorkoutPrescription?, legacyTarget: String?,
                                             bareNumberIsSeconds: Bool = false) -> Int? {
        if let prescription, prescription.kind == .duration {
            guard prescription.validationMessage == nil, let seconds = prescription.lowerBound else { return nil }
            return Int(seconds)
        }
        guard let seconds = targetSeconds(legacyTarget, bareNumberIsSeconds: bareNumberIsSeconds),
              (1...86_400).contains(seconds) else { return nil }
        return seconds
    }

    public static func seconds(fromMinutes input: String) -> Int? {
        guard let minutes = StrengthSetEntryRules.weight(from: input), minutes > 0,
              minutes < Double(Int.max / 60) else { return nil }
        return Int((minutes * 60).rounded())
    }

    public static func targetSeconds(_ target: String?, bareNumberIsSeconds: Bool = false) -> Int? {
        guard let target else { return nil }
        let pattern = #"(\d+(?:[.,]\d+)?)(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?\s*(seconds?|secs?|s|minutes?|mins?|hours?|hrs?|h)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: target, range: NSRange(target.startIndex..., in: target)),
              let amountRange = Range(match.range(at: 1), in: target),
              let unitRange = Range(match.range(at: 2), in: target),
              let amount = Double(target[amountRange].replacingOccurrences(of: ",", with: ".")) else {
            return bareNumberIsSeconds ? StrengthSetEntryRules.reps(from: target) : nil
        }
        let unit = target[unitRange].lowercased()
        let multiplier = unit.hasPrefix("h") ? 3600.0 : unit.hasPrefix("min") ? 60.0 : 1.0
        let seconds = amount * multiplier
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return nil }
        return Int(seconds.rounded())
    }
}
