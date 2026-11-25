import Foundation

public enum StrengthSetEntryRules {
    public struct ReviewedEntry: Equatable, Sendable {
        public let weightText: String
        public let repsText: String
        public let displayedWeight: Double
        public let reps: Int
    }

    public enum EntryError: Error, Equatable, Sendable {
        case weight
        case reps
    }

    /// Fallbacks are only for untouched, unseeded rows. An editor passes nil after
    /// the person has changed a field, so clearing it cannot silently log history.
    public static func review(
        weightInput: String,
        repsInput: String,
        fallbackWeight: String? = nil,
        fallbackReps: Int? = nil,
        locale: Locale = .current
    ) throws -> ReviewedEntry {
        let weightText = weightInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackWeight ?? weightInput : weightInput
        let repsText = repsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackReps.map(String.init) ?? repsInput : repsInput
        guard let displayedWeight = weight(from: weightText, locale: locale) else { throw EntryError.weight }
        guard let reps = reps(from: repsText) else { throw EntryError.reps }
        return ReviewedEntry(weightText: weightText, repsText: repsText, displayedWeight: displayedWeight, reps: reps)
    }

    /// Late history may seed an untouched field, but never interrupt typing or
    /// repopulate an intentionally cleared value.
    public static func canSeedFromHistory(input: String, wasEdited: Bool, isFocused: Bool) -> Bool {
        input.isEmpty && !wasEdited && !isFocused
    }

    public static func weight(from input: String, locale: Locale = .current) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        guard !normalized.isEmpty, normalized.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    public static func reps(from input: String) -> Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
    }
}
